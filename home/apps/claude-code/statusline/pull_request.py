"""The pull request for the checked-out branch, found through gh without ever making a render wait.

`gh pr view` goes over the network and takes about half a second, against a line that renders in about
thirty milliseconds, so a render only reads a small cache file. When that file is missing or older than
CACHE_SECONDS, the render starts a detached refresh and shows whatever the file held, if anything; the
refresh's answer appears on a later render. The scheme follows ccstatusline's GitPr widget.

Each repository and branch pair gets its own file, holding {"number": ..., "url": ...}, or null for a
branch without a pull request. A null is cached like any other answer, which keeps a branch that never
gets one, such as trunk, to one lookup per CACHE_SECONDS rather than one per render.

Run as a script, this module is that detached refresh.
"""

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

# How long an answer stands before a render asks again, and so roughly how long a newly opened pull
# request takes to appear.
CACHE_SECONDS = 60

LOOKUP_TIMEOUT_SECONDS = 10

# A refresh removes its lock when it finishes, so a lock that outlives the lookup timeout belongs to a
# refresh that died, and the next render may take it over.
LOCK_STALE_SECONDS = 30

# What gh prints when the branch has no pull request, as opposed to failing to find out.
NO_PULL_REQUEST = "no pull requests found"

LOOKUP_FAILED = object()


def cache_directory_from(environment):
    """Where the answers live. Inside the bubble ~/.cache is a tmpfs of the session's own."""
    base = environment.get("XDG_CACHE_HOME") or Path.home() / ".cache"
    return Path(base) / "claude-code-statusline"


def cache_path(directory, repository_url, branch):
    """The file holding the answer for `branch` of the repository at `repository_url`."""
    digest = hashlib.sha256(f"{repository_url}\0{branch}".encode()).hexdigest()[:16]
    return directory / f"pull-request-{digest}.json"


def _lock_path(path):
    return path.with_name(f"{path.name}.lock")


def _valid(stored):
    """The pull request in `stored` when it has what the segment shows, else None."""
    if (
        isinstance(stored, dict)
        and isinstance(stored.get("number"), int)
        and isinstance(stored.get("url"), str)
    ):
        return {"number": stored["number"], "url": stored["url"]}
    return None


def read(path, now_epoch):
    """The cached pull request or None, and whether it is time to ask gh again.

    A missing or unreadable file has nothing to show and is due at once.
    """
    try:
        age_seconds = now_epoch - path.stat().st_mtime
        stored = json.loads(path.read_text())
    except (OSError, ValueError):
        return None, True
    return _valid(stored), age_seconds >= CACHE_SECONDS


def write(path, pull_request):
    """Store an answer, renaming it into place so a render never reads half a file."""
    scratch_path = path.with_name(f"{path.name}.{os.getpid()}")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        scratch_path.write_text(json.dumps(pull_request, separators=(",", ":")))
        os.replace(scratch_path, path)
    except OSError:
        try:
            scratch_path.unlink(missing_ok=True)
        except OSError:
            pass


def lookup(directory, branch):
    """What gh knows about `branch`: its pull request, None when it has none, or LOOKUP_FAILED.

    The branch goes after `--` so a branch named like a flag stays an argument, and is named rather than
    left for gh to infer so the answer always belongs to the branch the cache file is keyed on.
    """
    try:
        finished = subprocess.run(
            ("gh", "pr", "view", "--json", "number,url", "--", branch),
            cwd=directory,
            capture_output=True,
            text=True,
            timeout=LOOKUP_TIMEOUT_SECONDS,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return LOOKUP_FAILED
    if finished.returncode != 0:
        return None if NO_PULL_REQUEST in finished.stderr else LOOKUP_FAILED
    try:
        return _valid(json.loads(finished.stdout))
    except ValueError:
        return LOOKUP_FAILED


def refresh(directory, repository_url, branch, cache_directory):
    """Ask gh about `branch` and store the answer, then release the lock the render took."""
    path = cache_path(cache_directory, repository_url, branch)
    try:
        found = lookup(directory, branch)
        if found is not LOOKUP_FAILED:
            write(path, found)
        else:
            # Keep the last answer and wait a full period before asking again, rather than starting a
            # doomed lookup on every render while offline.
            try:
                os.utime(path)
            except FileNotFoundError:
                write(path, None)
            except OSError:
                pass
    finally:
        try:
            _lock_path(path).unlink(missing_ok=True)
        except OSError:
            pass


def _take_lock(lock_path, now_epoch):
    """Whether this render may start a refresh: no other refresh holds the lock, or its holder died."""
    try:
        if now_epoch - lock_path.stat().st_mtime >= LOCK_STALE_SECONDS:
            lock_path.unlink(missing_ok=True)
    except OSError:
        pass
    try:
        os.close(os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
    except OSError:
        return False
    return True


def _start_refresh(directory, repository_url, branch):
    """Run this module detached, so the render prints and exits while gh is still on the network.

    The standard streams go to /dev/null because an inherited stdout would hold open the pipe Claude
    Code reads the line from until gh finished. A new session keeps signals aimed at the render's
    process group away from the refresh.
    """
    subprocess.Popen(
        (sys.executable, __file__, directory, repository_url, branch),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def current(
    directory,
    repository_url,
    branch,
    cache_directory,
    now_epoch,
    start_refresh=_start_refresh,
):
    """The pull request to show for `branch`, or None, starting a refresh when the answer is due.

    Nothing is asked outside a GitHub repository.
    """
    if not (repository_url and branch):
        return None
    path = cache_path(cache_directory, repository_url, branch)
    pull_request, due = read(path, now_epoch)
    if not due:
        return pull_request
    lock_path = _lock_path(path)
    try:
        cache_directory.mkdir(parents=True, exist_ok=True)
    except OSError:
        return pull_request
    if _take_lock(lock_path, now_epoch):
        try:
            start_refresh(directory, repository_url, branch)
        except OSError:
            lock_path.unlink(missing_ok=True)
    return pull_request


if __name__ == "__main__":
    refresh(*sys.argv[1:4], cache_directory_from(os.environ))

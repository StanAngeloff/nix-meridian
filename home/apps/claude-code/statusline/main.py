"""Reading Claude Code's status line payload and printing one line that fits the terminal."""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import fit
import render
import segments

# Claude Code sets COLUMNS for the status line child, then truncates the rendered output with an
# ellipsis: a two-column left indent plus a two-column right margin leave COLUMNS - 4 usable.
# Measured against a live session at two widths -- at COLUMNS=50, 46 characters render and 47
# truncate; at COLUMNS=80, 76 render and 77 truncate.
MARGIN_COLUMNS = 4

# What to assume when COLUMNS says nothing, chosen so that nothing degrades. A child of Claude Code
# that is not a status line reports COLUMNS=0, which is why the parsed value falls through an `or`
# rather than only a missing-key check.
ASSUMED_COLUMNS = 200

# Below roughly this width no useful line exists, so stop chasing an unreachable target and let
# Claude Code truncate the tersest forms.
MINIMUM_BUDGET = 20

GIT_TIMEOUT_SECONDS = 2


def budget_from(environment):
    """The columns available to the line, from COLUMNS."""
    try:
        columns = int(environment.get("COLUMNS") or 0)
    except ValueError:
        columns = 0
    return max(MINIMUM_BUDGET, (columns or ASSUMED_COLUMNS) - MARGIN_COLUMNS)


def _git(directory, *arguments):
    try:
        finished = subprocess.run(
            ("git", "-C", directory, "--no-optional-locks", *arguments),
            capture_output=True,
            text=True,
            timeout=GIT_TIMEOUT_SECONDS,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return finished.stdout.strip() if finished.returncode == 0 else ""


def git_branch(directory):
    """The branch name, a short commit when HEAD is detached, or "" outside a repository."""
    return _git(directory, "symbolic-ref", "--quiet", "--short", "HEAD") or _git(
        directory, "rev-parse", "--short", "HEAD"
    )


_GITHUB_SSH = re.compile(r"^git@github\.com:(.+?)(?:\.git)?$")
_GITHUB_HTTPS = re.compile(r"^https?://github\.com/(.+?)(?:\.git)?$")


def github_repo_url(directory):
    """The https://github.com/owner/repo URL for origin, or "" when it is not GitHub."""
    remote = _git(directory, "remote", "get-url", "origin")
    for pattern in (_GITHUB_SSH, _GITHUB_HTTPS):
        match = pattern.match(remote)
        if match:
            return f"https://github.com/{match.group(1)}"
    return ""


def publish_rate_limits(payload, config_directory):
    """Hand the rate limit windows to the usage tray, which shows them in the GNOME panel.

    Claude Code derives these from the inference API's rate-limit headers on every render, so while a
    session is working they are fresher than anything the tray's own /api/oauth/usage poll can get --
    and free, which matters because that endpoint rate-limits hard. The tray still polls for the
    per-model window and the credit balance, neither of which appears here, but far less often while
    this file keeps moving.

    The whole rate_limits object goes through verbatim rather than being picked apart, so field names
    live in one place (the tray's usage.py) and a window Claude Code adds later needs no change here.

    Under ~/.claude rather than XDG_RUNTIME_DIR: the bubble lays a masked tmpfs over the runtime
    directory, so a file written there by a bubbled session would be invisible to the tray on the
    host. ~/.claude is bound through, which is the same channel bubble/modules/notifications uses.
    Renaming into place keeps concurrent sessions from writing over each other mid-write.
    """
    limits = payload.get("rate_limits")
    if not limits:
        return
    scratch_path = config_directory / f"usage-activity.{os.getpid()}"
    try:
        scratch_path.write_text(json.dumps(limits, separators=(",", ":")))
        os.replace(scratch_path, config_directory / "usage-activity")
    except OSError:
        try:
            scratch_path.unlink(missing_ok=True)
        except OSError:
            pass


def line_for(payload, branch, now_epoch, budget, github_url=""):
    """The finished line for this payload at this width, or "" when there is nothing to show."""
    built = segments.build(
        payload, branch=branch, now_epoch=now_epoch, github_url=github_url
    )
    if not built:
        return ""
    measure = render.measure_with(built)
    return render.render(built, fit.fit(built, budget, measure))


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
        return 0
    config_directory = Path(
        os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude"
    )
    publish_rate_limits(payload, config_directory)
    directory = (
        payload.get("cwd")
        or (payload.get("workspace") or {}).get("current_dir")
        or os.getcwd()
    )
    line = line_for(
        payload,
        git_branch(directory),
        int(time.time()),
        budget_from(os.environ),
        github_url=github_repo_url(directory),
    )
    if line:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())

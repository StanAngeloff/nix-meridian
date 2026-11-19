"""Talking to the tmux server the navigator runs under."""

import fcntl
import hashlib
import os
import subprocess
from contextlib import contextmanager

# Server options, set with set -g; tmux.navigator.conf reads the same names in its formats.
OPEN = "@navigator-open"  # 1 while the navigator is open
PANE = "@navigator-pane"  # the pane the navigator runs in
# The session whose window switches the navigator follows: the one it was opened or opened a window from.
# The phone switches windows in its own session, grouped with default, and must not take the navigator along.
SESSION = "@navigator-session"
WIDTH = "@navigator-width"  # columns of the navigator and of every placeholder
MIN_WINDOW_WIDTH = (
    "@navigator-min-width"  # narrower windows, such as the phone's, get no column
)

TIMEOUT_SECONDS = 2


class TmuxError(Exception):
    pass


def tmux(*arguments: str) -> str:
    try:
        result = subprocess.run(
            ["tmux", *arguments],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise TmuxError(str(error)) from error
    if result.returncode != 0:
        raise TmuxError(result.stderr.strip())
    return result.stdout


def option(name: str) -> str:
    return tmux("show", "-gqv", name).strip()


def number_option(name: str, default: int) -> int:
    try:
        return int(option(name) or default)
    except ValueError:
        return default


@contextmanager
def lock():
    """Serialises the commands that add, move and remove columns, which hooks can start at the same moment.

    One lock per tmux server, keyed by its socket, in the runtime directory.
    """
    socket_path = os.environ.get("TMUX", "").split(",")[0] or tmux(
        "display", "-p", "#{socket_path}"
    )
    key = hashlib.sha256(socket_path.encode()).hexdigest()[:16]
    runtime_path = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    lock_path = os.path.join(runtime_path, f"tmux-navigator-{key}.lock")
    with open(lock_path, "w") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)

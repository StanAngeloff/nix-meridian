"""What runs inside a pane, read from /proc: tmux names only the program in the foreground, which for a pane that
started its own tmux is whatever started it."""

import os

# The name a tmux client gives its own process, whatever started it.
TMUX_CLIENT = "tmux: client"


def children(pid: str, root: str = "/proc") -> list[str]:
    found: list[str] = []
    try:
        threads = os.listdir(f"{root}/{pid}/task")
    except OSError:
        return found
    for thread in threads:
        try:
            with open(f"{root}/{pid}/task/{thread}/children") as handle:
                found += handle.read().split()
        except OSError:
            pass  # the thread or the process ended meanwhile
    return found


def command_name(pid: str, root: str = "/proc") -> str:
    try:
        with open(f"{root}/{pid}/comm") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def environment_value(pid: str, name: str, root: str = "/proc") -> str:
    """The first value of the environment variable name found in the process or below it, else nothing.

    Reads one variable out of each environment and keeps nothing else: an environment can hold tokens.
    """
    prefix = name.encode() + b"="
    pending, seen = [pid], set()
    while pending:
        current = pending.pop()
        if not current or current in seen:
            continue
        seen.add(current)
        try:
            with open(f"{root}/{current}/environ", "rb") as handle:
                for variable in handle.read().split(b"\0"):
                    if variable.startswith(prefix):
                        return variable[len(prefix) :].decode(errors="replace")
        except OSError:
            pass  # gone meanwhile, or not ours to read
        pending += children(current, root)
    return ""


def runs_tmux_client(pid: str, root: str = "/proc") -> bool:
    """Whether a tmux client runs anywhere below the process: a pane attached to a tmux of its own."""
    pending, seen = [pid], set()
    while pending:
        current = pending.pop()
        if not current or current in seen:
            continue
        seen.add(current)
        if command_name(current, root) == TMUX_CLIENT:
            return True
        pending += children(current, root)
    return False

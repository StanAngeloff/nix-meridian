"""Opening, moving and closing the navigator.

While it is open, every window at least @navigator-min-width wide keeps a column of the navigator's width on its left:
the navigator itself in the window on screen, a placeholder that sleeps everywhere else. Switching windows swaps the
navigator with the target's placeholder, so no window ever changes size and the navigator keeps running.
The swap for an ordinary switch is in tmux.navigator.conf; the commands here cover opening, closing, a window that has
no column yet, a window crossing the minimum width, and Enter and Tab in the navigator.
"""

import os
import signal

import model
from tmux import MIN_WINDOW_WIDTH, OPEN, PANE, SESSION, WIDGETS, WIDTH, TmuxError, lock
from tmux import number_option
from tmux import option, tmux

DEFAULT_WIDTH = 36
DEFAULT_MIN_WINDOW_WIDTH = 100
SEPARATOR = model.FIELD_SEPARATOR


def navigator_command() -> list[str]:
    return [os.environ["TMUX_NAVIGATOR_COMMAND"], "pane"]


def placeholder_command() -> list[str]:
    return [os.environ["TMUX_NAVIGATOR_PLACEHOLDER"]]


def drawn_channel(navigator: str) -> str:
    """The wait-for channel a navigator signals once its first frame is on screen; one per pane, as pane IDs are
    never reused, so a signal nobody waited for cannot release a later wait."""
    return f"navigator-drawn-{navigator}"


def column_width() -> int:
    return number_option(WIDTH, DEFAULT_WIDTH)


def min_window_width() -> int:
    return number_option(MIN_WINDOW_WIDTH, DEFAULT_MIN_WINDOW_WIDTH)


def is_open() -> bool:
    return option(OPEN) == "1"


def live_navigator() -> str | None:
    """The navigator's pane, unless it has gone with its window.

    Looked up in the list of panes: display -t falls back to the current pane for a pane that no longer exists.
    """
    pane_id = option(PANE)
    if pane_id and pane_id in tmux("list-panes", "-a", "-F", "#{pane_id}").split():
        return pane_id
    return None


def panes(target: list[str], fields: str) -> list[list[str]]:
    output = tmux("list-panes", *target, "-F", fields)
    return [line.split(SEPARATOR) for line in output.splitlines()]


def column_of(window_id: str) -> str | None:
    for pane_id, start_command in panes(
        ["-t", window_id], f"#{{pane_id}}{SEPARATOR}#{{pane_start_command}}"
    ):
        if model.is_column(start_command):
            return pane_id
    return None


def window_width(window_id: str) -> int:
    return int(tmux("display", "-p", "-t", window_id, "#{window_width}"))


def add_column(window_id: str, command: list[str]) -> str:
    """Splits a column off the window's left edge, without moving focus or unzooming the window."""
    zoomed, zoomed_pane = tmux(
        "display", "-p", "-t", window_id, "#{window_zoomed_flag} #{pane_id}"
    ).split()
    pane_id = tmux(
        "split-window",
        "-hbf",
        "-d",
        "-l",
        str(column_width()),
        "-t",
        window_id,
        "-P",
        "-F",
        "#{pane_id}",
        "--",
        *command,
    ).strip()
    if zoomed == "1":
        tmux("resize-pane", "-Z", "-t", zoomed_pane)
    return pane_id


def give_placeholder(window_id: str) -> None:
    """A placeholder for a wide window without a column, so that a later switch to it resizes nothing."""
    if window_width(window_id) >= min_window_width() and not column_of(window_id):
        add_column(window_id, placeholder_command())


def windows_on_screen() -> list[str]:
    """The windows shown by clients of @navigator-session, the session the navigator follows."""
    session = option(SESSION)
    clients = tmux(
        "list-clients", "-F", f"#{{client_session}}{SEPARATOR}#{{window_id}}"
    )
    shown = [line.split(SEPARATOR) for line in clients.splitlines()]
    return list(dict.fromkeys(window for name, window in shown if name == session))


def refresh_status() -> None:
    """Redraws every status bar now: it shows the window list, or the widgets while the navigator is open."""
    for client in tmux("list-clients", "-F", "#{client_name}").split():
        tmux("refresh-client", "-S", "-t", client)


def nudge(navigator: str) -> None:
    """Has the navigator redraw at once after it moved; SIGWINCH, which a process still starting up ignores."""
    try:
        os.kill(
            int(tmux("display", "-p", "-t", navigator, "#{pane_pid}")), signal.SIGWINCH
        )
    except (TmuxError, ValueError, ProcessLookupError):
        pass


def install(window_id: str) -> str | None:
    """Puts the navigator into the window's column, creating either as needed; hold the lock.

    Returns the navigator's pane, or None for a window too narrow for it.
    """
    if window_width(window_id) < min_window_width():
        return None
    column = column_of(window_id)
    navigator = live_navigator()
    if column and column == navigator:
        return navigator
    if column and navigator:
        tmux("swap-pane", "-d", "-Z", "-s", navigator, "-t", column)
    elif column:
        # The navigator went with its window: a new one starts in the placeholder, which resizes nothing.
        tmux("respawn-pane", "-k", "-t", column, "--", *navigator_command())
        navigator = column
        tmux("set", "-g", PANE, navigator)
    elif navigator:
        # A window without a column yet: the navigator moves over, and its old window gets a placeholder.
        old_window = tmux("display", "-p", "-t", navigator, "#{window_id}").strip()
        tmux(
            "join-pane",
            "-hbf",
            "-d",
            "-l",
            str(column_width()),
            "-s",
            navigator,
            "-t",
            window_id,
        )
        try:
            give_placeholder(old_window)
        except TmuxError:
            pass  # the old window closed meanwhile
    else:
        navigator = add_column(window_id, navigator_command())
        tmux("set", "-g", PANE, navigator)
    nudge(navigator)
    return navigator


def toggle(pressed_pane: str, client: str, session: str) -> None:
    """prefix Tab, pressed in a pane of the client's session: opens the navigator focused, focuses it from another
    pane, and closes it from itself.

    tmux.navigator.conf handles focusing a navigator already in the window without starting this.
    """
    if is_open() and pressed_pane == live_navigator():
        close()
        return
    window_id = tmux("display", "-p", "-t", pressed_pane, "#{window_id}").strip()
    with lock():
        minimum = min_window_width()
        if window_width(window_id) < minimum:
            tmux(
                "display-message",
                "-c",
                client,
                f"The navigator needs a window at least {minimum} columns wide",
            )
            return
        was_open = is_open()
        tmux("set", "-g", OPEN, "1", ";", "set", "-g", SESSION, session)
        if not was_open:
            refresh_status()
        navigator = install(window_id)
        if navigator:
            tmux("select-pane", "-t", navigator)
    if not was_open:
        # Every placeholder makes a Claude Code session redraw at its new width, and tmux takes each redraw in before
        # anything else, so populating at once held up the navigator's first frame by a few hundred milliseconds.
        if navigator:
            try:
                tmux("wait-for", drawn_channel(navigator))
            except TmuxError:
                pass  # no frame within the timeout: populate anyway
        populate(session)


def populate(first_session: str) -> None:
    """Gives every other window its placeholder once the navigator has drawn, the current session's windows first.

    One window per turn of the lock, so that switching windows meanwhile waits for one split at most.
    """
    windows = [
        line.split(SEPARATOR)
        for line in tmux(
            "list-windows", "-a", "-F", f"#{{session_name}}{SEPARATOR}#{{window_id}}"
        ).splitlines()
    ]
    ordered = [w for s, w in windows if s == first_session]
    ordered += [w for s, w in windows if s != first_session]
    for window_id in dict.fromkeys(ordered):
        with lock():
            if not is_open():
                return
            try:
                give_placeholder(window_id)
            except TmuxError:
                pass  # the window closed meanwhile


def close() -> None:
    """Removes the navigator first, as the window on screen is the one you see re-wrap, then every placeholder."""
    with lock():
        navigator = live_navigator()
        tmux("set", "-gu", OPEN, ";", "set", "-gu", PANE, ";", "set", "-gu", SESSION)
        tmux("set", "-gu", WIDGETS)
        refresh_status()
        columns = [
            pane_id
            for pane_id, start_command in panes(
                ["-a"], f"#{{pane_id}}{SEPARATOR}#{{pane_start_command}}"
            )
            if model.is_column(start_command)
        ]
        if navigator:
            columns.insert(0, navigator)
        for pane_id in dict.fromkeys(columns):
            try:
                tmux("kill-pane", "-t", pane_id)
            except TmuxError:
                pass  # gone with its window meanwhile


def focus_content(window_id: str, navigator: str | None) -> None:
    """Moves focus off a navigator that arrived focused: a window left with it focused keeps that spot active for the
    placeholder that takes its place, and a switch made outside the navigator should land in the window's content.
    """
    if (
        navigator
        and tmux("display", "-p", "-t", window_id, "#{pane_id}").strip() == navigator
    ):
        leave(navigator)


def arrive(window_id: str = "", session: str = "") -> None:
    """A window came on screen that the swap in tmux.navigator.conf could not serve: no column, or no navigator.

    Without a window, every window on screen: after a hook closed a window, as nothing announces the next one.
    With a session, the client showing the window has just moved to it, and the navigator now follows it.
    """
    with lock():
        if not is_open():
            return
        if session:
            tmux("set", "-g", SESSION, session)
        for window in [window_id] if window_id else windows_on_screen():
            focus_content(window, install(window))


def resized(window_id: str) -> None:
    """A window crossed the minimum width: narrow, it loses its column; wide again, it gets it back."""
    with lock():
        if not is_open():
            return
        column = column_of(window_id)
        if window_width(window_id) < min_window_width():
            if column:
                if column == live_navigator():
                    tmux("set", "-gu", PANE)
                tmux("kill-pane", "-t", column)
            return
        if column:
            return
        if window_id in windows_on_screen():
            focus_content(window_id, install(window_id))
        else:
            give_placeholder(window_id)


def focused_client(navigator: str) -> tuple[str, str]:
    """The client looking at the navigator, as (name, session): the one that pressed the key."""
    fields = f"#{{client_activity}}{SEPARATOR}#{{client_name}}{SEPARATOR}#{{client_session}}{SEPARATOR}#{{pane_id}}"
    clients = [
        line.split(SEPARATOR)
        for line in tmux("list-clients", "-F", fields).splitlines()
    ]
    looking = [c for c in clients if c[3] == navigator] or clients
    _, name, session, _ = max(looking, key=lambda c: int(c[0] or 0))
    return name, session


def go(navigator: str, window_id: str, pane_id: str = "") -> None:
    """Enter or a click: opens the window, in any session, and keeps focus in the navigator, or gives it to pane_id.

    The navigator swaps into the target's column before the switch, in one command list, so the screen shows the
    target with the navigator already in place. A target without a column gets one first, while it is out of sight.
    """
    with lock():
        client, client_session = focused_client(navigator)
        holders = tmux(
            "list-windows", "-a", "-F", f"#{{session_name}}{SEPARATOR}#{{window_id}}"
        ).splitlines()
        sessions = [
            line.split(SEPARATOR)[0]
            for line in holders
            if line.split(SEPARATOR)[1] == window_id
        ]
        if not sessions:
            return
        session = client_session if client_session in sessions else sessions[0]
        column = column_of(window_id)
        if not column and window_width(window_id) >= min_window_width():
            column = add_column(window_id, placeholder_command())
        commands = ["set", "-g", SESSION, session, ";"]
        if column and column != navigator:
            commands += ["swap-pane", "-d", "-Z", "-s", navigator, "-t", column, ";"]
        if session != client_session:
            commands += ["switch-client", "-c", client, "-t", session, ";"]
        commands += ["select-window", "-t", f"{session}:{window_id}"]
        if pane_id or column:
            commands += [";", "select-pane", "-t", pane_id or navigator]
        tmux(*commands)


def move(window_id: str, neighbour_id: str, side: str) -> None:
    """A drop: the window goes before or after its neighbour in its session, and every session of the group is
    renumbered, as move-window -r renumbers only the one session it is given."""
    fields = f"#{{session_name}}{SEPARATOR}#{{session_group}}{SEPARATOR}#{{window_id}}"
    rows = [
        line.split(SEPARATOR)
        for line in tmux("list-windows", "-a", "-F", fields).splitlines()
    ]
    holder = next(((s, g) for s, g, w in rows if w == window_id), None)
    if holder is None:
        return  # closed meanwhile
    session, group = holder
    tmux(
        "move-window",
        "-b" if side == "before" else "-a",
        "-s",
        f"{session}:{window_id}",
        "-t",
        f"{session}:{neighbour_id}",
    )
    for name in sorted({s for s, g, _ in rows if (g or s) == (group or session)}):
        tmux("move-window", "-r", "-t", name)


def leave(navigator: str) -> None:
    """Tab: focus goes to the pane last used in the navigator's window."""
    window_id = tmux("display", "-p", "-t", navigator, "#{window_id}").strip()
    fields = f"#{{pane_id}}{SEPARATOR}#{{pane_last}}{SEPARATOR}#{{pane_start_command}}"
    candidates = [
        (pane_id, last == "1")
        for pane_id, last, start_command in panes(["-t", window_id], fields)
        if not model.is_column(start_command)
    ]
    if candidates:
        last_used = [pane_id for pane_id, last in candidates if last]
        tmux("select-pane", "-t", (last_used or [candidates[0][0]])[0])

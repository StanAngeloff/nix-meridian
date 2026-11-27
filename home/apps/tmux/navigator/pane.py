"""The navigator itself: draws the list in its pane and acts on its keys.

It redraws once a second, at once on a key, and at once on SIGWINCH, which tmux sends when the pane resizes and
control.py sends after moving the navigator into another window.
"""

import os
import select
import signal
import sys
import termios
import time
import tty

import agents
import control
import draw
import keys
import links
import model
import processes
import widgets
from tmux import DONE_SECONDS, WIDGETS, TmuxError, number_option, tmux

POLL_SECONDS = 1.0
DONE_SECONDS_DEFAULT = 30
PROFILE_VARIABLE = "CLAUDE_BUBBLE_PROFILE"


def read_snapshot(home: str) -> model.Snapshot:
    listing = tmux(
        *("list-panes", "-a", "-F", model.PANES_FORMAT, ";"),
        *("list-windows", "-a", "-F", model.SECTIONS_FORMAT),
    )
    snapshot = model.parse(listing, home)
    # A pane attached to a tmux of its own shows as tmux, not as whatever started it; Claude Code panes are skipped.
    for session in snapshot.sessions:
        for window in session.windows:
            for pane in window.panes:
                if not pane.state and not pane.role:
                    if processes.runs_tmux_client(pane.pid):
                        pane.role = "tmux"
    return snapshot


def window_profile(snapshot: model.Snapshot, window_id: str) -> str:
    """The Claude Code profile of the window's Claude Code pane, which the bubble sets in the session's environment
    (home/apps/claude-code/bubble/modules/profiles/hooks.sh); nothing for a window without one.
    """
    window = next(
        (w for s in snapshot.sessions for w in s.windows if w.id == window_id), None
    )
    pane = model.claude_pane(window) if window else None
    return processes.environment_value(pane.pid, PROFILE_VARIABLE) if pane else ""


def run() -> None:
    own_pane = os.environ["TMUX_PANE"]
    home = os.path.expanduser("~")
    cursor = keys.Cursor()
    cpu_meter = widgets.CpuMeter()
    link_rules = links.load()
    scanner = agents.Scanner(home)
    linger = number_option(DONE_SECONDS, DONE_SECONDS_DEFAULT)
    shown_widgets = shown_profile = ""

    # Signals only wake the loop; the wakeup descriptor turns them into something select can wait on.
    wake_read, wake_write = os.pipe()
    os.set_blocking(wake_write, False)
    signal.set_wakeup_fd(wake_write)
    signal.signal(signal.SIGWINCH, lambda *_: None)
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    tty.setraw(0)
    # A dropped window's session is renumbered from base-index, which the drag preview shows ahead of the drop.
    base_index = number_option("base-index", 0)
    # Hide the cursor, ask tmux for focus events and for the mouse in SGR form, drags included (1002), and clear.
    os.write(1, b"\x1b[?25l\x1b[?1004h\x1b[?1002h\x1b[?1006h\x1b[2J")
    previous_frame = ""
    while True:
        try:
            snapshot = read_snapshot(home)
        except TmuxError:
            return  # the server is gone
        scanner.attach(snapshot.sessions, time.time(), linger)
        # The status bar's widgets: handed to tmux only when they change, and drawn at once the first time and when the
        # profile changes, as a window switch should not wait for the bar's own 5-second refresh.
        open_window = snapshot.pane_windows.get(own_pane, "")
        profile = window_profile(snapshot, open_window)
        widget_text = widgets.read(cpu_meter, profile)
        if widget_text != shown_widgets:
            tmux("set", "-g", WIDGETS, widget_text)
            if not shown_widgets or profile != shown_profile:
                control.refresh_status()
            shown_widgets, shown_profile = widget_text, profile
        focused = own_pane in snapshot.active_panes
        # Away from the navigator, the cursor rests on the open window, where it starts when focus comes back.
        if not focused or cursor.window not in model.window_order(snapshot.sessions):
            cursor.window = open_window
        # The key hints show only on ?, and go with focus, so the next focus starts without them; so does grouping.
        if not focused:
            cursor.help = False
            cursor.pane = ""
        # While a window is dragged, the list shows it where it would drop, every window numbered as after the drop.
        drag = cursor.drag
        if drag and drag.window not in model.window_order(snapshot.sessions):
            cursor.drag = drag = None
        sessions, dragging = snapshot.sessions, ""
        if drag and drag.position != drag.origin:
            sessions = model.reordered(
                snapshot.sessions, drag.window, drag.position, base_index
            )
            dragging = drag.window
        size = os.get_terminal_size(0)
        view = draw.View(
            open_window,
            cursor.window,
            focused,
            dragging,
            cursor.help,
            expanded=frozenset(cursor.expanded),
            cursor_pane=cursor.pane,
        )
        hints = draw.GROUP_HINTS if cursor.pane and focused else None
        canvas = draw.draw(sessions, view, size.columns, size.lines, link_rules, hints)
        frame = canvas.to_ansi()
        if frame != previous_frame:
            os.write(1, frame.encode())
            if not previous_frame:
                tmux("wait-for", "-S", control.drawn_channel(own_pane))
            previous_frame = frame

        ready, _, _ = select.select([0, wake_read], [], [], POLL_SECONDS)
        if wake_read in ready:
            os.read(wake_read, 512)
        if 0 not in ready:
            continue
        data = os.read(0, 64)
        if not data:
            return  # the pane closed
        now = time.monotonic()
        for key in keys.split_keys(data.decode(errors="ignore")):
            action = keys.handle_key(cursor, sessions, key, now, canvas.targets)
            try:
                if action and action.kind == "open":
                    control.go(own_pane, cursor.window, action.pane)
                elif action and action.kind == "leave":
                    control.leave(own_pane)
                elif action and action.kind == "rename":
                    window = keys.window_of(sessions, action.window)
                    if window:
                        control.rename(own_pane, window.id, window.name)
                elif action and action.kind in ("move", "regroup", "swap"):
                    if action.kind == "move":
                        control.move(action.window, action.neighbour, action.side)
                    elif action.kind == "regroup":
                        control.regroup(action.window, action.pane, action.side)
                    else:
                        control.swap(action.pane, action.neighbour)
                    # Keys still to come in this read, a held Shift+Down say, move from where things are now.
                    snapshot = read_snapshot(home)
                    sessions = snapshot.sessions
            except TmuxError:
                pass  # the window went away meanwhile; the next frame shows what is left


def main() -> None:
    attributes = termios.tcgetattr(0)
    try:
        run()
    finally:
        termios.tcsetattr(0, termios.TCSADRAIN, attributes)

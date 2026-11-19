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

import control
import draw
import keys
import model
from tmux import TmuxError, tmux

POLL_SECONDS = 1.0


def read_snapshot(home: str) -> model.Snapshot:
    return model.parse(tmux("list-panes", "-a", "-F", model.PANES_FORMAT), home)


def run() -> None:
    own_pane = os.environ["TMUX_PANE"]
    home = os.path.expanduser("~")
    cursor = keys.Cursor()

    # Signals only wake the loop; the wakeup descriptor turns them into something select can wait on.
    wake_read, wake_write = os.pipe()
    os.set_blocking(wake_write, False)
    signal.set_wakeup_fd(wake_write)
    signal.signal(signal.SIGWINCH, lambda *_: None)
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    tty.setraw(0)
    # Hide the cursor, ask tmux for focus events and for mouse clicks and the wheel in SGR form, and start clear.
    os.write(1, b"\x1b[?25l\x1b[?1004h\x1b[?1000h\x1b[?1006h\x1b[2J")
    previous_frame = ""
    while True:
        try:
            snapshot = read_snapshot(home)
        except TmuxError:
            return  # the server is gone
        open_window = snapshot.pane_windows.get(own_pane, "")
        focused = own_pane in snapshot.active_panes
        # Away from the navigator, the cursor rests on the open window, where it starts when focus comes back.
        if not focused or cursor.window not in model.window_order(snapshot.sessions):
            cursor.window = open_window
        size = os.get_terminal_size(0)
        view = draw.View(open_window, cursor.window, focused)
        canvas = draw.draw(snapshot, view, size.columns, size.lines)
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
            action = keys.handle_key(
                cursor, snapshot.sessions, key, now, canvas.targets
            )
            try:
                if action and action[0] == "open":
                    control.go(own_pane, cursor.window, action[1])
                elif action and action[0] == "leave":
                    control.leave(own_pane)
            except TmuxError:
                pass  # the window went away meanwhile; the next frame shows what is left


def main() -> None:
    attributes = termios.tcgetattr(0)
    try:
        run()
    finally:
        termios.tcsetattr(0, termios.TCSADRAIN, attributes)

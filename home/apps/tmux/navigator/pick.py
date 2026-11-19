"""The phone hub's list (home/apps/claude-code/remote/hub.sh): the navigator's rows for the windows of the hub's session
group, drawn full screen until one is picked.

A tap on a window or a pane opens it, as does typing a window's number; n asks for a new session and q quits. The hub
acts on what is picked, printed to standard output as "open <window> <pane>", "new" or "quit"; the list itself draws on
/dev/tty, as the hub reads that output.
"""

import os
import select
import signal
import sys
import termios
import time
import tty
from dataclasses import dataclass

import draw
import keys
import model
import pane
from model import Session
from tmux import TmuxError, tmux

POLL_SECONDS = 1.0
HINTS = [[("tap 1-9", "open"), ("n", "new"), ("q", "quit")]]
# Hide the cursor, ask for presses and releases in SGR form (as the hub always has), and clear; then undo all of it.
START = b"\x1b[?25l\x1b[?1000h\x1b[?1006h\x1b[2J"
END = b"\x1b[?1000l\x1b[?1006l\x1b[?25h\x1b[0m\x1b[2J\x1b[H"


@dataclass
class Picked:
    kind: str  # "open", "new" or "quit"
    window: str = ""
    pane: str = ""


class Picker:
    """Keys and taps on the list. A tap opens on release over the row it pressed; a window number opens at once unless
    a longer one could still be typed, then after keys.NUMBER_TIMEOUT without another digit.
    """

    def __init__(self):
        self.cursor = keys.Cursor()
        self.pressed_row: int | None = None
        self.deadline = 0.0  # when a number a longer one could extend opens its window; 0 when none is being typed

    @property
    def typing(self) -> bool:
        return bool(self.deadline)

    def key(
        self, sessions: list[Session], key: str, now: float, targets
    ) -> Picked | None:
        """targets maps each row of the frame on screen to its window and pane (draw.Canvas)."""
        mouse = keys.MOUSE.fullmatch(key)
        if mouse:
            if int(mouse[1]) != keys.LEFT:
                return None
            row = int(mouse[3]) - 1
            if mouse[4] == "M":
                self.pressed_row = row
                return None
            pressed, self.pressed_row = self.pressed_row, None
            if row != pressed or row not in targets:
                return None
            return opened(sessions, *targets[row])
        if key.isdigit():
            keys.type_digit(self.cursor, sessions, key, now)
            self.deadline = 0.0
            if not self.cursor.number:
                return None
            if extendable(sessions, self.cursor.window, self.cursor.number):
                self.deadline = now + keys.NUMBER_TIMEOUT
                return None
            return opened(sessions, self.cursor.window)
        if key == "n":
            return Picked("new")
        if key == "q":
            return Picked("quit")
        return None

    def tick(self, sessions: list[Session], now: float) -> Picked | None:
        """Opens the window of a number left alone for keys.NUMBER_TIMEOUT."""
        if not self.deadline or now < self.deadline:
            return None
        self.deadline = 0.0
        return opened(sessions, self.cursor.window)


def extendable(sessions: list[Session], window_id: str, number: str) -> bool:
    """Whether another digit could still make number a longer window number in the window's session."""
    session = model.session_of(sessions, window_id)
    numbers = [str(w.index) for w in session.windows] if session else []
    return any(n.startswith(number) and n != number for n in numbers)


def opened(sessions: list[Session], window_id: str, pane_id: str = "") -> Picked | None:
    """The pane to open: the one tapped, else the window's Claude Code pane, else its active pane, as the hub zooms
    the pane it opens."""
    if pane_id:
        return Picked("open", window_id, pane_id)
    session = model.session_of(sessions, window_id)
    window = (
        next((w for w in session.windows if w.id == window_id), None)
        if session
        else None
    )
    if window is None or not window.panes:
        return None
    chosen = model.claude_pane(window) or next(
        (p for p in window.panes if p.active), window.panes[0]
    )
    return Picked("open", window_id, chosen.id)


def of_group(sessions: list[Session], group: str) -> list[Session]:
    """The sessions of the group, which model.parse lists under the group's name; every session when it has none."""
    return [s for s in sessions if s.name == group] or sessions


def hub_view(session: str, home: str) -> tuple[list[Session], str]:
    """The windows the hub's session shares with its group, and the one it last showed, drawn cyan like the window the
    navigator sits in."""
    snapshot = pane.read_snapshot(home)
    try:
        output = tmux(
            "display", "-p", "-t", f"={session}", "#{session_group}\x1f#{window_id}"
        )
    except TmuxError:
        return snapshot.sessions, ""
    group, _, window_id = output.strip().partition("\x1f")
    return of_group(snapshot.sessions, group or session), window_id


def run(session: str, screen: int) -> Picked:
    home = os.path.expanduser("~")
    picker = Picker()
    # A resize, the phone turning, redraws at once; the signal only wakes select.
    wake_read, wake_write = os.pipe()
    os.set_blocking(wake_write, False)
    signal.set_wakeup_fd(wake_write)
    signal.signal(signal.SIGWINCH, lambda *_: None)
    previous_frame = ""
    while True:
        sessions, open_window = hub_view(session, home)
        now = time.monotonic()
        picked = picker.tick(sessions, now)
        if picked:
            return picked
        size = os.get_terminal_size(0)
        # The cursor shows only while a number is being typed, on the window it would open. PLAIN: Termux has no Nerd Font.
        view = draw.View(
            open_window, picker.cursor.window, picker.typing, glyphs=draw.PLAIN
        )
        canvas = draw.draw(sessions, view, size.columns, size.lines, hints=HINTS)
        frame = canvas.to_ansi()
        if frame != previous_frame:
            os.write(screen, frame.encode())
            previous_frame = frame

        timeout = POLL_SECONDS
        if picker.typing:
            timeout = max(0.0, min(timeout, picker.deadline - now))
        ready, _, _ = select.select([0, wake_read], [], [], timeout)
        if wake_read in ready:
            os.read(wake_read, 512)
        if 0 not in ready:
            continue
        data = os.read(0, 64)
        if not data:
            return Picked(
                "quit"
            )  # the connection closed; the hub has no one left to serve
        now = time.monotonic()
        for key in keys.split_keys(data.decode(errors="ignore")):
            picked = picker.key(sessions, key, now, canvas.targets)
            if picked:
                return picked


def main(session: str) -> None:
    screen = os.open("/dev/tty", os.O_WRONLY)
    attributes = termios.tcgetattr(0)
    try:
        tty.setraw(0)
        os.write(screen, START)
        picked = run(session, screen)
    finally:
        os.write(screen, END)
        termios.tcsetattr(0, termios.TCSADRAIN, attributes)
        os.close(screen)
    print(" ".join(part for part in (picked.kind, picked.window, picked.pane) if part))
    sys.stdout.flush()

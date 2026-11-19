"""Keys and clicks in the navigator: what each does to the cursor, and which action it asks for."""

import re
from dataclasses import dataclass

from model import Session, session_of, window_order

# A digit typed within this many seconds of the previous one extends the window number: 1 then 2 is window 12.
NUMBER_TIMEOUT = 0.8

DOWN = ("j", "\x1b[B")
UP = ("k", "\x1b[A")
ENTER = ("\r", "\n")
LEAVE = ("\t", "\x1b")  # Tab hands focus back to the pane; so does Esc

# A mouse event in SGR form (mode 1006), which the navigator asks tmux for: ESC [ < button ; column ; row, then M for
# a press or m for a release. Column and row count from 1 at the pane's top left.
MOUSE = re.compile(r"\x1b\[<(\d+);(\d+);(\d+)([Mm])")
LEFT_PRESS = 0
WHEEL_UP = 64
WHEEL_DOWN = 65

# What a key or click asks for: ("open", "") opens the cursor's window and keeps focus in the navigator,
# ("open", pane) opens it and focuses that pane, ("leave", "") hands focus back to the window's pane.
Action = tuple[str, str]


@dataclass
class Cursor:
    window: str = ""  # the window under the cursor
    number: str = ""  # the window number being typed
    number_typed_at: float = 0.0  # when its last digit arrived


def split_keys(data: str):
    """Splits one read into keys: a mouse event is one, an arrow or a focus event is ESC [ and one character."""
    i = 0
    while i < len(data):
        mouse = MOUSE.match(data, i)
        if mouse:
            length = mouse.end() - i
        elif data.startswith("\x1b[", i) and i + 2 < len(data):
            length = 3
        else:
            length = 1
        yield data[i : i + length]
        i += length


def handle_key(
    cursor: Cursor,
    sessions: list[Session],
    key: str,
    now: float,
    targets: dict[int, tuple[str, str]],
) -> Action | None:
    """Applies one key or click to the cursor, and returns the action it asks for, if any.

    targets maps each row of the last frame drawn to the window and pane a click there opens (draw.Canvas).
    """
    mouse = MOUSE.fullmatch(key)
    if mouse:
        return handle_mouse(cursor, sessions, mouse, targets)
    if key in DOWN or key in UP:
        move(cursor, sessions, 1 if key in DOWN else -1)
    elif key.isdigit():
        type_digit(cursor, sessions, key, now)
    elif key in ENTER:
        return ("open", "")
    elif key in LEAVE:
        return ("leave", "")
    return None


def handle_mouse(cursor, sessions, mouse: re.Match, targets) -> Action | None:
    """A click on a window's row opens it, like Enter; on a pane's row it opens the window at that pane.
    The wheel moves the cursor. Releases, other buttons and rows without a window do nothing.
    """
    button, row, pressed = int(mouse[1]), int(mouse[3]) - 1, mouse[4] == "M"
    if not pressed:
        return None
    if button in (WHEEL_UP, WHEEL_DOWN):
        move(cursor, sessions, 1 if button == WHEEL_DOWN else -1)
        return None
    if button != LEFT_PRESS or row not in targets:
        return None
    cursor.window, pane_id = targets[row]
    return ("open", pane_id)


def move(cursor: Cursor, sessions: list[Session], step: int) -> None:
    order = window_order(sessions)
    if order:
        position = order.index(cursor.window) if cursor.window in order else 0
        cursor.window = order[(position + step) % len(order)]


def type_digit(cursor: Cursor, sessions: list[Session], digit: str, now: float):
    """Moves the cursor to the window numbered by the digits typed so far, in the session under the cursor.

    A digit within NUMBER_TIMEOUT of the previous one extends the number when that window exists (1 then 2 is 12);
    otherwise the digit starts a new number, so 1 then 2 lands on 2 in a session without a window 12.
    """
    session = session_of(sessions, cursor.window) or (sessions[0] if sessions else None)
    if session is None:
        return
    by_index = {str(window.index): window.id for window in session.windows}
    recent = now - cursor.number_typed_at <= NUMBER_TIMEOUT
    for number in (cursor.number + digit if recent else "", digit):
        if number in by_index:
            cursor.window, cursor.number = by_index[number], number
            break
    else:
        cursor.number = ""
    cursor.number_typed_at = now

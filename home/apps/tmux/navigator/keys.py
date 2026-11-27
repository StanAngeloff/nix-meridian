"""Keys and clicks in the navigator: what each does to the cursor, and which action it asks for."""

import re
from dataclasses import dataclass, field

from model import Session, Window, session_of, window_order

# A digit typed within this many seconds of the previous one extends the window number: 1 then 2 is window 12.
NUMBER_TIMEOUT = 0.8

DOWN = ("j", "\x1b[B")
UP = ("k", "\x1b[A")
# Shift+Down and Shift+Up, as tmux passes them to a pane: they move the window under the cursor within its session.
SHIFT_DOWN = "\x1b[1;2B"
SHIFT_UP = "\x1b[1;2A"
ENTER = ("\r", "\n")
LEAVE = ("\t", "\x1b")  # Tab hands focus back to the pane; so does Esc
HELP = "?"  # shows the key hints, and hides them again
SPACE = " "  # lists the workflows of the cursor's window agent by agent, and folds them back into a count
# Shift+J and Shift+K do what Shift+Down and Shift+Up do: move the window under the cursor, or a pane while grouping.
MOVE_DOWN = ("J", SHIFT_DOWN)
MOVE_UP = ("K", SHIFT_UP)
GROUP = "g"  # starts grouping the panes of the cursor's window, and ends it
RENAME = "r"  # renames the window under the cursor, where prefix , renames the window on screen
# While grouping: a pane joins a group, or leaves its group (layout.py, joined and left).
NEST = ("l", "\x1b[C")
UNNEST = ("h", "\x1b[D")
ESCAPE = "\x1b"
QUIT = "q"  # ends grouping, as g and Esc do

# A mouse event in SGR form (mode 1006), which the navigator asks tmux for: ESC [ < button ; column ; row, then M for
# a press or m for a release. Column and row count from 1 at the pane's top left.
MOUSE = re.compile(r"\x1b\[<(\d+);(\d+);(\d+)([Mm])")
# A whole control sequence: ESC [, its parameters, and one final character. Arrows, Shift+arrows, focus events and
# mouse events are all of this form; read one character at a time, ESC [1;2A would type a stray 2.
CONTROL_SEQUENCE = re.compile(r"\x1b\[[0-9;<>?]*[@-~]")
LEFT = 0
LEFT_DRAG = 32  # the left button held while the mouse moves, which the navigator asks tmux for (mode 1002)
WHEEL_UP = 64
WHEEL_DOWN = 65


@dataclass
class Action:
    """What a key or click asks for: "open" the cursor's window, keeping focus in the navigator or giving it to
    pane; "leave" for the window's pane; "move" window before or after neighbour, a drop; "rename" window;
    while grouping, "regroup" pane of window, side "join" or "leave", or "swap" pane with its neighbour, a pane too.
    """

    kind: str
    pane: str = ""
    window: str = ""
    neighbour: str = ""
    side: str = ""  # "before" or "after"


@dataclass
class Drag:
    """A window picked up with the left button; position is its place in its session's list, as shown while it is
    carried, and origin where it started, so a release without a move is a click."""

    window: str
    pane: str
    origin: int
    position: int


@dataclass
class Cursor:
    window: str = ""  # the window under the cursor
    number: str = ""  # the window number being typed
    number_typed_at: float = 0.0  # when its last digit arrived
    drag: Drag | None = None  # a window being dragged to a new place
    help: bool = False  # the key hints are shown
    expanded: set[str] = field(
        default_factory=set
    )  # windows whose workflows list their agents
    # The pane under the cursor while the panes of the cursor's window are being grouped; empty otherwise.
    pane: str = ""


def split_keys(data: str):
    """Splits one read into keys: a control sequence is one key, anything else one character."""
    i = 0
    while i < len(data):
        sequence = CONTROL_SEQUENCE.match(data, i)
        length = sequence.end() - i if sequence else 1
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
    A click while grouping ends the grouping and counts as it would otherwise.
    """
    mouse = MOUSE.fullmatch(key)
    if cursor.pane and not mouse:
        return handle_grouping(cursor, sessions, key)
    cursor.pane = ""
    if mouse:
        return handle_mouse(cursor, sessions, mouse, targets)
    if key in MOVE_DOWN or key in MOVE_UP:
        return shift(cursor, sessions, 1 if key in MOVE_DOWN else -1)
    if key in DOWN or key in UP:
        move(cursor, sessions, 1 if key in DOWN else -1)
    elif key.isdigit():
        type_digit(cursor, sessions, key, now)
    elif key in ENTER:
        return Action("open")
    elif key in LEAVE:
        return Action("leave")
    elif key == HELP:
        cursor.help = not cursor.help
    elif key == SPACE and cursor.window:
        cursor.expanded ^= {cursor.window}
    elif key == GROUP:
        window = window_of(sessions, cursor.window)
        if window and len(window.panes) > 1:
            cursor.pane = window.panes[0].id
    elif key == RENAME and cursor.window:
        return Action("rename", window=cursor.window)
    return None


def handle_grouping(cursor: Cursor, sessions: list[Session], key: str) -> Action | None:
    """Keys while grouping the panes of the cursor's window: j and k move between its panes,
    l and h nest a pane into a group and take it out, J and K move it past its neighbour, Enter opens it;
    g, q or Esc end the grouping, and Tab leaves the navigator."""
    window = window_of(sessions, cursor.window)
    order = [pane.id for pane in window.panes] if window else []
    if cursor.pane not in order:
        cursor.pane = ""  # the pane or its window went away
        return None
    position = order.index(cursor.pane)
    if key in DOWN or key in UP:
        cursor.pane = order[(position + (1 if key in DOWN else -1)) % len(order)]
    elif key in NEST or key in UNNEST:
        side = "join" if key in NEST else "leave"
        return Action("regroup", pane=cursor.pane, window=cursor.window, side=side)
    elif key in MOVE_DOWN or key in MOVE_UP:
        neighbour = position + (1 if key in MOVE_DOWN else -1)
        if 0 <= neighbour < len(order):
            return Action(
                "swap",
                pane=cursor.pane,
                window=cursor.window,
                neighbour=order[neighbour],
            )
    elif key in ENTER:
        pane, cursor.pane = cursor.pane, ""
        return Action("open", pane=pane)
    elif key in (GROUP, QUIT, ESCAPE):
        cursor.pane = ""
    elif key in LEAVE:
        cursor.pane = ""
        return Action("leave")
    return None


def window_of(sessions: list[Session], window_id: str) -> Window | None:
    return next(
        (w for session in sessions for w in session.windows if w.id == window_id), None
    )


def handle_mouse(cursor, sessions, mouse: re.Match, targets) -> Action | None:
    """The left button picks a window up by any of its rows. Dragged over another window of the same session, it takes
    that window's place; released there, it moves (Action "move"). Released where it started, it was a click: a
    window's row opens the window, like Enter, and a pane's row opens it at that pane. The wheel moves the cursor.

    sessions are the ones drawn, with a dragged window already in its new place, as are the rows of targets.
    """
    button, row, pressed = int(mouse[1]), int(mouse[3]) - 1, mouse[4] == "M"
    if pressed and button in (WHEEL_UP, WHEEL_DOWN):
        move(cursor, sessions, 1 if button == WHEEL_DOWN else -1)
    elif pressed and button == LEFT:
        cursor.drag = None
        if row in targets:
            window_id, pane_id = targets[row]
            origin = place(sessions, window_id)
            cursor.drag = Drag(window_id, pane_id, origin, origin)
            cursor.window = window_id
    elif pressed and button == LEFT_DRAG and cursor.drag and row in targets:
        hovered = targets[row][0]
        session = session_of(sessions, cursor.drag.window)
        if hovered != cursor.drag.window and session_of(sessions, hovered) is session:
            cursor.drag.position = place(sessions, hovered)
    elif not pressed and button == LEFT and cursor.drag:
        drag, cursor.drag = cursor.drag, None
        cursor.window = drag.window
        if drag.position == drag.origin:
            return Action("open", pane=drag.pane)
        return drop(sessions, drag)
    return None


def shift(cursor: Cursor, sessions: list[Session], step: int) -> Action | None:
    """Shift+Down or Shift+Up: the window under the cursor trades places with the next or previous one in its
    session, as a drop there would; nothing at either end. The cursor stays on the window.
    """
    session = session_of(sessions, cursor.window)
    if session is None:
        return None
    order = [w.id for w in session.windows]
    neighbour = order.index(cursor.window) + step
    if not 0 <= neighbour < len(order):
        return None
    side = "after" if step > 0 else "before"
    return Action("move", window=cursor.window, neighbour=order[neighbour], side=side)


def place(sessions: list[Session], window_id: str) -> int:
    """The window's place in its session's list."""
    session = session_of(sessions, window_id)
    return [w.id for w in session.windows].index(window_id) if session else 0


def drop(sessions: list[Session], drag: Drag) -> Action:
    """The move that leaves the dragged window where it is drawn: before the window after it, or after the one
    before it when it is last."""
    session = session_of(sessions, drag.window)
    order = [w.id for w in session.windows]
    position = order.index(drag.window)
    if position + 1 < len(order):
        return Action(
            "move", window=drag.window, neighbour=order[position + 1], side="before"
        )
    return Action(
        "move", window=drag.window, neighbour=order[position - 1], side="after"
    )


def move(cursor: Cursor, sessions: list[Session], step: int) -> None:
    order = window_order(sessions)
    if order:
        position = order.index(cursor.window) if cursor.window in order else 0
        cursor.window = order[(position + step) % len(order)]


def type_digit(cursor: Cursor, sessions: list[Session], digit: str, now: float):
    """Moves the cursor to the window numbered by the digits typed so far, in the session under the cursor.

    A digit within NUMBER_TIMEOUT of the previous one extends the number when that window exists (1 then 2 is 12);
    otherwise the digit starts a new number, so 1 then 2 lands on 2 in a session without a window 12.
    A section header shows no number, so no digits land on it.
    """
    session = session_of(sessions, cursor.window) or (sessions[0] if sessions else None)
    if session is None:
        return
    by_index = {
        str(window.index): window.id for window in session.windows if not window.section
    }
    recent = now - cursor.number_typed_at <= NUMBER_TIMEOUT
    for number in (cursor.number + digit if recent else "", digit):
        if number in by_index:
            cursor.window, cursor.number = by_index[number], number
            break
    else:
        cursor.number = ""
    cursor.number_typed_at = now

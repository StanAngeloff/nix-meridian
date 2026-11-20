"""The phone hub's new-session screens (hub.sh beside this file): a recent directory, then a cc profile and a name.

Both draw as the hub's list does, with the navigator's own painter (home/apps/tmux/navigator/draw.py): a header, rows
numbered from the newest directory down, and the key hints at the foot. A tap or a number picks a directory; the second
screen shows it as a row with two branches, the profiles with the default selected, then the name being typed. Enter
prints the directory, the profile and the name on three lines for hub.sh to start; going back to the hub's list prints
nothing. The screens draw on /dev/tty, as hub.sh reads standard output.
"""

import codecs
import os
import re
import select
import signal
import sys
import termios
import time
import tty
from dataclasses import dataclass, field
from types import SimpleNamespace

import draw

# The directory screen goes back to the hub's list after this long without a key, as the hub always has.
WAIT_SECONDS = 30.0
TITLE = "New session"
NAME_PLACEHOLDER = "session name"
# A branch's text starts where a pane's icon would; a profile's padding sits in the gap before it, so the profiles' names
# line up with the name being typed.
NAME_X = draw.CONTENT_X + 3
PROFILE_X = NAME_X - 1
# Hide the cursor, ask for presses and releases in SGR form (as the hub's list does), and clear; then undo all of it.
START = "\x1b[?25l\x1b[?1000h\x1b[?1006h\x1b[2J"
END = "\x1b[?1000l\x1b[?1006l\x1b[?25h\x1b[0m\x1b[2J\x1b[H"
ESCAPE = "\x1b"
TAB = "\t"
ENTER = ("\r", "\n")
BACKSPACE = ("\x7f", "\x08")
MOUSE = re.compile(r"\x1b\[<(\d+);(\d+);(\d+)([Mm])")
LEFT_BUTTON = 0
BACK = "back"


@dataclass
class Started:
    directory: str
    profile: str
    name: str


@dataclass
class Frame:
    canvas: draw.Canvas
    # Row → (first column, column after the last, index) for each thing a tap on that row picks: a directory on the
    # directory screen, a profile on the second. Rows and columns count from 0.
    targets: dict[int, list[tuple[int, int, int]]] = field(default_factory=dict)
    # (row, column) where the name being typed ends.
    cursor: tuple[int, int] | None = None


def slug_name(slug: str) -> str:
    """The profile name a directory's slug spells: personal--2 is personal/2 (profiles.sh, as usage.py copies it)."""
    return slug.replace("--", "/")


def read_profiles(profiles_path: str) -> tuple[list[str], str]:
    """The cc profiles by name, and the default: each directory in profiles/ holding credentials/, and the one the
    active link points at. The active link and the hidden backup are not profiles (profiles.sh, _profile_names), nor
    is active where it is a directory, as inside a session (_profile_valid_name).
    """
    try:
        entries = os.listdir(profiles_path)
    except OSError:
        return [], ""
    names = sorted(
        slug_name(entry)
        for entry in entries
        if not entry.startswith(".")
        and entry != "active"
        and not os.path.islink(os.path.join(profiles_path, entry))
        and os.path.isdir(os.path.join(profiles_path, entry, "credentials"))
    )
    try:
        target = os.readlink(os.path.join(profiles_path, "active"))
    except OSError:
        target = ""
    default = slug_name(os.path.basename(target.rstrip("/")).removesuffix(".json"))
    return names, default


def abbreviate_home(path: str, home: str) -> str:
    if path == home or path.startswith(home + "/"):
        return "~" + path[len(home) :]
    return path


def cut_path(path: str, width: int) -> tuple[str, str]:
    """The path's parent, drawn dimmer, and its last part, as a browser dims a web address around its domain. A path
    wider than width loses its start to an ellipsis, so its last part shows."""
    if width < 1:
        return "", ""
    parent, slash, name = path.rpartition("/")
    parent += slash
    if len(path) > width:
        keep = width - 1
        name = name[max(len(name) - keep, 0) :]
        parent = draw.ELLIPSIS + parent[len(parent) - (keep - len(name)) :]
    return parent, name


def split_keys(text: str) -> list[str]:
    """The keys in text: a control sequence (a tap, an arrow) is one key, as is every other character. An Escape that
    starts no sequence is the Escape key."""
    keys = []
    index = 0
    while index < len(text):
        end = index + 1
        if text[index] == ESCAPE and index + 1 < len(text) and text[index + 1] in "[O":
            end = index + 2
            if text[index + 1] == "[":
                while end < len(text) and not "\x40" <= text[end] <= "\x7e":
                    end += 1
            end += 1
        keys.append(text[index:end])
        index = end
    return keys


def draw_title(c: draw.Canvas) -> None:
    # draw_header reads only the session's name.
    draw.draw_header(c, 0, SimpleNamespace(name=TITLE), draw.PLAIN)


def draw_directory(
    c: draw.Canvas, y: int, index: int, path: str, home: str, trunk: str
) -> None:
    """A directory as the hub's list draws a window: its number, the trunk, then its path."""
    c.put(draw.INDEX_X, y, f"{index + 1:>2}", draw.STATUS_FG)
    c.put(draw.TRUNK_X, y, trunk, draw.DIMMER)
    width = c.cols - draw.CONTENT_X - 1
    parent, name = cut_path(abbreviate_home(path, home), width)
    x = c.put(draw.CONTENT_X, y, parent, draw.DIM)
    c.put(x, y, name, draw.STATUS_FG)


def draw_branch(c: draw.Canvas, y: int, trunk: str, branch: str) -> None:
    c.put(draw.TRUNK_X, y, trunk, draw.DIMMER)
    c.put(draw.CONTENT_X, y, branch, draw.DIMMER)


class NewSession:
    """What the two screens show and what each key does to them. The directory screen is on show until a directory is
    picked; Escape on the second screen goes back to it, keeping the profile and the name.
    """

    def __init__(self, directories: list[str], profiles: list[str], default: str):
        self.directories = directories
        self.profiles = profiles
        self.profile = profiles.index(default) if default in profiles else 0
        self.directory: int | None = None
        self.name = ""
        # (row, index) a press landed on; its release there picks it.
        self.pressed: tuple[int, int] | None = None

    def frame(self, home: str, columns: int, rows: int) -> Frame:
        frame = Frame(draw.Canvas(columns, rows))
        draw_title(frame.canvas)
        if self.directory is None:
            hints = self.draw_directories(frame, home)
        else:
            hints = self.draw_details(frame, home)
        draw.draw_hints(frame.canvas, rows - 2, [hints])
        return frame

    def draw_directories(self, frame: Frame, home: str) -> list[tuple[str, str]]:
        c = frame.canvas
        count = len(self.directories)
        if not count:
            c.put(1, 1, "No project directories found.", draw.DIM)
            return [("esc", "back")]
        for index, path in enumerate(self.directories):
            y = 1 + index
            # The trunk stops at mid-row on the last row, as under the hub's last window.
            draw_directory(c, y, index, path, home, "╵" if index == count - 1 else "│")
            frame.targets[y] = [(0, c.cols, index)]
        numbers = "1" if count == 1 else f"1-{count}"
        return [(f"tap {numbers}", "pick"), ("esc", "back")]

    def draw_details(self, frame: Frame, home: str) -> list[tuple[str, str]]:
        """The directory as a row, the profiles on its first branch and the name on its last."""
        c = frame.canvas
        draw_directory(
            c, 1, self.directory, self.directories[self.directory], home, "│"
        )
        y = 2
        if self.profiles:
            y = self.draw_profiles(frame, y)
        draw_branch(c, y, "╵", "└─")
        room = max(c.cols - NAME_X - 1, 1)  # a column is left for the cursor
        shown = self.name
        if len(shown) > room:
            shown = draw.ELLIPSIS + shown[len(shown) - room + 1 :]
        if shown:
            c.put(NAME_X, y, shown, draw.TEXT)
        else:
            c.put_fitted(NAME_X, y, NAME_PLACEHOLDER, room, draw.DIMMER)
        frame.cursor = (y, NAME_X + len(shown))
        if len(self.profiles) < 2:
            return [("enter", "start"), ("esc", "back")]
        return [("enter", "start"), ("tab", "profile"), ("esc", "back")]

    def draw_profiles(self, frame: Frame, y: int) -> int:
        """One per profile from row y, the selected one on the cyan of the hub's open window; profiles that do not fit
        continue on the next row, under the first. Returns the row after them."""
        c = frame.canvas
        draw_branch(c, y, "│", "├─")
        x = PROFILE_X
        for index, name in enumerate(self.profiles):
            text = f" {name} "
            if x > PROFILE_X and x + len(text) > c.cols:
                y += 1
                draw_branch(c, y, "│", "│")
                x = PROFILE_X
            frame.targets.setdefault(y, []).append((x, x + len(text), index))
            if index == self.profile:
                c.put(x, y, text, draw.FOCUSED_TAB_FG, draw.FOCUSED_TAB_BG, bold=True)
            else:
                c.put(x, y, text, draw.DIM)
            x += len(text)
        return y + 1

    def key(self, key: str, frame: Frame) -> Started | str | None:
        """What key does on the screen frame shows: a Started or BACK when the screens are done, else None."""
        mouse = MOUSE.fullmatch(key)
        if mouse:
            return self.tap(frame, mouse)
        if self.directory is None:
            if key == ESCAPE:
                return BACK
            if key.isdigit() and 1 <= int(key) <= len(self.directories):
                self.directory = int(key) - 1
            return None
        if key == ESCAPE:
            self.directory = None
        elif key == TAB and self.profiles:
            self.profile = (self.profile + 1) % len(self.profiles)
        elif key in ENTER:
            if not self.name:
                return BACK
            profile = self.profiles[self.profile] if self.profiles else ""
            return Started(self.directories[self.directory], profile, self.name)
        elif key in BACKSPACE:
            self.name = self.name[:-1]
        elif len(key) == 1 and key.isprintable():
            self.name += key
        return None

    def tap(self, frame: Frame, mouse: re.Match) -> None:
        """A tap picks on release over what it pressed, as in the hub's list."""
        if int(mouse[1]) != LEFT_BUTTON:
            return None
        row, column = int(mouse[3]) - 1, int(mouse[2]) - 1
        under = next(
            (
                (row, index)
                for first, after, index in frame.targets.get(row, [])
                if first <= column < after
            ),
            None,
        )
        if mouse[4] == "M":
            self.pressed = under
            return None
        pressed, self.pressed = self.pressed, None
        if under is None or under != pressed:
            return None
        if self.directory is None:
            self.directory = under[1]
        else:
            self.profile = under[1]
        return None


def render(frame: Frame) -> str:
    """The frame's canvas; the cursor shows only where a name is being typed."""
    text = frame.canvas.to_ansi()
    if frame.cursor is None:
        return text + "\x1b[?25l"
    row, column = frame.cursor
    return text + f"\x1b[{row + 1};{column + 1}H\x1b[?25h"


def run(session: NewSession, home: str, screen: int) -> Started | str:
    # A resize, the phone turning or its keyboard showing, redraws at once; the signal only wakes select.
    wake_read, wake_write = os.pipe()
    os.set_blocking(wake_write, False)
    signal.set_wakeup_fd(wake_write)
    signal.signal(signal.SIGWINCH, lambda *_: None)
    decoder = codecs.getincrementaldecoder("utf-8")(errors="ignore")
    deadline = time.monotonic() + WAIT_SECONDS
    previous = ""
    while True:
        size = os.get_terminal_size(0)
        frame = session.frame(home, size.columns, size.lines)
        text = render(frame)
        if text != previous:
            os.write(screen, text.encode())
            previous = text
        timeout = None
        if session.directory is None:
            timeout = deadline - time.monotonic()
            if timeout <= 0:
                return BACK
        ready, _, _ = select.select([0, wake_read], [], [], timeout)
        if wake_read in ready:
            os.read(wake_read, 512)
        if 0 not in ready:
            continue
        data = os.read(0, 64)
        if not data:
            return BACK  # the connection closed; the hub's list finds out and quits
        deadline = time.monotonic() + WAIT_SECONDS
        for key in split_keys(decoder.decode(data)):
            outcome = session.key(key, frame)
            if outcome:
                return outcome
            frame = session.frame(home, size.columns, size.lines)


def main(directories: list[str]) -> None:
    home = os.path.expanduser("~")
    config_path = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(home, ".claude")
    profiles, default = read_profiles(os.path.join(config_path, "profiles"))
    session = NewSession(directories, profiles, default)
    screen = os.open("/dev/tty", os.O_WRONLY)
    attributes = termios.tcgetattr(0)
    try:
        tty.setraw(0)
        os.write(screen, START.encode())
        outcome = run(session, home, screen)
    finally:
        os.write(screen, END.encode())
        termios.tcsetattr(0, termios.TCSADRAIN, attributes)
        os.close(screen)
    if isinstance(outcome, Started):
        print(outcome.directory, outcome.profile, outcome.name, sep="\n")


if __name__ == "__main__":
    main(sys.argv[1:])

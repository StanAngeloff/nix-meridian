"""Drawing the navigator: every session as a header, every window as a line, its panes as a tree below it."""

from dataclasses import dataclass

from model import Pane, Session, Snapshot, Window

# Colours, from home/apps/tmux/tmux.conf, PALETTE.md and the Ghostty palette.
TERMINAL_BG = "#000000"
TERMINAL_FG = "#ffffff"
STATUS_FG = "#9e9e9e"  # colour247, unfocused tab text
FOCUSED_TAB_BG = "#00afff"  # colour39, the anchor
FOCUSED_TAB_FG = "#000000"
FOCUSED_TAB_DIM = "#00557c"  # secondary text and lines on the cyan of the open window
SESSION_FG = "#d0d0d0"  # colour252, as in status-left
SESSION_BG = "#808080"  # colour244
DIM = "#6c6c6c"  # colour242
DIMMER = "#4e4e4e"  # colour239
CURSOR_BG = "#262626"  # colour235
CURSOR_ON_CYAN = (
    "#ffffff"  # the cursor's bar on the open window, where cyan would vanish
)
TEXT = "#bcbcbc"  # colour250

# Traffic-light dots: shade 500 on the dark bar, shade 600 on the cyan tab (PALETTE.md).
DOT_ON_DARK = {
    "blocked": "#ff0000",
    "working": "#ff9300",
    "unread": "#00ff00",
    "read": "#4cb24c",
}
DOT_ON_CYAN = {
    "blocked": "#cc0000",
    "working": "#cc7500",
    "unread": "#00cc00",
    "read": "#3d8e3d",
}

POWERLINE_ARROW = "\ue0b0"
DOT = "●"
ELLIPSIS = "…"

# Nerd Font icons for panes without Claude Code, keyed by #{pane_current_command}.
# Every one is in BerkeleyMono Nerd Font Mono; tmux gives these private-use glyphs one cell, as the font does.
SHELL_ICON = "\uf489"
GIT_ICON = "\ue702"
VIM_ICON = "\ue62b"
TEXT_ICON = "\uf15c"
PROGRAM_ICONS = {
    "zsh": SHELL_ICON,
    "bash": SHELL_ICON,
    "sh": SHELL_ICON,
    "fish": SHELL_ICON,
    "nvim": "\uf36f",
    "vim": VIM_ICON,
    "vi": VIM_ICON,
    "tig": GIT_ICON,
    "git": GIT_ICON,
    "lazygit": GIT_ICON,
    "ssh": "\uf233",
    "mosh-client": "\uf233",
    "python": "\ue73c",
    "python3": "\ue73c",
    "node": "\ue718",
    "bun": "\ue718",
    "htop": "\uf080",
    "btop": "\uf080",
    "top": "\uf080",
    "journalctl": TEXT_ICON,
    "less": TEXT_ICON,
    "tail": TEXT_ICON,
    "ov": TEXT_ICON,
    "man": "\uf02d",
}
OTHER_ICON = "\uf013"

# Columns of a window's rows: the cursor's bar, the window number, the session's trunk, then the content.
INDEX_X = 1
TRUNK_X = 3
CONTENT_X = 5


@dataclass
class View:
    open_window: str  # the window the navigator sits in, drawn cyan
    cursor: str  # the window under the cursor
    focused: (
        bool  # the cursor and the key hints show only while the navigator has focus
    )


class Canvas:
    """A grid of cells, each (character, foreground, background, bold), written out as ANSI."""

    def __init__(self, cols: int, rows: int):
        self.cols, self.rows = cols, rows
        blank = (" ", TERMINAL_FG, TERMINAL_BG, False)
        self.cells = [[blank] * cols for _ in range(rows)]
        # What a click on each row opens: (window ID, pane ID), the pane empty on a window's own row.
        self.targets: dict[int, tuple[str, str]] = {}

    def put(self, x, y, text, fg, bg=TERMINAL_BG, bold=False) -> int:
        """Writes text at (x, y), clipped to the canvas; returns the column after it."""
        if 0 <= y < self.rows:
            for character in text:
                if 0 <= x < self.cols:
                    self.cells[y][x] = (character, fg, bg, bold)
                x += 1
        return x

    def fill(self, x, y, width, bg) -> None:
        self.put(x, y, " " * width, TERMINAL_FG, bg)

    def text(self, y: int) -> str:
        return "".join(cell[0] for cell in self.cells[y])

    def to_ansi(self) -> str:
        out = []
        previous = None
        for y, row in enumerate(self.cells):
            out.append(f"\x1b[{y + 1};1H")
            for character, fg, bg, bold in row:
                if (fg, bg, bold) != previous:
                    previous = (fg, bg, bold)
                    out.append("\x1b[0m" + ("\x1b[1m" if bold else ""))
                    out.append(sgr(fg, 38) + sgr(bg, 48))
                out.append(character)
        out.append("\x1b[0m")
        return "".join(out)


def sgr(colour: str, base: int) -> str:
    # The terminal's own colours draw as default (SGR 39 and 49), so Ghostty's background opacity still applies.
    if (base, colour) in ((38, TERMINAL_FG), (48, TERMINAL_BG)):
        return f"\x1b[{base + 1}m"
    red, green, blue = (int(colour[i : i + 2], 16) for i in (1, 3, 5))
    return f"\x1b[{base};2;{red};{green};{blue}m"


def fit(text: str, width: int) -> str:
    if width <= 0:
        return ""
    return text if len(text) <= width else text[: width - 1] + ELLIPSIS


def icon(pane: Pane, on_cyan: bool) -> tuple[str, str]:
    """A Claude pane's traffic-light dot, or the icon of the program running in the pane."""
    if pane.state:
        return DOT, (DOT_ON_CYAN if on_cyan else DOT_ON_DARK)[pane.state]
    glyph = PROGRAM_ICONS.get(pane.command, OTHER_ICON)
    return glyph, FOCUSED_TAB_DIM if on_cyan else STATUS_FG


class RowPainter:
    """Paints the rows of one window: cyan when it is the open window, grey under the cursor."""

    def __init__(self, c: Canvas, view: View, window: Window):
        self.c = c
        self.on_cyan = window.id == view.open_window
        self.under_cursor = view.focused and window.id == view.cursor
        if self.on_cyan:
            self.bg = FOCUSED_TAB_BG
        else:
            self.bg = CURSOR_BG if self.under_cursor else TERMINAL_BG
        self.trunk_fg = FOCUSED_TAB_DIM if self.on_cyan else DIMMER
        self.secondary_fg = FOCUSED_TAB_DIM if self.on_cyan else DIM

    def start(self, y: int, trunk: str, index: str = "") -> None:
        """Starts a row with its piece of the session's trunk, the line between numbers and names."""
        self.c.fill(0, y, self.c.cols, self.bg)
        if self.under_cursor:
            bar = CURSOR_ON_CYAN if self.on_cyan else FOCUSED_TAB_BG
            self.c.put(0, y, "▌", bar, self.bg)
        if index:
            fg = FOCUSED_TAB_FG if self.on_cyan else STATUS_FG
            self.c.put(INDEX_X, y, f"{index:>2}", fg, self.bg)
        self.c.put(TRUNK_X, y, trunk, self.trunk_fg, self.bg)

    def name(self, x: int, y: int, text: str) -> None:
        if self.on_cyan:
            fg = FOCUSED_TAB_FG
        else:
            fg = TEXT if self.under_cursor else STATUS_FG
        bold = self.on_cyan or self.under_cursor
        self.c.put(x, y, fit(text, self.c.cols - x - 1), fg, self.bg, bold)

    def secondary(self, x: int, y: int, text: str) -> None:
        width = self.c.cols - x - 1
        self.c.put(x, y, fit(text, width), self.secondary_fg, self.bg)

    def icon(self, x: int, y: int, pane: Pane) -> None:
        glyph, fg = icon(pane, self.on_cyan)
        self.c.put(x, y, glyph, fg, self.bg)


@dataclass
class Line:
    """A row of the list: how to draw it, the window it belongs to, so scrolling keeps a window whole, and the
    pane it shows, if any."""

    draw: object
    window_id: str = ""
    pane_id: str = ""


def list_lines(c: Canvas, view: View, sessions: list[Session]) -> list[Line]:
    lines: list[Line] = []
    for s, session in enumerate(sessions):
        if s:
            lines.append(Line(lambda y: None))
        lines.append(Line(lambda y, session=session: draw_header(c, y, session)))
        for w, window in enumerate(session.windows):
            lines += window_lines(c, view, window, w == len(session.windows) - 1)
    return lines


def window_lines(c: Canvas, view: View, window: Window, last: bool) -> list[Line]:
    """The window's name, then one tree line per pane; the window line has no icon, as state belongs to panes."""
    row = RowPainter(c, view, window)

    def name_line(y):
        row.start(y, "│", str(window.index))
        row.name(CONTENT_X, y, window.name)

    lines = [Line(name_line, window.id)]
    for p, pane in enumerate(window.panes):
        last_pane = p == len(window.panes) - 1
        branch = "└─" if last_pane else "├─"
        # The trunk stops at mid-row on the session's last row, level with the last branch beside it.
        trunk = "╵" if last and last_pane else "│"

        def pane_line(y, pane=pane, branch=branch, trunk=trunk):
            row.start(y, trunk)
            row.c.put(CONTENT_X, y, branch, row.trunk_fg, row.bg)
            row.icon(CONTENT_X + 3, y, pane)
            row.secondary(CONTENT_X + 5, y, pane.label)

        lines.append(Line(pane_line, window.id, pane.id))
    return lines


def draw_header(c: Canvas, y: int, session: Session) -> None:
    x = c.put(0, y, f" {session.name} ", SESSION_FG, SESSION_BG, bold=True)
    x = c.put(x, y, POWERLINE_ARROW, SESSION_BG)
    c.put(x + 1, y, "─" * (c.cols - x - 1), DIMMER)


def draw_hints(c: Canvas, y: int) -> None:
    c.put(0, y, "─" * c.cols, DIMMER)
    x = 1
    for key, label in (("j k", "move"), ("⏎", "open"), ("⇥", "pane")):
        x = c.put(x, y + 1, key, TEXT, bold=True)
        x = c.put(x, y + 1, f" {label}   ", DIM)


def draw(snapshot: Snapshot, view: View, cols: int, rows: int) -> Canvas:
    c = Canvas(cols, rows)
    footer_rows = 2 if view.focused else 0
    list_rows = rows - footer_rows
    lines = list_lines(c, view, snapshot.sessions)

    # Scroll so the window under the cursor, or the open one, stays in view whole.
    anchor = view.cursor if view.focused else view.open_window
    anchor_rows = [i for i, line in enumerate(lines) if line.window_id == anchor]
    top = 0
    if len(lines) > list_rows and anchor_rows:
        top = max(0, min(anchor_rows[-1] - list_rows + 2, anchor_rows[0] - 1))
        top = min(top, len(lines) - list_rows + 1)
    for row, line in enumerate(lines[top : top + list_rows]):
        line.draw(row)
        if line.window_id:
            c.targets[row] = (line.window_id, line.pane_id)
    hidden_below = max(0, len(lines) - top - list_rows)
    if top:
        c.fill(0, 0, cols, TERMINAL_BG)
        c.put(cols - 12, 0, f"↑ {top} more", DIM)
        c.targets.pop(0, None)
    if hidden_below:
        c.fill(0, list_rows - 1, cols, TERMINAL_BG)
        c.put(cols - 12, list_rows - 1, f"↓ {hidden_below} more", DIM)
        c.targets.pop(list_rows - 1, None)
    if footer_rows:
        draw_hints(c, list_rows)
    return c

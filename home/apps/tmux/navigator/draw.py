"""Drawing the navigator: every session as a header, every window as a line, its panes as a tree below it."""

from dataclasses import dataclass

import links
from model import Branch, Pane, Session, Window

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
# The cursor's bar on the open window, where cyan would vanish.
CURSOR_ON_CYAN = "#ffffff"
LIFTED_BG = "#3a3a3a"  # colour237, a window being dragged
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
TICK = "✓"  # a branch that ended (agents.py), in the read shade, for the linger time
# Most agent rows an expanded workflow shows (Space); a last row counts the rest.
WORKFLOW_ROWS = 20
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
REPOSITORY_ICON = (
    "\uf401"  # nf-oct-repo, before a window's repository at the right edge
)
# A window's title keeps at least this many cells; its repository gives way first, and goes when even this is short.
TITLE_MIN_WIDTH = 10
# Icons by Pane.role: a ticket for the issue board, one cell wide like the rest, where an emoji ticket would take
# two cells in tmux (U+1F3AB) or possibly in Ghostty (U+1F39F, which tmux counts as one); tmux's own for a nested tmux.
ROLE_ICONS = {"issues": "\uf145", "tmux": "\uebc8"}


@dataclass(frozen=True)
class Glyphs:
    """The glyphs the rows draw besides text: a Nerd Font's (NERD_FONT), or PLAIN where the terminal has none."""

    arrow: str  # after a session's name
    programs: dict[str, str]  # a pane's icon by #{pane_current_command}
    other: str  # the icon of any other program
    roles: dict[str, str]  # a pane's icon by Pane.role, ahead of its program's
    repository: str  # before a window's repository


NERD_FONT = Glyphs(
    POWERLINE_ARROW, PROGRAM_ICONS, OTHER_ICON, ROLE_ICONS, REPOSITORY_ICON
)
# For the phone hub, as Termux has no Nerd Font: the session's patch ends square, every pane without Claude Code gets
# a hollow dot (its command is named beside it), and @ comes before the repository, as in the names cc gives windows.
PLAIN = Glyphs("", {}, "○", {}, "@")

# Columns of a window's rows: the cursor's bar, the window number, the session's trunk, then the content.
INDEX_X = 1
TRUNK_X = 3
CONTENT_X = 5


@dataclass
class View:
    open_window: str  # the window the navigator sits in, drawn cyan
    cursor: str  # the window under the cursor
    # The cursor shows only while the navigator has focus.
    focused: bool
    # A window being dragged, drawn raised in the place it would drop into.
    dragging: str = ""
    # The key hints, shown while the navigator has focus once ? has asked for them.
    help: bool = False
    glyphs: Glyphs = NERD_FONT
    # Windows whose workflows list their agents, one row each, rather than a count (Space).
    expanded: frozenset[str] = frozenset()


class Canvas:
    """A grid of cells, each (character, foreground, background, bold, link URL), written out as ANSI."""

    def __init__(self, cols: int, rows: int, rules: list[links.Rule] = ()):
        self.cols, self.rows = cols, rows
        self.rules = rules  # what put_fitted links (links.py)
        blank = (" ", TERMINAL_FG, TERMINAL_BG, False, "")
        self.cells = [[blank] * cols for _ in range(rows)]
        # What a click on each row opens: (window ID, pane ID), the pane empty on a window's own row.
        self.targets: dict[int, tuple[str, str]] = {}

    def put(self, x, y, text, fg, bg=TERMINAL_BG, bold=False, urls=()) -> int:
        """Writes text at (x, y), clipped to the canvas; returns the column after it. urls are the links of the
        first characters, as many as it has."""
        if 0 <= y < self.rows:
            for i, character in enumerate(text):
                if 0 <= x < self.cols:
                    url = urls[i] if i < len(urls) else ""
                    self.cells[y][x] = (character, fg, bg, bold, url)
                x += 1
        return x

    def put_fitted(self, x, y, text, width, fg, bg=TERMINAL_BG, bold=False) -> int:
        """Writes text cut to width (fit), linked as the whole text is, so a cut issue still opens the one it named;
        the ellipsis links nothing."""
        shown = fit(text, width)
        urls = links.urls(text, self.rules)[: len(shown)]
        if shown != text:
            urls = urls[:-1]
        return self.put(x, y, shown, fg, bg, bold, urls)

    def fill(self, x, y, width, bg) -> None:
        self.put(x, y, " " * width, TERMINAL_FG, bg)

    def text(self, y: int) -> str:
        return "".join(cell[0] for cell in self.cells[y])

    def to_ansi(self) -> str:
        out = []
        previous = None
        link = ""
        for y, row in enumerate(self.cells):
            out.append(f"\x1b[{y + 1};1H")
            for character, fg, bg, bold, url in row:
                if url != link:
                    link = url
                    out.append(hyperlink(url))
                if (fg, bg, bold) != previous:
                    previous = (fg, bg, bold)
                    out.append("\x1b[0m" + ("\x1b[1m" if bold else ""))
                    out.append(sgr(fg, 38) + sgr(bg, 48))
                out.append(character)
        if link:
            out.append(hyperlink(""))
        out.append("\x1b[0m")
        return "".join(out)


def sgr(colour: str, base: int) -> str:
    # The terminal's own colours draw as default (SGR 39 and 49), so Ghostty's background opacity still applies.
    if (base, colour) in ((38, TERMINAL_FG), (48, TERMINAL_BG)):
        return f"\x1b[{base + 1}m"
    red, green, blue = (int(colour[i : i + 2], 16) for i in (1, 3, 5))
    return f"\x1b[{base};2;{red};{green};{blue}m"


def hyperlink(url: str) -> str:
    """Starts a link to url (OSC 8), which runs on through cursor moves and SGR resets; an empty url ends it."""
    return f"\x1b]8;;{url}\x1b\\"


def fit(text: str, width: int) -> str:
    if width <= 0:
        return ""
    return text if len(text) <= width else text[: width - 1] + ELLIPSIS


def icon(pane: Pane, on_cyan: bool, glyphs: Glyphs = NERD_FONT) -> tuple[str, str]:
    """A Claude pane's traffic-light dot, or the icon of the program running in the pane."""
    if pane.state:
        return DOT, (DOT_ON_CYAN if on_cyan else DOT_ON_DARK)[pane.state]
    glyph = glyphs.roles.get(pane.role) or glyphs.programs.get(
        pane.command, glyphs.other
    )
    return glyph, FOCUSED_TAB_DIM if on_cyan else STATUS_FG


class RowPainter:
    """Paints the rows of one window: cyan when it is the open window, grey under the cursor."""

    def __init__(self, c: Canvas, view: View, window: Window):
        self.c = c
        self.glyphs = view.glyphs
        lifted = window.id == view.dragging
        self.on_cyan = window.id == view.open_window and not lifted
        self.under_cursor = lifted or (view.focused and window.id == view.cursor)
        if self.on_cyan:
            self.bg = FOCUSED_TAB_BG
        elif lifted:
            self.bg = LIFTED_BG
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

    def name(self, x: int, y: int, text: str, right: str = "") -> None:
        """The window's title from x, and right, dimmed, against the right edge when there is room for both."""
        if self.on_cyan:
            fg = FOCUSED_TAB_FG
        else:
            fg = TEXT if self.under_cursor else STATUS_FG
        bold = self.on_cyan or self.under_cursor
        width = self.c.cols - x - 1
        right_width = min(len(right), width - TITLE_MIN_WIDTH - 1) if right else 0
        if right_width >= len(self.glyphs.repository) + 4:
            shown_width = len(fit(right, right_width))
            title_width = width - shown_width - 1
            self.c.put_fitted(
                self.c.cols - 1 - shown_width,
                y,
                right,
                right_width,
                self.secondary_fg,
                self.bg,
            )
        else:
            title_width = width
        self.c.put_fitted(x, y, text, title_width, fg, self.bg, bold)

    def secondary(self, x: int, y: int, text: str) -> None:
        width = self.c.cols - x - 1
        self.c.put_fitted(x, y, text, width, self.secondary_fg, self.bg)

    def icon(self, x: int, y: int, pane: Pane) -> None:
        glyph, fg = icon(pane, self.on_cyan, self.glyphs)
        self.c.put(x, y, glyph, fg, self.bg)

    def branch(self, x: int, y: int, branch: Branch) -> None:
        """A branch's dot (its tick once ended) at x, its label after it, and a workflow's progress against the right
        edge when there is room for both."""
        if branch.kind != "more":
            dots = DOT_ON_CYAN if self.on_cyan else DOT_ON_DARK
            glyph, state = (DOT, "working") if branch.running else (TICK, "read")
            self.c.put(x, y, glyph, dots[state], self.bg)
        x += 2
        width = self.c.cols - x - 1
        detail = branch.detail
        # A workflow's name matters more than its phase: when both do not fit, only its count stays.
        if len(branch.label) + 1 + len(detail) > width:
            detail = detail.rpartition(" ")[2]
        if detail and width - len(detail) - 1 >= TITLE_MIN_WIDTH:
            width -= len(detail) + 1
            self.c.put(
                self.c.cols - 1 - len(detail), y, detail, self.secondary_fg, self.bg
            )
        self.c.put_fitted(x, y, branch.label, width, self.secondary_fg, self.bg)


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
        lines.append(
            Line(lambda y, session=session: draw_header(c, y, session, view.glyphs))
        )
        for w, window in enumerate(session.windows):
            lines += window_lines(c, view, window, w == len(session.windows) - 1)
    return lines


def window_lines(c: Canvas, view: View, window: Window, last: bool) -> list[Line]:
    """The window's name, then one tree line per pane, each followed by its branches (agents.py); the window line has
    no icon, as state belongs to panes. A row of a pane's branch opens that pane."""
    row = RowPainter(c, view, window)

    def name_line(y, trunk):
        row.start(y, trunk, str(window.index))
        repository = (
            f"{view.glyphs.repository} {window.repository}" if window.repository else ""
        )
        row.name(CONTENT_X, y, window.title, repository)

    drawers = [(name_line, "")]
    for p, pane in enumerate(window.panes):
        last_pane = p == len(window.panes) - 1

        def pane_line(y, trunk, pane=pane, last_pane=last_pane):
            row.start(y, trunk)
            row.c.put(CONTENT_X, y, "└─" if last_pane else "├─", row.trunk_fg, row.bg)
            row.icon(CONTENT_X + 3, y, pane)
            row.secondary(CONTENT_X + 5, y, pane.label)

        drawers.append((pane_line, pane.id))
        expanded = window.id in view.expanded
        for guides, last_branch, branch in branch_rows(pane.branches, expanded):

            def branch_line(
                y, trunk, guides=guides, last_branch=last_branch, branch=branch
            ):
                row.start(y, trunk)
                # Guides: the pane's own line down to the panes after it, then one per level above this branch.
                for level, more in enumerate((not last_pane,) + guides):
                    if more:
                        row.c.put(CONTENT_X + 3 * level, y, "│", row.trunk_fg, row.bg)
                x = CONTENT_X + 3 * (len(guides) + 1)
                row.c.put(x, y, "└─" if last_branch else "├─", row.trunk_fg, row.bg)
                row.branch(x + 3, y, branch)

            drawers.append((branch_line, pane.id))
    # The trunk stops at mid-row on the session's last row, level with the last branch beside it.
    lines = []
    for index, (drawer, pane_id) in enumerate(drawers):
        trunk = "╵" if last and index == len(drawers) - 1 else "│"
        lines.append(
            Line(
                lambda y, drawer=drawer, trunk=trunk: drawer(y, trunk),
                window.id,
                pane_id,
            )
        )
    return lines


def branch_rows(
    branches: list[Branch], expanded: bool, guides: tuple[bool, ...] = ()
) -> list[tuple[tuple[bool, ...], bool, Branch]]:
    """Each branch in tree order, with a guide per level above it (whether a sibling follows there) and whether it is
    the last of its own siblings. A workflow lists its agents only when expanded, at most WORKFLOW_ROWS of them.
    """
    rows = []
    for index, branch in enumerate(branches):
        last = index == len(branches) - 1
        rows.append((guides, last, branch))
        children = branch.children
        if branch.kind == "workflow":
            children = children if expanded else []
            if len(children) > WORKFLOW_ROWS:
                hidden = len(children) - WORKFLOW_ROWS + 1
                more = Branch("more", "", f"{ELLIPSIS} {hidden} more", False)
                children = children[: WORKFLOW_ROWS - 1] + [more]
        rows += branch_rows(children, expanded, guides + (not last,))
    return rows


def draw_header(c: Canvas, y: int, session: Session, glyphs: Glyphs) -> None:
    x = c.put(0, y, f" {session.name} ", SESSION_FG, SESSION_BG, bold=True)
    x = c.put(x, y, glyphs.arrow, SESSION_BG)
    c.put(x + 1, y, "─" * (c.cols - x - 1), DIMMER)


HINTS = [
    [("j k", "move"), ("⏎", "open"), ("⇥", "pane"), ("?", "hide")],
    [("⇧↑ ⇧↓", "reorder"), ("1-9", "jump")],
    [("space", "workflow agents")],
]


def draw_hints(c: Canvas, y: int, lines: list[list[tuple[str, str]]]) -> None:
    c.put(0, y, "─" * c.cols, DIMMER)
    for row, hints in enumerate(lines, 1):
        x = 1
        for key, label in hints:
            x = c.put(x, y + row, key, TEXT, bold=True)
            x = c.put(x, y + row, f" {label}  ", DIM)


def draw(
    sessions: list[Session],
    view: View,
    cols: int,
    rows: int,
    rules: list[links.Rule] = (),
    hints: list[list[tuple[str, str]]] | None = None,
) -> Canvas:
    """The list, with the key hints at the foot: HINTS once ? has asked for them, or hints, always, when given."""
    c = Canvas(cols, rows, rules)
    if hints is None:
        hints = HINTS if view.focused and view.help else []
    footer_rows = 1 + len(hints) if hints else 0
    list_rows = rows - footer_rows
    lines = list_lines(c, view, sessions)

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
        draw_hints(c, list_rows, hints)
    return c

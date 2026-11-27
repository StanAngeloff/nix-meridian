"""What the navigator shows: every window of every session, read from one tmux call:
`list-panes -a`, then `list-windows -a` for the section headers."""

import re
from dataclasses import dataclass, field, replace

import layout

# The window rollup order of claude-state.conf: blocked > working > unread > read.
STATE_ORDER = ["blocked", "working", "unread", "read"]

# claude-state.conf's per-pane verdicts, from @claude-pane-verdict.
VERDICT_STATES = {"B": "blocked", "W": "working", "U": "unread", "R": "read"}

# The navigator and its placeholders are recognised by the command tmux started them with, which is fixed when the
# pane is created; a pane option set afterwards would leave a moment in which a new placeholder looks like any pane.
# Both run from the tmux-navigator package (package.nix), so their start commands contain its bin directory.
COLUMN_MARKER = "/bin/tmux-navigator"

# cc names a window <repository>@<session>[<keyword>] (home/apps/claude-code/initialize.zsh): the keyword is the name
# its owner gave the work, and a rename by hand may put a space before the bracket.
CC_WINDOW_NAME = re.compile(
    r"(?P<repository>[^@\s]+)@(?P<session>[^\s\[\]]+)(?:\s*\[(?P<keyword>[^\]]+)\])?"
)

FIELD_SEPARATOR = "\x1f"
FIELDS = [
    "session_name",
    "session_group",
    "window_id",
    "window_index",
    "window_name",
    "pane_id",
    "pane_active",
    "E:@claude-pane-verdict",
    "pane_current_command",
    "pane_current_path",
    "pane_title",
    "pane_start_command",
    "pane_floating_flag",
    "@issues-board",
    "pane_pid",
    "window_layout",
    "pane_last",
]
PANES_FORMAT = FIELD_SEPARATOR.join("#{" + name + "}" for name in FIELDS)
# A window option: a section header's colour, a name in draw.SECTION_HUES; the section is grey without it.
SECTION_COLOUR = "@navigator-section-colour"
# Each window's section header title, if it is one, whether it is empty, and its colour, read with list-windows:
# the emptiness takes a pane loop, and in a list-panes format a pane loop re-sorts the array list-panes walks.
# Both share one static array in tmux 3.8 (sort_get_panes_window), so the listing's rows would repeat.
SECTIONS_FORMAT = FIELD_SEPARATOR.join(
    [
        "#{window_id}",
        "#{E:@navigator-section}",
        "#{E:@navigator-section-empty}",
        "#{" + SECTION_COLOUR + "}",
    ]
)


@dataclass
class Branch:
    """Work a Claude Code session runs beside its own turn, drawn under its pane: a sub-agent, a workflow, or a shell
    started in the background (agents.py)."""

    kind: str  # "agent", "workflow" or "shell"
    key: str  # the same thing from one look to the next: an agent ID, a workflow run, a shell's task
    label: str
    running: bool
    ended_at: float = (
        0.0  # when it ended, in seconds since the epoch; its tick shows for a while after
    )
    detail: str = (
        ""  # a workflow's phase and its done and started agents, as "Verify 1/3"
    )
    children: list["Branch"] = field(default_factory=list)
    stopped: bool = (
        False  # it was stopped rather than finishing; a cross shows instead of the tick
    )


@dataclass
class Pane:
    id: str
    command: str  # #{pane_current_command}
    path: str  # #{pane_current_path}, with ~ for the home directory
    title: str = ""  # #{pane_title}; Claude Code writes its task there
    state: str = ""  # blocked, working, unread or read while Claude Code runs here
    active: bool = False
    # What the pane is when its foreground program does not say: "issues" for the issue board that prefix C-i opens,
    # known by the option issues-toggle.sh sets on it; "tmux" for a pane attached to a tmux of its own, which
    # pane.read_snapshot finds among its processes.
    role: str = ""
    pid: str = ""  # #{pane_pid}, the process tmux started in the pane
    # The group the pane is in, numbered within its window from 1; 0 on its own (layout.py).
    group: int = 0
    last: bool = False  # #{pane_last}: the window's pane used before the active one
    branches: list[Branch] = field(
        default_factory=list
    )  # a Claude Code pane's, which agents.Scanner adds

    @property
    def label(self) -> str:
        if self.state:
            return claude_task(self.title)
        if self.role == "issues":
            return "issue board"
        if self.role == "tmux":
            return f"tmux  {self.path}"
        return f"{self.command}  {self.path}"


@dataclass
class Window:
    id: str
    index: int
    name: str
    panes: list[Pane] = field(default_factory=list)
    # A section header's title, which tmux reads in the window's name (@navigator-section in tmux.navigator.conf);
    # empty for any other window. A header is drawn as a band with its title, its panes below it.
    section: str = ""
    # A section header whose one pane is a zsh in the home directory (@navigator-section-empty): that pane is not drawn.
    section_empty: bool = False
    section_colour: str = (
        ""  # a section header's colour (SECTION_COLOUR); grey when empty
    )

    @property
    def title(self) -> str:
        """What the window is called in the navigator: the keyword of a name cc gave it, else its session, else the
        name as it is. The session usually reappears in the title Claude Code gives its pane, just below.
        """
        match = CC_WINDOW_NAME.fullmatch(self.name)
        if match is None:
            return self.name
        return match["keyword"] or match["session"]

    @property
    def repository(self) -> str:
        """The repository of a name cc gave the window, else nothing."""
        match = CC_WINDOW_NAME.fullmatch(self.name)
        return match["repository"] if match else ""


@dataclass
class Session:
    name: str
    windows: list[Window]


@dataclass
class Snapshot:
    sessions: list[Session]
    pane_windows: dict[
        str, str
    ]  # pane ID → window ID, for every pane including the column
    active_panes: set[str]  # the active pane of each window


def claude_task(title: str) -> str:
    """The task in a Claude Code title: "✳ Bump bootvine" when idle, a spinner frame instead of ✳ while working."""
    # A Kitty graphics probe that tmux took for a title; claude-state.conf restores the real one.
    if re.match(r"G[a-zA-Z]=", title):
        return "Claude Code"
    first = title[:1]
    if first in "✳◐◑" or "⠀" <= first <= "⣿":
        title = title[1:].lstrip()
    return title or "Claude Code"


def is_column(start_command: str) -> bool:
    return COLUMN_MARKER in start_command


def parse(text: str, home: str) -> Snapshot:
    """Every window of every session, once per session group and under the group's name.

    The sessions of a group share their windows: the phone hub's remote session is grouped with default.
    The navigator, its placeholders and floating panes are left out, and so is a window with nothing else in it.
    A window's panes come in the order tmux lays them out, top left first, each with its group.
    An empty section header keeps its pane, which the navigator does not draw.
    text has the lines of PANES_FORMAT and those of SECTIONS_FORMAT.
    """
    sessions: dict[str, Session] = {}
    session_of_group: dict[str, str] = {}
    pane_windows: dict[str, str] = {}
    active_panes: set[str] = set()
    layouts: dict[str, str] = {}
    columns: dict[str, set[str]] = {}
    boards: dict[str, set[str]] = {}
    lines = [line.split(FIELD_SEPARATOR) for line in text.splitlines()]
    sections = {fields[0]: fields[1:] for fields in lines if len(fields) == 4}
    for fields in lines:
        if len(fields) != len(FIELDS):
            continue
        (
            session_name,
            group,
            window_id,
            window_index,
            window_name,
            pane_id,
            active,
            verdict,
            command,
            path,
            title,
            start_command,
            floating,
            issues_board,
            pid,
            window_layout,
            last,
        ) = fields
        pane_windows[pane_id] = window_id
        layouts.setdefault(window_id, window_layout)
        if is_column(start_command):
            columns.setdefault(window_id, set()).add(pane_id)
        if issues_board == "1":
            boards.setdefault(window_id, set()).add(pane_id)
        if active == "1":
            active_panes.add(pane_id)
        group = group or session_name
        if session_of_group.setdefault(group, session_name) != session_name:
            continue
        # Floating panes come and go over a window, like the prefix w switcher or the tig float, and are not listed.
        if is_column(start_command) or floating == "1":
            continue
        session = sessions.setdefault(group, Session(group, []))
        if not session.windows or session.windows[-1].id != window_id:
            section, empty, colour = sections.get(window_id, ("", "0", ""))
            window = Window(window_id, int(window_index), window_name)
            window.section, window.section_empty = section, empty == "1"
            window.section_colour = colour
            session.windows.append(window)
        if path == home or path.startswith(home + "/"):
            path = "~" + path[len(home) :]
        state = VERDICT_STATES.get(verdict, "")
        role = "issues" if issues_board == "1" else ""
        pane = Pane(pane_id, command, path, title, state, active == "1", role, pid)
        pane.last = last == "1"
        session.windows[-1].panes.append(pane)
    for session in sessions.values():
        for window in session.windows:
            read = layout.read(
                layouts[window.id],
                columns.get(window.id, set()),
                boards.get(window.id, set()),
            )
            if read:
                arrange(window, read.arrangement)
    return Snapshot(
        [session for session in sessions.values() if session.windows],
        pane_windows,
        active_panes,
    )


def arrange(window: Window, arrangement: layout.Arrangement) -> None:
    """Puts the window's panes in the arrangement's order and numbers their groups; a pane it does not have goes last."""
    order, groups = {}, {}
    for number, item in enumerate(arrangement.items, 1):
        for pane_id in item:
            order[pane_id] = len(order)
            groups[pane_id] = number if len(item) > 1 else 0
    window.panes.sort(key=lambda pane: order.get(pane.id, len(order)))
    for pane in window.panes:
        pane.group = groups.get(pane.id, 0)


def current_pane(window: Window) -> Pane | None:
    """The pane you are in: the window's active pane, or, while the navigator or a floating pane has focus, the pane
    used before it, which Tab and Esc in the navigator go back to (control.leave); None when that is not listed either.
    """
    return next((pane for pane in window.panes if pane.active), None) or next(
        (pane for pane in window.panes if pane.last), None
    )


def claude_pane(window: Window) -> Pane | None:
    """The window's Claude Code pane: the active one when it runs Claude Code, else the first that does."""
    claude = [pane for pane in window.panes if pane.state]
    return next((pane for pane in claude if pane.active), claude[0] if claude else None)


def reordered(
    sessions: list[Session], window_id: str, position: int, base_index: int
) -> list[Session]:
    """The sessions with the window moved to position in its session's list, its windows numbered from base_index
    as tmux numbers them after a move-window -r: what a drop in the navigator would leave.
    """
    result = []
    for session in sessions:
        moving = next((w for w in session.windows if w.id == window_id), None)
        if moving is None:
            result.append(session)
            continue
        others = [w for w in session.windows if w.id != window_id]
        windows = others[:position] + [moving] + others[position:]
        numbered = [replace(w, index=base_index + i) for i, w in enumerate(windows)]
        result.append(Session(session.name, numbered))
    return result


def window_order(sessions: list[Session]) -> list[str]:
    return [window.id for session in sessions for window in session.windows]


def session_of(sessions: list[Session], window_id: str) -> Session | None:
    return next(
        (s for s in sessions if any(w.id == window_id for w in s.windows)), None
    )

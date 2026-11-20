"""What a Claude Code session runs beside its own turn, drawn under its pane: sub-agents (nested up to MAX_DEPTH),
workflows, and shells started in the background.

All of it comes from what Claude Code itself writes as it goes (2.1.325), not from hooks, whose sub-agent events are
lossy, nor from the screen:
- ~/.claude/sessions/<pid>.json, named by the PID of the Claude Code process: sessionId, status ("busy" or "idle"),
  statusUpdatedAt (when that began) and startedAt.
- The session's directory, ~/.claude/projects/<slug>/<sessionId>/ (in the bubble's state overlay for a project other
  than the one it was launched in), beside its transcript, <sessionId>.jsonl:
  - subagents/agent-<id>.meta.json and agent-<id>.jsonl for every Agent call and fork. A background agent's meta gains
    "finished" (or "stoppedByUser") when it ends; a foreground one has ended when its transcript ends its turn.
  - subagents/workflows/<run>/journal.jsonl, appended as a workflow's agents start and return; workflows/scripts/
    <name>-<run>.js, written as the run starts; workflows/<run>.json, written only once it has ended.
- A shell in the background is a child of the Claude Code process writing to tasks/<id>.output, as the shell of a
  foreground Bash call does too; the transcript records the background one's ID as backgroundTaskId.

Every look is bounded: a JSON file is parsed again only when its size or modification time changed, a transcript or a
journal is read from where the last look ended (or near its end, the first time), and nothing is written.
"""

import json
import os
import re
from dataclasses import dataclass, field

import processes
from model import Branch, Session

# Claude Code's process as /proc names it: .claude-unwrapped, cut to 15 characters.
CLAUDE_COMMAND = ".claude-unwrapp"
MAX_DEPTH = 3  # sub-agents nested deeper are not drawn
# Of an agent's transcript, read when it changes: where the end of its turn, or the call that spawned a child, is.
TAIL_BYTES = 64 * 1024
# Of a session's transcript, read the first time: recent enough for the shells it put in the background this turn.
FIRST_LOOK_BYTES = 1024 * 1024
# The most of what a growing file gained that one look reads; anything older is skipped.
APPENDED_LIMIT = 4 * 1024 * 1024
FIND_AGAIN_SECONDS = (
    10.0  # how long before a session directory not found yet is looked for again
)
SPAWN_LOOKS = 5  # how many looks a nested agent's parent is searched for before it hangs under the session

BACKGROUND_TASK = re.compile(r'"backgroundTaskId"\s*:\s*"(\w+)"')
TASK_OUTPUT = re.compile(r"/tasks/(\w+)\.output$")
LABEL_WIDTH = 60  # of a shell's command
SHELLS = {"bash", "sh", "zsh", "dash"}
# Programs that start the real command in a child of their own: bwrap's sandbox (Plannotator runs in one), a timeout,
# setsid. A shell's label is the command below them.
WRAPPERS = {"bwrap", "timeout", "setsid"}


def signature(path: str) -> tuple[int, int] | None:
    """What changes when a file does: its modification time and size."""
    try:
        status = os.stat(path)
    except OSError:
        return None
    return status.st_mtime_ns, status.st_size


def modified(path: str) -> float:
    found = signature(path)
    return found[0] / 1e9 if found else 0.0


class Files:
    """JSON files, parsed again only when they change; one half written keeps what it said last."""

    def __init__(self):
        self.parsed: dict[str, tuple[tuple[int, int], object]] = {}

    def json(self, path: str):
        found = signature(path)
        if found is None:
            self.parsed.pop(path, None)
            return None
        cached = self.parsed.get(path)
        if cached and cached[0] == found:
            return cached[1]
        try:
            with open(path, "rb") as handle:
                value = json.loads(handle.read())
        except (OSError, ValueError):
            return cached[1] if cached else None
        self.parsed[path] = (found, value)
        return value


def read_tail(path: str, limit: int = TAIL_BYTES) -> list[str]:
    """The whole lines among the last limit bytes of a file."""
    try:
        with open(path, "rb") as handle:
            size = handle.seek(0, os.SEEK_END)
            start = max(0, size - limit)
            handle.seek(start)
            data = handle.read(size - start)
    except OSError:
        return []
    if start:
        data = data.partition(b"\n")[2]
    return data.decode(errors="replace").splitlines()


class Appended:
    """The whole lines a file that only grows has gained since the last look; the first look starts first_bytes from
    its end."""

    def __init__(self, path: str, first_bytes: int):
        self.path, self.first_bytes = path, first_bytes
        self.offset: int | None = None
        self.rest = b""  # the start of a line not finished yet

    def lines(self) -> list[str]:
        found = signature(self.path)
        if found is None:
            return []
        size = found[1]
        skip_partial = False
        if self.offset is None or size < self.offset:
            self.offset, self.rest = max(0, size - self.first_bytes), b""
            skip_partial = self.offset > 0
        if size - self.offset > APPENDED_LIMIT:
            self.offset, self.rest, skip_partial = size - APPENDED_LIMIT, b"", True
        if size == self.offset:
            return []
        try:
            with open(self.path, "rb") as handle:
                handle.seek(self.offset)
                data = handle.read(size - self.offset)
        except OSError:
            return []
        self.offset += len(data)
        data = self.rest + data
        if skip_partial:
            data = data.partition(b"\n")[2]
        complete, _, self.rest = data.rpartition(b"\n")
        return complete.decode(errors="replace").splitlines()


def parsed(lines: list[str]):
    for line in lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict):
            yield entry


def turn_ended(lines: list[str]) -> bool:
    """Whether an agent's transcript ends its turn: its last assistant message stops for good, or only hands back a
    workflow agent's StructuredOutput."""
    for entry in reversed(list(parsed(lines))):
        if entry.get("type") != "assistant":
            continue
        message = entry.get("message") or {}
        if message.get("stop_reason") in ("end_turn", "stop_sequence"):
            return True
        content = message.get("content") or []
        tools = [
            part.get("name")
            for part in content
            if isinstance(part, dict) and part.get("type") == "tool_use"
        ]
        return tools == ["StructuredOutput"]
    return False


def find_claude(pid: str, root: str) -> str:
    """The Claude Code process at or below pid, else nothing."""
    pending, seen = [pid], set()
    while pending:
        current = pending.pop(0)
        if not current or current in seen:
            continue
        seen.add(current)
        if processes.command_name(current, root) == CLAUDE_COMMAND:
            return current
        pending += processes.children(current, root)
    return ""


BOOT_TIMES: dict[str, int] = {}  # by /proc root


def boot_time(root: str) -> int:
    if root not in BOOT_TIMES:
        with open(f"{root}/stat") as handle:
            BOOT_TIMES[root] = next(
                int(line.split()[1]) for line in handle if line.startswith("btime ")
            )
    return BOOT_TIMES[root]


def process_start(pid: str, root: str) -> float:
    """When the process started, in seconds since the epoch; 0 when it is gone."""
    try:
        with open(f"{root}/{pid}/stat") as handle:
            fields = handle.read().rpartition(")")[2].split()
        boot = boot_time(root)
    except (OSError, StopIteration, ValueError):
        return 0.0
    # starttime is the 22nd field of stat, the 20th after the command's closing parenthesis, in clock ticks since boot.
    return boot + int(fields[19]) / os.sysconf("SC_CLK_TCK")


def task_id(pid: str, root: str) -> str:
    """The task whose output file the process writes to, as Claude Code's shells do, else nothing."""
    try:
        target = os.readlink(f"{root}/{pid}/fd/1")
    except OSError:
        return ""
    match = TASK_OUTPUT.search(target)
    return match[1] if match else ""


def command_of(pid: str, root: str, depth: int = 0) -> str:
    """The command a process runs, seen through WRAPPERS to the program they started."""
    children = processes.children(pid, root)
    if processes.command_name(pid, root) in WRAPPERS and children and depth < 4:
        return command_of(children[0], root, depth + 1)
    return command_line(pid, root)


def command_line(pid: str, root: str) -> str:
    try:
        with open(f"{root}/{pid}/cmdline", "rb") as handle:
            arguments = handle.read().decode(errors="replace").split("\0")
    except OSError:
        return ""
    arguments = [argument for argument in arguments if argument]
    if not arguments:
        return ""
    text = " ".join([os.path.basename(arguments[0])] + arguments[1:])
    return text[:LABEL_WIDTH]


@dataclass
class Agent:
    id: str
    label: str
    depth: int  # its spawnDepth: 1 for the session's own, 2 for one an agent spawned
    background: bool
    tool_use_id: str  # the call that spawned it, in its parent's transcript
    started_at: float  # when its meta was written, as it was spawned
    parent: str | None = (
        None  # the agent that spawned it; "" for the session; None while not found yet
    )
    parent_looks: int = 0
    running: bool = True
    ended_at: float = 0.0
    transcript: tuple[int, int] | None = (
        None  # its transcript's signature when last read
    )


@dataclass
class WorkflowRun:
    run: str
    name: str
    journal: Appended
    agents: dict[str, list] = field(
        default_factory=dict
    )  # ID → [label, running, ended_at]
    phase: str = ""
    ended_at: float = 0.0  # 0 while it runs


@dataclass
class Shell:
    label: str
    running: bool = True
    ended_at: float = 0.0


@dataclass
class SessionState:
    session_id: str
    started_at: (
        float  # of the Claude Code process; anything older belongs to an earlier one
    )
    directory: str = ""
    looked_for_at: float = 0.0
    files: Files = field(default_factory=Files)
    transcript: Appended | None = None
    background_ids: set[str] = field(default_factory=set)
    agents: dict[str, Agent] = field(default_factory=dict)
    ignored: set[str] = field(
        default_factory=set
    )  # agents and runs from before started_at
    agents_listed: tuple[int, int] | None = None
    workflows: dict[str, WorkflowRun] = field(default_factory=dict)
    workflows_listed: tuple[int, int] | None = None
    shells: dict[str, Shell] = field(default_factory=dict)


class Scanner:
    """Gives each Claude Code pane its branches, from one look a second; it keeps what it found between looks, so a
    branch that ended keeps its tick for the linger time and nothing unchanged is read twice.
    """

    def __init__(self, home: str, proc_root: str = "/proc", state_home: str = ""):
        self.claude_root = f"{home}/.claude"
        state_home = (
            state_home or os.environ.get("XDG_STATE_HOME") or f"{home}/.local/state"
        )
        self.overlay_root = f"{state_home}/claude-cc/projects"
        self.proc_root = proc_root
        self.claude_pids: dict[str, str] = {}  # pane process → its Claude Code process
        self.records = Files()  # ~/.claude/sessions/<pid>.json, by path
        self.sessions: dict[str, SessionState] = (
            {}
        )  # by Claude Code process and session
        self.last: dict[str, list[Branch]] = (
            {}
        )  # by pane process, for a look that fails

    def attach(self, sessions: list[Session], now: float, linger: float) -> None:
        """Gives every Claude Code pane in sessions its branches; forgets the sessions no pane runs any more."""
        live: set[str] = set()
        for session in sessions:
            for window in session.windows:
                for pane in window.panes:
                    if not pane.state or not pane.pid:
                        continue
                    try:
                        pane.branches = self.branches(pane.pid, now, linger, live)
                    except (
                        Exception
                    ):  # an unexpected file must never take the navigator down
                        pane.branches = self.last.get(pane.pid, [])
                    self.last[pane.pid] = pane.branches
        for key in list(self.sessions):
            if key not in live:
                del self.sessions[key]
        panes = {
            pane.pid
            for session in sessions
            for window in session.windows
            for pane in window.panes
        }
        for pid in list(self.last):
            if pid not in panes:
                del self.last[pid]
                self.claude_pids.pop(pid, None)

    def branches(
        self, pane_pid: str, now: float, linger: float, live: set[str]
    ) -> list[Branch]:
        claude_pid = self.claude_pid(pane_pid)
        if not claude_pid:
            return []
        record = self.records.json(f"{self.claude_root}/sessions/{claude_pid}.json")
        if not isinstance(record, dict) or not record.get("sessionId"):
            return []
        key = f"{claude_pid}:{record['sessionId']}"
        live.add(key)
        state = self.sessions.get(key)
        if state is None:
            started_at = float(record.get("startedAt") or 0) / 1000
            state = self.sessions[key] = SessionState(record["sessionId"], started_at)
        if not self.locate(state, now):
            return []
        busy = record.get("status") == "busy"
        # When the current busy spell began; whatever the turn runs in the foreground started after it.
        busy_since = float(record.get("statusUpdatedAt") or 0) / 1000 if busy else now
        self.scan_agents(state, busy, busy_since)
        branches = self.agent_tree(state, now, linger)
        branches += self.scan_workflows(state, now, linger)
        branches += self.scan_shells(state, claude_pid, busy, busy_since, now, linger)
        return branches

    def claude_pid(self, pane_pid: str) -> str:
        known = self.claude_pids.get(pane_pid)
        if known and processes.command_name(known, self.proc_root) == CLAUDE_COMMAND:
            return known
        found = find_claude(pane_pid, self.proc_root)
        self.claude_pids[pane_pid] = found
        return found

    def locate(self, state: SessionState, now: float) -> bool:
        """Finds the session's directory, in the projects directory or the bubble's overlay, at most once in a while."""
        if state.directory:
            return True
        if now - state.looked_for_at < FIND_AGAIN_SECONDS:
            return False
        state.looked_for_at = now
        candidates = [f"{self.claude_root}/projects"]
        try:
            candidates += [
                f"{self.overlay_root}/{bubble}"
                for bubble in os.listdir(self.overlay_root)
            ]
        except OSError:
            pass
        for projects in candidates:
            try:
                slugs = os.listdir(projects)
            except OSError:
                continue
            for slug in slugs:
                directory = f"{projects}/{slug}/{state.session_id}"
                if os.path.isdir(directory) or os.path.exists(directory + ".jsonl"):
                    state.directory = directory
                    state.transcript = Appended(directory + ".jsonl", FIRST_LOOK_BYTES)
                    return True
        return False

    def scan_agents(self, state: SessionState, busy: bool, busy_since: float) -> None:
        directory = f"{state.directory}/subagents"
        listed = signature(directory)
        if listed != state.agents_listed:
            state.agents_listed = listed
            # Claude Code replaces a meta to rewrite it, so a changed listing is also how a background agent that
            # finished shows it was resumed (a child it waited for returned, or it was sent a message).
            for agent in state.agents.values():
                if agent.background and not agent.running:
                    self.update_agent(state, agent, busy, busy_since)
            try:
                names = os.listdir(directory)
            except OSError:
                names = []
            for name in names:
                if not (name.startswith("agent-") and name.endswith(".meta.json")):
                    continue
                agent_id = name[len("agent-") : -len(".meta.json")]
                if agent_id in state.agents or agent_id in state.ignored:
                    continue
                if not self.add_agent(state, agent_id):
                    state.agents_listed = (
                        None  # its meta was half written: list again next look
                    )
        for agent in sorted(state.agents.values(), key=lambda a: a.depth):
            if agent.running:
                self.update_agent(state, agent, busy, busy_since)

    def add_agent(self, state: SessionState, agent_id: str) -> bool:
        path = f"{state.directory}/subagents/agent-{agent_id}"
        started_at = modified(path + ".meta.json")
        if max(started_at, modified(path + ".jsonl")) < state.started_at:
            state.ignored.add(agent_id)
            return True
        meta = state.files.json(path + ".meta.json")
        if not isinstance(meta, dict):
            return False
        depth = meta.get("spawnDepth")
        # Agent team members stay idle on purpose rather than finish, and are not drawn.
        if meta.get("taskKind") == "in_process_teammate" or depth == 0:
            state.ignored.add(agent_id)
            return True
        parent = "" if not isinstance(depth, int) or depth <= 1 else None
        state.agents[agent_id] = Agent(
            agent_id,
            str(meta.get("name") or meta.get("description") or "agent"),
            depth if isinstance(depth, int) and depth > 0 else 1,
            meta.get("requestShape") == "background",
            str(meta.get("toolUseId") or ""),
            started_at,
            # Newer metas name the agent that spawned this one; for older ones it is searched for.
            parent=str(meta.get("parentAgentId") or "") or parent,
        )
        return True

    def update_agent(
        self, state: SessionState, agent: Agent, busy: bool, busy_since: float
    ) -> None:
        path = f"{state.directory}/subagents/agent-{agent.id}"
        if agent.parent is None:
            self.find_parent(state, agent)
        if agent.background:
            meta = state.files.json(path + ".meta.json")
            if not isinstance(meta, dict):
                return
            ended = bool(meta.get("finished") or meta.get("stoppedByUser"))
            agent.running = not ended
            agent.ended_at = modified(path + ".meta.json") if ended else 0.0
            return
        # A foreground agent runs only within its parent's own run: the session's current busy spell, or a running agent.
        parent = state.agents.get(agent.parent or "")
        if parent is not None:
            parent_running = parent.running
        else:
            parent_running = busy and agent.started_at >= busy_since - 1
        transcript = signature(path + ".jsonl")
        ended = False
        if transcript != agent.transcript:
            agent.transcript = transcript
            ended = turn_ended(read_tail(path + ".jsonl"))
        if ended or not parent_running:
            agent.running, agent.ended_at = False, modified(path + ".jsonl")

    def find_parent(self, state: SessionState, agent: Agent) -> None:
        """The running agent one level up whose transcript holds the call that spawned agent; the session when none
        does after a few looks."""
        needle = re.compile(rf'"id"\s*:\s*"{re.escape(agent.tool_use_id)}"')
        for candidate in state.agents.values():
            if candidate.depth != agent.depth - 1 or not agent.tool_use_id:
                continue
            if candidate.started_at > agent.started_at or not (
                candidate.running or candidate.ended_at >= agent.started_at
            ):
                continue
            path = f"{state.directory}/subagents/agent-{candidate.id}.jsonl"
            if any(needle.search(line) for line in read_tail(path)):
                agent.parent = candidate.id
                return
        agent.parent_looks += 1
        if agent.parent_looks >= SPAWN_LOOKS or not agent.tool_use_id:
            agent.parent = ""

    def agent_tree(
        self, state: SessionState, now: float, linger: float
    ) -> list[Branch]:
        nodes = {
            agent.id: Branch(
                "agent", agent.id, agent.label, agent.running, agent.ended_at
            )
            for agent in state.agents.values()
            if agent.depth <= MAX_DEPTH
        }
        roots: list[Branch] = []
        for agent in sorted(state.agents.values(), key=lambda a: (a.started_at, a.id)):
            if agent.id not in nodes:
                continue
            # An agent whose parent was never found hangs under the session.
            parent = nodes.get(agent.parent or "")
            (parent.children if parent else roots).append(nodes[agent.id])
        for root in roots:
            settle(root)
        return shown(roots, now, linger)

    def scan_workflows(
        self, state: SessionState, now: float, linger: float
    ) -> list[Branch]:
        directory = f"{state.directory}/subagents/workflows"
        listed = signature(directory)
        if listed != state.workflows_listed:
            state.workflows_listed = listed
            try:
                runs = os.listdir(directory)
            except OSError:
                runs = []
            for run in runs:
                if run in state.workflows or run in state.ignored:
                    continue
                journal = f"{directory}/{run}/journal.jsonl"
                if (
                    max(modified(journal), modified(f"{directory}/{run}"))
                    < state.started_at
                ):
                    state.ignored.add(run)
                    continue
                state.workflows[run] = WorkflowRun(
                    run,
                    self.workflow_name(state, run),
                    Appended(journal, APPENDED_LIMIT),
                )
        branches = []
        for workflow in state.workflows.values():
            if not workflow.ended_at:
                self.update_workflow(state, workflow, now)
            if workflow.ended_at and now - workflow.ended_at > linger:
                continue
            branches.append(workflow_branch(workflow, now, linger))
        return branches

    def workflow_name(self, state: SessionState, run: str) -> str:
        scripts = f"{state.directory}/workflows/scripts"
        try:
            names = os.listdir(scripts)
        except OSError:
            names = []
        suffix = f"-{run}.js"
        for name in names:
            if name.endswith(suffix):
                return name[: -len(suffix)]
        return "workflow"

    def update_workflow(
        self, state: SessionState, workflow: WorkflowRun, now: float
    ) -> None:
        if workflow.name == "workflow":
            workflow.name = self.workflow_name(state, workflow.run)
        for entry in parsed(workflow.journal.lines()):
            agent_id = str(entry.get("agentId") or "")
            if entry.get("type") == "started" and agent_id:
                workflow.agents[agent_id] = [
                    str(entry.get("label") or "agent"),
                    True,
                    0.0,
                ]
                workflow.phase = str(entry.get("phase") or workflow.phase)
            elif entry.get("type") == "result" and agent_id in workflow.agents:
                workflow.agents[agent_id][1:] = [False, now]
        # The run's own record is written only once it has ended.
        ended = modified(f"{state.directory}/workflows/{workflow.run}.json")
        if ended:
            workflow.ended_at = ended
            for agent in workflow.agents.values():
                if agent[1]:
                    agent[1:] = [False, ended]

    def scan_shells(
        self,
        state: SessionState,
        claude_pid: str,
        busy: bool,
        busy_since: float,
        now: float,
        linger: float,
    ) -> list[Branch]:
        if state.transcript is not None:
            for line in state.transcript.lines():
                state.background_ids.update(BACKGROUND_TASK.findall(line))
        alive: dict[str, str] = {}
        for child in processes.children(claude_pid, self.proc_root):
            task = task_id(child, self.proc_root)
            if task:
                alive[task] = child
        for task, pid in alive.items():
            shell = state.shells.get(task)
            if shell is None:
                # A foreground call's shell lives only within the current busy spell, so one from before it, or any
                # while idle, was started in the background.
                background = (
                    task in state.background_ids
                    or not busy
                    or 0 < process_start(pid, self.proc_root) < busy_since
                )
                if not background:
                    continue
                shell = state.shells[task] = Shell("")
            # The command the shell runs, or the shell itself when it has replaced itself with its one command.
            command = next(
                (
                    command_of(grandchild, self.proc_root)
                    for grandchild in processes.children(pid, self.proc_root)
                ),
                "",
            )
            if (
                not command
                and processes.command_name(pid, self.proc_root) not in SHELLS
            ):
                command = command_of(pid, self.proc_root)
            shell.label = command or shell.label or "shell"
        branches = []
        for task, shell in state.shells.items():
            if shell.running and task not in alive:
                shell.running, shell.ended_at = False, now
            if shell.running or now - shell.ended_at <= linger:
                branches.append(
                    Branch(
                        "shell", task, f"$ {shell.label}", shell.running, shell.ended_at
                    )
                )
        return branches


def settle(branch: Branch) -> None:
    """An agent waits for the agents it started: it reads as running while any of them runs, and keeps its tick for as
    long as theirs."""
    for child in branch.children:
        settle(child)
        branch.running = branch.running or child.running
        branch.ended_at = max(branch.ended_at, child.ended_at)


def shown(branches: list[Branch], now: float, linger: float) -> list[Branch]:
    kept = [b for b in branches if b.running or now - b.ended_at <= linger]
    for branch in kept:
        branch.children = shown(branch.children, now, linger)
    return kept


def workflow_branch(workflow: WorkflowRun, now: float, linger: float) -> Branch:
    """One line for the workflow: its phase and how many of its started agents still run; its agents as children,
    shown only when its window's workflows are expanded (Space), the running ones first.
    """
    running = sum(1 for agent in workflow.agents.values() if agent[1])
    detail = ""
    if not workflow.ended_at:
        detail = f"{workflow.phase} {running}/{len(workflow.agents)}".strip()
    children = [
        Branch("agent", agent_id, label, agent_running, ended_at)
        for agent_id, (label, agent_running, ended_at) in workflow.agents.items()
        if agent_running or now - ended_at <= linger
    ]
    children.sort(key=lambda branch: not branch.running)
    return Branch(
        "workflow",
        workflow.run,
        workflow.name,
        not workflow.ended_at,
        workflow.ended_at,
        detail,
        children,
    )

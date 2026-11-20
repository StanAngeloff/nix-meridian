import json
import os
import tempfile
import unittest

import agents
from model import Pane, Session, Window

TICKS = os.sysconf("SC_CLK_TCK")
BOOT = 1000  # btime in the fake /proc/stat
STARTED = 2000.0  # when the fake Claude Code process started
BUSY_SINCE = 3000.0  # when its current turn began
NOW = 3100.0
LINGER = 30.0


def assistant(stop_reason, *tools):
    content = [
        {"type": "tool_use", "name": tool, "id": f"toolu_{tool}"} for tool in tools
    ]
    if not tools:
        content = [{"type": "text", "text": "done"}]
    return {
        "type": "assistant",
        "message": {"stop_reason": stop_reason, "content": content},
    }


class Fixture(unittest.TestCase):
    """A home with one Claude Code session, process 50 under the pane's shell 40, and a /proc to match."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.home = f"{self.temporary.name}/home"
        self.proc = f"{self.temporary.name}/proc"
        os.makedirs(self.proc)
        with open(f"{self.proc}/stat", "w") as handle:
            handle.write(f"cpu 1 2 3\nbtime {BOOT}\n")
        agents.BOOT_TIMES.clear()
        self.process("40", "zsh", ["50"], started=STARTED - 5)
        self.process("50", agents.CLAUDE_COMMAND, [], started=STARTED)
        self.directory = f"{self.home}/.claude/projects/-repo/S1"
        os.makedirs(f"{self.directory}/subagents")
        self.write(f"{self.directory}.jsonl", "", at=STARTED)
        self.record(status="busy")
        self.scanner = agents.Scanner(self.home, self.proc)

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, path, text, at):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            handle.write(text)
        os.utime(path, (at, at))

    def lines(self, path, entries, at):
        self.write(path, "".join(json.dumps(e) + "\n" for e in entries), at)

    def record(self, status, since=BUSY_SINCE):
        self.write(
            f"{self.home}/.claude/sessions/50.json",
            json.dumps(
                {
                    "sessionId": "S1",
                    "status": status,
                    "statusUpdatedAt": int(since * 1000),
                    "startedAt": int(STARTED * 1000),
                }
            ),
            at=since,
        )

    def process(self, pid, name, child_pids, started, command=None, output=None):
        directory = f"{self.proc}/{pid}"
        os.makedirs(f"{directory}/task/{pid}", exist_ok=True)
        os.makedirs(f"{directory}/fd", exist_ok=True)
        with open(f"{directory}/comm", "w") as handle:
            handle.write(name + "\n")
        with open(f"{directory}/task/{pid}/children", "w") as handle:
            handle.write(" ".join(child_pids) + (" " if child_pids else ""))
        ticks = int((started - BOOT) * TICKS)
        with open(f"{directory}/stat", "w") as handle:
            handle.write(f"{pid} ({name}) S" + " 0" * 18 + f" {ticks} 0 0\n")
        with open(f"{directory}/cmdline", "wb") as handle:
            handle.write("\0".join(command or [name]).encode() + b"\0")
        if output:
            os.symlink(output, f"{directory}/fd/1")

    def gone(self, pid):
        for parent in os.listdir(self.proc):
            children = f"{self.proc}/{parent}/task/{parent}/children"
            if os.path.exists(children):
                with open(children) as handle:
                    kept = [c for c in handle.read().split() if c != pid]
                with open(children, "w") as handle:
                    handle.write(" ".join(kept) + (" " if kept else ""))
        os.rename(f"{self.proc}/{pid}", f"{self.proc}/gone-{pid}")

    def agent(self, agent_id, meta, entries=(), at=BUSY_SINCE + 10):
        path = f"{self.directory}/subagents/agent-{agent_id}"
        self.write(path + ".meta.json", json.dumps(meta), at=at)
        self.lines(path + ".jsonl", entries, at=at)

    def scan(self, now=NOW, linger=LINGER):
        pane = Pane("%1", "claude", "~", "✳ task", "working", pid="40")
        self.scanner.attach(
            [Session("default", [Window("@1", 1, "w", [pane])])], now, linger
        )
        return pane.branches


class SessionTest(Fixture):
    def test_a_pane_without_claude_code_or_a_session_file_has_no_branches(self):
        os.remove(f"{self.home}/.claude/sessions/50.json")
        self.agent("a1", {"description": "work", "requestShape": "background"})
        self.assertEqual(self.scan(), [])

    def test_a_session_in_the_bubbles_overlay_is_found_too(self):
        overlay = f"{self.temporary.name}/state/claude-cc/projects/b1/-other/S1"
        os.makedirs(os.path.dirname(overlay))
        os.rename(self.directory, overlay)
        os.rename(f"{self.directory}.jsonl", f"{overlay}.jsonl")
        self.directory = overlay
        self.scanner = agents.Scanner(
            self.home, self.proc, f"{self.temporary.name}/state"
        )
        self.agent("a1", {"description": "work", "requestShape": "background"})
        self.assertEqual([b.label for b in self.scan()], ["work"])


class AgentTest(Fixture):
    def test_a_background_agent_runs_until_its_meta_says_finished_then_ticks_for_the_linger_time(
        self,
    ):
        meta = {"description": "survey", "requestShape": "background", "spawnDepth": 1}
        self.agent("a1", meta, [assistant("end_turn")])
        [branch] = self.scan()
        self.assertEqual(
            (branch.kind, branch.label, branch.running), ("agent", "survey", True)
        )
        self.write(
            f"{self.directory}/subagents/agent-a1.meta.json",
            json.dumps(meta | {"finished": True}),
            at=NOW,
        )
        [branch] = self.scan(now=NOW + 1)
        self.assertFalse(branch.running)
        self.assertEqual(branch.ended_at, NOW)
        self.assertEqual(self.scan(now=NOW + LINGER + 1), [])

    def test_a_fork_is_called_by_its_name(self):
        self.agent(
            "f1",
            {
                "name": "fix-ctrl-g",
                "description": "prefix Ctrl+G does…",
                "requestShape": "background",
            },
        )
        self.assertEqual(self.scan()[0].label, "fix-ctrl-g")

    def test_a_foreground_agent_runs_until_its_transcript_ends_its_turn(self):
        path = f"{self.directory}/subagents/agent-a2.jsonl"
        self.agent("a2", {"description": "explore"}, [assistant("tool_use", "Read")])
        self.assertTrue(self.scan()[0].running)
        self.lines(path, [assistant("tool_use", "Read"), assistant("end_turn")], at=NOW)
        self.assertFalse(self.scan(now=NOW + 1)[0].running)

    def test_a_workflow_agents_structured_output_ends_its_turn(self):
        self.assertTrue(
            agents.turn_ended([json.dumps(assistant("tool_use", "StructuredOutput"))])
        )
        self.assertFalse(agents.turn_ended([json.dumps(assistant("tool_use", "Bash"))]))
        self.assertFalse(agents.turn_ended(["not json", ""]))

    def test_a_foreground_agent_from_before_the_current_turn_is_over(self):
        self.agent(
            "a3",
            {"description": "old"},
            [assistant("tool_use", "Bash")],
            at=BUSY_SINCE - 60,
        )
        self.assertEqual(self.scan(), [])

    def test_a_foreground_agent_is_over_once_its_session_is_idle(self):
        self.agent(
            "a4",
            {"description": "cut short"},
            [assistant("tool_use", "Bash")],
            at=NOW - 5,
        )
        self.assertTrue(self.scan()[0].running)
        self.record(status="idle", since=NOW)
        self.assertFalse(self.scan(now=NOW + 1)[0].running)

    def test_agents_from_before_the_process_started_and_team_members_are_left_out(self):
        self.agent(
            "old",
            {"description": "resumed", "requestShape": "background"},
            at=STARTED - 100,
        )
        self.agent(
            "mate",
            {
                "description": "teammate",
                "taskKind": "in_process_teammate",
                "spawnDepth": 0,
            },
        )
        self.assertEqual(self.scan(), [])

    def test_a_half_written_meta_is_read_again_on_the_next_look(self):
        path = f"{self.directory}/subagents/agent-a5.meta.json"
        self.agent("a5", {"description": "x", "requestShape": "background"})
        self.write(path, '{"description": "hal', at=BUSY_SINCE + 10)
        self.assertEqual(self.scan(), [])
        self.write(
            path,
            json.dumps({"description": "whole", "requestShape": "background"}),
            at=BUSY_SINCE + 10,
        )
        self.assertEqual([b.label for b in self.scan(now=NOW + 1)], ["whole"])


class NestingTest(Fixture):
    def spawn(self, child, depth, parent, label):
        """An agent of the given depth whose spawning call sits in parent's transcript."""
        tool = f"toolu_{child}"
        self.agent(
            child,
            {
                "description": label,
                "spawnDepth": depth,
                "toolUseId": tool,
                "requestShape": "background",
            },
        )
        if parent:
            spawned = {
                "type": "assistant",
                "message": {
                    "stop_reason": "tool_use",
                    "content": [{"type": "tool_use", "id": tool, "name": "Agent"}],
                },
            }
            path = f"{self.directory}/subagents/agent-{parent}.jsonl"
            with open(path, "a") as handle:
                handle.write(json.dumps(spawned) + "\n")
            os.utime(path, (BUSY_SINCE + 10, BUSY_SINCE + 10))

    def test_nested_agents_hang_under_the_agent_that_spawned_them_down_to_three_levels(
        self,
    ):
        self.spawn("p1", 1, None, "research")
        self.spawn("c1", 2, "p1", "chromium")
        self.spawn("g1", 3, "c1", "nss")
        self.spawn("d1", 4, "g1", "too deep")
        [root] = self.scan()
        self.assertEqual(root.label, "research")
        [child] = root.children
        self.assertEqual(child.label, "chromium")
        [grandchild] = child.children
        self.assertEqual((grandchild.label, grandchild.children), ("nss", []))

    def test_a_meta_that_names_the_parent_agent_links_to_it_directly(self):
        self.agent(
            "p3", {"description": "lead", "spawnDepth": 1, "requestShape": "background"}
        )
        self.agent(
            "c3",
            {
                "description": "helper",
                "spawnDepth": 2,
                "parentAgentId": "p3",
                "requestShape": "background",
            },
        )
        [root] = self.scan()
        self.assertEqual([c.label for c in root.children], ["helper"])

    def test_an_agent_reads_as_running_while_an_agent_it_started_still_runs(self):
        self.agent(
            "p4",
            {
                "description": "lead",
                "spawnDepth": 1,
                "requestShape": "background",
                "finished": True,
            },
            at=NOW - 2,
        )
        self.agent(
            "c4",
            {
                "description": "helper",
                "spawnDepth": 2,
                "parentAgentId": "p4",
                "requestShape": "background",
            },
        )
        [root] = self.scan()
        self.assertTrue(root.running)
        self.assertTrue(root.children[0].running)

    def test_a_background_agent_that_finished_and_is_resumed_runs_again(self):
        meta = {"description": "lead", "requestShape": "background"}
        self.agent("p5", meta | {"finished": True}, at=NOW - 2)
        self.assertFalse(self.scan()[0].running)
        # Claude Code replaces the meta, which shows in its directory's listing.
        path = f"{self.directory}/subagents/agent-p5.meta.json"
        self.write(path + ".new", json.dumps(meta), at=NOW)
        os.replace(path + ".new", path)
        self.assertTrue(self.scan(now=NOW + 1)[0].running)

    def test_an_agent_whose_parent_is_not_found_hangs_under_the_session(self):
        self.spawn("p2", 1, None, "research")
        self.spawn("o2", 2, None, "orphan")
        for look in range(agents.SPAWN_LOOKS):
            branches = self.scan(now=NOW + look)
        self.assertEqual(sorted(b.label for b in branches), ["orphan", "research"])


class WorkflowTest(Fixture):
    def setUp(self):
        super().setUp()
        self.run = f"{self.directory}/subagents/workflows/wf_1"
        self.write(
            f"{self.directory}/workflows/scripts/review-changes-wf_1.js",
            "",
            at=NOW - 20,
        )
        self.journal = [
            {"type": "launched"},
            {
                "type": "started",
                "agentId": "w1",
                "label": "review:bugs",
                "phase": "Review",
            },
            {
                "type": "started",
                "agentId": "w2",
                "label": "review:perf",
                "phase": "Review",
            },
            {"type": "result", "agentId": "w1", "result": "ok"},
        ]
        self.lines(f"{self.run}/journal.jsonl", self.journal, at=NOW - 10)

    def test_one_line_with_its_phase_and_running_out_of_started_agents(self):
        [branch] = self.scan()
        self.assertEqual(
            (branch.kind, branch.label, branch.running),
            ("workflow", "review-changes", True),
        )
        self.assertEqual(branch.detail, "Review 1/2")
        self.assertEqual(
            [(c.label, c.running) for c in branch.children],
            [("review:perf", True), ("review:bugs", False)],
        )

    def test_the_run_ends_when_its_record_is_written(self):
        self.scan()
        self.write(f"{self.directory}/workflows/wf_1.json", "{}", at=NOW + 5)
        [branch] = self.scan(now=NOW + 6)
        self.assertEqual(
            (branch.running, branch.detail, branch.ended_at), (False, "", NOW + 5)
        )
        self.assertTrue(all(not child.running for child in branch.children))
        self.assertEqual(self.scan(now=NOW + 5 + LINGER + 1), [])

    def test_the_journal_is_read_only_where_it_grew(self):
        self.scan()
        self.lines(
            f"{self.run}/journal.jsonl",
            self.journal
            + [
                {
                    "type": "started",
                    "agentId": "w3",
                    "label": "verify",
                    "phase": "Verify",
                }
            ],
            at=NOW,
        )
        [branch] = self.scan(now=NOW + 1)
        self.assertEqual(branch.detail, "Verify 2/3")


class ShellTest(Fixture):
    def background_shell(self, task, started, command=("sleep", "600")):
        output = f"/tmp/claude-1000/-repo/S1/tasks/{task}.output"
        self.process("60", "bash", ["61"], started=started, output=output)
        self.process("61", command[0], [], started=started, command=list(command))
        with open(f"{self.proc}/50/task/50/children", "w") as handle:
            handle.write("60 ")

    def test_a_shell_the_transcript_put_in_the_background_shows_its_command_then_ticks_when_it_exits(
        self,
    ):
        self.background_shell(
            "b1", started=NOW - 5, command=("/nix/store/x-coreutils/bin/sleep", "600")
        )
        self.lines(
            f"{self.directory}.jsonl",
            [{"toolUseResult": {"backgroundTaskId": "b1"}}],
            at=NOW,
        )
        [branch] = self.scan()
        self.assertEqual(
            (branch.kind, branch.label, branch.running), ("shell", "$ sleep 600", True)
        )
        self.gone("60")
        [branch] = self.scan(now=NOW + 2)
        self.assertEqual((branch.running, branch.ended_at), (False, NOW + 2))

    def test_a_shell_that_replaced_itself_with_its_command_is_called_by_that_command(
        self,
    ):
        output = "/tmp/claude-1000/-repo/S1/tasks/b3.output"
        self.process(
            "62",
            "sleep",
            [],
            started=BUSY_SINCE - 100,
            command=["sleep", "90"],
            output=output,
        )
        with open(f"{self.proc}/50/task/50/children", "w") as handle:
            handle.write("62 ")
        self.assertEqual([b.label for b in self.scan()], ["$ sleep 90"])

    def test_the_shell_of_the_current_foreground_call_is_not_drawn(self):
        self.background_shell("f1", started=NOW - 5)
        self.assertEqual(self.scan(), [])

    def test_a_shell_older_than_the_current_turn_or_alive_while_idle_was_backgrounded(
        self,
    ):
        self.background_shell("b2", started=BUSY_SINCE - 100)
        self.assertEqual([b.label for b in self.scan()], ["$ sleep 600"])


class RobustnessTest(Fixture):
    def test_garbage_everywhere_never_raises(self):
        self.write(f"{self.directory}/subagents/agent-x.meta.json", "[1, 2", at=NOW)
        self.write(
            f"{self.directory}/subagents/agent-y.meta.json", '"a string"', at=NOW
        )
        self.write(
            f"{self.directory}/subagents/workflows/wf_9/journal.jsonl",
            "{bad\n[]\n",
            at=NOW,
        )
        self.write(f"{self.home}/.claude/sessions/50.json", "null", at=NOW)
        self.assertEqual(self.scan(), [])

    def test_a_look_that_fails_keeps_the_last_branches(self):
        self.agent("a1", {"description": "work", "requestShape": "background"})
        self.assertEqual(len(self.scan()), 1)
        self.scanner.branches = lambda *arguments: 1 / 0
        self.assertEqual([b.label for b in self.scan()], ["work"])


class AppendedTest(unittest.TestCase):
    def test_only_whole_new_lines_are_returned_and_the_first_look_starts_near_the_end(
        self,
    ):
        with tempfile.TemporaryDirectory() as directory:
            path = f"{directory}/log"
            with open(path, "w") as handle:
                handle.write("old line one\nold line two\n")
            reader = agents.Appended(path, first_bytes=14)
            self.assertEqual(reader.lines(), ["old line two"])
            with open(path, "a") as handle:
                handle.write("new\nhal")
            self.assertEqual(reader.lines(), ["new"])
            with open(path, "a") as handle:
                handle.write("f\n")
            self.assertEqual(reader.lines(), ["half"])
            self.assertEqual(reader.lines(), [])


if __name__ == "__main__":
    unittest.main()

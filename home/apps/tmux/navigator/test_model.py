import unittest

import model
import test_layout

HOME = "/home/someone"
NAVIGATOR = "/nix/store/abc-tmux-navigator/bin/tmux-navigator pane"
PLACEHOLDER = "/nix/store/abc-tmux-navigator/bin/tmux-navigator-placeholder"


def row(
    session="default",
    group="",
    window="@1",
    index="1",
    name="one",
    pane="%1",
    active="1",
    verdict="",
    command="zsh",
    path=HOME,
    title="",
    start="",
    floating="0",
    issues_board="",
    pid="100",
    layout="",
    last="0",
):
    fields = [session, group, window, index, name, pane, active, verdict, command]
    rest = [path, title, start, floating, issues_board, pid, layout, last]
    return model.FIELD_SEPARATOR.join(fields + rest)


class WindowNameTest(unittest.TestCase):
    def title_and_repository(self, name):
        window = model.Window("@1", 1, name)
        return window.title, window.repository

    def test_a_name_cc_gave_shows_its_keyword_and_repository(self):
        self.assertEqual(
            self.title_and_repository("webapp@ticket-101[lint triage]"),
            ("lint triage", "webapp"),
        )
        self.assertEqual(
            self.title_and_repository("nix-meridian@feature-x [DOCS]"),
            ("DOCS", "nix-meridian"),
        )

    def test_without_a_keyword_the_session_is_the_title(self):
        self.assertEqual(
            self.title_and_repository("nix-meridian@x-tmux-tabby"),
            ("x-tmux-tabby", "nix-meridian"),
        )

    def test_any_other_name_stays_as_it_is(self):
        for name in ("webapp", "bold-fox", "a@b c", "@x", "repo@"):
            self.assertEqual(self.title_and_repository(name), (name, ""))


class SectionTest(unittest.TestCase):
    def test_a_window_tmux_calls_a_section_header_carries_its_title(self):
        text = "\n".join(
            [
                row(window="@1", pane="%1", name="-- Work --"),
                row(window="@2", index="2", pane="%2", name="two"),
                model.FIELD_SEPARATOR.join(["@1", "Work", "1"]),
                model.FIELD_SEPARATOR.join(["@2", "", "0"]),
                row(window="@3", index="3", pane="%3", name="-- Cosuno --"),
                model.FIELD_SEPARATOR.join(["@3", "Cosuno", "0"]),
            ]
        )
        windows = model.parse(text, HOME).sessions[0].windows
        self.assertEqual(
            [(w.section, w.section_empty) for w in windows],
            [("Work", True), ("", False), ("Cosuno", False)],
        )
        windows = windows[:2]
        self.assertEqual(
            [(w.name, w.section) for w in windows],
            [("-- Work --", "Work"), ("two", "")],
        )
        self.assertEqual([p.id for p in windows[0].panes], ["%1"])


class ClaudePaneTest(unittest.TestCase):
    def test_the_active_claude_pane_else_the_first_else_none(self):
        shell = model.Pane("%1", "zsh", "~", active=True)
        first = model.Pane("%2", "claude", "~", "✳ a", "read")
        second = model.Pane("%3", "claude", "~", "✳ b", "working", active=True)
        self.assertIs(
            model.claude_pane(model.Window("@1", 1, "w", [first, second])), second
        )
        self.assertIs(
            model.claude_pane(model.Window("@1", 1, "w", [shell, first])), first
        )
        self.assertIsNone(model.claude_pane(model.Window("@1", 1, "w", [shell])))


class CurrentPaneTest(unittest.TestCase):
    def test_the_active_pane_else_the_one_used_before_else_none(self):
        before = model.Pane("%1", "zsh", "~", last=True)
        other = model.Pane("%2", "tig", "~")
        active = model.Pane("%3", "nvim", "~", active=True)
        window = model.Window("@1", 1, "w", [before, other, active])
        self.assertIs(model.current_pane(window), active)
        window.panes = [before, other]
        self.assertIs(model.current_pane(window), before)
        window.panes = [other]
        self.assertIsNone(model.current_pane(window))

    def test_with_the_navigator_focused_it_is_the_pane_used_before(self):
        text = "\n".join(
            [
                row(pane="%1", start=NAVIGATOR, active="1"),
                row(pane="%2", active="0", last="1"),
                row(pane="%3", active="0"),
            ]
        )
        window = model.parse(text, HOME).sessions[0].windows[0]
        self.assertEqual(model.current_pane(window).id, "%2")


class ReorderedTest(unittest.TestCase):
    def test_moves_the_window_and_numbers_its_session_from_the_base(self):
        sessions = [
            model.Session(
                "default", [model.Window(f"@{i}", i + 4, f"w{i}") for i in range(4)]
            ),
            model.Session("other", [model.Window("@9", 7, "x")]),
        ]
        moved = model.reordered(sessions, "@0", 2, 1)
        self.assertEqual(
            [(w.id, w.index) for w in moved[0].windows],
            [("@1", 1), ("@2", 2), ("@0", 3), ("@3", 4)],
        )
        self.assertEqual(moved[1].windows[0].index, 7)
        self.assertEqual(
            sessions[0].windows[0].index, 4
        )  # the snapshot itself is left alone


class ClaudeTaskTest(unittest.TestCase):
    def test_strips_the_idle_and_working_markers(self):
        self.assertEqual(model.claude_task("✳ Bump bootvine"), "Bump bootvine")
        self.assertEqual(model.claude_task("◐ Bump bootvine"), "Bump bootvine")
        self.assertEqual(model.claude_task("⠂ Bump bootvine"), "Bump bootvine")

    def test_a_kitty_probe_or_an_empty_title_reads_as_claude_code(self):
        self.assertEqual(model.claude_task("Gi=31,s=1,v=1,a=q"), "Claude Code")
        self.assertEqual(model.claude_task("✳"), "Claude Code")


class ParseTest(unittest.TestCase):
    def test_reads_windows_and_panes_with_their_state(self):
        text = "\n".join(
            [
                row(pane="%1", verdict="W", command="claude", title="◐ Task"),
                row(pane="%2", active="0", command="tig", path=HOME + "/repo"),
            ]
        )
        snapshot = model.parse(text, HOME)
        (session,) = snapshot.sessions
        (window,) = session.windows
        self.assertEqual([p.id for p in window.panes], ["%1", "%2"])
        self.assertEqual(window.panes[0].state, "working")
        self.assertEqual(window.panes[0].label, "Task")
        self.assertEqual(window.panes[1].label, "tig  ~/repo")
        self.assertEqual(snapshot.active_panes, {"%1"})

    def test_leaves_out_the_navigator_and_placeholders_but_knows_their_windows(self):
        text = "\n".join(
            [
                row(window="@1", pane="%9", start=NAVIGATOR),
                row(window="@1", pane="%1", active="0"),
                row(window="@2", index="2", pane="%8", start=PLACEHOLDER),
                row(window="@2", index="2", pane="%2"),
            ]
        )
        snapshot = model.parse(text, HOME)
        panes = [p.id for w in snapshot.sessions[0].windows for p in w.panes]
        self.assertEqual(panes, ["%1", "%2"])
        self.assertEqual(snapshot.pane_windows["%9"], "@1")
        self.assertIn("%9", snapshot.active_panes)

    def test_the_issue_board_is_named_for_what_it_is(self):
        text = "\n".join([row(pane="%1"), row(pane="%2", issues_board="1")])
        (window,) = model.parse(text, HOME).sessions[0].windows
        self.assertEqual([p.role for p in window.panes], ["", "issues"])
        self.assertEqual(window.panes[1].label, "issue board")

    def test_floating_panes_are_left_out(self):
        text = "\n".join([row(pane="%1"), row(pane="%2", command="tig", floating="1")])
        (window,) = model.parse(text, HOME).sessions[0].windows
        self.assertEqual([p.id for p in window.panes], ["%1"])

    def test_a_window_with_only_its_column_is_left_out(self):
        text = "\n".join(
            [
                row(window="@1", pane="%1"),
                row(window="@2", index="2", pane="%8", start=PLACEHOLDER),
            ]
        )
        (session,) = model.parse(text, HOME).sessions
        self.assertEqual([w.id for w in session.windows], ["@1"])

    def test_a_session_group_shows_once_under_the_group_name(self):
        text = "\n".join(
            [
                row(session="default", group="default", pane="%1"),
                row(session="remote", group="default", pane="%1"),
                row(session="scratch", window="@5", pane="%5"),
            ]
        )
        sessions = model.parse(text, HOME).sessions
        self.assertEqual([s.name for s in sessions], ["default", "scratch"])
        self.assertEqual(len(sessions[0].windows[0].panes), 1)

    def test_panes_come_in_layout_order_with_their_groups(self):
        # The navigator's column, then review 1 above #5, then review 2 above #6; tmux numbered them otherwise.
        spec = ("h", ["%9", ("v", ["%3", "%1"]), ("v", ["%4", "%2"]), "%5"])
        laid_out = test_layout.window(spec)
        text = "\n".join(
            row(pane=pane, start=NAVIGATOR if pane == "%9" else "", layout=laid_out)
            for pane in ("%1", "%2", "%3", "%4", "%5", "%9")
        )
        (window,) = model.parse(text, HOME).sessions[0].windows
        self.assertEqual(
            [(p.id, p.group) for p in window.panes],
            [("%3", 1), ("%1", 1), ("%4", 2), ("%2", 2), ("%5", 0)],
        )

    def test_the_issue_board_is_in_no_group_and_comes_last(self):
        spec = ("h", ["%1", ("v", ["%2", "%3"]), "%8"])
        laid_out = test_layout.window(spec)
        text = "\n".join(
            row(pane=pane, issues_board="1" if pane == "%8" else "", layout=laid_out)
            for pane in ("%8", "%1", "%2", "%3")
        )
        (window,) = model.parse(text, HOME).sessions[0].windows
        self.assertEqual(
            [(p.id, p.group) for p in window.panes],
            [("%1", 0), ("%2", 2), ("%3", 2), ("%8", 0)],
        )

    def test_without_a_layout_panes_keep_tmux_s_order_and_no_groups(self):
        text = "\n".join([row(pane="%2"), row(pane="%1")])
        (window,) = model.parse(text, HOME).sessions[0].windows
        self.assertEqual(
            [(p.id, p.group) for p in window.panes], [("%2", 0), ("%1", 0)]
        )

    def test_home_becomes_a_tilde_only_on_a_path_boundary(self):
        text = "\n".join(
            [
                row(pane="%1", path=HOME),
                row(pane="%2", path=HOME + "-other/x"),
            ]
        )
        panes = model.parse(text, HOME).sessions[0].windows[0].panes
        self.assertEqual([p.path for p in panes], ["~", HOME + "-other/x"])


if __name__ == "__main__":
    unittest.main()

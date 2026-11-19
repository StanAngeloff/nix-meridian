import unittest

import model

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
):
    fields = [session, group, window, index, name, pane, active, verdict, command]
    return model.FIELD_SEPARATOR.join(fields + [path, title, start, floating])


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

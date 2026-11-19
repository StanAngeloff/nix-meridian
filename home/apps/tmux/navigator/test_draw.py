import unittest

import draw
import model
from model import Pane, Session, Window

SESSIONS = [
    Session(
        "default",
        [
            Window("@1", 1, "task", [Pane("%1", "claude", "~", "◐ Do it", "working")]),
            Window(
                "@2",
                2,
                "other",
                [
                    Pane("%2", "claude", "~", "✳ Wait", "blocked"),
                    Pane("%3", "tig", "~/repo"),
                ],
            ),
        ],
    ),
    Session("scratch", [Window("@5", 1, "notes", [Pane("%5", "nvim", "~/notes")])]),
]


def render(cursor="@1", focused=False, rows=14, cols=30, sessions=None, dragging=""):
    view = draw.View(
        open_window="@1", cursor=cursor, focused=focused, dragging=dragging
    )
    return draw.draw(sessions or SESSIONS, view, cols, rows)


class TreeTest(unittest.TestCase):
    def test_windows_branch_into_their_panes_and_the_trunk_ends_each_session(self):
        canvas = render()
        lines = [canvas.text(y).rstrip() for y in range(10)]
        self.assertEqual(lines[1], "  1│ task")
        self.assertTrue(lines[2].startswith("   │ └─ ● Do it"))
        self.assertTrue(lines[4].startswith("   │ ├─ ● Wait"))
        self.assertTrue(lines[5].startswith("   ╵ └─"))
        self.assertIn("tig  ~/repo", lines[5])
        self.assertEqual(lines[6], "")
        self.assertTrue(lines[7].startswith(" scratch "))
        self.assertTrue(lines[9].startswith("   ╵ └─"))

    def test_the_open_window_is_cyan_with_dots_in_the_darker_shade(self):
        canvas = render()
        self.assertEqual(canvas.cells[1][0][2], draw.FOCUSED_TAB_BG)
        self.assertEqual(
            canvas.cells[2][draw.CONTENT_X + 3][1], draw.DOT_ON_CYAN["working"]
        )
        self.assertEqual(
            canvas.cells[4][draw.CONTENT_X + 3][1], draw.DOT_ON_DARK["blocked"]
        )

    def test_long_text_ends_in_an_ellipsis_inside_the_pane(self):
        canvas = render(cols=13)
        self.assertEqual(canvas.text(2).rstrip()[-1], draw.ELLIPSIS)
        self.assertEqual(len(canvas.text(2)), 13)


class IconTest(unittest.TestCase):
    def test_the_issue_board_gets_a_ticket_whatever_shell_runs_it(self):
        board = Pane("%9", "zsh", "~", role="issues")
        self.assertEqual(draw.icon(board, on_cyan=False)[0], draw.ROLE_ICONS["issues"])
        self.assertEqual(draw.icon(Pane("%8", "zsh", "~"), False)[0], draw.SHELL_ICON)

    def test_a_nested_tmux_gets_the_tmux_icon_and_label(self):
        nested = Pane("%7", "bash", "~/work", role="tmux")
        self.assertEqual(draw.icon(nested, on_cyan=False)[0], draw.ROLE_ICONS["tmux"])
        self.assertEqual(nested.label, "tmux  ~/work")


class DragTest(unittest.TestCase):
    def test_a_dragged_window_shows_raised_in_its_new_place_with_the_numbers_after_the_drop(
        self,
    ):
        sessions = model.reordered(SESSIONS, "@1", 1, 1)
        canvas = render(sessions=sessions, dragging="@1", focused=True)
        lines = [canvas.text(y).rstrip() for y in range(6)]
        self.assertEqual(lines[1], "  1│ other")
        self.assertEqual(lines[4], "▌ 2│ task")
        self.assertEqual(canvas.cells[4][2][2], draw.LIFTED_BG)


class NameTest(unittest.TestCase):
    def frame(self, name, cols):
        sessions = [
            Session("default", [Window("@7", 7, name, [Pane("%7", "zsh", "~")])])
        ]
        return render(sessions=sessions, cols=cols)

    def test_the_title_then_the_repository_dimmed_against_the_right_edge(self):
        canvas = self.frame("webapp@ticket-101[lint triage]", 36)
        line = canvas.text(1)
        self.assertTrue(line.startswith("  7│ lint triage "))
        self.assertTrue(line.rstrip().endswith(draw.REPOSITORY_ICON + " webapp"))
        self.assertEqual(canvas.cells[1][34][1], draw.DIM)

    def test_the_repository_gives_way_first_then_goes(self):
        long_title = "webapp@ticket-101[continuous integration monitoring]"
        line = self.frame(long_title, 36).text(1).rstrip()
        self.assertIn("continuous", line)
        self.assertTrue(line.endswith(draw.ELLIPSIS) or "webapp" in line)
        narrow = self.frame(long_title, 20).text(1).rstrip()
        self.assertNotIn(draw.REPOSITORY_ICON, narrow)


class TargetTest(unittest.TestCase):
    def test_rows_map_to_their_window_and_pane_and_headers_to_nothing(self):
        targets = render().targets
        self.assertNotIn(0, targets)
        self.assertEqual(targets[1], ("@1", ""))
        self.assertEqual(targets[2], ("@1", "%1"))
        self.assertEqual(targets[5], ("@2", "%3"))
        self.assertNotIn(6, targets)
        self.assertEqual(targets[9], ("@5", "%5"))

    def test_a_scroll_marker_row_opens_nothing(self):
        targets = render(cursor="@5", focused=True, rows=6).targets
        self.assertNotIn(0, targets)


class FocusTest(unittest.TestCase):
    def test_unfocused_shows_no_cursor_and_no_hints(self):
        canvas = render(cursor="@2")
        self.assertNotIn("move", canvas.text(13))
        self.assertEqual(canvas.cells[3][0][0], " ")

    def test_focused_marks_the_cursor_window_and_shows_hints(self):
        canvas = render(cursor="@2", focused=True)
        self.assertIn("move", canvas.text(13))
        self.assertEqual(
            canvas.cells[3][0][:3], ("▌", draw.FOCUSED_TAB_BG, draw.CURSOR_BG)
        )

    def test_the_cursor_on_the_open_window_has_a_white_bar(self):
        canvas = render(cursor="@1", focused=True)
        self.assertEqual(canvas.cells[1][0][:2], ("▌", draw.CURSOR_ON_CYAN))


class ScrollTest(unittest.TestCase):
    def test_the_cursor_window_stays_in_view(self):
        canvas = render(cursor="@5", focused=True, rows=6)
        shown = [canvas.text(y) for y in range(4)]
        self.assertTrue(any("notes" in line for line in shown))
        self.assertTrue(any("more" in line for line in shown))


if __name__ == "__main__":
    unittest.main()

import unittest

import keys
import model
from keys import Action
from model import Pane, Session, Window


def windows(prefix: str, count: int) -> list[Window]:
    return [
        Window(f"@{prefix}{i}", i, f"{prefix}{i}", [Pane(f"%{prefix}{i}", "zsh", "~")])
        for i in range(1, count + 1)
    ]


SESSIONS = [Session("default", windows("d", 12)), Session("scratch", windows("s", 3))]


def press(*typed: tuple[str, float], start: str = "@d1") -> str:
    cursor = keys.Cursor(window=start)
    for key, at in typed:
        keys.handle_key(cursor, SESSIONS, key, at, {})
    return cursor.window


class DigitTest(unittest.TestCase):
    def test_one_digit_picks_that_window(self):
        self.assertEqual(press(("4", 0.0)), "@d4")

    def test_quick_digits_make_one_number(self):
        self.assertEqual(press(("1", 0.0), ("2", 0.3)), "@d12")

    def test_a_pause_starts_a_new_number(self):
        self.assertEqual(press(("1", 0.0), ("2", 1.5)), "@d2")

    def test_a_number_without_a_window_starts_over_from_the_last_digit(self):
        self.assertEqual(press(("1", 0.0), ("2", 0.3), ("3", 0.6)), "@d3")

    def test_a_digit_without_a_window_leaves_the_cursor(self):
        self.assertEqual(press(("0", 0.0)), "@d1")

    def test_digits_count_in_the_session_under_the_cursor(self):
        self.assertEqual(press(("2", 0.0), start="@s1"), "@s2")


class SectionTest(unittest.TestCase):
    def sessions(self):
        work = Window("@w", 2, "-- Work --", [Pane("%w", "zsh", "~")], section="Work")
        return [Session("default", [*windows("d", 1), work, *windows("e", 3)[2:]])]

    def test_j_and_k_stop_on_a_section_header(self):
        cursor = keys.Cursor(window="@d1")
        keys.handle_key(cursor, self.sessions(), "j", 0.0, {})
        self.assertEqual(cursor.window, "@w")
        keys.handle_key(cursor, self.sessions(), "j", 0.0, {})
        self.assertEqual(cursor.window, "@e3")

    def test_space_on_a_section_colours_it_and_expands_nothing(self):
        cursor = keys.Cursor(window="@w")
        action = keys.handle_key(cursor, self.sessions(), " ", 0.0, {})
        self.assertEqual(action, Action("colour", window="@w"))
        self.assertEqual(cursor.expanded, set())
        cursor = keys.Cursor(window="@d1")
        self.assertIsNone(keys.handle_key(cursor, self.sessions(), " ", 0.0, {}))
        self.assertEqual(cursor.expanded, {"@d1"})

    def test_digits_skip_a_section_header_which_shows_no_number(self):
        cursor = keys.Cursor(window="@d1")
        keys.handle_key(cursor, self.sessions(), "2", 0.0, {})
        self.assertEqual(cursor.window, "@d1")
        keys.handle_key(cursor, self.sessions(), "3", 2.0, {})
        self.assertEqual(cursor.window, "@e3")


class RenameTest(unittest.TestCase):
    def test_r_renames_the_window_under_the_cursor(self):
        cursor = keys.Cursor(window="@d3")
        action = keys.handle_key(cursor, SESSIONS, "r", 0.0, {})
        self.assertEqual(action, Action("rename", window="@d3"))

    def test_r_while_grouping_renames_nothing(self):
        cursor = keys.Cursor(window="@d3", pane="%d3")
        self.assertIsNone(keys.handle_key(cursor, SESSIONS, "r", 0.0, {}))


class MoveTest(unittest.TestCase):
    def test_j_and_k_cross_sessions_and_wrap(self):
        self.assertEqual(press(("j", 0.0), start="@d12"), "@s1")
        self.assertEqual(press(("k", 0.0), start="@d1"), "@s3")
        self.assertEqual(press(("\x1b[B", 0.0), start="@d1"), "@d2")


class ActionTest(unittest.TestCase):
    def test_enter_opens_and_tab_or_escape_leaves(self):
        cursor = keys.Cursor(window="@d1")

        def handle(key):
            return keys.handle_key(cursor, SESSIONS, key, 0.0, {})

        self.assertEqual(handle("\r"), Action("open"))
        self.assertEqual(handle("\t"), Action("leave"))
        self.assertEqual(handle("\x1b"), Action("leave"))
        self.assertIsNone(handle("\x1b[I"))

    def test_question_mark_shows_and_hides_the_hints(self):
        cursor = keys.Cursor(window="@d1")
        keys.handle_key(cursor, SESSIONS, "?", 0.0, {})
        self.assertTrue(cursor.help)
        keys.handle_key(cursor, SESSIONS, "?", 0.0, {})
        self.assertFalse(cursor.help)

    def test_space_expands_the_workflows_of_the_cursors_window_and_folds_them_back(
        self,
    ):
        cursor = keys.Cursor(window="@d1")
        self.assertIsNone(keys.handle_key(cursor, SESSIONS, " ", 0.0, {}))
        self.assertEqual(cursor.expanded, {"@d1"})
        cursor.window = "@d2"
        keys.handle_key(cursor, SESSIONS, " ", 0.0, {})
        self.assertEqual(cursor.expanded, {"@d1", "@d2"})
        keys.handle_key(cursor, SESSIONS, " ", 0.0, {})
        self.assertEqual(cursor.expanded, {"@d1"})

    def test_shift_down_and_up_move_the_window_within_its_session(self):
        cursor = keys.Cursor(window="@d1")
        down = keys.handle_key(cursor, SESSIONS, "\x1b[1;2B", 0.0, {})
        self.assertEqual(
            down, Action("move", window="@d1", neighbour="@d2", side="after")
        )
        cursor = keys.Cursor(window="@d5")
        up = keys.handle_key(cursor, SESSIONS, "\x1b[1;2A", 0.0, {})
        self.assertEqual(
            up, Action("move", window="@d5", neighbour="@d4", side="before")
        )
        self.assertEqual(cursor.window, "@d5")

    def test_nothing_past_either_end_of_a_session(self):
        first, last = keys.Cursor(window="@d1"), keys.Cursor(window="@d12")
        self.assertIsNone(keys.handle_key(first, SESSIONS, "\x1b[1;2A", 0.0, {}))
        self.assertIsNone(keys.handle_key(last, SESSIONS, "\x1b[1;2B", 0.0, {}))

    def test_split_keys_keeps_sequences_whole(self):
        split = list(
            keys.split_keys("jj\x1b[A\x1b[I4\x1b[<0;12;3M\x1b[<0;12;3m\x1b[1;2A\x1b")
        )
        expected = [
            "j",
            "j",
            "\x1b[A",
            "\x1b[I",
            "4",
            "\x1b[<0;12;3M",
            "\x1b[<0;12;3m",
            "\x1b[1;2A",
            "\x1b",
        ]
        self.assertEqual(split, expected)


PAIRS = [
    Session(
        "default",
        [
            Window(
                "@1",
                1,
                "pairs",
                [Pane(f"%{n}", "zsh", "~") for n in ("1", "5", "2", "6")],
            ),
            Window("@2", 2, "alone", [Pane("%9", "zsh", "~")]),
        ],
    )
]


def grouping(*typed: str, start: str = "@1"):
    """Presses g on the window, then each key; the cursor and the last action."""
    cursor = keys.Cursor(window=start)
    action = keys.handle_key(cursor, PAIRS, "g", 0.0, {})
    for key in typed:
        action = keys.handle_key(cursor, PAIRS, key, 0.0, {})
    return cursor, action


class GroupingTest(unittest.TestCase):
    def test_g_starts_on_the_windows_first_pane_and_g_q_or_escape_ends_it(self):
        self.assertEqual(grouping()[0].pane, "%1")
        self.assertEqual(grouping("g")[0].pane, "")
        self.assertEqual(grouping("\x1b")[0].pane, "")
        self.assertEqual(grouping("q")[0].pane, "")

    def test_a_window_with_one_pane_has_nothing_to_group(self):
        self.assertEqual(grouping(start="@2")[0].pane, "")

    def test_j_and_k_move_between_the_windows_panes_and_wrap(self):
        self.assertEqual(grouping("j", "j")[0].pane, "%2")
        self.assertEqual(grouping("k")[0].pane, "%6")
        self.assertEqual(grouping("\x1b[B")[0].pane, "%5")
        self.assertEqual(grouping("j")[0].window, "@1")

    def test_l_and_h_regroup_the_pane(self):
        _, join = grouping("j", "l")
        self.assertEqual(join, Action("regroup", pane="%5", window="@1", side="join"))
        _, leave = grouping("j", "\x1b[D")
        self.assertEqual(leave, Action("regroup", pane="%5", window="@1", side="leave"))

    def test_shift_j_and_k_swap_the_pane_with_its_neighbour_but_not_past_the_ends(self):
        _, down = grouping("J")
        self.assertEqual(down, Action("swap", pane="%1", window="@1", neighbour="%5"))
        _, up = grouping("j", "\x1b[1;2A")
        self.assertEqual(up, Action("swap", pane="%5", window="@1", neighbour="%1"))
        self.assertIsNone(grouping("K")[1])

    def test_enter_opens_the_pane_and_tab_leaves_both_ending_the_grouping(self):
        cursor, action = grouping("j", "\r")
        self.assertEqual((action, cursor.pane), (Action("open", pane="%5"), ""))
        cursor, action = grouping("\t")
        self.assertEqual((action, cursor.pane), (Action("leave"), ""))

    def test_other_keys_do_nothing_while_grouping(self):
        cursor, action = grouping("2", " ", "?")
        self.assertEqual((cursor.window, cursor.pane, action), ("@1", "%1", None))
        self.assertEqual((cursor.expanded, cursor.help), (set(), False))

    def test_a_click_ends_the_grouping(self):
        cursor, _ = grouping(mouse(65, 0))
        self.assertEqual((cursor.pane, cursor.window), ("", "@2"))

    def test_shift_j_and_k_move_the_window_outside_grouping(self):
        cursor = keys.Cursor(window="@d1")
        self.assertEqual(
            keys.handle_key(cursor, SESSIONS, "J", 0.0, {}),
            Action("move", window="@d1", neighbour="@d2", side="after"),
        )


def mouse(button: int, row: int, pressed: bool = True) -> str:
    """A mouse event at a 0-based row of the navigator, as tmux sends it in SGR form (1-based)."""
    return f"\x1b[<{button};10;{row + 1}{'M' if pressed else 'm'}"


def rows_of(drawn: list[Session]) -> dict[int, tuple[str, str]]:
    """One row per window, in the order drawn: the targets a frame of the drawn sessions would have."""
    order = model.window_order(drawn)
    return {row: (window_id, "") for row, window_id in enumerate(order)}


def gesture(*events: str, cursor: keys.Cursor | None = None, targets=None):
    """Runs mouse events as pane.py would: against the sessions as drawn, with a dragged window in its new place,
    and the rows of that frame."""
    cursor = cursor or keys.Cursor(window="@d1")
    action = None
    for event in events:
        drawn = SESSIONS
        if cursor.drag and cursor.drag.position != cursor.drag.origin:
            drawn = model.reordered(
                SESSIONS, cursor.drag.window, cursor.drag.position, 1
            )
        rows = targets if targets is not None else rows_of(drawn)
        action = keys.handle_key(cursor, drawn, event, 0.0, rows)
    return action, cursor


class ClickTest(unittest.TestCase):
    def test_a_click_on_a_window_row_opens_it_like_enter(self):
        action, cursor = gesture(mouse(0, 3), mouse(0, 3, pressed=False))
        self.assertEqual((action, cursor.window), (Action("open"), "@d4"))

    def test_a_click_on_a_pane_row_opens_the_window_at_that_pane(self):
        pane_row = {4: ("@d4", "%d4")}
        events = (mouse(0, 4), mouse(0, 4, pressed=False))
        action, cursor = gesture(*events, targets=pane_row)
        self.assertEqual((action, cursor.window), (Action("open", pane="%d4"), "@d4"))

    def test_a_press_alone_does_nothing_yet(self):
        self.assertIsNone(gesture(mouse(0, 3))[0])

    def test_releases_other_buttons_and_empty_rows_do_nothing(self):
        self.assertIsNone(gesture(mouse(0, 3, pressed=False))[0])
        self.assertIsNone(gesture(mouse(2, 3), mouse(2, 3, pressed=False))[0])
        self.assertIsNone(gesture(mouse(0, 30), mouse(0, 30, pressed=False))[0])

    def test_the_wheel_moves_the_cursor(self):
        self.assertEqual(gesture(mouse(65, 0))[1].window, "@d2")
        self.assertEqual(gesture(mouse(64, 0))[1].window, "@s3")


class DragTest(unittest.TestCase):
    def test_a_window_dragged_down_goes_before_the_one_now_after_it(self):
        events = (mouse(0, 0), mouse(32, 1), mouse(32, 2), mouse(0, 2, pressed=False))
        action, _ = gesture(*events)
        expected = Action("move", window="@d1", neighbour="@d4", side="before")
        self.assertEqual(action, expected)

    def test_a_window_dragged_up_goes_before_the_one_it_was_dropped_on(self):
        action, _ = gesture(mouse(0, 3), mouse(32, 0), mouse(0, 0, pressed=False))
        expected = Action("move", window="@d4", neighbour="@d1", side="before")
        self.assertEqual(action, expected)

    def test_a_window_dragged_to_the_end_goes_after_the_last(self):
        cursor = keys.Cursor(window="@d1")
        gesture(mouse(0, 0), cursor=cursor)
        cursor.drag.position = 11  # carried past every other window
        action, _ = gesture(mouse(0, 0, pressed=False), cursor=cursor)
        expected = Action("move", window="@d1", neighbour="@d12", side="after")
        self.assertEqual(action, expected)

    def test_another_session_s_rows_are_not_a_place(self):
        _, cursor = gesture(mouse(0, 0), mouse(32, 12))  # row 12 is scratch's first
        self.assertEqual(cursor.drag.position, cursor.drag.origin)

    def test_dragged_back_where_it_started_it_is_a_click(self):
        events = (mouse(0, 0), mouse(32, 2), mouse(32, 0), mouse(0, 0, pressed=False))
        action, _ = gesture(*events)
        self.assertEqual(action, Action("open"))


if __name__ == "__main__":
    unittest.main()

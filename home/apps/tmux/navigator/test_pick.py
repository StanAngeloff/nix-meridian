import unittest

import keys
import pick
from model import Pane, Session, Window

SESSIONS = [
    Session(
        "default",
        [
            Window(
                "@1",
                1,
                "one",
                [
                    Pane("%1", "zsh", "~", active=True),
                    Pane("%2", "claude", "~", "✳ task", "read"),
                ],
            ),
            Window("@2", 2, "two", [Pane("%3", "nvim", "~", active=True)]),
            Window(
                "@12",
                12,
                "twelve",
                [Pane("%4", "claude", "~", "✳ other", "working", active=True)],
            ),
        ],
    )
]
# Rows as draw.draw lays them out: the session's header, then each window's line and its panes' lines.
TARGETS = {
    1: ("@1", ""),
    2: ("@1", "%1"),
    3: ("@1", "%2"),
    4: ("@2", ""),
    5: ("@2", "%3"),
    6: ("@12", ""),
    7: ("@12", "%4"),
}


def tap(picker, row, release_row=None):
    """A press and a release of the left button, rows counted from 0 as draw.Canvas counts them."""
    release_row = row if release_row is None else release_row
    picker.key(SESSIONS, f"\x1b[<0;9;{row + 1}M", 0.0, TARGETS)
    return picker.key(SESSIONS, f"\x1b[<0;9;{release_row + 1}m", 0.0, TARGETS)


class TapTest(unittest.TestCase):
    def test_a_tap_on_a_pane_opens_that_pane(self):
        self.assertEqual(tap(pick.Picker(), 2), pick.Picked("open", "@1", "%1"))

    def test_a_tap_on_a_window_opens_its_claude_pane_else_its_active_one(self):
        self.assertEqual(tap(pick.Picker(), 1), pick.Picked("open", "@1", "%2"))
        self.assertEqual(tap(pick.Picker(), 4), pick.Picked("open", "@2", "%3"))

    def test_a_tap_released_on_another_row_or_on_the_header_opens_nothing(self):
        self.assertIsNone(tap(pick.Picker(), 1, release_row=4))
        self.assertIsNone(tap(pick.Picker(), 0))


class NumberTest(unittest.TestCase):
    def test_a_number_no_longer_one_could_extend_opens_at_once(self):
        picked = pick.Picker().key(SESSIONS, "2", 0.0, TARGETS)
        self.assertEqual(picked, pick.Picked("open", "@2", "%3"))

    def test_a_number_a_longer_one_could_extend_waits_for_the_next_digit(self):
        picker = pick.Picker()
        self.assertIsNone(picker.key(SESSIONS, "1", 0.0, TARGETS))
        self.assertTrue(picker.typing)
        self.assertEqual(picker.cursor.window, "@1")
        self.assertIsNone(picker.tick(SESSIONS, keys.NUMBER_TIMEOUT / 2))
        picked = picker.tick(SESSIONS, keys.NUMBER_TIMEOUT + 0.01)
        self.assertEqual(picked, pick.Picked("open", "@1", "%2"))
        self.assertFalse(picker.typing)

    def test_the_next_digit_in_time_extends_the_number(self):
        picker = pick.Picker()
        picker.key(SESSIONS, "1", 0.0, TARGETS)
        picked = picker.key(SESSIONS, "2", 0.3, TARGETS)
        self.assertEqual(picked, pick.Picked("open", "@12", "%4"))

    def test_a_number_without_a_window_does_nothing(self):
        picker = pick.Picker()
        self.assertIsNone(picker.key(SESSIONS, "7", 0.0, TARGETS))
        self.assertFalse(picker.typing)


class KeyTest(unittest.TestCase):
    def test_n_asks_for_a_new_session_and_q_quits(self):
        self.assertEqual(pick.Picker().key(SESSIONS, "n", 0.0, {}), pick.Picked("new"))
        self.assertEqual(pick.Picker().key(SESSIONS, "q", 0.0, {}), pick.Picked("quit"))


class GroupTest(unittest.TestCase):
    def test_only_the_hubs_group_is_listed_and_every_session_when_it_is_unknown(self):
        sessions = SESSIONS + [Session("scratch", [Window("@9", 1, "notes")])]
        self.assertEqual(pick.of_group(sessions, "default"), SESSIONS)
        self.assertEqual(pick.of_group(sessions, ""), sessions)


if __name__ == "__main__":
    unittest.main()

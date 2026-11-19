import unittest

import keys
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

        self.assertEqual(handle("\r"), ("open", ""))
        self.assertEqual(handle("\t"), ("leave", ""))
        self.assertEqual(handle("\x1b"), ("leave", ""))
        self.assertIsNone(handle("\x1b[I"))

    def test_split_keys_keeps_sequences_whole(self):
        split = list(keys.split_keys("jj\x1b[A\x1b[I4\x1b[<0;12;3M\x1b[<0;12;3m\x1b"))
        expected = [
            "j",
            "j",
            "\x1b[A",
            "\x1b[I",
            "4",
            "\x1b[<0;12;3M",
            "\x1b[<0;12;3m",
            "\x1b",
        ]
        self.assertEqual(split, expected)


# Rows of the last frame: row 2 is window 4's name, row 3 its first pane.
TARGETS = {2: ("@d4", ""), 3: ("@d4", "%d4")}


def click(key: str) -> tuple[keys.Action | None, str]:
    cursor = keys.Cursor(window="@d1")
    action = keys.handle_key(cursor, SESSIONS, key, 0.0, TARGETS)
    return action, cursor.window


class MouseTest(unittest.TestCase):
    def test_a_click_on_a_window_row_opens_it_like_enter(self):
        self.assertEqual(click("\x1b[<0;10;3M"), (("open", ""), "@d4"))

    def test_a_click_on_a_pane_row_opens_the_window_at_that_pane(self):
        self.assertEqual(click("\x1b[<0;10;4M"), (("open", "%d4"), "@d4"))

    def test_releases_other_buttons_and_empty_rows_do_nothing(self):
        self.assertEqual(click("\x1b[<0;10;3m"), (None, "@d1"))
        self.assertEqual(click("\x1b[<2;10;3M"), (None, "@d1"))
        self.assertEqual(click("\x1b[<0;10;1M"), (None, "@d1"))

    def test_the_wheel_moves_the_cursor(self):
        self.assertEqual(click("\x1b[<65;10;1M"), (None, "@d2"))
        self.assertEqual(click("\x1b[<64;10;1M"), (None, "@s3"))


if __name__ == "__main__":
    unittest.main()

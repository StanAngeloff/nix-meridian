import os
import tempfile
import unittest

import draw
import new_session
from new_session import BACK, NewSession, Started

HOME = "/home/someone"
DIRECTORIES = [f"{HOME}/newest", f"{HOME}/src/middle", "/srv/oldest"]
PROFILES = ["personal", "personal/2", "team"]
ROWS = 12


def tap(column, row):
    """A press and a release at 1-based column and row, as the terminal reports them."""
    return [f"\x1b[<0;{column};{row}M", f"\x1b[<0;{column};{row}m"]


def press(session, keys, columns=60):
    outcome = None
    for key in keys:
        outcome = session.key(key, session.frame(HOME, columns, ROWS))
        if outcome:
            return outcome
    return outcome


def screen(session, columns=60):
    """The frame's rows as text, without trailing blanks, and the rows below the list left out."""
    canvas = session.frame(HOME, columns, ROWS).canvas
    rows = [canvas.text(y).rstrip() for y in range(canvas.rows)]
    return [row for row in rows[: canvas.rows - 2] if row] + rows[canvas.rows - 2 :]


def on_details(profiles=PROFILES, default="personal"):
    session = NewSession(DIRECTORIES, profiles, default)
    press(session, ["2"])
    return session


def colours(canvas, y, text):
    """The (foreground, background, bold) of each character of text's first appearance on row y."""
    x = canvas.text(y).index(text)
    return {cell[1:4] for cell in canvas.cells[y][x : x + len(text)]}


class SplitKeysTest(unittest.TestCase):
    def test_characters_are_keys(self):
        self.assertEqual(new_session.split_keys("ab1"), ["a", "b", "1"])

    def test_a_tap_is_one_key(self):
        self.assertEqual(new_session.split_keys("\x1b[<0;5;7Mx"), ["\x1b[<0;5;7M", "x"])

    def test_a_lone_escape_is_the_escape_key(self):
        self.assertEqual(new_session.split_keys("\x1b"), ["\x1b"])
        self.assertEqual(new_session.split_keys("\x1bx"), ["\x1b", "x"])

    def test_arrows_are_one_key(self):
        self.assertEqual(new_session.split_keys("\x1b[A\x1bOB"), ["\x1b[A", "\x1bOB"])


class CutPathTest(unittest.TestCase):
    def test_parent_and_last_part(self):
        self.assertEqual(new_session.cut_path("~/src/voxize", 40), ("~/src/", "voxize"))

    def test_a_path_that_fits_is_whole(self):
        self.assertEqual(new_session.cut_path("~/src/voxize", 12), ("~/src/", "voxize"))

    def test_a_wide_path_loses_its_start(self):
        parent, name = new_session.cut_path("~/a/long/parent/voxize", 12)
        self.assertEqual((parent, name), ("…rent/", "voxize"))

    def test_the_last_part_shows_as_far_as_it_can(self):
        self.assertEqual(new_session.cut_path("~/src/voxize", 4), ("…", "ize"))

    def test_home_alone(self):
        self.assertEqual(new_session.cut_path("~", 10), ("", "~"))


class AbbreviateHomeTest(unittest.TestCase):
    def test_home_and_below(self):
        self.assertEqual(new_session.abbreviate_home(HOME, HOME), "~")
        self.assertEqual(new_session.abbreviate_home(f"{HOME}/x", HOME), "~/x")

    def test_a_sibling_that_shares_the_prefix_stays_whole(self):
        self.assertEqual(new_session.abbreviate_home(f"{HOME}2/x", HOME), f"{HOME}2/x")


class DirectoryScreenTest(unittest.TestCase):
    def test_drawn_as_the_hub_draws_its_list_newest_first(self):
        self.assertEqual(
            screen(NewSession(DIRECTORIES, PROFILES, ""), columns=30),
            [
                " New session  " + "─" * 16,
                "  1│ ~/newest",
                "  2│ ~/src/middle",
                "  3╵ /srv/oldest",
                "─" * 30,
                " tap 1-3 pick  esc back",
            ],
        )

    def test_uses_the_hub_list_colours(self):
        canvas = NewSession(DIRECTORIES, PROFILES, "").frame(HOME, 60, ROWS).canvas
        self.assertEqual(
            colours(canvas, 0, " New session "),
            {(draw.SESSION_FG, draw.SESSION_BG, True)},
        )
        self.assertEqual(
            colours(canvas, 2, " 2"), {(draw.STATUS_FG, draw.TERMINAL_BG, False)}
        )
        self.assertEqual(
            colours(canvas, 2, "│"), {(draw.DIMMER, draw.TERMINAL_BG, False)}
        )
        self.assertEqual(
            colours(canvas, 2, "~/src/"), {(draw.DIM, draw.TERMINAL_BG, False)}
        )
        self.assertEqual(
            colours(canvas, 2, "middle"), {(draw.STATUS_FG, draw.TERMINAL_BG, False)}
        )
        self.assertEqual(
            colours(canvas, ROWS - 1, "tap 1-3"), {(draw.TEXT, draw.TERMINAL_BG, True)}
        )

    def test_a_digit_picks_its_directory(self):
        session = NewSession(DIRECTORIES, PROFILES, "")
        self.assertIsNone(press(session, ["3"]))
        self.assertEqual(session.directory, 2)

    def test_a_digit_without_a_directory_does_nothing(self):
        session = NewSession(DIRECTORIES, PROFILES, "")
        self.assertIsNone(press(session, ["4", "0", "x"]))
        self.assertIsNone(session.directory)

    def test_escape_goes_back_to_the_list(self):
        self.assertEqual(press(NewSession(DIRECTORIES, PROFILES, ""), ["\x1b"]), BACK)

    def test_a_tap_picks_on_release_over_the_same_row(self):
        session = NewSession(DIRECTORIES, PROFILES, "")
        press(session, tap(10, 3))  # row 3 is "2│ ~/src/middle"
        self.assertEqual(session.directory, 1)

    def test_a_tap_released_on_another_row_picks_nothing(self):
        session = NewSession(DIRECTORIES, PROFILES, "")
        press(session, ["\x1b[<0;10;3M", "\x1b[<0;10;4m"])
        self.assertIsNone(session.directory)

    def test_a_tap_on_the_header_picks_nothing(self):
        session = NewSession(DIRECTORIES, PROFILES, "")
        press(session, tap(10, 1))
        self.assertIsNone(session.directory)

    def test_no_directories(self):
        rows = screen(NewSession([], PROFILES, ""))
        self.assertIn(" No project directories found.", rows)
        self.assertEqual(rows[-1], " esc back")

    def test_one_directory(self):
        rows = screen(NewSession(DIRECTORIES[:1], PROFILES, ""))
        self.assertIn("  1╵ ~/newest", rows)
        self.assertEqual(rows[-1], " tap 1 pick  esc back")


class DetailsScreenTest(unittest.TestCase):
    def test_the_directory_with_profiles_and_name_as_branches(self):
        session = on_details()
        press(session, list("sc-1"))
        self.assertEqual(
            screen(session),
            [
                " New session  " + "─" * 46,
                "  2│ ~/src/middle",
                "   │ ├─ personal  personal/2  team",
                "   ╵ └─ sc-1",
                "─" * 60,
                " enter start  tab profile  esc back",
            ],
        )
        self.assertEqual(session.frame(HOME, 60, ROWS).cursor, (3, 12))

    def test_an_empty_name_shows_a_placeholder_and_the_cursor_at_its_start(self):
        session = on_details()
        frame = session.frame(HOME, 60, ROWS)
        self.assertEqual(frame.canvas.text(3).rstrip(), "   ╵ └─ session name")
        self.assertEqual(
            colours(frame.canvas, 3, "session name"),
            {(draw.DIMMER, draw.TERMINAL_BG, False)},
        )
        self.assertEqual(frame.cursor, (3, 8))

    def test_the_default_profile_is_selected_on_cyan(self):
        session = on_details(default="personal/2")
        self.assertEqual(session.profile, 1)
        canvas = session.frame(HOME, 60, ROWS).canvas
        self.assertEqual(
            colours(canvas, 2, " personal/2 "),
            {(draw.FOCUSED_TAB_FG, draw.FOCUSED_TAB_BG, True)},
        )
        self.assertEqual(
            colours(canvas, 2, "team"), {(draw.DIM, draw.TERMINAL_BG, False)}
        )

    def test_an_unknown_default_selects_the_first(self):
        self.assertEqual(on_details(default="gone").profile, 0)

    def test_tab_moves_to_the_next_profile_and_wraps(self):
        session = on_details()
        press(session, ["\t", "\t"])
        self.assertEqual(session.profile, 2)
        press(session, ["\t"])
        self.assertEqual(session.profile, 0)

    def test_a_tap_selects_a_profile(self):
        session = on_details()
        # "   │ ├─ personal  personal/2  team": " personal/2 " spans columns 17 to 28, 0-based.
        press(session, tap(20, 3))
        self.assertEqual(session.profile, 1)

    def test_profiles_that_do_not_fit_continue_under_the_first(self):
        session = on_details()
        rows = screen(session, columns=26)
        self.assertEqual(rows[2], "   │ ├─ personal")
        self.assertEqual(rows[3], "   │ │  personal/2  team")
        self.assertEqual(rows[4], "   ╵ └─ session name")
        press(session, tap(10, 4), columns=26)
        self.assertEqual(session.profile, 1)

    def test_typing_and_backspace_edit_the_name(self):
        session = on_details()
        press(session, list("abc") + ["\x7f", "d", "\x1b[A"])
        self.assertEqual(session.name, "abd")

    def test_digits_type_into_the_name(self):
        session = on_details()
        press(session, list("sc-123"))
        self.assertEqual((session.directory, session.name), (1, "sc-123"))

    def test_enter_starts_with_the_profile_and_name(self):
        session = on_details()
        outcome = press(session, ["\t"] + list("sc-123/login") + ["\r"])
        self.assertEqual(
            outcome, Started(f"{HOME}/src/middle", "personal/2", "sc-123/login")
        )

    def test_enter_with_no_name_goes_back_to_the_list(self):
        self.assertEqual(press(on_details(), ["\r"]), BACK)

    def test_escape_goes_back_to_the_directories_keeping_profile_and_name(self):
        session = on_details()
        press(session, ["\t", "x", "\x1b"])
        self.assertIsNone(session.directory)
        press(session, ["1"])
        self.assertEqual(
            (session.directory, session.profile, session.name), (0, 1, "x")
        )

    def test_a_long_name_shows_its_end(self):
        session = on_details()
        press(session, list("abcdefghij"))
        frame = session.frame(HOME, 18, ROWS)
        self.assertEqual(
            frame.canvas.text(frame.cursor[0]).rstrip(), "   ╵ └─ …cdefghij"
        )
        self.assertEqual(frame.cursor[1], 17)

    def test_no_profiles(self):
        session = on_details(profiles=[], default="")
        rows = screen(session)
        self.assertEqual(rows[1:3], ["  2│ ~/src/middle", "   ╵ └─ session name"])
        self.assertEqual(rows[-1], " enter start  esc back")
        self.assertEqual(
            press(session, ["x", "\r"]), Started(f"{HOME}/src/middle", "", "x")
        )


class ReadProfilesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = self.directory.name

    def tearDown(self):
        self.directory.cleanup()

    def profile(self, slug):
        os.makedirs(os.path.join(self.path, slug, "credentials"))

    def test_profiles_by_name_and_the_default(self):
        for slug in ("personal", "personal--2", "team", ".v2-backup"):
            self.profile(slug)
        os.makedirs(os.path.join(self.path, "no-credentials"))
        os.symlink("personal--2", os.path.join(self.path, "active"))
        self.assertEqual(
            new_session.read_profiles(self.path),
            (["personal", "personal/2", "team"], "personal/2"),
        )

    def test_an_active_directory_is_not_a_profile(self):
        self.profile("personal")
        self.profile("active")
        self.assertEqual(new_session.read_profiles(self.path), (["personal"], ""))

    def test_no_profiles_directory(self):
        self.assertEqual(
            new_session.read_profiles(os.path.join(self.path, "none")), ([], "")
        )


class RenderTest(unittest.TestCase):
    def test_hides_the_cursor_on_the_directory_screen(self):
        frame = NewSession(DIRECTORIES, PROFILES, "").frame(HOME, 30, ROWS)
        self.assertTrue(new_session.render(frame).endswith("\x1b[?25l"))

    def test_shows_the_cursor_where_the_name_ends(self):
        frame = on_details().frame(HOME, 60, ROWS)
        self.assertTrue(new_session.render(frame).endswith("\x1b[4;9H\x1b[?25h"))


if __name__ == "__main__":
    unittest.main()

import os
import tempfile
import unittest

from file_under_pointer import hyperlink_path, label, names_under, resolve


def click(lines: list[str], y: int, needle: str) -> list[str]:
    """The names under a click on the second character of the first needle on row y (the text before it is one cell wide)."""
    return names_under(lines, lines[y].index(needle) + 1, y)


class NamesUnderTest(unittest.TestCase):
    def test_a_word_on_its_own_row(self):
        lines = ["Plan saved to docs/PLAN.md. Next"]
        self.assertEqual(click(lines, 0, "docs"), ["docs/PLAN.md."])

    def test_a_name_claude_code_wrapped_at_a_hyphen_joins_from_its_first_row(self):
        lines = [
            "▌ The review is finished. The briefing is at /tmp/reviews/review-of-the-",
            "▌ cleanup-branch/briefing-for-the-cleanup-branch.md.",
            "▌",
        ]
        self.assertEqual(
            click(lines, 0, "/tmp"),
            [
                "/tmp/reviews/review-of-the-cleanup-branch/briefing-for-the-cleanup-branch.md.",
                "/tmp/reviews/review-of-the-",
            ],
        )

    def test_a_wrapped_name_joins_from_its_last_row(self):
        lines = [
            "▌ The briefing is at /tmp/reviews/review-of-the-",
            "▌ cleanup-branch/briefing.md.",
        ]
        self.assertEqual(
            click(lines, 1, "cleanup"),
            [
                "/tmp/reviews/review-of-the-cleanup-branch/briefing.md.",
                "cleanup-branch/briefing.md.",
            ],
        )

    def test_a_name_over_three_rows(self):
        lines = ["▌ see /tmp/a-", "▌ b-", "▌ c.md now"]
        self.assertEqual(
            click(lines, 1, "b-")[:3],
            ["/tmp/a-b-c.md", "/tmp/a-b-", "b-c.md"],
        )

    def test_a_row_that_broke_at_a_space_still_gives_the_word_alone(self):
        lines = ["▌ The plan is in docs/PLAN.md", "▌ and the notes follow."]
        self.assertEqual(click(lines, 0, "docs"), ["docs/PLAN.mdand", "docs/PLAN.md"])

    def test_a_word_inside_its_row_is_not_joined(self):
        lines = ["▌ a-", "▌ see docs/PLAN.md now", "▌ b"]
        self.assertEqual(click(lines, 1, "docs"), ["docs/PLAN.md"])

    def test_rows_of_different_messages_are_not_joined(self):
        lines = ["▌ the plan is /tmp/a-", "▏ ● Bash(ls)"]
        self.assertEqual(click(lines, 0, "/tmp"), ["/tmp/a-"])

    def test_a_prompts_other_rows_join_after_their_indent(self):
        lines = ["▌ ❯ open /tmp/reviews/review-of-the-", "▌   branch/notes.md please"]
        self.assertEqual(
            click(lines, 0, "/tmp"),
            [
                "/tmp/reviews/review-of-the-branch/notes.md",
                "/tmp/reviews/review-of-the-",
            ],
        )

    def test_rows_without_a_bar_join_too_as_a_wrapped_shell_line_does(self):
        lines = ["$ cat /tmp/a/very/long/pa", "th/to/file.txt"]
        self.assertEqual(
            click(lines, 0, "/tmp"),
            ["/tmp/a/very/long/path/to/file.txt", "/tmp/a/very/long/pa"],
        )

    def test_brackets_and_quotes_end_a_word(self):
        lines = ['▌ Brackets (docs/PLAN.md), quotes "docs/NOTES.md".']
        self.assertEqual(click(lines, 0, "docs/PLAN"), ["docs/PLAN.md"])
        self.assertEqual(click(lines, 0, "docs/NOTES"), ["docs/NOTES.md"])

    def test_wide_characters_before_the_word_take_two_cells(self):
        lines = ["⏺ Wide 日本語 docs/PLAN.md."]
        self.assertEqual(names_under(lines, 18, 0), ["docs/PLAN.md."])

    def test_the_bar_and_blank_cells_name_nothing(self):
        lines = ["▌ see docs/PLAN.md", ""]
        self.assertEqual(names_under(lines, 0, 0), [])
        self.assertEqual(names_under(lines, 5, 0), [])
        self.assertEqual(names_under(lines, 40, 0), [])
        self.assertEqual(names_under(lines, 0, 1), [])
        self.assertEqual(names_under(lines, 0, 5), [])


class ResolveTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.pane_path = self.directory.name
        os.makedirs(os.path.join(self.pane_path, "docs"))
        for name in ("docs/PLAN.md", "docs/v1."):
            with open(os.path.join(self.pane_path, name), "w"):
                pass

    def tearDown(self):
        self.directory.cleanup()

    def path(self, name: str) -> str:
        return os.path.join(self.pane_path, name)

    def test_drops_the_sentence_dot(self):
        self.assertEqual(
            resolve("docs/PLAN.md.", self.pane_path), self.path("docs/PLAN.md")
        )

    def test_drops_a_line_and_column(self):
        self.assertEqual(
            resolve("docs/PLAN.md:42:7.", self.pane_path), self.path("docs/PLAN.md")
        )

    def test_keeps_a_dot_that_is_part_of_the_name(self):
        self.assertEqual(resolve("docs/v1.", self.pane_path), self.path("docs/v1."))

    def test_an_absolute_name_ignores_the_pane_directory(self):
        self.assertEqual(
            resolve(self.path("docs/PLAN.md") + ",", "/"), self.path("docs/PLAN.md")
        )

    def test_finds_a_directory(self):
        self.assertEqual(resolve("./docs/.", self.pane_path), self.path("docs"))

    def test_a_name_that_is_no_file(self):
        self.assertIsNone(resolve("docs/MISSING.md.", self.pane_path))


class HyperlinkTest(unittest.TestCase):
    def test_a_file_link_with_an_encoded_space(self):
        self.assertEqual(
            hyperlink_path("file:///tmp/My%20Notes.md"), "/tmp/My Notes.md"
        )

    def test_a_file_link_with_a_host(self):
        self.assertEqual(
            hyperlink_path("file://laptop/tmp/notes.md."), "/tmp/notes.md."
        )

    def test_a_web_link_is_no_file(self):
        self.assertIsNone(hyperlink_path("https://example.com/notes.md"))


class LabelTest(unittest.TestCase):
    def test_a_path_inside_the_pane_directory(self):
        self.assertEqual(
            label("/work/project/docs/PLAN.md", "/work/project"), "docs/PLAN.md"
        )

    def test_a_path_in_home(self):
        home = os.path.expanduser("~")
        self.assertEqual(label(home + "/notes.md", "/work/project"), "~/notes.md")

    def test_another_path(self):
        self.assertEqual(label("/etc/hosts", "/work/project"), "/etc/hosts")


if __name__ == "__main__":
    unittest.main()

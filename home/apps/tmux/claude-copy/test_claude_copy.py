import unittest

from claude_copy import clean, start_columns


class StartColumnsTest(unittest.TestCase):
    def test_a_line_selection_starts_every_line_at_the_left_edge(self):
        self.assertEqual(start_columns("line", False, 0, 20, 92, 21), (0, 0))

    def test_a_selection_made_downwards_starts_at_its_start(self):
        self.assertEqual(start_columns("char", False, 98, 24, 119, 26), (98, 0))

    def test_a_selection_made_upwards_starts_at_the_cursor(self):
        self.assertEqual(start_columns("char", False, 19, 21, 7, 19), (7, 0))

    def test_a_selection_on_one_row_starts_at_its_left_end(self):
        self.assertEqual(start_columns("char", False, 40, 5, 12, 5), (12, 0))

    def test_a_rectangle_starts_every_line_at_its_left_side(self):
        self.assertEqual(start_columns("char", True, 30, 5, 2, 9), (2, 2))


class ReplyTest(unittest.TestCase):
    def test_drops_the_bar_from_whole_rows(self):
        copied = (
            "▌ Rivers carry water from highlands\n▌ through rock, deposits sediment\n"
        )
        self.assertEqual(
            clean(copied, 0, 0),
            "Rivers carry water from highlands\nthrough rock, deposits sediment\n",
        )

    def test_keeps_a_first_line_that_starts_inside_its_row(self):
        copied = "Engineers track river\n▌ flow with gauges\n▌ might return"
        self.assertEqual(
            clean(copied, 98, 0),
            "Engineers track river\nflow with gauges\nmight return",
        )

    def test_drops_the_space_after_a_bar_left_out_of_the_selection(self):
        copied = " Rivers carry water\n▌ through rock"
        self.assertEqual(clean(copied, 1, 0), "Rivers carry water\nthrough rock")

    def test_keeps_a_list_item_indented_under_its_marker(self):
        copied = (
            "▌ - The second item covers\n▌   moves sediment\n▌   above.\n"
            "▌   - A nested note"
        )
        self.assertEqual(
            clean(copied, 0, 0),
            "- The second item covers\n  moves sediment\n  above.\n  - A nested note",
        )

    def test_drops_the_indent_the_selected_rows_share(self):
        copied = "▌   moves sediment, erodes\n▌   above."
        self.assertEqual(clean(copied, 0, 0), "moves sediment, erodes\nabove.")

    def test_keeps_the_indent_of_code_relative_to_its_least_indented_row(self):
        copied = "▌     if ready:\n▌         start()"
        self.assertEqual(clean(copied, 0, 0), "if ready:\n    start()")

    def test_keeps_a_quote_mark(self):
        copied = "▌ ▎ Rivers are often described\n▌ ▎ and their ecosystems"
        self.assertEqual(
            clean(copied, 0, 0), "▎ Rivers are often described\n▎ and their ecosystems"
        )

    def test_a_blank_row_inside_a_reply_becomes_an_empty_line(self):
        copied = "▌ Probe\n▌\n▌ Rivers carry"
        self.assertEqual(clean(copied, 0, 0), "Probe\n\nRivers carry")


class PromptTest(unittest.TestCase):
    def test_drops_the_marker_and_the_indent_of_the_other_rows(self):
        copied = (
            '▌ ❯ This is a formatting probe\n▌   "Probe"; two paragraphs\n'
            "▌   columns and two rows.\n▌"
        )
        self.assertEqual(
            clean(copied, 0, 0),
            'This is a formatting probe\n"Probe"; two paragraphs\ncolumns and two rows.\n',
        )

    def test_drops_the_marker_when_the_selection_starts_on_it(self):
        self.assertEqual(clean("❯ hello there", 2, 0), "hello there")

    def test_drops_the_padding_after_the_text(self):
        self.assertEqual(
            clean("▌   bullet of about   \n▌   columns  ", 0, 0),
            "bullet of about\ncolumns",
        )


class ToolCallTest(unittest.TestCase):
    def test_drops_the_thin_bar(self):
        copied = "▏ ● Bash(echo copy-probe)\n▏   ⎿  copy-probe"
        self.assertEqual(
            clean(copied, 0, 0), "● Bash(echo copy-probe)\n  ⎿  copy-probe"
        )


class AcrossMessagesTest(unittest.TestCase):
    def test_each_message_loses_its_own_bar_and_indent(self):
        copied = (
            "▌   columns and two rows.\n▌\n\n"
            "▏ ● Bash(echo copy-probe)\n▏   ⎿  copy-probe\n\n"
            "▌ Probe\n\n"
            "▣ Claude · Haiku 5.5 · 8s"
        )
        self.assertEqual(
            clean(copied, 0, 0),
            "columns and two rows.\n\n\n"
            "● Bash(echo copy-probe)\n  ⎿  copy-probe\n\n"
            "Probe\n\n"
            "▣ Claude · Haiku 5.5 · 8s",
        )

    def test_keeps_rows_without_a_bar_as_they_are(self):
        copied = "✻ Crunched for 7s\n  ⏵⏵ bypass permissions on"
        self.assertEqual(clean(copied, 0, 0), copied)


class RectangleTest(unittest.TestCase):
    def test_a_rectangle_over_the_bars_drops_them(self):
        self.assertEqual(
            clean("▌ Rivers carry\n▌ through rock", 0, 0), "Rivers carry\nthrough rock"
        )

    def test_a_rectangle_inside_the_text_stays_as_selected(self):
        self.assertEqual(
            clean("carry water\nrock, deposits", 9, 9), "carry water\nrock, deposits"
        )


if __name__ == "__main__":
    unittest.main()

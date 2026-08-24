import unittest

import fit
import palette
import render


def segment(key, group, *texts):
    return fit.Segment(
        key, group, tuple(fit.Form(text, index) for index, text in enumerate(texts))
    )


class VisibleWidth(unittest.TestCase):
    def test_counts_plain_text_by_character(self):
        self.assertEqual(render.visible_width("5h:42%"), 6)

    def test_ignores_colour_sequences(self):
        self.assertEqual(
            render.visible_width(f"{palette.PASTEL_TEAL}5h:42%{palette.RESET}"), 6
        )

    def test_counts_the_status_line_glyphs_as_one_column_each(self):
        # Escapes rather than literals: symbol glyphs can degrade to a bare space in a file write.
        glyphs = "✦│█↑↓◌Σ─…"
        self.assertEqual(len(glyphs), 9)
        self.assertEqual(render.visible_width(glyphs), 9)

    def test_counts_genuinely_wide_characters_as_two_columns(self):
        self.assertEqual(render.visible_width("漢"), 2)

    def test_is_zero_for_empty_and_colour_only_text(self):
        self.assertEqual(render.visible_width(""), 0)
        self.assertEqual(render.visible_width(palette.RESET), 0)


class Render(unittest.TestCase):
    def test_joins_separate_groups_with_the_separator(self):
        segments = (segment("a", "a", "AAA"), segment("b", "b", "BBB"))
        line = render.render(segments, {"a": 0, "b": 0})
        self.assertEqual(render.ANSI_SEQUENCE.sub("", line), "AAA │ BBB")

    def test_joins_segments_in_one_group_with_a_single_space(self):
        segments = (
            segment("five", "rate", "5h:42%"),
            segment("seven", "rate", "7d:7%"),
        )
        line = render.render(segments, {"five": 0, "seven": 0})
        self.assertEqual(render.ANSI_SEQUENCE.sub("", line), "5h:42% 7d:7%")

    def test_leaves_no_separator_behind_a_dropped_segment(self):
        segments = (
            segment("a", "a", "AAA"),
            segment("gone", "gone", "X", fit.DROP),
            segment("b", "b", "BBB"),
        )
        line = render.render(segments, {"a": 0, "gone": 1, "b": 0})
        self.assertEqual(render.ANSI_SEQUENCE.sub("", line), "AAA │ BBB")

    def test_drops_a_whole_group_without_a_dangling_separator(self):
        segments = (
            segment("a", "a", "AAA"),
            segment("five", "rate", "5h:42%", fit.DROP),
            segment("seven", "rate", "7d:7%", fit.DROP),
        )
        line = render.render(segments, {"a": 0, "five": 1, "seven": 1})
        self.assertEqual(render.ANSI_SEQUENCE.sub("", line), "AAA")

    def test_is_empty_when_every_segment_is_dropped(self):
        segments = (segment("a", "a", "AAA", fit.DROP),)
        self.assertEqual(render.render(segments, {"a": 1}), "")

    def test_separator_is_dim_grey_and_resets(self):
        segments = (segment("a", "a", "AAA"), segment("b", "b", "BBB"))
        self.assertIn(
            f"{palette.DIM_GRAY} │ {palette.RESET}",
            render.render(segments, {"a": 0, "b": 0}),
        )


class MeasureWith(unittest.TestCase):
    def test_measures_the_line_render_would_produce(self):
        segments = (
            segment("a", "a", f"{palette.CYAN}AAA{palette.RESET}"),
            segment("b", "b", "BBB"),
        )
        measure = render.measure_with(segments)
        chosen = {"a": 0, "b": 0}
        self.assertEqual(
            measure(chosen), render.visible_width(render.render(segments, chosen))
        )
        self.assertEqual(measure(chosen), 9)  # AAA + " | " + BBB

    def test_is_usable_as_fits_measure_parameter(self):
        segments = (segment("a", "a", "AAAAAAAA", "AA"), segment("b", "b", "BBB"))
        chosen = fit.fit(segments, 8, render.measure_with(segments))
        self.assertEqual(chosen, {"a": 1, "b": 0})

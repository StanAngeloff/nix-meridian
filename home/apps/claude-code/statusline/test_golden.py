"""The whole line, for one fixed payload, at the widths that matter.

The invariants are the contract. The recorded strings are a characterisation of today's penalty
table: when a penalty changes they change too, and the diff is the point -- it shows exactly which
segment gave way at which width.
"""

import unittest

import fit
import main
import render
import segments

NOW = 1_800_000_000

PAYLOAD = {
    "model": {"id": "claude-opus-4-6[1m]", "display_name": "Opus 4.6 (1M context)"},
    "cwd": "/home/stan/nix-meridian",
    "cost": {
        "total_cost_usd": 1.234,
        "total_duration_ms": 720_000,
        "total_lines_added": 5,
        "total_lines_removed": 2,
    },
    "context_window": {
        "context_window_size": 1_000_000,
        "used_percentage": 34.0,
        "total_input_tokens": 100,
        "total_output_tokens": 50,
        "current_usage": {
            "input_tokens": 10,
            "output_tokens": 20,
            "cache_creation_input_tokens": 30,
        },
    },
    "exceeds_200k_tokens": False,
    "rate_limits": {
        "five_hour": {"used_percentage": 42.0, "resets_at": NOW + 7_800},
        "seven_day": {"used_percentage": 7.0},
    },
}

WIDTHS = (30, 45, 60, 80, 100, 120)


def built():
    return segments.build(PAYLOAD, branch="trunk", now_epoch=NOW)


def line_at(columns):
    return main.line_for(
        PAYLOAD, "trunk", NOW, main.budget_from({"COLUMNS": str(columns)})
    )


def plain_at(columns):
    return render.ANSI_SEQUENCE.sub("", line_at(columns))


class Invariants(unittest.TestCase):
    def test_never_overflows_unless_nothing_can_be_shortened(self):
        segments_built = built()
        measure = render.measure_with(segments_built)
        for columns in range(20, 201):
            budget = main.budget_from({"COLUMNS": str(columns)})
            chosen = fit.fit(segments_built, budget, measure)
            if measure(chosen) > budget:
                self.assertIsNone(
                    fit.cheapest_step(segments_built, chosen, measure),
                    f"at {columns} columns the line overflows but could still be shortened",
                )

    def test_narrowing_never_restores_a_segment_or_lengthens_a_form(self):
        segments_built = built()
        measure = render.measure_with(segments_built)
        previous = None
        for columns in range(200, 19, -1):
            chosen = fit.fit(
                segments_built, main.budget_from({"COLUMNS": str(columns)}), measure
            )
            if previous is not None:
                for key, level in chosen.items():
                    self.assertGreaterEqual(
                        level, previous[key], f"{key} got richer at {columns}"
                    )
            previous = chosen

    def test_the_laptop_view_is_untouched(self):
        # At 120 columns the budget is 116 and the full line is about 105, so nothing degrades.
        segments_built = built()
        chosen = fit.fit(segments_built, 116, render.measure_with(segments_built))
        self.assertEqual(chosen, fit.richest(segments_built))

    def test_context_and_the_five_hour_window_outlive_everything_else(self):
        plain = plain_at(30)
        self.assertIn("34%", plain)
        self.assertIn("5h", plain)


class GoldenLines(unittest.TestCase):
    EXPECTED = {
        30: "✦ O4.6 │ 34% │ 5h42 7d7",
        45: "✦ Opus 4.6 │ trunk │ 34% │ 5h:42% 7d:7%",
        60: "✦ Opus 4.6 │ trunk │ +5/-2 │ ██---- 34% │ 5h:42% 7d:7%",
        80: "✦ Opus 4.6 (1m) │ trunk │ $1.23 │ 12m │ +5/-2 │ ██---- 34% │ 5h:42% 7d:7%",
        100: "✦ Opus 4.6 (1m) │ trunk │ $1.23 │ 12m │ +5/-2 │ 10↑ 20↓ 30◌ Σ150 │ ███------- 34% │ 5h:42% 7d:7%",
        120: "✦ claude-opus-4-6 (1m) │ trunk │ $1.23 │ 12m │ +5/-2 │ 10↑ 20↓ 30◌ Σ150 │ ███------- 34% │ 5h:42% 7d:7%",
    }

    def test_renders_the_recorded_line_at_each_width(self):
        for columns in WIDTHS:
            with self.subTest(columns=columns):
                self.assertEqual(plain_at(columns), self.EXPECTED[columns])

    def test_every_recorded_line_fits_its_budget(self):
        for columns in WIDTHS:
            with self.subTest(columns=columns):
                budget = main.budget_from({"COLUMNS": str(columns)})
                self.assertLessEqual(
                    render.visible_width(self.EXPECTED[columns]), budget
                )

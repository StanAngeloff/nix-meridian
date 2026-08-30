import unittest

import palette
import render
import segments

NOW = 1_800_000_000

FULL_PAYLOAD = {
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
        "used_percentage": 34.4,
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


def plain(segment, level):
    return render.ANSI_SEQUENCE.sub("", segment.forms[level].text)


def by_key(payload, key, **kwargs):
    for segment in segments.build(payload, **kwargs):
        if segment.key == key:
            return segment
    return None


class Helpers(unittest.TestCase):
    def test_human_count_matches_the_shell_implementation(self):
        self.assertEqual(segments.human_count(999), "999")
        self.assertEqual(segments.human_count(1_234), "1.2k")
        self.assertEqual(segments.human_count(1_234_567), "1.2m")

    def test_context_label_uses_integer_units(self):
        self.assertEqual(segments.context_label(1_000_000), " (1m)")
        self.assertEqual(segments.context_label(200_000), " (200k)")
        self.assertEqual(segments.context_label(None), "")

    def test_percent_of_rounds_half_away_from_zero_like_printf(self):
        self.assertEqual(segments.percent_of(34.4), 34)
        self.assertEqual(segments.percent_of(34.5), 35)

    def test_reset_countdown_formats_hours_and_minutes(self):
        self.assertEqual(segments.reset_countdown(NOW + 7_800, NOW), "2h10m")
        self.assertEqual(segments.reset_countdown(NOW + 600, NOW), "10m")

    def test_reset_countdown_is_empty_when_unknown_or_past(self):
        self.assertEqual(segments.reset_countdown(None, NOW), "")
        self.assertEqual(segments.reset_countdown("nonsense", NOW), "")
        self.assertEqual(segments.reset_countdown(NOW - 1, NOW), "")


class ModelName(unittest.TestCase):
    def test_strips_the_variant_annotation_from_display_name(self):
        self.assertEqual(
            segments.model_name({"display_name": "Opus 4.6 (1M context)"}), "Opus 4.6"
        )
        self.assertEqual(segments.model_name({"display_name": "Sonnet 5"}), "Sonnet 5")

    def test_falls_back_to_deriving_the_name_from_the_identifier(self):
        self.assertEqual(segments.model_name({"id": "claude-opus-4-6[1m]"}), "Opus 4.6")
        self.assertEqual(segments.model_name({"id": "claude-sonnet-5"}), "Sonnet 5")

    def test_initials_keep_the_version(self):
        self.assertEqual(segments.model_initials("Opus 4.6"), "O4.6")
        self.assertEqual(segments.model_initials("Sonnet 5"), "S5")


class ModelSegment(unittest.TestCase):
    def test_forms_shorten_from_identifier_to_initials(self):
        model = by_key(FULL_PAYLOAD, "model")
        self.assertEqual(
            [plain(model, level) for level in range(len(model.forms))],
            [
                "✦ claude-opus-4-6 (1m)",
                "✦ Opus 4.6 (1m)",
                "✦ Opus 4.6",
                "✦ O4.6",
            ],
        )

    def test_has_no_drop(self):
        model = by_key(FULL_PAYLOAD, "model")
        self.assertTrue(all(form.text for form in model.forms))

    def test_penalties_match_the_table(self):
        model = by_key(FULL_PAYLOAD, "model")
        self.assertEqual([form.penalty for form in model.forms], [0, 2, 5, 14])

    def test_context_label_comes_from_the_window_size_not_display_name(self):
        # Sonnet 5 is a one-million-token model whose display_name says nothing about it.
        payload = dict(FULL_PAYLOAD)
        payload["model"] = {"id": "claude-sonnet-5", "display_name": "Sonnet 5"}
        model = by_key(payload, "model")
        self.assertEqual(plain(model, 1), "✦ Sonnet 5 (1m)")


class ContextSegment(unittest.TestCase):
    def test_bar_narrows_then_disappears(self):
        ctx = by_key(FULL_PAYLOAD, "ctx")
        self.assertEqual(
            [plain(ctx, level) for level in range(len(ctx.forms))],
            ["███------- 34%", "██---- 34%", "34%"],
        )

    def test_penalties_match_the_table(self):
        self.assertEqual(
            [form.penalty for form in by_key(FULL_PAYLOAD, "ctx").forms], [0, 2, 8]
        )

    def test_is_green_normally_and_amber_beyond_two_hundred_thousand(self):
        self.assertIn(palette.PASTEL_GREEN, by_key(FULL_PAYLOAD, "ctx").forms[0].text)
        payload = dict(FULL_PAYLOAD, exceeds_200k_tokens=True)
        self.assertIn(palette.AMBER, by_key(payload, "ctx").forms[0].text)

    def test_has_no_drop(self):
        self.assertTrue(all(form.text for form in by_key(FULL_PAYLOAD, "ctx").forms))


class RateLimitSegments(unittest.TestCase):
    def test_five_hour_omits_the_countdown_below_half(self):
        five = by_key(FULL_PAYLOAD, "five_hour", now_epoch=NOW)
        self.assertEqual(
            [plain(five, level) for level in range(len(five.forms))],
            ["5h:42%", "5h42", ""],
        )
        self.assertEqual([form.penalty for form in five.forms], [0, 6, 60])

    def test_five_hour_gains_the_countdown_at_or_above_half(self):
        payload = dict(FULL_PAYLOAD)
        payload["rate_limits"] = {
            "five_hour": {"used_percentage": 61.0, "resets_at": NOW + 7_800},
            "seven_day": {"used_percentage": 7.0},
        }
        five = by_key(payload, "five_hour", now_epoch=NOW)
        self.assertEqual(
            [plain(five, level) for level in range(len(five.forms))],
            ["5h:61% (resets 2h10m)", "5h:61%", "5h61", ""],
        )
        self.assertEqual([form.penalty for form in five.forms], [0, 4, 10, 60])

    def test_seven_day_forms_and_penalties(self):
        seven = by_key(FULL_PAYLOAD, "seven_day")
        self.assertEqual(
            [plain(seven, level) for level in range(len(seven.forms))],
            ["7d:7%", "7d7", ""],
        )
        self.assertEqual([form.penalty for form in seven.forms], [0, 3, 20])

    def test_both_share_the_rate_group(self):
        self.assertEqual(by_key(FULL_PAYLOAD, "five_hour").group, "rate")
        self.assertEqual(by_key(FULL_PAYLOAD, "seven_day").group, "rate")


class BranchSegment(unittest.TestCase):
    def test_short_branch_without_separator_has_no_prefix_form(self):
        branch = by_key(FULL_PAYLOAD, "branch", branch="trunk")
        self.assertEqual(
            [plain(branch, level) for level in range(len(branch.forms))],
            ["trunk", "trunk", ""],
        )

    def test_long_branch_without_separator_truncates_to_twelve_columns(self):
        branch = by_key(FULL_PAYLOAD, "branch", branch="very-long-branch-name")
        self.assertEqual(plain(branch, 1), "very-long-b…")
        self.assertEqual(render.visible_width(branch.forms[1].text), 12)

    def test_branch_with_separator_degrades_to_prefix(self):
        branch = by_key(FULL_PAYLOAD, "branch", branch="sc-54321/story-title-goes-here")
        self.assertEqual(
            [plain(branch, level) for level in range(len(branch.forms))],
            ["sc-54321/story-title-goes-here", "sc-54321", ""],
        )

    def test_prefix_degrades_cheaply_so_other_segments_keep_their_rich_forms(self):
        branch = by_key(FULL_PAYLOAD, "branch", branch="sc-54321/story-title-goes-here")
        self.assertEqual(
            [f.penalty for f in branch.forms],
            [0, 1, 30],
        )

    def test_prefix_form_handles_all_separator_characters(self):
        for separator in ["/", "+", "@", "#", ".", "!", "?"]:
            name = f"prefix{separator}rest"
            branch = by_key(FULL_PAYLOAD, "branch", branch=name)
            forms = [plain(branch, level) for level in range(len(branch.forms))]
            self.assertIn(
                "prefix", forms, f"separator {separator!r} should yield prefix form"
            )

    def test_absent_without_a_branch(self):
        self.assertIsNone(by_key(FULL_PAYLOAD, "branch", branch=""))

    def test_penalties_without_separator(self):
        self.assertEqual(
            [f.penalty for f in by_key(FULL_PAYLOAD, "branch", branch="trunk").forms],
            [0, 5, 30],
        )

    def test_link_wraps_branch_when_github_url_is_provided(self):
        branch = by_key(
            FULL_PAYLOAD,
            "branch",
            branch="trunk",
            github_url="https://github.com/user/repo",
        )
        self.assertIn(
            "\x1b]8;;https://github.com/user/repo/tree/trunk\x1b\\",
            branch.forms[0].text,
        )
        self.assertIn("\x1b]8;;\x1b\\", branch.forms[0].text)

    def test_link_uses_full_branch_in_url_even_when_text_is_prefix(self):
        branch = by_key(
            FULL_PAYLOAD,
            "branch",
            branch="sc-54321/story-title",
            github_url="https://github.com/user/repo",
        )
        self.assertEqual(plain(branch, 1), "sc-54321")
        self.assertIn("/tree/sc-54321/story-title", branch.forms[1].text)

    def test_link_costs_zero_visible_columns(self):
        plain_branch = by_key(FULL_PAYLOAD, "branch", branch="trunk")
        linked_branch = by_key(
            FULL_PAYLOAD,
            "branch",
            branch="trunk",
            github_url="https://github.com/user/repo",
        )
        self.assertEqual(
            render.visible_width(plain_branch.forms[0].text),
            render.visible_width(linked_branch.forms[0].text),
        )

    def test_no_link_without_github_url(self):
        branch = by_key(FULL_PAYLOAD, "branch", branch="trunk")
        self.assertNotIn("\x1b]8", branch.forms[0].text)


class CheapSegments(unittest.TestCase):
    def test_cost_rounds_to_cents_and_can_be_dropped(self):
        cost = by_key(FULL_PAYLOAD, "cost")
        self.assertEqual(
            [plain(cost, level) for level in range(len(cost.forms))], ["$1.23", ""]
        )
        self.assertEqual([form.penalty for form in cost.forms], [0, 5])

    def test_duration_uses_hours_when_present(self):
        self.assertEqual(plain(by_key(FULL_PAYLOAD, "duration"), 0), "12m")
        payload = dict(
            FULL_PAYLOAD, cost=dict(FULL_PAYLOAD["cost"], total_duration_ms=3_960_000)
        )
        self.assertEqual(plain(by_key(payload, "duration"), 0), "1h6m")

    def test_diff_shows_both_counts(self):
        diff = by_key(FULL_PAYLOAD, "diff")
        self.assertEqual(
            [plain(diff, level) for level in range(len(diff.forms))], ["+5/-2", ""]
        )
        self.assertEqual([form.penalty for form in diff.forms], [0, 6])

    def test_tokens_collapse_to_the_total_before_dropping(self):
        tokens = by_key(FULL_PAYLOAD, "tokens")
        self.assertEqual(
            [plain(tokens, level) for level in range(len(tokens.forms))],
            ["10↑ 20↓ 30◌ Σ150", "Σ150", ""],
        )
        self.assertEqual([form.penalty for form in tokens.forms], [0, 4, 8])


class Ordering(unittest.TestCase):
    def test_segments_render_in_the_established_order(self):
        keys = [
            s.key for s in segments.build(FULL_PAYLOAD, branch="trunk", now_epoch=NOW)
        ]
        self.assertEqual(
            keys,
            [
                "model",
                "branch",
                "cost",
                "duration",
                "diff",
                "tokens",
                "ctx",
                "five_hour",
                "seven_day",
            ],
        )


class DegeneratePayloads(unittest.TestCase):
    def test_a_session_with_no_api_calls_yet_has_no_rate_limits(self):
        payload = {k: v for k, v in FULL_PAYLOAD.items() if k != "rate_limits"}
        keys = [s.key for s in segments.build(payload, branch="trunk", now_epoch=NOW)]
        self.assertNotIn("five_hour", keys)
        self.assertNotIn("seven_day", keys)
        self.assertIn("model", keys)

    def test_a_zero_cost_session_omits_cost(self):
        payload = dict(FULL_PAYLOAD, cost={"total_cost_usd": 0, "total_duration_ms": 0})
        self.assertIsNone(by_key(payload, "cost"))
        self.assertIsNone(by_key(payload, "duration"))

    def test_a_payload_with_no_current_usage_omits_tokens(self):
        payload = dict(
            FULL_PAYLOAD,
            context_window={"context_window_size": 200_000, "used_percentage": 1.0},
        )
        self.assertIsNone(by_key(payload, "tokens"))
        self.assertIsNotNone(by_key(payload, "ctx"))

    def test_an_empty_payload_produces_no_segments(self):
        self.assertEqual(segments.build({}), ())

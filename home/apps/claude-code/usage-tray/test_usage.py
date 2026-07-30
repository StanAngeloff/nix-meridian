import re
import unittest
from datetime import datetime

import usage


def _at(text):
    return datetime.fromisoformat(text)


def _text(markup):
    """Strip Pango tags and the leading offset, so content can be asserted on its own."""
    return re.sub(r"<[^>]+>", "", markup).replace(usage.ZERO_WIDTH_SPACE, "")


NOW = _at("2026-07-30T11:05:00+00:00")


class ParseSnapshot(unittest.TestCase):
    def test_reads_the_five_hour_and_seven_day_percentages(self):
        payload = {
            "five_hour": {
                "utilization": 11.0,
                "resets_at": "2026-07-30T11:20:00.547470+00:00",
            },
            "seven_day": {
                "utilization": 24.0,
                "resets_at": "2026-07-31T07:00:00.547488+00:00",
            },
            "limits": [],
        }

        snapshot = usage.parse_snapshot(payload, now=NOW)

        self.assertEqual(snapshot.five_hour.percent, 11)
        self.assertEqual(snapshot.seven_day.percent, 24)
        self.assertEqual(
            snapshot.five_hour.resets_at, _at("2026-07-30T11:20:00.547470+00:00")
        )

    def test_finds_the_scoped_model_limit_by_kind_and_name_not_by_position(self):
        payload = {
            "limits": [
                {"kind": "session", "percent": 11, "resets_at": None, "scope": None},
                {"kind": "weekly_all", "percent": 24, "resets_at": None, "scope": None},
                {
                    "kind": "weekly_scoped",
                    "percent": 21,
                    "resets_at": "2026-07-31T06:59:59.547715+00:00",
                    "scope": {
                        "model": {"id": None, "display_name": "Fable"},
                        "surface": None,
                    },
                },
            ]
        }

        snapshot = usage.parse_snapshot(payload, now=NOW)

        self.assertEqual([limit.title for limit in snapshot.scoped], ["Fable"])
        self.assertEqual(snapshot.scoped[0].percent, 21)

    def test_omits_the_scoped_limit_when_the_account_has_none(self):
        payload = {
            "five_hour": {"utilization": 11.0, "resets_at": None},
            "limits": [
                {"kind": "weekly_all", "percent": 24, "resets_at": None, "scope": None}
            ],
        }

        snapshot = usage.parse_snapshot(payload, now=NOW)

        self.assertEqual(snapshot.scoped, ())


class ParseCredits(unittest.TestCase):
    def test_reads_the_limit_as_minor_units(self):
        payload = {
            "limits": [],
            "extra_usage": {
                "is_enabled": True,
                "monthly_limit": 20000,
                "decimal_places": 2,
                "currency": "EUR",
            },
            "spend": {"used": {"amount_minor": 0, "currency": "EUR", "exponent": 2}},
        }

        credits = usage.parse_snapshot(payload, now=NOW).credits

        self.assertEqual(credits.limit, 200.00)
        self.assertEqual(credits.currency, "EUR")

    def test_takes_the_used_amount_from_spend_not_from_used_credits(self):
        payload = {
            "limits": [],
            "extra_usage": {
                "is_enabled": True,
                "monthly_limit": 20000,
                "decimal_places": 2,
                "currency": "EUR",
                "used_credits": 4500.0,
            },
            "spend": {"used": {"amount_minor": 4500, "currency": "EUR", "exponent": 2}},
        }

        credits = usage.parse_snapshot(payload, now=NOW).credits

        self.assertEqual(credits.used, 45.00)

    def test_omits_credits_when_extra_usage_is_disabled(self):
        payload = {
            "limits": [],
            "extra_usage": {"is_enabled": False, "monthly_limit": 20000},
        }

        self.assertIsNone(usage.parse_snapshot(payload, now=NOW).credits)

    def test_omits_the_used_amount_when_spend_is_absent(self):
        payload = {
            "limits": [],
            "extra_usage": {
                "is_enabled": True,
                "monthly_limit": 20000,
                "decimal_places": 2,
                "currency": "EUR",
            },
        }

        credits = usage.parse_snapshot(payload, now=NOW).credits

        self.assertEqual(credits.limit, 200.00)
        self.assertIsNone(credits.used)


class Backoff(unittest.TestCase):
    def test_a_healthy_poll_waits_the_normal_cadence(self):
        self.assertEqual(usage.poll_delay(consecutive_failures=0), 300)

    def test_each_failure_doubles_the_wait_up_to_a_five_minute_cap(self):
        delays = [usage.poll_delay(consecutive_failures=n) for n in range(6)]

        self.assertEqual(delays, [300, 600, 1200, 1800, 1800, 1800])

    def test_no_failure_count_ever_polls_faster_than_the_healthy_cadence(self):
        for failures in range(20):
            self.assertGreaterEqual(
                usage.poll_delay(consecutive_failures=failures), 300
            )


class RetryAfter(unittest.TestCase):
    def test_reads_a_delay_in_seconds(self):
        self.assertEqual(usage.parse_retry_after("120"), 120)

    def test_ignores_a_zero_delay_so_a_refusing_server_cannot_cause_a_tight_loop(self):
        # Observed live: the endpoint answers 429 with `retry-after: 0`.
        self.assertIsNone(usage.parse_retry_after("0"))

    def test_ignores_a_header_that_is_not_a_plain_count_of_seconds(self):
        # Retry-After may also be an HTTP date. Rather than parse two formats, fall back to the
        # normal backoff, which is never faster than the healthy cadence anyway.
        self.assertIsNone(usage.parse_retry_after("Wed, 21 Oct 2026 07:28:00 GMT"))
        self.assertIsNone(usage.parse_retry_after(""))
        self.assertIsNone(usage.parse_retry_after(None))

    def test_waits_at_least_as_long_as_the_server_asked(self):
        self.assertEqual(usage.poll_delay(consecutive_failures=0, retry_after=900), 900)

    def test_never_waits_less_than_our_own_backoff(self):
        # A server asking for 5s must not override the failure ladder, or a run of 429s becomes a
        # tight loop against an endpoint that is already refusing us.
        self.assertEqual(usage.poll_delay(consecutive_failures=3, retry_after=5), 1800)

    def test_caps_an_absurd_retry_after(self):
        self.assertEqual(
            usage.poll_delay(consecutive_failures=0, retry_after=86400), 3600
        )


class RestoringACachedSnapshot(unittest.TestCase):
    def test_a_recent_cache_is_worth_showing_while_the_first_poll_runs(self):
        earlier = _at("2026-07-30T10:30:00+00:00")

        self.assertTrue(usage.is_worth_restoring(earlier, now=NOW))

    def test_a_cache_older_than_every_window_is_not_worth_showing(self):
        # Past seven days both the session and weekly windows have reset, so the numbers describe
        # nothing. Better to show the loading state than confident nonsense.
        ancient = _at("2026-07-20T10:30:00+00:00")

        self.assertFalse(usage.is_worth_restoring(ancient, now=NOW))

    def test_nothing_to_restore_is_not_worth_restoring(self):
        self.assertFalse(usage.is_worth_restoring(None, now=NOW))


class Age(unittest.TestCase):
    def test_reports_minutes(self):
        self.assertEqual(
            usage.format_age(_at("2026-07-30T10:58:00+00:00"), NOW), "7m ago"
        )

    def test_reports_hours_and_minutes(self):
        self.assertEqual(
            usage.format_age(_at("2026-07-30T08:35:00+00:00"), NOW), "2h30m ago"
        )

    def test_reports_days_rather_than_a_large_hour_count(self):
        # Restoring a cache from disk makes long ages ordinary, and "51h05m ago" is hard to read.
        self.assertEqual(
            usage.format_age(_at("2026-07-28T08:00:00+00:00"), NOW), "2d ago"
        )


class ActivityPing(unittest.TestCase):
    def test_polls_at_once_when_the_budget_already_allows_it(self):
        self.assertEqual(
            usage.delay_after_activity(
                seconds_since_attempt=400, consecutive_failures=0
            ),
            0,
        )

    def test_waits_out_the_remaining_cadence_when_a_poll_was_recent(self):
        self.assertEqual(
            usage.delay_after_activity(
                seconds_since_attempt=100, consecutive_failures=0
            ),
            200,
        )

    def test_activity_does_not_shorten_a_backoff(self):
        # A statusline ping proves inference is working, not that the metadata endpoint has stopped
        # refusing us — they are separate budgets. Pinging must not pull the ladder in.
        self.assertEqual(
            usage.delay_after_activity(
                seconds_since_attempt=9999, consecutive_failures=3
            ),
            1800,
        )

    def test_never_polls_faster_than_the_cadence_however_often_it_is_pinged(self):
        for elapsed in range(0, 300, 25):
            self.assertGreaterEqual(
                usage.delay_after_activity(
                    seconds_since_attempt=elapsed, consecutive_failures=0
                ),
                300 - elapsed,
            )


class Staleness(unittest.TestCase):
    def test_one_failure_does_not_make_the_data_stale(self):
        self.assertFalse(
            usage.is_stale(consecutive_failures=1, fetched_at=NOW, now=NOW)
        )

    def test_two_consecutive_failures_make_the_data_stale(self):
        self.assertTrue(usage.is_stale(consecutive_failures=2, fetched_at=NOW, now=NOW))

    def test_data_older_than_the_stale_ceiling_is_stale_even_without_failures(self):
        later = _at("2026-07-30T11:16:00+00:00")

        self.assertTrue(
            usage.is_stale(consecutive_failures=0, fetched_at=NOW, now=later)
        )

    def test_data_with_no_successful_fetch_yet_is_not_stale_but_loading(self):
        self.assertFalse(
            usage.is_stale(consecutive_failures=0, fetched_at=None, now=NOW)
        )


class PanelLabel(unittest.TestCase):
    def _snapshot(self):
        return usage.parse_snapshot(
            {
                "five_hour": {"utilization": 11.0, "resets_at": None},
                "seven_day": {"utilization": 24.0, "resets_at": None},
                "limits": [],
            },
            now=NOW,
        )

    def test_dims_the_prefixes_and_brightens_the_numbers_when_fresh(self):
        # Same two colours the tmux status line uses, so the panel and the terminal agree.
        self.assertEqual(
            usage.panel_label(self._snapshot(), stale=False),
            "\u200b"
            '<span foreground="#377880">'
            '5h:<span foreground="#56b6c2">11%</span>'
            ' 7d:<span foreground="#56b6c2">24%</span>'
            "</span>",
        )

    def test_dims_the_whole_label_when_stale(self):
        self.assertEqual(
            usage.panel_label(self._snapshot(), stale=True),
            '\u200b<span foreground="#646464">5h:11% 7d:24%</span>',
        )

    def test_shows_an_ellipsis_before_the_first_poll_succeeds(self):
        self.assertEqual(
            usage.panel_label(None, stale=False),
            '\u200b<span foreground="#646464">…</span>',
        )

    def test_the_loading_label_is_distinguishable_from_the_stale_label(self):
        loading = usage.panel_label(None, stale=False)
        stale = usage.panel_label(self._snapshot(), stale=True)

        self.assertNotEqual(loading, stale)


class ResetWording(unittest.TestCase):
    def test_uses_a_relative_time_within_the_next_day(self):
        self.assertEqual(
            usage.format_reset(_at("2026-07-30T11:20:00+00:00"), now=NOW),
            "resets in 15m",
        )

    def test_includes_hours_in_a_relative_time_when_there_are_some(self):
        self.assertEqual(
            usage.format_reset(_at("2026-07-30T14:35:00+00:00"), now=NOW),
            "resets in 3h30m",
        )

    def test_uses_a_weekday_and_clock_time_for_a_weekly_reset_under_a_day_away(self):
        # The real 7-day reset sits about 20 hours out, so a plain 24-hour threshold would wrongly
        # render it as a countdown. Anything past the session window reads better as a wall time.
        self.assertEqual(
            usage.format_reset(_at("2026-07-31T07:00:00+00:00"), now=NOW),
            "resets Fri 07:00",
        )

    def test_says_nothing_when_there_is_no_reset_time(self):
        self.assertEqual(usage.format_reset(None, now=NOW), "")


class Bar(unittest.TestCase):
    def test_fills_one_cell_per_ten_percent(self):
        self.assertEqual(usage.bar(40), "▓▓▓▓░░░░░░")

    def test_shows_an_empty_bar_at_zero(self):
        self.assertEqual(usage.bar(0), "░░░░░░░░░░")

    def test_shows_at_least_one_cell_for_any_use_at_all(self):
        self.assertEqual(usage.bar(4), "▓░░░░░░░░░")

    def test_never_overflows_past_ten_cells(self):
        self.assertEqual(usage.bar(140), "▓▓▓▓▓▓▓▓▓▓")


FULL_PAYLOAD = {
    "five_hour": {"utilization": 11.0, "resets_at": "2026-07-30T11:20:00.547470+00:00"},
    "seven_day": {"utilization": 24.0, "resets_at": "2026-07-31T07:00:00.547488+00:00"},
    "extra_usage": {
        "is_enabled": True,
        "monthly_limit": 20000,
        "decimal_places": 2,
        "currency": "EUR",
    },
    "spend": {"used": {"amount_minor": 0, "currency": "EUR", "exponent": 2}},
    "limits": [
        {
            "kind": "weekly_scoped",
            "percent": 21,
            "resets_at": "2026-07-31T06:59:59.547715+00:00",
            "scope": {"model": {"id": None, "display_name": "Fable"}, "surface": None},
        }
    ],
}


class MenuRows(unittest.TestCase):
    def test_lists_every_limit_then_the_credits(self):
        snapshot = usage.parse_snapshot(FULL_PAYLOAD, now=NOW)

        rows = usage.menu_rows(snapshot, stale=False, now=NOW)

        self.assertEqual(
            [_text(row) for row in rows],
            [
                "5-hour     ▓░░░░░░░░░   11%   resets in 15m",
                "7-day      ▓▓░░░░░░░░   24%   resets Fri 07:00",
                "Fable      ▓▓░░░░░░░░   21%   resets Fri 06:59",
                "Credits    €0.00 / €200.00",
            ],
        )

    def test_every_row_is_monospaced_so_the_columns_line_up(self):
        snapshot = usage.parse_snapshot(FULL_PAYLOAD, now=NOW)

        rows = usage.menu_rows(snapshot, stale=False, now=NOW)

        for row in rows:
            self.assertIn("<tt>", row)
            self.assertTrue(row.endswith("</tt>"), row)

    def test_escapes_a_model_name_that_would_otherwise_break_the_markup(self):
        # The title comes from scope.model.display_name in the payload, so it is external text and
        # a bare ampersand would make the whole row fail to parse as markup.
        payload = dict(
            FULL_PAYLOAD,
            limits=[
                {
                    "kind": "weekly_scoped",
                    "percent": 21,
                    "resets_at": None,
                    "scope": {"model": {"id": None, "display_name": "A&B<C"}},
                }
            ],
        )
        snapshot = usage.parse_snapshot(payload, now=NOW)

        rows = usage.menu_rows(snapshot, stale=False, now=NOW)

        scoped_row = [row for row in rows if "A&amp;B&lt;C" in row]
        self.assertEqual(len(scoped_row), 1, rows)

    def test_titles_and_reset_times_keep_the_menu_default_colour(self):
        # The popover background is lighter than the terminal's, so the dim teal that reads fine in
        # tmux turns to mud here. Only the data is coloured; the rest inherits the theme.
        snapshot = usage.parse_snapshot(FULL_PAYLOAD, now=NOW)

        rows = usage.menu_rows(snapshot, stale=False, now=NOW)

        self.assertIn("<tt>5-hour", rows[0])
        self.assertTrue(rows[0].endswith("resets in 15m</tt>"), rows[0])

    def test_uses_the_alpha_compensated_palette_because_rows_are_insensitive(self):
        # Insensitive rows render at alpha 0.4, and Pango foreground sets RGB but not alpha, so the
        # panel's colours arrive at 40% and look muddy. The menu needs brighter source colours.
        snapshot = usage.parse_snapshot(FULL_PAYLOAD, now=NOW)

        rows = usage.menu_rows(snapshot, stale=False, now=NOW)

        self.assertIn(usage.MENU_VALUE_COLOUR, rows[0])
        self.assertIn(usage.MENU_MUTED_COLOUR, rows[0])
        self.assertNotIn(usage.VALUE_COLOUR, rows[0])
        self.assertNotIn(usage.PREFIX_COLOUR, rows[0])

    def test_dims_every_row_when_stale(self):
        snapshot = usage.parse_snapshot(FULL_PAYLOAD, now=NOW)

        rows = usage.menu_rows(snapshot, stale=True, now=NOW)

        for row in rows:
            self.assertIn(usage.MENU_STALE_COLOUR, row)
            self.assertNotIn(usage.MENU_VALUE_COLOUR, row)

    def test_drops_the_credits_row_when_extra_usage_is_disabled(self):
        payload = dict(FULL_PAYLOAD, extra_usage={"is_enabled": False})
        snapshot = usage.parse_snapshot(payload, now=NOW)

        rows = usage.menu_rows(snapshot, stale=False, now=NOW)

        self.assertFalse([row for row in rows if "Credits" in row])

    def test_drops_the_scoped_row_when_the_account_has_no_scoped_limit(self):
        payload = dict(FULL_PAYLOAD, limits=[])
        snapshot = usage.parse_snapshot(payload, now=NOW)

        rows = usage.menu_rows(snapshot, stale=False, now=NOW)

        self.assertFalse([row for row in rows if "Fable" in row])

    def test_says_how_old_the_numbers_are_when_stale(self):
        snapshot = usage.parse_snapshot(FULL_PAYLOAD, now=NOW)
        later = _at("2026-07-30T11:12:00+00:00")

        rows = usage.menu_rows(snapshot, stale=True, now=later)

        self.assertIn("Last updated 7m ago", _text(rows[-1]))

    def test_names_the_actual_reason_the_refresh_failed(self):
        snapshot = usage.parse_snapshot(FULL_PAYLOAD, now=NOW)
        later = _at("2026-07-30T11:12:00+00:00")

        rows = usage.menu_rows(
            snapshot, stale=True, now=later, reason="network unreachable"
        )

        self.assertEqual(_text(rows[-1]), "Last updated 7m ago — network unreachable")

    def test_gives_the_age_alone_when_there_is_no_reason_to_report(self):
        snapshot = usage.parse_snapshot(FULL_PAYLOAD, now=NOW)
        later = _at("2026-07-30T11:12:00+00:00")

        rows = usage.menu_rows(snapshot, stale=True, now=later)

        self.assertEqual(_text(rows[-1]), "Last updated 7m ago")

    def test_says_it_is_loading_before_the_first_poll(self):
        self.assertEqual(
            [_text(r) for r in usage.menu_rows(None, stale=False, now=NOW)], ["Loading"]
        )


class SignedOut(unittest.TestCase):
    def test_the_panel_says_so_when_there_are_no_credentials_and_no_history(self):
        self.assertEqual(
            usage.panel_label(None, stale=False, signed_out=True),
            '\u200b<span foreground="#646464">?</span>',
        )

    def test_the_menu_says_so_when_there_are_no_credentials_and_no_history(self):
        self.assertEqual(
            [
                _text(row)
                for row in usage.menu_rows(None, stale=False, now=NOW, signed_out=True)
            ],
            ["Not signed in"],
        )

    def test_previous_numbers_still_show_when_the_credentials_go_away(self):
        # Losing the token is just another failure. Stale numbers beat no numbers, so the
        # signed-out wording only applies when nothing was ever fetched.
        snapshot = usage.parse_snapshot(FULL_PAYLOAD, now=NOW)

        self.assertEqual(
            usage.panel_label(snapshot, stale=True, signed_out=True),
            '\u200b<span foreground="#646464">5h:11% 7d:24%</span>',
        )


if __name__ == "__main__":
    unittest.main()

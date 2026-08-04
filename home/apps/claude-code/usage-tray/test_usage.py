import re
import unittest
from datetime import datetime

import usage


def _at(text):
    return datetime.fromisoformat(text)


def _epoch(moment):
    """The status line reports reset times as epoch seconds, not as ISO strings."""
    return int(moment.timestamp())


def _text(markup):
    """Strip Pango tags and the leading offset, so content can be asserted on its own."""
    return re.sub(r"<[^>]+>", "", markup).replace(usage.ZERO_WIDTH_SPACE, "")


NOW = _at("2026-07-30T11:05:00+00:00")


def _view(payload=None, activity=None, now=NOW):
    """A merged view, which is what panel_label and menu_rows take."""
    snapshot = usage.parse_snapshot(payload, now=now) if payload is not None else None
    return usage.compose(snapshot, activity, now=now)


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


class ParseActivity(unittest.TestCase):
    """The status line hands over its own `rate_limits` object verbatim.

    Its shape is not the endpoint's: percentages are `used_percentage`, and reset times are epoch
    seconds rather than ISO strings.
    """

    def test_reads_both_windows_and_their_epoch_reset_times(self):
        activity = usage.parse_activity(
            {
                "five_hour": {"used_percentage": 19.4, "resets_at": _epoch(NOW) + 900},
                "seven_day": {
                    "used_percentage": 27.0,
                    "resets_at": _epoch(NOW) + 72000,
                },
            },
            observed_at=NOW,
        )

        self.assertEqual(activity.five_hour.percent, 19)
        self.assertEqual(activity.seven_day.percent, 27)
        self.assertEqual(activity.five_hour.resets_at, _at("2026-07-30T11:20:00+00:00"))
        self.assertEqual(activity.observed_at, NOW)

    def test_tolerates_a_window_without_a_reset_time(self):
        activity = usage.parse_activity(
            {"five_hour": {"used_percentage": 19.4}}, observed_at=NOW
        )

        self.assertIsNone(activity.five_hour.resets_at)
        self.assertIsNone(activity.seven_day)

    def test_is_nothing_when_neither_window_is_reported(self):
        self.assertIsNone(usage.parse_activity({}, observed_at=NOW))
        self.assertIsNone(usage.parse_activity({"five_hour": {}}, observed_at=NOW))
        self.assertIsNone(usage.parse_activity(None, observed_at=NOW))

    def test_is_nothing_for_the_bare_percentage_an_older_hook_wrote(self):
        # The previous hook wrote just the five-hour percentage, which is legal JSON and so arrives
        # here as an integer. A session still running that hook must read as "no figures" rather than
        # as a reading of nothing, or it would clear a current session's numbers.
        self.assertIsNone(usage.parse_activity(19, observed_at=NOW))
        self.assertIsNone(usage.parse_activity("19", observed_at=NOW))


class ComposingSources(unittest.TestCase):
    """Two feeds with different reach: the status line has the windows, the endpoint has the rest."""

    def _snapshot(self, at):
        return usage.parse_snapshot(
            {
                "five_hour": {"utilization": 11.0, "resets_at": None},
                "seven_day": {"utilization": 24.0, "resets_at": None},
                "limits": [
                    {
                        "kind": "weekly_scoped",
                        "percent": 21,
                        "resets_at": None,
                        "scope": {"model": {"display_name": "Fable"}},
                    }
                ],
            },
            now=at,
        )

    def test_a_newer_status_line_reading_wins_the_windows(self):
        stale_at = _at("2026-07-30T10:30:00+00:00")
        activity = usage.parse_activity(
            {
                "five_hour": {"used_percentage": 19.0},
                "seven_day": {"used_percentage": 27.0},
            },
            observed_at=NOW,
        )

        view = usage.compose(self._snapshot(stale_at), activity, now=NOW)

        self.assertEqual(view.five_hour.percent, 19)
        self.assertEqual(view.seven_day.percent, 27)
        self.assertEqual(view.windows_at, NOW)
        self.assertTrue(view.windows_from_activity)

    def test_the_endpoint_still_owns_fable_and_credits_however_fresh_the_ping(self):
        # The status line has no scoped window at all, so a ping must never drop Fable.
        activity = usage.parse_activity(
            {"five_hour": {"used_percentage": 19.0}}, observed_at=NOW
        )
        snapshot_at = _at("2026-07-30T10:30:00+00:00")

        view = usage.compose(self._snapshot(snapshot_at), activity, now=NOW)

        self.assertEqual([limit.title for limit in view.scoped], ["Fable"])
        self.assertEqual(view.details_at, snapshot_at)

    def test_a_fresh_poll_wins_over_an_older_ping(self):
        old_ping = usage.parse_activity(
            {"five_hour": {"used_percentage": 19.0}},
            observed_at=_at("2026-07-30T10:30:00+00:00"),
        )

        view = usage.compose(self._snapshot(NOW), old_ping, now=NOW)

        self.assertEqual(view.five_hour.percent, 11)
        self.assertFalse(view.windows_from_activity)

    def test_a_ping_alone_carries_the_panel_before_any_poll_succeeds(self):
        activity = usage.parse_activity(
            {"five_hour": {"used_percentage": 19.0}}, observed_at=NOW
        )

        view = usage.compose(None, activity, now=NOW)

        self.assertEqual(view.five_hour.percent, 19)
        self.assertEqual(view.scoped, ())
        self.assertIsNone(view.details_at)

    def test_nothing_from_either_source_is_an_empty_view(self):
        view = usage.compose(None, None, now=NOW)

        self.assertIsNone(view.five_hour)
        self.assertIsNone(view.windows_at)
        self.assertFalse(view.has_data)


class Cadence(unittest.TestCase):
    def test_a_live_status_line_makes_the_poll_rare(self):
        # While Claude Code is feeding the windows, the only thing a request still adds is Fable and
        # the credit balance, and neither moves fast enough to be worth a five-minute cadence.
        recent = _at("2026-07-30T11:04:00+00:00")

        self.assertEqual(usage.base_cadence(recent, now=NOW), 1800)

    def test_a_long_pause_returns_to_the_normal_cadence(self):
        old = _at("2026-07-30T10:55:00+00:00")

        self.assertEqual(usage.base_cadence(old, now=NOW), 300)

    def test_no_status_line_at_all_uses_the_normal_cadence(self):
        self.assertEqual(usage.base_cadence(None, now=NOW), 300)

    def test_the_backoff_ladder_starts_from_whichever_cadence_is_in_force(self):
        self.assertEqual(usage.poll_delay(0, base=1800), 1800)
        self.assertEqual(usage.poll_delay(1, base=300), 600)


class RequestSpacing(unittest.TestCase):
    """A floor under every trigger, not just the timer.

    One rewrite of the credentials file emits three file-monitor events, and a burst of simultaneous
    requests is what draws a 429 from a metadata endpoint even when the daily total is trivial.
    """

    def test_a_request_that_has_just_happened_forces_a_wait(self):
        self.assertEqual(usage.spacing_delay(0), usage.MINIMUM_REQUEST_SPACING_SECONDS)

    def test_the_wait_shrinks_as_the_last_request_recedes(self):
        self.assertEqual(usage.spacing_delay(20), 10)

    def test_no_wait_once_the_floor_has_passed(self):
        self.assertEqual(usage.spacing_delay(999), 0)

    def test_the_first_request_of_all_is_not_delayed(self):
        self.assertEqual(usage.spacing_delay(None), 0)


class Retiming(unittest.TestCase):
    """Re-timing may pull a poll in, never push it out.

    The old rule re-armed at the full backoff measured from now, so a ping every minute against a
    thirty-minute backoff moved the deadline out of reach and the tray never retried at all.
    """

    def test_a_ping_cannot_postpone_a_poll_that_is_already_due_sooner(self):
        self.assertEqual(usage.retime(1800, seconds_until_pending=120), 120)

    def test_a_ping_can_bring_a_poll_forward(self):
        self.assertEqual(usage.retime(30, seconds_until_pending=600), 30)

    def test_an_overdue_deadline_is_not_negative(self):
        self.assertEqual(usage.retime(1800, seconds_until_pending=-5), 0)

    def test_with_nothing_scheduled_the_delay_stands(self):
        self.assertEqual(usage.retime(1800, seconds_until_pending=None), 1800)


class Scheduling(unittest.TestCase):
    def test_only_a_completed_poll_may_push_the_next_one_further_out(self):
        postponed = usage.schedule_delay(
            1800,
            seconds_until_pending=120,
            seconds_since_attempt=600,
            may_postpone=True,
        )
        retimed = usage.schedule_delay(
            1800,
            seconds_until_pending=120,
            seconds_since_attempt=600,
            may_postpone=False,
        )

        self.assertEqual(postponed, 1800)
        self.assertEqual(retimed, 120)

    def test_the_floor_wins_over_a_nearer_deadline(self):
        # Honouring the spacing can move a deadline out, which is the one postponement allowed to
        # anybody: a request 5s after the last one is exactly what drew the 429s.
        self.assertEqual(
            usage.schedule_delay(
                0, seconds_until_pending=5, seconds_since_attempt=2, may_postpone=False
            ),
            28,
        )

    def test_a_session_pinging_forever_still_gets_a_poll(self):
        """The regression that started this: pings starved the retry completely.

        The old rule re-armed at the full backoff measured from now, so a ping every minute against a
        thirty-minute backoff moved the deadline out on every ping and no request ever happened.
        Simulated here over six hours of minute-by-minute pings.
        """
        pending = 1800.0
        since_attempt = 0.0
        polls = 0

        for minute in range(360):
            for _ in range(60):
                pending -= 1
                since_attempt += 1
                if pending <= 0:
                    polls += 1
                    since_attempt = 0.0
                    pending = usage.schedule_delay(
                        1800,
                        seconds_until_pending=None,
                        seconds_since_attempt=since_attempt,
                        may_postpone=True,
                    )
            # One ping per minute, each of which used to reset the deadline to the full backoff.
            pending = usage.schedule_delay(
                1800,
                seconds_until_pending=pending,
                seconds_since_attempt=since_attempt,
                may_postpone=False,
            )

        self.assertEqual(
            polls, 12, "six hours at a thirty-minute backoff is twelve polls"
        )

    def test_the_same_traffic_never_beats_the_request_floor(self):
        # The other half: whatever the trigger, two requests can never land inside the spacing.
        gaps = []
        pending = 0.0
        since_attempt = None
        elapsed = 0.0
        last_poll_at = None

        for _ in range(20000):
            elapsed += 1
            pending -= 1
            if since_attempt is not None:
                since_attempt += 1
            if pending <= 0:
                if last_poll_at is not None:
                    gaps.append(elapsed - last_poll_at)
                last_poll_at = elapsed
                since_attempt = 0.0
                pending = usage.schedule_delay(
                    300, None, since_attempt, may_postpone=True
                )
            if int(elapsed) % 7 == 0:
                # A burst-prone trigger firing far faster than any real one.
                pending = usage.schedule_delay(
                    0, pending, since_attempt, may_postpone=False
                )

        self.assertTrue(gaps)
        self.assertGreaterEqual(
            min(gaps),
            usage.MINIMUM_REQUEST_SPACING_SECONDS,
            f"closest pair: {min(gaps)}s",
        )


class Staleness(unittest.TestCase):
    def _view(self, windows_at, from_activity):
        activity = usage.parse_activity(
            {"five_hour": {"used_percentage": 19.0}}, observed_at=windows_at
        )
        if from_activity:
            return usage.compose(None, activity, now=windows_at)
        snapshot = usage.parse_snapshot(
            {"five_hour": {"utilization": 11.0}, "limits": []}, now=windows_at
        )
        return usage.compose(snapshot, None, now=windows_at)

    def test_one_failure_does_not_make_the_data_stale(self):
        view = self._view(NOW, from_activity=False)

        self.assertFalse(usage.is_stale(view, consecutive_failures=1, now=NOW))

    def test_two_consecutive_failures_make_polled_data_stale(self):
        view = self._view(NOW, from_activity=False)

        self.assertTrue(usage.is_stale(view, consecutive_failures=2, now=NOW))

    def test_failures_do_not_grey_out_numbers_the_status_line_just_supplied(self):
        # The whole point of the feed: a rate-limited endpoint says nothing about whether the
        # windows on screen are right, and while Claude Code is running they are.
        view = self._view(NOW, from_activity=True)

        self.assertFalse(usage.is_stale(view, consecutive_failures=9, now=NOW))

    def test_data_older_than_the_stale_ceiling_is_stale_whatever_fed_it(self):
        later = _at("2026-07-30T11:16:00+00:00")

        for from_activity in (True, False):
            view = self._view(NOW, from_activity=from_activity)

            self.assertTrue(usage.is_stale(view, consecutive_failures=0, now=later))

    def test_data_with_no_successful_fetch_yet_is_not_stale_but_loading(self):
        view = usage.compose(None, None, now=NOW)

        self.assertFalse(usage.is_stale(view, consecutive_failures=0, now=NOW))


class PanelLabel(unittest.TestCase):
    def _view(self):
        return _view(
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
            usage.panel_label(self._view(), stale=False),
            "\u200b"
            '<span foreground="#377880">'
            '5h:<span foreground="#56b6c2">11%</span>'
            ' 7d:<span foreground="#56b6c2">24%</span>'
            "</span>",
        )

    def test_dims_the_whole_label_when_stale(self):
        self.assertEqual(
            usage.panel_label(self._view(), stale=True),
            '\u200b<span foreground="#646464">5h:11% 7d:24%</span>',
        )

    def test_shows_an_ellipsis_before_the_first_poll_succeeds(self):
        self.assertEqual(
            usage.panel_label(_view(), stale=False),
            '\u200b<span foreground="#646464">…</span>',
        )

    def test_the_loading_label_is_distinguishable_from_the_stale_label(self):
        loading = usage.panel_label(_view(), stale=False)
        stale = usage.panel_label(self._view(), stale=True)

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
        view = _view(FULL_PAYLOAD)

        rows = usage.menu_rows(view, stale=False, now=NOW)

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
        view = _view(FULL_PAYLOAD)

        rows = usage.menu_rows(view, stale=False, now=NOW)

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
        view = _view(payload)

        rows = usage.menu_rows(view, stale=False, now=NOW)

        scoped_row = [row for row in rows if "A&amp;B&lt;C" in row]
        self.assertEqual(len(scoped_row), 1, rows)

    def test_titles_and_reset_times_keep_the_menu_default_colour(self):
        # The popover background is lighter than the terminal's, so the dim teal that reads fine in
        # tmux turns to mud here. Only the data is coloured; the rest inherits the theme.
        view = _view(FULL_PAYLOAD)

        rows = usage.menu_rows(view, stale=False, now=NOW)

        self.assertIn("<tt>5-hour", rows[0])
        self.assertTrue(rows[0].endswith("resets in 15m</tt>"), rows[0])

    def test_uses_the_alpha_compensated_palette_because_rows_are_insensitive(self):
        # Insensitive rows render at alpha 0.4, and Pango foreground sets RGB but not alpha, so the
        # panel's colours arrive at 40% and look muddy. The menu needs brighter source colours.
        view = _view(FULL_PAYLOAD)

        rows = usage.menu_rows(view, stale=False, now=NOW)

        self.assertIn(usage.MENU_VALUE_COLOUR, rows[0])
        self.assertIn(usage.MENU_MUTED_COLOUR, rows[0])
        self.assertNotIn(usage.VALUE_COLOUR, rows[0])
        self.assertNotIn(usage.PREFIX_COLOUR, rows[0])

    def test_dims_every_row_when_stale(self):
        view = _view(FULL_PAYLOAD)

        rows = usage.menu_rows(view, stale=True, now=NOW)

        for row in rows:
            self.assertIn(usage.MENU_STALE_COLOUR, row)
            self.assertNotIn(usage.MENU_VALUE_COLOUR, row)

    def test_drops_the_credits_row_when_extra_usage_is_disabled(self):
        payload = dict(FULL_PAYLOAD, extra_usage={"is_enabled": False})
        view = _view(payload)

        rows = usage.menu_rows(view, stale=False, now=NOW)

        self.assertFalse([row for row in rows if "Credits" in row])

    def test_drops_the_scoped_row_when_the_account_has_no_scoped_limit(self):
        payload = dict(FULL_PAYLOAD, limits=[])
        view = _view(payload)

        rows = usage.menu_rows(view, stale=False, now=NOW)

        self.assertFalse([row for row in rows if "Fable" in row])

    def test_says_how_old_the_numbers_are_when_stale(self):
        view = _view(FULL_PAYLOAD)
        later = _at("2026-07-30T11:12:00+00:00")

        rows = usage.menu_rows(view, stale=True, now=later)

        self.assertIn("Last updated 7m ago", _text(rows[-1]))

    def test_names_the_actual_reason_the_refresh_failed(self):
        view = _view(FULL_PAYLOAD)
        later = _at("2026-07-30T11:12:00+00:00")

        rows = usage.menu_rows(
            view, stale=True, now=later, reason="network unreachable"
        )

        self.assertEqual(_text(rows[-1]), "Last updated 7m ago — network unreachable")

    def test_gives_the_age_alone_when_there_is_no_reason_to_report(self):
        view = _view(FULL_PAYLOAD)
        later = _at("2026-07-30T11:12:00+00:00")

        rows = usage.menu_rows(view, stale=True, now=later)

        self.assertEqual(_text(rows[-1]), "Last updated 7m ago")

    def test_reports_the_endpoint_age_when_only_the_endpoint_rows_are_behind(self):
        # The status line keeps the windows current, so the panel is right and nothing is dimmed —
        # but Fable and the credits came from a poll that is now well past the active cadence, and
        # saying so is the only way to tell those two rows apart from the fresh ones.
        polled_at = _at("2026-07-30T10:00:00+00:00")
        activity = usage.parse_activity(
            {"five_hour": {"used_percentage": 19.0}}, observed_at=NOW
        )
        view = usage.compose(
            usage.parse_snapshot(FULL_PAYLOAD, now=polled_at), activity, now=NOW
        )

        rows = usage.menu_rows(
            view, stale=False, now=NOW, reason="endpoint returned 429"
        )

        self.assertEqual(_text(rows[-1]), "Endpoint 1h05m ago — endpoint returned 429")

    def test_says_nothing_extra_when_both_feeds_are_current(self):
        view = _view(FULL_PAYLOAD)

        rows = usage.menu_rows(view, stale=False, now=NOW)

        self.assertNotIn("Endpoint", _text(rows[-1]))
        self.assertIn("Credits", _text(rows[-1]))

    def test_no_endpoint_row_when_the_account_has_nothing_only_the_endpoint_knows(self):
        # With no scoped window and no credits, a poll adds nothing the status line has not already
        # supplied, so its age is not worth a row.
        payload = dict(FULL_PAYLOAD, limits=[], extra_usage={"is_enabled": False})
        activity = usage.parse_activity(
            {"five_hour": {"used_percentage": 19.0}}, observed_at=NOW
        )
        view = usage.compose(
            usage.parse_snapshot(payload, now=_at("2026-07-30T08:00:00+00:00")),
            activity,
            now=NOW,
        )

        rows = usage.menu_rows(view, stale=False, now=NOW)

        self.assertFalse([row for row in rows if "Endpoint" in row])

    def test_says_it_is_loading_before_the_first_poll(self):
        self.assertEqual(
            [_text(r) for r in usage.menu_rows(_view(), stale=False, now=NOW)],
            ["Loading"],
        )


class SignedOut(unittest.TestCase):
    def test_the_panel_says_so_when_there_are_no_credentials_and_no_history(self):
        self.assertEqual(
            usage.panel_label(_view(), stale=False, signed_out=True),
            '\u200b<span foreground="#646464">?</span>',
        )

    def test_the_menu_says_so_when_there_are_no_credentials_and_no_history(self):
        self.assertEqual(
            [
                _text(row)
                for row in usage.menu_rows(
                    _view(), stale=False, now=NOW, signed_out=True
                )
            ],
            ["Not signed in"],
        )

    def test_previous_numbers_still_show_when_the_credentials_go_away(self):
        # Losing the token is just another failure. Stale numbers beat no numbers, so the
        # signed-out wording only applies when nothing was ever fetched.
        view = _view(FULL_PAYLOAD)

        self.assertEqual(
            usage.panel_label(view, stale=True, signed_out=True),
            '\u200b<span foreground="#646464">5h:11% 7d:24%</span>',
        )


if __name__ == "__main__":
    unittest.main()

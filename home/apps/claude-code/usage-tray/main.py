"""Wiring: merge the status line's figures with the endpoint's, and poll only when they run out."""

import sys
from datetime import datetime, timedelta, timezone

import gi

gi.require_version("Gtk", "3.0")

from gi.repository import GLib, Gtk  # noqa: E402

import client  # noqa: E402
import tray  # noqa: E402
import usage  # noqa: E402

# The shell attaches to a new tray item a moment after it registers. Measured: a change at 6s was
# painted, one at 0s was not.
SHELL_ATTACH_GRACE_SECONDS = 5

# Everything on screen is derived from the current time — how old the numbers are, how long until a
# window resets, whether any of it is stale — so it has to be rebuilt on a clock of its own. Doing it
# only when a poll landed froze the age at whatever it was when the last request failed, which read
# as "just now" for the whole half hour of a backoff. Half a minute keeps a figure quoted in whole
# minutes honest, and Tray.render drops the repaint when nothing actually changed.
RENDER_TICK_SECONDS = 30


def _now():
    return datetime.now(timezone.utc)


class Application:
    def __init__(self):
        self._credentials_path = client.default_credentials_path()
        self._state_path = client.default_state_path()
        self._activity_path = client.default_activity_path()
        self._profiles_path = client.default_profiles_path()
        self._session = client.build_session()
        self._tray = tray.Tray(on_refresh=self.refresh_now, on_quit=self.quit)

        self._profile = None
        self._snapshot = None
        self._activity = None
        self._consecutive_failures = 0
        self._signed_out = False
        self._reason = None
        self._retry_after = None
        self._timer_id = None
        self._attempted_at = None
        self._deadline = None
        self._token = None

    def start(self):
        self._monitor = client.watch_credentials(
            self._credentials_path, self._on_credentials_changed
        )
        self._activity_monitor = client.watch_activity(
            self._activity_path, self._on_activity
        )
        self._profile_monitor = client.watch_profile(
            self._profiles_path, self._on_profile_changed
        )
        self._take_profile()
        self._restore()
        self._render()
        self._poll()
        GLib.timeout_add_seconds(RENDER_TICK_SECONDS, self._on_tick)
        # Both renders above land before the shell has attached to the item, and the next one is a
        # poll away. Repaint once it has, so the panel is not blank for the first minute.
        GLib.timeout_add_seconds(
            SHELL_ATTACH_GRACE_SECONDS, self._repaint_once_attached
        )

    def _restore(self):
        """Show whatever the two feeds left on disk until a poll replaces it.

        Stale-while-revalidate: a restart while the endpoint is refusing us would otherwise sit on
        the loading ellipsis indefinitely, even though perfectly good numbers are on disk. The status
        line's file is read here too, so a restart mid-session has the windows at once rather than
        waiting for the next render of a session that may be sitting idle.
        """
        self._take_activity()

        payload, fetched_at = client.read_state(self._state_path)
        if payload is None or not usage.is_worth_restoring(fetched_at, now=_now()):
            return
        try:
            self._snapshot = usage.parse_snapshot(payload, now=fetched_at)
        except (AttributeError, TypeError, ValueError):
            return
        self._reason = "restored from cache"

    def _repaint_once_attached(self):
        self._render()
        self._tray.repaint()
        return False

    def quit(self):
        Gtk.main_quit()

    def refresh_now(self):
        """The Refresh menu item, under the same request floor as every other trigger."""
        self._pull_in(0)

    def _on_tick(self):
        self._render()
        return True

    def _on_credentials_changed(self):
        """A different token is the one event that makes an immediate retry worth attempting.

        Compared against the token last used rather than trusting the rewrite. Claude Code rewrites
        this file for reasons that leave the token alone, and treating every rewrite as a refresh
        cleared the backoff and fired a request each time.
        """
        token = client.read_token(self._credentials_path)
        if token is None or token == self._token:
            return
        self._consecutive_failures = 0
        self._retry_after = None
        self._pull_in(0)

    def _take_profile(self):
        payload, name = client.read_profile(self._profiles_path)
        self._profile = usage.parse_profile(payload, name)

    def _on_profile_changed(self):
        self._take_profile()
        self._render()

    def _on_activity(self):
        """Claude Code published new figures: take them, and re-time the poll rather than make one.

        The windows are what the panel shows and they have just arrived for free, so all the endpoint
        still owes us is the scoped window and the credit balance, on whatever cadence is in force.
        Because this only ever pulls a poll forward, a session pinging every minute can no longer
        push the next attempt out of reach the way it used to.
        """
        if not self._take_activity():
            return
        self._render()
        self._pull_in(
            usage.poll_delay(
                self._consecutive_failures,
                self._retry_after,
                base=self._base_cadence(),
            )
        )

    def _take_activity(self):
        """Adopt the status line's latest figures, reporting whether there were any.

        A reading is only replaced by one that parsed. Anything else leaves the last good figures
        alone rather than clearing them, which matters whenever a session is still running an older
        status line than the one on disk: its file holds a bare percentage, that is legal JSON, and
        treating it as an empty reading would let one stale session wipe a current session's numbers
        on every render.
        """
        payload, observed_at = client.read_activity(self._activity_path)
        if payload is None:
            return False
        activity = usage.parse_activity(payload, observed_at=observed_at)
        if activity is None:
            return False
        self._activity = activity
        return True

    def _base_cadence(self):
        return usage.base_cadence(
            self._activity.observed_at if self._activity else None, now=_now()
        )

    def _seconds_since_attempt(self):
        if self._attempted_at is None:
            return None
        return (_now() - self._attempted_at).total_seconds()

    def _seconds_until_deadline(self):
        if self._deadline is None:
            return None
        return (self._deadline - _now()).total_seconds()

    def _arm(self, delay):
        """Schedule the poll after one completed — the only caller allowed to postpone."""
        self._set_timer(delay, may_postpone=True)

    def _pull_in(self, delay):
        """Re-time a pending poll: earlier if `delay` is sooner, never later."""
        self._set_timer(delay, may_postpone=False)

    def _set_timer(self, delay, may_postpone):
        """The one place a poll is scheduled, so no trigger can get around the floor."""
        delay = usage.schedule_delay(
            delay,
            seconds_until_pending=self._seconds_until_deadline(),
            seconds_since_attempt=self._seconds_since_attempt(),
            may_postpone=may_postpone,
        )
        self._cancel_timer()
        self._deadline = _now() + timedelta(seconds=delay)
        self._timer_id = GLib.timeout_add_seconds(max(1, int(delay)), self._on_timer)

    def _poll(self):
        self._attempted_at = _now()
        self._deadline = None
        token = client.read_token(self._credentials_path)
        if token is None:
            self._on_failure(client.Unavailable("not signed in"), signed_out=True)
            return
        self._token = token
        client.fetch_usage(self._session, token, self._on_response)

    def _on_response(self, payload, error):
        if error is not None:
            self._on_failure(error)
            return
        try:
            self._snapshot = usage.parse_snapshot(payload, now=_now())
        except (AttributeError, TypeError, ValueError) as parse_error:
            self._on_failure(client.Unavailable(f"unexpected payload ({parse_error})"))
            return
        self._consecutive_failures = 0
        self._signed_out = False
        self._reason = None
        self._retry_after = None
        client.write_state(self._state_path, payload)
        self._render()
        self._arm(usage.poll_delay(0, base=self._base_cadence()))

    def _on_failure(self, error, signed_out=False):
        self._consecutive_failures += 1
        self._retry_after = getattr(error, "retry_after", None)
        self._signed_out = signed_out
        self._reason = str(error)
        print(f"claude-usage-tray: {error}", file=sys.stderr, flush=True)
        self._render()
        self._arm(
            usage.poll_delay(
                self._consecutive_failures,
                self._retry_after,
                base=self._base_cadence(),
            )
        )

    def _render(self):
        now = _now()
        view = usage.compose(self._snapshot, self._activity, now=now)
        stale = usage.is_stale(view, self._consecutive_failures, now=now)
        header = usage.profile_row(self._profile)
        data_rows = usage.menu_rows(
            view,
            stale=stale,
            now=now,
            signed_out=self._signed_out,
            reason=self._reason,
        )
        rows = ([header, None] if header is not None else []) + data_rows
        self._tray.render(
            label=usage.panel_label(view, stale=stale, signed_out=self._signed_out),
            rows=rows,
            stale=stale,
        )

    def _cancel_timer(self):
        if self._timer_id is not None:
            GLib.source_remove(self._timer_id)
            self._timer_id = None

    def _on_timer(self):
        self._timer_id = None
        self._poll()
        return False


def main():
    application = Application()
    application.start()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())

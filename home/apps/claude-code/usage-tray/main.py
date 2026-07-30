"""Wiring: poll on a timer, back off on failure, retry at once when the token is refreshed."""

import sys
from datetime import datetime, timezone

import gi

gi.require_version("Gtk", "3.0")

from gi.repository import GLib, Gtk  # noqa: E402

import client  # noqa: E402
import tray  # noqa: E402
import usage  # noqa: E402

# The shell attaches to a new tray item a moment after it registers. Measured: a change at 6s was
# painted, one at 0s was not.
SHELL_ATTACH_GRACE_SECONDS = 5


def _now():
    return datetime.now(timezone.utc)


class Application:
    def __init__(self):
        self._credentials_path = client.default_credentials_path()
        self._state_path = client.default_state_path()
        self._activity_path = client.default_activity_path()
        self._session = client.build_session()
        self._tray = tray.Tray(on_refresh=self.refresh_now, on_quit=self.quit)

        self._snapshot = None
        self._consecutive_failures = 0
        self._signed_out = False
        self._reason = None
        self._retry_after = None
        self._timer_id = None
        self._attempted_at = None

    def start(self):
        self._monitor = client.watch_credentials(
            self._credentials_path, self._on_credentials_changed
        )
        self._activity_monitor = client.watch_activity(
            self._activity_path, self._on_activity
        )
        self._restore()
        self._render()
        self._poll()
        # Both renders above land before the shell has attached to the item, and the next one is a
        # poll away. Repaint once it has, so the panel is not blank for the first minute.
        GLib.timeout_add_seconds(
            SHELL_ATTACH_GRACE_SECONDS, self._repaint_once_attached
        )

    def _restore(self):
        """Show the last good payload from disk until a poll replaces it.

        Stale-while-revalidate: a restart while the endpoint is refusing us would otherwise sit on
        the loading ellipsis indefinitely, even though perfectly good numbers are on disk. Dated by
        the file's modification time rather than now, so the age the dropdown reports is the real
        one and the staleness rules apply to it unchanged.
        """
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
        self._cancel_timer()
        self._poll()

    def _on_credentials_changed(self):
        """A token refresh is the one event that makes an immediate retry worth attempting."""
        self._consecutive_failures = 0
        self.refresh_now()

    def _on_activity(self):
        """Claude Code's limits moved, so re-time the poll to land just after them.

        Deliberately not a backoff reset: the status line's figures come from the inference API's
        rate-limit headers, which say nothing about whether the usage endpoint has stopped refusing
        us. delay_after_activity holds both the cadence and the ladder as floors.
        """
        elapsed = (
            (_now() - self._attempted_at).total_seconds()
            if self._attempted_at is not None
            else None
        )
        delay = usage.delay_after_activity(
            seconds_since_attempt=elapsed if elapsed is not None else 0,
            consecutive_failures=self._consecutive_failures,
        )
        self._cancel_timer()
        if delay <= 0:
            self._poll()
        else:
            self._timer_id = GLib.timeout_add_seconds(int(delay), self._on_timer)

    def _poll(self):
        self._attempted_at = _now()
        token = client.read_token(self._credentials_path)
        if token is None:
            self._on_failure(client.Unavailable("not signed in"), signed_out=True)
            return
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
        self._schedule()

    def _on_failure(self, error, signed_out=False):
        self._consecutive_failures += 1
        self._retry_after = getattr(error, "retry_after", None)
        self._signed_out = signed_out
        self._reason = str(error)
        print(f"claude-usage-tray: {error}", file=sys.stderr, flush=True)
        self._render()
        self._schedule()

    def _render(self):
        stale = usage.is_stale(
            consecutive_failures=self._consecutive_failures,
            fetched_at=self._snapshot.fetched_at if self._snapshot else None,
            now=_now(),
        )
        self._tray.render(
            label=usage.panel_label(
                self._snapshot, stale=stale, signed_out=self._signed_out
            ),
            rows=usage.menu_rows(
                self._snapshot,
                stale=stale,
                now=_now(),
                signed_out=self._signed_out,
                reason=self._reason,
            ),
            stale=stale,
        )

    def _cancel_timer(self):
        if self._timer_id is not None:
            GLib.source_remove(self._timer_id)
            self._timer_id = None

    def _schedule(self):
        self._cancel_timer()
        delay = usage.poll_delay(self._consecutive_failures, self._retry_after)
        self._timer_id = GLib.timeout_add_seconds(delay, self._on_timer)

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

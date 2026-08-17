"""Everything that touches the outside world: the credentials file, the endpoint, the state file.

Kept apart from usage.py so that the decisions stay testable without a network or a session bus.
"""

import json
import os
from datetime import datetime, timezone

import gi

gi.require_version("Soup", "3.0")

from gi.repository import Gio, GLib, Soup  # noqa: E402

import usage  # noqa: E402

PROFILES_ACTIVE_LINK = "active"

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
OAUTH_BETA_HEADER = "oauth-2025-04-20"
REQUEST_TIMEOUT_SECONDS = 5

# How long to let a file settle before reporting it changed. One rewrite emits three events —
# `deleted`, `created`, `changes-done-hint` for a rename into place, or two `changed` and a hint for
# an in-place write — and answering each separately turned one token refresh into three simultaneous
# requests, which is what drew the 429s. Measured with a Gio monitor against both write styles.
MONITOR_SETTLE_MILLISECONDS = 250


class Unavailable(Exception):
    """The usage numbers could not be refreshed.

    Carries wording fit for the dropdown, and the server's Retry-After when it sent one, so the
    scheduler can wait as long as it was asked to instead of only its own backoff.
    """

    def __init__(self, message, retry_after=None):
        super().__init__(message)
        self.retry_after = retry_after


def _config_directory():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")


def default_credentials_path():
    return os.path.join(_config_directory(), ".credentials.json")


def default_profiles_path():
    return os.path.join(_config_directory(), "profiles")


def default_state_path():
    runtime_directory = GLib.get_user_runtime_dir()
    return os.path.join(runtime_directory, "claude-usage.json")


def default_activity_path():
    """Where the status line hook publishes Claude Code's own rate-limit figures.

    Written by home/apps/claude-code/statusline/statusline.sh, which puts the `rate_limits` object
    from its input in here verbatim. Claude Code recomputes those numbers from the inference API's
    rate-limit headers on every render, so while a session is working this is both fresher than a
    poll and free.

    Alongside the credentials rather than in XDG_RUNTIME_DIR, because the bubble lays a masked
    tmpfs over the runtime directory: a ping written there by a bubbled session would land in the
    bubble's private copy and never reach this process. The config directory is bound through.
    """
    return os.path.join(os.path.dirname(default_credentials_path()), "usage-activity")


def _watch(path, on_change):
    """Fire on_change once per rewrite of path, however many events the rewrite emits.

    The burst is coalesced by restarting a short timer on every event and only reporting once it
    elapses. Without that, each caller has to defend itself against being invoked three times in the
    same instant, and the one that did not is what put bursts of requests on the endpoint.

    The file need not exist yet — no session may have rendered since boot — because Gio watches the
    path rather than the inode and still fires once it appears.
    """
    pending = None

    def _settled():
        nonlocal pending
        pending = None
        on_change()
        return False

    def _changed(*_):
        nonlocal pending
        if pending is not None:
            GLib.source_remove(pending)
        pending = GLib.timeout_add(MONITOR_SETTLE_MILLISECONDS, _settled)

    monitor = Gio.File.new_for_path(path).monitor_file(Gio.FileMonitorFlags.NONE, None)
    monitor.connect("changed", _changed)
    return monitor


def watch_activity(activity_path, on_activity):
    """Fire on_activity when the status line has published new figures."""
    return _watch(activity_path, on_activity)


def read_activity(activity_path):
    """Return the status line's `rate_limits` object and when it was written, or (None, None).

    Dated by modification time, which is when Claude Code rendered the line and therefore when the
    figures were true.
    """
    try:
        observed_at = datetime.fromtimestamp(
            os.path.getmtime(activity_path), timezone.utc
        )
        with open(activity_path, "r", encoding="utf-8") as activity_file:
            return json.load(activity_file), observed_at
    except (OSError, ValueError):
        return None, None


def read_profile(profiles_path):
    """Read the active profile's JSON payload and its name, or (None, None).

    The active profile is a symlink at profiles_path/active pointing to a profile JSON file. The
    profile name is the symlink target without the .json extension.
    """
    active_link = os.path.join(profiles_path, PROFILES_ACTIVE_LINK)
    try:
        target = os.readlink(active_link)
    except OSError:
        return None, None
    name = os.path.splitext(target)[0]
    if not name:
        return None, None
    profile_file = os.path.join(profiles_path, target)
    try:
        with open(profile_file, "r", encoding="utf-8") as handle:
            return json.load(handle), name
    except (OSError, ValueError):
        return None, None


def watch_profile(profiles_path, on_change):
    """Fire on_change when the active profile symlink is replaced."""
    return _watch(os.path.join(profiles_path, PROFILES_ACTIVE_LINK), on_change)


def read_token(credentials_path):
    """Read the current OAuth access token, or None when there is not one.

    Read-only, every poll, with no caching. Claude Code owns this file and rewrites it on refresh,
    and whichever account the user's alias has swapped in is simply whatever is found here. Writing
    to it — or refreshing the token ourselves, which would rotate the refresh token out from under
    Claude Code — would race the process that owns it.
    """
    try:
        with open(credentials_path, "r", encoding="utf-8") as credentials_file:
            payload = json.load(credentials_file)
    except (OSError, ValueError):
        return None
    token = (payload.get("claudeAiOauth") or {}).get("accessToken")
    return token or None


def build_session():
    session = Soup.Session()
    session.set_timeout(REQUEST_TIMEOUT_SECONDS)
    return session


def fetch_usage(session, token, on_done):
    """GET the usage endpoint, calling on_done(payload, error) on the main loop.

    Asynchronous through libsoup rather than a blocking client in a thread: the request already has
    to live on the GLib main loop, and a five-second timeout would otherwise freeze the panel.
    """
    message = Soup.Message.new("GET", USAGE_URL)
    headers = message.get_request_headers()
    headers.append("Authorization", f"Bearer {token}")
    headers.append("anthropic-beta", OAUTH_BETA_HEADER)
    headers.append("Content-Type", "application/json")

    def _finished(source, result, _user_data=None):
        try:
            body = source.send_and_read_finish(result)
        except GLib.Error as error:
            on_done(None, Unavailable(f"network unreachable ({error.message})"))
            return

        status = message.get_status()
        if status == Soup.Status.UNAUTHORIZED:
            on_done(None, Unavailable("token expired"))
            return
        if status != Soup.Status.OK:
            retry_after = usage.parse_retry_after(
                message.get_response_headers().get_one("Retry-After")
            )
            suffix = f", retry in {retry_after}s" if retry_after else ""
            on_done(
                None,
                Unavailable(f"endpoint returned {int(status)}{suffix}", retry_after),
            )
            return

        try:
            payload = json.loads(body.get_data().decode("utf-8"))
        except (ValueError, UnicodeDecodeError) as error:
            on_done(None, Unavailable(f"unreadable response ({error})"))
            return
        on_done(payload, None)

    session.send_and_read_async(message, GLib.PRIORITY_DEFAULT, None, _finished, None)


def watch_credentials(credentials_path, on_change):
    """Fire on_change whenever the credentials file is rewritten.

    This is what lets backoff be interrupted: a rewrite may mean Claude Code has just refreshed the
    token, which is the one event that makes an immediate retry worth attempting rather than waiting
    out the cap. Whether the token actually changed is the caller's business — a rewrite alone is not
    proof of one.
    """
    return _watch(credentials_path, on_change)


def write_state(state_path, payload):
    """Publish the last good payload for any other consumer that wants it.

    Nothing here reads it back. It exists so the tmux status line can show the Fable number, which
    the Claude Code status line hook cannot provide. Written through a temporary file and renamed
    so a reader never sees a half-written document.
    """
    temporary_path = f"{state_path}.tmp"
    try:
        with open(temporary_path, "w", encoding="utf-8") as state_file:
            json.dump(payload, state_file)
        # The runtime directory is already private to the user; this keeps the account's spend
        # limits owner-only regardless of where the path ends up.
        os.chmod(temporary_path, 0o600)
        os.replace(temporary_path, state_path)
    except OSError:
        try:
            os.unlink(temporary_path)
        except OSError:
            pass


def read_state(state_path):
    """Return the cached payload and the moment it was written, or (None, None).

    The modification time is the payload's real age, so the dropdown can say how stale it is rather
    than passing week-old numbers off as fresh.
    """
    try:
        fetched_at = datetime.fromtimestamp(os.path.getmtime(state_path), timezone.utc)
        with open(state_path, "r", encoding="utf-8") as state_file:
            return json.load(state_file), fetched_at
    except (OSError, ValueError):
        return None, None

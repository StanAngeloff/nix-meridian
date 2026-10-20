"""Everything that touches the outside world: the credentials file, the endpoint, the state file.

Kept apart from usage.py so that the decisions stay testable without a network or a session bus.
"""

import json
import os
import sys
from dataclasses import dataclass
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


# The systemd user manager, which runs every bubbled session in its own scope; see SessionWatch.
SYSTEMD_BUS_NAME = "org.freedesktop.systemd1"
SYSTEMD_OBJECT_PATH = "/org/freedesktop/systemd1"
SYSTEMD_MANAGER_INTERFACE = "org.freedesktop.systemd1.Manager"
SYSTEMD_SCOPE_INTERFACE = "org.freedesktop.systemd1.Scope"
# bubble/modules/lifetime names each session's scope claude-bubble-<suffix>.scope.
SESSION_SCOPE_PREFIX = "claude-bubble-"
SESSION_SCOPE_SUFFIX = ".scope"


@dataclass(frozen=True)
class FeedPaths:
    """Where one shown profile's figures come from and go to.

    key tells two feeds apart across a change of layout or default: a feed whose key is still wanted
    keeps its figures and its schedule. name is None in the older layouts when no profile is named.
    """

    key: tuple
    name: str | None
    credentials_path: str
    activity_path: str
    state_path: str


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


def default_profiles_path():
    return os.path.join(_config_directory(), "profiles")


def is_profile_layout():
    """Whether each profile has its own directory, which is what lets several be shown at once.

    Before the migration profiles/active linked a token file, or there were no profiles, and one
    account at a time lived in the shared files.
    """
    return os.path.isdir(
        os.path.join(default_profiles_path(), PROFILES_ACTIVE_LINK, "credentials")
    )


def default_profile_name():
    """The default profile's name, which profiles/active links, or None."""
    try:
        target = os.readlink(
            os.path.join(default_profiles_path(), PROFILES_ACTIVE_LINK)
        )
    except OSError:
        return None
    return os.path.splitext(target)[0] if target.endswith(".json") else target or None


def profile_feed_paths(name):
    """One profile's own files, by name rather than through profiles/active.

    Every bubbled session writes its status line figures into its own profile's directory: inside the
    bubble profiles/active is bound to that directory (bubble/modules/profiles/hooks.sh), so the host
    sees them at profiles/<name>/usage-activity. That file is under the config directory, not the runtime
    directory, because the bubble masks the runtime directory; see publish_rate_limits in statusline/main.py.
    The cache is the profile's own too, so a restart shows each account's last figures under its own name.
    """
    profile_path = os.path.join(default_profiles_path(), name)
    return FeedPaths(
        key=("profile", name),
        name=name,
        credentials_path=os.path.join(profile_path, "credentials", ".credentials.json"),
        activity_path=os.path.join(profile_path, "usage-activity"),
        state_path=os.path.join(
            GLib.get_user_runtime_dir(), f"claude-usage-{name}.json"
        ),
    )


def shared_feed_paths():
    """The one feed of the older layouts, which kept the live account in the shared files.

    Keyed by the profile profiles/active names, so a switch of account drops the previous one's figures
    rather than showing them under the new name.
    """
    name = default_profile_name()
    return FeedPaths(
        key=("shared", name),
        name=name,
        credentials_path=os.path.join(_config_directory(), ".credentials.json"),
        activity_path=os.path.join(_config_directory(), "usage-activity"),
        state_path=os.path.join(GLib.get_user_runtime_dir(), "claude-usage.json"),
    )


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


def _read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def read_profile(profiles_path):
    """Read the default profile's identity payload and its name, or (None, None).

    profiles_path/active links either a profile directory, with its own .claude.json and
    credentials/, or in the older layout a <name>.json token file. The payload has the shape
    usage.parse_profile reads either way.
    """
    active_link = os.path.join(profiles_path, PROFILES_ACTIVE_LINK)
    try:
        target = os.readlink(active_link)
    except OSError:
        return None, None
    if target.endswith(".json"):
        name = os.path.splitext(target)[0]
        payload = _read_json(os.path.join(profiles_path, target))
        if not name or payload is None:
            return None, None
        return payload, name
    if not target:
        return None, None
    payload = read_named_profile(profiles_path, target)
    if payload is None:
        return None, None
    return payload, target


def read_named_profile(profiles_path, name):
    """Read one profile directory's identity payload, in the shape usage.parse_profile reads, or None."""
    profile_path = os.path.join(profiles_path, name)
    config = _read_json(os.path.join(profile_path, ".claude.json"))
    if config is None:
        return None
    credentials = _read_json(
        os.path.join(profile_path, "credentials", ".credentials.json")
    )
    return usage.slot_profile_payload(config, credentials)


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


class SessionWatch:
    """Follows which profiles have a running session, from the systemd user manager on the session bus.

    Each bubbled session runs in its own claude-bubble-<suffix>.scope, filed under its profile's slice
    (bubble/modules/lifetime and bubble/modules/profiles). A scope appearing, finishing a job or being
    collected starts a fresh listing of the active session scopes and their slices, which is the same
    question `cc profiles list` asks. Listings are asynchronous, so a slow manager never stalls the panel,
    and the answer to a listing that a newer one has overtaken is dropped.

    on_change(names) receives the set of profile names whenever it changes. Without a session bus or a
    manager there are no live profiles to report, and the tray shows the default profile alone.
    """

    def __init__(self, on_change):
        self._on_change = on_change
        self._connection = None
        self._generation = 0
        self._listing_pending = None
        self._names = frozenset()

    def start(self):
        try:
            self._connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        except GLib.Error as error:
            print(
                f"claude-usage-tray: no session bus, so other profiles' sessions stay hidden ({error.message})",
                file=sys.stderr,
                flush=True,
            )
            return
        self._connection.signal_subscribe(
            SYSTEMD_BUS_NAME,
            SYSTEMD_MANAGER_INTERFACE,
            None,
            SYSTEMD_OBJECT_PATH,
            None,
            Gio.DBusSignalFlags.NONE,
            self._on_signal,
        )
        # The manager sends its unit and job signals only to clients that asked for them.
        self._connection.call(
            SYSTEMD_BUS_NAME,
            SYSTEMD_OBJECT_PATH,
            SYSTEMD_MANAGER_INTERFACE,
            "Subscribe",
            None,
            None,
            Gio.DBusCallFlags.NONE,
            -1,
            None,
            self._on_subscribed,
        )
        self._list()

    def _on_subscribed(self, connection, result):
        try:
            connection.call_finish(result)
        except GLib.Error as error:
            print(
                f"claude-usage-tray: systemd refused the subscription, so sessions are listed once only ({error.message})",
                file=sys.stderr,
                flush=True,
            )

    def _on_signal(self, _connection, _sender, _path, _interface, signal, parameters):
        arguments = parameters.unpack()
        if signal in ("UnitNew", "UnitRemoved"):
            unit_name = arguments[0]
        elif signal == "JobRemoved":
            unit_name = arguments[2]
        else:
            return
        if not (
            unit_name.startswith(SESSION_SCOPE_PREFIX)
            and unit_name.endswith(SESSION_SCOPE_SUFFIX)
        ):
            return
        # A session's start or stop arrives as several signals in one burst; one listing answers them all.
        if self._listing_pending is None:
            self._listing_pending = GLib.idle_add(self._on_idle)

    def _on_idle(self):
        self._listing_pending = None
        self._list()
        return False

    def _list(self):
        self._generation += 1
        self._connection.call(
            SYSTEMD_BUS_NAME,
            SYSTEMD_OBJECT_PATH,
            SYSTEMD_MANAGER_INTERFACE,
            "ListUnitsByPatterns",
            GLib.Variant(
                "(asas)",
                (["active"], [f"{SESSION_SCOPE_PREFIX}*{SESSION_SCOPE_SUFFIX}"]),
            ),
            GLib.VariantType.new("(a(ssssssouso))"),
            Gio.DBusCallFlags.NONE,
            -1,
            None,
            self._on_listed,
            self._generation,
        )

    def _on_listed(self, connection, result, generation):
        try:
            units = connection.call_finish(result).unpack()[0]
        except GLib.Error as error:
            print(
                f"claude-usage-tray: could not list the sessions ({error.message})",
                file=sys.stderr,
                flush=True,
            )
            return
        if generation != self._generation:
            return
        unit_paths = [unit[6] for unit in units]
        slices = {}
        if not unit_paths:
            self._publish(generation, slices)
            return
        for unit_path in unit_paths:
            connection.call(
                SYSTEMD_BUS_NAME,
                unit_path,
                "org.freedesktop.DBus.Properties",
                "Get",
                GLib.Variant("(ss)", (SYSTEMD_SCOPE_INTERFACE, "Slice")),
                GLib.VariantType.new("(v)"),
                Gio.DBusCallFlags.NONE,
                -1,
                None,
                self._on_slice,
                (generation, unit_path, len(unit_paths), slices),
            )

    def _on_slice(self, connection, result, context):
        generation, unit_path, expected_count, slices = context
        try:
            slices[unit_path] = connection.call_finish(result).unpack()[0]
        except GLib.Error:
            # The scope ended between the listing and this question: it has no session to report.
            slices[unit_path] = ""
        if len(slices) == expected_count:
            self._publish(generation, slices)

    def _publish(self, generation, slices):
        if generation != self._generation:
            return
        names = frozenset(
            name
            for name in map(usage.profile_from_slice, slices.values())
            if name is not None
        )
        if names != self._names:
            self._names = names
            self._on_change(names)


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

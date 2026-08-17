"""Pure logic for the Claude usage tray.

Everything the program decides lives here: how the endpoint's payload becomes a snapshot, how long
to wait after a failure, when data counts as stale, and how any of it is worded. Nothing in this
module opens a socket, touches the clock or imports gi, so all of it is reachable from tests with
no display and no session bus.
"""

import html
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

# Five minutes, not one. The endpoint answered 429 at a one-minute cadence on 2026-07-30, and it is
# a metadata endpoint on a far tighter budget than the inference API — it also shares the token with
# Claude Code, which calls it for its own /usage command, so the two contend. Nothing is lost: even
# a session window running flat out moves about a third of a percent per minute.
HEALTHY_CADENCE_SECONDS = 300

# What the cadence becomes while Claude Code is reporting the windows itself. The only thing a
# request still adds then is the scoped window and the credit balance, and neither moves fast enough
# to be worth asking every five minutes.
ACTIVE_CADENCE_SECONDS = 1800

# How long a status line reading counts as current. Claude Code renders its line on every turn, so
# anything within a few minutes means a session is working; past that the feed has gone quiet and
# the endpoint is all that is left.
ACTIVITY_FRESH_FOR = timedelta(minutes=3)

# A floor under every request, whatever asked for it. One rewrite of the credentials file emits three
# file-monitor events, and answering each of them immediately put three simultaneous requests on a
# metadata endpoint — which is what drew the 429s of 2026-08-04, even though the whole day's traffic
# was 15 requests. The ladder alone could not prevent it: it only spaces polls the timer schedules.
MINIMUM_REQUEST_SPACING_SECONDS = 30

MAXIMUM_BACKOFF_SECONDS = 1800
# The longest a Retry-After will be honoured. Past this the endpoint is telling us to go away for
# longer than a panel indicator can usefully stay blank, so it retries and shows stale meanwhile.
MAXIMUM_RETRY_AFTER_SECONDS = 3600
STALE_AFTER = timedelta(minutes=10)
STALE_AFTER_FAILURES = 2

# Longer than the active cadence on purpose. Polling rarely while the status line feeds the windows
# is the design, not a fault, so the endpoint's own age only becomes worth reporting once it exceeds
# what that design would produce.
DETAILS_STALE_AFTER = timedelta(minutes=45)

# Past the longest window every limit has reset, so a cache older than this describes nothing and
# the loading state is more honest than confident nonsense.
RESTORE_WITHIN = timedelta(days=7)

# Long enough to cover the whole session window, short enough that a weekly reset — which is
# usually less than a day out — still reads as a weekday and a time rather than a countdown.
RELATIVE_RESET_WITHIN = timedelta(hours=6)

BAR_CELLS = 10
FILLED_CELL = "▓"
EMPTY_CELL = "░"
ZERO_WIDTH_SPACE = "\u200b"
LOADING_LABEL = "…"
LOADING_LABEL_ROW = "Loading"
SIGNED_OUT_LABEL = "?"
SIGNED_OUT_LABEL_ROW = "Not signed in"

# The same three colours the tmux status line uses, so the panel and the terminal agree. The panel
# renders these only because the appindicator extension is patched to send our label through
# set_markup; see home/gnome-shell/extensions/appindicator.nix.
PREFIX_COLOUR = "#377880"
VALUE_COLOUR = "#56b6c2"
STALE_COLOUR = "#646464"

# The dropdown needs its own, brighter palette. Its rows are insensitive so that hovering them does
# nothing, and the shell theme styles that as `color: st-transparentize(#ffffff, 0.6)` — alpha 0.4.
# A Pango foreground attribute sets RGB but not alpha, so the panel's colours would arrive at 40%
# opacity and read as mud. These are the panel colours solved back through
# `apparent = 0.4 * source + 0.6 * background`, with the dark popover background of
# `st-lighten(#2e2e33, 8%)`, roughly #3f3f46. The bright value clips: 40% opacity cannot reach
# #56b6c2 no matter the source, so it lands a little muted, which is the price of not being hoverable.
MENU_VALUE_COLOUR = "#79ffff"
MENU_MUTED_COLOUR = "#3fd3d7"
MENU_STALE_COLOUR = "#9c9c9c"


@dataclass(frozen=True)
class Profile:
    name: str
    email: str | None
    subscription: str | None
    organization: str | None


@dataclass(frozen=True)
class Limit:
    title: str
    percent: int
    resets_at: datetime | None


@dataclass(frozen=True)
class Credits:
    used: float | None
    limit: float
    currency: str


@dataclass(frozen=True)
class Snapshot:
    """What the usage endpoint returned. The only source for the scoped window and the credits."""

    five_hour: Limit | None
    seven_day: Limit | None
    scoped: tuple[Limit, ...]
    credits: Credits | None
    fetched_at: datetime


@dataclass(frozen=True)
class Activity:
    """What Claude Code's status line reported. Only the two account-wide windows, but free and
    current: it recomputes them from the inference API's rate-limit headers on every render.
    """

    five_hour: Limit | None
    seven_day: Limit | None
    observed_at: datetime


@dataclass(frozen=True)
class View:
    """The two sources merged into what is actually on screen.

    Provenance is kept because it decides whether a failing endpoint should grey the panel: if the
    windows came from the status line, a 429 says nothing about whether they are right.
    """

    five_hour: Limit | None
    seven_day: Limit | None
    scoped: tuple[Limit, ...]
    credits: Credits | None
    windows_at: datetime | None
    windows_from_activity: bool
    details_at: datetime | None

    @property
    def has_data(self):
        return any(
            (self.five_hour, self.seven_day, self.scoped, self.credits is not None)
        )


def _parse_timestamp(text):
    if not text:
        return None
    return datetime.fromisoformat(text)


def _parse_epoch(value):
    """Read a reset time the status line reported, which is epoch seconds rather than ISO text."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    try:
        return datetime.fromtimestamp(value, timezone.utc)
    except (OSError, OverflowError, ValueError):
        return None


def _parse_window(payload, key, title):
    window = payload.get(key)
    if not isinstance(window, dict):
        return None
    return Limit(
        title=title,
        percent=round(window.get("utilization") or 0),
        resets_at=_parse_timestamp(window.get("resets_at")),
    )


def _parse_scoped(payload):
    """Pick the per-model weekly limits out of limits[].

    Fable arrives only here, with no top-level key of its own, and its position in the array is not
    guaranteed. Match on kind and read the name off the scope rather than indexing.
    """
    scoped = []
    for entry in payload.get("limits") or []:
        if not isinstance(entry, dict) or entry.get("kind") != "weekly_scoped":
            continue
        model = (entry.get("scope") or {}).get("model") or {}
        display_name = model.get("display_name")
        if not display_name:
            continue
        scoped.append(
            Limit(
                title=display_name,
                percent=round(entry.get("percent") or 0),
                resets_at=_parse_timestamp(entry.get("resets_at")),
            )
        )
    return tuple(scoped)


def _parse_credits(payload):
    """Read the usage-credit allowance, converting from minor units.

    monthly_limit is in minor units scaled by decimal_places, so 20000 at 2 places is 200.00 rather
    than 20000. The used amount comes from spend.used.amount_minor, which says so in its name;
    extra_usage.used_credits is deliberately ignored because its units could not be established
    (the only observed value was zero, which reads the same either way).
    """
    extra_usage = payload.get("extra_usage")
    if not isinstance(extra_usage, dict) or not extra_usage.get("is_enabled"):
        return None

    monthly_limit = extra_usage.get("monthly_limit")
    if monthly_limit is None:
        return None
    limit_scale = 10 ** (extra_usage.get("decimal_places") or 0)

    used = None
    spend_used = (payload.get("spend") or {}).get("used")
    if isinstance(spend_used, dict) and spend_used.get("amount_minor") is not None:
        used = spend_used["amount_minor"] / 10 ** (spend_used.get("exponent") or 0)

    return Credits(
        used=used,
        limit=monthly_limit / limit_scale,
        currency=extra_usage.get("currency") or "",
    )


def _parse_activity_window(payload, key, title):
    window = payload.get(key)
    if not isinstance(window, dict):
        return None
    percent = window.get("used_percentage")
    if percent is None:
        return None
    return Limit(
        title=title,
        percent=round(percent),
        resets_at=_parse_epoch(window.get("resets_at")),
    )


def parse_activity(payload, observed_at):
    """Read the `rate_limits` object the status line hands over, or None if it has no windows.

    The hook writes that object through untouched rather than picking fields out of it in shell, so
    field names are named in one place — here — and a window Claude Code adds later needs no change
    on the writing side.
    """
    if not isinstance(payload, dict):
        return None
    five_hour = _parse_activity_window(payload, "five_hour", "5-hour")
    seven_day = _parse_activity_window(payload, "seven_day", "7-day")
    if five_hour is None and seven_day is None:
        return None
    return Activity(five_hour=five_hour, seven_day=seven_day, observed_at=observed_at)


def parse_profile(payload, name):
    """Build a Profile from the active profile's JSON and its name, or None."""
    if not isinstance(payload, dict) or not name:
        return None
    oauth = payload.get("oauthAccount") or {}
    claude = payload.get("claudeAiOauth") or {}
    return Profile(
        name=name,
        email=oauth.get("emailAddress") or None,
        subscription=claude.get("subscriptionType") or None,
        organization=oauth.get("organizationName") or None,
    )


def compose(snapshot, activity, now):
    """Merge the two feeds into one view, newest reading of the windows winning.

    The scoped window and the credits only ever come from the endpoint — the status line has no
    equivalent — so a ping must never displace them, however fresh it is. `windows_at` describes the
    reading that supplied the windows, which is what the age and staleness rules then work from.
    """
    five_hour = snapshot.five_hour if snapshot else None
    seven_day = snapshot.seven_day if snapshot else None
    windows_at = snapshot.fetched_at if snapshot else None
    windows_from_activity = False

    if activity is not None and (
        windows_at is None or activity.observed_at > windows_at
    ):
        # Either window the status line omitted keeps the endpoint's figure rather than disappearing.
        five_hour = activity.five_hour or five_hour
        seven_day = activity.seven_day or seven_day
        windows_at = activity.observed_at
        windows_from_activity = True

    return View(
        five_hour=five_hour,
        seven_day=seven_day,
        scoped=snapshot.scoped if snapshot else (),
        credits=snapshot.credits if snapshot else None,
        windows_at=windows_at,
        windows_from_activity=windows_from_activity,
        details_at=snapshot.fetched_at if snapshot else None,
    )


def bar(percent):
    """A ten-cell text meter.

    Text rather than a widget because the menu travels over DBusMenu, which carries labels, icons
    and toggles but not arbitrary widgets. Any non-zero usage claims a cell so that a small number
    still reads as more than nothing.
    """
    filled = min(BAR_CELLS, int(percent * BAR_CELLS / 100))
    if percent > 0:
        filled = max(1, filled)
    return FILLED_CELL * filled + EMPTY_CELL * (BAR_CELLS - filled)


def _escape(text):
    """Make text safe to embed in markup.

    Titles come from scope.model.display_name in the payload, so they are external text. A bare
    ampersand there would make the whole row fail to parse and render as nothing.
    """
    return html.escape(str(text), quote=False)


def _span(text, colour):
    return f'<span foreground="{colour}">{text}</span>'


def _offset(markup):
    """Prefix a zero-width space, because a foreground attribute starting at byte 0 is lost.

    Measured on GNOME 50 across four markup shapes: whichever `foreground` span begins at byte
    index 0 renders in the theme's colour instead of ours, while every span starting later is
    correct. Four sibling spans lost only the first prefix; nesting the dim colour into one span
    covering everything lost both prefixes; adding a no-op attribute at index 0 as a decoy changed
    nothing, because it did not move ours off zero. The dropdown was never affected, and its rows
    happen to begin with an uncoloured title — the same rule, seen from the other side.

    A zero-width space is three UTF-8 bytes, so it pushes the first span to index 3 while adding
    nothing visible. The cause is unexplained: Clutter merges markup attributes with the ones St
    sets from CSS (`font-features "tnum"` here, over the whole range), and something in that merge
    discards a foreground at the origin. Since `<tt>` at index 0 survives, it is specific to colour.
    """
    return f"{ZERO_WIDTH_SPACE}{markup}"


def panel_label(view, stale, signed_out=False):
    """The panel text, as Pango markup.

    Everything this returns is rendered through set_markup, so it must always be well-formed
    markup. That holds trivially here because every value is a number we formatted ourselves; any
    text taken from the payload would have to be escaped first.
    """
    if not view.has_data:
        return _offset(
            _span(SIGNED_OUT_LABEL if signed_out else LOADING_LABEL, STALE_COLOUR)
        )

    windows = []
    if view.five_hour is not None:
        windows.append(("5h:", f"{view.five_hour.percent}%"))
    if view.seven_day is not None:
        windows.append(("7d:", f"{view.seven_day.percent}%"))

    if stale:
        return _offset(
            _span(" ".join(prefix + value for prefix, value in windows), STALE_COLOUR)
        )
    # One outer span sets the dim base and the values override it, rather than a run of sibling
    # spans. Fewer attributes, and the prefixes cannot end up unstyled if a leading attribute is
    # dropped — which is how the panel behaved with siblings.
    inner = " ".join(prefix + _span(value, VALUE_COLOUR) for prefix, value in windows)
    return _offset(_span(inner, PREFIX_COLOUR))


def format_reset(resets_at, now):
    """Word a reset time the way it is most useful to read.

    Relative for the session window, because what matters there is how long is left. Absolute for
    the weekly ones, because "resets in 19h55m" is harder to act on than a weekday and a time.
    """
    if resets_at is None:
        return ""
    remaining = resets_at - now
    if remaining >= RELATIVE_RESET_WITHIN:
        return f"resets {resets_at:%a %H:%M}"
    minutes = max(0, int(remaining.total_seconds() // 60))
    hours, minutes = divmod(minutes, 60)
    return f"resets in {hours}h{minutes:02d}m" if hours else f"resets in {minutes}m"


CURRENCY_SYMBOLS = {"EUR": "€", "USD": "$", "GBP": "£"}


def _format_money(amount, currency):
    symbol = CURRENCY_SYMBOLS.get(currency, f"{currency} " if currency else "")
    return f"{symbol}{amount:.2f}"


def is_worth_restoring(fetched_at, now):
    """Whether a snapshot recovered from the cache is worth showing while the first poll runs."""
    if fetched_at is None:
        return False
    return (now - fetched_at) <= RESTORE_WITHIN


def format_age(fetched_at, now):
    """How old the numbers are, in the coarsest unit that still says something.

    Days matter because restoring from the cache makes long ages ordinary, and "51h05m ago" reads
    worse than "2d ago" for a figure that is only there to say "do not trust this".
    """
    minutes = max(0, int((now - fetched_at).total_seconds() // 60))
    if minutes < 1:
        return "just now"
    hours, minutes = divmod(minutes, 60)
    days, hours = divmod(hours, 24)
    if days:
        return f"{days}d ago"
    return f"{hours}h{minutes:02d}m ago" if hours else f"{minutes}m ago"


def profile_row(profile):
    """The dropdown header identifying which account the numbers belong to.

    Same banner as the terminal launcher, adapted for the menu palette. Never dimmed by staleness:
    the profile is identity, not data, and it is either known or absent.
    """
    if profile is None:
        return None
    label = _escape(profile.name.upper())
    body = _span(f"\U0001faaa {label}", MENU_VALUE_COLOUR)
    if profile.email:
        body += _escape(f"  ·  {profile.email}")
    if profile.subscription:
        suffix = profile.subscription
        if profile.organization:
            suffix += f" ({profile.organization})"
        body += _escape(f"  ·  {suffix}")
    return _offset(f"<tt>{body}</tt>")


def _row(segments, stale):
    """Assemble one dropdown row from (text, colour) pairs, where colour None inherits the theme.

    Monospaced so the columns line up: the menu font is proportional, so space padding alone leaves
    the bars and percentages ragged.

    Only the data carries colour. The popover background is lighter than the terminal's and its font
    larger, so the dim teal that reads well in tmux is muddy here; titles and reset times are left
    to the shell's own text colour, which is already tuned for that background. Stale is the
    exception, collapsing every segment to one grey so a stale dropdown recedes as a unit.
    """
    body = ""
    for text, colour in segments:
        if not text:
            continue
        effective = MENU_STALE_COLOUR if stale else colour
        body += _span(_escape(text), effective) if effective else _escape(text)
    return _offset(f"<tt>{body}</tt>")


def menu_rows(view, stale, now, signed_out=False, reason=None):
    """The dropdown, as Pango markup.

    Strings rather than widgets because DBusMenu only carries labels, and markup only because the
    appindicator extension is patched to render our menu through set_markup; see
    home/gnome-shell/extensions/appindicator.nix. Rows whose data the account does not have are
    left out entirely: a Fable row reading 0% would claim an allowance that is not there.

    Every string here is derived from `now`, so this has to be rebuilt on a clock of its own and not
    only when a poll lands. Rebuilding it solely on poll completion froze the age at whatever it was
    when the last request failed, which read as "just now" for as long as the backoff lasted.
    """
    if not view.has_data:
        text = SIGNED_OUT_LABEL_ROW if signed_out else LOADING_LABEL_ROW
        return [_row([(text, None)], stale=True)]

    rows = []
    for limit in (view.five_hour, view.seven_day, *view.scoped):
        if limit is None:
            continue
        meter = bar(limit.percent)
        filled = meter.rstrip(EMPTY_CELL)
        rows.append(
            _row(
                [
                    (f"{limit.title:<10} ", None),
                    (filled, MENU_VALUE_COLOUR),
                    (meter[len(filled) :], MENU_MUTED_COLOUR),
                    (f" {limit.percent:>4}%", MENU_VALUE_COLOUR),
                    (f"   {format_reset(limit.resets_at, now)}".rstrip(), None),
                ],
                stale,
            )
        )

    if view.credits is not None:
        used = view.credits.used
        limit_text = _format_money(view.credits.limit, view.credits.currency)
        amount = (
            f"{limit_text} limit"
            if used is None
            else f"{_format_money(used, view.credits.currency)} / {limit_text}"
        )
        rows.append(
            _row([(f"{'Credits':<10} ", None), (amount, MENU_VALUE_COLOUR)], stale)
        )

    footer = None
    if stale:
        footer = f"Last updated {format_age(view.windows_at, now)}"
    elif details_are_stale(view, now):
        # The windows are current, so the panel is right; it is only the endpoint-only rows above
        # that are behind. Naming the endpoint rather than the fields keeps this true whether the
        # account has a scoped window, credits or both.
        footer = f"Endpoint {format_age(view.details_at, now)}"
    if footer is not None:
        rows.append(
            _row(
                [(f"{footer} — {reason}" if reason else footer, None)],
                stale=True,
            )
        )
    return rows


def parse_retry_after(text):
    """Read a Retry-After header expressed as a count of seconds, or None.

    The header may also be an HTTP date. Rather than carry a second parser, anything that is not a
    plain integer falls back to the normal backoff, which never polls faster than the healthy
    cadence anyway.
    """
    try:
        seconds = int(str(text).strip())
    except (TypeError, ValueError):
        return None
    return seconds if seconds > 0 else None


def base_cadence(activity_at, now):
    """The interval between healthy polls, which depends on whether anything else is feeding us.

    Long while the status line is live: Claude Code is already reporting the windows more often and
    more accurately than a poll could, so a request only refreshes the scoped window and the credit
    balance. Short once the feed goes quiet, because then nothing else keeps the panel current.
    """
    if activity_at is not None and (now - activity_at) <= ACTIVITY_FRESH_FOR:
        return ACTIVE_CADENCE_SECONDS
    return HEALTHY_CADENCE_SECONDS


def poll_delay(consecutive_failures, retry_after=None, base=None):
    """Seconds to wait before the next poll.

    Doubling starts from the cadence in force rather than below it, so a run of failures can only
    ever slow polling down. The caller resets the failure count on success, and also when the token
    on disk actually changes, since that means a retry has a fresh reason to succeed.

    A Retry-After from the server raises the floor but never lowers it: being asked to come back in
    five seconds must not turn a run of 429s into a tight loop against an endpoint already refusing
    us. It is capped, because an hour of silence is the most a panel indicator should honour before
    trying again regardless.
    """
    backoff = min(
        MAXIMUM_BACKOFF_SECONDS,
        (HEALTHY_CADENCE_SECONDS if base is None else base) * 2**consecutive_failures,
    )
    if retry_after is None:
        return backoff
    return min(MAXIMUM_RETRY_AFTER_SECONDS, max(backoff, retry_after))


def spacing_delay(seconds_since_attempt):
    """How long a request must wait to keep the minimum spacing, whatever asked for it.

    Applies to the timer, to a credentials change and to the Refresh menu item alike. Without it any
    trigger that fires in a burst becomes a burst of requests, which is how the file monitor's three
    events per rewrite turned into three simultaneous polls.
    """
    if seconds_since_attempt is None:
        return 0
    return max(0, MINIMUM_REQUEST_SPACING_SECONDS - seconds_since_attempt)


def retime(delay, seconds_until_pending):
    """Reconcile a newly computed delay with a poll that is already scheduled.

    Re-timing may only bring a poll forward. Re-arming at the full delay measured from now meant a
    ping every minute against a thirty-minute backoff pushed the deadline out of reach on every
    ping, so the tray stopped retrying entirely for as long as any session kept working.
    """
    if seconds_until_pending is None:
        return delay
    return max(0, min(delay, seconds_until_pending))


def schedule_delay(delay, seconds_until_pending, seconds_since_attempt, may_postpone):
    """The delay actually armed, reconciling a request with the floor and with a poll already due.

    One rule in one place, because the two failures this replaces were both about which caller was
    allowed to move a deadline. Only a completed poll may push the next one further out — that is how
    a growing backoff takes effect. Everything else (a ping, a token change, the Refresh item) may
    pull it in but never postpone it.

    The floor is applied last, so honouring it can still move a deadline out by up to the spacing
    itself. That is bounded and self-clearing: past the floor, spacing_delay is zero and nothing can
    postpone anything.
    """
    if not may_postpone:
        delay = retime(delay, seconds_until_pending)
    return max(delay, spacing_delay(seconds_since_attempt))


def is_stale(view, consecutive_failures, now):
    """Whether the numbers on screen should be marked as no longer trustworthy.

    Keyed on the age of whatever is displayed, so it covers both feeds with one rule. Failures are a
    second, faster trigger — a couple of them catch an outage before the age ceiling would — but only
    for figures the endpoint supplied. A rate-limited endpoint says nothing about windows the status
    line reported a moment ago, and grieving over them was exactly what made a working panel grey.
    """
    if view.windows_at is None:
        return False
    if (now - view.windows_at) > STALE_AFTER:
        return True
    return (
        not view.windows_from_activity and consecutive_failures >= STALE_AFTER_FAILURES
    )


def details_are_stale(view, now):
    """Whether the endpoint-only figures are old enough to say so.

    Separate from is_stale because they are allowed to lag: polling rarely while the status line
    carries the windows is the intent, so this only fires once the endpoint is further behind than
    that intent accounts for.
    """
    if view.details_at is None:
        return False
    if not view.scoped and view.credits is None:
        return False
    return (now - view.details_at) > DETAILS_STALE_AFTER


def parse_snapshot(payload, now):
    return Snapshot(
        five_hour=_parse_window(payload, "five_hour", "5-hour"),
        seven_day=_parse_window(payload, "seven_day", "7-day"),
        scoped=_parse_scoped(payload),
        credits=_parse_credits(payload),
        fetched_at=now,
    )

"""Pure logic for the Claude usage tray.

Everything the program decides lives here: how the endpoint's payload becomes a snapshot, how long
to wait after a failure, when data counts as stale, and how any of it is worded. Nothing in this
module opens a socket, touches the clock or imports gi, so all of it is reachable from tests with
no display and no session bus.
"""

import html
from dataclasses import dataclass
from datetime import datetime, timedelta

# Five minutes, not one. The endpoint answered 429 at a one-minute cadence on 2026-07-30, and it is
# a metadata endpoint on a far tighter budget than the inference API — it also shares the token with
# Claude Code, which calls it for its own /usage command, so the two contend. Nothing is lost: even
# a session window running flat out moves about a third of a percent per minute.
HEALTHY_CADENCE_SECONDS = 300
MAXIMUM_BACKOFF_SECONDS = 1800
# The longest a Retry-After will be honoured. Past this the endpoint is telling us to go away for
# longer than a panel indicator can usefully stay blank, so it retries and shows stale meanwhile.
MAXIMUM_RETRY_AFTER_SECONDS = 3600
STALE_AFTER = timedelta(minutes=10)
STALE_AFTER_FAILURES = 2

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
    five_hour: Limit | None
    seven_day: Limit | None
    scoped: tuple[Limit, ...]
    credits: Credits | None
    fetched_at: datetime


def _parse_timestamp(text):
    if not text:
        return None
    return datetime.fromisoformat(text)


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


def panel_label(snapshot, stale, signed_out=False):
    """The panel text, as Pango markup.

    Everything this returns is rendered through set_markup, so it must always be well-formed
    markup. That holds trivially here because every value is a number we formatted ourselves; any
    text taken from the payload would have to be escaped first.
    """
    if snapshot is None:
        return _offset(
            _span(SIGNED_OUT_LABEL if signed_out else LOADING_LABEL, STALE_COLOUR)
        )

    windows = []
    if snapshot.five_hour is not None:
        windows.append(("5h:", f"{snapshot.five_hour.percent}%"))
    if snapshot.seven_day is not None:
        windows.append(("7d:", f"{snapshot.seven_day.percent}%"))

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


def menu_rows(snapshot, stale, now, signed_out=False, reason=None):
    """The dropdown, as Pango markup.

    Strings rather than widgets because DBusMenu only carries labels, and markup only because the
    appindicator extension is patched to render our menu through set_markup; see
    home/gnome-shell/extensions/appindicator.nix. Rows whose data the account does not have are
    left out entirely: a Fable row reading 0% would claim an allowance that is not there.
    """
    if snapshot is None:
        text = SIGNED_OUT_LABEL_ROW if signed_out else LOADING_LABEL_ROW
        return [_row([(text, None)], stale=True)]

    rows = []
    for limit in (snapshot.five_hour, snapshot.seven_day, *snapshot.scoped):
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

    if snapshot.credits is not None:
        used = snapshot.credits.used
        limit_text = _format_money(snapshot.credits.limit, snapshot.credits.currency)
        amount = (
            f"{limit_text} limit"
            if used is None
            else f"{_format_money(used, snapshot.credits.currency)} / {limit_text}"
        )
        rows.append(
            _row([(f"{'Credits':<10} ", None), (amount, MENU_VALUE_COLOUR)], stale)
        )

    if stale:
        age = f"Last updated {format_age(snapshot.fetched_at, now)}"
        rows.append(_row([(f"{age} — {reason}" if reason else age, None)], stale=True))
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


def poll_delay(consecutive_failures, retry_after=None):
    """Seconds to wait before the next poll.

    Doubling starts from the healthy cadence rather than below it, so a run of failures can only
    ever slow polling down. The caller resets the failure count on success, and also when the
    credentials file changes, since that means a retry has a fresh reason to succeed.

    A Retry-After from the server raises the floor but never lowers it: being asked to come back in
    five seconds must not turn a run of 429s into a tight loop against an endpoint already refusing
    us. It is capped, because an hour of silence is the most a panel indicator should honour before
    trying again regardless.
    """
    backoff = min(
        MAXIMUM_BACKOFF_SECONDS,
        HEALTHY_CADENCE_SECONDS * 2**consecutive_failures,
    )
    if retry_after is None:
        return backoff
    return min(MAXIMUM_RETRY_AFTER_SECONDS, max(backoff, retry_after))


def delay_after_activity(seconds_since_attempt, consecutive_failures):
    """Seconds to wait after Claude Code reports activity.

    Re-times the poll so a refresh lands just after the numbers have actually moved, which is what
    keeps the panel agreeing with the tmux status line. Bounded two ways: never sooner than the
    healthy cadence allows, so a busy session cannot turn every render into a request, and never
    sooner than the current backoff, because activity says inference is working — it says nothing
    about the metadata endpoint, which has its own budget and may still be refusing us.
    """
    floor = poll_delay(consecutive_failures)
    if consecutive_failures:
        return floor
    return max(0, floor - max(0, seconds_since_attempt))


def is_stale(consecutive_failures, fetched_at, now):
    """Whether the displayed numbers should be marked as no longer trustworthy.

    Two triggers, because either alone leaves a gap: a couple of failures catch a fast outage
    without letting one dropped packet flicker the panel, and an age ceiling catches polls that
    keep failing too slowly for the count to climb.
    """
    if fetched_at is None:
        return False
    return (
        consecutive_failures >= STALE_AFTER_FAILURES or (now - fetched_at) > STALE_AFTER
    )


def parse_snapshot(payload, now):
    return Snapshot(
        five_hour=_parse_window(payload, "five_hour", "5-hour"),
        seven_day=_parse_window(payload, "seven_day", "7-day"),
        scoped=_parse_scoped(payload),
        credits=_parse_credits(payload),
        fetched_at=now,
    )

"""Building the status line's segments from the payload Claude Code pipes in on standard input.

Each segment offers its forms richest first, each with a penalty for the information that form gives
up; fit.py spends those penalties against the available width. Colour is baked into the form text
here so render.py only has to decide where the separators go.

The penalties are the whole tuning surface. They are ratios in practice, not absolutes: what matters
is a form's penalty against the columns it saves, because that ratio is what the fitter sorts on.
"""

import re
import fit
import palette

STAR = "✦"
BLOCK = "█"
ARROW_IN = "↑"
ARROW_OUT = "↓"
RING = "◌"
SIGMA = "Σ"
ELLIPSIS = "…"

CONTEXT_BAR_WIDE = 10
CONTEXT_BAR_NARROW = 6
BRANCH_SHORT_COLUMNS = 12
BRANCH_PREFIX_RE = re.compile(r"[+/@#.!?\s]")

# The five-hour window only earns its reset countdown once it is half spent. Below that the
# percentage alone is the whole story, and the countdown is nineteen columns that buy nothing.
RESET_SHOWN_FROM_PERCENT = 50


def percent_of(value):
    """A percentage as an integer, rounding half away from zero the way printf '%.0f' did."""
    return int(float(value) + 0.5)


def human_count(value):
    """A token count as 999, 1.2k or 1.2m."""
    if value >= 1_000_000:
        return f"{value / 1_000_000:.1f}m"
    if value >= 1_000:
        return f"{value / 1_000:.1f}k"
    return str(value)


def context_label(size):
    """The parenthesised context window size, as " (1m)" or " (200k)"."""
    if not size:
        return ""
    if size >= 1_000_000:
        return f" ({size // 1_000_000}m)"
    if size >= 1_000:
        return f" ({size // 1_000}k)"
    return ""


def model_name(model):
    """The model's human name.

    display_name already reads "Opus 4.6" or "Sonnet 5", so no parsing of the identifier is needed --
    except for the trailing parenthetical, which annotates the explicit [1m] variant the user asked
    for rather than the model's real context window. Sonnet 5 is a one-million-token model whose
    display_name says nothing about it, which is why the size label is computed from
    context_window.context_window_size instead.
    """
    display = (model.get("display_name") or "").strip()
    if display:
        return display.split(" (")[0].strip()
    return _name_from_identifier(model.get("id") or "")


def _name_from_identifier(model_id):
    bare = model_id.split("[")[0]
    parts = [part for part in bare.removeprefix("claude-").split("-") if part]
    if not parts:
        return bare or "?"
    return f"{parts[0].capitalize()} {'.'.join(parts[1:])}".strip()


def model_initials(name):
    """ "Opus 4.6" as "O4.6", "Sonnet 5" as "S5"."""
    words = name.split()
    if not words:
        return "?"
    return words[0][0].upper() + "".join(words[1:])


def reset_countdown(resets_at, now_epoch):
    """How long until a rate limit window resets, as "2h10m", or "" when unknown or already past."""
    try:
        target_epoch = int(resets_at)
    except (TypeError, ValueError):
        return ""
    remaining = target_epoch - now_epoch
    if remaining <= 0:
        return ""
    hours, minutes = remaining // 3600, (remaining % 3600) // 60
    return f"{hours}h{minutes}m" if hours else f"{minutes}m"


def build(payload, branch="", now_epoch=0, github_url=""):
    """Every segment that has data to show, in the order it renders.

    The clock and the branch arrive as arguments rather than being read here, which keeps this module
    free of subprocesses and of the current time.
    """
    candidates = (
        _model(payload),
        _branch(branch, github_url=github_url),
        _cost(payload),
        _duration(payload),
        _diff(payload),
        _tokens(payload),
        _context(payload),
        _five_hour(payload, now_epoch),
        _seven_day(payload),
    )
    return tuple(segment for segment in candidates if segment is not None)


def _model(payload):
    model = payload.get("model") or {}
    identifier = (model.get("id") or "").split("[")[0]
    if not identifier and not model.get("display_name"):
        return None
    label = context_label(
        (payload.get("context_window") or {}).get("context_window_size")
    )
    name = model_name(model)
    return fit.Segment(
        "model",
        "model",
        (
            fit.Form(
                palette.paint(f"{STAR} {identifier or name}{label}", palette.CYAN), 0
            ),
            fit.Form(palette.paint(f"{STAR} {name}{label}", palette.CYAN), 2),
            fit.Form(palette.paint(f"{STAR} {name}", palette.CYAN), 5),
            fit.Form(palette.paint(f"{STAR} {model_initials(name)}", palette.CYAN), 14),
        ),
    )


def _branch_prefix(branch):
    """The leading token before the first separator, mirroring the tmux window-title normalisation."""
    match = BRANCH_PREFIX_RE.search(branch)
    if match:
        return branch[: match.start()]
    return ""


def _branch_label(text, branch, github_url):
    painted = palette.paint(text, palette.GREEN)
    if github_url:
        return palette.link(painted, f"{github_url}/tree/{branch}")
    return painted


def _branch(branch, github_url=""):
    if not branch:
        return None
    prefix = _branch_prefix(branch)
    if prefix and len(prefix) < len(branch):
        forms = (
            fit.Form(_branch_label(branch, branch, github_url), 0),
            fit.Form(_branch_label(prefix, branch, github_url), 1),
            fit.Form(fit.DROP, 30),
        )
    else:
        short = branch
        if len(branch) > BRANCH_SHORT_COLUMNS:
            short = branch[: BRANCH_SHORT_COLUMNS - 1] + ELLIPSIS
        forms = (
            fit.Form(_branch_label(branch, branch, github_url), 0),
            fit.Form(_branch_label(short, branch, github_url), 5),
            fit.Form(fit.DROP, 30),
        )
    return fit.Segment("branch", "branch", tuple(forms))


def _cost(payload):
    total = (payload.get("cost") or {}).get("total_cost_usd")
    if not total:
        return None
    return fit.Segment(
        "cost",
        "cost",
        (
            fit.Form(palette.paint(f"${total:.2f}", palette.PASTEL_YELLOW), 0),
            fit.Form(fit.DROP, 5),
        ),
    )


def _duration(payload):
    milliseconds = (payload.get("cost") or {}).get("total_duration_ms")
    if not milliseconds:
        return None
    seconds = int(milliseconds) // 1000
    hours, minutes = seconds // 3600, (seconds % 3600) // 60
    if hours:
        text = f"{hours}h{minutes}m"
    elif minutes:
        text = f"{minutes}m"
    else:
        # Under a minute the shell implementation showed nothing, and a bare "0m" is noise.
        return None
    return fit.Segment(
        "duration",
        "duration",
        (
            fit.Form(palette.paint(text, palette.PASTEL_MAGENTA), 0),
            fit.Form(fit.DROP, 4),
        ),
    )


def _diff(payload):
    cost = payload.get("cost") or {}
    if "total_lines_added" not in cost and "total_lines_removed" not in cost:
        return None
    added = cost.get("total_lines_added") or 0
    removed = cost.get("total_lines_removed") or 0
    text = (
        palette.paint(f"+{added}", palette.PASTEL_GREEN)
        + "/"
        + palette.paint(f"-{removed}", palette.PASTEL_RED)
    )
    return fit.Segment("diff", "diff", (fit.Form(text, 0), fit.Form(fit.DROP, 6)))


def _tokens(payload):
    window = payload.get("context_window") or {}
    usage = window.get("current_usage")
    if not usage:
        return None
    incoming = human_count(usage.get("input_tokens") or 0)
    outgoing = human_count(usage.get("output_tokens") or 0)
    thinking = human_count(usage.get("cache_creation_input_tokens") or 0)
    total = human_count(
        (window.get("total_input_tokens") or 0)
        + (window.get("total_output_tokens") or 0)
    )
    return fit.Segment(
        "tokens",
        "tokens",
        (
            fit.Form(
                f"{incoming}{ARROW_IN} {outgoing}{ARROW_OUT} {thinking}{RING} {SIGMA}{total}",
                0,
            ),
            fit.Form(f"{SIGMA}{total}", 4),
            fit.Form(fit.DROP, 8),
        ),
    )


def _context(payload):
    window = payload.get("context_window") or {}
    used = window.get("used_percentage")
    if used is None:
        return None
    percent = percent_of(used)
    window_size = window.get("context_window_size") or 1_000_000
    tokens_used = int(float(used) * window_size / 100)
    colour = palette.context_color(tokens_used)

    def bar(columns):
        filled = min(columns, percent * columns // 100)
        return BLOCK * filled + "-" * (columns - filled)

    return fit.Segment(
        "ctx",
        "ctx",
        (
            fit.Form(palette.paint(f"{bar(CONTEXT_BAR_WIDE)} {percent}%", colour), 0),
            fit.Form(palette.paint(f"{bar(CONTEXT_BAR_NARROW)} {percent}%", colour), 2),
            fit.Form(palette.paint(f"{percent}%", colour), 8),
        ),
    )


def _five_hour(payload, now_epoch):
    window = (payload.get("rate_limits") or {}).get("five_hour") or {}
    used = window.get("used_percentage")
    if used is None:
        return None
    percent = percent_of(used)
    labelled = palette.paint("5h:", palette.DIM_TEAL) + palette.paint(
        f"{percent}%", palette.PASTEL_TEAL
    )
    compact = palette.paint(f"5h{percent}", palette.PASTEL_TEAL)
    countdown = reset_countdown(window.get("resets_at"), now_epoch)
    if percent >= RESET_SHOWN_FROM_PERCENT and countdown:
        forms = (
            fit.Form(f"{labelled} (resets {countdown})", 0),
            fit.Form(labelled, 4),
            fit.Form(compact, 10),
            fit.Form(fit.DROP, 60),
        )
    else:
        forms = (fit.Form(labelled, 0), fit.Form(compact, 6), fit.Form(fit.DROP, 60))
    return fit.Segment("five_hour", "rate", forms)


def _seven_day(payload):
    window = (payload.get("rate_limits") or {}).get("seven_day") or {}
    used = window.get("used_percentage")
    if used is None:
        return None
    percent = percent_of(used)
    return fit.Segment(
        "seven_day",
        "rate",
        (
            fit.Form(
                palette.paint("7d:", palette.DIM_TEAL)
                + palette.paint(f"{percent}%", palette.PASTEL_TEAL),
                0,
            ),
            fit.Form(palette.paint(f"7d{percent}", palette.PASTEL_TEAL), 3),
            fit.Form(fit.DROP, 20),
        ),
    )

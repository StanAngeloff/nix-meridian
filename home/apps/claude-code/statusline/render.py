"""Turning chosen segment forms into the one line the status line prints, and measuring it.

This is the only place that knows how segments become a line: which separator goes between them and
which of them share a run. `measure_with` hands the fitter the width of a candidate line built by
this same code, so the width the fitter optimises against cannot drift from the width that ships.

Widths are display columns, not bytes, because Claude Code truncates by column: colour costs
nothing, and the ambiguous-width glyphs this line uses each count as one. Both were confirmed
against a live session, where 46 such glyphs fitted a 50-column pane and 47 truncated -- exactly the
ASCII boundary.
"""

import re
import unicodedata

import palette

# SGR colour sequences and OSC 8 hyperlink open/close markers — all zero-width.
ANSI_SEQUENCE = re.compile(r"\x1b\[[0-9;]*m|\x1b\]8;;[^\x1b]*\x1b\\")

# East Asian Width classes that occupy two terminal columns. "A" (ambiguous) is deliberately absent:
# Claude Code counts it as one, matching Node's string-width default, and almost every glyph on this
# line is ambiguous.
DOUBLE_WIDTH_CLASSES = frozenset({"W", "F"})

SEPARATOR = f"{palette.DIM_GRAY} │ {palette.RESET}"
WITHIN_GROUP = " "


def visible_width(text):
    """The terminal columns `text` occupies once colour sequences are removed."""
    bare = ANSI_SEQUENCE.sub("", text)
    return sum(
        2 if unicodedata.east_asian_width(char) in DOUBLE_WIDTH_CLASSES else 1
        for char in bare
    )


def render(segments, chosen):
    """The line, colour included. Dropped segments leave no separator behind."""
    runs = []
    for segment in segments:
        text = segment.forms[chosen[segment.key]].text
        if not text:
            continue
        if runs and runs[-1][0] == segment.group:
            runs[-1][1].append(text)
        else:
            runs.append((segment.group, [text]))
    return SEPARATOR.join(WITHIN_GROUP.join(texts) for _, texts in runs)


def measure_with(segments):
    """A `measure` callable for fit(), closed over these segments."""
    return lambda chosen: visible_width(render(segments, chosen))

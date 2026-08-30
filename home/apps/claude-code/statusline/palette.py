"""The status line's colours, in one place so segments.py and render.py need not import each other.

Carried over unchanged from the shell implementation this replaced: the line's appearance on a wide
terminal is not part of what changed.
"""

CYAN = "\x1b[38;2;78;205;196m"
GREEN = "\x1b[32m"
DIM_GRAY = "\x1b[38;2;100;100;100m"
RESET = "\x1b[0m"
PASTEL_YELLOW = "\x1b[38;2;229;192;123m"
PASTEL_MAGENTA = "\x1b[38;2;198;146;233m"
PASTEL_TEAL = "\x1b[38;2;86;182;194m"
DIM_TEAL = "\x1b[38;2;55;120;128m"
PASTEL_GREEN = "\x1b[38;2;152;195;121m"
PASTEL_RED = "\x1b[38;2;224;108;117m"
AMBER = "\x1b[38;2;255;191;0m"


def paint(text, colour):
    """`text` in `colour`, reset afterwards."""
    return f"{colour}{text}{RESET}"


def link(text, url):
    """`text` as a clickable OSC 8 hyperlink."""
    return f"\x1b]8;;{url}\x1b\\{text}\x1b]8;;\x1b\\"

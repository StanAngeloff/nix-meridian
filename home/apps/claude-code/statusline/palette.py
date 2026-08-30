"""The status line's colours, in one place so segments.py and render.py need not import each other.

Carried over unchanged from the shell implementation this replaced: the line's appearance on a wide
terminal is not part of what changed.
"""

import math

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

# Context bar gradient keypoints, interpolated in Oklab for perceptually even transitions.
#
# The context bar changes color as the session fills to signal degradation quality:
#
#     0-100k tokens   solid green            session is fresh, no pressure
#     100k-140k       green to pale amber    linear in Oklab; 140k is where quality starts dropping
#     140k-200k       pale amber to orange   linear in Oklab; things are noticeably worse
#     200k-1M         orange to red          ease-out curve 1-(1-t)^13, see below
#
# The 200k-1M band uses a steep ease-out so that most of the visible change happens in the first
# 160k tokens past 200k (by 360k the curve is at 94%, essentially red). The exponent 13 comes from
# solving 1-(1-0.2)^n = 0.95 for n, where 0.2 is 160k/800k. A power curve like t^0.14 would hit
# the same 80%-at-20% target but has infinite slope at t=0, producing a visible cliff at the 200k
# boundary; the ease-out form 1-(1-t)^n has slope n at t=0 (finite), giving a smooth entry.
#
# Interpolation happens in Oklab rather than sRGB so the green-to-amber midpoint doesn't muddy or
# desaturate the way linear RGB blending does.
_GREEN_RGB = (152, 195, 121)
_PALE_AMBER_RGB = (229, 192, 123)
_FIERY_ORANGE_RGB = (255, 140, 50)
_SCREAMING_RED_RGB = (255, 30, 30)


def _srgb_to_linear(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return int(
        (12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055) * 255 + 0.5
    )


def _linear_to_oklab(r, g, b):
    el = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_ = math.copysign(abs(el) ** (1 / 3), el)
    m_ = math.copysign(abs(m) ** (1 / 3), m)
    s_ = math.copysign(abs(s) ** (1 / 3), s)
    return (
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    )


def _oklab_to_linear(big_l, a, b):
    l_ = big_l + 0.3963377774 * a + 0.2158037573 * b
    m_ = big_l - 0.1055613458 * a - 0.0638541728 * b
    s_ = big_l - 0.0894841775 * a - 1.2914855480 * b
    return (
        +4.0767416621 * l_**3 - 3.3077115913 * m_**3 + 0.2309699292 * s_**3,
        -1.2684380046 * l_**3 + 2.6097574011 * m_**3 - 0.3413193965 * s_**3,
        -0.0041960863 * l_**3 - 0.7034186147 * m_**3 + 1.7076147010 * s_**3,
    )


def _rgb_to_oklab(r, g, b):
    return _linear_to_oklab(_srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b))


def _oklab_to_rgb(big_l, a, b):
    lr, lg, lb = _oklab_to_linear(big_l, a, b)
    return _linear_to_srgb(lr), _linear_to_srgb(lg), _linear_to_srgb(lb)


def _lerp_oklab(c1, c2, t):
    lab1, lab2 = _rgb_to_oklab(*c1), _rgb_to_oklab(*c2)
    return _oklab_to_rgb(*(a + (b - a) * t for a, b in zip(lab1, lab2)))


def context_color(tokens_used):
    """A true-color escape for the context bar, graduated from green through amber/orange to red."""
    if tokens_used <= 100_000:
        r, g, b = _GREEN_RGB
    elif tokens_used <= 140_000:
        r, g, b = _lerp_oklab(
            _GREEN_RGB, _PALE_AMBER_RGB, (tokens_used - 100_000) / 40_000
        )
    elif tokens_used <= 200_000:
        r, g, b = _lerp_oklab(
            _PALE_AMBER_RGB, _FIERY_ORANGE_RGB, (tokens_used - 140_000) / 60_000
        )
    else:
        t = (tokens_used - 200_000) / 800_000
        t = 1 - (1 - t) ** 13
        r, g, b = _lerp_oklab(_FIERY_ORANGE_RGB, _SCREAMING_RED_RGB, t)
    return f"\x1b[38;2;{r};{g};{b}m"


def paint(text, colour):
    """`text` in `colour`, reset afterwards."""
    return f"{colour}{text}{RESET}"


def link(text, url):
    """`text` as a clickable OSC 8 hyperlink."""
    return f"\x1b]8;;{url}\x1b\\{text}\x1b]8;;\x1b\\"

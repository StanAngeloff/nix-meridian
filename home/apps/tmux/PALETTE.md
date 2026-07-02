# @claude-state traffic-light palette

How the colours in the tmux format strings were chosen (July 2026).

## Anchor

The focused-tab background in Ghostty is `colour39` from the xterm 256 cube:

    colour39 = #00afff = hsl(199, 100%, 50%)

This became the Tailwind-style "500" — the reference point for saturation (100%) and lightness (50%). Every state colour is derived from this energy level, just at a different hue.

## Ghostty palette matters

Colours 0-15 are overridden by Ghostty (defined in `home/apps/ghostty/default.nix`), so they don't match xterm defaults. Colours 16-255 follow the standard xterm 6x6x6 cube and greyscale ramp.

## Tailwind-like shade system

Each hue has shades from 50 (near-white) to 950 (near-black), varying only lightness. Three shades are used:

| Role                         | Shade | Lightness | Where it appears                     |
| :--------------------------- | :---- | :-------- | :----------------------------------- |
| Unfocused dot                | 500   | 50%       | Coloured dot on dark (#080808) bar   |
| Focused tab background       | 500   | 50%       | Full tab tint, black text            |
| Focused dot (on coloured bg) | 700   | 30%       | Darker dot visible against bright bg |

The 700-shade dot was chosen over 300 (too washed out), 800/900 (indistinguishable from black), and white (loses hue information). It sits at the sweet spot where the dot reads as a distinct element against its own-hue background without fighting the text for attention.

## State hues

| State       | Hue | Saturation | Reasoning                                                 |
| :---------- | :-- | :--------- | :-------------------------------------------------------- |
| blocked     | 0   | 100%       | Pure red — universal "stop / needs attention"             |
| working     | 35  | 100%       | Warm amber-orange — activity without alarm                |
| idle-unread | 120 | 100%       | Pure green — done, unread                                 |
| idle-read   | 120 | 40%        | Same green hue, desaturated — done, already seen          |
| no-state    | 199 | 100%       | Cyan (the anchor) — Claude Code not running, just the tab |

### Why read is desaturated, not a different hue

Two options were tested: (A) shifting read to hue 150 (spring green, distinct from 120) and (B) keeping hue 120 but dropping saturation to 40%. Option A introduced a bluish tint that looked off next to the other pure-hue states. Option B felt natural — same green family, just quieter — and matched the original colour108 (`hsl(120, 20%, 60%)`) in spirit.

## Final colour table

| State       | Dot (unfocused) | Background (focused) | Dot (focused) |
| :---------- | :-------------- | :------------------- | :------------ |
| blocked     | #ff0000         | #ff0000              | #990000       |
| working     | #ff9300         | #ff9300              | #995900       |
| idle-unread | #00ff00         | #00ff00              | #009900       |
| idle-read   | #4cb24c         | #4cb24c              | #009900       |
| no-state    | (none)          | #00afff              | (none)        |

Text: #000000 (black) on focused tabs, #9e9e9e (grey) on unfocused. Bar background: #080808.

## Dot rules

- A dot means Claude Code is running in that window (any state).
- No dot means Claude Code is not running — just the tab background (cyan for focused, dark for unfocused).
- The dot sits after the window index, before the name: `5| ● Claude 1`.
- On unfocused tabs the dot is shade 500 (bright) against the dark bar.
- On focused tabs the dot is shade 700 (darker) against the shade-500 background.

---

> [!TIP]
> **tmux format gotcha** – Commas inside `#[fg=X,bg=Y]` are treated as ternary separators by the tmux format parser (`#{?cond,then,else}`). This silently breaks the conditional. The fix is to split combined styles into separate directives: `#[fg=X]#[bg=Y]`. Found and verified on tmux 3.6a.

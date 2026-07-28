# @claude-window-state traffic-light palette

How the colours in the tmux format strings were chosen (July 2026).

## Anchor

The focused-tab background in Ghostty is `colour39` from the xterm 256 cube:

    colour39 = #00afff = hsl(199, 100%, 50%)

This became the Tailwind-style "500" — the reference point for saturation (100%) and lightness (50%). Every state colour is derived from this energy level, just at a different hue.

## Ghostty palette matters

Colours 0-15 are overridden by Ghostty (defined in `home/apps/ghostty/default.nix`), so they don't match xterm defaults. Colours 16-255 follow the standard xterm 6x6x6 cube and greyscale ramp.

## Tailwind-like shade system

Each hue has shades from 50 (near-white) to 950 (near-black), varying only lightness. Two dot shades are used, one per focus state:

| Role          | Shade | Lightness | Where it appears                                        |
| :------------ | :---- | :-------- | :------------------------------------------------------ |
| Unfocused dot | 500   | 50%       | Bright coloured dot on the dark (#080808) bar           |
| Focused dot   | 600   | 40%       | Darkened coloured dot on the cyan (#00afff) focused tab |

The focused tab keeps its familiar cyan background (the anchor) — the dot alone carries the state. Because cyan is bright, a _darkened_ dot (shade 600, L=40%) reads against it — the inverse of the unfocused case, where a _bright_ dot (shade 500) pops against the dark bar. L40 was chosen deliberately: L30 reads better but drifts muddy, and L50 blends into the cyan tab. L40 trades a little legibility to stay faithful to the original hue.

### An abandoned detour: state-coloured backgrounds

An earlier iteration tinted the whole focused tab with the state colour (red/amber/green background, dark dot on top). It worked and tested clean, but in daily use it read as _too different_ — the familiar cyan tab was gone. Reverted to the uniform cyan background above; the dot does the signalling.

## State hues

| State    | Hue | Saturation | Reasoning                                                 |
| :------- | :-- | :--------- | :-------------------------------------------------------- |
| blocked  | 0   | 100%       | Pure red — universal "stop / needs attention"             |
| working  | 35  | 100%       | Warm amber-orange — activity without alarm                |
| unread   | 120 | 100%       | Pure green — done, unread                                 |
| read     | 120 | 40%        | Same green hue, desaturated — done, already seen          |
| no-state | 199 | 100%       | Cyan (the anchor) — Claude Code not running, just the tab |

### Why read is desaturated, not a different hue

Two options were tested: (A) shifting read to hue 150 (spring green, distinct from 120) and (B) keeping hue 120 but dropping saturation to 40%. Option A introduced a bluish tint that looked off next to the other pure-hue states. Option B felt natural — same green family, just quieter — and matched the original colour108 (`hsl(120, 20%, 60%)`) in spirit.

The desaturation does double duty: it keeps read distinct from unread on the focused tab too, where both are darkened greens (unread #00cc00 full-sat vs read #3d8e3d muted). Without it the two focused states would be near-identical.

## Final colour table

| State    | Dot (unfocused) | Dot (focused) | Focused tab bg |
| :------- | :-------------- | :------------ | :------------- |
| blocked  | #ff0000         | #cc0000       | #00afff        |
| working  | #ff9300         | #cc7500       | #00afff        |
| unread   | #00ff00         | #00cc00       | #00afff        |
| read     | #4cb24c         | #3d8e3d       | #00afff        |
| no-state | (none)          | (none)        | #00afff        |

Text: #000000 (black) on focused tabs, #9e9e9e (grey) on unfocused. Bar background: #080808. The focused tab background is always #00afff regardless of state.

## Dot rules

- A dot means Claude Code is running in that window (any state).
- No dot means Claude Code is not running — just the tab background (cyan for focused, dark for unfocused).
- The dot sits after the window index, before the name: `5| ● Claude 1`.
- On unfocused tabs the dot is shade 500 (bright) against the dark bar.
- On focused tabs the dot is shade 600 (darkened) against the cyan tab background.

---

> [!TIP]
> **tmux format gotcha** – Commas inside `#[fg=X,bg=Y]` are treated as ternary separators by the tmux format parser (`#{?cond,then,else}`). This silently breaks the conditional. The fix is to split combined styles into separate directives: `#[fg=X]#[bg=Y]`. Found and verified on tmux 3.6a.

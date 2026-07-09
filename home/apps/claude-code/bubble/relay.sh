# Host-side notification relay for a bubbled Claude Code session. Tails the bubble event file
# (written by the in-bubble hook) and applies the tmux @claude-state traffic light on the
# launching pane + plays the chime. Runs entirely host-side, where tmux and PipeWire are
# reachable. Args: <state-file> <tmux-pane> <chime-mp3>
set -euo pipefail

event_file="$1"
tmux_pane="$2"
chime_file="$3"

apply() {
	local state="$1" chime="$2"
	if [ -n "$tmux_pane" ]; then
		# Resolve idle -> born read/unread from the pane's live window focus. This lives host-side
		# (not in the in-bubble hook) because only here is the tmux socket reachable; mirrors the
		# un-bubbled hook's rule so bubbled and un-bubbled sessions render identically.
		if [ "$state" = idle ]; then
			if [ "$(tmux display -p -t "$tmux_pane" '#{window_active}' 2>/dev/null)" = 1 ]; then
				state=idle-read
			else
				state=idle-unread
			fi
		fi
		if [ "$state" = off ]; then
			tmux set -wu -t "$tmux_pane" @claude-state 2>/dev/null || true
		else
			tmux set -w -t "$tmux_pane" @claude-state "$state" 2>/dev/null || true
		fi
	fi
	if [ "$chime" = 1 ]; then
		setsid --fork pw-play "$chime_file" >/dev/null 2>&1 || true
	fi
}

# Tail appended lines; each is "state\tchime".
tail -n +1 -F "$event_file" 2>/dev/null | while IFS=$'\t' read -r state chime; do
	if [ -n "$state" ]; then apply "$state" "${chime:-0}"; fi
done

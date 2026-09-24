# Host-side notification bridge: relay.sh (its own writeShellApplication, see module.nix) runs as a companion process, tailing the event file and applying the tmux state light + chime host-side, so tmux and PipeWire sockets never cross the boundary.
# relay_pid is global: it crosses from the before-run hook to the after-run and cleanup hooks.

notifications_prepare() {
	# Event channel to the relay; lives under the writable ~/.claude so in-bubble hooks can append to it and the host relay can read it.
	# mktemp: several sessions may run in the same project directory simultaneously, one event channel each.
	event_path="$home_path/.claude/bubble-events"
	mkdir -p "$event_path"
	event_file="$(mktemp "$event_path/$(basename "$project_path").XXXXXX")"
}

notifications_environment() {
	bwrap_args+=(
		--setenv CLAUDE_BUBBLE_EVENT_FILE "$event_file"
		# The bubble must never talk to the host tmux directly — the relay owns that side.
		--unsetenv TMUX
		--unsetenv TMUX_PANE
	)
}

notifications_before_run() {
	# TMUX_PANE is still set here (host side); the bubble child gets it unset via --unsetenv.
	relay_pid=""
	if [[ -n "${TMUX_PANE:-}" ]]; then
		setsid "@bubbleRelay@" "$event_file" "$TMUX_PANE" "@chimeMp3@" &
		relay_pid=$!
	fi
}

notifications_after_run() {
	if [[ -n "$relay_pid" ]]; then
		kill -- -"$relay_pid" 2>/dev/null || true
		# Cleared so the cleanup hook does not signal the group again, by then possibly a new one reusing the number.
		relay_pid=""
		tmux set -pu -t "$TMUX_PANE" @claude-pane 2>/dev/null || true
		tmux set -pu -t "$TMUX_PANE" @claude-blocked 2>/dev/null || true
		tmux set -pu -t "$TMUX_PANE" @claude-unread 2>/dev/null || true
		tmux set -pu -t "$TMUX_PANE" @tig_path 2>/dev/null || true
	fi
}

notifications_cleanup() {
	# After-run is skipped when the session ends through the EXIT trap alone, as when its pane is closed.
	# The relay runs in its own session outside the session scope, so nothing else stops it: it would tail the deleted file forever.
	if [[ -n "${relay_pid:-}" ]]; then
		kill -- -"$relay_pid" 2>/dev/null || true
		relay_pid=""
	fi
	if [[ -n "${event_file:-}" ]]; then rm -f "$event_file"; fi
}

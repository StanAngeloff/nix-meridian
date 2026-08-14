# shellcheck shell=bash
# Drive the tmux Claude Code traffic light from a Claude Code hook, and apply the resulting pane options.
#
# Working and idle are not decided here. Claude Code writes them into its own terminal title, which tmux exposes as #{pane_title}, and home/apps/tmux/claude-state.conf turns that into a dot. This script owns only what the title cannot say: that a prompt is waiting, and whether a finished turn has been looked at.
#
# Two entry points:
#   (stdin)                       a hook payload; resolves an action and applies it to $TMUX_PANE
#   --apply <pane> <action>       applies an action to a pane, for the bubble relay, which reaches tmux when the in-bubble hook cannot
#
# Actions: session-start, turn-start, blocked, turn-end, session-end.
#
# Dry run: CLAUDE_TMUX_DRY_RUN=1 prints the resolved action and never touches tmux or the bubble event channel.

# Is the user actually watching this pane?
# @claude-focused only exists once a focus event has fired for the pane, so a pane that has never gained or lost focus since the server started has no value at all. Reading that absence as "not watched" would mark a turn unread in a freshly created pane you are staring at, so it falls back to being the active pane of the active window. Once any focus event fires the fallback stops applying.
is_watched() {
	local pane_id="$1" focused
	focused="$(tmux show -pqv -t "$pane_id" @claude-focused 2>/dev/null || true)"
	if [ -n "$focused" ]; then
		[ "$focused" = 1 ]
		return
	fi
	[ "$(tmux display -p -t "$pane_id" '#{&&:#{pane_active},#{window_active}}' 2>/dev/null || echo 0)" = 1 ]
}

apply_action() {
	local pane_id="$1" action="$2"
	case "$action" in
	session-start)
		tmux set -p -t "$pane_id" @claude-pane 1 2>/dev/null || true
		tmux set -pu -t "$pane_id" @claude-blocked 2>/dev/null || true
		tmux set -pu -t "$pane_id" @claude-unread 2>/dev/null || true
		;;
	blocked)
		tmux set -p -t "$pane_id" @claude-blocked 1 2>/dev/null || true
		;;
	turn-start)
		tmux set -pu -t "$pane_id" @claude-blocked 2>/dev/null || true
		tmux set -pu -t "$pane_id" @claude-unread 2>/dev/null || true
		;;
	turn-end)
		tmux set -pu -t "$pane_id" @claude-blocked 2>/dev/null || true
		if is_watched "$pane_id"; then
			tmux set -pu -t "$pane_id" @claude-unread 2>/dev/null || true
		else
			tmux set -p -t "$pane_id" @claude-unread 1 2>/dev/null || true
		fi
		;;
	session-end)
		tmux set -pu -t "$pane_id" @claude-pane 2>/dev/null || true
		tmux set -pu -t "$pane_id" @claude-blocked 2>/dev/null || true
		tmux set -pu -t "$pane_id" @claude-unread 2>/dev/null || true
		;;
	esac
	tmux refresh-client -S 2>/dev/null || true
}

# Resolve the action a hook payload implies. Prints nothing for events that no longer matter.
get_action() {
	local event agent_id tool
	# jq emits one field per line (comma operator); read one line at a time.
	# A single IFS=$'\t' read would collapse an empty agent_id field — tab is IFS whitespace, so consecutive tabs merge into one delimiter and tool_name slides into $agent_id.
	{
		IFS= read -r event || true
		IFS= read -r agent_id || true
		IFS= read -r tool || true
	} < <(jq -r '(.hook_event_name // ""), (.agent_id // ""), (.tool_name // "")')

	# A waiting prompt halts the whole session whoever raised it, so subagent-originated blocks count.
	case "$event" in
	PermissionRequest | Elicitation)
		printf blocked
		return 0
		;;
	PreToolUse)
		case "$tool" in
		AskUserQuestion | ExitPlanMode) printf blocked ;;
		esac
		return 0
		;;
	esac

	# Everything below is main-agent lifecycle. A subagent runs inside the parent's turn and must never start or end it.
	if [ -n "$agent_id" ]; then
		return 0
	fi

	case "$event" in
	SessionStart) printf session-start ;;
	UserPromptSubmit) printf turn-start ;;
	Stop | StopFailure) printf turn-end ;;
	SessionEnd) printf session-end ;;
	esac
	return 0
}

if [ "${1:-}" = --apply ]; then
	apply_action "$2" "$3"
	exit 0
fi

action="$(get_action)"
[ -n "$action" ] || exit 0

# Checked before the bubble branch: a dry run is an explicit request to touch nothing, and a bubbled session exports CLAUDE_BUBBLE_EVENT_FILE to every child, so testing from inside one would otherwise silently append to a live event channel instead of printing.
if [ "${CLAUDE_TMUX_DRY_RUN:-}" = 1 ]; then
	printf '%s\n' "$action"
	exit 0
fi

# Inside the bubble there is no tmux socket. Forward the action to the host-side relay, which owns every tmux write — including the watched check, which the bubble cannot make.
if [ -n "${CLAUDE_BUBBLE_EVENT_FILE:-}" ]; then
	printf '%s\n' "$action" >>"$CLAUDE_BUBBLE_EVENT_FILE"
	exit 0
fi

[ -n "${TMUX_PANE:-}" ] || exit 0
apply_action "$TMUX_PANE" "$action"

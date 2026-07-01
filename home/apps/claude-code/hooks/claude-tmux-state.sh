# Drive the tmux @claude-state traffic light from a Claude Code hook.
# Reads the hook's JSON payload on stdin. jq and tmux come from the Nix wrapper PATH.
#
# @claude-state values written to the pane's window:
#   blocked | working | idle-unread | idle-read     (unset on session end)
#
# Dry run: CLAUDE_TMUX_DRY_RUN=1 prints the resolved state and never touches tmux;
# CLAUDE_TMUX_WINDOW_ACTIVE overrides the focused-window check.

# Get the target state purely from the stdin hook payload.
# Prints blocked|working|idle|off, or nothing to mean "ignore this event".
get_state() {
	local event agent tool state=''
	# jq emits one field per line (comma operator); read one line at a time.
	# A single IFS=$'\t' read would collapse an empty agent_id field — tab is IFS whitespace,
	# so consecutive tabs merge into one delimiter and tool_name slides into $agent.
	{
		IFS= read -r event || true
		IFS= read -r agent || true
		IFS= read -r tool || true
	} < <(jq -r '(.hook_event_name // ""), (.agent_id // ""), (.tool_name // "")')
	case "$event" in
	SessionStart) state='idle-read' ;;
	UserPromptSubmit) state='working' ;;
	PreToolUse)
		case "$tool" in
		AskUserQuestion | ExitPlanMode) state='blocked' ;;
		*) state='working' ;;
		esac
		;;
	PostToolUse) state='working' ;;
	PermissionRequest | Elicitation) state='blocked' ;;
	Stop | StopFailure) state='idle' ;;
	SessionEnd) state='off' ;;
	esac

	# The window tracks the MAIN agent, but a subagent runs inside the parent's turn, so its states count too.
	# Honor working (progress) and blocked (a permission or elicitation prompt halts the whole session on you, whoever raised it);
	# honoring the subagent's working events is also what clears the red once you approve, so the dot never sticks red.
	# A subagent must never end the parent's turn, so drop anything that resolves to idle/off
	# (subagent completion fires SubagentStop, which we do not handle).
	if [ -n "$agent" ]; then
		case "$state" in
		working | blocked) : ;;
		*) state='' ;;
		esac
	fi

	printf '%s' "$state"
}

state="$(get_state)"
[ -n "$state" ] || exit 0

# Is this pane's window currently focused? (Used only for the idle born-read rule.)
is_window_active() {
	if [ -n "${CLAUDE_TMUX_WINDOW_ACTIVE:-}" ]; then
		printf '%s' "$CLAUDE_TMUX_WINDOW_ACTIVE"
	else
		tmux display -p -t "$TMUX_PANE" '#{window_active}' 2>/dev/null || true
	fi
}

# A finished turn (Stop/StopFailure) is born unread, unless we are already looking at the window,
# in which case it is born read (you watched it finish).
if [ "$state" = idle ]; then
	if [ "$(is_window_active)" = 1 ]; then state='idle-read'; else state='idle-unread'; fi
fi

# Dry run: emit the decision and stop, without touching tmux.
if [ "${CLAUDE_TMUX_DRY_RUN:-}" = 1 ]; then
	printf '%s\n' "$state"
	exit 0
fi

[ -n "${TMUX_PANE:-}" ] || exit 0
if [ "$state" = off ]; then
	tmux set -wu -t "$TMUX_PANE" @claude-state 2>/dev/null || true
else
	tmux set -w -t "$TMUX_PANE" @claude-state "$state" 2>/dev/null || true
fi

# shellcheck shell=bash
# Set the per-pane @tig_path when Claude enters a worktree, clear it on exit.
# The tig popup (prefix + C-g) checks @tig_path before pane_current_path,
# so this makes it follow the worktree instead of the shell's working directory.

payload=$(cat)
tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty')

apply_tig_path() {
	local path="$1"
	if [ -n "${TMUX_PANE:-}" ]; then
		tmux set -p -t "$TMUX_PANE" @tig_path "$path" 2>/dev/null || true
	elif [ -n "${CLAUDE_BUBBLE_EVENT_FILE:-}" ]; then
		printf 'tig-path-set:%s\n' "$path" >>"$CLAUDE_BUBBLE_EVENT_FILE"
	fi
}

clear_tig_path() {
	if [ -n "${TMUX_PANE:-}" ]; then
		tmux set -pu -t "$TMUX_PANE" @tig_path 2>/dev/null || true
	elif [ -n "${CLAUDE_BUBBLE_EVENT_FILE:-}" ]; then
		printf 'tig-path-unset\n' >>"$CLAUDE_BUBBLE_EVENT_FILE"
	fi
}

case "$tool" in
EnterWorktree)
	path=$(printf '%s' "$payload" | jq -r '.tool_response.worktreePath // empty')
	[ -n "$path" ] && apply_tig_path "$path"
	;;
ExitWorktree)
	clear_tig_path
	;;
esac

exit 0

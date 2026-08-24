# shellcheck shell=bash
# Keep the tmux window name in step with the Claude Code session actually running in the pane.
#
# initialize.zsh names the window once, before Claude Code starts, from the --name/--resume flag.
# /resume and /branch then swap the session out from under that name -- both fire SessionStart, with
# source "resume" and "fork" respectively -- so this recomputes the name from whatever session is now
# current. /clear and /compact keep the name they had, so they are ignored.
#
# /rename changes the name with no hook of any kind, so it cannot be followed; see notifications.nix.
#
# The repository@name rule lives here and nowhere else: initialize.zsh calls --compute for it rather
# than keeping a second copy that could drift.
#
# Entry points:
#   --compute <session-name> [--branch]   print the window name for a session name; no lookup, no tmux
#   --apply <pane> <session-id> <source>  wait for the session's name, then rename that pane's window
#   (stdin)                               a SessionStart payload; dispatches --apply without blocking
#
# Claude Code writes the session name only after SessionStart returns: a few hundred milliseconds late
# on resume, and later still on a /branch left unnamed, where the name is generated rather than given.
# So --apply waits for it, and every caller reaches --apply detached -- a hook that blocked here would
# stall the very session start it is reporting on.

# U+E0A0, the powerline branch glyph already used in the shell prompt, marks a window whose session came
# from /branch. An unnamed branch reports a generated name, so the glyph is what distinguishes it.
# Written as an escape rather than the character itself: it sits in the private use area, where editors and
# copy-paste drop it silently, and a marker that degrades to a bare space is invisible rather than broken.
readonly branch_marker=$' \ue0a0'

readonly wait_seconds=30
readonly poll_seconds=0.2

# Claude Code records each live session as ~/.claude/sessions/<pid>.json.
# Matched on the sessionId field rather than the filename: a bubbled session's pid belongs to another
# namespace, so the filename cannot be predicted from inside the bubble.
# Prints "<name>\t<cwd>"; the cwd comes from the same record so the repository is resolved against the
# session's own directory rather than whichever one this process happens to have inherited.
resolve_session() {
	local session_id="$1" waited=0 record
	while :; do
		# /resume reuses the sessionId of the target, so multiple files can carry the same id at once: the
		# stale process that just exited and the new one that took it over. Picking the most recently updated
		# file avoids returning the old collision-renamed name instead of the current one.
		record=$(jq -r --arg id "$session_id" \
			'select(.sessionId == $id and (.name // "") != "")
			 | [.updatedAt // 0, .name, .cwd] | @tsv' \
			"$HOME"/.claude/sessions/*.json 2>/dev/null |
			sort -rnk1,1 | head -1 | cut -f2-)
		if [ -n "$record" ]; then
			printf '%s' "$record"
			return 0
		fi
		# Integer arithmetic on a fractional poll interval: five polls per second, hence the *5.
		waited=$((waited + 1))
		[ "$waited" -lt $((wait_seconds * 5)) ] || return 1
		sleep "$poll_seconds"
	done
}

# The name is truncated at the first punctuation or whitespace, which is what keeps a window name short
# enough to read in the status line. Anything after it is detail the status line has no room for.
compute_window_name() {
	local session_name="$1" marker="$2" directory="$3" git_common repository_name normalized
	git_common=$(git -C "$directory" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
	[ -n "$git_common" ] || return 1
	repository_name="${git_common%/.git}"
	repository_name="${repository_name##*/}"
	normalized="${session_name%%[/@#.!?[:space:]]*}"
	[ -n "$repository_name" ] && [ -n "$normalized" ] || return 1
	printf '%s@%s%s' "$repository_name" "$normalized" "$marker"
}

case "${1:-}" in
--compute)
	[ -n "${2:-}" ] || exit 1
	marker=""
	[ "${3:-}" = --branch ] && marker="$branch_marker"
	compute_window_name "$2" "$marker" "$PWD"
	exit
	;;
--apply)
	pane="$2"
	session_id="$3"
	source_name="$4"
	record=$(resolve_session "$session_id") || exit 0
	session_name="${record%%$'\t'*}"
	directory="${record#*$'\t'}"
	marker=""
	[ "$source_name" = fork ] && marker="$branch_marker"
	window_name=$(compute_window_name "$session_name" "$marker" "$directory") || exit 0
	# Resolved to the containing window rather than passing the pane as a window target: the wait means
	# the pane may be gone by now, and a lookup that fails is a rename that correctly does not happen.
	window_id=$(tmux display -p -t "$pane" '#{window_id}' 2>/dev/null) || exit 0
	[ -n "$window_id" ] || exit 0
	tmux rename-window -t "$window_id" "$window_name" 2>/dev/null || true
	exit 0
	;;
esac

# Hook path. The source is filtered here rather than by a SessionStart matcher: matcher semantics for
# this event are undocumented, and a matcher that silently never matches is indistinguishable from a
# working one that has nothing to do.
{
	IFS= read -r event || true
	IFS= read -r source_name || true
	IFS= read -r session_id || true
	IFS= read -r agent_id || true
} < <(jq -r '(.hook_event_name // ""), (.source // ""), (.session_id // ""), (.agent_id // "")')

[ "$event" = SessionStart ] || exit 0
[ -n "$session_id" ] || exit 0
# A subagent starting is not the session changing identity.
[ -z "$agent_id" ] || exit 0

case "$source_name" in
resume | fork) ;;
*) exit 0 ;;
esac

if [ "${CLAUDE_WINDOW_NAME_DRY_RUN:-}" = 1 ]; then
	printf 'window-name:%s:%s\n' "$session_id" "$source_name"
	exit 0
fi

# Inside the bubble there is no tmux socket, and the host-side relay is already asynchronous, so the
# wait costs the session nothing. Outside it, setsid buys the same thing the chime uses it for.
if [ -n "${CLAUDE_BUBBLE_EVENT_FILE:-}" ]; then
	printf 'window-name:%s:%s\n' "$session_id" "$source_name" >>"$CLAUDE_BUBBLE_EVENT_FILE"
	exit 0
fi

[ -n "${TMUX_PANE:-}" ] || exit 0
setsid --fork "$0" --apply "$TMUX_PANE" "$session_id" "$source_name" >/dev/null 2>&1
exit 0

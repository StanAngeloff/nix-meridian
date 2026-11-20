# shellcheck shell=bash
# CC session hub for remote access.
# Runs as the SSH forced command, outside tmux, in an outer loop.

set -euo pipefail

SESSION=remote
CLAUDE_DIR="$HOME/.claude"

list_recent_directories() {
	local max="${1:-9}"
	local -a results=()
	for dir in "$CLAUDE_DIR"/projects/*/; do
		[ -d "$dir" ] || continue
		local latest
		latest=$(find "$dir" -maxdepth 1 -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 || true)
		[ -n "$latest" ] || continue
		local ts file cwd
		ts=${latest%% *}
		file=${latest#* }
		cwd=$(grep -m1 -o '"cwd":"[^"]*"' "$file" 2>/dev/null | head -1)
		cwd=${cwd#'"cwd":"'}
		cwd=${cwd%'"'}
		[ -n "$cwd" ] && [ -d "$cwd" ] && results+=("$ts|$cwd")
	done
	if [ "${#results[@]}" -gt 0 ]; then
		printf '%s\n' "${results[@]}" | LC_ALL=C sort -rn | awk -F'|' '!seen[$2]++' | head -"$max" | cut -d'|' -f2
	fi
}

new_session_flow() {
	local -a directories=()
	mapfile -t directories < <(list_recent_directories 9)

	# A directory, then a profile and a name, on the screens new_session.py beside this script draws. It prints the
	# three on separate lines, or nothing when the phone went back to the list.
	local picked
	if ! picked=$(cc-hub-new-session "${directories[@]}"); then
		printf '\n  The new-session screens failed. Press a key to go back.\n'
		read -rsn1 || true
		return
	fi
	local -a chosen=()
	mapfile -t chosen <<<"$picked"
	if [ "${#chosen[@]}" -lt 3 ]; then
		return
	fi
	local target_dir="${chosen[0]}" profile_name="${chosen[1]}" session_name="${chosen[2]}"

	ensure_remote_session

	# The profile is always explicit: a session started without -P holds up switching the default profile until it ends.
	local -a profile_args=()
	if [ -n "$profile_name" ]; then
		profile_args=(-P "$profile_name")
	fi
	# direnv loads the .envrc the directory or a parent holds, such as bubble binds or a session-name rule, as a shell does
	# on cd. claude-cc then starts the session the way cc does.
	local launch
	printf -v launch '%q ' @direnv@ exec . @claudeCc@ "${profile_args[@]}" -n "$session_name"
	# new-window makes the new window current; it takes the lowest free index, so after a closed window it is not the last.
	tmux new-window -t "$SESSION" -n "$session_name" -c "$target_dir" "$launch; tmux detach-client"
	tmux attach -t "$SESSION"
}

ensure_remote_session() {
	# tmux copies these into the session from whichever client creates or attaches it, and SSH has none of them.
	# Take the laptop's values from the global environment so windows opened from the phone keep the desktop.
	local name assignment
	for name in WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE; do
		if assignment=$(tmux show-environment -g "$name" 2>/dev/null) && [[ "$assignment" == "$name="* ]]; then
			export "$name=${assignment#*=}"
		fi
	done

	# Clean up legacy session name if it exists.
	tmux kill-session -t phone 2>/dev/null || true

	if ! tmux has-session -t "$SESSION" 2>/dev/null; then
		# new-session -t fails unless the default session exists.
		tmux-default-session
		tmux new-session -d -t default -s "$SESSION"
	fi

	tmux set -t "$SESSION" status-position top

	# Status bar via status-format[0]: completely replaces the status line rendering so the
	# global window-status-format (shared across grouped sessions) does not show all windows.
	# Dimmed back button on the left, colored state dot + window name in the center.
	tmux set -t "$SESSION" 'status-format[0]' \
		'#[align=left,fg=colour247,dim] ◀ Sessions #[nodim,default,align=centre]#{?#{E:@claude-window-state},#{?#{==:#{E:@claude-window-state},blocked},#[fg=#ff0000]●,#{?#{==:#{E:@claude-window-state},working},#[fg=#ff9300]●,#{?#{==:#{E:@claude-window-state},unread},#[fg=#00ff00]●,#[fg=#4cb24c]●}}}#[fg=colour247] ,}#W #[align=right]'

	# Back button: tap the ◀ Sessions region (x < 12) to detach back to the hub.
	# status-format[0] fires MouseDown1StatusDefault for all regions; the nested if-shell
	# restricts the detach to clicks in the back button area only.
	tmux bind -n MouseDown1StatusDefault if -F "#{==:#S,$SESSION}" \
		'if-shell "[ #{mouse_x} -lt 12 ]" "detach-client"'
	tmux bind Escape if -F "#{==:#S,$SESSION}" 'detach-client'
}

select_and_attach() {
	local pane_id="$1" window_id="$2"
	tmux select-window -t "$SESSION:=${window_id}" 2>/dev/null || true
	tmux select-pane -t "$pane_id" -Z 2>/dev/null || true
	tmux attach -t "$SESSION"
}

main() {
	ensure_remote_session

	while true; do
		# The navigator's rows for the windows of the remote session's group, drawn by the navigator's own code
		# (home/apps/tmux/navigator/pick.py), so the phone shows them as the laptop does.
		local choice
		if ! choice=$(tmux-navigator pick "$SESSION"); then
			printf '\n  The session list failed. Press a key to try again.\n'
			read -rsn1 || exit 0
			continue
		fi
		local kind window_id pane_id
		read -r kind window_id pane_id <<<"$choice"
		case "$kind" in
		open)
			select_and_attach "$pane_id" "$window_id"
			;;
		new)
			new_session_flow
			;;
		*)
			exit 0 # quit, or the connection closed
			;;
		esac
	done
}

main

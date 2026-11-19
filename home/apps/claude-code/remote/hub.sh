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

abbreviate_home() {
	local path="$1"
	if [[ "$path" == "$HOME" || "$path" == "$HOME"/* ]]; then
		printf '%s' "~${path#"$HOME"}"
	else
		printf '%s' "$path"
	fi
}

render_directory_picker() {
	local total="$1"
	printf '\033[2J\033[H'
	printf '\033[1m  Select a directory\033[0m\n\n'

	local index=0
	while IFS= read -r dir_path; do
		index=$((index + 1))
		local label
		label=$(abbreviate_home "$dir_path")
		local key=$((total - index + 1))
		printf '  %s│ %s\n' "$key" "$label"
	done

	if [ "$index" -eq 0 ]; then
		printf '  \033[2mNo project directories found.\033[0m\n'
	fi

	printf '\n  \033[2mType a number or Escape to go back.\033[0m\n'
	return "$index"
}

new_session_flow() {
	local entries=()
	while IFS= read -r line; do
		entries+=("$line")
	done < <(list_recent_directories 9 | tac)

	local count="${#entries[@]}"
	local rendered_count=0
	if [ "$count" -eq 0 ]; then
		render_directory_picker 0 </dev/null || rendered_count=$?
	else
		render_directory_picker "$count" < <(printf '%s\n' "${entries[@]}") || rendered_count=$?
	fi

	if [ "$rendered_count" -eq 0 ]; then
		sleep 2
		return
	fi

	local selection=""
	if ! read -rsn1 -t 30 selection; then
		return
	fi

	local idx=-1
	case "$selection" in
	[1-9])
		idx=$((count - selection))
		;;
	esac

	if [ "$idx" -lt 0 ] || [ "$idx" -ge "$count" ]; then
		return
	fi

	local target_dir="${entries[$idx]}"

	printf '\033[2J\033[H'
	local label
	label=$(abbreviate_home "$target_dir")
	printf '\033[1m  New session in %s\033[0m\n\n' "$label"
	printf '  Session name: '
	local session_name=""
	read -r session_name </dev/tty
	if [ -z "$session_name" ]; then
		return
	fi

	ensure_remote_session

	# direnv loads the .envrc the directory or a parent holds, such as bubble binds or a session-name rule, as a shell does
	# on cd. claude-cc then starts the session the way cc does.
	local launch
	printf -v launch '%q ' @direnv@ exec . @claudeCc@ -n "$session_name"
	tmux new-window -t "$SESSION" -n "$session_name" -c "$target_dir" "$launch; tmux detach-client"
	tmux select-window -t "$SESSION:{end}"
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

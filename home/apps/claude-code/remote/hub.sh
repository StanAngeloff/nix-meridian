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

	local zsh_cmd
	zsh_cmd="cd $(printf '%q' "$target_dir") && cc -n $(printf '%q' "$session_name")"
	tmux new-window -t "$SESSION" -n "$session_name" \
		"zsh -ic $(printf '%q' "$zsh_cmd"); tmux detach-client"
	tmux select-window -t "$SESSION:{end}"
	tmux attach -t "$SESSION"
}

ensure_remote_session() {
	# Clean up legacy session name if it exists.
	tmux kill-session -t phone 2>/dev/null || true

	if ! tmux has-session -t "$SESSION" 2>/dev/null; then
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

color_for_verdict() {
	case "$1" in
	B) printf '\033[31m' ;;
	W) printf '\033[33m' ;;
	U) printf '\033[32m' ;;
	R) printf '\033[2;32m' ;;
	*) printf '\033[37m' ;;
	esac
}

list_cc_panes() {
	# Scoped to the default session, not -a: once the remote session exists it is grouped with
	# default (shares its windows), and -a would walk every session's view of those same windows,
	# listing each pane twice.
	tmux list-panes -s -t default -F '#{pane_id}|#{window_id}|#{window_name}|#{E:@claude-pane-verdict}' 2>/dev/null |
		while IFS='|' read -r pane_id window_id window_name verdict; do
			[ -n "$verdict" ] || continue
			printf '%s|%s|%s|%s\n' "$pane_id" "$window_id" "$window_name" "$verdict"
		done
}

render_picker() {
	local reset=$'\033[0m'
	printf '\033[2J\033[H'
	printf '\033[1m  Claude Code Sessions\033[0m\n\n'

	local index=0
	while IFS='|' read -r _pane_id _window_id window_name verdict; do
		index=$((index + 1))
		local color
		color="$(color_for_verdict "$verdict")"
		printf '  %s│ %s●%s %s\n' "$index" "$color" "$reset" "$window_name"
	done

	if [ "$index" -eq 0 ]; then
		printf '  \033[2mNo cc sessions running. Waiting...\033[0m\n'
	fi

	printf '\n  \033[2mTap a session or type its number.  \033[4mN\033[24mew  \033[4mQ\033[24muit\033[0m\n'
	return "$index"
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
		local entries=()
		while IFS= read -r line; do
			entries+=("$line")
		done < <(list_cc_panes)

		local count="${#entries[@]}"

		# Two gotchas: printf reuses its format at least once even with zero arguments, so a
		# zero-element array would still send render_picker one blank line and render a phantom row;
		# and render_picker reports its count through its exit status, which set -e treats as a
		# failure for any nonzero count.
		local rendered_count=0
		if [ "$count" -eq 0 ]; then
			render_picker </dev/null || rendered_count=$?
		else
			render_picker < <(printf '%s\n' "${entries[@]}") || rendered_count=$?
		fi

		local timeout=3
		if [ "$rendered_count" -gt 0 ]; then
			timeout=10
		fi

		local selection=""
		printf '\033[?1000h\033[?1006h'
		if read -rsn1 -t "$timeout" selection; then
			printf '\033[?1000l\033[?1006l'
			case "$selection" in
			[1-9])
				local idx=$((selection - 1))
				if [ "$idx" -lt "$count" ]; then
					local entry="${entries[$idx]}"
					local pane_id window_id
					IFS='|' read -r pane_id window_id _ _ <<<"$entry"
					select_and_attach "$pane_id" "$window_id"
				fi
				;;
			$'\033')
				local seq=""
				while IFS= read -rsn1 -t 0.1 ch; do
					seq="${seq}${ch}"
					[[ "$ch" == [Mm] ]] && break
				done
				if [[ "$seq" =~ ^\[.?([0-9]+)\;([0-9]+)\;([0-9]+)[Mm]$ ]] && [ "${BASH_REMATCH[1]}" -eq 0 ]; then
					local row="${BASH_REMATCH[3]}"
					local idx=$((row - 3))
					if [ "$idx" -ge 0 ] && [ "$idx" -lt "$count" ]; then
						local entry="${entries[$idx]}"
						local pane_id window_id
						IFS='|' read -r pane_id window_id _ _ <<<"$entry"
						select_and_attach "$pane_id" "$window_id"
					fi
				fi
				;;
			n)
				new_session_flow
				;;
			q)
				exit 0
				;;
			esac
		fi
		printf '\033[?1000l\033[?1006l'
	done
}

main

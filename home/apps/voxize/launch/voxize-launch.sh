# Super+S: voxize-tui in a tmux floating pane over the focused pane when Ghostty with tmux has focus, otherwise the Voxize window.
# Design and evidence: docs/superpowers/specs/2026-11-04-voxize-tmux-launcher-design.md

# The card's cap, copied from CardView's max-width and max-height in Voxize's src/voxize/tui/tui.tcss.
card_width=88
card_height=24

# Amber, in the family of the other pop-up tints (tig's magenta, the scratch note's teal).
# Voxize paints every cell itself, so the tint is its own setting (VOXIZE_TUI_BACKGROUND, from 0.3.1); a tmux pane style never shows.
tui_background='#100b06'

fall_back() {
	echo "voxize-launch: $1; opening the Voxize window" >&2
	return 1
}

# The process behind the focused window, from the Window Calls extension (the same call Voxize's own context detection makes).
focused_window_pid() {
	busctl --user -j call org.gnome.Shell /org/gnome/Shell/Extensions/Windows org.gnome.Shell.Extensions.Windows List |
		jq -r '.data[0] | fromjson | .[] | select(.focus == true) | .pid'
}

# Succeeds when process $1 is process $2 or one of its descendants.
descends_from() {
	local pid="$1" ancestor_pid="$2"
	while [[ -n "$pid" && "$pid" -gt 1 ]]; do
		if [[ "$pid" == "$ancestor_pid" ]]; then
			return 0
		fi
		pid=$(awk '/^PPid:/ { print $2 }' "/proc/$pid/status" 2>/dev/null) || return 1
	done
	return 1
}

# One axis of the floating pane, printed as "size offset", in window coordinates of its content.
# The border is drawn one cell outside the content, so a pane fits the whole card only with two cells to spare; a smaller pane is
# covered exactly, its border landing on the neighbouring borders or off-screen.
fit_axis() {
	local cap="$1" pane_size="$2" pane_offset="$3"
	if ((pane_size >= cap + 2)); then
		echo "$cap $((pane_offset + (pane_size - cap) / 2))"
	else
		echo "$pane_size $pane_offset"
	fi
}

launch() {
	local window_pid command_line
	window_pid=$(focused_window_pid) || fall_back "no answer from GNOME about the focused window" || return
	[[ "$window_pid" =~ ^[0-9]+$ ]] || fall_back "no focused window" || return
	command_line=$(tr '\0' ' ' <"/proc/$window_pid/cmdline") || fall_back "cannot read the focused window's command line" || return
	# The test Voxize's context detection uses for Ghostty with tmux.
	[[ "$command_line" == */ghostty* && "$command_line" == */tmux* ]] || fall_back "the focused window is not Ghostty with tmux" || return

	# tmux flags the client whose terminal reported focus last (focus-events is on). The ancestry test drops a client that kept the
	# flag from attach without ever reporting focus, such as one over SSH.
	local flags client_pid pane_id target_pane_id="" match_count=0
	while read -r flags client_pid pane_id; do
		if [[ ",$flags," == *,focused,* ]] && descends_from "$client_pid" "$window_pid"; then
			target_pane_id="$pane_id"
			match_count=$((match_count + 1))
		fi
	done < <(tmux list-clients -F '#{client_flags} #{client_pid} #{pane_id}')
	((match_count == 1)) || fall_back "found $match_count focused tmux clients in the focused window" || return

	local window_id="" pane_left pane_top pane_width pane_height pane_path
	read -r window_id pane_left pane_top pane_width pane_height pane_path < <(
		tmux display-message -p -t "$target_pane_id" '#{window_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height} #{pane_current_path}'
	)
	[[ -n "$window_id" ]] || fall_back "cannot read pane $target_pane_id" || return

	local existing_pane_id=""
	read -r existing_pane_id < <(tmux list-panes -t "$window_id" -f '#{@voxize}' -F '#{pane_id}')
	if [[ -n "$existing_pane_id" ]]; then
		tmux select-pane -t "$existing_pane_id" || fall_back "cannot focus pane $existing_pane_id" || return
		return 0
	fi

	local width x height y
	read -r width x < <(fit_axis "$card_width" "$pane_width" "$pane_left")
	read -r height y < <(fit_axis "$card_height" "$pane_height" "$pane_top")
	# voxize-tui reads WHISPER.txt from the directory it starts in.
	local directory_arguments=()
	if [[ -n "$pane_path" ]]; then
		directory_arguments=(-c "$pane_path")
	fi
	local voxize_tui_path new_pane_id
	voxize_tui_path=$(command -v voxize-tui) || fall_back "voxize-tui is not on PATH" || return
	# new-pane takes the box with its border (tmux 3.8), one cell beyond the content on every side.
	new_pane_id=$(
		tmux new-pane -t "$target_pane_id" -x "$((width + 2))" -y "$((height + 2))" -X "$((x - 1))" -Y "$((y - 1))" "${directory_arguments[@]}" \
			-e "VOXIZE_TUI_BACKGROUND=$tui_background" -P -F '#{pane_id}' "$voxize_tui_path"
	) || fall_back "tmux new-pane failed" || return
	# A missing tag only costs the second press its focus-the-open-one shortcut, so it never opens the window as well.
	tmux set-option -p -t "$new_pane_id" @voxize 1 || true
	# The border title, drawn by pane-border-format in home/apps/tmux/tmux.conf; voxize-tui sets none, so the hostname would show.
	tmux set-option -p -t "$new_pane_id" @float-title-bold voxize \; \
		set-option -p -t "$new_pane_id" @float-title-rest "${pane_path/#"$HOME"/\~}" || true
}

launch || exec voxize

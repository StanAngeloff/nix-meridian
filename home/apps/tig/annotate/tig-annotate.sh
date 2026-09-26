cmd_add() {
	local git_dir="$1"
	shift

	# tig-annotate-store owns the store: it validates the anchor, records the sidecar, and names the note.
	local prepared
	if ! prepared=$(tig-annotate-store prepare "$git_dir" "$@"); then
		printf '%s\n' "$prepared"
		return 0
	fi
	local note_file popup_title
	{
		read -r note_file
		read -r popup_title
	} <<<"$prepared"

	local popup_height=6 popup_x=0 popup_y popup_w
	if [ -f "$note_file" ] && grep -q '[^[:space:]]' "$note_file"; then
		local line_count
		line_count=$(wc -l <"$note_file")
		popup_height=$((line_count + 3))
		if [ "$popup_height" -lt 6 ]; then
			popup_height=6
		elif [ "$popup_height" -gt 20 ]; then
			popup_height=20
		fi
	fi
	local tmux_client tmux_target
	tmux_client=$(tmux display-message -p '#{client_name}')
	tmux_target=$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}')

	local pane_height pane_width
	pane_height=$(tmux display-message -p '#{pane_height}')
	pane_width=$(tmux display-message -p '#{pane_width}')

	local capture_plain capture_ansi
	capture_plain=$(tmux capture-pane -t "$tmux_target" -p)
	capture_ansi=$(tmux capture-pane -t "$tmux_target" -e -p)

	# Detect split view by checking for the panel separator (│).
	local sep_col
	sep_col=$(echo "$capture_plain" | awk '/│/ {print index($0, "│") - 1; exit}')

	if [ -n "$sep_col" ] && [ "$sep_col" -gt 0 ]; then
		popup_x=$((sep_col + 1))
		popup_w=$((pane_width - sep_col - 1))
	else
		popup_w=$pane_width
	fi

	# Find the cursor line: scan for the cursor background color (48;5;34m)
	# and pick the line where it starts furthest to the right. In split view
	# the right-panel cursor starts at a higher column than the left-panel one.
	local cursor_y
	cursor_y=$(echo "$capture_ansi" | python3 -c "
import sys, re
ansi = re.compile(r'\033\[([0-9;]*)m')
best_x1, best_row = -1, 0
for row, line in enumerate(sys.stdin, 1):
    line = line.rstrip('\n')
    bg34, col, x1 = False, 0, None
    i = 0
    while i < len(line):
        m = ansi.match(line, i)
        if m:
            params = m.group(1).split(';')
            for j in range(len(params)-2):
                if params[j]=='48' and params[j+1]=='5' and params[j+2]=='34':
                    bg34 = True
                    if x1 is None: x1 = col
            if '0' in params or '49' in params:
                bg34 = False
            i = m.end()
        else:
            col += 1
            i += 1
    if x1 is not None and x1 > best_x1:
        best_x1 = x1
        best_row = row
print(best_row)
")

	# tmux -y is the BOTTOM edge of the popup (source: cmd-display-menu.c
	# "This is the bottom-left position"), so add popup_height to place the
	# top edge one row below the cursor.
	if [ -n "$cursor_y" ] && [ "$cursor_y" -gt 0 ]; then
		popup_y=$((cursor_y + popup_height))
		if [ "$popup_y" -gt "$pane_height" ]; then
			popup_y=$((cursor_y - 1))
		fi
	else
		popup_y=$((pane_height / 2 + popup_height / 2))
	fi

	local self
	self=$(realpath "$0")

	# -T is a tmux format, so "#" in a file name is doubled to stay literal. A command given as separate arguments
	# runs without a shell, so quotes in the note path stay literal too.
	tmux display-popup -EE \
		-c "$tmux_client" \
		-t "$tmux_target" \
		-T " ${popup_title//\#/##} " \
		-x "$popup_x" \
		-y "$popup_y" \
		-w "$popup_w" -h "$popup_height" \
		-b heavy \
		-s 'bg=#081018' \
		-S 'bg=#081018,fg=#6f9f9f' \
		"$self" _edit_note "$note_file"

	tig-annotate-store settle "$note_file"
}

cmd_copy() {
	tig-annotate-store copy "$1"
}

cmd_list() {
	local git_dir="$1"

	if [ -z "$(tig-annotate-store entries "$git_dir")" ]; then
		echo "No annotations"
		return 0
	fi

	local self
	self=$(realpath "$0")
	local tmux_client tmux_target
	tmux_client=$(tmux display-message -p '#{client_name}')
	tmux_target=$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}')

	# tig passes a relative ".git" at the top level, and a popup would start in the session's start directory:
	# start it here, so the store it lists and the working tree it compares against are this repository's.
	# -d is a tmux format, hence the doubled "#".
	tmux display-popup -EE \
		-c "$tmux_client" \
		-t "$tmux_target" \
		-d "${PWD//\#/##}" \
		-T ' annotations ' \
		-xC -yC -w 80% -h 80% \
		-b heavy \
		-s 'bg=#081018' \
		-S 'bg=#081018,fg=#6f9f9f' \
		"$self" _fzf_list "$git_dir"
}

cmd_fzf_list() {
	local git_dir="$1"
	local self
	self=$(realpath "$0")

	# fzf ends an action at ")+" or ")," however the text is quoted, so the directory reaches the reload through
	# the environment, expanded by fzf's action shell, and the action text stays constant.
	local selected
	# shellcheck disable=SC2016
	selected=$(
		tig-annotate-store entries "$git_dir" | TIG_ANNOTATE_GIT_DIR=$git_dir fzf \
			--multi \
			--ansi \
			--delimiter=$'\t' \
			--with-nth=2 \
			--preview='cat {1}' \
			--header='Enter: copy | C-e: edit | C-t: trash | C-a: all | Esc: close' \
			--bind 'ctrl-a:select-all' \
			--bind 'ctrl-t:execute-silent(tig-annotate-store trash {+1})+reload(tig-annotate-store entries "$TIG_ANNOTATE_GIT_DIR")' \
			--bind "ctrl-e:execute($self _edit_note {1})"
	) || true

	[ -z "$selected" ] && return 0

	local note_files=() note_file
	while IFS=$'\t' read -r note_file _; do
		note_files+=("$note_file")
	done <<<"$selected"

	local summary
	summary=$(tig-annotate-store copy "$git_dir" "${note_files[@]}")
	notify-send \
		--app-name=tig-annotate \
		--icon=edit-copy \
		--category=transfer.complete \
		--urgency=low \
		--transient \
		"tig-annotate" \
		"$summary"
}

cmd_edit_note() {
	exec popup-nvim "$1"
}

case "${1:-}" in
add)
	shift
	cmd_add "$@"
	;;
copy)
	shift
	cmd_copy "$@"
	;;
list)
	shift
	cmd_list "$@"
	;;
_fzf_list)
	shift
	cmd_fzf_list "$@"
	;;
_edit_note)
	shift
	cmd_edit_note "$@"
	;;
*)
	echo "Usage: tig-annotate {add|copy|list} <git-dir> [args...]"
	exit 1
	;;
esac

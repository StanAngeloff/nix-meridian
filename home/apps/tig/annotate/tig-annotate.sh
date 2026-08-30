resolve_git_dir() {
	local git_dir="$1"
	if [ -f "$git_dir" ]; then
		local target
		target=$(sed -n 's/^gitdir: //p' "$git_dir")
		if [[ "$target" != /* ]]; then
			target="$(cd "$(dirname "$git_dir")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
		fi
		git_dir="$target"
	fi
	if [[ "$git_dir" != /* ]]; then
		git_dir="$(cd "$(dirname "$git_dir")" && pwd)/$(basename "$git_dir")"
	fi
	printf '%s' "$git_dir"
}

encode_path() {
	printf '%s' "$1" | sed 's|/|·|g'
}

decode_path() {
	printf '%s' "$1" | sed 's|·|/|g'
}

notes_path() {
	printf '%s/tig-annotate' "$(resolve_git_dir "$1")"
}

note_filename() {
	printf '%s:%s.md' "$(encode_path "$1")" "$2"
}

cmd_add() {
	local git_dir="$1" file="$2" lineno="${3:-0}" lineno_old="${4:-0}"

	local effective_lineno="$lineno"
	if [ "$effective_lineno" = "0" ]; then
		effective_lineno="$lineno_old"
	fi
	if [ "$effective_lineno" = "0" ]; then
		effective_lineno="file"
	fi

	local annotations_path
	annotations_path=$(notes_path "$git_dir")
	mkdir -p "$annotations_path"

	local note_file
	note_file="$annotations_path/$(note_filename "$file" "$effective_lineno")"

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

	tmux display-popup -EE \
		-c "$tmux_client" \
		-t "$tmux_target" \
		-T " $file:$effective_lineno " \
		-x "$popup_x" \
		-y "$popup_y" \
		-w "$popup_w" -h "$popup_height" \
		-b heavy \
		-s 'bg=#081018' \
		-S 'bg=#081018,fg=#6f9f9f' \
		"'$self' _edit_note '$note_file'"

	if [ -f "$note_file" ] && ! grep -q '[^[:space:]]' "$note_file"; then
		rm -f "$note_file"
	elif [ -f "$note_file" ]; then
		echo "Annotated: $file:$effective_lineno"
	fi
}

cmd_copy() {
	local git_dir="$1"
	local annotations_path
	annotations_path=$(notes_path "$git_dir")

	if [ ! -d "$annotations_path" ] || [ -z "$(ls -A "$annotations_path" 2>/dev/null)" ]; then
		echo "No annotations to copy"
		return 0
	fi

	local output="" count=0
	for note_file in "$annotations_path"/*.md; do
		[ -f "$note_file" ] || continue
		grep -q '[^[:space:]]' "$note_file" || continue
		local base
		base=$(basename "$note_file" .md)
		local encoded_path="${base%:*}"
		local lineno="${base##*:}"
		local file_path
		file_path=$(decode_path "$encoded_path")
		local content
		content=$(cat "$note_file")

		if [ $count -gt 0 ]; then
			output+=$'\n\n---\n\n'
		fi
		output+="> $file_path:$lineno"$'\n'"$content"
		count=$((count + 1))
	done

	printf '%s\n' "$output" | wl-copy >/dev/null 2>&1
	echo "Copied $count annotation(s) to clipboard"
}

cmd_list() {
	local git_dir="$1"
	local annotations_path
	annotations_path=$(notes_path "$git_dir")

	if [ ! -d "$annotations_path" ] || [ -z "$(ls -A "$annotations_path" 2>/dev/null)" ]; then
		echo "No annotations"
		return 0
	fi

	local self
	self=$(realpath "$0")

	tmux display-popup -EE \
		-T ' annotations ' \
		-xC -yC -w 80% -h 80% \
		-b heavy \
		-s 'bg=#081018' \
		-S 'bg=#081018,fg=#6f9f9f' \
		"'$self' _fzf_list '$annotations_path' '$git_dir'"
}

cmd_fzf_list() {
	local annotations_path="$1" git_dir="$2"
	local self
	self=$(realpath "$0")

	local selected
	selected=$(
		"$self" _build_entries "$annotations_path" | fzf \
			--multi \
			--ansi \
			--delimiter=$'\t' \
			--with-nth=2 \
			--preview='cat {1}' \
			--header='Enter: copy | C-e: edit | C-t: trash | C-a: all | Esc: close' \
			--bind 'ctrl-a:select-all' \
			--bind "ctrl-t:execute-silent(gio trash {+1})+reload($self _build_entries $annotations_path)" \
			--bind "ctrl-e:execute($self _edit_note {1})"
	) || true

	[ -z "$selected" ] && return 0

	local output="" count=0
	while IFS=$'\t' read -r note_file _rest; do
		[ -f "$note_file" ] || continue
		local base
		base=$(basename "$note_file" .md)
		local encoded_path="${base%:*}"
		local lineno="${base##*:}"
		local file_path
		file_path=$(decode_path "$encoded_path")
		local content
		content=$(cat "$note_file")
		[ $count -gt 0 ] && output+=$'\n\n---\n\n'
		output+="> $file_path:$lineno"$'\n'"$content"
		count=$((count + 1))
	done <<<"$selected"

	printf '%s\n' "$output" | wl-copy >/dev/null 2>&1
	notify-send \
		--app-name=tig-annotate \
		--icon=edit-copy \
		--category=transfer.complete \
		--urgency=low \
		--transient \
		"Copied $count annotation(s)" \
		"$count annotation(s) copied to clipboard"
}

cmd_build_entries() {
	local annotations_path="$1"
	for note_file in "$annotations_path"/*.md; do
		[ -f "$note_file" ] || continue
		grep -q '[^[:space:]]' "$note_file" || continue
		local base
		base=$(basename "$note_file" .md)
		local encoded_path="${base%:*}"
		local lineno="${base##*:}"
		local file_path
		file_path=$(decode_path "$encoded_path")
		local first_line
		first_line=$(head -1 "$note_file")
		printf '%s\t%s:%s — %s\n' "$note_file" "$file_path" "$lineno" "$first_line"
	done
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
_build_entries)
	shift
	cmd_build_entries "$@"
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

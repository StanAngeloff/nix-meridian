# prefix C-n for pane $1 on client $2: its scratch note, in a floating pane where the note popup used to be.
# Inside tig the note belongs to the pane tig was opened from. A second press focuses the open note instead of opening another.
pressed_pane_id="$1"
client_name="$2"
# shellcheck source=/dev/null
source @popupBox@
require_floating_panes

window_id=$(tmux display-message -p -t "$pressed_pane_id" '#{window_id}')
note_pane_id=$(tmux display-message -p -t "$pressed_pane_id" '#{?@tig,#{@caller-pane-id},#{pane_id}}')
note_pane_pid=$(tmux display-message -p -t "$note_pane_id" '#{pane_pid}')
# Keyed by pane ID and the PID of its first process, so a pane ID reused after a tmux restart never finds an old note.
note_file="$HOME/.cache/tmux-scratch-notes/$note_pane_id-$note_pane_pid.md"

open_note_float_id=$(tmux list-panes -t "$window_id" -f "#{==:#{@note-for},$note_pane_id}" -F '#{pane_id}' | head -n 1)
if [[ -n "$open_note_float_id" ]]; then
	tmux select-pane -t "$open_note_float_id"
	exit 0
fi

read -r width height x y < <(popup_box "$client_name" 70 60)
note_float_id=$(
	tmux new-pane -t "$pressed_pane_id" -x "$width" -y "$height" -X "$x" -Y "$y" -B heavy -T 'scratch note' \
		-s 'bg=#081018' -S 'bg=#081018,fg=#6f9f9f' -R 'bg=#081018,fg=#6f9f9f' -P -F '#{pane_id}' \
		@scratchNote@ "$note_file"
)
# The border title names the file the note saves to.
tmux set -p -t "$note_float_id" @note-for "$note_pane_id" \; set -p -t "$note_float_id" @float-title-bold 'scratch note' \; \
	set -p -t "$note_float_id" @float-title-rest "${note_file/#"$HOME"/\~}"

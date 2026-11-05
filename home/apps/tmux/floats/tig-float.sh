# prefix C-g for window $1, pressed from pane $2 on client $3; one tig per window.
# No tig in the window: open one where the tig popup used to be. tig open: shade it to a strip in the top-right corner. tig shaded: bring it back.
window_id="$1"
pressed_pane_id="$2"
client_name="$3"
# shellcheck source=/dev/null
source @popupBox@
require_floating_panes

# The magenta of the tig popup.
tig_background='#100610'
tig_border='bg=#100610,fg=#8f6f8f'

tig_pane_id=$(tmux list-panes -t "$window_id" -f '#{@tig}' -F '#{pane_id}' | head -n 1)
read -r width height x y < <(popup_box "$client_name" 90 90)

if [[ -z "$tig_pane_id" ]]; then
	tig_path=$(tmux display-message -p -t "$pressed_pane_id" '#{?@tig_path,#{@tig_path},#{pane_current_path}}')
	# The home directory as ~, so the title still fits the shaded strip.
	tig_title_path="${tig_path/#"$HOME"/\~}"
	# Open on the first unstaged file, below the staged ones; the pane's shell expands the command.
	# shellcheck disable=SC2016
	tig_pane_id=$(
		tmux new-pane -t "$pressed_pane_id" -x "$width" -y "$height" -X "$x" -Y "$y" -c "$tig_path" -T "tig $tig_title_path" \
			-s "bg=$tig_background" -S "$tig_border" -R "$tig_border" -P -F '#{pane_id}' \
			'tig status +$(expr 4 + $(git diff --staged --name-only | wc -l))'
	)
	# The border title, drawn by pane-border-format in tmux.conf.
	tmux set -p -t "$tig_pane_id" @tig 1 \; set -p -t "$tig_pane_id" @caller-pane-id "$pressed_pane_id" \; \
		set -p -t "$tig_pane_id" @float-title-bold tig \; set -p -t "$tig_pane_id" @float-title-rest "$tig_title_path"
elif [[ -n "$(tmux display-message -p -t "$tig_pane_id" '#{@tig-shaded}')" ]]; then
	tmux resize-pane -t "$tig_pane_id" -x "$width" -y "$height" \; move-pane -t "$tig_pane_id" -X "$x" -Y "$y" \; \
		set -pu -t "$tig_pane_id" @tig-shaded \; select-pane -t "$tig_pane_id"
else
	tmux resize-pane -t "$tig_pane_id" -x 30 -y 1 \; move-pane -t "$tig_pane_id" -P top-right \; \
		set -p -t "$tig_pane_id" @tig-shaded 1
	# Focus returns to the pane tig was opened from, or the previous pane when that one has closed.
	caller_pane_id=$(tmux display-message -p -t "$tig_pane_id" '#{@caller-pane-id}')
	tmux select-pane -t "$caller_pane_id" 2>/dev/null || tmux last-pane -t "$window_id"
fi

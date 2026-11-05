# prefix G for window $1, pressed from pane $2 on client $3: pick the directory tig opens in, in a floating pane where its popup used to be.
# Inside tig it picks for the pane tig was opened from. A pick closes the window's tig, so the next prefix C-g opens it there.
# The picker pane runs this script again as: --pick <window> <pane>.
# shellcheck source=/dev/null
source @popupBox@

if [[ "$1" == --pick ]]; then
	window_id="$2"
	pane_id="$3"
	# The current choice comes first, then every directory up to three levels down; "." clears the choice.
	current_path=$(tmux display-message -p -t "$pane_id" '#{@tig_path}')
	current_relative=$(realpath --relative-to=. "$current_path" 2>/dev/null || true)
	candidates=$(
		if [[ -n "$current_relative" && -d "./$current_relative" ]]; then
			echo "./$current_relative"
		fi
		find . -maxdepth 3 -type d -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | sort |
			{ if [[ -n "$current_relative" ]]; then grep -xvF "./$current_relative" || true; else cat; fi; } || true
	)
	new_path=$(fzf <<<"$candidates") || exit 1
	if [[ "$new_path" == . ]]; then
		tmux set-option -pu -t "$pane_id" @tig_path
	else
		tmux set-option -p -t "$pane_id" @tig_path "$(realpath "$new_path")"
	fi
	tig_pane_id=$(tmux list-panes -t "$window_id" -f '#{@tig}' -F '#{pane_id}' | head -n 1)
	if [[ -n "$tig_pane_id" ]]; then
		tmux kill-pane -t "$tig_pane_id"
	fi
	exit 0
fi

window_id="$1"
pressed_pane_id="$2"
client_name="$3"
require_floating_panes

# One picker per window: a second press focuses the open one.
picker_pane_id=$(tmux list-panes -t "$window_id" -f '#{@tig-path-picker}' -F '#{pane_id}' | head -n 1)
if [[ -n "$picker_pane_id" ]]; then
	tmux select-pane -t "$picker_pane_id"
	exit 0
fi

pane_id=$(tmux display-message -p -t "$pressed_pane_id" '#{?@tig,#{@caller-pane-id},#{pane_id}}')
pane_path=$(tmux display-message -p -t "$pane_id" '#{pane_current_path}')
read -r width height x y < <(popup_box "$client_name" 60 60)
picker_pane_id=$(
	tmux new-pane -t "$pressed_pane_id" -x "$width" -y "$height" -X "$x" -Y "$y" -c "$pane_path" -T "tig path" \
		-s 'bg=#100610' -S 'bg=#100610,fg=#8f6f8f' -R 'bg=#100610,fg=#8f6f8f' -P -F '#{pane_id}' \
		"$(realpath "$0")" --pick "$window_id" "$pane_id"
)
tmux set -p -t "$picker_pane_id" @tig-path-picker 1 \; \
	set -p -t "$picker_pane_id" @float-title-bold 'tig path' \; set -p -t "$picker_pane_id" @float-title-rest "${pane_path/#"$HOME"/\~}"

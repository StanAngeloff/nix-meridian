# prefix C-i (or prefix I) for window $1, pressed from pane $2; one issue board per window.
# A board in the window closes. No board: open one in a split to the right, on the journal the window is named after.
window_id="$1"
pressed_pane_id="$2"

board_pane_id=$(tmux list-panes -t "$window_id" -f '#{@issues-board}' -F '#{pane_id}' | head -n 1)
if [[ -n "$board_pane_id" ]]; then
	tmux kill-pane -t "$board_pane_id"
	exit 0
fi

# The board is the stans-additions plugin's, in the ccc checkout beside the pane's main clone; a worktree resolves to its main clone.
pane_path=$(tmux display-message -p -t "$pressed_pane_id" '#{pane_current_path}')
if ! git_common_path=$(git -C "$pane_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
	tmux display-message "No issue board: $pane_path is not in a git repository"
	exit 0
fi
board_script_path="$(dirname "$(dirname "$git_common_path")")/ccc/plugins/stans-additions/contrib/issues/issues.mjs"
if [[ ! -f "$board_script_path" ]]; then
	tmux display-message "No issue board: $board_script_path is missing"
	exit 0
fi

# cc names a window <repository>@<session>[<keyword>] (claude-code/initialize.zsh), and a rename by hand may add " [keyword]".
# The board finds the journal from the session part, and shows every journal when none matches.
board_command=(@issuesBoard@ "$board_script_path" board)
window_name=$(tmux display-message -p -t "$window_id" '#{window_name}')
if [[ "$window_name" == *@* ]]; then
	window_session="${window_name#*@}"
	window_session="${window_session%%\[*}"
	window_session="${window_session%% *}"
	if [[ -n "$window_session" ]]; then board_command+=(--find-journal "$window_session"); fi
fi

# A board that fails keeps its pane open with the error until Enter, as the /issues skill's split does.
board_pane_id=$(
	tmux split-window -h -l 45% -t "$pressed_pane_id" -P -F '#{pane_id}' \
		"${board_command[*]@Q} || { printf '\nThe board stopped. Press Enter to close this pane.'; read -r _; }"
)
tmux set -p -t "$board_pane_id" @issues-board 1

# shellcheck shell=bash
# Sourced by the floating pane scripts beside it.

# Floating panes move and resize from tmux 3.8 on; on an older server resize-pane would scramble the tiled panes underneath.
# A switch leaves the running server on its old version until it restarts, so this says so instead of acting.
require_floating_panes() {
	local version
	version=$(tmux display-message -p '#{version}')
	if [[ "$version" =~ ^([0-9]+)\.([0-9]+) ]] && ((BASH_REMATCH[1] * 100 + BASH_REMATCH[2] < 308)); then
		tmux display-message "tmux $version is still running; floating panes need 3.8, so restart the tmux server"
		exit 0
	fi
}

# Prints "width height x y" for client $1: the box display-popup -xC -yC -w $2% -h $3% draws, border included, in window coordinates.
# These are display-popup's own rules (cmd-display-menu.c): a share of the whole terminal, status line included, centred with its rounding.
# new-pane, resize-pane and move-pane place the same border-inclusive box, so a floating pane covers exactly what the popup did.
popup_box() {
	local client_name="$1" width_percent="$2" height_percent="$3"
	local client_width client_height status status_position status_lines window_top width height x y bottom
	read -r client_width client_height status status_position < <(
		tmux display-message -p -c "$client_name" '#{client_width} #{client_height} #{status} #{status-position}'
	)
	case "$status" in
	off) status_lines=0 ;;
	on) status_lines=1 ;;
	*) status_lines="$status" ;;
	esac
	window_top=0
	if [[ "$status_position" == top ]]; then
		window_top="$status_lines"
	fi

	width=$((client_width * width_percent / 100))
	height=$((client_height * height_percent / 100))
	x=$(((client_width - 1) / 2 - width / 2))
	if ((x + width >= client_width)); then
		x=$((client_width - width))
	elif ((x < 0)); then
		x=0
	fi
	# display-popup centres on the bottom edge and derives the top from it.
	bottom=$(((client_height - 1) / 2 + height / 2))
	if ((bottom >= client_height)); then
		bottom=$((client_height - height))
	fi
	if ((bottom < height)); then
		y=0
	else
		y=$((bottom - height))
	fi
	if ((y + height >= client_height)); then
		y=$((client_height - height))
	fi
	y=$((y - window_top))
	if ((y < 0)); then
		y=0
	fi
	echo "$width $height $x $y"
}

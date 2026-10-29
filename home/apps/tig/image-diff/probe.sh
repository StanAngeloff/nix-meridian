#!/usr/bin/env bash
# Drives a patched tig in a private tmux server and checks the stage view's image diffs:
# what tig draws, the graphics commands it writes to the terminal, and the helper's cache.
# Development tool for image-diff.patch; not installed.
#
# Usage: probe.sh <tig binary> <tig-image-diff helper>
# Build them with: nix build .#nixosConfigurations.stan-latitude.pkgs.tig --no-link --print-out-paths
# and use home/apps/tig/image-diff/helper.py through a wrapper, or the tig-image-diff the configuration installs.
set -euo pipefail

if [ $# -ne 2 ] || [ ! -x "$1" ] || [ ! -e "$2" ]; then
	echo "Usage: probe.sh <tig binary> <tig-image-diff helper>" >&2
	exit 2
fi

tig_binary=$(realpath "$1")
helper_path=$(realpath "$2")
work_path=$(mktemp -d "${TMPDIR:-/tmp}/tig-image-diff-probe.XXXXXX")
repository_path="$work_path/repository"
socket_path="$work_path/tmux.sock"
# script records tig's raw output; tmux's pipe-pane drops passthrough sequences.
output_path="$work_path/output.bin"
# The popup checks run on a server of their own, shown by an outer client in a container whose bytes script records.
popup_socket_path="$work_path/popup.sock"
container_socket_path="$work_path/container.sock"
outer_path="$work_path/outer.bin"
failure_count=0

cleanup() {
	tmux -S "$socket_path" kill-server 2>/dev/null || true
	tmux -S "$popup_socket_path" kill-server 2>/dev/null || true
	tmux -S "$container_socket_path" kill-server 2>/dev/null || true
	rm -rf "$work_path"
}
trap cleanup EXIT

check() {
	local description=$1
	shift
	if "$@"; then
		echo "ok   $description"
	else
		echo "FAIL $description"
		failure_count=$((failure_count + 1))
	fi
}

pane() {
	tmux -S "$socket_path" capture-pane -p -t 0
}

# Waits until the pane shows the pattern; script appends to the output file whenever tig draws.
wait_for_pane() {
	for _ in $(seq 40); do
		pane | grep -q -- "$1" && return 0
		inotifywait -qq -t 3 -e modify "$output_path" || true
	done
	return 1
}

wait_for_output() {
	for _ in $(seq 40); do
		grep -aq -- "$1" "$output_path" && return 0
		inotifywait -qq -t 3 -e modify "$output_path" || true
	done
	return 1
}

graphics_commands() {
	grep -ao $'\ePtmux;\e\e_G[^;\e]*' "$output_path" | sed 's/^.*_G//' || true
}

# Bounded: at most 30 tries of up to a second each, woken early when the outer terminal receives bytes.
wait_until() {
	for _ in $(seq 30); do
		"$@" && return 0
		inotifywait -qq -t 1 -e modify "$outer_path" 2>/dev/null || true
	done
	return 1
}

popup_server_has_client_on() {
	tmux -S "$popup_socket_path" list-clients -F '#{session_name}' 2>/dev/null | grep -qx "$1"
}

popup_server_pane_shows() {
	tmux -S "$popup_socket_path" capture-pane -p -t "$1" 2>/dev/null | grep -q -- "$2"
}

outer_terminal_received() {
	grep -aq -- "$1" "$outer_path"
}

open_file() {
	tmux -S "$socket_path" send-keys -t 0 q '/' "$1" Enter
	wait_for_pane "matches '"
	tmux -S "$socket_path" send-keys -t 0 Enter
}

git -C "$work_path" init -q repository
cd "$repository_path"
git config user.email test@example.com
git config user.name Test
git lfs install --local >/dev/null
git lfs track '*.png' >/dev/null
magick -size 400x300 gradient:navy-skyblue changed.png
magick -size 200x100 xc:white staged.png
git add .gitattributes changed.png staged.png
git commit -qm one
magick changed.png -fill orange -draw 'rectangle 50,50 120,100' changed.png
magick staged.png -fill black -draw 'rectangle 10,10 30,30' staged.png
git add staged.png
magick -size 64x64 xc:green untracked.png
head -c 4096 /dev/zero >untracked.bin

printf '#!/bin/sh\nexec python3 %s "$@"\n' "$helper_path" >"$work_path/helper"
[ "${helper_path##*.}" = py ] || printf '#!/bin/sh\nexec %s "$@"\n' "$helper_path" >"$work_path/helper"
chmod +x "$work_path/helper"
cat >"$work_path/tigrc" <<CONFIG
set image-diff-bin = $work_path/helper
bind stage [ move-prev-diff
bind stage ] move-next-diff
CONFIG
printf 'set -g default-terminal tmux-256color\nset -g allow-passthrough on\n' >"$work_path/tmux.conf"
: >"$output_path"
: >"$outer_path"

tmux -S "$socket_path" -f "$work_path/tmux.conf" new-session -d -x 120 -y 40 \
	"cd $repository_path; TIGRC_USER=$work_path/tigrc exec script -q -f -c '$tig_binary status' $output_path"
check "status view lists the files" wait_for_pane "changed.png"
tig_pid=$(pgrep -n -f "^$tig_binary status" || true)

tmux -S "$socket_path" send-keys -t 0 '/' 'changed\.png' Enter
wait_for_pane "matches '" || true
tmux -S "$socket_path" send-keys -t 0 Enter
check "unstaged Git LFS image shows both labels" wait_for_pane "old (index) .* new (working tree)"
check "status bar reports the changed share" wait_for_pane "3.02% of pixels changed · highlight 50%"
check "both panels are sent as virtual placements" \
	test "$(graphics_commands | grep -c '^a=T,U=1,q=2,f=32,t=f,s=400,v=300,')" -eq 2
check "image rows are placeholder cells in a 256-color foreground" \
	bash -c "tmux -S '$socket_path' capture-pane -p -e -t 0 | grep -a -A1 'old (index)' | tail -1 | grep -aq $'\e\\[38;5;[0-9]*m\xf4\x8e\xbb\xae'"

tmux -S "$socket_path" send-keys -t 0 ']'
check "] raises the highlight" wait_for_pane "highlight 60%"
tmux -S "$socket_path" send-keys -t 0 '[' '['
check "[ lowers it" wait_for_pane "highlight 40%"
check "each change re-sends only the new panel" test "$(graphics_commands | grep -c '^a=T')" -eq 5

open_file 'untracked\.png'
check "untracked image has one panel" wait_for_pane "new (untracked)"
check "untracked image is reported as new" wait_for_pane "new image, 64x64"
tmux -S "$socket_path" send-keys -t 0 ']'
check "] has nothing to highlight on a lone image" wait_for_pane "nothing to highlight"
tmux -S "$socket_path" send-keys -t 0 '/' 'zzz' Enter
check "searching walks the image rows" wait_for_pane "No match found"

open_file 'untracked\.bin'
check "a binary that is not an image hides its bytes" wait_for_pane "Binary file not shown"
check "and raises no error" bash -c "! tmux -S '$socket_path' capture-pane -p -t 0 | grep -q 'Image diff:'"

open_file 'staged\.png'
check "staged image compares HEAD with the index" wait_for_pane "old (HEAD) .* new (index)"
check "staged change share" wait_for_pane "2.21% of pixels changed"

tmux -S "$socket_path" resize-window -t 0 -x 90
check "a narrower window places the panels again" wait_for_output "a=p,U=1,q=2,i=[0-9]*,p=1,c=44,"

cache_path="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/tig-image-diff/$tig_pid"
check "the cache lives under the tig process id" test -n "$tig_pid" -a -d "$cache_path"
tmux -S "$socket_path" send-keys -t 0 Q Q
check "quitting deletes both images" wait_for_output "a=d,d=I,q=2,i=[0-9]*"$'\e'
for _ in $(seq 10); do
	[ -e "$cache_path" ] || break
	inotifywait -qq -t 1 -e delete_self "$cache_path" 2>/dev/null || true
done
check "quitting removes the cache" test ! -e "$cache_path"

# The tig popup binding shows a scratch session through a nested client inside a popup, so commands cross two tmux layers.
tmux -S "$popup_socket_path" -f "$work_path/tmux.conf" new-session -d -s main -x 200 -y 50
tmux -S "$popup_socket_path" new-session -d -s scratch -x 180 -y 45 \
	"cd $repository_path; TIGRC_USER=$work_path/tigrc exec $tig_binary status"
tmux -S "$container_socket_path" -f /dev/null new-session -d -x 200 -y 50 \
	"env -u TMUX script -q -f -c 'tmux -S $popup_socket_path attach -t main' $outer_path"
wait_until popup_server_has_client_on main || true
client_name=$(tmux -S "$popup_socket_path" list-clients -F '#{client_name}' | head -1)
tmux -S "$popup_socket_path" display-popup -c "$client_name" -E -w 190 -h 48 \
	"tmux -S $popup_socket_path attach-session -t scratch" &
wait_until popup_server_has_client_on scratch || true
popup_tig_pid=$(tmux -S "$popup_socket_path" display-message -p -t scratch:0 '#{pane_pid}')
wait_until popup_server_pane_shows scratch:0 "changed.png" || true
tmux -S "$popup_socket_path" send-keys -t scratch:0 '/' 'changed\.png' Enter
wait_until popup_server_pane_shows scratch:0 "matches '" || true
tmux -S "$popup_socket_path" send-keys -t scratch:0 Enter
check "a tig in a popup's nested client shows the image" wait_until popup_server_pane_shows scratch:0 "pixels changed"
check "and its graphics commands reach the terminal unwrapped" wait_until outer_terminal_received $'\e_Ga=T,U=1,q=2,'
check "with none left wrapped" bash -c "! grep -aq $'\ePtmux;' '$outer_path'"
# Quit before the server goes, so this tig removes its own cache.
popup_cache_path="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/tig-image-diff/$popup_tig_pid"
tmux -S "$popup_socket_path" send-keys -t scratch:0 Q Q
for _ in $(seq 10); do
	[ -e "$popup_cache_path" ] || break
	inotifywait -qq -t 1 -e delete_self "$popup_cache_path" 2>/dev/null || true
done
check "the popup's tig removes its cache on quitting" test ! -e "$popup_cache_path"

if [ "$failure_count" -gt 0 ]; then
	echo "$failure_count check(s) failed"
	exit 1
fi
echo "all checks passed"

#!/usr/bin/env bash
# Drives a patched tig in a private tmux server and checks what %(annotation) reports on each kind of diff line
# in the pager, diff and stage views, and that the ※ mark lands on the line a note is keyed to.
# Development tool for annotation-marks.patch; not installed.
#
# Usage: probe.sh <tig binary>
# Build one with: nix build .#nixosConfigurations.stan-latitude.pkgs.tig --no-link --print-out-paths
set -euo pipefail

if [ $# -ne 1 ] || [ ! -x "$1" ]; then
	echo "Usage: probe.sh <tig binary>" >&2
	exit 2
fi

tig_binary=$(realpath "$1")
work_path=$(mktemp -d "${TMPDIR:-/tmp}/tig-annotate-probe.XXXXXX")
repository_path="$work_path/repository"
records_path="$work_path/records"
socket_path=""
session_count=0
reference_mark=$'\xe2\x80\xbb'
failure_count=0

cleanup() {
	[ -z "$socket_path" ] || tmux -S "$socket_path" kill-server 2>/dev/null || true
	rm -rf "$work_path"
}
trap cleanup EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

git_quiet() {
	git -C "$repository_path" -c user.name=probe -c user.email=probe@example.invalid "$@" >/dev/null
}

drift() {
	{
		printf 'new1\nnew2\nnew3\n'
		seq -f 'line%g' 1 7
		seq -f 'line%g' 9 10
	} >"$1"
}

# Fixture: a commit whose diff shifts numbering (three lines added above a deleted line8), adds a tab-indented line,
# deletes a whole file and drops a trailing newline; plus the same shift left unstaged in stage.txt, and two files
# (one in a directory named c) that the last checks delete in the index.
mkdir -p "$repository_path/c" "$records_path"
git init -q "$repository_path"
seq -f 'line%g' 1 10 >"$repository_path/drift.txt"
seq -f 'line%g' 1 10 >"$repository_path/stage.txt"
printf 'alpha\n' >"$repository_path/tabbed.txt"
printf 'bye\n' >"$repository_path/gone.txt"
printf 'first\n' >"$repository_path/newline.txt"
printf 'farewell\n' >"$repository_path/staged-gone.txt"
printf 'inside c\n' >"$repository_path/c/staged-gone.txt"
git_quiet add -A
git_quiet commit -m 'base commit'
drift "$repository_path/drift.txt"
printf 'alpha\n\tindented tab\n' >"$repository_path/tabbed.txt"
printf 'first\nlast' >"$repository_path/newline.txt"
git_quiet rm -q gone.txt
git_quiet add -A
git_quiet commit -m 'drift commit'
drift "$repository_path/stage.txt"

# Each X press writes one numbered record: the annotation= line, then the text= line.
cat >"$work_path/dump" <<EOF
#!/bin/sh
record_count=\$(ls "$records_path" | wc -l)
printf '%s\n' "\$@" >"$records_path/\$((record_count + 1))"
EOF
chmod +x "$work_path/dump"
printf 'bind generic X +%s annotation=%%(annotation) text=%%(text)\n' "$work_path/dump" >"$work_path/tigrc"

tmux_probe() {
	tmux -S "$socket_path" "$@"
}

wait_for_screen() {
	for _ in $(seq 50); do
		if tmux_probe capture-pane -p 2>/dev/null | grep -Eq -- "$1"; then
			return 0
		fi
		sleep 0.1
	done
	echo "timed out waiting for /$1/ on screen" >&2
	return 1
}

start_tig() {
	# Each run gets a fresh server: a new-session straight after kill-server on the same socket can reach the old
	# server while it is still exiting, and fails with "server exited unexpectedly".
	[ -z "$socket_path" ] || tmux_probe kill-server 2>/dev/null || true
	session_count=$((session_count + 1))
	socket_path="$work_path/tmux-$session_count"
	tmux_probe new-session -d -x 200 -y 50 -c "$repository_path" \
		env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
		TIGRC_USER="$work_path/tigrc" GIT_PAGER="$tig_binary" "$@"
}

search() {
	tmux_probe send-keys Home
	tmux_probe send-keys /
	sleep 0.2
	tmux_probe send-keys -l -- "$1"
	tmux_probe send-keys Enter
	sleep 0.2
}

record_at() {
	local before after
	before=$(find "$records_path" -type f | wc -l)
	search "$1"
	tmux_probe send-keys X
	for _ in $(seq 50); do
		after=$(find "$records_path" -type f | wc -l)
		if [ "$after" -gt "$before" ]; then
			cat "$records_path/$after"
			return 0
		fi
		sleep 0.1
	done
	return 1
}

pass() {
	printf 'ok    %s\n' "$1"
}

fail() {
	printf 'FAIL  %s\n' "$1"
	failure_count=$((failure_count + 1))
}

check() {
	local label="$1" pattern="$2" expected="$3" record actual
	record=$(record_at "$pattern") || record=""
	actual=$(sed -n 1p <<<"$record")
	if [ "$actual" = "annotation=$expected" ]; then
		pass "$label"
	else
		fail "$label: expected annotation=$expected, got ${actual:-no record}"
	fi
}

check_raw_tab() {
	local label="$1" record
	record=$(record_at 'indented tab') || record=""
	if [ "$(sed -n 2p <<<"$record")" = $'text=+\tindented tab' ]; then
		pass "$label"
	else
		fail "$label: %(text) is not the raw line: $(sed -n 2p <<<"$record" | cat -A)"
	fi
}

echo "== pager view (git show through GIT_PAGER)"
start_tig git -c color.ui=never show HEAD
wait_for_screen 'drift commit'
check "pager: added line" '^\+new1$' 'drift.txt:1'
check "pager: context line after additions" '^ line1$' 'drift.txt:4'
check "pager: deleted line" '^-line8$' 'drift.txt:-8'
check "pager: context line after deletion" '^ line9$' 'drift.txt:11'
check "pager: deleted file" '^-bye$' 'gone.txt:-1'
check "pager: added last line" '^\+last$' 'newline.txt:2'
check "pager: no-newline marker" 'No newline at end of file' ''
check "pager: diff header" '^diff --git a/drift.txt' ''
check "pager: chunk header" '^@@ -1,10' ''
check "pager: commit message" 'drift commit' ''
check_raw_tab "pager: %(text) keeps tabs"

echo "== diff view (tig show)"
start_tig "$tig_binary" show HEAD
wait_for_screen 'drift commit'
check "diff: deleted line" '^-line8$' 'drift.txt:-8'
check "diff: context line" '^ line9$' 'drift.txt:11'
check "diff: diffstat line" 'drift.txt +[|]' ''

echo "== stage view (tig status, unstaged stage.txt)"
start_tig "$tig_binary" status
wait_for_screen 'stage.txt'
search 'stage.txt'
tmux_probe send-keys Enter
wait_for_screen '\[stage\]'
check "stage: deleted line" '^-line8$' 'stage.txt:-8'
check "stage: context line" '^ line9$' 'stage.txt:11'
check "stage: added line" '^\+new3$' 'stage.txt:3'
check "stage: diffstat line" 'stage.txt +[|]' ''

echo "== marks (a note keyed drift.txt:-8)"
mkdir -p "$repository_path/.git/tig-annotate"
printf 'note\n' >"$repository_path/.git/tig-annotate/drift.txt:-8.md"
start_tig "$tig_binary" show HEAD
wait_for_screen '^-line8'
screen=$(tmux_probe capture-pane -p)
if grep -E '^-line8' <<<"$screen" | grep -qF "$reference_mark"; then
	pass "marks: ※ on -line8"
else
	fail "marks: no ※ on -line8"
fi
if grep -E '^ line9' <<<"$screen" | grep -qF "$reference_mark"; then
	fail "marks: stray ※ on line9"
else
	pass "marks: no ※ on line9"
fi

echo "== pager view (staged deletions through git diff --cached)"
git_quiet rm -q staged-gone.txt c/staged-gone.txt
# diff.mnemonicPrefix prints the old side as "c/{path}", a prefix tig does not strip on its own.
start_tig git -c color.ui=never -c diff.mnemonicPrefix=true diff --cached
wait_for_screen 'farewell'
check "pager: staged deletion, mnemonic prefix" '^-farewell$' 'staged-gone.txt:-1'
check "pager: staged deletion in c/, mnemonic prefix" '^-inside c$' 'c/staged-gone.txt:-1'
start_tig git -c color.ui=never diff --cached
wait_for_screen 'farewell'
check "pager: staged deletion in c/, default prefix" '^-inside c$' 'c/staged-gone.txt:-1'

printf '\n%d failure(s)\n' "$failure_count"
[ "$failure_count" -eq 0 ]

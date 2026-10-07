# shellcheck shell=bash
# PLANNOTATOR_BROWSER for the isolated package: shows the review in the review-window Electron app (review-window/).
# Plannotator runs it with the review URL as its direct child, inside the network namespace isolate.sh made,
# so the window reaches only loopback. Electron gets a PID namespace of its own, so all of its processes end together.
# Its output is captured by Plannotator and never shown, so it speaks to the user through Plannotator's stderr.
# Usage: plannotator-review-window <http://localhost:PORT/...>

if [[ $# -ne 1 ]]; then
	echo "usage: plannotator-review-window <http://localhost:PORT/...>" >&2
	exit 2
fi
review_url="$1"

# First pass: run again under a parent-death signal, so the kernel kills the launcher, and with it the window,
# when Plannotator exits. The parent's id travels along to catch a Plannotator that exited before the signal was armed.
if [[ -z "${PLANNOTATOR_REVIEW_WINDOW_SERVER_PID:-}" ]]; then
	export PLANNOTATOR_REVIEW_WINDOW_SERVER_PID="$PPID"
	exec @setpriv@ --pdeathsig KILL -- "$0" "$@"
fi
if [[ "$PPID" != "$PLANNOTATOR_REVIEW_WINDOW_SERVER_PID" ]]; then
	exit 0
fi
unset PLANNOTATOR_REVIEW_WINDOW_SERVER_PID

# Plannotator's stderr reaches Claude.
# The write runs in a subshell: with no reader left (Claude killed), bash would die of SIGPIPE before ending the session.
# It appends, since that stderr may be a file (Claude Code's Bash tool collects a command's output in one), which > would empty.
tell_plannotator() { # <message>
	(printf 'Plannotator review window: %s\n' "$1" >>"/proc/$PPID/fd/2") 2>/dev/null || true
}

# Ends the review the way an interruption does: Plannotator exits 143 without feedback and keeps the draft.
# Not POST /api/exit, which deletes the draft.
end_session() { # <message>
	tell_plannotator "$1"
	kill -TERM "$PPID" 2>/dev/null || true
	exit 0
}

wayland_display="${WAYLAND_DISPLAY:-wayland-0}"
if [[ "$wayland_display" == /* ]]; then
	wayland_socket_path="$wayland_display"
else
	wayland_socket_path="${XDG_RUNTIME_DIR:-}/$wayland_display"
fi
if [[ ! -S "$wayland_socket_path" ]]; then
	end_session "no Wayland socket at $wayland_socket_path, so there is no review window (a bubble started --without-clipboard has none)"
fi

# The profile keeps cookies (Plannotator's settings, Comment mode among them) and the zoom level across reviews.
# Electron cannot share it between two running windows, so a concurrent review gets a throwaway one in the namespace's /tmp.
exec {lock_descriptor}>>"$PLANNOTATOR_DATA_DIR/review-window.lock"
if @flock@ --nonblock "$lock_descriptor"; then
	profile_path="$PLANNOTATOR_DATA_DIR/review-window"
else
	profile_path="$(@mktemp@ -d /tmp/review-window.XXXXXX)"
	tell_plannotator "another review window is open, so this one starts with a fresh profile and Plannotator's default settings"
fi

# The render nodes isolate.sh passed in, which the fresh /dev leaves out, so Electron draws on the GPU.
render_node_arguments=()
for render_node_path in /dev/dri/renderD*; do
	if [[ -c "$render_node_path" ]]; then
		render_node_arguments+=(--dev-bind "$render_node_path" "$render_node_path")
	fi
done

unset DISPLAY
export PLANNOTATOR_WINDOW_PROFILE="$profile_path"
electron_exit_code=0
@bwrap@ --unshare-pid --die-with-parent --bind / / --dev /dev "${render_node_arguments[@]}" --proc /proc \
	-- @electron@ --ozone-platform=wayland @appDirectory@ "$review_url" || electron_exit_code=$?

if [[ "$electron_exit_code" -eq 0 ]]; then
	end_session "the window was closed without sending feedback; the draft is kept, and running the review again restores it"
fi
end_session "the window failed (Electron exit status $electron_exit_code) without sending feedback; the draft is kept"

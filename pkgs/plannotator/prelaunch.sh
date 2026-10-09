# shellcheck shell=bash
# The step between isolate.sh and Plannotator, inside the namespace: when the subcommand opens a review window,
# starts it before Plannotator, then becomes Plannotator.
# The window loads its copy of the page while the server starts, so Electron's start and the page's script run beside the
# server's; Plannotator's browser command then only hands it the server's URL (review-window.sh).
# Started from this shell, which then execs Plannotator, the window is Plannotator's child,
# as when Plannotator starts it itself, so every way a review ends works the same.
# On when the browser command is the review window (the wrapper's default); PLANNOTATOR_WINDOW_PRELAUNCH=1 turns it on
# for a browser command that execs the review window itself (tests/plannotator's), 0 turns it off.
# Usage: plannotator-prelaunch <plannotator executable> [argument...]

plannotator_executable="$1"
shift

# The page each subcommand serves: the review page for review, the plan page for the others that open a window.
page_name=""
case "${1:-}" in
review) page_name=review ;;
annotate | annotate-last) page_name=plan ;;
esac
# These print and exit before a window could show anything.
for argument in "$@"; do
	case "$argument" in
	-h | --help | --version) page_name="" ;;
	esac
done
case "${PLANNOTATOR_WINDOW_PRELAUNCH:-}" in
1) ;;
"")
	if [[ "${PLANNOTATOR_BROWSER:-}" != "@reviewWindow@" ]]; then
		page_name=""
	fi
	;;
*) page_name="" ;;
esac

if [[ -n "$page_name" ]]; then
	# In the namespace's own /tmp, which nothing outside this session sees.
	PLANNOTATOR_WINDOW_HANDOFF="$(@mktemp@ -d /tmp/review-window-handoff.XXXXXX)"
	export PLANNOTATOR_WINDOW_HANDOFF
	# Locked before the window starts and held by it until it ends,
	# so the browser command finds it however late the window is in starting.
	exec {handoff_lock_descriptor}>"$PLANNOTATOR_WINDOW_HANDOFF/window.lock"
	@flock@ "$handoff_lock_descriptor"
	# Plannotator's stdout carries the review's outcome to Claude, so nothing of the window's may reach it;
	# the window speaks through Plannotator's stderr instead.
	"@reviewWindow@" --page "$page_name" </dev/null >/dev/null 2>&1 &
	exec {handoff_lock_descriptor}>&-
fi

exec "$plannotator_executable" "$@"

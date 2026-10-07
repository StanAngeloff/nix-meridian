# shellcheck shell=bash
# Host-side notification relay for a bubbled Claude Code session. Tails the bubble event file written by the in-bubble hook, applies each action to the launching pane, and plays the chime. Runs entirely host-side, where tmux and PipeWire are reachable.
# Args: <event-file> <tmux-pane> <chime-mp3>
set -euo pipefail

event_file="$1"
tmux_pane="$2"
chime_file="$3"
# Same pattern as www-browser.sh: one http or https URL, without whitespace.
web_url_pattern='^https?://[^[:space:]]+$'

# Tail appended lines; each is one action name, a tig-path-set:<path> directive or a www-browser:<url> request.
tail -n +1 -F "$event_file" 2>/dev/null | while IFS= read -r action; do
	[ -n "$action" ] || continue
	case "$action" in
	www-browser:*)
		# The boundary for claude-bubble-www-browser: anything in the bubble can append this line, so the URL is checked here.
		url="${action#www-browser:}"
		if [[ "$url" =~ $web_url_pattern ]]; then
			setsid --fork xdg-open "$url" </dev/null >/dev/null 2>&1 || true
		else
			logger -t claude-bubble-relay "refused to open a URL that is not plain http or https: ${url:0:200}" || true
		fi
		continue
		;;
	tig-path-set:*)
		tmux set -p -t "$tmux_pane" @tig_path "${action#tig-path-set:}" 2>/dev/null || true
		continue
		;;
	tig-path-unset)
		tmux set -pu -t "$tmux_pane" @tig_path 2>/dev/null || true
		continue
		;;
	esac
	if [ -n "$tmux_pane" ]; then
		claude-tmux-state --apply "$tmux_pane" "$action" || true
	fi
	if [ "$action" = blocked ]; then
		setsid --fork pw-play "$chime_file" >/dev/null 2>&1 || true
	fi
done

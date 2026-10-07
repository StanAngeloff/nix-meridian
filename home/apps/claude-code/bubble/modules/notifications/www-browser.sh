# shellcheck shell=bash
# Hands one http or https URL to the host browser, for programs that take a browser command.
# Inside the bubble the request travels to the host-side relay through the session's event file;
# relay.sh checks it again, because anything in the bubble can write that file.
# Outside the bubble it refuses:
# whatever runs it there (Plannotator's review window, inside its own network namespace) falls back to copying the URL instead.
# Usage: claude-bubble-www-browser <http(s)://...>
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: claude-bubble-www-browser <http(s)://...>" >&2
	exit 2
fi
url="$1"

# Same pattern as relay.sh's www-browser case. [:space:] also rules out a newline, which would split one request in two.
web_url_pattern='^https?://[^[:space:]]+$'
if [[ ! "$url" =~ $web_url_pattern ]]; then
	echo "claude-bubble-www-browser: refusing a URL that is not plain http or https: $url" >&2
	exit 1
fi

if [[ -z "${CLAUDE_BUBBLE_EVENT_FILE:-}" ]]; then
	echo "claude-bubble-www-browser: not inside the bubble, so there is no relay to open $url" >&2
	exit 1
fi
printf 'www-browser:%s\n' "$url" >>"$CLAUDE_BUBBLE_EVENT_FILE"

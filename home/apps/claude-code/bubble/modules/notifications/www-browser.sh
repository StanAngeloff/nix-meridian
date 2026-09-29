# shellcheck shell=bash
# Opens a loopback URL in the host browser, for programs that take a browser command.
# Inside the bubble the request travels to the host-side relay through the session's event file; relay.sh checks it
# again, because anything in the bubble can write that file. Outside the bubble it runs xdg-open.
# Usage: claude-bubble-www-browser <http://127.0.0.1:PORT/...|http://localhost:PORT/...>
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: claude-bubble-www-browser <http://127.0.0.1:PORT/...|http://localhost:PORT/...>" >&2
	exit 2
fi
url="$1"

# Same pattern as relay.sh's www-browser case. [:space:] also rules out a newline, which would split one request in two.
loopback_url_pattern='^http://(127\.0\.0\.1|localhost):[0-9]{1,5}(/[^[:space:]]*)?$'
if [[ ! "$url" =~ $loopback_url_pattern ]]; then
	echo "claude-bubble-www-browser: refusing a URL that is not plain http on loopback: $url" >&2
	exit 1
fi

if [[ -n "${CLAUDE_BUBBLE_EVENT_FILE:-}" ]]; then
	printf 'www-browser:%s\n' "$url" >>"$CLAUDE_BUBBLE_EVENT_FILE"
else
	exec xdg-open "$url"
fi

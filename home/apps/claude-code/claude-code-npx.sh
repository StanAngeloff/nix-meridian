# Claude Code's sandbox rewrites TMPDIR to $TMPDIR/claude-<uid>, so we
# default TMPDIR to /tmp (not the namespaced directory) to avoid double-nesting.
# TMP gets the namespaced directory for unsandboxed commands that prefer it.
CLAUDE_TMPDIR="/tmp/claude-$(id -u)"
mkdir -p "$CLAUDE_TMPDIR"
export TMP="${TMP:-$CLAUDE_TMPDIR}"
export TMPDIR="${TMPDIR:-/tmp}"

exec npx --yes --silent @package@@@version@ "$@"

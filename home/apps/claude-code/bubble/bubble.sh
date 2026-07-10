# Bubblewrap isolation for Claude Code — the skeleton: session facts, the scratch directory, the cleanup trap and the lifecycle slots.
# Every concern (base mounts, gpg, github, notifications, …) is a module at bubble/modules/<name>/hooks.sh defining <module>_<phase>() hook functions; bubble/package.nix concatenates the definitions and generates the per-phase call lines, in a module order that is also the bwrap bind order — the module list and the ordering constraints live there.
# Slot markers are replaced wherever they appear, comments included — never mention one outside its slot.
# Hooks share the script's globals: the facts below, bwrap_args, and their own cross-phase variables.
#
# Boundary: host read-only, synthetic tmpfs $HOME with only the project and ~/.claude writable, secrets excluded by allowlist, network + PID namespaces shared (loopback dev services and `ps` must work).
# Inner Bash sandbox is turned off via the alias's --settings.

set -euo pipefail

# Substituted at build time (builtins.replaceStrings — no import-from-derivation).
claudeBin="@claudeBin@"

project_path="$(pwd -P)"
user_name="$(id -un)"
user_id="$(id -u)"
home_path="$HOME"
xdg_runtime_path="${XDG_RUNTIME_DIR:-/run/user/$user_id}"

# Highlight boundary-affecting announcements when stderr is a terminal; stay plain when piped.
highlight_on=""
highlight_off=""
if [[ -t 2 ]]; then
	highlight_on=$'\033[1;33m'
	highlight_off=$'\033[0m'
fi

# Arguments the bubble owns: tokens exactly matching --with-<grant>, where <grant> is declared by a module (see package.nix), are consumed here and announced on stderr; every other argument passes to Claude Code untouched, so unknown --with-* spellings surface as Claude Code's own unknown-option error.
declare -A bubble_grants=()
claude_args=()
help_requested=""
for argument in "$@"; do
	if [[ "$argument" == --with-?* && " @grantNames@ " == *" ${argument#--with-} "* ]]; then
		bubble_grants["${argument#--with-}"]=1
		echo "${highlight_on}claude-bubble: grant '${argument#--with-}' active${highlight_off}" >&2
	else
		if [[ "$argument" == "--help" || "$argument" == "-h" ]]; then help_requested=1; fi
		claude_args+=("$argument")
	fi
done

# Per-session scratch bound in as a guaranteed-writable $TMPDIR (mining found empty $TMPDIR silently collapsing paths to /wayback etc.).
scratch_path="$(mktemp -d "/tmp/claude-bubble.$user_id.XXXXXX")"

@moduleFunctions@

# Cleanup hooks run twice on the happy path (the explicit call at the end, then the EXIT trap) and once on error paths, possibly before prepare ever ran — they must be idempotent and tolerate never-created paths.
# Installed before the prepare hooks so nothing they create can leak.
cleanup() {
	rm -rf "$scratch_path"
	@cleanupCalls@
}
trap cleanup EXIT

@prepareCalls@

bwrap_args=()

@mountCalls@

@environmentCalls@

bwrap_args+=(--chdir "$project_path")

@beforeRunCalls@

set +e
bwrap "${bwrap_args[@]}" -- "$claudeBin" "${claude_args[@]}"
exit_code=$?
set -e

@afterRunCalls@

# Claude Code has printed its own help by now; document the bubble-owned flags after it.
if [[ -n "$help_requested" ]]; then
	printf '%s' '@grantsHelp@'
fi

# Not redundant with the trap: without a direct call shellcheck cannot see the cleanup hooks invoked (SC2329).
cleanup

exit "$exit_code"

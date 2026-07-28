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

# Arguments the bubble owns: --with-<grant>/--without-<grant> flags (declared by modules, see package.nix), -v/--volume specs (Docker-style host:container:mode), and --help/-h (for appending bubble docs). Every other argument passes to Claude Code untouched, so unknown --with-* spellings surface as Claude Code's own unknown-option error.
declare -A bubble_grants=()
@defaultGrantInitializers@
bubble_volumes=()
claude_args=()
help_requested=""
args=("$@")
index=0
while [[ $index -lt ${#args[@]} ]]; do
	argument="${args[$index]}"
	if [[ "$argument" == --with-?* && " @grantNames@ " == *" ${argument#--with-} "* ]]; then
		bubble_grants["${argument#--with-}"]=1
		echo "${highlight_on}claude-bubble: grant '${argument#--with-}' active${highlight_off}" >&2
	elif [[ "$argument" == --without-?* && " @grantNames@ " == *" ${argument#--without-} "* ]]; then
		unset "bubble_grants[${argument#--without-}]"
		echo "${highlight_on}claude-bubble: grant '${argument#--without-}' disabled${highlight_off}" >&2
	elif [[ ("$argument" == "-v" || "$argument" == "--volume") && $((index + 1)) -lt ${#args[@]} && "${args[$((index + 1))]}" == /* ]]; then
		index=$((index + 1))
		bubble_volumes+=("${args[$index]}")
	else
		# A "profiles" argument followed by a subcommand hands off to the standalone profile-switching
		# command, before any bubble machinery starts. Requiring a trailing argument keeps a Claude
		# option value that happens to be the word "profiles" (e.g. -p profiles) from being hijacked.
		if [[ "$argument" == "profiles" && $((index + 1)) -lt ${#args[@]} ]]; then
			exec @profilesHandler@ "${args[@]:$((index + 1))}"
		fi
		if [[ "$argument" == "--help" || "$argument" == "-h" ]]; then help_requested=1; fi
		claude_args+=("$argument")
	fi
	index=$((index + 1))
done

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

# User-requested volumes (-v/--volume): parsed as host[:container[:mode]] following Docker semantics.
for volume_spec in "${bubble_volumes[@]}"; do
	volume_host="" volume_container="" volume_mode="rw"
	IFS=: read -r volume_host volume_container volume_mode_or_empty <<<"$volume_spec"
	if [[ -z "$volume_container" ]]; then
		volume_container="$volume_host"
	elif [[ "$volume_container" == "ro" || "$volume_container" == "rw" ]]; then
		volume_mode="$volume_container"
		volume_container="$volume_host"
	fi
	if [[ -n "$volume_mode_or_empty" ]]; then
		volume_mode="$volume_mode_or_empty"
	fi
	case "$volume_mode" in
	ro) bwrap_args+=(--ro-bind "$volume_host" "$volume_container") ;;
	*) bwrap_args+=(--bind "$volume_host" "$volume_container") ;;
	esac
	echo "${highlight_on}claude-bubble: volume '$volume_host' → '$volume_container' ($volume_mode)${highlight_off}" >&2
done

bwrap_args+=(--chdir "$project_path")

@beforeRunCalls@

set +e
# The arguments go in on a file descriptor rather than the command line: /proc/<pid>/cmdline is world-readable, and the secrets module's --setenv pairs carry live credentials, so expanding the array here would publish them to every process on the host for the lifetime of the session. Process substitution keeps them in a pipe; a temporary file would trade that for the on-disk exposure the keyring migration closed, and a here-string cannot carry NUL separators because command substitution strips them. The whole array goes through, not just the secrets, so a module that starts injecting a value later is covered without revisiting this.
# The trade-off is that `ps` no longer shows the bubble's mount layout.
bwrap --args 3 -- "$claudeBin" "${claude_args[@]}" 3< <(printf '%s\0' "${bwrap_args[@]}")
exit_code=$?
set -e

@afterRunCalls@

# Claude Code has printed its own help by now; document the bubble-owned flags after it.
if [[ -n "$help_requested" ]]; then
	printf '%s' '@grantsHelp@'
	printf '\n  -v, --volume HOST[:CONTAINER[:MODE]]\n        Bind-mount HOST into the bubble at CONTAINER (default: same path).\n        MODE is rw (default) or ro. May be repeated.\n'
fi

# Not redundant with the trap: without a direct call shellcheck cannot see the cleanup hooks invoked (SC2329).
cleanup

exit "$exit_code"

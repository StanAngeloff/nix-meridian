# Bubblewrap isolation for Claude Code. Assembled and exec'd host-side; only the final
# `bwrap ... claude` runs bubbled. See bubble/package.nix for the packaging.
#
# Boundary: host read-only, synthetic tmpfs $HOME with only the project and ~/.claude
# writable, secrets excluded by allowlist, network + PID namespaces shared (loopback dev
# services and `ps` must work). Inner Bash sandbox is turned off via the alias's --settings.

set -euo pipefail

# Store paths and the injection list are substituted in at build time (see bubble/package.nix; builtins.replaceStrings fills these @placeholder@ slots — no import-from-derivation).
claudeBin="@claudeBin@"
bubbleRelay="@bubbleRelay@"
chimeMp3="@chimeMp3@"
bubbleInject="@bubbleInject@"

project_path="$(pwd -P)"
user_name="$(id -un)"
user_id="$(id -u)"
home_path="$HOME"
xdg_runtime_path="${XDG_RUNTIME_DIR:-/run/user/$user_id}"

# Per-session scratch bound in as a guaranteed-writable $TMPDIR (mining found empty
# $TMPDIR silently collapsing paths to /wayback etc.).
scratch_path="$(mktemp -d "/tmp/claude-bubble.$user_id.XXXXXX")"

# Synthetic gnupg: public keyring only, so in-bubble gpg finds the signing pubkey; the
# secret key never enters — the forwarded restricted agent socket does the crypto.
gnupg_seed_path="$scratch_path/gnupg"
mkdir -p "$gnupg_seed_path"
chmod 700 "$gnupg_seed_path"
gpg --export 2>/dev/null | GNUPGHOME="$gnupg_seed_path" gpg --import 2>/dev/null || true

# Shadow gh's hosts.yml (its keyring-backed account, which the bubble's masked keyring cannot read) with an empty file, so in-bubble `gh` sees only the injected GH_TOKEN.
# Otherwise gh reports that account "invalid" and prints `gh auth logout …`, which — if copied to the host — deletes the real credential. config.yml (settings) stays live via the directory bind below.
gh_empty_hosts="$scratch_path/gh-hosts-empty"
: >"$gh_empty_hosts"

# Event channel to the host-side notification relay; lives under the writable ~/.claude
# so in-bubble hooks can append to it and the host relay can read it.
event_path="$home_path/.claude/bubble-events"
mkdir -p "$event_path"
event_file="$event_path/$$.$(basename "$project_path")"
: >"$event_file"

# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() {
	rm -rf "$scratch_path"
	rm -f "$event_file"
}
trap cleanup EXIT

# Resolve the github MCP / gh token host-side (keyring is unreachable in-bubble).
gh_token="$(secret-tool lookup name mcp_keys key GH_TOKEN 2>/dev/null || true)"

# Encode the project path the way Claude Code names its transcript dir (/ -> -).
project_slug="${project_path//\//-}"

bwrap_args=(
	--die-with-parent
	# No --unshare-net / --unshare-pid: loopback dev services and host `ps` must work.
	--proc /proc
	--dev /dev
	--tmpfs /tmp
	# System, read-only.
	--ro-bind /nix /nix
	--ro-bind /etc /etc
	# NixOS FHS shims: /bin/sh (Claude Code's hook runner does posix_spawn '/bin/sh') and /usr/bin/env (env-shebang scripts).
	# Both are symlinks into /nix (bound above), so they resolve inside the bubble; without them every hook fails ENOENT.
	--ro-bind-try /bin /bin
	--ro-bind-try /usr /usr
	--ro-bind /run/current-system /run/current-system
	--ro-bind-try /run/systemd/resolve /run/systemd/resolve
	--ro-bind-try /sys /sys
	--ro-bind-try /run/opengl-driver /run/opengl-driver
	# Nix daemon socket -> in-bubble `nix build` works.
	--bind-try /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket
	# Synthetic empty home; project and ~/.claude are layered rw on top.
	--tmpfs "$home_path"
	--bind "$scratch_path" "$scratch_path"
	--bind "$project_path" "$project_path"
	--bind "$home_path/.claude" "$home_path/.claude"
)

# Masks inside ~/.claude: secret sprawl + other projects' transcripts.
for mask in file-history paste-cache backups daemon; do
	bwrap_args+=(--tmpfs "$home_path/.claude/$mask")
done
# projects/: hide all, re-expose only the current project's transcript dir (resume + memory).
bwrap_args+=(--tmpfs "$home_path/.claude/projects")
if [[ -d "$home_path/.claude/projects/$project_slug" ]]; then
	bwrap_args+=(--bind "$home_path/.claude/projects/$project_slug" "$home_path/.claude/projects/$project_slug")
fi

# Git identity + signing config, gh settings, nvim config — read-only.
bwrap_args+=(--ro-bind-try "$home_path/.gitconfig" "$home_path/.gitconfig")
bwrap_args+=(--ro-bind-try "$home_path/.config/git" "$home_path/.config/git")
bwrap_args+=(--ro-bind-try "$home_path/.config/gh" "$home_path/.config/gh")
# Shadow the keyring-backed gh account (see gh_empty_hosts above) so in-bubble `gh` uses only GH_TOKEN.
bwrap_args+=(--ro-bind-try "$gh_empty_hosts" "$home_path/.config/gh/hosts.yml")
bwrap_args+=(--ro-bind-try "$home_path/.config/nvim" "$home_path/.config/nvim")
# Only known_hosts from ~/.ssh (public data) so `git push` verifies GitHub's host key;
# private keys stay out — auth is via the forwarded agent socket.
bwrap_args+=(--ro-bind-try "$home_path/.ssh/known_hosts" "$home_path/.ssh/known_hosts")

# Synthetic gnupg (rw so gpg can update trustdb/random_seed; contains no secret keys).
bwrap_args+=(--bind "$gnupg_seed_path" "$home_path/.gnupg")

# XDG_RUNTIME_DIR: masked tmpfs (hides podman.sock, keyring, tmux, nvim sockets), then
# only the two gpg-agent sockets are re-exposed.
bwrap_args+=(--tmpfs "$xdg_runtime_path")
bwrap_args+=(--dir "$xdg_runtime_path/gnupg")
# Restricted "extra" socket (requires services.gpg-agent.enableExtraSocket): signing and
# decryption allowed, key management refused, secret keys never cross. Spike-verified:
# in-bubble gpg rejects the tmpfs runtime dir (secure-directory check) and resolves its
# agent socket at ~/.gnupg/S.gpg-agent, so bind the socket THERE (inside the seeded
# public-only gnupg directory); also expose it at the runtime path for tools that resolve
# via gpgconf. On a miss gpg silently autostarts a throwaway agent and reports a
# misleading "No secret key" — check `gpg-connect-agent 'getinfo pid'` when debugging.
bwrap_args+=(--ro-bind-try "$xdg_runtime_path/gnupg/S.gpg-agent.extra" "$home_path/.gnupg/S.gpg-agent")
bwrap_args+=(--ro-bind-try "$xdg_runtime_path/gnupg/S.gpg-agent.extra" "$xdg_runtime_path/gnupg/S.gpg-agent")
bwrap_args+=(--ro-bind-try "$xdg_runtime_path/gnupg/S.gpg-agent.ssh" "$xdg_runtime_path/gnupg/S.gpg-agent.ssh")

# Environment.
bwrap_args+=(
	--setenv HOME "$home_path"
	--setenv USER "$user_name"
	--setenv PATH "$PATH"
	--setenv TMPDIR "$scratch_path"
	--setenv TMP "$scratch_path"
	--setenv XDG_RUNTIME_DIR "$xdg_runtime_path"
	--setenv SSH_AUTH_SOCK "$xdg_runtime_path/gnupg/S.gpg-agent.ssh"
	--setenv NIX_REMOTE daemon
	--setenv TERM "${TERM:-xterm-256color}"
	--setenv CLAUDE_BUBBLE 1
	--setenv CLAUDE_BUBBLE_EVENT_FILE "$event_file"
	--unsetenv TMUX
	--unsetenv TMUX_PANE
	--unsetenv DOCKER_HOST
)
# if-form (not `[[ ]] &&`) so an unset variable can never trip errexit edge cases.
if [[ -n "${LANG:-}" ]]; then bwrap_args+=(--setenv LANG "$LANG"); fi
if [[ -n "${LC_ALL:-}" ]]; then bwrap_args+=(--setenv LC_ALL "$LC_ALL"); fi
if [[ -n "${COLORTERM:-}" ]]; then bwrap_args+=(--setenv COLORTERM "$COLORTERM"); fi
if [[ -n "$gh_token" ]]; then bwrap_args+=(--setenv GH_TOKEN "$gh_token"); fi

# Declarative extra secret injections: $bubbleInject is a space-separated list of keyring var
# names (substituted at build time); each fetched host-side and injected.
# Array-read instead of unquoted expansion keeps shellcheck (SC2086) happy at build time.
read -r -a inject_names <<<"$bubbleInject"
for name in "${inject_names[@]}"; do
	value="$(secret-tool lookup name mcp_keys key "$name" 2>/dev/null || true)"
	if [[ -n "$value" ]]; then bwrap_args+=(--setenv "$name" "$value"); fi
done

bwrap_args+=(--chdir "$project_path")

# Start the host-side notification relay (it has tmux + PipeWire; the bubble does not).
# TMUX_PANE is still set here (host side); the bubble child gets it unset via --unsetenv above.
relay_pid=""
if [[ -n "${TMUX_PANE:-}" ]]; then
	"$bubbleRelay" "$event_file" "$TMUX_PANE" "$chimeMp3" &
	relay_pid=$!
fi

set +e
bwrap "${bwrap_args[@]}" -- "$claudeBin" "$@"
exit_code=$?
set -e

if [[ -n "$relay_pid" ]]; then
	kill "$relay_pid" 2>/dev/null || true
	tmux set -wu -t "$TMUX_PANE" @claude-state 2>/dev/null || true
fi
exit "$exit_code"

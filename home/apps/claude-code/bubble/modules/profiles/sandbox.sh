set -euo pipefail

# Runs a command in a throwaway nested bubblewrap sandbox, for the proofs in verify.sh beside this file.
# Inside: every home directory under an empty tmpfs; empty /tmp and /run, so no session socket, D-Bus or resolver socket;
# the nix daemon and garbage-collector sockets masked; a cleared environment; with --offline, no network at all.
# The probe root is the only writable path shared with the outside, bound at the same path. CLAUDE_CONFIG_DIR and
# XDG_RUNTIME_DIR point into it, and bubblewrap options given between the probe root and -- come last, so they can add
# binds or override those variables.

usage_line="usage: claude-profiles-sandbox [--offline] <probe root> [bubblewrap options…] -- <command…>"
network_options=()
if [[ "${1:-}" == --offline ]]; then
	network_options=(--unshare-net)
	shift
fi
if [[ $# -lt 1 ]]; then
	echo "$usage_line" >&2
	exit 2
fi
probe_root="$1"
shift
extra_options=()
while [[ $# -gt 0 && "$1" != -- ]]; do
	extra_options+=("$1")
	shift
done
if [[ $# -lt 2 ]]; then
	echo "$usage_line" >&2
	exit 2
fi
shift

socket_masks=()
for socket_path in /nix/var/nix/daemon-socket /nix/var/nix/gc-socket; do
	if [[ -d "$socket_path" ]]; then
		socket_masks+=(--tmpfs "$socket_path")
	fi
done

exec bwrap \
	--die-with-parent --unshare-pid --unshare-ipc "${network_options[@]}" \
	--ro-bind /nix /nix "${socket_masks[@]}" \
	--ro-bind /etc /etc \
	--tmpfs /run \
	--ro-bind /run/current-system /run/current-system \
	--ro-bind-try /bin /bin --ro-bind-try /usr /usr --ro-bind-try /lib64 /lib64 \
	--proc /proc --dev /dev --tmpfs /tmp \
	--tmpfs /home --tmpfs "$HOME" \
	--bind "$probe_root" "$probe_root" \
	--clearenv \
	--setenv PATH "$PATH" \
	--setenv HOME "$HOME" \
	--setenv USER "$(id -un)" \
	--setenv TERM "${TERM:-xterm-256color}" \
	--setenv LANG "${LANG:-C.UTF-8}" \
	--setenv TMPDIR /tmp \
	--setenv CLAUDE_CONFIG_DIR "$probe_root/config" \
	--setenv XDG_RUNTIME_DIR "$probe_root/runtime" \
	"${extra_options[@]}" \
	--chdir "$probe_root" \
	-- "$@"

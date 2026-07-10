# The Nix daemon socket is a host-mutation channel: the daemon runs host-side as root and honours nix-env / nix profile (rewrite host profiles) and nix store gc (delete live paths), not just builds.
# It is exposed by default through the system module's broad `--ro-bind /nix` (the socket lives at /nix/var/nix/daemon-socket/socket), and nix auto-connects to it whenever present — NIX_REMOTE is not required. So sealing means masking the socket the /nix bind leaks, not withholding a bind. (Verified: without the mask, `nix build` succeeds in a sealed session.)

nix_mount() {
	if [[ -z "${bubble_grants[nix]:-}" ]]; then
		# Mask both sockets the /nix bind leaks (daemon = full RPC; gc = temproot registration); nix then finds no daemon and cannot write the read-only store, so builds and host mutation both fail closed.
		bwrap_args+=(--tmpfs /nix/var/nix/daemon-socket)
		bwrap_args+=(--tmpfs /nix/var/nix/gc-socket)
	fi
}

nix_environment() {
	if [[ -n "${bubble_grants[nix]:-}" ]]; then
		bwrap_args+=(--setenv NIX_REMOTE daemon)
	fi
}

# Container control plane. Sealed by default: the xdg mask hides the podman API socket and DOCKER_HOST is unset so Docker-API clients do not go looking. `--with-podman` re-exposes the socket for the session — host-side podman executes with the user's full filesystem view (any `podman run -v` mounts whatever the user can read), so the grant opts this session out of the boundary for user-readable paths.

podman_prepare() {
	if [[ -n "${bubble_grants[podman]:-}" && ! -S "$xdg_runtime_path/podman/podman.sock" ]]; then
		bubble_warn "--with-podman requested but $xdg_runtime_path/podman/podman.sock does not exist" \
			"is podman.socket active?"
	fi
}

podman_mount() {
	# The directory, not the socket file, so a socket-unit restart (which recreates podman.sock) stays visible.
	if [[ -n "${bubble_grants[podman]:-}" ]]; then
		bwrap_args+=(--ro-bind-try "$xdg_runtime_path/podman" "$xdg_runtime_path/podman")
	fi
}

podman_environment() {
	if [[ -n "${bubble_grants[podman]:-}" ]]; then
		# CONTAINER_HOST switches the podman CLI to remote mode; DOCKER_HOST serves Docker-API clients (docker-compose, supabase CLI).
		bwrap_args+=(
			--setenv CONTAINER_HOST "unix://$xdg_runtime_path/podman/podman.sock"
			--setenv DOCKER_HOST "unix://$xdg_runtime_path/podman/podman.sock"
		)
	else
		bwrap_args+=(--unsetenv DOCKER_HOST)
	fi
}

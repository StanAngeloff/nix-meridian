# Masked tmpfs over XDG_RUNTIME_DIR: hides podman.sock, the keyring, tmux and nvim sockets. Later modules (gpg, ssh) re-expose only their agent sockets on top.
xdg_mount() {
	bwrap_args+=(--tmpfs "$xdg_runtime_path")
}

xdg_environment() {
	bwrap_args+=(--setenv XDG_RUNTIME_DIR "$xdg_runtime_path")
}

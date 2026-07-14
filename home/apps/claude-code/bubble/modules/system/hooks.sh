system_prepare() {
	mkdir -p "$scratch_path/tmp"
}

system_mount() {
	bwrap_args+=(
		--die-with-parent
		# No --unshare-net / --unshare-pid: loopback dev services and host `ps` must work.
		--proc /proc
		--dev /dev
		--bind "$scratch_path/tmp" /tmp
		# System, read-only.
		--ro-bind /nix /nix
		--ro-bind /etc /etc
		# NixOS FHS shims: /bin/sh (Claude Code's hook runner does posix_spawn '/bin/sh') and /usr/bin/env (env-shebang scripts).
		# Both are symlinks into /nix (bound above), so they resolve inside the bubble; without them every hook fails ENOENT.
		--ro-bind-try /bin /bin
		--ro-bind-try /usr /usr
		# nix-ld's ELF-interpreter shim (programs.nix-ld): without it manylinux binaries — e.g. uv-provisioned tools like ruff — fail to spawn with a misleading ENOENT on an existing file.
		--ro-bind-try /lib64 /lib64
		--ro-bind /run/current-system /run/current-system
		--ro-bind-try /run/systemd/resolve /run/systemd/resolve
		--ro-bind-try /sys /sys
		--ro-bind-try /run/opengl-driver /run/opengl-driver
	)
}

system_environment() {
	bwrap_args+=(
		--setenv PATH "$PATH"
		--setenv TERM "${TERM:-xterm-256color}"
	)
	# if-form (not `[[ ]] &&`) so an unset variable can never trip errexit edge cases.
	if [[ -n "${LANG:-}" ]]; then bwrap_args+=(--setenv LANG "$LANG"); fi
	if [[ -n "${LC_ALL:-}" ]]; then bwrap_args+=(--setenv LC_ALL "$LC_ALL"); fi
	if [[ -n "${COLORTERM:-}" ]]; then bwrap_args+=(--setenv COLORTERM "$COLORTERM"); fi
	# The nix-ld shim reads these at exec time; interactive shells re-export them from the bound /etc, but processes spawned without a profile would otherwise miss them.
	if [[ -n "${NIX_LD:-}" ]]; then bwrap_args+=(--setenv NIX_LD "$NIX_LD"); fi
	if [[ -n "${NIX_LD_LIBRARY_PATH:-}" ]]; then bwrap_args+=(--setenv NIX_LD_LIBRARY_PATH "$NIX_LD_LIBRARY_PATH"); fi
}

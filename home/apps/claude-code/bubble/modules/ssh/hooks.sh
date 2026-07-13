ssh_prepare() {
	# SSH requires Include'd files to be owned by root or the current user. Inside the bubble, nix store files show as nobody:nogroup (bwrap maps unmapped UIDs), so any Include pointing into /nix/store fails with "Bad owner or permissions". Strip those Includes from a copy of the system ssh_config.
	ssh_config_path="$scratch_path/ssh_config"
	ssh_config_target=""
	if [[ -r /etc/ssh/ssh_config ]]; then
		grep -v '^Include /nix/store/' /etc/ssh/ssh_config > "$ssh_config_path"
		# On NixOS /etc/ssh/ssh_config is a symlink into the nix store; bwrap cannot overlay a symlink on a read-only mount. Resolve to the real path and bind there instead — a later, more specific --ro-bind layers on top of the broad --ro-bind /nix /nix.
		ssh_config_target="$(readlink -f /etc/ssh/ssh_config)"
	fi
}

ssh_mount() {
	# Only known_hosts from ~/.ssh (public data) so `git push` verifies GitHub's host key; private keys stay out — auth is via the forwarded agent socket.
	bwrap_args+=(--ro-bind-try "$home_path/.ssh/known_hosts" "$home_path/.ssh/known_hosts")
	# The gpg-agent's ssh socket; the gpg module creates $xdg_runtime_path/gnupg.
	bwrap_args+=(--ro-bind-try "$xdg_runtime_path/gnupg/S.gpg-agent.ssh" "$xdg_runtime_path/gnupg/S.gpg-agent.ssh")
	# Shadow the system ssh_config with one that drops nix-store Includes (see ssh_prepare).
	if [[ -f "$ssh_config_path" && -n "$ssh_config_target" ]]; then
		bwrap_args+=(--ro-bind "$ssh_config_path" "$ssh_config_target")
	fi
}

ssh_environment() {
	bwrap_args+=(--setenv SSH_AUTH_SOCK "$xdg_runtime_path/gnupg/S.gpg-agent.ssh")
}

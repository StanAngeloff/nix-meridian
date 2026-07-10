ssh_mount() {
	# Only known_hosts from ~/.ssh (public data) so `git push` verifies GitHub's host key; private keys stay out — auth is via the forwarded agent socket.
	bwrap_args+=(--ro-bind-try "$home_path/.ssh/known_hosts" "$home_path/.ssh/known_hosts")
	# The gpg-agent's ssh socket; the gpg module creates $xdg_runtime_path/gnupg.
	bwrap_args+=(--ro-bind-try "$xdg_runtime_path/gnupg/S.gpg-agent.ssh" "$xdg_runtime_path/gnupg/S.gpg-agent.ssh")
}

ssh_environment() {
	bwrap_args+=(--setenv SSH_AUTH_SOCK "$xdg_runtime_path/gnupg/S.gpg-agent.ssh")
}

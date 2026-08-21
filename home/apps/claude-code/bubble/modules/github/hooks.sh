# Shadow gh's hosts.yml (its keyring-backed account, which the bubble's masked keyring cannot read) with an empty file, so in-bubble `gh` sees only the injected GH_TOKEN.
# Otherwise gh reports that account "invalid" and prints `gh auth logout …`, which — if copied to the host — deletes the real credential.
# An empty REGULAR file, not /dev/null: gh errors "permission denied" on a device-node bind.
github_prepare() {
	gh_empty_hosts="$scratch_path/gh-hosts-empty"
	: >"$gh_empty_hosts"
}

github_mount() {
	# Bind config.yml individually so hosts.yml can be shadowed with the empty file from the prepare hook.
	# A whole-directory bind followed by a file overlay fails when hosts.yml is a symlink (Home Manager).
	bwrap_args+=(--dir "$home_path/.config/gh")
	bwrap_args+=(--ro-bind-try "$(readlink -f "$home_path/.config/gh/config.yml")" "$home_path/.config/gh/config.yml")
	bwrap_args+=(--ro-bind-try "$gh_empty_hosts" "$home_path/.config/gh/hosts.yml")

	# Expose gh extensions (installed by Home Manager into the Nix store) so commands like `gh stack` work.
	bwrap_args+=(--dir "$home_path/.local/share/gh")
	bwrap_args+=(--ro-bind-try "$home_path/.local/share/gh/extensions" "$home_path/.local/share/gh/extensions")
}

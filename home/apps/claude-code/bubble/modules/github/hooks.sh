# Shadow gh's hosts.yml (its keyring-backed account, which the bubble's masked keyring cannot read) with an empty file, so in-bubble `gh` sees only the injected GH_TOKEN.
# Otherwise gh reports that account "invalid" and prints `gh auth logout …`, which — if copied to the host — deletes the real credential.
# An empty REGULAR file, not /dev/null: gh errors "permission denied" on a device-node bind.
github_prepare() {
	gh_empty_hosts="$scratch_path/gh-hosts-empty"
	: >"$gh_empty_hosts"
}

github_mount() {
	# gh settings (config.yml) stay live via the directory bind; hosts.yml is shadowed by the empty file from the prepare hook.
	bwrap_args+=(--ro-bind-try "$home_path/.config/gh" "$home_path/.config/gh")
	bwrap_args+=(--ro-bind-try "$gh_empty_hosts" "$home_path/.config/gh/hosts.yml")
}

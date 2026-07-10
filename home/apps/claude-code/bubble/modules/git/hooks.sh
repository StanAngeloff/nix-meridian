# Git identity + signing config, read-only.
git_mount() {
	bwrap_args+=(--ro-bind-try "$home_path/.gitconfig" "$home_path/.gitconfig")
	bwrap_args+=(--ro-bind-try "$home_path/.config/git" "$home_path/.config/git")
}

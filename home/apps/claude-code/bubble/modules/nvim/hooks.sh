nvim_mount() {
	bwrap_args+=(--ro-bind-try "$home_path/.config/nvim" "$home_path/.config/nvim")
}

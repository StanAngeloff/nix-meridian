nvim_mount() {
	bwrap_args+=(
		--ro-bind-try "$home_path/.config/nvim" "$home_path/.config/nvim"
		--ro-bind-try "$home_path/.local/share/nvim" "$home_path/.local/share/nvim"
	)
}

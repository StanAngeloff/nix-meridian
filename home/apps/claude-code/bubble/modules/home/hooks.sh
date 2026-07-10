# Synthetic empty home; the project, the scratch directory and later modules' binds are layered on top.
home_mount() {
	bwrap_args+=(
		--tmpfs "$home_path"
		--bind "$scratch_path" "$scratch_path"
		--bind "$project_path" "$project_path"
	)
}

home_environment() {
	bwrap_args+=(
		--setenv HOME "$home_path"
		--setenv USER "$user_name"
		--setenv TMPDIR "$scratch_path"
		--setenv TMP "$scratch_path"
	)
}

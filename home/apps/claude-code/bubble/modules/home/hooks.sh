# Synthetic empty home; the project and later modules' binds are layered on top.
# It lives in the scratch directory rather than a tmpfs, so package caches, which can reach gigabytes in a session, stay out of memory.
home_prepare() {
	mkdir -p "$scratch_path/home"
}

home_mount() {
	bwrap_args+=(
		--bind "$scratch_path/home" "$home_path"
		--bind "$project_path" "$project_path"
	)
}

home_environment() {
	bwrap_args+=(
		--setenv HOME "$home_path"
		--setenv USER "$user_name"
		--setenv TMPDIR /tmp
		--setenv TMP /tmp
	)
}

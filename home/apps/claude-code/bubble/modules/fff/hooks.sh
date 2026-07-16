# fff.nvim stores an LMDB query database at ~/.local/share/nvim/fff_queries; the nvim module binds that tree read-only, so layer a writable copy on top.
fff_prepare() {
	fff_queries_host="$home_path/.local/share/nvim/fff_queries"
	fff_queries_scratch="$scratch_path/fff_queries"
	if [[ -d "$fff_queries_host" ]]; then
		cp -a "$fff_queries_host" "$fff_queries_scratch"
	else
		mkdir -p "$fff_queries_scratch"
	fi
}

fff_mount() {
	if [[ -d "$fff_queries_scratch" ]]; then
		bwrap_args+=(--bind "$fff_queries_scratch" "$home_path/.local/share/nvim/fff_queries")
	fi
}

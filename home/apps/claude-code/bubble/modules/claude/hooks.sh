claude_prepare() {
	# Encode the project path the way Claude Code names its transcript directory (/ -> -).
	project_slug="${project_path//\//-}"
}

claude_mount() {
	local mask
	bwrap_args+=(--bind "$home_path/.claude" "$home_path/.claude")
	# Masks inside ~/.claude: secret sprawl + other projects' transcripts.
	for mask in file-history paste-cache backups daemon; do
		bwrap_args+=(--tmpfs "$home_path/.claude/$mask")
	done
	# projects/: hide all, re-expose only the current project's transcript directory (resume + memory).
	bwrap_args+=(--tmpfs "$home_path/.claude/projects")
	if [[ -d "$home_path/.claude/projects/$project_slug" ]]; then
		bwrap_args+=(--bind "$home_path/.claude/projects/$project_slug" "$home_path/.claude/projects/$project_slug")
	fi
}

claude_environment() {
	bwrap_args+=(--setenv CLAUDE_BUBBLE 1)
}

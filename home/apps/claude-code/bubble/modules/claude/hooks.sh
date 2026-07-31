claude_prepare() {
	# Claude Code slugifies with path.replace(/[^a-zA-Z0-9]/g, "-").
	project_slug="${project_path//[^a-zA-Z0-9]/-}"
	mkdir -p "$home_path/.claude/projects/$project_slug"
	# Scratch-backed overlay replaces a kernel tmpfs so the contents survive bwrap's exit
	# and claude_after_run can rescue stray directories if CC's slug ever drifts from ours.
	projects_overlay="$scratch_path/projects-overlay"
	mkdir -p "$projects_overlay"
}

claude_mount() {
	local mask
	bwrap_args+=(--bind "$home_path/.claude" "$home_path/.claude")
	for mask in file-history paste-cache backups daemon; do
		bwrap_args+=(--tmpfs "$home_path/.claude/$mask")
	done
	# Hide all projects, re-expose only the current project's transcript directory (resume + memory).
	bwrap_args+=(--bind "$projects_overlay" "$home_path/.claude/projects")
	bwrap_args+=(--bind "$home_path/.claude/projects/$project_slug" "$home_path/.claude/projects/$project_slug")
}

claude_environment() {
	bwrap_args+=(--setenv CLAUDE_BUBBLE 1)
}

claude_after_run() {
	local stray stray_name stray_files rescue_base rescue_target timestamp
	rescue_base="$home_path/.claude/rescued-projects"
	for stray in "$projects_overlay"/*/; do
		[[ -d "$stray" ]] || continue
		stray_name="$(basename "$stray")"
		[[ "$stray_name" == "$project_slug" ]] && continue
		# Claude Code can register project directories besides the one we mount — notably the path of a git worktree it manages (--worktree). The session transcript stays under the launch directory, which we do mount, so these extras are empty: no data to lose, and they vanish with the scratch cleanup. Rescue and warn only when the stray actually holds files.
		stray_files="$(find "$stray" -type f -print -quit 2>/dev/null || true)"
		[[ -n "$stray_files" ]] || continue
		mkdir -p "$rescue_base"
		rescue_target="$rescue_base/$stray_name"
		if [[ -d "$rescue_target" ]]; then
			timestamp="$(date +%Y%m%dT%H%M%S)"
			rescue_target="${rescue_target}.${timestamp}"
		fi
		mv "$stray" "$rescue_target"
		echo "" >&2
		bubble_error "session data rescued — Claude Code used an unexpected project slug" \
			"Claude Code wrote   ${stray_name}" \
			"bubble expected     ${project_slug}" \
			"rescued to          ${rescue_target}" \
			"" \
			"restore it with" \
			"  mv '${rescue_target}' \\" \
			"     '${home_path}/.claude/projects/${stray_name}'"
		echo "" >&2
	done
}

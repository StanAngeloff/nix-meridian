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
	local stray stray_name rescue_base rescue_target timestamp
	rescue_base="$home_path/.claude/rescued-projects"
	for stray in "$projects_overlay"/*/; do
		[[ -d "$stray" ]] || continue
		stray_name="$(basename "$stray")"
		[[ "$stray_name" == "$project_slug" ]] && continue
		mkdir -p "$rescue_base"
		rescue_target="$rescue_base/$stray_name"
		if [[ -d "$rescue_target" ]]; then
			timestamp="$(date +%Y%m%dT%H%M%S)"
			rescue_target="${rescue_target}.${timestamp}"
		fi
		mv "$stray" "$rescue_target"
		local red_on="" red_off=""
		if [[ -t 2 ]]; then red_on=$'\033[1;31m'; red_off=$'\033[0m'; fi
		echo "" >&2
		echo "${red_on}  ╔══════════════════════════════════════════════════════╗${red_off}" >&2
		echo "${red_on}  ║  ⚠  SESSION DATA RESCUED                             ║${red_off}" >&2
		echo "${red_on}  ╚══════════════════════════════════════════════════════╝${red_off}" >&2
		echo "" >&2
		echo "  ${highlight_on}↳ slug mismatch${highlight_off}" >&2
		echo "    Claude Code wrote → ${stray_name}" >&2
		echo "    Bubble expected  → ${project_slug}" >&2
		echo "" >&2
		echo "  ${highlight_on}↳ rescued to${highlight_off}" >&2
		echo "    ${rescue_target}" >&2
		echo "" >&2
		echo "  ${highlight_on}↳ to restore${highlight_off}" >&2
		echo "    mv '${rescue_target}' \\" >&2
		echo "       '${home_path}/.claude/projects/${stray_name}'" >&2
		echo "" >&2
	done
}

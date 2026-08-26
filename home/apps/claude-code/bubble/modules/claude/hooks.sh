claude_prepare() {
	# Claude Code slugifies with path.replace(/[^a-zA-Z0-9]/g, "-").
	project_slug="${project_path//[^a-zA-Z0-9]/-}"
	mkdir -p "$home_path/.claude/projects/$project_slug"
	# Scratch-backed overlay replaces a kernel tmpfs so the contents survive bwrap's exit
	# and claude_after_run can merge stray directories (worktree slugs) back into the project.
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
	local stray stray_name stray_files target is_worktree target_display
	for stray in "$projects_overlay"/*/; do
		[[ -d "$stray" ]] || continue
		stray_name="$(basename "$stray")"
		[[ "$stray_name" == "$project_slug" ]] && continue
		# Claude Code registers project directories for paths it works in — notably git worktrees it
		# manages (--worktree, subagent isolation). Empty ones are harmless scratch artefacts; non-empty
		# ones carry session transcripts and workflow data that belong with the project.
		stray_files="$(find "$stray" -type f -print -quit 2>/dev/null || true)"
		[[ -n "$stray_files" ]] || continue
		is_worktree=""
		if [[ "$stray_name" == "$project_slug"* ]]; then
			# Worktree of the same project: merge back into the base project directory.
			target="$home_path/.claude/projects/$project_slug"
			is_worktree=1
		else
			# Different project entirely: place at its correct location so the data is
			# available when Claude Code is next launched from that path.
			target="$home_path/.claude/projects/$stray_name"
		fi
		# When the target exists, merge with no-clobber. Conflicting files (session items are
		# UUID-named so this is rare — mainly memory files) are saved with a timestamped
		# .worktree suffix so the base project's version wins without losing the worktree's,
		# and repeated conflicts accumulate rather than overwriting each other.
		local conflicts=() failed=() suffix
		suffix="worktree.$(date +%Y%m%dT%H%M%S).$$"
		if [[ -d "$target" ]]; then
			while IFS= read -r -d '' file; do
				local rel="${file#"$stray/"}"
				if [[ -e "$target/$rel" ]]; then
					local dest="$target/$rel.$suffix"
					while [[ -e "$dest" ]]; do dest="$dest.1"; done
					if cp -a "$file" "$dest"; then
						conflicts+=("$rel")
					else
						failed+=("$rel")
					fi
				fi
			done < <(find "$stray" -type f -print0)
			if ! cp -a -n "$stray"/. "$target"/; then
				bubble_error "failed to merge some session data into $(abbreviate_home "$target") — unsaved files will be lost with scratch cleanup"
			fi
		else
			if ! mv "$stray" "$target"; then
				bubble_error "failed to move session data to $(abbreviate_home "$target") — files will be lost with scratch cleanup"
			fi
		fi
		target_display="$(abbreviate_home "$target")"
		if [[ ${#failed[@]} -gt 0 ]]; then
			bubble_error "failed to save ${#failed[@]} conflicting file(s) — worktree versions lost:" \
				"${failed[*]}"
		fi
		if [[ -n "$is_worktree" ]]; then
			[[ ${#conflicts[@]} -gt 0 ]] || continue
			bubble_warn "merged worktree data into $target_display, ${#conflicts[@]} file(s) already existed (saved as *.$suffix):" \
				"${conflicts[*]}"
		elif [[ ${#conflicts[@]} -gt 0 ]]; then
			bubble_warn "merged stray session data into $target_display, ${#conflicts[@]} file(s) already existed (saved as *.$suffix):" \
				"${conflicts[*]}"
		else
			bubble_warn "moved stray session data to $target_display"
		fi
	done
}

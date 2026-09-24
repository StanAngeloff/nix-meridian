# Each session runs in its own transient systemd user scope, and cleanup stops that scope,
# so nothing the session started outlives it.
# The bubble shares the host PID namespace (host `ps` must work), so a process that detaches (setsid, a double fork)
# is otherwise reparented to the user manager and lives on, keeping the bubble's mount namespace and tmpfs home in memory.
# Every descendant inherits the cgroup, and nothing inside the bubble can leave it (/sys is read-only, the user bus is masked),
# which makes the scope the one handle on the whole session.
# lifetime_unit_name is global: it crosses from the before-run hook to the cleanup hook.

lifetime_before_run() {
	lifetime_unit_name=""
	# Launched where the user manager is unreachable (inside another bubble, whose user bus is masked),
	# the session runs unscoped rather than refusing to start.
	# Inside another bubble it still sits in that session's scope, so what it detaches ends with the outer session.
	if ! systemctl --user show-environment >/dev/null 2>&1; then
		bubble_warn "systemd user manager unreachable: processes this session detaches will outlive it"
		return 0
	fi
	# The scratch directory's random suffix is unique among live sessions, so sessions in one project get distinct units.
	lifetime_unit_name="claude-bubble-${scratch_path##*.}"
	launcher_args+=(
		systemd-run --user --scope --quiet --collect
		--unit="$lifetime_unit_name"
		--description="Claude bubble: $(abbreviate_home "$project_path")"
		# Whatever is still running at cleanup is orphaned by definition,
		# so a short grace period keeps one that ignores SIGTERM from holding up the prompt.
		--property=TimeoutStopSec=5s
	)
}

lifetime_cleanup() {
	if [[ -z "${lifetime_unit_name:-}" ]]; then return 0; fi
	local unit_name="$lifetime_unit_name.scope" control_group_path process_id process_name name_list="" noun="processes"
	local -a leftover_names=()
	# Cleared first, so the second cleanup pass returns above.
	lifetime_unit_name=""
	# Once bwrap exits, systemd stops and collects an empty scope by itself; only processes left behind keep it active.
	if ! systemctl --user is-active --quiet "$unit_name"; then return 0; fi
	control_group_path="$(systemctl --user show --property=ControlGroup --value "$unit_name" 2>/dev/null || true)"
	if [[ -n "$control_group_path" && -r "/sys/fs/cgroup$control_group_path/cgroup.procs" ]]; then
		while read -r process_id; do
			leftover_names+=("$(cat "/proc/$process_id/comm" 2>/dev/null || echo unknown)")
		done <"/sys/fs/cgroup$control_group_path/cgroup.procs"
	fi
	if [[ ${#leftover_names[@]} -eq 1 ]]; then noun="process"; fi
	if [[ ${#leftover_names[@]} -gt 0 ]]; then
		while read -r process_name; do
			name_list+="${name_list:+, }$process_name"
		done < <(printf '%s\n' "${leftover_names[@]}" | sort -u)
	fi
	if ! systemctl --user stop "$unit_name" 2>/dev/null; then
		bubble_warn "could not stop $unit_name: ${#leftover_names[@]} leftover $noun still running${name_list:+ ($name_list)}" \
			"stop it by hand: systemctl --user stop $unit_name"
		return 0
	fi
	# Announced only once the stop succeeded, so it never claims a kill that failed,
	# and each session names what it would otherwise have leaked.
	if [[ ${#leftover_names[@]} -gt 0 ]]; then
		bubble_info "stopped ${#leftover_names[@]} leftover $noun: $name_list"
	fi
}

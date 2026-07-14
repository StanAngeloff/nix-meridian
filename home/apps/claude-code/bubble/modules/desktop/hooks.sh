# The bubble shares the host network namespace, so the host X server's abstract socket (@/tmp/.X11-unix/Xn) is reachable inside — only the MIT-MAGIC-COOKIE keeps it shut. The xdg tmpfs mask hides the normal cookie location ($XDG_RUNTIME_DIR/.mutter-Xwaylandauth.*), but a cookie planted under a path the bubble binds through (the project directory, ~/.claude) would grant full X11 access (XTEST input injection, key logging, screen capture). Fail closed if one exists there.
desktop_prepare() {
	local xauth_path="${XAUTHORITY:-}"
	if [[ -n "$xauth_path" ]]; then
		case "$xauth_path" in
		"$home_path/.claude"/* | "$project_path"/*)
			printf '%sclaude-bubble: refusing to launch — XAUTHORITY points inside a bubble-writable path (%s).\nA reachable X cookie + the shared network namespace = full desktop control. Move the cookie out or unset XAUTHORITY.%s\n' "$highlight_on" "$xauth_path" "$highlight_off" >&2
			exit 1
			;;
		esac
	fi
	local suspect
	for suspect in "$project_path/.Xauthority" "$home_path/.claude/.Xauthority"; do
		if [[ -e "$suspect" ]]; then
			printf '%sclaude-bubble: refusing to launch — X authority cookie found at %s (bubble-writable path).\nA reachable X cookie + the shared network namespace = full desktop control. Remove it before launching.%s\n' "$highlight_on" "$suspect" "$highlight_off" >&2
			exit 1
		fi
	done
}

# The bubble is headless unless a narrower module grants one desktop IPC. The xdg mask already hides the Wayland, X11 and D-Bus session sockets, so inherited pointers dangle — unset them so graphical/session clients fail cleanly instead of hanging on an absent socket.
desktop_environment() {
	bwrap_args+=(
		--unsetenv DISPLAY
		--unsetenv XAUTHORITY
		--unsetenv DBUS_SESSION_BUS_ADDRESS
	)
	if [[ -z "${bubble_grants[clipboard]:-}" ]]; then
		bwrap_args+=(--unsetenv WAYLAND_DISPLAY)
	fi
}

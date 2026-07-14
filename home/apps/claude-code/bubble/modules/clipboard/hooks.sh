# Wayland clipboard (on by default). Exposes only the compositor socket; X11 and session D-Bus stay hidden. --without-clipboard revokes, falling back to OSC52.

clipboard_prepare() {
	if [[ -n "${bubble_grants[clipboard]:-}" ]]; then
		clipboard_wayland_display="${WAYLAND_DISPLAY:-wayland-0}"
		if [[ "$clipboard_wayland_display" == /* ]]; then
			clipboard_wayland_socket="$clipboard_wayland_display"
		else
			clipboard_wayland_socket="$xdg_runtime_path/$clipboard_wayland_display"
		fi

		if [[ ! -S "$clipboard_wayland_socket" ]]; then
			echo "${highlight_on}claude-bubble: --with-clipboard requested but $clipboard_wayland_socket does not exist (wl-copy/wl-paste will not reach the compositor)${highlight_off}" >&2
		fi
	fi
}

clipboard_mount() {
	if [[ -n "${bubble_grants[clipboard]:-}" ]]; then
		bwrap_args+=(--ro-bind-try "$clipboard_wayland_socket" "$clipboard_wayland_socket")
	fi
}

clipboard_environment() {
	if [[ -n "${bubble_grants[clipboard]:-}" ]]; then
		bwrap_args+=(
			--setenv WAYLAND_DISPLAY "$clipboard_wayland_display"
			--setenv CLAUDE_BUBBLE_CLIPBOARD 1
		)
	fi
}

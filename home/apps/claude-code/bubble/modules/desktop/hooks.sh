# The bubble is headless. The xdg mask already hides the Wayland, X11 and D-Bus session sockets, so these inherited pointers dangle — unset them so graphical/session clients fail cleanly instead of hanging on an absent socket. A future --with-gui grant would be the inverse: bind the sockets and keep the vars.
desktop_environment() {
	bwrap_args+=(
		--unsetenv DISPLAY
		--unsetenv WAYLAND_DISPLAY
		--unsetenv XAUTHORITY
		--unsetenv DBUS_SESSION_BUS_ADDRESS
	)
}

# Read-only config for CLI tools that Claude Code or its subprocesses invoke.
tools_mount() {
	bwrap_args+=(
		--ro-bind-try "$home_path/.config/ripgrep" "$home_path/.config/ripgrep"
	)
}

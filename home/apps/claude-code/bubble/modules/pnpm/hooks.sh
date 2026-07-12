# Makes pnpm work inside the bubble by giving its store a home on the same mount as the project.
# pnpm hardlinks packages between its content-addressable store and node_modules, and hardlinks cannot cross bubblewrap mount boundaries (they fail with EXDEV), so the store must sit on the project's own mount. The bubble binds only the project and never a shared parent (which would expose sibling repositories), so the store lives inside the project itself at <project>/.pnpm-store. That duplicates packages across repositories, the deliberate cost of keeping the boundary tight.
# The redirect is a shim (placed ahead of the real pnpm on PATH) that injects --store-dir pointing at the default ~/.local/share/pnpm/store path, which is a symlink into the project-local store. pnpm records the path it is handed verbatim rather than its resolved target, so .modules.yaml carries the default store path and an unbubbled host `pnpm install` of the same project agrees without any host-side configuration.
# Active whenever the working directory looks like a JavaScript project (a ./package.json exists); --with-pnpm forces it on for a project without a manifest.

pnpm_prepare() {
	pnpm_active=""
	if [[ -n "${bubble_grants[pnpm]:-}" || -f "$project_path/package.json" ]]; then
		pnpm_active=1
		mkdir -p "$project_path/.pnpm-store"
	fi
}

pnpm_mount() {
	if [[ -n "${pnpm_active:-}" ]]; then
		bwrap_args+=(
			--dir "$home_path/.local/share/pnpm"
			--symlink "$project_path/.pnpm-store" "$home_path/.local/share/pnpm/store"
			--ro-bind "@pnpmShimPathname@" "@pnpmShimPathname@"
		)
	fi
}

pnpm_environment() {
	if [[ -n "${pnpm_active:-}" ]]; then
		bwrap_args+=(--setenv PATH "@pnpmShimPathname@:$PATH")
	fi
}

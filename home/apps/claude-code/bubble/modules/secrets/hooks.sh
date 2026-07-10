# Declarative keyring→env injection: @secretVars@ is the space-separated allowlist substituted at build time (see modules/secrets/module.nix); each name is resolved host-side (the keyring is unreachable in-bubble) and injected only when present.
secrets_environment() {
	local -a inject_names
	local name value
	# Array-read instead of unquoted expansion keeps shellcheck (SC2086) happy at build time.
	read -r -a inject_names <<<"@secretVars@"
	for name in "${inject_names[@]}"; do
		value="$(@secretLookup@ 2>/dev/null || true)"
		if [[ -n "$value" ]]; then bwrap_args+=(--setenv "$name" "$value"); fi
	done
}

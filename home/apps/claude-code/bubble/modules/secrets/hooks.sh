# Declarative keyring→env injection: @keyringVariables@ is the space-separated allowlist substituted at build time (see modules/secrets/module.nix); each name is resolved host-side (the keyring is unreachable in-bubble) and injected only when present.
secrets_environment() {
	local -a inject_names
	local name value
	# Array-read instead of unquoted expansion keeps shellcheck (SC2086) happy at build time.
	read -r -a inject_names <<<"@keyringVariables@"
	for name in "${inject_names[@]}"; do
		value="$(@secretLookup@ 2>/dev/null || true)"
		# GH_TOKEN fallback: keyring PAT absent → gh's own OAuth token (stored in its keyring entry, resolved via `gh auth token` which runs host-side here, before bwrap hides the credential).
		# Captured once at launch and frozen via --setenv: unlike the old static PAT, a gh OAuth token can be rotated (gh auth refresh, expiry) — if that happens mid-session the in-bubble GH_TOKEN goes stale until the next launch.
		if [[ -z "$value" && "$name" == "GH_TOKEN" ]]; then
			value="$(gh auth token 2>/dev/null || true)"
		fi
		if [[ -n "$value" ]]; then bwrap_args+=(--setenv "$name" "$value"); fi
	done
}

profiles_prepare() {
	profiles_path="$home_path/.claude/profiles"
	profiles_active_name=""

	if [[ ! -d "$profiles_path" ]]; then return; fi

	local target
	target="$(readlink "$profiles_path/active" 2>/dev/null || true)"
	if [[ -z "$target" ]]; then return; fi
	if [[ ! -f "$profiles_path/$target" ]]; then return; fi

	profiles_active_name="${target%.json}"
}

# Both accounts' OAuth tokens live under here; nothing inside the bubble needs them
# (this handler and the hooks below all run host-side, before bwrap starts).
profiles_mount() {
	bwrap_args+=(--tmpfs "$profiles_path")
}

profiles_before_run() {
	if [[ -z "${profiles_active_name:-}" ]]; then return; fi

	local profile_file="$profiles_path/${profiles_active_name}.json"
	if ! jq -e . "$profile_file" >/dev/null 2>&1; then return; fi

	local email subscription organization label
	email="$(jq -r '.oauthAccount.emailAddress // "unknown"' "$profile_file")"
	subscription="$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' "$profile_file")"
	organization="$(jq -r '.oauthAccount.organizationName // empty' "$profile_file")"
	label="$(echo "$profiles_active_name" | tr '[:lower:]' '[:upper:]')"

	local cyan_on="" cyan_off=""
	if [[ -t 2 ]]; then
		cyan_on=$'\033[1;36m'
		cyan_off=$'\033[0m'
	fi

	if [[ -n "$organization" ]]; then
		echo "${cyan_on}  🪪 ${label}  ·  ${email}  ·  ${subscription} (${organization})${cyan_off}" >&2
	else
		echo "${cyan_on}  🪪 ${label}  ·  ${email}  ·  ${subscription}${cyan_off}" >&2
	fi
	echo "" >&2
}

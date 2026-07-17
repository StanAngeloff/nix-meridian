profiles_prepare() {
	profiles_dir="$home_path/.claude/profiles"
	profiles_cred_file="$home_path/.claude/.credentials.json"
	profiles_config_file="$home_path/.claude/.claude.json"
	profiles_active_name=""

	if [[ ! -d "$profiles_dir" ]]; then return; fi

	local target
	target="$(readlink "$profiles_dir/active" 2>/dev/null || true)"
	if [[ -z "$target" ]]; then
		echo "${highlight_on}claude-bubble: profiles directory exists but no active profile.${highlight_off}" >&2
		echo "  run: cc profiles migrate <name>" >&2
		echo "    or: cc profiles select <name>" >&2
		exit 1
	fi

	local profile_file="$profiles_dir/$target"
	if [[ ! -f "$profile_file" ]]; then
		echo "${highlight_on}claude-bubble: active profile points to missing file: $target${highlight_off}" >&2
		echo "  run: cc profiles select <name>" >&2
		exit 1
	fi

	profiles_active_name="${target%.json}"

	local oauth tmp
	oauth="$(jq -c '.claudeAiOauth' "$profile_file")"

	tmp="$(mktemp "$profiles_cred_file.tmp.XXXXXX")"
	jq --argjson oauth "$oauth" '.claudeAiOauth = $oauth' "$profiles_cred_file" >"$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$profiles_cred_file"

	local account
	account="$(jq -c '.oauthAccount // empty' "$profile_file")"
	if [[ -n "$account" ]]; then
		tmp="$(mktemp "$profiles_config_file.tmp.XXXXXX")"
		jq --argjson acct "$account" '.oauthAccount = $acct' "$profiles_config_file" >"$tmp"
		chmod 600 "$tmp"
		mv "$tmp" "$profiles_config_file"
	fi
}

profiles_before_run() {
	if [[ -z "${profiles_active_name:-}" ]]; then return; fi

	local profile_file="$profiles_dir/${profiles_active_name}.json"
	local email sub org label
	email="$(jq -r '.oauthAccount.emailAddress // "unknown"' "$profile_file")"
	sub="$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' "$profile_file")"
	org="$(jq -r '.oauthAccount.organizationName // empty' "$profile_file")"
	label="$(echo "$profiles_active_name" | tr '[:lower:]' '[:upper:]')"

	local cyan_on="" cyan_off=""
	if [[ -t 2 ]]; then
		cyan_on=$'\033[1;36m'
		cyan_off=$'\033[0m'
	fi

	if [[ -n "$org" ]]; then
		echo "${cyan_on}  🪪 ${label}  ·  ${email}  ·  ${sub} (${org})${cyan_off}" >&2
	else
		echo "${cyan_on}  🪪 ${label}  ·  ${email}  ·  ${sub}${cyan_off}" >&2
	fi
	echo "" >&2
}

profiles_after_run() {
	if [[ -z "${profiles_active_name:-}" ]]; then return; fi

	local profile_file="$profiles_dir/active"
	if [[ ! -L "$profile_file" ]]; then return; fi

	local oauth account
	oauth="$(jq -c '.claudeAiOauth // empty' "$profiles_cred_file" 2>/dev/null || true)"
	account="$(jq -c '.oauthAccount // empty' "$profiles_config_file" 2>/dev/null || true)"

	if [[ -n "$oauth" ]]; then
		jq -n --argjson claudeAiOauth "$oauth" --argjson oauthAccount "${account:-null}" \
			'{claudeAiOauth: $claudeAiOauth, oauthAccount: $oauthAccount}' >"$profile_file"
		chmod 600 "$profile_file"
	fi
}

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

	# A banner rather than a message, so it skips the launcher's prefix: it answers "who am I about to spend tokens as", and it is the last thing on screen before Claude Code's own interface takes over. Bold carries the profile name alone; the account details after it stay plain, like every other message body. bubble_off is empty exactly when the shared policy decided against colour, so this reuses that decision rather than testing the terminal again.
	local banner_on="" banner_off=""
	if [[ -n "$bubble_off" ]]; then
		banner_on=$'\033[1;36m'
		banner_off="$bubble_off"
	fi

	if [[ -n "$organization" ]]; then
		echo "  ${banner_on}🪪 ${label}${banner_off}  ·  ${email}  ·  ${subscription} (${organization})" >&2
	else
		echo "  ${banner_on}🪪 ${label}${banner_off}  ·  ${email}  ·  ${subscription}" >&2
	fi
	echo "" >&2
}

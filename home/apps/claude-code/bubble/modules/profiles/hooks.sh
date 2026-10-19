# Which account a session runs as. Each profile is a directory under ~/.claude/profiles holding one account's
# credentials/ and .claude.json (profiles.sh beside this file). The session's own profile is bound at profiles/active,
# which the shared ~/.claude/.claude.json links into, and Claude Code finds its credentials there through
# CLAUDE_SECURESTORAGE_CONFIG_DIR. Every other profile stays hidden under a tmpfs.
# profiles_path, profiles_name and profiles_is_nested cross from prepare to the later phases;
# lifetime_slice_name crosses to the lifetime module's before-run hook.

profiles_prepare() {
	profiles_path="$home_path/.claude/profiles"
	profiles_name=""
	profiles_is_nested=""
	local target variable_name

	if [[ -n "${CLAUDE_BUBBLE:-}" && -n "${CLAUDE_BUBBLE_PROFILE:-}" ]]; then
		# A session started inside another runs on its parent's profile: the parent's slot is already bound here,
		# and the variables naming it pass through the environment.
		# Both variables are required, so that a stray CLAUDE_BUBBLE_PROFILE outside a bubble cannot skip the mask and the check.
		profiles_is_nested=1
		if [[ -n "$bubble_profile_name" && "$bubble_profile_name" != "$CLAUDE_BUBBLE_PROFILE" ]]; then
			bubble_error "a session inside another keeps its profile ($CLAUDE_BUBBLE_PROFILE)"
			exit 1
		fi
	else
		target="$(readlink "$profiles_path/active" 2>/dev/null || true)"
		if [[ -z "$target" || "$target" == *.json ]]; then
			if [[ -n "$bubble_profile_name" ]]; then
				bubble_error "--profile needs one directory per profile" \
					"close every session, then run: cc profiles migrate"
				exit 1
			fi
			if [[ -n "$target" ]]; then
				bubble_info "profiles still run one account at a time: close every session, then run cc profiles migrate"
			fi
			return 0
		fi
		profiles_name="${bubble_profile_name:-$target}"
		if [[ ! "$profiles_name" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ || "$profiles_name" == active ||
			-L "$profiles_path/$profiles_name" || ! -d "$profiles_path/$profiles_name/credentials" ]]; then
			bubble_error "no profile named '$profiles_name'" "see: cc profiles list"
			exit 1
		fi
	fi

	# A login handed to Claude Code through its environment replaces the profile's own. Claude Code cannot tell its
	# subscription type and treats it as an organization account's, so the session would read the organization settings
	# every profile shares (see _profile_is_organization in profiles.sh).
	for variable_name in CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR CLAUDE_CODE_OAUTH_REFRESH_TOKEN; do
		if [[ -n "${!variable_name:-}" ]]; then
			bubble_error "$variable_name is set, and would replace the profile's own login" \
				"unset it first: unset $variable_name"
			exit 1
		fi
	done
	if [[ -n "$profiles_is_nested" ]]; then
		return 0
	fi

	if ! "@profilesHandler@" check; then
		bubble_error "refusing to start a session until cc profiles check passes"
		exit 1
	fi
	# Files the session's scope under its profile, which is how `cc profiles list` and `remove` see running sessions.
	lifetime_slice_name="claude-profile-$(systemd-escape -- "$profiles_name").slice"
}

profiles_mount() {
	# A nested session already sees only its parent's profile; covering it again would hide the parent's credentials.
	if [[ -n "$profiles_is_nested" ]]; then
		return 0
	fi
	# Every profile's tokens stay hidden; only this session's profile is bound back, at profiles/active.
	bwrap_args+=(--tmpfs "$profiles_path")
	if [[ -n "$profiles_name" ]]; then
		bwrap_args+=(--bind "$profiles_path/$profiles_name" "$profiles_path/active")
	fi
}

profiles_environment() {
	if [[ -z "$profiles_name" ]]; then
		return 0
	fi
	bwrap_args+=(
		--setenv CLAUDE_SECURESTORAGE_CONFIG_DIR "$profiles_path/active/credentials"
		--setenv CLAUDE_BUBBLE_PROFILE "$profiles_name"
	)
}

profiles_before_run() {
	if [[ -z "$profiles_name" ]]; then
		return 0
	fi
	local profile_path="$profiles_path/$profiles_name" email subscription organization label
	email="$(jq -r '.oauthAccount.emailAddress // "not logged in"' "$profile_path/.claude.json" 2>/dev/null || echo "not logged in")"
	# Leaves out the organization named after a personal account, as _profile_label in profiles.sh does.
	organization="$(jq -r --arg personal_suffix "'s Organization" \
		'.oauthAccount | select(.organizationName != .emailAddress + $personal_suffix) | .organizationName // empty' \
		"$profile_path/.claude.json" 2>/dev/null || true)"
	subscription="$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' "$profile_path/credentials/.credentials.json" 2>/dev/null || echo unknown)"
	label="$(echo "$profiles_name" | tr '[:lower:]' '[:upper:]')"

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

set -euo pipefail

config_path="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
profiles_path="$config_path/profiles"
credentials_file="$config_path/.credentials.json"
config_file="$config_path/.claude.json"

# Unlike the launcher this command leaves bubble_prefix empty, so the severity word leads and results print bare — see utilities/log.sh.

# First argument is the message, any further ones are continuation lines.
_profile_die() {
	bubble_error "$@"
	exit 1
}

_profile_check_not_running() {
	local pids
	pids="$(pgrep -u "$(id -un)" -f '(claude-unwrapped|/bin/claude( |$))' 2>/dev/null || true)"
	if [[ -n "$pids" ]]; then
		_profile_die "Claude Code is running (PIDs: $(echo "$pids" | tr '\n' ' ' | sed 's/ *$//'))" \
			"close all sessions before managing profiles"
	fi
}

_profile_active_profile_name() {
	local target
	target="$(readlink "$profiles_path/active" 2>/dev/null || true)"
	if [[ -z "$target" ]]; then return 1; fi
	echo "${target%.json}"
}

_profile_capture_profile() {
	local destination_file="$1"
	local oauth account temporary_file
	oauth="$(jq -c '.claudeAiOauth // empty' "$credentials_file")"
	if [[ -z "$oauth" ]]; then
		_profile_die "no claudeAiOauth in $credentials_file — not logged in?"
	fi
	account="$(jq -c '.oauthAccount // empty' "$config_file")"
	temporary_file="$(mktemp "$destination_file.tmp.XXXXXX")"
	jq -n --argjson claudeAiOauth "$oauth" --argjson oauthAccount "${account:-null}" \
		'{claudeAiOauth: $claudeAiOauth, oauthAccount: $oauthAccount}' >"$temporary_file"
	chmod 600 "$temporary_file"
	mv "$temporary_file" "$destination_file"
}

# Identity of the account a live-credentials or profile-store file belongs to, for
# comparing "who's actually logged in" against "who the profile store thinks is logged in".
_profile_account_identity() {
	jq -r '.oauthAccount.accountUuid // .oauthAccount.emailAddress // empty' "$1" 2>/dev/null || true
}

# Snapshot the outgoing profile before switching away from it, but only when doing so is safe:
# skip (with a warning, not a hard failure) if nothing is logged in, or if the live account
# doesn't match what the profile is supposed to hold — overwriting would destroy the other
# account's only token copy instead of switching to it.
_profile_capture_outgoing() {
	local outgoing="$1"
	[[ -n "$outgoing" && -f "$profiles_path/$outgoing.json" ]] || return 0
	local live_oauth
	live_oauth="$(jq -c '.claudeAiOauth // empty' "$credentials_file" 2>/dev/null || true)"
	[[ -n "$live_oauth" ]] || return 0
	local live_id stored_id
	live_id="$(_profile_account_identity "$config_file")"
	stored_id="$(_profile_account_identity "$profiles_path/$outgoing.json")"
	if [[ -n "$live_id" && -n "$stored_id" && "$live_id" != "$stored_id" ]]; then
		bubble_warn "live account does not match profile '$outgoing' — skipping snapshot" \
			"overwriting it would destroy the other account's only copy of its tokens"
		return 0
	fi
	_profile_capture_profile "$profiles_path/$outgoing.json"
}

_profile_restore_profile() {
	local source_file="$1"
	local oauth temporary_file account
	oauth="$(jq -c '.claudeAiOauth // empty' "$source_file")"
	if [[ -z "$oauth" ]]; then
		_profile_die "profile '$source_file' has no claudeAiOauth — corrupt?"
	fi

	temporary_file="$(mktemp "$credentials_file.tmp.XXXXXX")"
	jq --argjson oauth "$oauth" '.claudeAiOauth = $oauth' "$credentials_file" >"$temporary_file"
	[[ -s "$temporary_file" ]] || _profile_die "failed to update $credentials_file"
	chmod 600 "$temporary_file"
	mv "$temporary_file" "$credentials_file"

	account="$(jq -c '.oauthAccount // empty' "$source_file")"
	if [[ -n "$account" ]]; then
		temporary_file="$(mktemp "$config_file.tmp.XXXXXX")"
		jq --argjson account "$account" '.oauthAccount = $account' "$config_file" >"$temporary_file"
		[[ -s "$temporary_file" ]] || _profile_die "failed to update $config_file"
		chmod 600 "$temporary_file"
		mv "$temporary_file" "$config_file"
	fi
}

_profile_valid_name() {
	[[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]
}

_profile_profile_label() {
	local file="$1"
	local email subscription organization
	email="$(jq -r '.oauthAccount.emailAddress // "unknown"' "$file")"
	subscription="$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' "$file")"
	organization="$(jq -r '.oauthAccount.organizationName // empty' "$file")"
	if [[ -n "$organization" ]]; then
		printf '%s (%s, %s)' "$email" "$subscription" "$organization"
	else
		printf '%s (%s)' "$email" "$subscription"
	fi
}

_profile_cmd_migrate() {
	local name="${1:-}"
	if [[ -z "$name" ]]; then
		_profile_die "profile name required" \
			"usage: cc profiles migrate <name>"
	fi
	if ! _profile_valid_name "$name"; then
		_profile_die "invalid profile name: $name"
	fi
	local profile_file="$profiles_path/$name.json"
	if [[ -f "$profile_file" ]]; then
		_profile_die "profile '$name' already exists"
	fi
	if _profile_active_profile_name >/dev/null; then
		_profile_die "a profile is already active" \
			"run 'cc profiles add <name>' to add another account"
	fi

	mkdir -p "$profiles_path"
	_profile_capture_profile "$profile_file"
	ln -sfn "$name.json" "$profiles_path/active"

	local label
	label="$(_profile_profile_label "$profile_file")"
	printf '%smigrated:%s %s\n' "$bubble_family_on" "$bubble_off" "$label" >&2
	printf '%sactive profile:%s %s\n' "$bubble_family_on" "$bubble_off" "$name" >&2
}

_profile_cmd_list() {
	if [[ ! -d "$profiles_path" ]]; then
		bubble_info "no profiles yet — run: cc profiles migrate <name>"
		exit 0
	fi
	local active
	active="$(_profile_active_profile_name || true)"
	local found=0
	for file in "$profiles_path"/*.json; do
		[[ -f "$file" ]] || continue
		found=1
		local name label marker
		name="$(basename "$file" .json)"
		label="$(_profile_profile_label "$file")"
		marker="  "
		if [[ "$name" == "$active" ]]; then marker="* "; fi
		printf '  %s%s%s%s  %s\n' "$marker" "$bubble_family_on" "$name" "$bubble_off" "$label" >&2
	done
	if [[ $found -eq 0 ]]; then
		bubble_info "no profiles yet — run: cc profiles migrate <name>"
	fi
}

_profile_cmd_which() {
	local name
	name="$(_profile_active_profile_name)" || _profile_die "no active profile"
	local profile_file="$profiles_path/$name.json"
	if [[ ! -f "$profile_file" ]]; then
		_profile_die "active profile '$name' points to missing file"
	fi
	local email
	email="$(jq -r '.oauthAccount.emailAddress // "unknown"' "$profile_file")"
	echo "$name $email"
}

_profile_cmd_select() {
	local name="${1:-}"
	if [[ -z "$name" ]]; then
		_profile_die "profile name required" \
			"usage: cc profiles select <name>"
	fi
	local profile_file="$profiles_path/$name.json"
	if [[ ! -f "$profile_file" ]]; then
		_profile_die "profile '$name' does not exist" \
			"run 'cc profiles list' to see the available profiles"
	fi
	_profile_check_not_running

	_profile_capture_outgoing "$(_profile_active_profile_name || true)"
	_profile_restore_profile "$profile_file"
	ln -sfn "$name.json" "$profiles_path/active"

	local label
	label="$(_profile_profile_label "$profile_file")"
	printf '%sactive profile:%s %s  %s\n' "$bubble_family_on" "$bubble_off" "$name" "$label" >&2
}

_profile_cmd_remove() {
	local name="${1:-}"
	if [[ -z "$name" ]]; then
		_profile_die "profile name required" \
			"usage: cc profiles remove <name>"
	fi
	if ! _profile_valid_name "$name"; then
		_profile_die "invalid profile name: $name"
	fi
	local profile_file="$profiles_path/$name.json"
	if [[ ! -f "$profile_file" ]]; then
		_profile_die "profile '$name' does not exist"
	fi
	local active
	active="$(_profile_active_profile_name || true)"
	if [[ "$name" == "$active" ]]; then
		_profile_die "cannot remove the active profile" \
			"switch away from it first: cc profiles select <other>"
	fi
	rm "$profile_file"
	printf '%sremoved:%s %s\n' "$bubble_family_on" "$bubble_off" "$name" >&2
}

_profile_cmd_add() {
	local name="${1:-}"
	if [[ -z "$name" ]]; then
		_profile_die "profile name required" \
			"usage: cc profiles add <name>"
	fi
	if ! _profile_valid_name "$name"; then
		_profile_die "invalid profile name: $name"
	fi
	shift
	local profile_file="$profiles_path/$name.json"
	if [[ -f "$profile_file" ]]; then
		_profile_die "profile '$name' already exists"
	fi
	_profile_check_not_running

	local outgoing
	outgoing="$(_profile_active_profile_name || true)"
	if [[ -z "$outgoing" || ! -f "$profiles_path/$outgoing.json" ]]; then
		_profile_die "no active profile to preserve" \
			"run 'cc profiles migrate <name>' first"
	fi
	_profile_capture_outgoing "$outgoing"

	# Covers explicit exit below and any other termination (signal, set -e) while credentials
	# are mid-swap; disarmed once the new account's tokens are safely saved to a profile.
	_profile_restore_on_abort() {
		_profile_restore_profile "$profiles_path/$outgoing.json"
	}
	trap _profile_restore_on_abort EXIT

	local temporary_file
	temporary_file="$(mktemp "$credentials_file.tmp.XXXXXX")"
	jq 'del(.claudeAiOauth)' "$credentials_file" >"$temporary_file"
	chmod 600 "$temporary_file"
	mv "$temporary_file" "$credentials_file"

	bubble_info "launching the Claude Code auth flow" \
		"complete the login in your browser, then exit Claude Code"
	echo "" >&2

	claude auth login "$@" || true

	local new_oauth
	new_oauth="$(jq -c '.claudeAiOauth // empty' "$credentials_file" 2>/dev/null || true)"
	if [[ -z "$new_oauth" ]]; then
		echo "" >&2
		bubble_error "auth did not complete — restoring the previous credentials"
		exit 1
	fi

	trap - EXIT

	_profile_capture_profile "$profile_file"
	ln -sfn "$name.json" "$profiles_path/active"

	echo "" >&2
	local label
	label="$(_profile_profile_label "$profile_file")"
	printf '%ssaved:%s %s  %s\n' "$bubble_family_on" "$bubble_off" "$name" "$label" >&2
	printf '%sactive profile:%s %s\n' "$bubble_family_on" "$bubble_off" "$name" >&2
}

_profile_usage() {
	cat >&2 <<'USAGE'
Usage: cc profiles <command> [args]

Commands:
  migrate <name>    Capture current credentials as a named profile
  add <name>        Authenticate a new account and save as a profile
  list              List all profiles
  which             Print the active profile name and email
  select <name>     Switch the active profile
  remove <name>     Delete a profile
USAGE
	exit 1
}

case "${1:-}" in
migrate)
	shift
	_profile_cmd_migrate "$@"
	;;
add)
	shift
	_profile_cmd_add "$@"
	;;
list)
	shift
	_profile_cmd_list
	;;
which)
	shift
	_profile_cmd_which
	;;
select)
	shift
	_profile_cmd_select "$@"
	;;
remove)
	shift
	_profile_cmd_remove "$@"
	;;
*) _profile_usage ;;
esac

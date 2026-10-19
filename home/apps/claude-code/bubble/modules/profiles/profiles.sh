set -euo pipefail

# Account profiles. Each profile is a directory, profiles/<name>/, holding one account's credentials/.credentials.json
# and its .claude.json. The shared ~/.claude/.claude.json links profiles/active/.claude.json, and profiles/active links
# the default profile on the host and is the session's own profile inside a bubble (see hooks.sh beside this file).
# Sessions of one profile share its directory, which is what lets Claude Code's refresh lock coordinate their refreshes.
# Everything else in ~/.claude is shared, the server caches included: see _profile_is_organization.

config_path="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
profiles_path="$config_path/profiles"
active_link="$profiles_path/active"
shared_config_file="$config_path/.claude.json"
shared_credentials_file="$config_path/.credentials.json"
backup_path="$profiles_path/.v2-backup"

# Keys of .claude.json that describe one account. A profile seeded from another profile's copy starts without them,
# and Claude Code fetches its own on first launch.
account_scoped_keys=(
	oauthAccount
	cachedDynamicConfigs
	cachedExtraUsageDisabledReason
	cachedGrowthBookFeatures
	cachedStatsigGates
	claudeAiMcpEverConnected
	groveConfigCache
	overageCreditGrantCache
	passesEligibilityCache
	passesLastSeenRemaining
	penguinModeOrgEnabled
	s1mAccessCache
	s1mNonSubscriberAccessCache
)

# claude-bubble's subcommand dispatch names itself here, so `add` can run the login in a bubble on the new profile.
bubble_command="${CLAUDE_BUBBLE_COMMAND:-claude-bubble}"
# Hands the login page to the host browser from inside that bubble.
www_browser="@wwwBrowser@"
# The proofs the layout rests on, run against the installed Claude Code; see verify.sh beside this file.
verify_command="@profilesVerify@"

# Unlike the launcher this command leaves bubble_prefix empty, so the severity word leads and results print bare — see utilities/log.sh.

# First argument is the message, any further ones are continuation lines.
_profile_die() {
	bubble_error "$@"
	exit 1
}

# Names become directory names and a systemd slice name; "active" belongs to the link.
_profile_valid_name() {
	[[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ && "$1" != active ]]
}

# slot when profiles/active links a profile directory, v2 when it links a <name>.json token file (the layout that ran
# one account at a time), none when there are no profiles.
_profile_layout() {
	local target
	target="$(readlink "$active_link" 2>/dev/null || true)"
	if [[ -z "$target" ]]; then
		echo none
	elif [[ "$target" == *.json ]]; then
		echo v2
	else
		echo slot
	fi
}

_profile_default_name() {
	local target
	target="$(readlink "$active_link" 2>/dev/null || true)"
	echo "${target%.json}"
}

_profile_exists() {
	_profile_valid_name "$1" && [[ ! -L "$profiles_path/$1" && -d "$profiles_path/$1/credentials" ]]
}

# Every profile directory, by name; the active link and the hidden backup are not profiles.
_profile_names() {
	local directory
	for directory in "$profiles_path"/*/; do
		directory="${directory%/}"
		if [[ ! -L "$directory" && -d "$directory/credentials" ]]; then
			basename "$directory"
		fi
	done
}

# The account a .claude.json belongs to, for messages.
_profile_file_account() {
	jq -r '.oauthAccount.emailAddress // "an unknown account"' "$1" 2>/dev/null || echo "an unknown account"
}

# Whether a profile's stored login is an organization account: subscription type team or enterprise, or none recorded.
# Every profile shares the server caches in ~/.claude, an organization's managed settings (remote-settings.json) and
# policy limits (policy-limits.json) among them. Claude Code reads them only for such a login, and a personal Max or Pro
# login never opens them, so they stay that organization's as long as at most one profile is one.
# A profile without a stored login is neither.
_profile_is_organization() {
	jq -e '.claudeAiOauth
		| if type == "object" and ((.accessToken // "") != "" or (.refreshToken // "") != "")
		  then .subscriptionType == null or .subscriptionType == "team" or .subscriptionType == "enterprise"
		  else false end' \
		"$profiles_path/$1/credentials/.credentials.json" >/dev/null 2>&1
}

# The profiles whose stored login is an organization account, one name per line.
_profile_organization_names() {
	local name
	while read -r name; do
		if _profile_is_organization "$name"; then
			echo "$name"
		fi
	done < <(_profile_names)
}

# The layout's invariants. The bubble runs this before every session and Home Manager's activation before every switch,
# and both refuse to go on when it fails. On an older layout it only prints a note.
_profile_cmd_check() {
	local layout default_name target name_list status=0
	local -a problems=() organization_names=()
	layout="$(_profile_layout)"
	if [[ "$layout" == v2 ]]; then
		bubble_info "profiles still use the layout that runs one account at a time" \
			"close every session, then run: cc profiles migrate"
	fi
	if [[ "$layout" != slot ]]; then
		return 0
	fi

	default_name="$(_profile_default_name)"
	if ! _profile_exists "$default_name" || [[ ! -f "$profiles_path/$default_name/.claude.json" ]]; then
		problems+=("$active_link links '$default_name', which is not a profile with credentials/ and .claude.json")
	fi
	target="$(readlink "$shared_config_file" 2>/dev/null || true)"
	if [[ "$target" != profiles/active/.claude.json ]]; then
		if [[ -f "$shared_config_file" && ! -L "$shared_config_file" ]]; then
			problems+=("$shared_config_file is a regular file holding $(_profile_file_account "$shared_config_file"); a writer replaced the link into profiles/active")
		else
			problems+=("$shared_config_file must link profiles/active/.claude.json")
		fi
	fi
	if [[ -e "$shared_credentials_file" || -L "$shared_credentials_file" ]]; then
		problems+=("$shared_credentials_file exists; each profile keeps its tokens in profiles/<name>/credentials/")
	fi
	if [[ ${#problems[@]} -gt 0 ]]; then
		bubble_error "the profile layout is damaged:" "${problems[@]}" "" \
			"move each stray file into the profile it belongs to, then run: cc profiles migrate"
		status=1
	fi

	mapfile -t organization_names < <(_profile_organization_names)
	if [[ ${#organization_names[@]} -gt 1 ]]; then
		name_list="$(printf "'%s', " "${organization_names[@]}")"
		bubble_error "profiles ${name_list%, } are organization accounts (Team, Enterprise, or no subscription type)" \
			"every profile reads the same cached organization settings, so at most one may be an organization account" \
			"remove all but one with: cc profiles remove <name> (the default cannot be removed: cc profiles select another first)"
		status=1
	fi
	return "$status"
}

# Writes jq's output beside the destination and renames it into place, mode 600, so no reader sees half a file.
_profile_write_json() {
	local destination_file="$1" temporary_file
	shift
	temporary_file="$(mktemp "$destination_file.XXXXXX")"
	if ! jq "$@" >"$temporary_file" || [[ ! -s "$temporary_file" ]]; then
		rm -f -- "${temporary_file:?}"
		_profile_die "could not write $destination_file"
	fi
	chmod 600 "$temporary_file"
	mv -T -- "$temporary_file" "$destination_file"
}

# Points a link at its target in one rename, so a reader never finds the path missing.
_profile_link() {
	local target="$1" link_path="$2" temporary_link
	temporary_link="$(dirname "$link_path")/.$(basename "$link_path").$$"
	ln -sfn -- "$target" "$temporary_link"
	mv -T -- "$temporary_link" "$link_path"
}

# Queries of the running machine are functions, so the tests can stand in for them.

# PIDs of running Claude Code processes, bubbled or not, one per line.
_profile_claude_process_ids() {
	pgrep -u "$(id -un)" -f '(claude-unwrapped|/bin/claude( |$))' 2>/dev/null || true
}

# Whether a process runs in a bubble session's systemd scope (bubble/modules/lifetime); a nested bubble runs in its parent's.
_profile_process_is_bubbled() {
	grep -q '/claude-bubble-[^/]*\.scope' "/proc/$1/cgroup" 2>/dev/null
}

# One line per running bubble session, naming the profile its scope's slice was given at launch (bubble/modules/profiles).
# Fails when the user manager cannot be asked, so callers refuse rather than guess.
_profile_session_profiles() {
	local unit_name slice_name
	systemctl --user show-environment >/dev/null 2>&1 || return 1
	while read -r unit_name _; do
		slice_name="$(systemctl --user show --property=Slice --value "$unit_name" 2>/dev/null || true)"
		if [[ "$slice_name" == claude-profile-*.slice ]]; then
			slice_name="${slice_name#claude-profile-}"
			systemd-escape --unescape -- "${slice_name%.slice}"
		fi
	done < <(systemctl --user list-units --type=scope --state=active --plain --no-legend 'claude-bubble-*.scope' 2>/dev/null || true)
}

_profile_refuse_inside_bubble() {
	if [[ -n "${CLAUDE_BUBBLE:-}" ]]; then
		_profile_die "cc profiles $1 runs on the host, outside any session" \
			"a session sees only its own profile"
	fi
}

_profile_refuse_while_claude_runs() {
	local process_id process_ids=""
	while read -r process_id; do
		if [[ -n "$process_id" ]]; then
			process_ids+="${process_ids:+ }$process_id"
		fi
	done < <(_profile_claude_process_ids)
	if [[ -n "$process_ids" ]]; then
		_profile_die "Claude Code is running (PIDs: $process_ids)" "close every session first"
	fi
}

# Bubbled sessions keep the profile they bound at launch; a session outside the bubble follows profiles/active live.
_profile_refuse_while_unbubbled_claude_runs() {
	local process_id process_ids=""
	while read -r process_id; do
		if [[ -n "$process_id" ]] && ! _profile_process_is_bubbled "$process_id"; then
			process_ids+="${process_ids:+ }$process_id"
		fi
	done < <(_profile_claude_process_ids)
	if [[ -n "$process_ids" ]]; then
		_profile_die "Claude Code is running outside the bubble (PIDs: $process_ids)" \
			"it follows the default profile as that changes; close it first"
	fi
}

_profile_require_slot() {
	if [[ "$(_profile_layout)" != slot ]]; then
		_profile_die "profiles still use the layout that runs one account at a time" \
			"close every session, then run: cc profiles migrate"
	fi
}

# $1 is the command, for the usage line; $2 the name it was given.
_profile_require_name() {
	if [[ -z "$2" ]]; then
		_profile_die "profile name required" "usage: cc profiles $1 <name>"
	fi
	_profile_valid_name "$2" || _profile_die "invalid profile name: $2"
}

_profile_label() {
	local profile_path="$profiles_path/$1" email subscription organization
	email="$(jq -r '.oauthAccount.emailAddress // "not logged in"' "$profile_path/.claude.json" 2>/dev/null || echo "not logged in")"
	# Claude.ai names a personal account's own organization after its email; that name repeats the email, so it is left out.
	organization="$(jq -r --arg personal_suffix "'s Organization" \
		'.oauthAccount | select(.organizationName != .emailAddress + $personal_suffix) | .organizationName // empty' \
		"$profile_path/.claude.json" 2>/dev/null || true)"
	subscription="$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' "$profile_path/credentials/.credentials.json" 2>/dev/null || echo unknown)"
	if [[ -n "$organization" ]]; then
		printf '%s (%s, %s)' "$email" "$subscription" "$organization"
	else
		printf '%s (%s)' "$email" "$subscription"
	fi
}

# A profile's .claude.json from another profile's copy: the shared state carries over, the account's own keys do not.
# account_json is the account to record, or null to leave it for a login to fill in.
_profile_seed_config() {
	local source_file="$1" destination_file="$2" account_json="$3" keys_json
	keys_json="$(printf '%s\n' "${account_scoped_keys[@]}" | jq -R . | jq -s -c .)"
	# shellcheck disable=SC2016 # A jq program: $keys and $account are its variables.
	_profile_write_json "$destination_file" --argjson keys "$keys_json" --argjson account "$account_json" \
		'reduce $keys[] as $key (.; del(.[$key])) | if $account == null then . else .oauthAccount = $account end' \
		"$source_file"
}

# Copies of every file the migration replaces, kept until deleted by hand.
# Nothing reads them, so their tokens cannot conflict with the live ones; they only go stale.
_profile_backup() {
	local staging_path="$backup_path.partial.$$" file
	if [[ -d "$backup_path" ]]; then
		return 0
	fi
	(umask 077 && mkdir -p "$staging_path")
	for file in "$profiles_path"/*.json "$shared_credentials_file" "$shared_config_file"; do
		if [[ -f "$file" && ! -L "$file" ]]; then
			cp -p -- "$file" "$staging_path/"
		fi
	done
	mv -T -- "$staging_path" "$backup_path"
}

# The account logged in now becomes the profile named for it: its live tokens are the freshest copy there is.
_profile_seed_from_live() {
	local profile_path="$profiles_path/$1"
	(umask 077 && mkdir -p "$profile_path/credentials")
	if [[ ! -f "$profile_path/credentials/.credentials.json" ]]; then
		if [[ ! -f "$shared_credentials_file" || -L "$shared_credentials_file" ]]; then
			_profile_die "no live credentials to move into profile '$1'" "log in first with: claude auth login"
		fi
		_profile_write_json "$profile_path/credentials/.credentials.json" . "$shared_credentials_file"
	fi
	if [[ ! -f "$profile_path/.claude.json" ]]; then
		if [[ ! -f "$shared_config_file" || -L "$shared_config_file" ]]; then
			_profile_die "no live .claude.json to copy into profile '$1'"
		fi
		_profile_write_json "$profile_path/.claude.json" . "$shared_config_file"
	fi
}

# Each parked profile of the older layout: its stored tokens plus the MCP tokens every account shared until now,
# and a .claude.json seeded from the default profile's copy, with its own account.
_profile_seed_v2_others() {
	local default_name="$1" token_file name profile_path mcp_json account_json
	mcp_json="$(jq -c '.mcpOAuth // null' "$profiles_path/$default_name/credentials/.credentials.json")"
	for token_file in "$profiles_path"/*.json; do
		if [[ ! -f "$token_file" ]]; then
			continue
		fi
		name="$(basename "$token_file" .json)"
		if [[ "$name" == "$default_name" ]] || ! _profile_valid_name "$name"; then
			continue
		fi
		if ! jq -e '.claudeAiOauth.refreshToken' "$token_file" >/dev/null 2>&1; then
			bubble_warn "skipping profile '$name': $token_file holds no tokens (it stays in the backup)"
			continue
		fi
		profile_path="$profiles_path/$name"
		(umask 077 && mkdir -p "$profile_path/credentials")
		if [[ ! -f "$profile_path/credentials/.credentials.json" ]]; then
			# shellcheck disable=SC2016 # A jq program: $mcp is its variable.
			_profile_write_json "$profile_path/credentials/.credentials.json" --argjson mcp "$mcp_json" \
				'{claudeAiOauth: .claudeAiOauth} + (if $mcp == null then {} else {mcpOAuth: $mcp} end)' "$token_file"
		fi
		if [[ ! -f "$profile_path/.claude.json" ]]; then
			account_json="$(jq -c '.oauthAccount // null' "$token_file")"
			_profile_seed_config "$profiles_path/$default_name/.claude.json" "$profile_path/.claude.json" "$account_json"
		fi
	done
}

# Run only by the migration that copied the live files into the default profile: from here on .claude.json is a link,
# and the tokens live in the profiles. The server caches stay where they are, shared (see _profile_is_organization).
_profile_retire_live_files() {
	local default_name="$1"
	if [[ -f "$shared_config_file" && ! -L "$shared_config_file" && -f "$profiles_path/$default_name/.claude.json" ]]; then
		_profile_link profiles/active/.claude.json "$shared_config_file"
	fi
	if [[ -f "$shared_credentials_file" && -f "$profiles_path/$default_name/credentials/.credentials.json" ]]; then
		rm -f -- "${shared_credentials_file:?}"
	fi
	rm -f -- "${profiles_path:?}"/*.json
}

# The shared directory's link into profiles/active. Only an absent path is linked: a regular file where the link
# belongs is left for check to report, because it may hold an account's newer state.
_profile_link_shared_root() {
	if [[ ! -e "$shared_config_file" && ! -L "$shared_config_file" ]]; then
		_profile_link profiles/active/.claude.json "$shared_config_file"
	fi
}

_profile_cmd_migrate() {
	local layout default_name
	_profile_refuse_inside_bubble migrate
	layout="$(_profile_layout)"
	if [[ "$layout" == none ]]; then
		default_name="${1:-}"
		if [[ -z "$default_name" ]]; then
			_profile_die "there are no profiles yet: name the account that is logged in now" \
				"usage: cc profiles migrate <name>"
		fi
		_profile_valid_name "$default_name" || _profile_die "invalid profile name: $default_name"
	else
		default_name="$(_profile_default_name)"
	fi
	_profile_refuse_while_claude_runs

	if [[ "$layout" == slot ]]; then
		_profile_link_shared_root
		bubble_info "profiles already have one directory each; a missing link is restored"
		_profile_cmd_check
		return
	fi

	(umask 077 && mkdir -p "$profiles_path")
	_profile_backup
	_profile_seed_from_live "$default_name"
	_profile_seed_v2_others "$default_name"
	_profile_retire_live_files "$default_name"
	_profile_link_shared_root
	# Last, so an interrupted migration still reads as the older layout and running it again finishes the job.
	_profile_link "$default_name" "$active_link"
	_profile_cmd_check
	printf '%smigrated:%s one directory per profile under %s; the default is %s\n' \
		"$bubble_family_on" "$bubble_off" "$profiles_path" "$default_name" >&2
	printf '%sbackup:%s %s (delete it once everything works)\n' "$bubble_family_on" "$bubble_off" "$backup_path" >&2
}

_profile_cmd_list() {
	local default_name name marker session_profiles sessions count
	_profile_refuse_inside_bubble list
	_profile_require_slot
	default_name="$(_profile_default_name)"
	session_profiles="$(_profile_session_profiles)" || session_profiles="unknown"
	while read -r name; do
		marker="  "
		if [[ "$name" == "$default_name" ]]; then
			marker="* "
		fi
		if [[ "$session_profiles" == unknown ]]; then
			sessions="sessions unknown"
		else
			count="$(grep -cx -- "$name" <<<"$session_profiles" || true)"
			case "$count" in
			0) sessions="" ;;
			1) sessions="1 session" ;;
			*) sessions="$count sessions" ;;
			esac
		fi
		printf '  %s%s%s%s  %s%s\n' "$marker" "$bubble_family_on" "$name" "$bubble_off" \
			"$(_profile_label "$name")" "${sessions:+  · $sessions}" >&2
	done < <(_profile_names)
}

# Inside a session profiles/active is the session's own profile; on the host it links the default.
_profile_cmd_which() {
	local name
	if [[ -n "${CLAUDE_BUBBLE_PROFILE:-}" ]]; then
		name="$CLAUDE_BUBBLE_PROFILE"
	else
		_profile_require_slot
		name="$(_profile_default_name)"
	fi
	echo "$name $(jq -r '.oauthAccount.emailAddress // "not logged in"' "$active_link/.claude.json" 2>/dev/null || echo "not logged in")"
}

_profile_cmd_select() {
	local name="${1:-}"
	_profile_refuse_inside_bubble select
	_profile_require_name select "$name"
	_profile_require_slot
	_profile_exists "$name" || _profile_die "profile '$name' does not exist" "see: cc profiles list"
	_profile_refuse_while_unbubbled_claude_runs
	_profile_link "$name" "$active_link"
	printf '%sdefault profile:%s %s  %s\n' "$bubble_family_on" "$bubble_off" "$name" "$(_profile_label "$name")" >&2
	bubble_info "running sessions keep their profile; new ones start on this one"
}

_profile_cmd_remove() {
	local name="${1:-}" session_profiles
	_profile_refuse_inside_bubble remove
	_profile_require_name remove "$name"
	_profile_require_slot
	_profile_exists "$name" || _profile_die "profile '$name' does not exist" "see: cc profiles list"
	if [[ "$name" == "$(_profile_default_name)" ]]; then
		_profile_die "cannot remove the default profile" "make another one the default first: cc profiles select <other>"
	fi
	session_profiles="$(_profile_session_profiles)" ||
		_profile_die "cannot ask systemd which sessions run, so profile '$name' stays"
	if grep -qx -- "$name" <<<"$session_profiles"; then
		_profile_die "profile '$name' has running sessions" "close them first"
	fi
	rm -rf -- "${profiles_path:?}/${name:?}"
	printf '%sremoved:%s %s\n' "$bubble_family_on" "$bubble_off" "$name" >&2
}

# The half-made profile `add` removes again, from its exit trap, unless the login completes and is allowed.
abandoned_profile_path=""
_profile_abandon() {
	if [[ -n "$abandoned_profile_path" ]]; then
		rm -rf -- "${abandoned_profile_path:?}"
	fi
}

_profile_cmd_add() {
	local name="${1:-}" profile_path default_name other_name
	_profile_refuse_inside_bubble add
	_profile_require_name add "$name"
	_profile_require_slot
	profile_path="$profiles_path/$name"
	if [[ -e "$profile_path" || -L "$profile_path" ]]; then
		_profile_die "profile '$name' already exists"
	fi
	default_name="$(_profile_default_name)"

	abandoned_profile_path="$profile_path"
	trap _profile_abandon EXIT
	(umask 077 && mkdir -p "$profile_path/credentials")
	_profile_seed_config "$profiles_path/$default_name/.claude.json" "$profile_path/.claude.json" null

	bubble_info "logging in to profile '$name' in a session bubble" "finish the login in your browser"
	# The login runs as a session on the new profile, so its tokens and its account land there and nowhere else.
	BROWSER="$www_browser" "$bubble_command" --profile "$name" auth login || true
	if ! jq -e '.claudeAiOauth.refreshToken' "$profile_path/credentials/.credentials.json" >/dev/null 2>&1; then
		_profile_die "the login did not finish; profile '$name' was not created"
	fi
	if _profile_is_organization "$name"; then
		while read -r other_name; do
			if [[ "$other_name" != "$name" ]]; then
				_profile_die "the login is an organization account, and profile '$other_name' already is one" \
					"every profile reads the same cached organization settings, so at most one may be an organization account" \
					"profile '$name' was not created"
			fi
		done < <(_profile_organization_names)
	fi
	abandoned_profile_path=""
	trap - EXIT
	printf '%sadded:%s %s  %s\n' "$bubble_family_on" "$bubble_off" "$name" "$(_profile_label "$name")" >&2
	bubble_info "start a session on it with: cc -P $name" "or make it the default: cc profiles select $name"
}

_profile_cmd_verify() {
	exec "$verify_command"
}

_profile_usage() {
	cat >&2 <<'USAGE'
Usage: cc profiles <command> [args]

Commands:
  list              List the profiles, the default, and their running sessions
  which             Print the default profile (inside a session, its own) and its email
  select <name>     Make <name> the default for new sessions; running sessions keep theirs
  add <name>        Log in to another account as a new profile
  remove <name>     Delete a profile that is not the default and has no running session
  migrate [<name>]  Move to one directory per profile (once, with every session closed)
  check             Verify the profile layout (run before every session and every switch)
  verify            Prove what the layout relies on against the installed Claude Code

Start one session on another profile with: cc -P <name> (or --profile <name>)
USAGE
	exit 1
}

_profile_main() {
	local command="${1:-}"
	if [[ $# -gt 0 ]]; then
		shift
	fi
	case "$command" in
	check) _profile_cmd_check ;;
	migrate) _profile_cmd_migrate "$@" ;;
	list) _profile_cmd_list ;;
	which) _profile_cmd_which ;;
	select) _profile_cmd_select "$@" ;;
	add) _profile_cmd_add "$@" ;;
	remove) _profile_cmd_remove "$@" ;;
	verify) _profile_cmd_verify ;;
	*) _profile_usage ;;
	esac
}

# Sourced by test_profiles.py, which stands in for the process and systemd queries before calling _profile_main.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	_profile_main "$@"
fi

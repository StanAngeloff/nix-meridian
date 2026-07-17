set -euo pipefail

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
profiles_dir="$config_dir/profiles"
cred_file="$config_dir/.credentials.json"
config_file="$config_dir/.claude.json"

highlight_on=""
highlight_off=""
red_on=""
red_off=""
if [[ -t 2 ]]; then
	highlight_on=$'\033[1;33m'
	highlight_off=$'\033[0m'
	red_on=$'\033[1;31m'
	red_off=$'\033[0m'
fi

die() {
	echo "${red_on}error:${red_off} $*" >&2
	exit 1
}

check_not_running() {
	local pids
	pids="$(pgrep -f '(claude-unwrapped|/bin/claude( |$))' 2>/dev/null || true)"
	if [[ -n "$pids" ]]; then
		die "Claude Code is running (PIDs: $(echo "$pids" | tr '\n' ' ' | sed 's/ *$//')). Close all sessions before managing profiles."
	fi
}

active_profile_name() {
	local target
	target="$(readlink "$profiles_dir/active" 2>/dev/null || true)"
	if [[ -z "$target" ]]; then return 1; fi
	echo "${target%.json}"
}

capture_profile() {
	local dest="$1"
	local oauth account
	oauth="$(jq -c '.claudeAiOauth // empty' "$cred_file")"
	if [[ -z "$oauth" ]]; then
		die "no claudeAiOauth in $cred_file — not logged in?"
	fi
	account="$(jq -c '.oauthAccount // empty' "$config_file")"
	jq -n --argjson claudeAiOauth "$oauth" --argjson oauthAccount "${account:-null}" \
		'{claudeAiOauth: $claudeAiOauth, oauthAccount: $oauthAccount}' >"$dest"
	chmod 600 "$dest"
}

profile_label() {
	local file="$1"
	local email sub org
	email="$(jq -r '.oauthAccount.emailAddress // "unknown"' "$file")"
	sub="$(jq -r '.claudeAiOauth.subscriptionType // "unknown"' "$file")"
	org="$(jq -r '.oauthAccount.organizationName // empty' "$file")"
	if [[ -n "$org" ]]; then
		printf '%s (%s, %s)' "$email" "$sub" "$org"
	else
		printf '%s (%s)' "$email" "$sub"
	fi
}

cmd_migrate() {
	local name="${1:-}"
	if [[ -z "$name" ]]; then
		die "profile name required. Usage: cc profiles migrate <name>"
	fi
	local profile_file="$profiles_dir/$name.json"
	if [[ -f "$profile_file" ]]; then
		die "profile '$name' already exists"
	fi

	mkdir -p "$profiles_dir"
	capture_profile "$profile_file"
	ln -sfn "$name.json" "$profiles_dir/active"

	local label
	label="$(profile_label "$profile_file")"
	echo "${highlight_on}migrated:${highlight_off} $label" >&2
	echo "${highlight_on}active profile:${highlight_off} $name" >&2
}

cmd_list() {
	if [[ ! -d "$profiles_dir" ]]; then
		echo "no profiles yet — run: cc profiles migrate <name>" >&2
		exit 0
	fi
	local active
	active="$(active_profile_name || true)"
	local found=0
	for file in "$profiles_dir"/*.json; do
		[[ -f "$file" ]] || continue
		found=1
		local name label marker
		name="$(basename "$file" .json)"
		label="$(profile_label "$file")"
		marker="  "
		if [[ "$name" == "$active" ]]; then marker="* "; fi
		printf '  %s%s%s  %s\n' "$marker" "${highlight_on}$name${highlight_off}" "" "$label" >&2
	done
	if [[ $found -eq 0 ]]; then
		echo "no profiles yet — run: cc profiles migrate <name>" >&2
	fi
}

cmd_which() {
	local name
	name="$(active_profile_name)" || die "no active profile"
	local profile_file="$profiles_dir/$name.json"
	if [[ ! -f "$profile_file" ]]; then
		die "active profile '$name' points to missing file"
	fi
	local email
	email="$(jq -r '.oauthAccount.emailAddress // "unknown"' "$profile_file")"
	echo "$name $email"
}

cmd_select() {
	local name="${1:-}"
	if [[ -z "$name" ]]; then
		die "profile name required. Usage: cc profiles select <name>"
	fi
	local profile_file="$profiles_dir/$name.json"
	if [[ ! -f "$profile_file" ]]; then
		die "profile '$name' does not exist. Run 'cc profiles list' to see available profiles."
	fi
	check_not_running
	ln -sfn "$name.json" "$profiles_dir/active"
	local label
	label="$(profile_label "$profile_file")"
	echo "${highlight_on}active profile:${highlight_off} $name  $label" >&2
}

cmd_remove() {
	local name="${1:-}"
	if [[ -z "$name" ]]; then
		die "profile name required. Usage: cc profiles remove <name>"
	fi
	local profile_file="$profiles_dir/$name.json"
	if [[ ! -f "$profile_file" ]]; then
		die "profile '$name' does not exist"
	fi
	local active
	active="$(active_profile_name || true)"
	if [[ "$name" == "$active" ]]; then
		die "cannot remove the active profile. Switch to another profile first: cc profiles select <other>"
	fi
	check_not_running
	rm "$profile_file"
	echo "${highlight_on}removed:${highlight_off} $name" >&2
}

cmd_add() {
	local name="${1:-}"
	if [[ -z "$name" ]]; then
		die "profile name required. Usage: cc profiles add <name>"
	fi
	shift
	local profile_file="$profiles_dir/$name.json"
	if [[ -f "$profile_file" ]]; then
		die "profile '$name' already exists"
	fi
	check_not_running

	mkdir -p "$profiles_dir"

	local backup=""
	local old_oauth
	old_oauth="$(jq -c '.claudeAiOauth // empty' "$cred_file" 2>/dev/null || true)"
	if [[ -n "$old_oauth" ]]; then
		backup="$(mktemp "$profiles_dir/.backup.XXXXXX")"
		echo "$old_oauth" >"$backup"
	fi

	restore_backup() {
		if [[ -n "${backup:-}" && -f "${backup:-}" ]]; then
			if [[ -n "$old_oauth" ]]; then
				local tmp
				tmp="$(mktemp "$cred_file.tmp.XXXXXX")"
				jq --argjson oauth "$old_oauth" '.claudeAiOauth = $oauth' "$cred_file" >"$tmp"
				chmod 600 "$tmp"
				mv "$tmp" "$cred_file"
			fi
			rm -f "$backup"
		fi
	}
	trap restore_backup INT TERM

	local tmp
	tmp="$(mktemp "$cred_file.tmp.XXXXXX")"
	jq 'del(.claudeAiOauth)' "$cred_file" >"$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$cred_file"

	echo "${highlight_on}launching Claude Code auth flow...${highlight_off}" >&2
	echo "complete the login in your browser, then exit Claude Code." >&2
	echo "" >&2

	local auth_exit=0
	claude auth login "$@" || auth_exit=$?

	trap - INT TERM

	local new_oauth
	new_oauth="$(jq -c '.claudeAiOauth // empty' "$cred_file" 2>/dev/null || true)"
	if [[ -z "$new_oauth" || "$auth_exit" -ne 0 ]]; then
		echo "" >&2
		echo "${red_on}auth did not complete — restoring previous credentials${red_off}" >&2
		restore_backup
		exit 1
	fi

	rm -f "${backup:-}"

	capture_profile "$profile_file"
	ln -sfn "$name.json" "$profiles_dir/active"

	echo "" >&2
	local label
	label="$(profile_label "$profile_file")"
	echo "${highlight_on}saved:${highlight_off} $name  $label" >&2
	echo "${highlight_on}active profile:${highlight_off} $name" >&2
}

usage() {
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
	cmd_migrate "$@"
	;;
add)
	shift
	cmd_add "$@"
	;;
list)
	shift
	cmd_list
	;;
which)
	shift
	cmd_which
	;;
select)
	shift
	cmd_select "$@"
	;;
remove)
	shift
	cmd_remove "$@"
	;;
*) usage ;;
esac

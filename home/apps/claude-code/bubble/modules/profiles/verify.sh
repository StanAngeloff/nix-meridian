set -euo pipefail

# The facts the account-profile layout rests on, proven against the installed Claude Code: `cc profiles verify`.
# They are Claude Code internals rather than promises, so they are proven again whenever its version changes.
# verified-version.nix beside this file records the version they last passed on, and Home Manager's activation prints
# a note when the packaged version differs (../../../default.nix).
# Every proof runs Claude Code through claude-profiles-sandbox (sandbox.sh beside this file) with fake tokens, so nothing
# here can reach ~/.claude, a running session or a real account. The first proof checks that isolation.

sandbox_command="@profilesSandbox@"
verified_version="@verifiedClaudeCodeVersion@"

# Set by _verify_main: the installed Claude Code, resolved once, and the throwaway directory every proof works under.
claude_file=""
probe_root=""
failure_count=0

# Unlike the launcher this command leaves bubble_prefix empty, so the severity word leads — see utilities/log.sh.

_verify_ok() {
	printf '%sok:%s %s\n' "$bubble_family_on" "$bubble_off" "$1" >&2
}

_verify_fail() {
	printf '%sFAIL:%s %s\n' "$bubble_error_on" "$bubble_off" "$1" >&2
	failure_count=$((failure_count + 1))
}

# $1 describes what holds when the command after it succeeds.
_verify_check() {
	local description="$1"
	shift
	if "$@"; then
		_verify_ok "$description"
	else
		_verify_fail "$description"
	fi
}

_verify_title() {
	printf '\n%s%s%s\n' "$bubble_family_on" "$1" "$bubble_off" >&2
}

# Fake tokens of the given subscription type, expiring at $3 (milliseconds since the epoch).
_verify_write_tokens() {
	local credentials_path="$1" subscription_type="$2" expires_at="$3"
	mkdir -p "$credentials_path"
	jq -n --arg type "$subscription_type" --argjson expires "$expires_at" \
		'{claudeAiOauth: {accessToken: "sk-ant-oat01-probe-fake", refreshToken: "sk-ant-ort01-probe-fake",
		  expiresAt: $expires, scopes: ["user:inference", "user:profile"], subscriptionType: $type}}' \
		>"$credentials_path/.credentials.json"
	chmod 600 "$credentials_path/.credentials.json"
}

# A .claude.json past onboarding that trusts the proof's directory, so an interactive session goes straight to its prompt.
# $3 is a JSON object merged in.
_verify_write_config() {
	jq -n --arg project "$2" --argjson extra "$3" \
		'{hasCompletedOnboarding: true, numStartups: 1, projects: {($project): {hasTrustDialogAccepted: true}}} + $extra' >"$1"
}

# Starts the command after $1, an inotifywait, in the background, and returns once its watches are established, so
# nothing can happen before it listens. Sets watch_id and watch_ready_fd for the caller to keep and hand to
# _verify_unwatch. inotifywait's stderr stays open on that descriptor until then: with -r it writes there again for every
# new directory, and a closed reader would kill it with SIGPIPE, losing the events it buffered.
# $1 is the file its events go to.
_verify_watch() {
	local events_file="$1" ready_file
	shift
	ready_file="$(mktemp -u "$probe_root/watch-ready.XXXXXX")"
	mkfifo "$ready_file"
	"$@" >"$events_file" 2>"$ready_file" &
	watch_id=$!
	exec {watch_ready_fd}<"$ready_file"
	read -r _ <&"$watch_ready_fd" # Setting up watches.
	read -r _ <&"$watch_ready_fd" # Watches established.
}

# Stops what _verify_watch started: $1 is its watch_id, $2 its watch_ready_fd. inotifywait writes out the events it
# buffered before it exits on SIGTERM.
_verify_unwatch() {
	local ready_fd="$2"
	kill "$1" 2>/dev/null || true
	wait "$1" 2>/dev/null || true
	exec {ready_fd}<&-
}

# The proofs below rely on this one: the sandbox shows no home directory, no session runtime directory, no resolver
# socket and no network, carries only the environment it set, and what it writes under its home stays inside.
_verify_isolation() {
	local proof_root="$probe_root/isolation" marker_name="isolation-$$" report variable_names
	_verify_title "the sandbox is isolated"
	mkdir -p "$proof_root/config" "$proof_root/runtime"
	# shellcheck disable=SC2016 # Expanded by the shell inside the sandbox.
	report="$("$sandbox_command" --offline "$proof_root" -- bash -c '
		echo "home entries: $(ls -A "$HOME" | wc -l)"
		echo "other home entries: $(find /home -mindepth 2 | wc -l)"
		if [[ -e /run/user ]]; then echo "session runtime: visible"; else echo "session runtime: hidden"; fi
		if [[ -e /run/systemd/resolve ]]; then echo "resolver: visible"; else echo "resolver: hidden"; fi
		if curl -sS -m 5 -o /dev/null https://api.anthropic.com 2>/dev/null; then echo "network: reachable"; else echo "network: none"; fi
		mkdir -p "$HOME/.claude"
		touch "$HOME/.claude/$1"
	' bash "$marker_name" </dev/null)"
	_verify_check "the home directory is empty" grep -qx 'home entries: 0' <<<"$report"
	_verify_check "no other home directory has anything in it" grep -qx 'other home entries: 0' <<<"$report"
	_verify_check "no session runtime directory (/run/user)" grep -qx 'session runtime: hidden' <<<"$report"
	_verify_check "no resolver socket" grep -qx 'resolver: hidden' <<<"$report"
	_verify_check "no network" grep -qx 'network: none' <<<"$report"
	variable_names="$("$sandbox_command" --offline "$proof_root" -- env </dev/null | cut -d= -f1 | LC_ALL=C sort | tr '\n' ' ')"
	_verify_check "the environment holds only what the sandbox set: ${variable_names% }" \
		test "${variable_names% }" == "CLAUDE_CONFIG_DIR HOME LANG PATH PWD TERM TMPDIR USER XDG_RUNTIME_DIR"
	_verify_check "what the sandbox wrote under its home never reached the real one" test ! -e "$HOME/.claude/$marker_name"
	if [[ -e "$HOME/.claude/$marker_name" ]]; then
		rm -f -- "${HOME:?}/.claude/${marker_name:?}"
	fi
}

# Each profile keeps its tokens in its own directory, which CLAUDE_SECURESTORAGE_CONFIG_DIR points Claude Code at, and
# sessions of one profile coordinate their refreshes through two locks: one inside that directory, one beside it.
_verify_credentials() {
	local proof_root="$probe_root/credentials" profile_path credentials_path status_json refresh_id
	local logger_id logger_fd release_id release_fd
	_verify_title "a profile's credential directory holds its tokens and both refresh locks"
	profile_path="$proof_root/profile"
	credentials_path="$profile_path/credentials"
	mkdir -p "$proof_root/config" "$proof_root/runtime"
	# Expired, so the session's first request refreshes them: the refresh takes both locks, then fails offline.
	_verify_write_tokens "$credentials_path" max 1000
	printf '{"hasCompletedOnboarding":true,"numStartups":1}\n' >"$proof_root/config/.claude.json"

	_verify_watch "$proof_root/events.log" \
		inotifywait -m -r -e create,delete,moved_to,close_write --format '%w%f %e' "$profile_path" "$proof_root/config"
	logger_id=$watch_id logger_fd=$watch_ready_fd
	status_json="$("$sandbox_command" --offline "$proof_root" --setenv CLAUDE_SECURESTORAGE_CONFIG_DIR "$credentials_path" -- \
		"$claude_file" auth status --json </dev/null 2>/dev/null || true)"

	# The lock beside the credential directory is released once the first refresh attempt is over, both locks taken.
	_verify_watch /dev/null timeout 90 inotifywait -e delete --include '/credentials\.lock$' "$profile_path"
	release_id=$watch_id release_fd=$watch_ready_fd
	"$sandbox_command" --offline "$proof_root" --setenv CLAUDE_SECURESTORAGE_CONFIG_DIR "$credentials_path" -- \
		"$claude_file" -p --no-session-persistence probe </dev/null >"$proof_root/refresh.log" 2>&1 &
	refresh_id=$!
	_verify_check "a refresh attempt ran to its end within 90 seconds" wait "$release_id"
	# Offline, the session keeps retrying and never ends by itself.
	kill "$refresh_id" 2>/dev/null || true
	wait "$refresh_id" 2>/dev/null || true
	_verify_unwatch "$release_id" "$release_fd"
	_verify_unwatch "$logger_id" "$logger_fd"

	_verify_check "Claude Code read the tokens from the credential directory" \
		jq -e '.loggedIn == true and .subscriptionType == "max"' <<<"$status_json" >/dev/null
	_verify_check "nothing was written to the config directory's .credentials.json" test ! -e "$proof_root/config/.credentials.json"
	_verify_check "the refresh lock was taken inside the credential directory" \
		grep -qF "$credentials_path/.oauth_refresh.lock CREATE" "$proof_root/events.log"
	_verify_check "the second refresh lock was taken beside it, inside the profile" \
		grep -qF "$profile_path/credentials.lock CREATE" "$proof_root/events.log"
}

# The shared ~/.claude/.claude.json is a link into the profile bound at profiles/active, and Claude Code saves through
# it, writing its temporary file beside the target, so the link survives. The bubble's own mount layout, rebuilt here.
_verify_config_link() {
	local proof_root="$probe_root/config-link" shared_path profile_path tmux_socket
	local logger_id logger_fd save_id save_fd
	_verify_title "Claude Code saves .claude.json through its link into the profile"
	shared_path="$proof_root/shared"
	profile_path="$proof_root/store/one"
	tmux_socket="$proof_root/tmux.sock"
	mkdir -p "$proof_root/config" "$proof_root/runtime" "$shared_path/profiles" "$profile_path"
	ln -s profiles/active/.claude.json "$shared_path/.claude.json"
	_verify_write_tokens "$profile_path/credentials" max 4102444800000
	_verify_write_config "$profile_path/.claude.json" "$proof_root" '{"oauthAccount": {"emailAddress": "someone@probe.example"}}'

	_verify_watch "$proof_root/events.log" \
		inotifywait -m -r -e create,delete,moved_to,close_write --format '%w%f %e' "$shared_path" "$profile_path"
	logger_id=$watch_id logger_fd=$watch_ready_fd
	# A save renames its temporary file onto .claude.json inside the profile; the first one is the event to wait for.
	_verify_watch /dev/null timeout 90 inotifywait -e moved_to --include '/\.claude\.json$' "$profile_path"
	save_id=$watch_id save_fd=$watch_ready_fd
	# Without TMUX, so a run from inside tmux starts a server of its own rather than talking to the caller's.
	env -u TMUX tmux -S "$tmux_socket" new-session -d -x 200 -y 50 -- \
		"$sandbox_command" --offline "$proof_root" \
		--bind "$shared_path" "$HOME/.claude" \
		--tmpfs "$HOME/.claude/profiles" \
		--bind "$profile_path" "$HOME/.claude/profiles/active" \
		--setenv CLAUDE_CONFIG_DIR "$HOME/.claude" \
		--setenv CLAUDE_SECURESTORAGE_CONFIG_DIR "$HOME/.claude/profiles/active/credentials" -- \
		"$claude_file"
	_verify_check "Claude Code saved .claude.json within 90 seconds" wait "$save_id"
	env -u TMUX tmux -S "$tmux_socket" kill-server 2>/dev/null || true
	_verify_unwatch "$save_id" "$save_fd"
	_verify_unwatch "$logger_id" "$logger_fd"

	_verify_check "the shared .claude.json is still the link into profiles/active" \
		test "$(readlink "$shared_path/.claude.json")" == profiles/active/.claude.json
	_verify_check "the temporary file was written beside the target, inside the profile" \
		grep -qE "^$profile_path/\.claude\.json\.tmp\.[^ ]+ CREATE" "$proof_root/events.log"
	_verify_check "nothing named .claude.json was written in the shared directory" \
		test -z "$(grep -E "^$shared_path/\.claude\.json(\.tmp\.[^ ]+)? (CREATE|MOVED_TO)" "$proof_root/events.log")"
}

# One session against the shared cache. $1 names it, $2 is its login's subscription type, $3 what it should see
# (applied or absent), and $4 the descriptor its SessionStart hook reports on.
_verify_cache_session() {
	local session_name="$1" subscription_type="$2" expected="$3" marker_fd="$4"
	local proof_root="$probe_root/shared-caches" session_id line="" seen="nothing" remote_settings_lines
	"$sandbox_command" --offline "$proof_root" \
		--setenv CLAUDE_SECURESTORAGE_CONFIG_DIR "$proof_root/credentials-$subscription_type" \
		--setenv PROBE_SESSION "$session_name" -- \
		"$claude_file" -p --no-session-persistence --debug-file "$proof_root/debug-$session_name.log" probe \
		</dev/null >"$proof_root/$session_name.log" 2>&1 &
	session_id=$!
	while read -r -t 90 line <&"$marker_fd"; do
		if [[ "$line" == "$session_name "* ]]; then
			seen="${line#"$session_name "}"
			break
		fi
	done
	# Offline, the session keeps retrying and never ends by itself.
	kill "$session_id" 2>/dev/null || true
	wait "$session_id" 2>/dev/null || true
	remote_settings_lines="$(grep -c 'Remote settings' "$proof_root/debug-$session_name.log" 2>/dev/null || true)"
	if [[ "$expected" == applied ]]; then
		_verify_check "a $subscription_type login applied the shared cache ($session_name: $seen), so the cache is live" \
			test "$seen" == applied
		_verify_check "its debug log shows it read the cache" test "${remote_settings_lines:-0}" -gt 0
	else
		_verify_check "a $subscription_type login ignored the shared cache ($session_name: $seen)" test "$seen" == absent
		_verify_check "and never opened it: no remote-settings lines in its debug log" test "${remote_settings_lines:-0}" -eq 0
	fi
}

# Every profile shares one config directory, so an organization's cached managed settings sit where every session can
# read them. Claude Code reads them only for an eligible login (Team, Enterprise or no subscription type): personal Max
# and Pro sessions, before and after a Team session, must not see them, while the Team session, the control, must.
_verify_shared_caches() {
	local proof_root="$probe_root/shared-caches" config_path marker_file marker_fd subscription_type
	_verify_title "personal logins ignore the organization settings every profile shares"
	config_path="$proof_root/config"
	marker_file="$proof_root/marker"
	mkdir -p "$config_path" "$proof_root/runtime"
	printf '%s\n' '{"env":{"PROBE_REMOTE_SETTINGS":"1"}}' >"$config_path/remote-settings.json"
	# Each session's SessionStart hook reports whether the cached setting reached it, on this pipe.
	mkfifo "$marker_file"
	exec {marker_fd}<>"$marker_file"
	jq -n --arg marker "$marker_file" \
		'{hooks: {SessionStart: [{hooks: [{type: "command",
		  command: ("if [ -n \"${PROBE_REMOTE_SETTINGS:-}\" ]; then echo \"$PROBE_SESSION applied\"; else echo \"$PROBE_SESSION absent\"; fi >" + $marker)}]}]}}' \
		>"$config_path/settings.json"
	_verify_write_config "$config_path/.claude.json" "$proof_root" '{}'
	for subscription_type in max pro team; do
		_verify_write_tokens "$proof_root/credentials-$subscription_type" "$subscription_type" 4102444800000
	done
	_verify_cache_session max-before max absent "$marker_fd"
	_verify_cache_session pro-before pro absent "$marker_fd"
	_verify_cache_session team team applied "$marker_fd"
	_verify_cache_session max-after max absent "$marker_fd"
	_verify_cache_session pro-after pro absent "$marker_fd"
	exec {marker_fd}<&-
}

# `cc profiles add` logs in from inside a bubble: the login hands its page to $BROWSER and listens on localhost, which
# the bubble shares with the host. Online, but no grant is ever made: the browser here only reports the URL, and the
# callback gets a bogus code with a wrong state, which Claude Code refuses before any token exchange.
_verify_login() {
	local proof_root="$probe_root/login" browser_file browser_fd tmux_socket authorize_url="" redirect_url callback_status
	_verify_title "a login inside a bubble reaches the browser and its callback"
	tmux_socket="$proof_root/tmux.sock"
	browser_file="$proof_root/browser"
	mkdir -p "$proof_root/config" "$proof_root/runtime" "$proof_root/profile/credentials"
	printf '{"hasCompletedOnboarding":true}\n' >"$proof_root/config/.claude.json"
	mkfifo "$browser_file"
	exec {browser_fd}<>"$browser_file"
	# shellcheck disable=SC2016 # Expanded when the stand-in browser runs.
	printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$1" >"$PROBE_BROWSER_REPORT"' >"$proof_root/browser.sh"
	chmod +x "$proof_root/browser.sh"

	# Without TMUX, so a run from inside tmux starts a server of its own rather than talking to the caller's.
	env -u TMUX tmux -S "$tmux_socket" new-session -d -x 200 -y 50 -- \
		"$sandbox_command" "$proof_root" \
		--setenv BROWSER "$proof_root/browser.sh" \
		--setenv PROBE_BROWSER_REPORT "$browser_file" \
		--setenv CLAUDE_SECURESTORAGE_CONFIG_DIR "$proof_root/profile/credentials" -- \
		"$claude_file" auth login
	_verify_check "the login handed its page to \$BROWSER within 60 seconds" read -r -t 60 authorize_url <&"$browser_fd"
	redirect_url="$(python3 -c 'import sys, urllib.parse
print(urllib.parse.parse_qs(urllib.parse.urlparse(sys.argv[1]).query).get("redirect_uri", [""])[0])' "$authorize_url")"
	_verify_check "its callback listens on localhost ($redirect_url)" test "${redirect_url#http://localhost:}" != "$redirect_url"
	callback_status="$(curl -sS -m 10 -o /dev/null -w '%{http_code}' \
		"$redirect_url?code=probe-bogus-code&state=probe-wrong-state" 2>/dev/null || true)"
	_verify_check "the callback answered from outside the sandbox (HTTP ${callback_status:-none})" \
		test "${callback_status:-000}" != 000
	env -u TMUX tmux -S "$tmux_socket" capture-pane -p >"$proof_root/screen.txt" 2>/dev/null || true
	env -u TMUX tmux -S "$tmux_socket" kill-server 2>/dev/null || true
	exec {browser_fd}<&-
	_verify_check "no credentials were written" test ! -s "$proof_root/profile/credentials/.credentials.json"
}

# Interactive proofs run in tmux servers of their own, which would outlive an interrupted run.
_verify_stop_servers() {
	local tmux_socket
	for tmux_socket in "$probe_root"/*/tmux.sock; do
		if [[ -S "$tmux_socket" ]]; then
			env -u TMUX tmux -S "$tmux_socket" kill-server 2>/dev/null || true
		fi
	done
}

_verify_main() {
	local claude_version
	claude_file="$(command -v claude || true)"
	if [[ -z "$claude_file" ]]; then
		bubble_error "no claude on PATH" "the proofs run against the installed Claude Code"
		exit 1
	fi
	# Resolved to the store, because a sandbox hides every home directory, and a profile's bin directory with it.
	claude_file="$(realpath -- "$claude_file")"
	probe_root="$(mktemp -d /tmp/cc-profiles-verify.XXXXXX)"
	trap _verify_stop_servers EXIT
	mkdir -p "$probe_root/version/config" "$probe_root/version/runtime"
	claude_version="$("$sandbox_command" --offline "$probe_root/version" -- "$claude_file" --version </dev/null 2>/dev/null || true)"
	claude_version="${claude_version%% *}"
	bubble_info "proving the profile layout on Claude Code ${claude_version:-of unknown version} ($claude_file)" \
		"in throwaway sandboxes under $probe_root; this takes under a minute"

	_verify_isolation
	if [[ "$failure_count" -gt 0 ]]; then
		bubble_error "the sandbox is not isolated, so no other proof ran" "kept for inspection: $probe_root"
		exit 1
	fi
	_verify_credentials
	_verify_config_link
	_verify_shared_caches
	_verify_login

	echo "" >&2
	if [[ "$failure_count" -gt 0 ]]; then
		bubble_error "$failure_count checks failed on Claude Code $claude_version" \
			"profiles may no longer keep their accounts apart on this version: investigate before running sessions of different profiles" \
			"kept for inspection: $probe_root"
		exit 1
	fi
	rm -rf -- "${probe_root:?}"
	if [[ "$claude_version" == "$verified_version" ]]; then
		printf '%sverified:%s Claude Code %s, the version on record\n' "$bubble_family_on" "$bubble_off" "$claude_version" >&2
	else
		printf '%sverified:%s Claude Code %s (on record: %s)\n' "$bubble_family_on" "$bubble_off" "$claude_version" \
			"$verified_version" >&2
		bubble_info "record it: set home/apps/claude-code/bubble/modules/profiles/verified-version.nix to \"$claude_version\""
	fi
}

_verify_main

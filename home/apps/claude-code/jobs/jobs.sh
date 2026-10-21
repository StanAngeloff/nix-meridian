# claude-jobs: runs and resumes the Claude Code jobs declared under nix-meridian.claude.jobs (./default.nix).
#
#   claude-jobs execute <job.json>   one run of a job, started by the job's systemd service
#   cc jobs run <job>                start a job's service now instead of waiting for its schedule
#   cc jobs resume <job> [run]       reopen a run's session interactively, the latest run unless one is named
#
# A run keeps its files in $XDG_STATE_HOME/claude-jobs/<job>/<run>/: run.json for the latest attempt, result.md linked to
# that attempt's final message, and attempt-<n>/ with each attempt's events.jsonl, result.md and stderr.log.
# The run's name is its stamp, computed once and shared by the directory, the session names, the output file and the
# notifications.
# Sessions start through claude-cc, which this script finds on PATH. claude-bubble ships this script as its `cc jobs`
# subcommand, so naming claude-cc's store path here would make each package depend on the other.

icon=@icon@
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/claude-jobs"
# Resolved before execute changes into the job's directory, where a relative $0 would point elsewhere.
self=$(realpath "$0")

# Like `cc profiles`, this command leaves bubble_prefix empty, so the severity word leads and results print bare.

# First argument is the message, any further ones are continuation lines.
die() {
	bubble_error "$@"
	exit 1
}

# notify-send waits on the notification daemon, so timeout keeps a missing daemon from holding up the run.
notify() {
	timeout 5 notify-send --app-name='Claude Code jobs' --icon="$icon" "$@" || true
}

# Shows a notification that opens the file $1 when clicked, with the remaining arguments passed to notify-send.
# Waiting for the click can take hours, so it runs in a unit of its own and the job's service ends meanwhile.
# Without a user manager to start that unit in, the notification still shows, only without the click.
notify_opening() {
	local file=$1
	shift
	systemd-run --user --quiet --collect --no-block --unit="claude-jobs-notification-$(uuidgen)" \
		"$self" open-on-click "$file" "$@" 2>/dev/null || notify "$@"
}

# Shows the notification and opens $1 if it is clicked. notify_opening's unit runs this.
open_on_click() {
	local file=$1
	shift
	# notify-send --wait returns once the notification is clicked or dismissed. It prints the name of the action a click
	# chose. A notification nobody touches for a day stops waiting.
	if [[ "$(timeout 1d notify-send --app-name='Claude Code jobs' --icon="$icon" --action=default=Open --wait "$@")" == default ]]; then
		xdg-open "$file"
	fi
}

# Escapes the characters the notification body reads as markup.
escape_markup() {
	sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# Prints a path with the home directory as ~.
abbreviate_home() {
	printf '%s' "${1/#"$HOME"/\~}"
}

# Prints a number of seconds the way a person says it: 90s, 2min, 1h 30min.
human_span() {
	local seconds=$1
	if ((seconds < 60)); then
		printf '%ss' "$seconds"
	elif ((seconds < 3600)); then
		printf '%smin' $((seconds / 60))
	elif ((seconds % 3600 == 0)); then
		printf '%sh' $((seconds / 3600))
	else
		printf '%sh %smin' $((seconds / 3600)) $((seconds % 3600 / 60))
	fi
}

# Prints the first heading of a Markdown file without its # marks, the title of a run's notification.
result_title() {
	sed -n '/^#\{1,6\} /{s/^#\{1,6\} *//p;q}' "$1"
}

# Prints the first paragraph of a Markdown file that is not a heading, three lines at most, as notification markup.
result_summary() {
	awk '/^#/ { if (started) exit; next } NF == 0 { if (started) exit; next } { started = 1; print; if (++lines == 3) exit }' "$1" |
		sed 's/\*\*//g; s/`//g' | escape_markup
}

# Runs the jq filter $1 over the events in $2 as one array, skipping any line that is not JSON.
events_query() {
	jq -nrR "[inputs | fromjson?] | $1" "$2"
}

# Prints one short line per step of a session's stream-json events, so the job's journal shows its progress.
progress() {
	jq --unbuffered -rR '
		fromjson? |
		if .type == "assistant" then
			.message.content[]? |
			if .type == "text" then "claude: \(.text | gsub("\\s+"; " ") | .[0:200])"
			elif .type == "tool_use" then "tool: \(.name) \(.input | tostring | .[0:120])"
			else empty end
		elif .type == "system" and .subtype == "task_started" then "background task started: \(.description)"
		elif .type == "system" and .subtype == "task_notification" then "background task \(.status): \(.summary // "")"
		elif .type == "result" then "result: \(.subtype)\(if .is_error then ", an error" else "" end), after \(.duration_ms / 1000 | floor)s"
		else empty end'
}

# Runs a command in the current directory through direnv, which loads the .envrc this directory or a parent holds,
# such as extra bubble binds or a session-name rule, and refuses an .envrc that was never allowed.
launch() {
	direnv exec . "$@"
}

# Prints the epoch of the job's latest scheduled slot at or before $1 and at most $2 seconds before it. Fails when there is none.
latest_slot() {
	local now=$1 span=$2 config=$3 latest='' at slot
	while IFS= read -r at; do
		while IFS= read -r slot; do
			slot=$(date -u -d "$slot" +%s)
			if ((slot <= now)) && [[ -z "$latest" || "$slot" -gt "$latest" ]]; then
				latest=$slot
			fi
		done < <(systemd-analyze calendar --base-time="@$((now - span))" --iterations=100 "$at" | sed -n 's/^ *(in UTC): //p')
	done < <(jq -r '.triggers.schedule.at[]' "$config")
	if [[ -z "$latest" ]]; then
		return 1
	fi
	printf '%s\n' "$latest"
}

# Prints why the attempt whose files are in $1 failed, or nothing when it succeeded.
# $2 is the attempt's exit status and $3 the output file the job requires, empty when it requires none.
attempt_failure() {
	local dir=$1 status=$2 output=$3 failed
	# timeout exits 124 when it stops a command. It exits 137 when the command ignored that and had to be killed.
	if ((status == 124 || status == 137)); then
		printf 'the attempt ran out of time'
		return
	fi
	if ((status != 0)); then
		printf 'the session exited with status %s' "$status"
		return
	fi
	if [[ "$(events_query '[.[] | select(.type == "result")] | last | .is_error == false' "$dir/events.jsonl")" != true ]]; then
		printf 'the session ended in an error'
		return
	fi
	# Any server that failed to connect fails the attempt, whether or not the prompt needed it.
	failed=$(events_query '[.[] | select(.type == "system" and .subtype == "init")] | last
		| [.mcp_servers[]? | select(.status == "failed") | .name] | join(", ")' "$dir/events.jsonl")
	if [[ -n "$failed" ]]; then
		printf 'MCP servers failed to connect: %s' "$failed"
		return
	fi
	if [[ -n "$output" && ! -s "$output" ]]; then
		printf 'the session did not write %s' "$(abbreviate_home "$output")"
		return
	fi
	if [[ ! -s "$dir/result.md" ]]; then
		printf 'the session left no final message'
	fi
}

execute() {
	local config=$1
	local name prompt cwd profile prefix drift='' attempts delay timeout_seconds output now slot='' span stamp run suffix=1 run_dir reason
	name=$(jq -r '.name' "$config")
	prompt=$(jq -r '.prompt' "$config")
	cwd=$(jq -r '.session.cwd' "$config")
	profile=$(jq -r '.session.profile // empty' "$config")
	prefix=$(jq -r '.session.prefix' "$config")
	attempts=$(jq -r '.retry.attempts' "$config")
	delay=$(jq -r '.retry["delay-seconds"]' "$config")
	timeout_seconds=$(jq -r '.session["timeout-seconds"]' "$config")
	now=$(date +%s)

	# systemd sets TRIGGER_UNIT only when the job's timer started the service. A run started by hand runs at once and takes
	# its start time as its name. A timer's run takes the time of its slot, which lies in the past when the timer catches up.
	if [[ -n "${TRIGGER_UNIT:-}" ]]; then
		drift=$(jq -r '.triggers.schedule["maximum-drift-seconds"] // empty' "$config")
		if [[ -n "$drift" ]]; then
			if ! slot=$(latest_slot "$now" "$drift" "$config"); then
				reason="its last scheduled time is more than $(human_span "$drift") back"
				bubble_info "skipped $name, $reason"
				notify --urgency=low --transient "$name skipped" "${reason^}, so it did not catch up."
				return 0
			fi
		else
			# Without a maximum drift every missed slot runs. The run takes the time of the latest slot within the last month
			# as its name, or its start time when the search finds none.
			for span in 60 3600 86400 2678400; do
				if slot=$(latest_slot "$now" "$span" "$config"); then
					break
				fi
			done
		fi
	fi
	stamp=$(date -d "@${slot:-$now}" +%Y-%m-%dT%H:%M)

	run=$stamp
	while [[ -e "$state_root/$name/$run" ]]; do
		suffix=$((suffix + 1))
		run="$stamp-$suffix"
	done
	run_dir="$state_root/$name/$run"
	mkdir -p "$run_dir"
	ln -sfn "$run" "$state_root/$name/latest"

	output=$(jq -r '.output // empty' "$config")
	output=${output//"{{run}}"/$run}
	prompt=${prompt//"{{output}}"/$output}
	if [[ -n "$output" ]]; then
		mkdir -p "$(dirname "$output")"
	fi

	local attempt backoff dir session_id session_name status failure='' report title
	cd "$cwd"
	for ((attempt = 1; attempt <= attempts; attempt++)); do
		if ((attempt > 1)); then
			backoff=$((delay * 2 ** (attempt - 2)))
			# A scheduled run stops retrying once the next attempt would start further from its slot than the maximum drift.
			if [[ -n "$drift" ]] && (($(date +%s) + backoff - slot > drift)); then
				failure="$failure, and another attempt would start more than $(human_span "$drift") after its scheduled time"
				break
			fi
			bubble_info "attempt $((attempt - 1)) of $name failed: $failure" "retrying in $(human_span "$backoff")"
			notify --urgency=low --transient "$name: attempt $((attempt - 1)) of $attempts failed" \
				"$(escape_markup <<<"${failure^}.")"$'\n'"Retrying in $(human_span "$backoff")."
			sleep "$backoff"
		fi

		dir="$run_dir/attempt-$attempt"
		mkdir -p "$dir"
		session_id=$(uuidgen)
		session_name="$prefix$name-$run"
		if ((attempt > 1)); then
			session_name+="-try$attempt"
		fi
		jq --arg run "$run" --arg id "$session_id" --arg session_name "$session_name" --argjson attempt "$attempt" --arg output "$output" \
			'{job: .name, run: $run, attempt: $attempt, "session-id": $id, "session-name": $session_name, output: $output, session: .session}' \
			"$config" >"$run_dir/run.json"
		ln -sfn "attempt-$attempt/result.md" "$run_dir/result.md"

		local -a args=()
		if [[ -n "$profile" ]]; then
			args+=(-P "$profile")
		fi
		args+=(-n "$session_name" --session-id "$session_id" -p "$prompt" --output-format stream-json --verbose)

		# An attempt only counts when it writes the output itself, so a file an earlier attempt left behind goes first.
		if [[ -n "$output" ]]; then
			rm -f "$output"
		fi
		# A headless session waits for its background work only once its input has ended, so its input is /dev/null.
		# The events go to the attempt's file whole and to the journal as one line per step. tee -p keeps writing the file
		# when the journal side stops reading, so a broken summary never cuts the session off.
		set +o errexit
		launch timeout --kill-after=60 "$timeout_seconds" claude-cc "${args[@]}" </dev/null 2>"$dir/stderr.log" |
			tee -p "$dir/events.jsonl" | progress
		status=${PIPESTATUS[0]}
		set -o errexit

		# A session that waited on background work prints one result per turn. The last result carries its final message.
		events_query '[.[] | select(.type == "result")] | last | .result // empty' "$dir/events.jsonl" >"$dir/result.md"
		failure=$(attempt_failure "$dir" "$status" "$output")
		if [[ -z "$failure" ]]; then
			report=${output:-$dir/result.md}
			title=$(result_title "$report")
			reason=''
			if ((attempt > 1)); then
				reason=$'\n'"It took $attempt attempts."
			fi
			notify_opening "$report" --urgency=normal "${title:-$name is ready}" \
				"$(result_summary "$report")$reason"$'\n\n'"<b>cc jobs resume $name</b> · $(abbreviate_home "$report")"
			return 0
		fi
	done

	# The session's own last words say what stopped it, such as a source it could not reach. Without any, stderr does.
	if [[ -s "$dir/result.md" ]]; then
		reason=$(head -n 5 "$dir/result.md" | escape_markup)
	else
		# stderr carries terminal colour codes, such as direnv's red errors, which a notification shows as raw text.
		reason=$(tail -n 5 "$dir/stderr.log" | sed 's/\x1b\[[0-9;]*m//g' | escape_markup)
	fi
	bubble_error "$name failed: $failure" "run files: $(abbreviate_home "$run_dir")"
	# A click opens what the last attempt left: its final message, or its stderr when it left none.
	report=$dir/result.md
	if [[ ! -s "$report" ]]; then
		report=$dir/stderr.log
	fi
	notify_opening "$report" --urgency=critical "$name failed" \
		"$(escape_markup <<<"${failure^}.")"$'\n\n'"$reason"$'\n\n'"Run files: $(abbreviate_home "$run_dir")"
	return 1
}

run() {
	local name=$1
	systemctl --user cat "claude-job-$name.service" >/dev/null 2>&1 || die "no job named $name"
	systemctl --user start --no-block "claude-job-$name.service"
	bubble_info "started $name, a notification follows when it ends" "watch it live with journalctl --user -fu claude-job-$name"
}

resume() {
	local name=$1 run=$2 run_file profile
	run_file="$state_root/$name/$run/run.json"
	if [[ ! -f "$run_file" && "$run" == latest ]]; then
		die "job $name has no runs yet" "its runs land in $state_root/$name"
	fi
	[[ -f "$run_file" ]] || die "job $name has no run $run" "its runs are in $state_root/$name"
	profile=$(jq -r '.session.profile // empty' "$run_file")

	local -a args=()
	if [[ -n "$profile" ]]; then
		args+=(-P "$profile")
	fi
	args+=(-r "$(jq -r '."session-id"' "$run_file")")

	# claude-cc resumes the run's session by its ID, which an .envrc's session-name rule cannot match. The rule is for naming
	# new sessions, which a resume does not do, so env switches it off after direnv has loaded the .envrc.
	cd "$(jq -r '.session.cwd' "$run_file")"
	launch env CLAUDE_BUBBLE_STRICT=0 claude-cc "${args[@]}"
}

usage() {
	cat >&2 <<'USAGE'
Usage: cc jobs <command> [args]

Commands:
  run <job>             Start a job now instead of waiting for its schedule
  resume <job> [<run>]  Reopen a run's session interactively, the latest run unless <run> names one

The jobs are nix-meridian.claude.jobs. Each run keeps its files in ~/.local/state/claude-jobs/<job>/<run>/.
USAGE
	exit 1
}

case "${1:-}" in
execute)
	[[ $# -eq 2 ]] || die "execute takes the job file its service passes" "usage: claude-jobs execute <job.json>"
	execute "$2"
	;;
open-on-click)
	[[ $# -ge 3 ]] || die "open-on-click takes the file to open and the notification" "usage: claude-jobs open-on-click <file> <notify-send arguments>"
	shift
	open_on_click "$@"
	;;
run)
	[[ $# -eq 2 ]] || die "job name required" "usage: cc jobs run <job>"
	run "$2"
	;;
resume)
	[[ $# -eq 2 || $# -eq 3 ]] || die "job name required" "usage: cc jobs resume <job> [<run>]"
	resume "$2" "${3:-latest}"
	;;
*)
	usage
	;;
esac

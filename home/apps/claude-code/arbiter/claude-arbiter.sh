# shellcheck shell=bash
# PreToolUse arbiter for bubbled sessions: Claude Code pipes every tool call to it as one JSON event on stdin.
# It asks cc-safety-net for a verdict, then translates that verdict for a session that runs with --dangerously-skip-permissions:
# - The engine asks only in modes where it expects a person to answer, and denies in bypass mode instead.
#   Claude Code shows a hook's ask in bypass mode too, so the engine is told the session runs in the default mode.
# - A call the engine stops becomes an ask, so a person decides; wiping the root or the home directory stays a deny.
# - A variable naming the script to run is an ask as well: the engine stops at its first objection,
#   so letting that one pass would let everything after it in the command run unchecked.
# - A shell command stopped on a request rule (arbiter-writes/gh-api-write or curl-write) gets a second look first,
#   because many of those stops are reads: a GraphQL query, or a request to the local development stack.
#   The engine runs again without the request rules, so any other objection in the command, or in a script it runs,
#   still asks with its own reason. Then classify_requests.py reads the command and every script the engine read,
#   and only when every request in them is a GraphQL query or goes to localhost does the call pass unprompted.
#   Claude Code's own ask rules still apply to it.
# - Every tool the engine ignores passes untouched.
# - Claude Code runs the call anyway after a hook fails or times out, so every failure here becomes an ask instead,
#   and the second look gives up with an ask before the hook's 30-second timeout.
#
# The engine runs in an emptied environment with its configuration pinned in the store, so no session setting can redirect it,
# and a repository's own .cc-safety-net/policy.json can only tighten that configuration, never switch a protection off.
# It logs each call it stops, commands verbatim, under ~/.claude/.cc-safety-net/logs, inside the bubble's writable ~/.claude.
# The second look's rerun logs nothing, so each stopped call is logged once, under the rule that stopped it first.
#
# Learn more at https://code.claude.com/docs/en/hooks and https://github.com/kenryu42/cc-safety-net

# A failure anywhere below, even jq's, ends in this fixed ask rather than a non-zero exit, which Claude Code treats as no decision.
# shellcheck disable=SC2329 # Only the EXIT trap calls it.
answer_failure() {
	local exit_code=$?
	if [[ -n ${scratch_directory:-} ]]; then
		rm -rf -- "$scratch_directory"
	fi
	if ((exit_code != 0)); then
		printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"claude-arbiter failed, so this call needs your confirmation."}}'
		exit 0
	fi
}
trap answer_failure EXIT

# answer DECISION REASON: prints Claude Code's decision for this call and stops.
answer() {
	jq -cn --arg decision "$1" --arg reason "$2" \
		'{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $decision, permissionDecisionReason: $reason}}'
	exit 0
}

# answer_stop DECISION RULE REASON: answers a call the engine stopped, which asks unless it wipes the root or the home.
answer_stop() {
	if [[ $1 == deny && $2 == rm.recursive-force-root-or-home ]]; then
		answer deny "$3"
	fi
	if [[ $1 != ask && $1 != deny ]]; then
		answer ask "cc-safety-net answered '$1', so this call needs your confirmation."
	fi
	answer ask "$3"
}

# run_engine POLICY SECONDS ARGUMENTS...: runs the engine on the given configuration, in an emptied environment,
# reading stdin, for at most SECONDS. Extra VARIABLE=value settings go in engine_settings beforehand.
run_engine() {
	local policy=$1 seconds=$2
	shift 2
	env -i HOME="$HOME" LANG=C.UTF-8 TMPDIR="${TMPDIR:-/tmp}" \
		CC_SAFETY_NET_HOME="$policy" CC_SAFETY_NET_NO_UPDATE_CHECK=1 CC_SAFETY_NET_PROJECT_TIGHTEN_ONLY=1 \
		"${engine_settings[@]}" timeout "$seconds" "@engineExe@" "$@"
}

# The engine's hook output carries its reason as a block of "Reason: …", "Rule: …" and "Command: …" lines
# between a header and a footer.

# rule_of OUTPUT: the id of the rule that stopped the call, or nothing.
rule_of() {
	local reason
	reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$1")
	sed -n '/^Rule: /{s///p;q;}' <<<"$reason"
}

# prompt_reason_of OUTPUT: the one-line reason the prompt shows.
prompt_reason_of() {
	local reason rule summary
	reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$1")
	rule=$(rule_of "$1")
	summary=$(sed -n '/^Reason: /{s///p;q;}' <<<"$reason")
	printf '%s\n' "cc-safety-net${rule:+ ($rule)}: ${summary:-$reason}"
}

# seconds_left: the seconds the second look may still spend, keeping the whole hook inside its 30-second timeout.
seconds_left() {
	printf '%s\n' $((28 - SECONDS))
}

event=$(cat)
tool_name=$(jq -r '.tool_name // ""' <<<"$event")

# The engine judges shell commands and the tools that name files; for any other tool it prints nothing, so it is not started.
# The names mirror its own routing (src/core/tool-input.ts, plus Monitor from its Claude Code adapter), normalized the same way:
# lower case, without "-", "_" or spaces.
normalized_tool_name=$(tr -d ' _-' <<<"$tool_name" | tr '[:upper:]' '[:lower:]')
case $normalized_tool_name in
bash | monitor | powershell | applypatch | patch | grep | grepsearch | rg | find | findbyname | glob | create | edit | listdir | \
	listpermissions | ls | multiedit | multireplacefilecontent | notebookedit | read | readfile | readurlcontent | \
	replacefilecontent | searchweb | strreplaceeditor | view | viewfile | write | writefile | writetofile) ;;
*) exit 0 ;;
esac

engine_event=$(jq -c '.permission_mode = "default"' <<<"$event")
engine_settings=(CC_SAFETY_NET_AUDIT_HOME="$HOME/.claude" CC_SAFETY_NET_AUDIT_SCOPE=blocked)
engine_exit_code=0
engine_output=$(run_engine "@policyPath@" 20 hook --coding-cli <<<"$engine_event") || engine_exit_code=$?
if ((engine_exit_code != 0)); then
	answer ask "cc-safety-net failed with exit code $engine_exit_code, so this call needs your confirmation."
fi
if [[ -z $engine_output ]]; then
	exit 0
fi

engine_decision=$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<<"$engine_output")
prompt_reason=$(prompt_reason_of "$engine_output")
rule_id=$(rule_of "$engine_output")

# Only a shell command the engine stopped on a request rule gets the second look.
case $engine_decision:$rule_id in
ask:custom.arbiter-writes/gh-api-write | ask:custom.arbiter-writes/curl-write) ;;
deny:custom.arbiter-writes/gh-api-write | deny:custom.arbiter-writes/curl-write) ;;
*) answer_stop "$engine_decision" "$rule_id" "$prompt_reason" ;;
esac
case $normalized_tool_name in
bash | monitor) ;;
*) answer_stop "$engine_decision" "$rule_id" "$prompt_reason" ;;
esac

# The second look. Its rerun gets a scratch directory to log into, which the EXIT trap removes,
# because without one the engine would log under $HOME.
command=$(jq -r '.tool_input.command // ""' <<<"$event")
cwd=$(jq -r '.cwd // ""' <<<"$event")
if [[ -z $command || -z $cwd ]]; then
	answer ask "$prompt_reason; second look: the call names no command or working directory"
fi
scratch_directory=$(mktemp -d)
engine_settings=(CC_SAFETY_NET_AUDIT_HOME="$scratch_directory")

if (($(seconds_left) < 2)); then
	answer ask "$prompt_reason; second look: out of time"
fi
rerun_exit_code=0
rerun_output=$(run_engine "@policyWithoutRequestRulesPath@" "$(seconds_left)" hook --coding-cli <<<"$engine_event") ||
	rerun_exit_code=$?
if ((rerun_exit_code != 0)); then
	answer ask "$prompt_reason; second look: cc-safety-net failed with exit code $rerun_exit_code"
fi
if [[ -n $rerun_output ]]; then
	answer_stop "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<<"$rerun_output")" \
		"$(rule_of "$rerun_output")" "$(prompt_reason_of "$rerun_output")"
fi

# The scripts the engine read, from its explain trace on the same configuration. The trace passes through the engine's
# secret redactor, which can replace a step's path; the classifier then asks.
if (($(seconds_left) < 2)); then
	answer ask "$prompt_reason; second look: out of time"
fi
trace=$(run_engine "@policyWithoutRequestRulesPath@" "$(seconds_left)" explain --json --cwd "$cwd" -- "$command" </dev/null)
if [[ $(jq -r '.result // ""' <<<"$trace") != allowed ]]; then
	answer ask "$prompt_reason; second look: the engine's trace does not allow the command"
fi
scripts=$(jq -c '[.. | objects | select(.type? == "script-file") | {path, bytes}]' <<<"$trace")

if (($(seconds_left) < 2)); then
	answer ask "$prompt_reason; second look: out of time"
fi
classification=$(
	jq -cn --arg command "$command" --arg cwd "$cwd" --argjson scripts "$scripts" --arg rule "$rule_id" \
		--arg rulebook "@policyPath@/rules/arbiter-writes/rulebook.json" \
		'{command: $command, cwd: $cwd, scripts: $scripts, rule: $rule, rulebook: $rulebook}' |
		timeout "$(seconds_left)" python3 -I "@classifierPath@"
)
if [[ $(jq -r '.verdict' <<<"$classification") == reads ]]; then
	exit 0
fi
answer ask "$prompt_reason; second look: $(jq -r '.reason' <<<"$classification")"

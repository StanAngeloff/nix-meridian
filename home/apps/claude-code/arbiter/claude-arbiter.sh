# shellcheck shell=bash
# PreToolUse arbiter for bubbled sessions: Claude Code pipes every tool call to it as one JSON event on stdin.
# It asks cc-safety-net for a verdict, then translates that verdict for a session that runs with --dangerously-skip-permissions:
# - The engine asks only in modes where it expects a person to answer, and denies in bypass mode instead.
#   Claude Code shows a hook's ask in bypass mode too, so the engine is told the session runs in the default mode.
# - A call the engine stops becomes an ask, so a person decides; wiping the root or the home directory stays a deny.
# - A command passes when the engine's only objection is a variable naming the script to run; so does every tool it ignores.
# - Claude Code runs the call anyway after a hook fails, so every failure here becomes an ask instead.
#
# The engine runs in an emptied environment with its configuration pinned in the store, so no session setting can redirect it.
# It logs each call it stops, commands verbatim, under ~/.claude/.cc-safety-net/logs, inside the bubble's writable ~/.claude.
#
# Learn more at https://code.claude.com/docs/en/hooks and https://github.com/kenryu42/cc-safety-net

# A failure anywhere below, even jq's, ends in this fixed ask rather than a non-zero exit, which Claude Code treats as no decision.
# shellcheck disable=SC2329 # Only the EXIT trap calls it.
answer_failure() {
	local exit_code=$?
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

event=$(cat)
tool_name=$(jq -r '.tool_name // ""' <<<"$event")

# The engine judges shell commands and the tools that name files; for any other tool it prints nothing, so it is not started.
# The names mirror its own routing (src/core/tool-input.ts), normalized the same way: lower case, without "-", "_" or spaces.
normalized_tool_name=$(tr -d ' _-' <<<"$tool_name" | tr '[:upper:]' '[:lower:]')
case $normalized_tool_name in
bash | powershell | applypatch | patch | grep | grepsearch | rg | find | findbyname | glob | create | edit | listdir | \
	listpermissions | ls | multiedit | multireplacefilecontent | notebookedit | read | readfile | readurlcontent | \
	replacefilecontent | searchweb | strreplaceeditor | view | viewfile | write | writefile | writetofile) ;;
*) exit 0 ;;
esac

engine_exit_code=0
engine_output=$(jq -c '.permission_mode = "default"' <<<"$event" |
	env -i HOME="$HOME" LANG=C.UTF-8 TMPDIR="${TMPDIR:-/tmp}" \
		CC_SAFETY_NET_HOME="@policyPath@" CC_SAFETY_NET_NO_UPDATE_CHECK=1 \
		CC_SAFETY_NET_AUDIT_HOME="$HOME/.claude" CC_SAFETY_NET_AUDIT_SCOPE=blocked \
		timeout 20 "@engineExe@" hook --coding-cli) || engine_exit_code=$?
if ((engine_exit_code != 0)); then
	answer ask "cc-safety-net failed with exit code $engine_exit_code, so this call needs your confirmation."
fi
if [[ -z $engine_output ]]; then
	exit 0
fi

engine_decision=$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<<"$engine_output")
engine_reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$engine_output")
# The reason is a block of "Reason: …", "Rule: …" and "Command: …" lines between a header and a footer.
rule_id=$(sed -n '/^Rule: /{s///p;q;}' <<<"$engine_reason")
reason_summary=$(sed -n '/^Reason: /{s///p;q;}' <<<"$engine_reason")
prompt_reason="cc-safety-net${rule_id:+ ($rule_id)}: ${reason_summary:-$engine_reason}"

if [[ -z $rule_id && $reason_summary == "shell execution source cannot be verified safely"* ]]; then
	exit 0
fi
case $engine_decision in
ask)
	answer ask "$prompt_reason"
	;;
deny)
	if [[ $rule_id == rm.recursive-force-root-or-home ]]; then
		answer deny "$prompt_reason"
	fi
	answer ask "$prompt_reason"
	;;
*)
	answer ask "cc-safety-net answered '$engine_decision', so this call needs your confirmation."
	;;
esac

# shellcheck shell=bash
# PermissionRequest hook for away mode: denies a prompt nobody answered in time.
# The away mod (mod/hooks/register.tsx) adds away_timeout_seconds to this hook's input while its session is in away mode;
# without it the hook passes at once. Claude Code runs this hook beside the dialog, so an answer from the person before the
# deadline wins and the deny printed after it is dropped.

payload=$(cat)
timeout_seconds=$(jq -r '.away_timeout_seconds | select(type == "number" and . >= 1) | ceil' <<<"$payload")
if [ -z "$timeout_seconds" ]; then
	exit 0
fi

sleep "$timeout_seconds"

case "$(jq -r '.tool_name // empty' <<<"$payload")" in
AskUserQuestion)
	message="The user is away (away mode is on) and nobody answered your question within ${timeout_seconds} seconds, so it was dismissed automatically. Go with the option you would recommend, say which one you picked and why, and carry on."
	;;
ExitPlanMode)
	message="The user is away (away mode is on) and nobody reviewed the plan within ${timeout_seconds} seconds, so it was not approved. Stay in plan mode: refine the plan and leave it ready for the user's review; do not start implementing."
	;;
*)
	message="The user is away (away mode is on) and nobody answered this permission prompt within ${timeout_seconds} seconds, so it was denied automatically; this is not a judgment of the action. Do not retry it or reach the same effect another way. Carry on with whatever does not need it, and when you finish, list what you skipped and why so the user can do it when they are back."
	;;
esac

jq -n --arg message "$message" '{hookSpecificOutput: {hookEventName: "PermissionRequest", decision: {behavior: "deny", message: $message}}}'

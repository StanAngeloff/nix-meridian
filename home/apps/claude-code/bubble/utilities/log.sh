# Message formatting shared by claude-bubble and claude-profiles. Both get this file spliced in at build time — bubble/package.nix fills the skeleton's slot, modules/profiles/module.nix prepends it to the standalone command — so there is one colour policy and one set of emitters instead of a copy per script, and a new module inherits them for free.
#
# bubble_prefix decides the shape, and it is the only thing the two callers disagree about. The launcher tags every line because its output arrives unbidden in the middle of a session started for another purpose, so it has to say who is speaking. The profiles command answers something just typed at the prompt, where attribution is already obvious, so it leaves the tag off and lets the severity word lead instead.
bubble_prefix=""

bubble_family_on=""
bubble_warning_on=""
bubble_error_on=""
bubble_off=""
# Colour for an interactive stderr only, and never when NO_COLOR is set (https://no-color.org). This is the single place either script decides, so anything else that wants colour tests bubble_off rather than repeating the check.
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
	bubble_family_on=$'\033[36m'
	bubble_warning_on=$'\033[33m'
	bubble_error_on=$'\033[31m'
	bubble_off=$'\033[0m'
fi

# _bubble_emit <severity> <severity-colour> <message> [continuation...]
# Colour rides on the prefix and the severity word; message bodies stay plain, so long paths and quoted arguments read as text rather than as a wall of bold.
_bubble_emit() {
	local severity="$1" severity_on="$2" message="$3" continuation lead lead_plain indent
	shift 3
	lead=""
	# Tracked alongside lead because the indent has to measure the printed width, which the escape sequences in lead would inflate.
	lead_plain="$bubble_prefix"
	if [[ -n "$bubble_prefix" ]]; then
		lead="$bubble_family_on$bubble_prefix$bubble_off "
	fi
	if [[ -n "$severity" ]]; then
		if [[ -n "$bubble_prefix" ]]; then
			message="$severity_on$severity:$bubble_off $message"
		else
			lead="$severity_on$severity:$bubble_off "
			lead_plain="$severity:"
		fi
	fi
	printf '%s%s\n' "$lead" "$message" >&2
	[[ $# -gt 0 ]] || return 0
	# Continuations align under whichever of the two leads the line. Untagged output has nothing to align under, so it falls back to a plain hanging indent.
	printf -v indent '%*s' "$((${#lead_plain} ? ${#lead_plain} + 1 : 2))" ''
	for continuation in "$@"; do
		# A blank separator line stays blank; indenting it would leave trailing whitespace behind.
		if [[ -z "$continuation" ]]; then
			printf '\n' >&2
		else
			printf '%s%s\n' "$indent" "$continuation" >&2
		fi
	done
}

bubble_info() { _bubble_emit "" "" "$@"; }
bubble_warn() { _bubble_emit "warning" "$bubble_warning_on" "$@"; }
bubble_error() { _bubble_emit "error" "$bubble_error_on" "$@"; }

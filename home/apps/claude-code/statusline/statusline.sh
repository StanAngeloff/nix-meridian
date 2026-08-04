# Claude Code status line
# Original session: $ claude --resume 7d46d2e1-4f58-49d6-91aa-4329728c9010

input=$(cat)

# ── colours ──────────────────────────────────────────────────────────────────
CYAN='\033[38;2;78;205;196m'
GREEN='\033[32m'
DIM_GRAY='\033[38;2;100;100;100m'
RESET='\033[0m'
PASTEL_YELLOW='\033[38;2;229;192;123m'
PASTEL_MAGENTA='\033[38;2;198;146;233m'
PASTEL_TEAL='\033[38;2;86;182;194m'
DIM_TEAL='\033[38;2;55;120;128m'
PASTEL_GREEN='\033[38;2;152;195;121m'
PASTEL_RED='\033[38;2;224;108;117m'
AMBER='\033[38;2;255;191;0m'

DIM_SEP="${DIM_GRAY} │ ${RESET}"

# ── model ────────────────────────────────────────────────────────────────────
model_id=$(echo "$input" | jq -r '.model.id // empty')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
model_part=""
if [ -n "$model_id" ]; then
	# Format context window size: 1000000 → 1M, 200000 → 200k
	ctx_label=""
	if [ -n "$ctx_size" ]; then
		if [ "$ctx_size" -ge 1000000 ] 2>/dev/null; then
			ctx_label=" ($(echo "scale=0; $ctx_size / 1000000" | bc)m)"
		elif [ "$ctx_size" -ge 1000 ] 2>/dev/null; then
			ctx_label=" ($(echo "scale=0; $ctx_size / 1000" | bc)k)"
		fi
	fi
	model_id="${model_id%%\[*}"
	model_part="${CYAN}✦ ${model_id}${ctx_label}${RESET}"
fi

# ── git branch ───────────────────────────────────────────────────────────────
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty')
git_dir="${cwd:-$(pwd)}"
git_part=""
branch=""
if git_ref=$(git -C "$git_dir" --no-optional-locks symbolic-ref --quiet HEAD 2>/dev/null); then
	branch="${git_ref#refs/heads/}"
elif git_ref=$(git -C "$git_dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null); then
	branch="$git_ref"
fi
if [ -n "$branch" ]; then
	git_part="${DIM_SEP}${GREEN}${branch}${RESET}"
fi

# ── diff stats ───────────────────────────────────────────────────────────────
diff_part=""
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')
if [ -n "$lines_added" ] || [ -n "$lines_removed" ]; then
	lines_added="${lines_added:-0}"
	lines_removed="${lines_removed:-0}"
	diff_part="${DIM_SEP}${PASTEL_GREEN}+${lines_added}${RESET}/${PASTEL_RED}-${lines_removed}${RESET}"
fi

# ── token breakdown from last message ────────────────────────────────────────
token_part=""
has_current=$(echo "$input" | jq -r '.context_window.current_usage // empty | if . then "yes" else empty end')
if [ "$has_current" = "yes" ]; then
	in_tok=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens                    // 0')
	out_tok=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens                   // 0')
	think_tok=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens     // 0')
	# Session-level totals for Σ
	total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens  // 0')
	total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
	tot_tok=$((total_in + total_out))
	# Format numbers with k suffix when >= 1000
	fmt_num() {
		local n=$1
		if [ "$n" -ge 1000000 ] 2>/dev/null; then
			printf '%.1fm' "$(echo "scale=1; $n / 1000000" | bc)"
		elif [ "$n" -ge 1000 ] 2>/dev/null; then
			printf '%.1fk' "$(echo "scale=1; $n / 1000" | bc)"
		else
			echo "$n"
		fi
	}
	in_f=$(fmt_num "$in_tok")
	out_f=$(fmt_num "$out_tok")
	think_f=$(fmt_num "$think_tok")
	tot_f=$(fmt_num "$tot_tok")
	token_part="${DIM_SEP}${in_f}↑ ${out_f}↓ ${think_f}◌ Σ${tot_f}"
fi

# ── session cost ─────────────────────────────────────────────────────────────
cost_part=""
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
if [ -n "$session_cost" ] && [ "$session_cost" != "0" ]; then
	cost_fmt=$(printf '$%.2f' "$session_cost")
	cost_part="${DIM_SEP}${PASTEL_YELLOW}${cost_fmt}${RESET}"
fi

# ── session duration ─────────────────────────────────────────────────────────
duration_part=""
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
if [ -n "$duration_ms" ] && [ "$duration_ms" != "0" ]; then
	total_sec=$((duration_ms / 1000))
	hours=$((total_sec / 3600))
	mins=$(((total_sec % 3600) / 60))
	if [ "$hours" -gt 0 ]; then
		duration_part="${DIM_SEP}${PASTEL_MAGENTA}${hours}h${mins}m${RESET}"
	elif [ "$mins" -gt 0 ]; then
		duration_part="${DIM_SEP}${PASTEL_MAGENTA}${mins}m${RESET}"
	fi
fi

# ── context progress bar ─────────────────────────────────────────────────────
ctx_part=""
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ]; then
	pct_int=$(printf '%.0f' "$used_pct")
	exceeds_200k=$(echo "$input" | jq -r '.exceeds_200k_tokens // false')
	if [ "$exceeds_200k" = "true" ]; then
		bar_color="$AMBER"
	else
		bar_color="$PASTEL_GREEN"
	fi
	bar_width=10
	filled=$((pct_int * bar_width / 100))
	if [ "$filled" -gt "$bar_width" ]; then filled=$bar_width; fi
	empty=$((bar_width - filled))
	bar=""
	for _ in $(seq 1 "$filled"); do bar="${bar}█"; done
	for _ in $(seq 1 "$empty"); do bar="${bar}-"; done
	ctx_part="${DIM_SEP}${bar_color}${bar} ${pct_int}%${RESET}"
fi

# ── rate limits ───────────────────────────────────────────────────────────────
rate_part=""
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage  // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage  // empty')

# Publish these limits for the usage tray, which shows them in the GNOME panel. Claude Code derives
# them from the inference API's rate-limit headers on every render, so while a session is working
# they are fresher than anything the tray's own /api/oauth/usage poll can get -- and free, which
# matters because that endpoint rate-limits hard. The tray still polls for the per-model window and
# the credit balance, neither of which appears here, but far less often while this file keeps moving.
#
# The whole rate_limits object goes through verbatim rather than picked apart here, so field names
# live in one place (the tray's usage.py) and a window Claude Code adds later needs no change on this
# side.
#
# Under ~/.claude rather than XDG_RUNTIME_DIR: the bubble lays a masked tmpfs over the runtime
# directory, so a file written there by a bubbled session would be invisible to the tray on the
# host. ~/.claude is bound through, which is the same channel bubble/modules/notifications uses.
# Renaming into place keeps concurrent sessions from writing over each other mid-write.
if [ -n "$five_pct" ] || [ -n "$week_pct" ]; then
	usage_path="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage-activity"
	if echo "$input" | jq -c '.rate_limits' >"${usage_path}.$$" 2>/dev/null; then
		mv -f "${usage_path}.$$" "$usage_path" 2>/dev/null || rm -f "${usage_path}.$$"
	else
		rm -f "${usage_path}.$$"
	fi
fi

if [ -n "$five_pct" ] || [ -n "$week_pct" ]; then
	rate_part="${DIM_SEP}"
	if [ -n "$five_pct" ]; then
		five_int=$(printf '%.0f' "$five_pct")
		rate_part="${rate_part}${DIM_TEAL}5h:${RESET}${PASTEL_TEAL}${five_int}%${RESET}"
		if [ "$five_int" -ge 50 ] 2>/dev/null; then
			resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
			if [ -n "$resets_at" ]; then
				now_epoch=$(date +%s)
				reset_epoch="$resets_at"
				if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt "$now_epoch" ]; then
					diff_sec=$((reset_epoch - now_epoch))
					rh=$((diff_sec / 3600))
					rm=$(((diff_sec % 3600) / 60))
					if [ "$rh" -gt 0 ]; then
						reset_str="${rh}h${rm}m"
					else
						reset_str="${rm}m"
					fi
					rate_part="${rate_part} (resets ${reset_str})"
				fi
			fi
		fi
	fi
	if [ -n "$week_pct" ]; then
		if [ -n "$five_pct" ]; then rate_part="${rate_part} "; fi
		rate_part="${rate_part}${DIM_TEAL}7d:${RESET}${PASTEL_TEAL}$(printf '%.0f' "$week_pct")%${RESET}"
	fi
fi

# ── assemble ─────────────────────────────────────────────────────────────────
printf "%b%b%b%b%b%b%b%b\n" \
	"$model_part" \
	"$git_part" \
	"$cost_part" \
	"$duration_part" \
	"$diff_part" \
	"$token_part" \
	"$ctx_part" \
	"$rate_part"

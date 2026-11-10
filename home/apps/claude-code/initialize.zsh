# Ordered (extended regex, model) pairs; the first regex matching the whole -m value wins.
# A '.' in a regex stands for an optional separator: '-', '_', '.' or nothing.
typeset -ga _claude_model_aliases=(
  'fable'       'claude-fable-5-2[1m]'
  'opus'        'claude-opus-5-5[1m]'
  'opus.4(.6)?' 'claude-opus-4-6[1m]'
  'sonnet'      'claude-sonnet-5'
)

# Sets REPLY to the model an alias stands for, or to the value unchanged when no alias matches.
function _claude_resolve_model_alias() {
  emulate -L zsh
  local MATCH MBEGIN MEND
  local -a match mbegin mend

  local pattern model
  for pattern model in "${_claude_model_aliases[@]}"; do
    if [[ "$1" =~ "^(${pattern//./[-_.]?})\$" ]]; then
      REPLY="$model"
      return
    fi
  done
  REPLY="$1"
}

# $1 is the model the launcher passes when no -m is given.
function _claude_expand_model_aliases() {
  emulate -L zsh

  local REPLY
  local resolved_model="$1"
  local i
  for (( i=1; i <= $#_cli_args; i++ )); do
    case "${_cli_args[$i]}" in
      -m|--model)
        if (( i < $#_cli_args )); then
          _claude_resolve_model_alias "${_cli_args[$i+1]}"
          _cli_args[$i+1]="$REPLY"
          resolved_model="$REPLY"
        fi
        ;;
      --model=*)
        _claude_resolve_model_alias "${_cli_args[$i]#--model=}"
        _cli_args[$i]="--model=${REPLY}"
        resolved_model="$REPLY"
        ;;
      -m*)
        _claude_resolve_model_alias "${_cli_args[$i]#-m}"
        _cli_args[$i]="-m${REPLY}"
        resolved_model="$REPLY"
        ;;
      # Claude Code has no short form for --effort; rewriting it here lets the per-model effort below see it.
      -e)
        _cli_args[$i]="--effort"
        ;;
      -e?*)
        _cli_args[$i]="--effort=${_cli_args[$i]#-e}"
        ;;
    esac
  done

  # Per-model effort, pattern-matched on the resolved model identifier; it is the only --effort cc passes.
  # Every model gets a level, max unless listed: without an explicit --effort, Claude Code falls back to settings.json.
  # A forced level replaces an explicit --effort; otherwise the explicit --effort wins.
  local effort=max
  local is_forced=0
  case "$resolved_model" in
    *fable*) effort=high; is_forced=1 ;;
    *opus-5-5*) effort=xhigh ;;
  esac

  local has_effort=0
  for (( i=1; i <= $#_cli_args; i++ )); do
    case "${_cli_args[$i]}" in
      --effort)
        if (( i < $#_cli_args )); then
          if (( is_forced )); then
            _cli_args[$i+1]="$effort"
          fi
          has_effort=1
        fi
        break
        ;;
      --effort=*)
        if (( is_forced )); then
          _cli_args[$i]="--effort=${effort}"
        fi
        has_effort=1
        break
        ;;
    esac
  done
  if (( ! has_effort )); then
    # Prepended: the launcher drops everything before a subcommand word, so the flag never reaches a handler
    # (claude auth login rejects it), and a trailing subcommand word (cc -p profiles) stays a prompt instead of a handoff.
    _cli_args=( "--effort" "$effort" "${_cli_args[@]}" )
  fi
}

# Succeeds when the launcher will hand these arguments to a subcommand handler instead of starting a session.
# Mirrors the launcher's rule in bubble/bubble.sh (a registered subcommand word followed by at least one more argument,
# after -m, -P/--profile and -v/--volume have consumed their values), so the two must change together.
# The words are in _claude_subcommand_names, which aliases.nix sets from the launcher's own registry.
function _claude_is_subcommand_handoff() {
  emulate -L zsh

  local i
  for (( i=1; i <= $#; i++ )); do
    case "${@[$i]}" in
      -m|-P|--profile)
        if (( i < $# )); then (( i += 1 )); fi
        ;;
      -v|--volume)
        if [[ "${@[$i+1]}" == /* ]]; then (( i += 1 )); fi
        ;;
      *)
        if (( ${_claude_subcommand_names[(Ie)${@[$i]}]:-0} && i < $# )); then return 0; fi
        ;;
    esac
  done
  return 1
}

# Sets REPLY to the part of session name $1 that goes into the window name: feature-x for feature-x/v2.
function _claude_window_session_name() {
  emulate -L zsh
  REPLY="${1%%[+/@#.!?[:space:]]*}"
}

# Sets REPLY to the file that holds the window keyword saved for session name $1.
function _claude_window_keyword_path() {
  emulate -L zsh
  REPLY="${XDG_STATE_HOME:-$HOME/.local/state}/claude-cc/keywords/$1"
}

# Saves the keyword of a window name such as nix-meridian@feature-x[DOCS] for its session name.
function _claude_save_window_keyword() {
  emulate -L zsh
  local MATCH MBEGIN MEND REPLY
  local -a match mbegin mend

  if [[ ! "$1" =~ '@([^@[:space:][]+) *\[([^]]+)\]$' ]]; then return 0; fi
  local session_name="${match[1]}"
  local keyword="${match[2]}"
  _claude_window_session_name "$session_name"
  if [[ "$REPLY" != "$session_name" ]]; then return 0; fi

  _claude_window_keyword_path "$session_name"
  mkdir -p "${REPLY:h}" && print -r -- "$keyword" > "$REPLY"
}

# Renames the tmux window cc runs in to $1, with keyword $2 in brackets when given,
# unless the window name already holds $1 as a whole word in any letter case.
# A name like that came from a manual rename (nix-meridian@feature-x[DOCS]), so cc keeps it.
# The function records each rename for _claude_restore_window_name.
function _claude_rename_window() {
  emulate -L zsh

  local base_name="$1"
  local new_name="$1${2:+[$2]}"
  local window
  # Without a target, tmux picks the window in front, which may not be the one holding this pane.
  window=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id} #{window_name}' 2>/dev/null)
  local window_id="${window%% *}"
  local old_name="${window#* }"
  if [[ -z "$window_id" ]]; then return 0; fi
  if [[ "${(L)old_name}" == (|*[^[:alnum:]_-])"${(L)base_name}"(|[^[:alnum:]_-]*) ]]; then return 0; fi

  tmux rename-window -t "$window_id" "$new_name"
  typeset -g _claude_renamed_window_id="$window_id"
  typeset -g _claude_renamed_window_old_name="$old_name"
  typeset -g _claude_renamed_window_new_name="$new_name"
}

function _claude_bubble_initialize() {
  emulate -L zsh

  # A subcommand never starts a session, so the session-name rules and the window rename do not apply.
  if _claude_is_subcommand_handoff "$@"; then return 0; fi

  local prefix_on="" error_on="" off=""
  if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
    prefix_on=$'\033[36m'
    error_on=$'\033[31m'
    off=$'\033[0m'
  fi

  local has_session_flag=0
  local session_name=""
  local i
  for (( i=1; i <= $#; i++ )); do
    case "${@[$i]}" in
      -n|--name|-r|--resume)
        has_session_flag=1
        if (( i < $# )); then
          local next="${@[$i+1]}"
          # A word starting with a dash is the next flag, as Claude Code reads it (-r alone opens the resume picker).
          [[ "$next" != -* ]] && session_name="$next"
        fi
        break
        ;;
      --name=*|--resume=*)
        has_session_flag=1
        session_name="${${@[$i]}#*=}"
        break
        ;;
    esac
  done

  local is_strict=0
  local strict_pattern=""
  if [[ -n "$CLAUDE_BUBBLE_STRICT" && "$CLAUDE_BUBBLE_STRICT" != "0" \
     && "${(L)CLAUDE_BUBBLE_STRICT}" != "false" ]]; then
    is_strict=1
    local first="${CLAUDE_BUBBLE_STRICT[1]}"
    local last="${CLAUDE_BUBBLE_STRICT[-1]}"
    if [[ "$first" == "$last" && "$first" == [/!@] && ${#CLAUDE_BUBBLE_STRICT} -gt 2 ]]; then
      strict_pattern="${CLAUDE_BUBBLE_STRICT[2,-2]}"
    fi
  fi

  if (( is_strict && ! has_session_flag )); then
    printf '%sclaude-bubble:%s %serror:%s pass -n/--name or -r/--resume (CLAUDE_BUBBLE_STRICT)\n' \
      "$prefix_on" "$off" "$error_on" "$off" >&2
    return 1
  fi

  if [[ -n "$strict_pattern" && -n "$session_name" ]]; then
    local delimiter="${CLAUDE_BUBBLE_STRICT[1]}"
    local sed_address
    if [[ "$delimiter" == "/" ]]; then
      sed_address="/${strict_pattern}/p"
    else
      sed_address="\\${delimiter}${strict_pattern}${delimiter}p"
    fi
    if ! printf '%s\n' "$session_name" | sed -nE "$sed_address" | read -r; then
      printf '%sclaude-bubble:%s %serror:%s session name '\''%s'\'' does not match: %s\n' \
        "$prefix_on" "$off" "$error_on" "$off" "$session_name" "$strict_pattern" >&2
      return 1
    fi
  fi

  if [[ -n "$CLAUDE_BUBBLE_TMUX" && "$CLAUDE_BUBBLE_TMUX" != "0" \
     && "${(L)CLAUDE_BUBBLE_TMUX}" != "false" \
     && -n "$TMUX" && -n "$session_name" ]]; then
    local git_common
    git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if [[ -n "$git_common" ]]; then
      local repository_name="${${git_common%/.git}:t}"
      local REPLY
      _claude_window_session_name "$session_name"
      local normalized="$REPLY"
      if [[ -n "$repository_name" && -n "$normalized" ]]; then
        local keyword=""
        _claude_window_keyword_path "$normalized"
        if [[ -r "$REPLY" ]]; then keyword=$(<"$REPLY"); fi
        _claude_rename_window "${repository_name}@${normalized}" "$keyword"
      fi
    fi
  fi
}

# Gives the window _claude_rename_window renamed its old name back, if the window still carries the name cc gave it.
# A window renamed by hand during the session keeps that name.
function _claude_restore_window_name() {
  emulate -L zsh

  if [[ -z "$_claude_renamed_window_id" ]]; then return 0; fi
  local current_name
  current_name=$(tmux display-message -p -t "$_claude_renamed_window_id" '#{window_name}' 2>/dev/null)
  if [[ "$current_name" == "$_claude_renamed_window_new_name" ]]; then
    tmux rename-window -t "$_claude_renamed_window_id" "$_claude_renamed_window_old_name" 2>/dev/null
  fi
}

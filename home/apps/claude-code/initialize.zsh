# Ordered (extended regex, model) pairs; the first regex matching the whole -m value wins.
# A '.' in a regex stands for an optional separator: '-', '_', '.' or nothing.
typeset -ga _claude_model_aliases=(
  'fable'       'claude-fable-5-1'
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

  # Per-model effort, pattern-matched on the resolved model identifier.
  # A forced level replaces an explicit --effort; otherwise the explicit --effort wins.
  local effort=""
  local is_forced=0
  case "$resolved_model" in
    *fable*) effort=high; is_forced=1 ;;
    *opus-5-5*) effort=xhigh ;;
  esac

  if [[ -n "$effort" ]]; then
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
      _cli_args+=( "--effort" "$effort" )
    fi
  fi
}

function _claude_bubble_initialize() {
  emulate -L zsh

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
          [[ "$next" != --* ]] && session_name="$next"
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
      local normalized="${session_name%%[+/@#.!?[:space:]]*}"
      if [[ -n "$repository_name" && -n "$normalized" ]]; then
        tmux rename-window "${repository_name}@${normalized}"
      fi
    fi
  fi
}

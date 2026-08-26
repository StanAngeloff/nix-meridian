typeset -gA _claude_model_aliases=(
  [fable]=claude-fable-5
  [opus]=claude-opus-4-6[1m]
  [sonnet]=claude-sonnet-5
)

function _claude_expand_model_aliases() {
  emulate -L zsh

  local i
  for (( i=1; i <= $#_cli_args; i++ )); do
    case "${_cli_args[$i]}" in
      -m|--model)
        if (( i < $#_cli_args )); then
          local next="${_cli_args[$i+1]}"
          if (( ${+_claude_model_aliases[$next]} )); then
            _cli_args[$i+1]="${_claude_model_aliases[$next]}"
          fi
        fi
        ;;
      --model=*)
        local val="${_cli_args[$i]#--model=}"
        if (( ${+_claude_model_aliases[$val]} )); then
          _cli_args[$i]="--model=${_claude_model_aliases[$val]}"
        fi
        ;;
      -m*)
        local val="${_cli_args[$i]#-m}"
        if (( ${+_claude_model_aliases[$val]} )); then
          _cli_args[$i]="-m${_claude_model_aliases[$val]}"
        fi
        ;;
    esac
  done
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

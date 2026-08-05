# Print the sole worktree of the top-level clone whose directory name contains the query.
#
# Worktrees are created for us by tooling and are often never visited from a shell,
# so they never enter zoxide's frecency database and `zz` alone can never reach them.
# Nothing is printed unless exactly one name matches; an ambiguous query is left for zoxide to rank.
function _zz_worktree() {
  # Restore default options for the duration of the call; array indexing and glob qualifiers below depend on them.
  emulate -L zsh

  [[ $# -eq 1 && -n $1 && $1 != -* && $1 != */* ]] || return 1

  # The main worktree heads the porcelain listing, so this is the clone itself even when called from a worktree.
  local -a listing
  listing=( ${(f)"$(\command git worktree list --porcelain 2> /dev/null)"} )

  local clone_path=${listing[1]#worktree }
  [[ -n $clone_path ]] || return 1

  local -a matches
  local parent_path name
  for parent_path in $clone_path/.claude/worktrees $clone_path/.worktrees; do
    for name in $parent_path/*(N-/:t); do
      # The query is quoted so that glob characters in it match literally.
      [[ ${name:l} == *"${1:l}"* ]] && matches+=( "$parent_path/$name" )
    done
  done

  (( $#matches == 1 )) || return 1

  print -r -- "$matches[1]"
}

# Jump to a directory within the current Git repository, preferring a worktree of the top-level clone.
function zz() {
  emulate -L zsh

  __zoxide_doctor

  local worktree_path
  if worktree_path="$(_zz_worktree "$@")"; then
    __zoxide_cd "$worktree_path"
    return
  fi

  # Outside a repository the flag drops out entirely; passing it empty matches nothing.
  local base_path result_path
  base_path="$(\command git rev-parse --show-toplevel 2> /dev/null)"
  result_path="$(\command zoxide query ${base_path:+--base-dir=$base_path} -- "$@")" && __zoxide_cd "$result_path"
}

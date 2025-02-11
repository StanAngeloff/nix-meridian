function _user_hostname_prompt() {
  if [ -n "$SSH_CLIENT$SSH2_CLIENT$SSH_TTY" ]; then
    echo "%{$fg[white]%}%n@%{$reset_color%}%{$fg[green]%}%m:%{$reset_color%}"
  fi
}

function _root_prompt() {
  if [ $UID -eq 0 ]; then echo "%{$fg[white]%}#%{$reset_color%}"; fi
}

function _git_branch() {
  local ref
  ref=$(command git symbolic-ref --quiet HEAD 2> /dev/null)
  local ret=$?
  if [[ $ret != 0 ]]; then
    [[ $ret == 128 ]] && return  # no git repo.
    ref=$(command git rev-parse --short HEAD 2> /dev/null) || return
  fi
  echo ${ref#refs/heads/}
}

function _git_branch_prompt() {
  local branch=$(_git_branch)
  if [ -n "$branch" ]; then
    # See http://zsh.sourceforge.net/Doc/Release/Prompt-Expansion.html
    echo " %8F‹ $branch›%f"
  fi
}

precmd() {
  local jobs
  # If there are suspended jobs, display the first argument of each command-line.
  #
  # See http://www.zsh.org/mla/users/2001/threads.html#00700
  if [[ "${(k)jobstates[(r)*+*]}" -gt 0 ]]; then
    jobs=' ['"${jobtexts[@]%% *}"']'
  fi
  psvar=( "$jobs" )
}

export PROMPT="$(_user_hostname_prompt)%{$fg[white]%}%{$reset_color%}%{$fg[yellow]%}%(!.%1~.%~)%{$reset_color%}$(_root_prompt)%{$fg[white]%}%1v%{$reset_color%}\$(_git_branch_prompt) %(?:→:×) "

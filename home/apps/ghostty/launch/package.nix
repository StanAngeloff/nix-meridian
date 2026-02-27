{
  lib,
  writeShellScript,
  name,
  ghostty,
  systemd,
  tmux,
  zsh,
}:
(writeShellScript name ''
  did_focus="$( ${systemd}/bin/busctl --user call org.gnome.Shell /de/lucaswerkmeister/ActivateWindowByTitle de.lucaswerkmeister.ActivateWindowByTitle activateByWmClass s "com.mitchellh.ghostty" )"

  if [ "$did_focus" != "b true" ]; then
    exec ${lib.getExe ghostty} -e ${zsh}/bin/zsh -c \
      '${tmux}/bin/tmux attach-session -t default 2>/dev/null || ${tmux}/bin/tmux new-session -s default -n default'
  fi
'')

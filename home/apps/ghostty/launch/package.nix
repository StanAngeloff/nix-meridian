{
  writeShellScript,
  name,
  ghostty-meridian,
  systemd,
  tmux,
  zsh,
}:
let
  ghostty = ghostty-meridian;
in
(writeShellScript name ''
  did_focus="$( ${systemd}/bin/busctl --user call org.gnome.Shell /de/lucaswerkmeister/ActivateWindowByTitle de.lucaswerkmeister.ActivateWindowByTitle activateByWmClass s "com.mitchellh.ghostty" )"

  if [ "$did_focus" != "b true" ]; then
    exec ${ghostty}/bin/ghostty -e ${zsh}/bin/zsh -c \
      '${tmux}/bin/tmux attach-session -t default 2>/dev/null || ${tmux}/bin/tmux new-session -s default -n default'
  fi
'')

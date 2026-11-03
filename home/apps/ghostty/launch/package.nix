{
  lib,
  pkgs,
  writeShellScript,
  name,
  ghostty,
  systemd,
  tmux,
  zsh,
}:
let
  tmuxDefaultSession = import ../../../../modules/lib/tmux-default-session.nix { inherit pkgs; };
in
(writeShellScript name ''
  did_focus="$( ${systemd}/bin/busctl --user call org.gnome.Shell /de/lucaswerkmeister/ActivateWindowByTitle de.lucaswerkmeister.ActivateWindowByTitle activateByWmClass s "com.mitchellh.ghostty" )"

  if [ "$did_focus" != "b true" ]; then
    exec ${lib.getExe ghostty} -e ${zsh}/bin/zsh -c \
      '${lib.getExe tmuxDefaultSession} && exec ${tmux}/bin/tmux attach-session -t =default'
  fi
'')

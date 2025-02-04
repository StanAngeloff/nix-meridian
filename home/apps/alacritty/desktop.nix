{ config, pkgs, ... }:
{
  dconf.settings = {
    "org/gnome/desktop/default-applications/terminal" = {
      exec = "alacritty";
      exec-arg = "--command";
    };
  };

  home.file."${config.home.homeDirectory}/.local/bin/launch-alacritty" = {
    text = ''
      #!/bin/sh

      did_focus="$( ${pkgs.systemd}/bin/busctl --user call org.gnome.Shell /de/lucaswerkmeister/ActivateWindowByTitle de.lucaswerkmeister.ActivateWindowByTitle activateByWmClass s "Alacritty" )"

      if [ "$did_focus" != "b true" ]; then
        exec ${pkgs.alacritty}/bin/alacritty -e ${pkgs.zsh}/bin/zsh -c \
          '${pkgs.tmux}/bin/tmux attach-session -t default 2>/dev/null || ${pkgs.tmux}/bin/tmux new-session -s default -n default'
      fi
    '';
    executable = true;
  };
}

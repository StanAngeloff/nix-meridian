{
  programs.alacritty = {
    enable = true;
  };

  dconf.settings = {
    "org/gnome/desktop/default-applications/terminal" = {
      exec = "alacritty";
      exec-arg = "--command";
    };
  };
}

{ pkgs, ... }:
{
  programs.gnome-shell.extensions = with pkgs.gnomeExtensions; [
    { package = clipboard-indicator; }
  ];

  dconf.settings."org/gnome/shell/extensions/clipboard-indicator" = {
    cache-size = 10;
    history-size = 50;
    move-item-first = true;
    paste-button = false;
    preview-size = 48;
    clear-history = [ ];
    next-entry = [ ];
    prev-entry = [ ];
    private-mode-binding = [ ];
    show-edit-button = false;
    show-pin-button = false;
    show-tag-button = false;
    toggle-menu = [ "<Super>c" ];
  };
}

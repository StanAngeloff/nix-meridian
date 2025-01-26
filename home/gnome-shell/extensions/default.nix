{
  imports = [
    ./clipboard-indicator.nix
  ];

  dconf.settings."org/gnome/shell" = {
    disable-user-extensions = false;
  };
}

{
  imports = [
    ./gnome-theme.nix
  ];

  programs.thunderbird = {
    enable = true;

    profiles = {
      default = {
        isDefault = true;
      };
    };
  };
}

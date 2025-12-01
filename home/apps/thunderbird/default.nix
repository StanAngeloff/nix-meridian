{
  imports = [
    #./themes/thunderbird-gnome-theme.nix.nix
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

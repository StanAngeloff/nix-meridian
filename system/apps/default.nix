{ pkgs, ... }:
{
  imports = [
    ./annoyances.nix
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # NOTE: nix-ld allows running unpatched dynamic binaries on NixOS.
  #
  # - This is a prerequisite for `aapt` when Expo does an Android build.
  # - This allows using Node.js binaries directly without needing to compile from source (e.g., `mise install node@24`).
  programs.nix-ld = {
    enable = true;

    # The default `libraries` are sufficient for most use cases.
  };

  # List packages to exclude from the default Gnome desktop environment.
  environment.gnome.excludePackages = with pkgs; [
    evince
  ];
}

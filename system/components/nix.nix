{
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Nix will automatically detect files in the store that have identical contents,
  # and replaces them with hard links to a single copy. (default: false)
  nix.settings.auto-optimise-store = true;
}

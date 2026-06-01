{
  # NOTE: programs.adb was removed in nixpkgs 26.05; systemd 258 handles uaccess rules natively.
  # android-tools is now installed as a user package in home/apps/default.nix.

  services.gvfs = {
    # GVfs, a userspace virtual filesystem, is needed for file transfer over MTP.
    enable = true;
  };
}

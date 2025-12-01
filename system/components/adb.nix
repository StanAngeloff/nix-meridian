{
  programs.adb = {
    enable = true;
  };

  services.gvfs = {
    # GVfs, a userspace virtual filesystem, is needed for file transfer over MTP.
    enable = true;
  };
}

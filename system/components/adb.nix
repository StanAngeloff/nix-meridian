{ pkgs, ... }:
{
  programs.adb = {
    enable = true;
  };

  services.udev.packages = with pkgs; [
    # The below is needed to enable "Transferring images" USB configuration.
    # Learn more at https://github.com/M0Rf30/android-udev-rules
    android-udev-rules
  ];

  services.gvfs = {
    # GVfs, a userspace virtual filesystem, is needed for file transfer over MTP.
    enable = true;
  };
}

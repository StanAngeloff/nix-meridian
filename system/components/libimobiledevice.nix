{ pkgs, ... }:
{
  # Learn more at https://nixos.wiki/wiki/IOS
  #
  services.usbmuxd = {
    enable = true;
    package = pkgs.usbmuxd2;
  };

  environment.systemPackages = with pkgs; [
    libimobiledevice
    ifuse
    # List/modify installed apps of iOS devices:
    ideviceinstaller
  ];
}

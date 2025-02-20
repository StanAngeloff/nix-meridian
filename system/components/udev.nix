{ pkgs, ... }:
{
  services.udev = {
    # This is a documented requirement for appindicator  ¯\_(ツ)_/¯
    packages = with pkgs; [ gnome-settings-daemon ];

    # See https://nixos.wiki/wiki/Power_Management#Solution_1:_Disabling_wakeup_triggers_for_all_PCIe_devices
    extraRules = ''
      ACTION=="add", SUBSYSTEM=="pci", DRIVER=="pcieport", ATTR{power/wakeup}="disabled"
    '';
  };
}

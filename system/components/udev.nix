{ pkgs, ... }:
{
  services.udev = {
    packages = with pkgs; [
      # Learn more at https://wiki.nixos.org/wiki/GNOME#Enable_system_tray_icons ¯\_(ツ)_/¯
      gnome-settings-daemon
    ];

    # See https://nixos.wiki/wiki/Power_Management#Solution_1:_Disabling_wakeup_triggers_for_all_PCIe_devices
    extraRules = ''
      ACTION=="add", SUBSYSTEM=="pci", DRIVER=="pcieport", ATTR{power/wakeup}="disabled"
    '';
  };
}

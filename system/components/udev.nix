{ pkgs, ... }:
{
  services.udev = {
    packages = with pkgs; [
      # Learn more at https://wiki.nixos.org/wiki/GNOME#Enable_system_tray_icons ¯\_(ツ)_/¯
      gnome-settings-daemon
      # The below is needed to enable "Transferring images" USB configuration.
      # Learn more at https://github.com/M0Rf30/android-udev-rules
      android-udev-rules
    ];

    # See https://nixos.wiki/wiki/Power_Management#Solution_1:_Disabling_wakeup_triggers_for_all_PCIe_devices
    extraRules = ''
      ACTION=="add", SUBSYSTEM=="pci", DRIVER=="pcieport", ATTR{power/wakeup}="disabled"
    '';
  };
}

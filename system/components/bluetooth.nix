{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;

    input = {
      General = {
        # See https://wiki.archlinux.org/title/Bluetooth_mouse#Thinkpad_Bluetooth_Laser_Mouse_problems
        UserspaceHID = true;
      };
    };
  };

  services.blueman.enable = true;
}

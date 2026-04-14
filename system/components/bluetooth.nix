{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;

    input = {
      General = {
        # Learn more at https://wiki.archlinux.org/title/Bluetooth_mouse#Thinkpad_Bluetooth_Laser_Mouse_problems
        # See https://github.com/bluez/bluez/blob/master@%7B2025-08-21%7D/profiles/input/input.conf#L12
        UserspaceHID = true;
      };
    };

    settings = {
      General = {
        # See https://github.com/bluez/bluez/blob/master@%7B2025-08-21%7D/src/main.conf#L125
        # This will allow Gnome Shell to report battery levels for Bluetooth devices.
        Experimental = true;
        # Enables kernel experimental features, alternatively a list of UUIDs can be given:
        # - "6fbaf188-05e0-496a-9885-d6ddfdb4e03e" - Unlocks Isochronous sockets in the kernel
        KernelExperimental = true; # Unlocks Isochronous sockets in the kernel
        ControllerMode = "dual"; # Use both BR/EDR and LE modes, which is required for LE Audio support
      };
    };
  };

  services.blueman.enable = true;
}

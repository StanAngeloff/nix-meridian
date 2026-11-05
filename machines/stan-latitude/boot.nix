{
  # Use the systemd-boot EFI boot loader.
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 0;
  };

  boot.initrd.kernelModules = [
    "dm-snapshot"
    "cryptd"
  ];
  boot.initrd.luks.devices = {
    "cryptroot" = {
      device = "/dev/disk/by-label/NIXOS_LUKS";
    };
  };
  #boot.kernelParams = [ "quiet" ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_HOME";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXOS_BOOT";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  # The partition fills with idle swapped-out memory, which leaves no room for a hibernation image, and the volume group has no free space to grow it.
  # At equal priority the kernel alternates between the two, so the file always has the most free space and systemd hibernates to it.
  swapDevices = [
    {
      device = "/dev/disk/by-label/NIXOS_SWAP";
      priority = 10;
    }
    {
      device = "/var/lib/swapfile";
      size = 32 * 1024;
      priority = 10;
    }
  ];
}

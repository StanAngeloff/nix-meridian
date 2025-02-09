{
  config,
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking.hostName = "stan-latitude";

  # Use the systemd-boot EFI boot loader.
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
    timeout = 0;
  };

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "vmd"
    "nvme"
    "usb_storage"
    "sd_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.initrd.kernelModules = [
    "dm-snapshot"
    "cryptd"
  ];
  boot.initrd.luks.devices = {
    "cryptroot" = {
      device = "/dev/disk/by-label/NIXOS_LUKS";
    };
  };
  boot.kernelModules = [ "kvm-intel" ];
  #boot.kernelParams = [ "quiet" ];
  boot.extraModulePackages = [ ];

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

  swapDevices = [
    { device = "/dev/disk/by-label/NIXOS_SWAP"; }
  ];

  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;
}

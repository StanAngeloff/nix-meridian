{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.nixos-hardware.nixosModules.dell-latitude-5520 # …close enough, right? Right?!
    "${inputs.nixpkgs}/pkgs/by-name/sa/samsung-unified-linux-driver_1_00_36/module.nix"
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

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Enable the Samsung Unified Linux Driver module directly instead of setting printing drivers.
  services.samsung-unified-linux-driver_1_00_36 = {
    enable = true; # Adds support for Samsung M2022W
  };

  services.printing.drivers = with pkgs; [
    epson-escpr # Adds support for Epson L3250
  ];

  services.fprintd = {
    enable = true;

    tod = {
      enable = true;
      driver = pkgs.libfprint-2-tod1-broadcom;
    };
  };
}

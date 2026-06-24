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

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "vmd"
    "nvme"
    "usb_storage"
    "sd_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

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

{ inputs, ... }:
let
  # bootvine 0.1.3 ignores the isolate to emergency or rescue mode and keeps pulling its terminal (tty12) to the front,
  # which hides the emergency shell after a failed LUKS unlock. Upstream's fix, a7aa038 (after 0.1.3), adds both
  # services to the unit's Before= and Conflicts=, so starting either stops bootvine; drop this once pkgs/bootvine is newer.
  emergencyShellHandover = {
    before = [
      "emergency.service"
      "rescue.service"
    ];
    conflicts = [
      "emergency.service"
      "rescue.service"
    ];
  };
in
{
  # nixos-26.05 has no bootvine module; nixpkgs-unstable's runs pkgs.bootvine, which pkgs/bootvine pins to a reviewed release.
  imports = [ "${inputs.nixpkgs-unstable}/nixos/modules/services/system/bootvine.nix" ];

  services.bootvine.enable = true;

  systemd.services.bootvine = emergencyShellHandover;
  boot.initrd.systemd.services.bootvine = emergencyShellHandover;
}

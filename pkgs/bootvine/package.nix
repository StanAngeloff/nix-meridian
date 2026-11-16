{
  lib,
  rustPlatform,
  fetchFromGitea,
  pkg-config,
  dbus,
  systemdLibs,
  versionCheckHook,
}:
# Live tree of systemd jobs on the boot console; system/components/bootvine.nix runs it.
# Copied from nixpkgs-unstable's pkgs/by-name/bo/bootvine, which nixos-26.05 lacks; delete this once the release ships it.
# It runs as root from the initrd on and receives the LUKS passphrase, so the version and hashes are a security pin:
# bump them only after reading the upstream diff. That is also why this copy drops nix-update-script.
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "bootvine";
  version = "0.1.3";
  __structuredAttrs = true;

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "wvhulle";
    repo = "bootvine";
    tag = "v${finalAttrs.version}";
    hash = "sha256-WzqLbOcOokwn2XT62YdD3llWZbNhMl/STbJb2Yn2/pQ=";
  };

  cargoHash = "sha256-uoWys8kdGUZ3YeriNLsU8we/kSTvCswQkzdnhTIEtCY=";

  cargoBuildFlags = [
    "--bin"
    "bootvine"
  ];

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    dbus
    systemdLibs
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  meta = {
    changelog = "https://codeberg.org/wvhulle/bootvine/releases/tag/${finalAttrs.src.tag}";
    description = "Boot animation showing stages of systemd as a tree";
    homepage = "https://codeberg.org/wvhulle/bootvine";
    license = lib.licenses.gpl3Plus;
    mainProgram = "bootvine";
    platforms = lib.platforms.linux;
  };
})

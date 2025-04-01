{
  proton-pass,
  fetchurl,
}:
proton-pass.overrideAttrs (finalAttrs: rec {
  version = "1.29.8"; # Override the version, as of 2025-02-11 the NixOS version is outdated.
  src = fetchurl {
    url = "https://proton.me/download/pass/linux/x64/proton-pass_${version}_amd64.deb";
    hash = "sha256-xwXIcoBPhANKiTv7DP+gmVeCtuzjymtQmHu+HuRKqjU=";
  };
})

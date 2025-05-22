{ lib, pkgs, ... }:
{
  home.packages = [ pkgs.jump ];

  programs.zsh.initContent =
    let
      zshConfigAfter = lib.mkOrder 1510 ''
        eval "$(${pkgs.jump}/bin/jump shell --bind=z)"
      '';
    in
    lib.mkMerge [ zshConfigAfter ];
}

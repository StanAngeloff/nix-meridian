{ pkgs, ... }:
{
  home.packages = [ pkgs.jump ];

  programs.zsh.initExtra = ''
    eval "$(${pkgs.jump}/bin/jump shell --bind=z)"
  '';
}

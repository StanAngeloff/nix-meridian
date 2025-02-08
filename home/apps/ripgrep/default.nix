{ config, ... }:
let
  configPath = "${config.home.homeDirectory}/.config/ripgrep/config";
in
{
  programs.ripgrep = {
    enable = true;
  };

  home.sessionVariables.RIPGREP_CONFIG_PATH = configPath;

  home.file."${configPath}".text = ''
    --hidden
    --ignore-vcs
    --smart-case
    --glob=!.git/*
    # See https://github.com/BurntSushi/ripgrep/blob/master/FAQ.md#silver-searcher-output
    #
    --colors=line:fg:yellow
    --colors=line:style:bold
    --colors=path:fg:green
    --colors=path:style:bold
    --colors=match:fg:black
    --colors=match:bg:yellow
    --colors=match:style:nobold
  '';
}

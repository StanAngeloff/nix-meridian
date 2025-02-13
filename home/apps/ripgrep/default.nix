{ config, ... }:
let
  configPath = "${config.home.homeDirectory}/.config/ripgrep/config";
in
{
  programs.ripgrep = {
    enable = true;
  };

  home.sessionVariables.RIPGREP_CONFIG_PATH = configPath;

  # NOTE: See home/apps/nixvim/plugins/fzf-lua.nix - the default ripgrep configuration is duplicated for fzf.
  home.file."${configPath}".text = ''
    --hidden
    --ignore-vcs
    --smart-case
    --glob=!.git/*
    --glob=!node_modules/*
    --colors=line:fg:yellow
    --colors=line:style:bold
    --colors=path:fg:green
    --colors=path:style:bold
    --colors=match:fg:black
    --colors=match:bg:yellow
    --colors=match:style:nobold
  '';
}

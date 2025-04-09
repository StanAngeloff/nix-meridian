{ pkgs, pkgs-unstable, ... }:
{
  programs.nixvim.plugins.copilot-lua = {
    enable = true;
    package = pkgs-unstable.vimPlugins.copilot-lua;

    copilotNodeCommand = "${pkgs.nodejs_22}/bin/node";

    suggestion = {
      enabled = true;
      autoTrigger = true;
    };

    filetypes = {
      markdown = true;
    };
  };
}

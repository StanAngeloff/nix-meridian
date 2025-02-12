{ pkgs, ... }:
{
  programs.nixvim.plugins.copilot-lua = {
    enable = true;

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

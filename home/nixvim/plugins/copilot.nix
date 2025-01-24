{ pkgs, ... }:
{
  programs.nixvim.plugins.copilot-vim = {
    enable = true;

    settings = {
      node_command = "${pkgs.nodejs_22}/bin/node";
    };
  };
}

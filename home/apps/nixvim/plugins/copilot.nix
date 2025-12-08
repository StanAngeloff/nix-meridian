{ pkgs, pkgs-unstable, ... }:
{
  programs.nixvim = {
    plugins.copilot-lua = {
      enable = true;
      package = pkgs-unstable.vimPlugins.copilot-lua;

      settings = {
        copilot_node_command = "${pkgs.nodejs_24}/bin/node";

        suggestion = {
          enabled = true;
          auto_trigger = true;
        };

        filetypes = {
          markdown = true;
        };
      };
    };

    extraConfigLua = ''
      vim.api.nvim_set_hl(0, "CopilotSuggestion", { fg = "#00a3a2", bg = "#003131", italic = true })
      vim.api.nvim_set_hl(0, "CopilotAnnotation", { fg = "#00a3a2", bg = "#003131", bold = true })
    '';
  };
}

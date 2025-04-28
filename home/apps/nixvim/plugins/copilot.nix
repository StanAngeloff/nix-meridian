{ pkgs, pkgs-unstable, ... }:
{
  programs.nixvim = {
    plugins.copilot-lua = {
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

    extraConfigLua = ''
      vim.api.nvim_set_hl(0, "CopilotSuggestion", { fg = "#00a3a2", bg = "#003131", italic = true })
      vim.api.nvim_set_hl(0, "CopilotAnnotation", { fg = "#00a3a2", bg = "#003131", bold = true })
    '';
  };
}

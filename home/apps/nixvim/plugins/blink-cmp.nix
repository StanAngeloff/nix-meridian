{ pkgs-unstable, ... }:
{
  programs.nixvim = {
    plugins.blink-cmp = {
      enable = true;
      package = pkgs-unstable.vimPlugins.blink-cmp;

      # See https://github.com/Saghen/blink.cmp/blob/v0.5.1/lua/blink/cmp/config.lua
      settings = {
        sources = {
          default = [
            "lsp"
            "path"
            "buffer"
          ];

          providers = {
            buffer = {
              opts = {
                # See https://github.com/Saghen/blink.cmp/blob/v1.1.1/doc/recipes.md#buffer-completion-from-all-open-buffers
                get_bufnrs.__raw = ''
                  function()
                    return vim.tbl_filter(function(bufnr)
                      return vim.bo[bufnr].buftype == ""
                    end, vim.api.nvim_list_bufs())
                  end
                '';
              };
            };
          };
        };

        completion = {
          accept = {
            auto_brackets = {
              enabled = true;
            };
          };
          documentation = {
            auto_show = true;
            window.border = "rounded";
          };
          list = {
            selection = {
              auto_insert = true;
            };
          };
        };

        signature = {
          enabled = true;
          window.border = "rounded";
        };

        cmdline = {
          keymap = {
            preset = "inherit";

            "<Tab>" = [
              {
                __raw = # lua
                  ''
                    function(cmp)
                      if cmp.is_ghost_text_visible() and not cmp.is_menu_visible() then return cmp.accept() end
                    end
                  '';
              }
              "show_and_insert"
              "select_next"
            ];
          };
        };

        keymap = {
          preset = "none";

          "<CR>" = [
            "accept"
            "fallback"
          ];
          "<Tab>".__raw = # lua
            ''
              {
                "accept",
                function(cmp)
                  if require("copilot.suggestion").is_visible() then
                    require('copilot.suggestion').accept()
                    return true
                  end
                  return false
                end,
                "fallback"
              }
            '';
          "<C-P>" = [
            "select_prev"
            "fallback"
          ];
          "<C-K>" = [
            "select_prev"
            "fallback"
          ];
          "<C-J>" = [
            "select_next"
            "fallback"
          ];
          "<C-N>" = [
            "select_next"
            "fallback"
          ];
          "<C-H>" = [
            "show_signature"
            "hide_signature"
            "fallback"
          ];
          "<C-E>" = [
            "hide"
          ];
          "<M-]>" = [
            "hide"
            "fallback"
          ];
        };
      };
    };

    extraConfigLua = ''
      vim.api.nvim_set_hl(0, "BlinkCmpMenuBorder", { link = "FloatBorder" })
      vim.api.nvim_set_hl(0, "BlinkCmpSignatureHelpBorder", { link = "FloatBorder" })
      vim.api.nvim_set_hl(0, "BlinkCmpDocBorder", { link = "FloatBorder" })
      vim.api.nvim_set_hl(0, "BlinkCmpDocSeparator", { link = "BlinkCmpDocBorder" })
    '';
  };

}

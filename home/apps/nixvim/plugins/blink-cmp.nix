{ pkgs-unstable, ... }:
{
  programs.nixvim.plugins.blink-cmp = {
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
      };

      completion = {
        accept = {
          auto_brackets = {
            enabled = true;
          };
        };
        documentation = {
          auto_show = true;
          window.border = "single";
        };
        list = {
          selection = {
            auto_insert = true;
          };
        };
      };

      signature = {
        enabled = true;
        window.border = "single";
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
}

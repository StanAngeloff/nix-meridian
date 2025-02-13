{
  programs.nixvim.plugins.blink-cmp = {
    enable = true;

    luaConfig.pre = # lua
      ''
        -- The version packages in Nix as of 2025-02-12 does not support "none" preset.
        require('blink.cmp.keymap').get_preset_keymap = function()
          return {}
        end
      '';

    # See https://github.com/Saghen/blink.cmp/blob/v0.5.1/lua/blink/cmp/config.lua
    settings = {
      sources = {
        default = [
          "lsp"
          "path"
          "buffer"
        ];
      };

      windows = {
        documentation = {
          auto_show = true;
        };
        autocomplete = {
          selection = "auto_insert";
        };
      };
      accept = {
        auto_brackets = {
          enabled = true;
        };
      };
      trigger = {
        signature_help = {
          enabled = true;
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
        "<C-K>" = [
          "select_prev"
          "fallback"
        ];
        "<C-J>" = [
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

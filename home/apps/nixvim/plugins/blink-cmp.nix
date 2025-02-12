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

    settings = {
      signature.enabled = true;

      sources = {
        default = [
          "lsp"
          "path"
          "buffer"
        ];
      };

      keymap = {
        preset = "none";
        "<CR>" = [
          "select_and_accept"
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

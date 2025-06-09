{ pkgs-unstable, ... }:
{
  programs.nixvim = {
    plugins.codecompanion = {
      enable = true;
      package = pkgs-unstable.vimPlugins.codecompanion-nvim;

      settings = {
        adapters = {
          anthropic.__raw = ''
            function()
              return require("codecompanion.adapters").extend("anthropic", {
                env = {
                  api_key = "cmd:secret-tool lookup service anthropic key api",
                },
              })
            end
          '';
          openai.__raw = ''
            function()
              return require("codecompanion.adapters").extend("openai", {
                env = {
                  api_key = "cmd:secret-tool lookup service openai key api",
                },
              })
            end
          '';
        };
        strategies = {
          chat = {
            adapter = "anthropic";
            keymaps = {
              close = {
                modes = {
                  n = "q";
                  i = "<C-q>";
                };
              };
              send = {
                modes = {
                  n = "<C-]>";
                  i = "<C-]>";
                };
              };
              stop = {
                modes = {
                  n = "<C-c>";
                };
              };
            };
          };
          inline = {
            adapter = "copilot";
          };
          cmd = {
            adapter = "anthropic";
          };
        };
        display = {
          chat = {
            show_settings = false;
            start_in_insert_mode = true;
            show_header_separator = true;
            window = {
              layout = "float";
            };
          };
        };
      };
    };

    keymaps = [
      {
        key = "<leader>c";
        mode = [
          "n"
          "v"
        ];
        action.__raw = ''function() require('codecompanion').toggle() end'';
      }
    ];
  };
}

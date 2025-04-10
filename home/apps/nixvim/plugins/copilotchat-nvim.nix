{ pkgs-unstable, ... }:
{
  programs.nixvim = {
    plugins.copilot-chat = {
      enable = true;
      package = pkgs-unstable.vimPlugins.CopilotChat-nvim;

      settings = {
        model = "claude-3.7-sonnet";
        context = "buffer";

        auto_insert_mode = true;

        window = {
          layout = "float";
        };

        mappings = {
          close = {
            insert = "<C-q>";
            normal = "q";
          };
          submit_prompt = {
            normal = "<C-]>";
            insert = "<C-]>";
          };
          accept_diff = {
            normal = "<CR>";
            insert = "<C-y>";
          };
        };
      };
    };

    keymaps = [
      {
        key = "<leader>c";
        mode = [ "n" ];
        action.__raw = ''function() require('CopilotChat').toggle() end'';
      }
    ];
  };
}

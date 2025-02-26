{ pkgs, ... }:
{
  programs.nixvim = {
    extraPlugins =
      let
        claudius-nvim = (
          pkgs.vimUtils.buildVimPlugin {
            name = "claudius.nvim";
            src = pkgs.fetchFromGitHub {
              owner = "StanAngeloff";
              repo = "claudius.nvim";
              rev = "9817214a57d163840b69ea2b23c2288a0c405ec7";
              hash = "sha256-1ojmlEXz4tliHy+XVxoFPg1hrZabpCZy7um2Brjzc5M=";
            };
          }
        );
      in
      [
        claudius-nvim
      ];

    extraConfigLua = ''
      require("claudius").setup({
        parameters = {
          max_tokens = 8000,
        },
        editing = {
          auto_write = true,
        },
        pricing = {
          enabled = true,
        },
        signs = {
          enabled = true,
        },
      })
    '';
  };
}

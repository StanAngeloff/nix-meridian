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
              rev = "09dd0d81f485ce6ad263ee01b4970ed19ac6ec90";
              hash = "sha256-44mElF6/wNL5eiBM8rvpYmfRjFXHpUvhIXMAArC4M50=";
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

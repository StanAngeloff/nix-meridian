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
              rev = "4c2883e467a6a19f45ebb90fb4bddfa75fdb5c6f";
              hash = "sha256-jQ4bI7clOgUyOFLyFHHv/BePNTwN+njrPzaGo9vHgZQ=";
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

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
              rev = "1fa13dfa747253f7e88a54e7984fe1168edd3aa4";
              hash = "sha256-3xjmtSYRcjT1TGEhxUgYxnbU1kU52cbvZpsNRfJYczY=";
            };
          }
        );
      in
      [
        claudius-nvim
      ];

    extraConfigLua = ''
      require("claudius").setup({
        signs = {
          enabled = true,
        },
      })
    '';
  };
}

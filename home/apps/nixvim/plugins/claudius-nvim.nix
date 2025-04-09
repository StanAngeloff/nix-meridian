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
              rev = "cac7d0f6a72474ef1c8fec4a27e4982f353caaf8";
              hash = "sha256-obSWGtYPJahqESCv3s/qmsPV/bijNbfv53pCML0qMj8=";
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

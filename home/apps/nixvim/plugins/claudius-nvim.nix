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
              rev = "31936c241b25bf70bab0e4b15318c88f1b930786";
              hash = "sha256-hYY/VIFFanagZDM3B2rhEDsdWCddvra//AI1q9vP/fs=";
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

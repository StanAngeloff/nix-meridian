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
              rev = "969b5832f7e14819bef78711532dca674e995cae";
              hash = "sha256-E0tw4HmGLSmVGHlWVSHWy/whyLaSUIioDWkvuyUMf7s=";
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
        pricing = {
          enabled = false,
        },
        signs = {
          enabled = true,
        },
      })
    '';
  };
}

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
              rev = "2c8be4b08474007e8b25941eeb79532e2b2e636c";
              hash = "sha256-2OeP35C7nffz0WK2dp26jBga8myZNXe+Sdmhplhf0XA=";
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

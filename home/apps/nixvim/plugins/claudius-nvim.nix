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
              rev = "4050291456fcba371930bfa0bf9f53c929a765bd";
              hash = "sha256-sC92vwmvgx+6B7movZFTo4ez5sUy3UmGbWGAmOLYCx4=";
            };
          }
        );
      in
      [
        claudius-nvim
      ];

    extraConfigLua = ''
      require("claudius").setup({ })
    '';
  };
}

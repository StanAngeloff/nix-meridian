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
              rev = "8eaf30422251c6b61c52d8a333504e60ab461c4b";
              hash = "sha256-1TwJz7T10OVpraHgN2nRBdrtI1hSzBmVHUNdBEgQ2Qg=";
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

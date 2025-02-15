{ pkgs, ... }:
{
  programs.nixvim = {
    extraPlugins =
      let
        vim-troll-stopper = (
          pkgs.vimUtils.buildVimPlugin {
            name = "vim-troll-stopper";
            src = pkgs.fetchFromGitHub {
              owner = "vim-utils";
              repo = "vim-troll-stopper";
              rev = "24a9db129cd2e3aa2dcd79742b6cb82a53afef6c";
              hash = "sha256-5Fa/zK5f6CtRL+adQj8x41GnwmPWPV1+nCQta8djfqs=";
            };
          }
        );
      in
      [
        vim-troll-stopper
      ];
  };
}

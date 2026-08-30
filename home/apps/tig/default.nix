{
  lib,
  pkgs,
  ...
}:
let
  tig = pkgs.tig;
  ansiless = cmd: "${lib.getExe pkgs.perl} -pe 's/\\e\\[[0-9;]*m//g' | ${cmd}";

  popupNvim = import ../../../modules/lib/popup-nvim.nix { inherit pkgs; };

  tigAnnotate = pkgs.writeShellApplication {
    name = "tig-annotate";
    bashOptions = [
      "pipefail"
      "nounset"
    ];
    runtimeInputs = [
      popupNvim
      pkgs.tmux
      pkgs.python3
      pkgs.fzf
      pkgs.wl-clipboard
      pkgs.util-linux
      pkgs.glib
      pkgs.libnotify
    ];
    text = builtins.readFile ./annotate/tig-annotate.sh;
  };
in
{
  home.packages = [
    tig
    tigAnnotate
  ];

  home.file.".config/tig/config".source = ./tigrc;
  home.file.".config/tig/vim.tigrc".text =
    builtins.readFile ./vim.tigrc
    + builtins.replaceStrings [ "@tigAnnotate@" ] [ (lib.getExe tigAnnotate) ] (
      builtins.readFile ./annotate/bindings.tigrc
    );

  programs.git = {
    settings = {
      pager = {
        diff = ansiless (lib.getExe tig);
        show = ansiless (lib.getExe tig);
      };
    };
  };
}

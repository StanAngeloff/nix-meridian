{ claude-cc }:
{ lib, pkgs, ... }:
let
  # The hub's list is the tmux navigator's (tmux-navigator pick), built as home/apps/tmux/default.nix builds it.
  navigator = pkgs.callPackage ../../tmux/navigator/package.nix {
    links = import ../footer-links.nix;
  };
  cc-hub = pkgs.writeShellApplication {
    name = "cc-hub";
    runtimeInputs = [
      navigator
      pkgs.tmux
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gawk
      (import ../../../../modules/lib/tmux-default-session.nix { inherit pkgs; })
    ];
    # hub.sh gets store paths rather than command names, because tmux runs a new window's command in the tmux server's
    # environment rather than the hub's.
    text =
      builtins.replaceStrings
        [ "@claudeCc@" "@direnv@" ]
        [ (lib.getExe claude-cc) (lib.getExe pkgs.direnv) ]
        (builtins.readFile ./hub.sh);
  };
in
{
  home.packages = [ cc-hub ];

  programs.tmux.extraConfig = ''
    # Remote access: tap ◀ Sessions (x < 12) to detach back to the hub.
    bind -n MouseDown1StatusDefault if -F '#{==:#S,remote}' 'if-shell "[ #{mouse_x} -lt 12 ]" "detach-client"'

    # Remote access: prefix + Escape as a keybind fallback for the same action.
    bind Escape if -F '#{==:#S,remote}' 'detach-client'
  '';
}

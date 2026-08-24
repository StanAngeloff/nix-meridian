{ pkgs, ... }:
let
  cc-hub = pkgs.writeShellApplication {
    name = "cc-hub";
    runtimeInputs = [
      pkgs.tmux
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gawk
    ];
    text = builtins.readFile ./hub.sh;
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

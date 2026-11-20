{ claude-cc }:
{ lib, pkgs, ... }:
let
  # The hub's list is the tmux navigator's (tmux-navigator pick), built as home/apps/tmux/default.nix builds it.
  navigator = pkgs.callPackage ../../tmux/navigator/package.nix {
    links = import ../footer-links.nix;
  };
  # The hub's new-session screens: a directory, then a profile and a name, drawn with the navigator's draw.py.
  new-session = pkgs.stdenv.mkDerivation {
    pname = "cc-hub-new-session";
    version = "0";

    # Listed explicitly so a stray __pycache__ from running the tests by hand cannot change the hash.
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./new_session.py
        ./test_new_session.py
      ];
    };

    nativeBuildInputs = [ pkgs.makeWrapper ];

    dontBuild = true;

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      PYTHONPATH=${navigator}/share/tmux-navigator ${pkgs.python3}/bin/python3 -m unittest discover -p 'test_*.py'
      runHook postCheck
    '';

    installPhase = ''
      runHook preInstall
      install -Dm644 -t $out/share/cc-hub-new-session new_session.py
      makeWrapper ${pkgs.python3}/bin/python3 $out/bin/cc-hub-new-session \
        --add-flags $out/share/cc-hub-new-session/new_session.py \
        --prefix PYTHONPATH : ${navigator}/share/tmux-navigator
      runHook postInstall
    '';

    meta.mainProgram = "cc-hub-new-session";
  };
  cc-hub = pkgs.writeShellApplication {
    name = "cc-hub";
    runtimeInputs = [
      new-session
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

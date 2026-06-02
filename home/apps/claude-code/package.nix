{
  lib,
  symlinkJoin,
  makeWrapper,
  claude-code-unwrapped,
}:
let
  env = import ./env.nix;
in
symlinkJoin {
  name = "claude-code";
  paths = [ claude-code-unwrapped ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/claude \
      --run '
        # $TMPDIR resolves to different paths between sandboxed and unsandboxed
        # commands in the same session. On NixOS, TMP/TMPDIR may also be unset
        # entirely, causing "$TMPDIR/file.txt" to collapse to "/file.txt".
        # Fixed in 2.1.154 but we keep sane defaults as a safety net.
        # See https://github.com/anthropics/claude-code/issues/48541
        CLAUDE_TMPDIR="/tmp/claude-$(id -u)"
        mkdir -p "$CLAUDE_TMPDIR"
        export TMP="''${TMP:-$CLAUDE_TMPDIR}"
        export TMPDIR="''${TMPDIR:-/tmp}"
      ' \
      ${lib.concatStringsSep " \\\n      " (
        lib.mapAttrsToList (name: value: "--set ${name} ${lib.escapeShellArg (toString value)}") env
      )}
  '';
  meta.mainProgram = "claude";
}

{
  lib,
  symlinkJoin,
  makeWrapper,
  libsecret,
  poppler-utils,
  claude-code-unwrapped,
}:
let
  env = import ./env.nix;
  keyring = import ./keyring.nix { inherit lib libsecret; };
in
symlinkJoin {
  name = "claude-code";
  paths = [ claude-code-unwrapped ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    # Put poppler's pdftoppm on PATH so the Read tool can rasterise PDFs without a nix shell (which the sealed bubble blocks); --suffix defers to any poppler already on PATH.
    wrapProgram $out/bin/claude \
      --suffix PATH : ${lib.makeBinPath [ poppler-utils ]} \
      --run '
        # $TMPDIR resolves to different paths between sandboxed and unsandboxed commands in the same session.
        # On NixOS, TMP/TMPDIR may also be unset entirely, causing "$TMPDIR/file.txt" to collapse to "/file.txt".
        # Fixed in 2.1.154 but we keep sane defaults as a safety net.
        # See https://github.com/anthropics/claude-code/issues/48541
        #
        CLAUDE_TMPDIR="/tmp/claude-$(id -u)"
        mkdir -p "$CLAUDE_TMPDIR"
        export TMP="''${TMP:-$CLAUDE_TMPDIR}"
        export TMPDIR="''${TMPDIR:-/tmp}"
        # Relocate ~/.claude.json into ~/.claude so it rides the bubble directory bind and Claude Code owns it live (never a single-file bind — EBUSY on rename).
        # Set host-wide so bare claude and the bubble agree on one inode.
        export CLAUDE_CONFIG_DIR="''${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
      ' \
      --run '
        # Resolve the GitHub token at launch: ~/.claude.json carries only a "Bearer ''${GH_TOKEN}" placeholder
        # (Claude Code expands environment variables in MCP headers), so the literal token never sits on disk.
        # The same variable authenticates the gh CLI, which prefers GH_TOKEN over its own stored OAuth.
        # Never clobber a caller-provided GH_TOKEN (callers may resolve it themselves, e.g. a sandbox wrapper running without keyring access),
        # and fail silent so keyring-less contexts still start.
        # Resolution order: caller-provided > keyring PAT (envchain) > gh OAuth token.
        # Note: a gh OAuth token can be rotated (gh auth refresh, expiry); it is captured at launch, so a mid-session rotation is only picked up on the next launch.
        if [ -z "''${GH_TOKEN:-}" ]; then
          GH_TOKEN="$(${keyring.lookupCommand "GH_TOKEN"} 2>/dev/null || true)"
          if [ -z "$GH_TOKEN" ]; then
            GH_TOKEN="$(gh auth token 2>/dev/null || true)"
          fi
          if [ -n "$GH_TOKEN" ]; then
            export GH_TOKEN
          fi
        fi
      ' \
      ${lib.concatStringsSep " \\\n      " (
        lib.mapAttrsToList (name: value: "--set-default ${name} ${lib.escapeShellArg (toString value)}") env
      )}
  '';
  meta.mainProgram = "claude";
}

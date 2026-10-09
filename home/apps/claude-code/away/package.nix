{
  lib,
  stdenvNoCC,
  writeShellApplication,
  coreutils,
  jq,
}:
# Away mode (/away): the PermissionRequest hook that denies an unanswered prompt, with the mod that tells it when as passthru.mod;
# see claude-away.sh and mod/hooks/register.tsx.
# writeShellApplication runs shellcheck at build time and sets meta.mainProgram, so lib.getExe resolves it.
let
  # The mod's plugin folder, for CLAUDE_CODE_PLUGIN_DIRS; its tests are left out.
  mod = stdenvNoCC.mkDerivation {
    pname = "claude-away-mod";
    inherit (lib.importJSON ./mod/.claude-plugin/plugin.json) version;

    src = lib.fileset.toSource {
      root = ./mod;
      fileset = lib.fileset.unions [
        ./mod/.claude-plugin/plugin.json
        ./mod/hooks/hooks.json
        ./mod/hooks/register.tsx
        ./mod/types/index.d.ts
      ];
    };

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      cp -r . $out
      runHook postInstall
    '';
  };
in
writeShellApplication {
  name = "claude-away";

  runtimeInputs = [
    coreutils
    jq
  ];

  text = builtins.readFile ./claude-away.sh;

  passthru = { inherit mod; };
}

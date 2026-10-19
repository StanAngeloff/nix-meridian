{
  lib,
  stdenvNoCC,
}:
# The /profile mod's plugin folder, for CLAUDE_CODE_PLUGIN_DIRS (../settings.nix); its tests are left out.
stdenvNoCC.mkDerivation {
  pname = "claude-profile-mod";
  inherit (lib.importJSON ./mod/.claude-plugin/plugin.json) version;

  src = lib.fileset.toSource {
    root = ./mod;
    fileset = lib.fileset.unions [
      ./mod/.claude-plugin/plugin.json
      ./mod/hooks/hooks.json
      ./mod/hooks/register.ts
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    cp -r . $out
    runHook postInstall
  '';
}

{
  config,
  lib,
  pkgs,
  ...
}:
# Claude Code mods: each folder here is one plugin folder, named by its .claude-plugin/plugin.json.
# A folder may hold more than the mod, as away/ holds its command hook; only what Claude Code loads goes into the build.
let
  # The manifest, the hooks module and, for a mod that keeps $.state, its type contract; tests are left out.
  buildMod =
    folder:
    let
      manifest = lib.importJSON (folder + "/.claude-plugin/plugin.json");
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = "claude-${manifest.name}-mod";
      inherit (manifest) version;

      src = lib.fileset.toSource {
        root = folder;
        fileset = lib.fileset.unions (
          [
            (folder + "/.claude-plugin/plugin.json")
            (folder + "/hooks")
          ]
          ++ lib.optional (lib.pathExists (folder + "/types")) (folder + "/types")
        );
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
{
  options.claude-code.mods = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    description = ''
      Plugin folders every Claude Code session loads, in order, through CLAUDE_CODE_PLUGIN_DIRS in settings.json (../settings.nix).
    '';
  };

  config.claude-code.mods = map buildMod [
    # /away: counts down an unanswered prompt; its command hook, built by ./away/hook.nix, does the denying.
    ./away
    # /profile: the account profile a session runs as.
    ./profile
    # How the conversation looks: bars beside prompts and tool calls, a model line closing each turn.
    ./glowup
  ];
}

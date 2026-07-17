{
  config,
  lib,
  pkgs,
  ...
}:
let
  servers = import ./servers.nix { inherit lib pkgs; };
  mcporter-settings = {
    mcpServers = builtins.mapAttrs (_: srv: builtins.removeAttrs srv [ "claudeAsk" ]) servers;
  };
in
{
  home.activation.updateMcporterSettings =
    let
      jq = lib.getExe pkgs.jq;
      sponge = "${lib.getBin pkgs.moreutils}/bin/sponge";
      settingsJson = builtins.toJSON mcporter-settings;
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settingsFile="${config.xdg.configHome}/mcporter/mcporter.json"

      if [[ ! -f "$settingsFile" ]]; then
        mkdir -p "$(dirname "$settingsFile")"
        echo "{}" > "$settingsFile"
        chmod 644 "$settingsFile"
      fi

      ${jq} --argjson nix ${lib.strings.escapeShellArg settingsJson} '
        . as $existing |
        ($existing + $nix) |
        .mcpServers = (($existing.mcpServers // {}) + $nix.mcpServers)
      ' "$settingsFile" | ${sponge} "$settingsFile"
    '';
}

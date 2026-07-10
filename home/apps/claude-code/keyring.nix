{ lib, libsecret }:
{
  # Single source of truth for how Claude tooling resolves secrets from the user keyring (stored via `envchain --set mcp_keys <KEY>`; libsecret attributes: name=mcp_keys, key=<KEY>).
  # Consumed by package.nix (bare wrapper's GH_TOKEN export) and bubble/modules/secrets/module.nix (in-bubble injection loop).
  # keyName may be a literal ("GH_TOKEN") or a shell expansion ('"$name"') — it is spliced into the command verbatim.
  lookupCommand =
    keyName: "${lib.getExe' libsecret "secret-tool"} lookup name mcp_keys key ${keyName}";
}

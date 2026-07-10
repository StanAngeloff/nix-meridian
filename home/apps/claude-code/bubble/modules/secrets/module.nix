{
  lib,
  libsecret,
  secretVars,
  ...
}:
let
  keyring = import ../../../keyring.nix { inherit lib libsecret; };
in
{
  substitutions = {
    secretVars = lib.concatStringsSep " " secretVars;
    # The runtime loop resolves each allowlisted name in turn; "$name" expands in-script.
    secretLookup = keyring.lookupCommand ''"$name"'';
  };
}

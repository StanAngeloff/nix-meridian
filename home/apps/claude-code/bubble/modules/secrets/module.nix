{
  lib,
  libsecret,
  keyringVariables,
  ...
}:
let
  keyring = import ../../../keyring.nix { inherit lib libsecret; };
in
{
  substitutions = {
    keyringVariables = lib.concatStringsSep " " keyringVariables;
    # The runtime loop resolves each allowlisted name in turn; "$name" expands in-script.
    secretLookup = keyring.lookupCommand ''"$name"'';
  };
}

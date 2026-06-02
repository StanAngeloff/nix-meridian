{
  lib,
  pkgs,
  ...
}:
let
  claude-code-npx = pkgs.callPackage ./package.nix { };
  claude-code-statusline = pkgs.callPackage ./statusline/package.nix { };
in
{
  imports = [
    (import ./aliases.nix {
      inherit lib;
      claude-code = claude-code-npx;
    })
    ./keybindings.nix
    (import ./settings.nix { inherit claude-code-statusline; })
    ./notifications.nix
  ];
}

{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  claude-code = pkgs.callPackage ./package.nix {
    claude-code-unwrapped = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
  claude-code-statusline = pkgs.callPackage ./statusline/package.nix { };
in
{
  imports = [
    (import ./aliases.nix {
      inherit lib;
      inherit claude-code;
    })
    ./keybindings.nix
    (import ./settings.nix { inherit claude-code-statusline; })
    ./notifications.nix
  ];

  home.packages = [ claude-code ];
}

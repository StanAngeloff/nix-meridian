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
  # Bubblewrap isolation wrapper that cc/ccc launch through; also profile-installed so it is runnable directly by name.
  claude-bubble = pkgs.callPackage ./bubble/package.nix { inherit claude-code; };
  # High-precedence --settings layer that turns the inner Bash sandbox off inside the bubble.
  bubbleSettings = import ./bubble/bubble-settings.json.nix { inherit pkgs; };
in
{
  imports = [
    (import ./aliases.nix {
      inherit
        lib
        claude-code
        claude-bubble
        bubbleSettings
        ;
    })
    ./keybindings.nix
    (import ./settings.nix { inherit claude-code-statusline; })
    ./notifications.nix
  ];

  home.packages = [
    claude-code
    claude-bubble
  ];

  # The bubble's pnpm module (bubble/modules/pnpm) redirects the pnpm store into <project>/.pnpm-store; keep it out of every repository.
  programs.git.ignores = [
    ".pnpm-store/"
    ".claude/settings.local.json"
  ];
}

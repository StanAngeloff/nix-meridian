{
  inputs,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  claude-code = pkgs.callPackage ./package.nix {
    claude-code-unwrapped = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
  claude-code-statusline = pkgs.callPackage ./statusline/package.nix { };
  integrations = import ../mcp.nix { inherit lib pkgs pkgs-unstable; };
  # Bubblewrap isolation wrapper that cc/ccc launch through; also profile-installed so it is runnable directly by name.
  claude-bubble = pkgs.callPackage ./bubble/package.nix {
    inherit claude-code;
    # Keyring variable names each integration needs; the bubble's secrets module resolves them host-side and injects them.
    keyringVariables = lib.unique (
      lib.concatMap (integration: integration.claude.secrets or [ ]) (lib.attrValues integrations)
    );
  };
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
    ./mcp.nix
    ./notifications.nix
  ];

  home.packages = [
    claude-code
    claude-bubble
  ];

  programs.git.ignores = [
    ".claude/settings.local.json"
  ];

  # --without-clipboard keeps the bubble headless, so wl-copy/wl-paste cannot reach the compositor. OSC52 remains the fallback for that stricter mode.
  programs.nixvim.extraConfigLua = ''
    if vim.env.CLAUDE_BUBBLE then
      vim.g.clipboard = vim.env.CLAUDE_BUBBLE_CLIPBOARD and "wl-copy" or "osc52"
    end
  '';
}

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

  programs.git.ignores = [
    ".claude/settings.local.json"
  ];

  # The bubble is headless (no Wayland/X11 socket), so wl-copy/xclip cannot reach the compositor. OSC 52 terminal escapes pass clipboard data through tmux to the outer terminal instead.
  programs.nixvim.extraConfigLua = ''
    if vim.env.CLAUDE_BUBBLE then
      vim.g.clipboard = "osc52"
    end
  '';
}

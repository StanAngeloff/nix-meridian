{
  inputs,
  lib,
  osConfig,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  claude-code = pkgs.callPackage ./package.nix {
    claude-code-unwrapped = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
  claude-code-statusline = pkgs.callPackage ./statusline/package.nix { };
  # Panel indicator for the subscription limits. Polls the usage endpoint itself; see package.nix.
  claude-usage-tray = pkgs.callPackage ./usage-tray/package.nix { };
  integrations = import ../mcp.nix { inherit lib pkgs pkgs-unstable; };
  # `cc remote`: phone pairing over Tailscale; see remote/package.nix.
  cc-remote = pkgs.callPackage ./remote/package.nix {
    tailscale = osConfig.services.tailscale.package;
    firstLoginCommand = "tailscale up ${lib.concatStringsSep " " osConfig.services.tailscale.extraSetFlags}";
  };
  # Bubblewrap isolation wrapper that cc launches through; also profile-installed so it is runnable directly by name.
  claude-bubble = pkgs.callPackage ./bubble/package.nix {
    inherit claude-code;
    # Keyring variable names each integration needs; the bubble's secrets module resolves them host-side and injects them.
    keyringVariables = lib.unique (
      lib.concatMap (integration: integration.claude.secrets or [ ]) (lib.attrValues integrations)
    );
    subcommands = [
      {
        name = "remote";
        handler = lib.getExe cc-remote;
        description = "Reach cc sessions from the phone over Tailscale (setup)";
      }
    ];
  };
  # The bubble's PreToolUse arbiter; see arbiter/claude-arbiter.sh.
  claude-arbiter = pkgs.callPackage ./arbiter/package.nix { };
  # High-precedence --settings layer for bubbled sessions: the inner Bash sandbox off, no bypass-mode dialog, the arbiter.
  bubbleSettings = import ./bubble/bubble-settings.json.nix { inherit lib pkgs claude-arbiter; };
  # cc and _cc pass it as --model; bare `claude` reads it from settings.json, where every switch also resets what /model saved.
  baseModel = "claude-opus-5-5[1m]";
in
{
  imports = [
    (import ./aliases.nix {
      inherit
        lib
        claude-code
        claude-bubble
        bubbleSettings
        baseModel
        ;
    })
    ./keybindings.nix
    (import ./settings.nix { inherit claude-code-statusline baseModel; })
    ./mcp.nix
    ./notifications.nix
    ./remote # phone remote access
    ./skills
  ];

  home.packages = [
    claude-code
    claude-bubble
    claude-usage-tray
    (pkgs.plannotator.override {
      installSkills = true;
      browserCommand = lib.getExe claude-bubble.wwwBrowser;
    })
  ];

  systemd.user.services.claude-usage-tray = {
    Unit = {
      Description = "Claude subscription usage in the GNOME panel";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.getExe claude-usage-tray;
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  home.sessionVariables.CLAUDE_BUBBLE_TMUX = "1";

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

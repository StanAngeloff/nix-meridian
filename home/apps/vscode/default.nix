{ config, pkgs-unstable, ... }:
{
  programs.vscode = {
    enable = true;

    mutableExtensionsDir = false;

    profiles.default = {
      enableExtensionUpdateCheck = false;

      extensions = with pkgs-unstable.vscode-extensions; [
        asvetliakov.vscode-neovim
        bbenoist.nix
        bierner.markdown-mermaid
        dbaeumer.vscode-eslint
        denoland.vscode-deno
        esbenp.prettier-vscode
        github.copilot
        github.copilot-chat
        github.github-vscode-theme
        ms-vscode.live-server
        ms-vsliveshare.vsliveshare
      ];

      userSettings = {
        "editor.fontFamily" = "${config.nix-meridian.fonts.monospace.name}";
        "editor.fontSize" = 14;
        "editor.letterSpacing" = -0.5;
        "editor.lineHeight" = 1.25;
        "editor.minimap.enabled" = false;
        "extensions.experimental.affinity" = {
          "asvetliakov.vscode-neovim" = 1;
        };
        "window.commandCenter" = false;
        "window.customTitleBarVisibility" = "auto";
        "window.dialogStyle" = "custom";
        "window.titleBarStyle" = "custom";
        "window.zoomLevel" = 1.25;
        "workbench.colorTheme" = "GitHub Dark Default";
        # Learn more at https://code.visualstudio.com/updates/v1_100#_expandable-hovers-for-javascript-and-typescript-experimental
        "typescript.experimental.expandableHover" = true;
      };

      keybindings = [
        {
          key = "Backspace";
          command = "vscode-neovim.send";
          args = "<BS>";
          when = "editorTextFocus && neovim.mode != insert";
        }
      ];
    };
  };
}

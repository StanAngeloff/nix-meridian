{ config, pkgs, ... }:
{
  programs.vscode = {
    enable = true;

    mutableExtensionsDir = false;
    enableExtensionUpdateCheck = false;

    extensions = with pkgs.vscode-extensions; [
      asvetliakov.vscode-neovim
      bbenoist.nix
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
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  monospaceFontFamily = "${
    builtins.replaceStrings [ " " ] [ "" ] config.nix-meridian.fonts.monospace.name
  } Nerd Font Mono";
in
{
  programs.ghostty = {
    enable = true;

    systemd.enable = false;
    enableZshIntegration = false;

    clearDefaultKeybinds = true;

    settings = {
      font-family = [
        monospaceFontFamily
        "IBM Plex Mono"
        "Adwaita Mono"
      ];
      font-family-bold = [
        "${monospaceFontFamily} ExtraBold" # sub-family so fontconfig weight-matches without font-style-bold
        monospaceFontFamily
        "IBM Plex Mono"
        "Adwaita Mono"
      ];
      font-family-italic = [
        monospaceFontFamily
        "IBM Plex Mono"
        "Adwaita Mono"
      ];
      font-family-bold-italic = [
        "${monospaceFontFamily} ExtraBold"
        monospaceFontFamily
        "IBM Plex Mono"
        "Adwaita Mono"
      ];
      font-size = 14;
      font-codepoint-map = "U+2591-U+2593=${monospaceFontFamily}"; # ░▒▓ | See https://github.com/ghostty-org/ghostty/discussions/9501

      adjust-cell-width = "-10%";
      adjust-cell-height = "0%";
      adjust-font-baseline = "0%";
      adjust-box-thickness = "-25%";

      maximize = true;
      window-decoration = "none";
      window-padding-x = 0;
      window-padding-y = 0;

      gtk-titlebar = false;
      gtk-custom-css = "~/.config/ghostty/gtk.css";

      background = "#000000";
      foreground = "#ffffff";
      background-opacity = 0.9875;

      palette = [
        "0=#000000"
        "1=#cd0000"
        "2=#00cd00"
        "3=#cdcd00"
        "4=#1e90ff"
        "5=#cd00cd"
        "6=#00cdcd"
        "7=#e5e5e5"
        "8=#4c4c4c"
        "9=#ff0000"
        "10=#00ff00"
        "11=#ffff00"
        "12=#4682b4"
        "13=#ff00ff"
        "14=#00ffff"
        "15=#ffffff"
      ];

      mouse-hide-while-typing = true;
      cursor-style = "bar";
      cursor-style-blink = true;
      mouse-scroll-multiplier = 0.5;

      keybind = [
        # General
        "ctrl+shift+,=reload_config"
        # Clipboard
        "ctrl+shift+c=copy_to_clipboard"
        "ctrl+shift+v=paste_from_clipboard"
        "ctrl+insert=copy_to_clipboard"
        "shift+insert=paste_from_selection"
        "copy=copy_to_clipboard"
        "paste=paste_from_clipboard"
        # Appearance
        "ctrl+0=reset_font_size"
        "ctrl+equal=increase_font_size:1"
        "ctrl++=increase_font_size:1"
        "ctrl+-=decrease_font_size:1"
      ];

      shell-integration-features = builtins.concatStringsSep "," [
        "no-cursor"
        "no-path"
        "no-ssh-env"
        "no-ssh-terminfo"
        "no-sudo"
        "title"
      ];

      app-notifications = builtins.concatStringsSep "," [
        "no-clipboard-copy"
        "config-reload"
      ];
    };
  };

  home.file.".config/ghostty/gtk.css".source = ./gtk.css;

  dconf.settings = {
    "org/gnome/desktop/default-applications/terminal" = with pkgs; {
      exec = lib.getExe ghostty;
      exec-arg = "-e";
    };
  };
}

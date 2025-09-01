{ config, pkgs, ... }:
let
  monospaceFontFamily = "${
    builtins.replaceStrings [ " " ] [ "" ] config.nix-meridian.fonts.monospace.name
  } Nerd Font Mono";
in
{
  programs.alacritty = {
    enable = true;

    settings = {
      colors.normal = {
        black = "#000000";
        red = "#cd0000";
        green = "#00cd00";
        yellow = "#cdcd00";
        blue = "#1e90ff";
        magenta = "#cd00cd";
        cyan = "#00cdcd";
        white = "#e5e5e5";
      };
      colors.bright = {
        black = "#4c4c4c";
        red = "#ff0000";
        green = "#00ff00";
        yellow = "#ffff00";
        blue = "#4682b4";
        magenta = "#ff00ff";
        cyan = "#00ffff";
        white = "#ffffff";
      };
      colors.primary = {
        background = "#000000";
        foreground = "#ffffff";
      };
      cursor.style = {
        shape = "Beam";
        blinking = "On";
      };
      env = {
        TERM = "alacritty";
      };
      font = {
        size = 14.0;
        offset = {
          x = -2;
          y = 0;
        };
        builtin_box_drawing = true;
        normal = {
          family = monospaceFontFamily;
          style = "Regular";
        };
        bold = {
          family = monospaceFontFamily;
          style = "ExtraBold";
        };
        italic = {
          family = monospaceFontFamily;
          style = "Oblique";
        };
        bold_italic = {
          family = monospaceFontFamily;
          style = "ExtraBold Oblique";
        };
      };
      mouse = {
        hide_when_typing = true;
      };
      window = {
        decorations = "none";
        opacity = 0.9875;
        startup_mode = "Maximized";
      };
      keyboard.bindings = [
        { key = "1"; mods = "Alt"; chars = "\\u001b1"; }
        { key = "2"; mods = "Alt"; chars = "\\u001b2"; }
        { key = "3"; mods = "Alt"; chars = "\\u001b3"; }
        { key = "4"; mods = "Alt"; chars = "\\u001b4"; }
        { key = "5"; mods = "Alt"; chars = "\\u001b5"; }
        { key = "6"; mods = "Alt"; chars = "\\u001b6"; }
        { key = "7"; mods = "Alt"; chars = "\\u001b7"; }
        { key = "8"; mods = "Alt"; chars = "\\u001b8"; }
        { key = "9"; mods = "Alt"; chars = "\\u001b9"; }

        { key = "H"; mods = "Alt"; chars = "\\u001bh"; }
        { key = "J"; mods = "Alt"; chars = "\\u001bj"; }
        { key = "K"; mods = "Alt"; chars = "\\u001bk"; }
        { key = "L"; mods = "Alt"; chars = "\\u001bl"; }

        { key = "Z"; mods = "Alt"; chars = "\\u001bz"; }
      ];
    };
  };

  dconf.settings = {
    "org/gnome/desktop/default-applications/terminal" = {
      exec = "${pkgs.alacritty}/bin/alacritty";
      exec-arg = "--command";
    };
  };
}

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
        shape = "Block";
      };
      env = {
        TERM = "alacritty";
      };
      font = {
        size = 14.0;
        offset = { x = -1; y = 0; };
        builtin_box_drawing = true;
        normal      = { family = "Berkeley Mono"; };
        bold        = { family = "Berkeley Mono ExtraBold"; };
        italic      = { family = "Berkeley Mono Oblique"; };
        bold_italic = { family = "Berkeley Mono ExtraBold Oblique"; };
      };
      mouse = {
        hide_when_typing = true;
      };
      window = {
        decorations = "none";
        opacity = 0.9875;
        startup_mode = "Maximized";
      };
    };
  };

  dconf.settings = {
    "org/gnome/desktop/default-applications/terminal" = {
      exec = "alacritty";
      exec-arg = "--command";
    };
  };
}

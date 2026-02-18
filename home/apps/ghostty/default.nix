{
  config,
  pkgs-unstable,
  ...
}:
let
  ghostty = pkgs-unstable.ghostty-meridian;
  monospaceFontFamily = "${
    builtins.replaceStrings [ " " ] [ "" ] config.nix-meridian.fonts.monospace.name
  } Nerd Font Mono";
in
{
  programs.ghostty = {
    enable = true;
    package = ghostty;

    systemd.enable = false;
    enableZshIntegration = false;

    clearDefaultKeybinds = true;

    settings = {
      font-family = [
        monospaceFontFamily
        "Adwaita Mono"
      ];
      font-size = 14;
      font-style = "Regular";
      font-style-bold = "ExtraBold";
      font-style-italic = "Oblique";
      font-style-bold-italic = "ExtraBold Oblique";

      adjust-cell-width = "-10%";
      adjust-cell-height = "2%";
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
        # ── base 16 ──────────────────────────────────────────────────────────
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
        # See https://gist.github.com/jake-stewart/0a8ea46159a7da2c808e5be2177e1783
        #
        # ── 6×6×6 colour cube (indices 16-231) ───────────────────────────────
        # Generated via lerp_lab() through the base-8 corners in CIELAB space,
        # with bg=#000000 and fg=#ffffff as the black / white anchors.
        "16=#000000"
        "17=#171f31"
        "18=#20395e"
        "19=#265491"
        "20=#2671c6"
        "21=#1e90ff"
        "22=#15290f"
        "23=#243e38"
        "24=#2e5463"
        "25=#346b91"
        "26=#3383c2"
        "27=#299cf5"
        "28=#1c4e14"
        "29=#2d5f3e"
        "30=#377167"
        "31=#3b8391"
        "32=#3995bd"
        "33=#2ca9eb"
        "34=#1f7615"
        "35=#318242"
        "36=#3b8e69"
        "37=#3f9b90"
        "38=#3ba8b8"
        "39=#2ab5e2"
        "40=#1aa011"
        "41=#30a745"
        "42=#3bad6b"
        "43=#3db48f"
        "44=#37bab3"
        "45=#20c1d7"
        "46=#00cd00"
        "47=#28cd46"
        "48=#34cd6b"
        "49=#36cd8d"
        "50=#2dcdad"
        "51=#00cdcd"
        "52=#2d1004"
        "53=#402431"
        "54=#51395d"
        "55=#5d508d"
        "56=#6568c0"
        "57=#6881f5"
        "58=#3c330f"
        "59=#4d4538"
        "60=#5b5762"
        "61=#656a8f"
        "62=#6b7ebe"
        "63=#6c92ef"
        "64=#485712"
        "65=#57663e"
        "66=#637467"
        "67=#6b8491"
        "68=#6f94bc"
        "69=#6ea4ea"
        "70=#507d12"
        "71=#5e8843"
        "72=#68936b"
        "73=#6f9e92"
        "74=#71a9ba"
        "75=#6db5e4"
        "76=#55a50d"
        "77=#62ab46"
        "78=#6bb26d"
        "79=#6fb993"
        "80=#6fbfb8"
        "81=#6ac6dd"
        "82=#56ce00"
        "83=#62d048"
        "84=#69d26f"
        "85=#6dd492"
        "86=#6bd5b5"
        "87=#64d8d7"
        "88=#511507"
        "89=#642632"
        "90=#74375c"
        "91=#814989"
        "92=#895cb9"
        "93=#8c70eb"
        "94=#603c0d"
        "95=#714939"
        "96=#7e5862"
        "97=#89678d"
        "98=#8f77ba"
        "99=#9187e9"
        "100=#6b5f0f"
        "101=#7a6b3e"
        "102=#867767"
        "103=#8f8491"
        "104=#9491bb"
        "105=#949ee8"
        "106=#74830e"
        "107=#818d43"
        "108=#8b966c"
        "109=#93a094"
        "110=#96aabc"
        "111=#96b5e6"
        "112=#7aa809"
        "113=#85af47"
        "114=#8eb670"
        "115=#94bd96"
        "116=#97c4bd"
        "117=#95cbe3"
        "118=#7bce00"
        "119=#86d24a"
        "120=#8ed673"
        "121=#93da98"
        "122=#95debd"
        "123=#92e2e1"
        "124=#781708"
        "125=#882332"
        "126=#95305b"
        "127=#9f3e85"
        "128=#a54cb2"
        "129=#a65be1"
        "130=#84430a"
        "131=#934d39"
        "132=#9f5761"
        "133=#a7628b"
        "134=#ad6eb6"
        "135=#ad7be3"
        "136=#8e660a"
        "137=#9b6f3e"
        "138=#a67968"
        "139=#ae8391"
        "140=#b38dbb"
        "141=#b398e6"
        "142=#958908"
        "143=#a19144"
        "144=#ab996d"
        "145=#b2a296"
        "146=#b7abbe"
        "147=#b7b4e8"
        "148=#99ab04"
        "149=#a5b248"
        "150=#aeb972"
        "151=#b5c19a"
        "152=#b9c8c2"
        "153=#b9d0e9"
        "154=#99ce00"
        "155=#a5d44c"
        "156=#aeda77"
        "157=#b4e09e"
        "158=#b8e6c4"
        "159=#b9eceb"
        "160=#a21206"
        "161=#ad1a33"
        "162=#b62259"
        "163=#bb2b82"
        "164=#be35ab"
        "165=#bb40d7"
        "166=#aa4804"
        "167=#b54d39"
        "168=#be5461"
        "169=#c45b89"
        "170=#c763b3"
        "171=#c66bdd"
        "172=#b16c03"
        "173=#bc723f"
        "174=#c57968"
        "175=#cb8090"
        "176=#cf88ba"
        "177=#ce90e4"
        "178=#b58d01"
        "179=#c09444"
        "180=#c99b6f"
        "181=#d0a397"
        "182=#d4aac0"
        "183=#d5b2ea"
        "184=#b6ae00"
        "185=#c2b54a"
        "186=#ccbc75"
        "187=#d3c49e"
        "188=#d8ccc7"
        "189=#dad4f0"
        "190=#b4ce00"
        "191=#c1d64f"
        "192=#cbdd7b"
        "193=#d3e5a4"
        "194=#d9edcc"
        "195=#ddf6f5"
        "196=#cd0000"
        "197=#d20032"
        "198=#d60058"
        "199=#d7007e"
        "200=#d400a5"
        "201=#cd00cd"
        "202=#d14b00"
        "203=#d84c38"
        "204=#dd4e60"
        "205=#e05087"
        "206=#df54af"
        "207=#db58d8"
        "208=#d47000"
        "209=#dc743e"
        "210=#e37868"
        "211=#e77c90"
        "212=#e981b9"
        "213=#e786e2"
        "214=#d49100"
        "215=#de9645"
        "216=#e79c70"
        "217=#eda299"
        "218=#f1a9c2"
        "219=#f1b0ec"
        "220=#d2af00"
        "221=#deb74b"
        "222=#e8bf78"
        "223=#f0c7a2"
        "224=#f6cfcc"
        "225=#f9d8f6"
        "226=#cdcd00"
        "227=#dbd751"
        "228=#e7e07f"
        "229=#f1eaaa"
        "230=#f9f5d4"
        "231=#ffffff"
        # ── 24-step greyscale ramp (indices 232-255) ─────────────────────────
        # Evenly spaced in CIELAB lightness between bg (#000000) and fg (#ffffff).
        "232=#0e0e0e"
        "233=#181818"
        "234=#1f1f1f"
        "235=#282828"
        "236=#303030"
        "237=#393939"
        "238=#424242"
        "239=#4b4b4b"
        "240=#555555"
        "241=#5e5e5e"
        "242=#686868"
        "243=#727272"
        "244=#7c7c7c"
        "245=#868686"
        "246=#919191"
        "247=#9b9b9b"
        "248=#a6a6a6"
        "249=#b0b0b0"
        "250=#bbbbbb"
        "251=#c6c6c6"
        "252=#d1d1d1"
        "253=#dddddd"
        "254=#e8e8e8"
        "255=#f3f3f3"
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
    };
  };

  home.file.".config/ghostty/gtk.css".source = ./gtk.css;

  dconf.settings = {
    "org/gnome/desktop/default-applications/terminal" = {
      exec = "${ghostty}/bin/ghostty";
      exec-arg = "-e";
    };
  };
}

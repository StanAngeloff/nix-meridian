{ config, pkgs, ... }:
let
  fonts = config.nix-meridian.fonts;

  typora-notion-theme = pkgs.fetchFromGitHub {
    owner = "adrian-fuertes";
    repo = "typora-notion-theme";
    tag = "v1.2.1";
    hash = "sha256-EzUNgvBD47Op/mI/vflVI5Mufkj3HPhg5qnqLcWxlmc=";
  };

  configurationPath = ".config/Typora";
  themesPath = "${configurationPath}/themes";
  dictionariesPath = "${configurationPath}/typora-dictionaries";
in
{
  home.packages = [ pkgs.typora ];

  home.file = {
    "${configurationPath}/conf/conf.user.json".text = builtins.toJSON {
      defaultFontFamily = {
        standard = fonts.serif.name;
        serif = fonts.serif.name;
        sansSerif = fonts.sansSerif.name;
        monospace = fonts.monospace.name;
      };
      autoHideMenuBar = true;
      searchService = [
        [
          "Search with Google"
          "https://google.com/search?q=%s"
        ]
      ];
      keyBinding = { };
      monocolorEmoji = false;
      maxFetchCountOnFileList = 500;
      flags = [ ];
    };

    "${dictionariesPath}/en_GB.aff".source =
      "${pkgs.hunspellDicts.en_GB-large}/share/hunspell/en_GB.aff";
    "${dictionariesPath}/en_GB.dic".source =
      "${pkgs.hunspellDicts.en_GB-large}/share/hunspell/en_GB.dic";
    "${themesPath}/notion-dark-enhanced.css".source =
      "${typora-notion-theme}/themes/enhanced/notion-dark-enhanced.css";

    "${themesPath}/notion-dark-ibm.css".text = ''
      @import "notion-dark-enhanced.css";

      :root {
        --font-family: "${fonts.sansSerif.name}", sans-serif;
        --monospace: "${fonts.monospace.name}", monospace;
      }

      h1, h2, h3, h4, h5, h6 {
        font-family: "${fonts.serif.name}", serif;
      }
    '';
  };
}

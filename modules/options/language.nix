{ lib, ... }:
with lib;
let
  # A language: its locale, and the other forms programs name it by, derived from the locale.
  languageType = types.submodule (
    { config, ... }:
    {
      options = {
        locale = mkOption {
          description = "The language and territory, as POSIX locales and hunspell and aspell dictionaries name it (en_GB).";
          type = types.str;
        };

        tag = mkOption {
          default = replaceStrings [ "_" ] [ "-" ] config.locale;
          defaultText = literalExpression ''replaceStrings [ "_" ] [ "-" ] locale'';
          description = "The locale as a BCP 47 tag (en-GB), as Chromium, Firefox and Bing name languages.";
          readOnly = true;
          type = types.str;
        };

        code = mkOption {
          default = head (splitString "_" config.locale);
          defaultText = literalExpression ''head (splitString "_" locale)'';
          description = "The language alone (en), as aspell's dictionaries, Vim's spell files and most of Firefox's language packs are named.";
          readOnly = true;
          type = types.str;
        };
      };
    }
  );
in
{
  # The one place the languages are set; the system locale, spell checkers and language packs read them in the form each needs.
  options.nix-meridian.language = mkOption {
    default.locale = "en_GB";
    description = "The system-wide language: the system locale, and the language of every spell checker.";
    type = languageType;
  };

  options.nix-meridian.secondaryLanguage = mkOption {
    default.locale = "bg_BG";
    description = "The language besides it, wherever a program takes more than one (Firefox's language packs, Vim's spell checking).";
    type = languageType;
  };
}

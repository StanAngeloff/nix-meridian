{ pkgs, ... }:
let
  # Learn more at https://code.claude.com/docs/en/terminal-config#create-a-custom-theme
  # A theme names the built-in preset it starts from and overrides only the colors it changes, so the rest follows upstream.
  meridianDark = {
    name = "Meridian Dark";
    base = "dark";
    overrides = {
      # Every text Claude Code marks as dim (thinking, hints, the ⎿ connector, secondary details) is drawn in this color.
      # Dark's own is rgb(153,153,153); this sets dimmed text further back from the prose.
      inactive = "rgb(128,128,128)";
    };
  };
in
{
  # Claude Code reads every *.json in this directory as a theme, by the file name; settings.nix selects this one.
  home.file.".claude/themes/meridian-dark.json".source =
    (pkgs.formats.json { }).generate "claude-code-theme-meridian-dark.json"
      meridianDark;
}

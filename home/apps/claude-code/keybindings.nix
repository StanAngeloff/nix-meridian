{ pkgs, ... }:
let
  keybindings = {
    "$schema" = "https://json.schemastore.org/claude-code-keybindings.json";
    bindings = [
      {
        context = "Global";
        bindings = {
          "ctrl+l" = "app:redraw";
        };
      }
      # See "[BUG] v2.1.94 silently changed Ctrl+L default" https://github.com/anthropics/claude-code/issues/45364
      {
        context = "Chat";
        bindings = {
          "ctrl+l" = null;
        };
      }
    ];
  };
in
{
  home.file.".claude/keybindings.json".source =
    (pkgs.formats.json { }).generate "claude-code-keybindings.json"
      keybindings;
}

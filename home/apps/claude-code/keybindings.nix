{ pkgs, ... }:
let
  keybindings = {
    "$schema" = "https://json.schemastore.org/claude-code-keybindings.json";
    bindings = [
      {
        context = "Global";
        bindings = {
          # See "[BUG] v2.1.94 silently changed Ctrl+L default" https://github.com/anthropics/claude-code/issues/45364
          "ctrl+l" = "app:redraw";
        };
      }
      {
        context = "Chat";
        bindings = {
          # Disable Ctrl+L to avoid conflicts with the overridden behavior.
          "ctrl+l" = null;
          # Disable Escape, it's so easy to interrupt a long-running request with it… Ctrl+C still works.
          "escape" = null;
        };
      }
      {
        context = "Confirmation";
        bindings = {
          # Disable Escape which may accidentally dismiss a confirmation prompt.
          "escape" = null;
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

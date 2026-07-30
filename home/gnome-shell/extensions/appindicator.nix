{ pkgs, ... }:
{
  # The extension renders every tray label with St.Label.set_text, so Pango markup arrives verbatim. Routing our own indicator through the ClutterText's set_markup instead lets the Claude usage tray colour its prefixes and numbers like the tmux status line does, and dim the whole label once the numbers go stale — none of which a plain string can express. Alternatives were worse: text rendered into the icon gets squared off by the extension's fixed-size IconActor, and a command-output extension like Executor would replace the dropdown entirely.
  # The dropdown gets the same treatment, so its rows can be monospaced and line their columns up — the menu font is proportional, so space padding alone leaves the bars and percentages ragged. Menu items reach the indicator through the _dbusClient the item factory stores on them.
  # Both sites are matched on the indicator id so every other tray application keeps set_text untouched, which matters more here than in the panel: an unescaped ampersand in someone else's menu entry would make the row fail to parse and vanish. Pinned with --replace-fail so an upstream change to either line breaks the build loudly instead of silently returning to unstyled text. Each line occurs exactly once in v64, and AppIndicator's `get id()` returns the SNI Id property, which is the string passed to Indicator.new(). See home/apps/claude-code/usage-tray/usage.py for the markup that relies on this.
  programs.gnome-shell.extensions = with pkgs.gnomeExtensions; [
    {
      package = appindicator.overrideAttrs (prev: {
        postPatch = ''
          ${prev.postPatch or ""}

          substituteInPlace indicatorStatusIcon.js \
            --replace-fail \
              'this._label.set_text(label);' \
              'this._indicator.id === "claude-usage-tray" ? this._label.clutter_text.set_markup(label) : this._label.set_text(label);'

          substituteInPlace dbusMenu.js \
            --replace-fail \
              'this.label.set_text(label);' \
              'this._dbusClient?.indicator?.id === "claude-usage-tray" ? this.label.clutter_text.set_markup(label) : this.label.set_text(label);'
        '';
      });
    }
  ];
}

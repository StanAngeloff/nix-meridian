# Text Claude Code turns into links (footerLinksRegexes in settings.nix): each pattern is a JavaScript regular expression,
# and its named groups fill the URL. The tmux navigator links the same text in window titles and pane tasks
# (home/apps/tmux/navigator/links.py).
[
  {
    type = "regex";
    pattern = "\\bsc-(?<id>\\d+)\\b";
    url = "https://app.shortcut.com/story/{id}";
    label = "sc-{id}";
  }
]

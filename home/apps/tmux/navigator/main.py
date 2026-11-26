"""tmux-navigator: a sidebar of every tmux window, on prefix Tab (tmux.navigator.conf).

tmux-navigator pane                              the navigator itself, run in its pane
tmux-navigator toggle <pane> <client> <session>  prefix Tab, pressed in <pane>
tmux-navigator arrive [<window> [<session>]]     a window came on screen without the navigator; all, without one
tmux-navigator resized <window>                  a window crossed the minimum width
tmux-navigator close
tmux-navigator pick <session>                    the phone hub's list for <session>; prints what was picked
tmux-navigator arrange <pane>                    prefix Space, pressed in <pane>: the window's next even layout
"""

import importlib
import sys

# Each command's module and function, with the fewest and most arguments it takes.
# A command imports only its own module: prefix Space waits for arrange, and the navigator's drawing would slow it.
COMMANDS = {
    "pane": ("pane", "main", 0, 0),
    "toggle": ("control", "toggle", 3, 3),
    "arrive": ("control", "arrive", 0, 2),
    "resized": ("control", "resized", 1, 1),
    "close": ("control", "close", 0, 0),
    "pick": ("pick", "main", 1, 1),
    "arrange": ("control", "arrange", 1, 1),
}


def main(arguments: list[str]) -> int:
    if not arguments or arguments[0] not in COMMANDS:
        print(__doc__, file=sys.stderr)
        return 2
    module, function, fewest, most = COMMANDS[arguments[0]]
    if not fewest <= len(arguments) - 1 <= most:
        print(__doc__, file=sys.stderr)
        return 2
    getattr(importlib.import_module(module), function)(*arguments[1:])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

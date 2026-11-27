"""Finds the file or directory named under the pointer in a pane, and opens it: the Open entry of the right-click pane menu.

`find` runs just before the menu opens (home/apps/tmux/default.nix). It reads the rows on screen,
drops the glowup mod's bar from each as the copy cleanup does (claude-copy/),
and takes the name under the pointer together with its pieces on the rows above and below, when Claude Code wrapped it.
The path goes into the pane's @open-file-path and the entry's text into @open-file-label;
when the name is no file, both are unset and the entry is greyed out.
`open` is the entry itself: xdg-open opens the path, as it does for a link Ghostty opens.
"""

import argparse
import os
import re
import subprocess
import unicodedata
import urllib.parse

from claude_copy import split_row

# Characters a name stops at, besides the end of its row's text.
SEPARATORS = frozenset(" \t\"'`()[]{}<>|;")

# Sentence punctuation that can follow a name; it comes off one character at a time until the name exists.
TRAILING = ".,;:!?"

# A :line or :line:column suffix, as compilers and Claude Code print after a file name.
LINE_SUFFIX = re.compile(r":\d+(?::\d+)?$")

# A name runs on into at most this many rows above and below the one under the pointer.
MOST_ROWS = 5


def cell_width(character: str) -> int:
    """How many cells tmux draws a character over: as utf8proc, which tmux is built with, East Asian wide characters take two."""
    if unicodedata.category(character) in ("Mn", "Me", "Cf"):
        return 0
    return 2 if unicodedata.east_asian_width(character) in ("W", "F") else 1


def index_at(text: str, column: int) -> int | None:
    """The index of the character drawn over the cell at column, counting cells from the text's first."""
    cells = 0
    for index, character in enumerate(text):
        cells += cell_width(character)
        if cells > column:
            return index
    return None


def word_span(text: str, index: int) -> tuple[int, int]:
    start = index
    while start > 0 and text[start - 1] not in SEPARATORS:
        start -= 1
    end = index + 1
    while end < len(text) and text[end] not in SEPARATORS:
        end += 1
    return start, end


def text_start(text: str) -> int:
    """Where a row's text starts after its indent: a prompt's other rows and a list item's are indented."""
    return len(text) - len(text.lstrip(" "))


def names_under(lines: list[str], x: int, y: int) -> list[str]:
    """The names the word under the cell at x, y can be part of, longest first.

    A word touching the start or end of its row's text is joined with the word at the facing end of the row above or below,
    while the rows share a bar (or have none), and so on from there:
    Claude Code wraps a long name at its hyphens or anywhere inside it, with nothing between the pieces.
    A row also breaks where a space was, so every run of pieces that includes the word under the pointer is a name;
    the longest one that exists wins.
    """
    if not 0 <= y < len(lines):
        return []
    rows = [split_row(line, 0) for line in lines]
    line = lines[y].rstrip(" ")
    text = rows[y].text
    offset = sum(cell_width(character) for character in line[: len(line) - len(text)])
    index = index_at(text, x - offset) if x >= offset else None
    if index is None or text[index] in SEPARATORS:
        return []
    start, end = word_span(text, index)
    pieces = [text[start:end]]
    clicked = 0

    top, top_start = y, start
    while top > 0 and y - top < MOST_ROWS and top_start == text_start(rows[top].text):
        above = rows[top - 1]
        if above.bar != rows[top].bar or not above.text or above.text[-1] in SEPARATORS:
            break
        top_start, _ = word_span(above.text, len(above.text) - 1)
        pieces.insert(0, above.text[top_start:])
        clicked += 1
        top -= 1

    bottom, bottom_end = y, end
    while (
        bottom + 1 < len(rows)
        and bottom - y < MOST_ROWS
        and bottom_end == len(rows[bottom].text)
    ):
        below = rows[bottom + 1]
        below_start = text_start(below.text)
        if (
            below.bar != rows[bottom].bar
            or below_start == len(below.text)
            or below.text[below_start] in SEPARATORS
        ):
            break
        _, bottom_end = word_span(below.text, below_start)
        pieces.append(below.text[below_start:bottom_end])
        bottom += 1

    names = []
    for length in range(len(pieces), 0, -1):
        for first in range(
            max(0, clicked - length + 1), min(clicked, len(pieces) - length) + 1
        ):
            names.append("".join(pieces[first : first + length]))
    return names


def hyperlink_path(uri: str) -> str | None:
    """The path of a file:// hyperlink, percent-decoded; its host is left out."""
    if not uri.startswith("file://"):
        return None
    return urllib.parse.unquote(urllib.parse.urlsplit(uri).path)


def resolve(name: str, pane_path: str) -> str | None:
    """The existing path a name refers to, from the pane's directory, after dropping sentence punctuation and a :line
    suffix one character at a time until it exists: a name whose own last character is a dot still opens.
    """
    while name:
        for candidate in (name, LINE_SUFFIX.sub("", name)):
            path = os.path.join(pane_path, os.path.expanduser(candidate))
            if os.path.exists(path):
                return os.path.normpath(path)
        if name[-1] not in TRAILING:
            return None
        name = name[:-1]
    return None


def label(path: str, pane_path: str) -> str:
    """The entry names the path from the pane's directory, or from ~."""
    for base, shown in ((pane_path, ""), (os.path.expanduser("~"), "~/")):
        if base and path != base and os.path.commonpath([path, base]) == base:
            return shown + os.path.relpath(path, base)
    return path


def number(value: str, default: int) -> int:
    return int(value) if value.isdigit() else default


def find(
    pane: str, x: int, y: int, scroll: int, height: int, pane_path: str, hyperlink: str
) -> None:
    # In copy mode -M reads copy mode's own copy of the pane, which keeps the rows it had when copy mode started,
    # and the range picks the rows on view, scroll_position rows up from its bottom; outside copy mode it is the screen.
    screen = subprocess.run(
        [
            "tmux",
            "capture-pane",
            "-p",
            "-M",
            "-t",
            pane,
            "-S",
            str(-scroll),
            "-E",
            str(height - 1 - scroll),
        ],
        capture_output=True,
        check=False,
    ).stdout.decode("utf-8", "surrogateescape")
    names = names_under(screen.split("\n"), x, y)
    link_path = hyperlink_path(hyperlink)
    if link_path:
        names.insert(0, link_path)
    for name in names:
        path = resolve(name, pane_path)
        if path:
            subprocess.run(
                ["tmux", "set", "-p", "-t", pane, "@open-file-path", path, ";"]
                + ["set", "-p", "-t", pane, "@open-file-label", label(path, pane_path)],
                check=False,
            )
            return
    subprocess.run(
        ["tmux", "set", "-pu", "-t", pane, "@open-file-path", ";"]
        + ["set", "-pu", "-t", pane, "@open-file-label"],
        check=False,
    )


def open_path(pane: str) -> None:
    path = (
        subprocess.run(
            ["tmux", "show", "-pqv", "-t", pane, "@open-file-path"],
            capture_output=True,
            check=False,
        )
        .stdout.decode("utf-8", "surrogateescape")
        .removesuffix("\n")
    )
    if path:
        os.execvp("xdg-open", ["xdg-open", path])


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Finds and opens the file named under the pointer in a tmux pane."
    )
    actions = parser.add_subparsers(dest="action", required=True)
    find_parser = actions.add_parser(
        "find", help="store the file under the pointer for the menu's Open entry"
    )
    find_parser.add_argument("--pane", required=True, help="#{pane_id}")
    find_parser.add_argument("--x", default="", help="#{mouse_x}")
    find_parser.add_argument("--y", default="", help="#{mouse_y}")
    find_parser.add_argument(
        "--scroll", default="", help="#{scroll_position}, empty outside copy mode"
    )
    find_parser.add_argument("--height", default="", help="#{pane_height}")
    find_parser.add_argument("--path", default="", help="#{pane_current_path}")
    find_parser.add_argument("--hyperlink", default="", help="#{mouse_hyperlink}")
    open_parser = actions.add_parser("open", help="open the stored file")
    open_parser.add_argument("--pane", required=True, help="#{pane_id}")
    arguments = parser.parse_args()

    if arguments.action == "find":
        find(
            arguments.pane,
            number(arguments.x, -1),
            number(arguments.y, -1),
            number(arguments.scroll, 0),
            number(arguments.height, 0),
            arguments.path,
            arguments.hyperlink,
        )
    else:
        open_path(arguments.pane)


if __name__ == "__main__":
    main()

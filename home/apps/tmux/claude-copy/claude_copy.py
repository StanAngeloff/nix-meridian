"""Copies a selection out of a Claude Code pane without the glowup mod's bars (home/apps/claude-code/mods/glowup) and the
padding beside them; every line break stays where Claude Code drew it.

The copy bindings in tmux.conf pipe a Claude pane's selection here with -C -P, which keep tmux from storing and sending the
raw selection, so the cleaned copy is the only one: it goes back to tmux as a paste buffer and to the clipboard of the client
that copied, as tmux's own copy would, and to wl-copy too for the y binding, which always copied to it.
"""

import argparse
import subprocess
import sys
from dataclasses import dataclass

# The mod draws one of these in the first column of each row of a message and a space after it:
# ▌ beside prompts and replies, ▏ beside tool calls.
BARS = ("▌", "▏")

# A row whose selection starts after its first column: whether it has a bar, and which, is not in the copy.
UNSEEN = "?"

# Claude Code starts the first row of a prompt with this marker and indents the prompt's other rows by its width.
PROMPT_MARKER = "❯ "


@dataclass
class Row:
    bar: str | None  # a glyph of BARS, UNSEEN, or None for a row without a bar
    text: str  # what is selected after the bar and its space
    whole: bool  # the text is selected from its start


def start_columns(
    mode: str, rectangle: bool, start_x: int, start_y: int, end_x: int, end_y: int
) -> tuple[int, int]:
    """The column the first copied line starts at, and the column every other line starts at."""
    if mode == "line":
        return 0, 0
    if rectangle:
        left = min(start_x, end_x)
        return left, left
    # The selection runs from where it started to the cursor, either way round, and the copy begins at the earlier end.
    first = start_x if (start_y, start_x) <= (end_y, end_x) else end_x
    return first, 0


def split_row(line: str, column: int) -> Row:
    line = line.rstrip(" ")
    if column == 0:
        if line[:1] in BARS:
            return Row(line[0], line[1:].removeprefix(" "), True)
        return Row(None, line, True)
    if column == 1:
        return Row(UNSEEN, line.removeprefix(" "), True)
    return Row(UNSEEN, line, column == 2)


def blocks(rows: list[Row]) -> list[list[Row]]:
    """Runs of rows with the same bar, one message each: messages are kept apart by a row without a bar or by their bars."""
    found: list[list[Row]] = []
    block: list[Row] = []
    block_bar = UNSEEN
    for row in rows:
        if row.bar is None or (
            block and UNSEEN not in (row.bar, block_bar) and row.bar != block_bar
        ):
            if block:
                found.append(block)
            block, block_bar = [], UNSEEN
        if row.bar is None:
            continue
        block.append(row)
        if row.bar != UNSEEN:
            block_bar = row.bar
    if block:
        found.append(block)
    return found


def dedent(block: list[Row]) -> None:
    """Drops a prompt's marker and the indent the block's whole rows share, which keeps a list item's rows under its marker."""
    whole = [row for row in block if row.whole]
    if not whole:
        return
    if whole[0] is block[0] and block[0].text.startswith(PROMPT_MARKER):
        block[0].text = " " * len(PROMPT_MARKER) + block[0].text[len(PROMPT_MARKER) :]
    indents = [len(row.text) - len(row.text.lstrip(" ")) for row in whole if row.text]
    indent = min(indents, default=0)
    for row in whole:
        row.text = row.text[indent:]


def clean(copied: str, first_column: int, other_column: int) -> str:
    rows = [
        split_row(line, first_column if index == 0 else other_column)
        for index, line in enumerate(copied.split("\n"))
    ]
    for block in blocks(rows):
        dedent(block)
    return "\n".join(row.text for row in rows)


def number(value: str) -> int:
    return int(value) if value.isdigit() else 0


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Cleans a selection copied in a Claude Code pane and copies it."
    )
    parser.add_argument("--socket", required=True, help="#{socket_path}")
    parser.add_argument("--client", default="", help="#{client_name}")
    parser.add_argument("--mode", default="char", help="#{selection_mode}")
    parser.add_argument("--rectangle", default="0", help="#{rectangle_toggle}")
    parser.add_argument(
        "--start", nargs=2, default=["0", "0"], help="#{selection_start_x} and _y"
    )
    parser.add_argument(
        "--end", nargs=2, default=["0", "0"], help="#{selection_end_x} and _y"
    )
    parser.add_argument("--wl-copy", action="store_true", help="copy with wl-copy too")
    arguments = parser.parse_args()

    columns = start_columns(
        arguments.mode,
        arguments.rectangle == "1",
        *(number(value) for value in arguments.start + arguments.end),
    )
    copied = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
    cleaned = clean(copied, *columns).encode("utf-8", "surrogateescape")

    target = ["-t", arguments.client] if arguments.client else []
    subprocess.run(
        ["tmux", "-S", arguments.socket, "load-buffer", "-w", *target, "-"],
        input=cleaned,
        check=False,
    )
    if arguments.wl_copy:
        # As tmux.conf's own y: --type skips wl-copy's type guess, which waits on the GVfs metadata daemon;
        # timeout stops a copy that never finishes.
        subprocess.run(
            ["timeout", "5", "wl-copy", "--type", "text/plain"],
            input=cleaned,
            check=False,
        )


if __name__ == "__main__":
    main()

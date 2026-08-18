#!/usr/bin/env python3
"""Minimal pager with tig-like cursor line, horizontal scroll, and no word wrap."""

import os
import re
import sys
import termios
import tty

ANSI_RE = re.compile(r"\033\[[0-9;]*m")
CURSOR_BG = "\033[37m\033[48;5;34m"
STATUS_BG = "\033[37m\033[48;5;56m"
RESET = "\033[0m"
CLEAR_LINE = "\033[K"
HIDE_CURSOR = "\033[?25l"
SHOW_CURSOR = "\033[?25h"
HOME = "\033[H"
CLEAR_SCREEN = "\033[2J"


def strip_ansi(text):
    return ANSI_RE.sub("", text)


def visible_length(text):
    return len(strip_ansi(text))


def expand_tabs(line, tab_width=8):
    """Replace tabs with spaces, preserving ANSI codes and tab stop alignment."""
    segments = ANSI_RE.split(line)
    escapes = ANSI_RE.findall(line)
    result = []
    column = 0
    for segment_index, segment in enumerate(segments):
        for character in segment:
            if character == "\t":
                spaces = tab_width - (column % tab_width)
                result.append(" " * spaces)
                column += spaces
            else:
                result.append(character)
                column += 1
        if segment_index < len(escapes):
            result.append(escapes[segment_index])
    return "".join(result)


def render_visible_slice(line, horizontal_offset, width):
    """Extract a horizontal slice of an ANSI-colored line for display."""
    expanded = expand_tabs(line)
    segments = ANSI_RE.split(expanded)
    escapes = ANSI_RE.findall(expanded)

    result = []
    active_escapes = []
    visible_column = 0

    for segment_index, segment in enumerate(segments):
        for character in segment:
            if visible_column >= horizontal_offset + width:
                break
            if visible_column >= horizontal_offset:
                if not result:
                    result.extend(active_escapes)
                result.append(character)
            visible_column += 1
        if visible_column >= horizontal_offset + width:
            break
        if segment_index < len(escapes):
            escape = escapes[segment_index]
            if escape == RESET:
                active_escapes.clear()
            else:
                active_escapes.append(escape)
            if visible_column >= horizontal_offset:
                result.append(escape)

    result.append(RESET)
    return "".join(result)


def get_terminal_size():
    try:
        columns, rows = os.get_terminal_size()
        return rows, columns
    except OSError:
        return 40, 120


def read_key(fd):
    """Read a single keypress, handling escape sequences for arrow keys and page keys."""
    character = os.read(fd, 1)
    if character == b"\x1b":
        second = os.read(fd, 1)
        if second == b"[":
            third = os.read(fd, 1)
            if third == b"A":
                return "UP"
            elif third == b"B":
                return "DOWN"
            elif third == b"C":
                return "RIGHT"
            elif third == b"D":
                return "LEFT"
            elif third == b"5":
                os.read(fd, 1)
                return "PGUP"
            elif third == b"6":
                os.read(fd, 1)
                return "PGDN"
            elif third == b"H":
                return "HOME"
            elif third == b"F":
                return "END"
        return "ESC"
    return character.decode("utf-8", errors="replace")


def run_pager(lines):
    tty_fd = os.open("/dev/tty", os.O_RDWR)
    tty_file = os.fdopen(tty_fd, "wb", buffering=0)
    old_settings = termios.tcgetattr(tty_fd)

    def write(text):
        tty_file.write(text.encode("utf-8", errors="replace"))

    try:
        tty.setraw(tty_fd)

        cursor_row = 0
        viewport_top = 0
        horizontal_offset = 0
        horizontal_step = 8

        write(HIDE_CURSOR)

        while True:
            height, width = get_terminal_size()
            viewable_height = height - 1

            max_viewport = max(0, len(lines) - viewable_height)
            if cursor_row < viewport_top:
                viewport_top = cursor_row
            elif cursor_row >= viewport_top + viewable_height:
                viewport_top = cursor_row - viewable_height + 1
            viewport_top = max(0, min(viewport_top, max_viewport))

            write(HOME)

            for screen_row in range(viewable_height):
                line_index = viewport_top + screen_row
                if line_index < len(lines):
                    line = lines[line_index]
                    sliced = render_visible_slice(line, horizontal_offset, width)
                    if line_index == cursor_row:
                        plain = strip_ansi(sliced)
                        write(f"\r{CURSOR_BG}{plain}{CLEAR_LINE}{RESET}\r\n")
                    else:
                        write(f"\r{RESET}{sliced}{RESET}{CLEAR_LINE}\r\n")
                else:
                    write(f"\r{RESET}{CLEAR_LINE}\r\n")

            percentage = ""
            if len(lines) > viewable_height:
                pct = int(100 * (viewport_top + viewable_height) / len(lines))
                pct = min(pct, 100)
                percentage = f"{pct:>4d}%"
            status_left = f"[pager] - line {cursor_row + 1} of {len(lines)}"
            status_line = f"{status_left}{percentage.rjust(width - len(status_left))}"
            write(f"{STATUS_BG}{status_line[:width]}{RESET}")

            tty_file.flush()

            key = read_key(tty_fd)
            if key in ("q", "Q", "ESC"):
                break
            elif key in ("j", "DOWN", "\n"):
                cursor_row = min(cursor_row + 1, len(lines) - 1)
            elif key in ("k", "UP"):
                cursor_row = max(cursor_row - 1, 0)
            elif key in ("l", "RIGHT"):
                horizontal_offset += horizontal_step
            elif key in ("h", "LEFT"):
                horizontal_offset = max(0, horizontal_offset - horizontal_step)
            elif key == "g":
                cursor_row = 0
                horizontal_offset = 0
            elif key == "G":
                cursor_row = len(lines) - 1
            elif key in (" ", "PGDN", "\x06"):
                max_vp = max(0, len(lines) - viewable_height)
                viewport_top = min(viewport_top + viewable_height, max_vp)
                cursor_row = min(cursor_row + viewable_height, len(lines) - 1)
            elif key in ("PGUP", "\x02"):
                viewport_top = max(viewport_top - viewable_height, 0)
                cursor_row = max(cursor_row - viewable_height, 0)
            elif key == "\x04":
                cursor_row = min(cursor_row + viewable_height // 2, len(lines) - 1)
            elif key == "\x15":
                cursor_row = max(cursor_row - viewable_height // 2, 0)
            elif key == "0":
                horizontal_offset = 0
            elif key == "$":
                max_visible = max(
                    (visible_length(line) for line in lines), default=0
                )
                horizontal_offset = max(0, max_visible - width)
    finally:
        termios.tcsetattr(tty_fd, termios.TCSADRAIN, old_settings)
        write(SHOW_CURSOR)
        write(CLEAR_SCREEN + HOME)
        tty_file.flush()
        tty_file.close()


def main():
    if sys.stdin.isatty():
        print("Usage: <command> | difft-pager", file=sys.stderr)
        sys.exit(1)
    lines = [line.rstrip("\n") for line in sys.stdin]
    if not lines:
        return
    run_pager(lines)


if __name__ == "__main__":
    main()

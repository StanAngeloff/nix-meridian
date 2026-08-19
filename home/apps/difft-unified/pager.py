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
SEARCH_HIT = "\033[30m\033[43m"
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


def compute_search_ranges(plain_text, pattern):
    """Return list of (start, end) visible-column ranges for search matches."""
    if not pattern:
        return []
    ranges = []
    for match in pattern.finditer(plain_text):
        start, end = match.start(), match.end()
        if start < end:
            ranges.append((start, end))
    return ranges


def overlay_on_ansi(ansi_text, highlight_ranges, highlight_escape):
    """Overlay highlight_escape at specific visible-column ranges onto ANSI-colored text.

    Preserves the original ANSI colors outside the highlighted ranges. Inside
    a highlighted range, emits highlight_escape; on leaving, restores whatever
    escapes were active before the range started.
    """
    if not highlight_ranges:
        return ansi_text

    segments = ANSI_RE.split(ansi_text)
    escapes = ANSI_RE.findall(ansi_text)

    result = []
    active_escapes = []
    visible_column = 0
    in_highlight = False

    for segment_index, segment in enumerate(segments):
        for character in segment:
            entering = not in_highlight and any(
                start <= visible_column < end for start, end in highlight_ranges
            )
            leaving = in_highlight and not any(
                start <= visible_column < end for start, end in highlight_ranges
            )
            if entering:
                result.append(highlight_escape)
                in_highlight = True
            elif leaving:
                result.append(RESET)
                result.extend(active_escapes)
                in_highlight = False
            result.append(character)
            visible_column += 1
        if segment_index < len(escapes):
            escape = escapes[segment_index]
            if not in_highlight:
                result.append(escape)
            if escape == RESET:
                active_escapes.clear()
            else:
                active_escapes.append(escape)

    if in_highlight:
        result.append(RESET)
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


PROMPT_FG = "\033[32m"


def read_search_input(tty_fd, tty_file, prompt, width):
    """Read a search string from the user, rendering the prompt on the bottom line."""
    height, _ = get_terminal_size()
    buf = []

    def draw_prompt():
        display = prompt + "".join(buf)
        tty_file.write(
            f"\033[{height};1H{RESET}{PROMPT_FG}{display}{CLEAR_LINE}{RESET}{SHOW_CURSOR}"
            .encode("utf-8")
        )
        tty_file.flush()

    draw_prompt()
    while True:
        raw = os.read(tty_fd, 1)
        if raw == b"\r" or raw == b"\n":
            tty_file.write(HIDE_CURSOR.encode("utf-8"))
            tty_file.flush()
            return "".join(buf)
        elif raw == b"\x1b":
            tty_file.write(HIDE_CURSOR.encode("utf-8"))
            tty_file.flush()
            return None
        elif raw == b"\x7f" or raw == b"\x08":
            if buf:
                buf.pop()
                draw_prompt()
        elif raw == b"\x15":
            buf.clear()
            draw_prompt()
        elif raw == b"\x17":
            while buf and buf[-1] == " ":
                buf.pop()
            while buf and buf[-1] != " ":
                buf.pop()
            draw_prompt()
        else:
            character = raw.decode("utf-8", errors="replace")
            if character.isprintable():
                buf.append(character)
                draw_prompt()


def compile_search(pattern_text):
    """Compile a search pattern with smart-case: case-insensitive unless uppercase is present."""
    if not pattern_text:
        return None
    flags = re.IGNORECASE if pattern_text == pattern_text.lower() else 0
    try:
        return re.compile(pattern_text, flags)
    except re.error:
        return re.compile(re.escape(pattern_text), flags)


def find_match_lines(lines, pattern):
    """Return sorted list of line indices that contain a match."""
    if not pattern:
        return []
    plain_lines = [strip_ansi(expand_tabs(line)) for line in lines]
    return [i for i, plain in enumerate(plain_lines) if pattern.search(plain)]


def find_next(match_lines, current, direction, wrap):
    """Find the next matching line index in the given direction."""
    if not match_lines:
        return None
    if direction > 0:
        for line_index in match_lines:
            if line_index > current:
                return line_index
        return match_lines[0] if wrap else None
    else:
        for line_index in reversed(match_lines):
            if line_index < current:
                return line_index
        return match_lines[-1] if wrap else None


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

        search_pattern = None
        search_direction = 1
        match_lines = []
        status_message = ""

        write(HIDE_CURSOR)

        while True:
            height, width = get_terminal_size()
            viewable_height = height - 2

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
                    plain = strip_ansi(sliced)
                    search_ranges = compute_search_ranges(plain, search_pattern) if search_pattern else []
                    if line_index == cursor_row:
                        cursor_line = f"{CURSOR_BG}{plain}"
                        if search_ranges:
                            cursor_line = overlay_on_ansi(cursor_line, search_ranges, SEARCH_HIT)
                        write(f"\r{cursor_line}{CLEAR_LINE}{RESET}\r\n")
                    else:
                        if search_ranges:
                            rendered = overlay_on_ansi(sliced, search_ranges, SEARCH_HIT)
                            write(f"\r{RESET}{rendered}{CLEAR_LINE}{RESET}\r\n")
                        else:
                            write(f"\r{RESET}{sliced}{RESET}{CLEAR_LINE}\r\n")
                else:
                    write(f"\r{RESET}{CLEAR_LINE}\r\n")

            percentage = ""
            if len(lines) > viewable_height:
                pct = int(100 * (viewport_top + viewable_height) / len(lines))
                pct = min(pct, 100)
                percentage = f"{pct:>4d}%"
            if status_message:
                status_left = status_message
                status_message = ""
            else:
                status_left = f"[pager] - line {cursor_row + 1} of {len(lines)}"
            status_line = f"{status_left}{percentage.rjust(max(0, width - len(status_left)))}"
            write(f"{STATUS_BG}{status_line[:width]}{RESET}\r\n{RESET}{CLEAR_LINE}")

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
            elif key in ("/", "?"):
                search_direction = 1 if key == "/" else -1
                termios.tcsetattr(tty_fd, termios.TCSADRAIN, old_settings)
                pattern_text = read_search_input(tty_fd, tty_file, key, width)
                tty.setraw(tty_fd)
                if pattern_text:
                    search_pattern = compile_search(pattern_text)
                    match_lines = find_match_lines(lines, search_pattern)
                    _match_set = set(match_lines)
                    if match_lines:
                        target = find_next(match_lines, cursor_row - search_direction, search_direction, True)
                        if target is not None:
                            cursor_row = target
                            match_index = match_lines.index(target) + 1
                            status_message = f"Line {target + 1} matches '{pattern_text}' ({match_index} of {len(match_lines)})"
                    else:
                        status_message = f"No match found for '{pattern_text}'"
                elif pattern_text == "" and search_pattern and match_lines:
                    target = find_next(match_lines, cursor_row, search_direction, True)
                    if target is not None:
                        cursor_row = target
                        match_index = match_lines.index(target) + 1
                        status_message = f"Line {target + 1} matches '{search_pattern.pattern}' ({match_index} of {len(match_lines)})"
            elif key == "n":
                if search_pattern and match_lines:
                    target = find_next(match_lines, cursor_row, search_direction, True)
                    if target is not None:
                        cursor_row = target
                        match_index = match_lines.index(target) + 1
                        status_message = f"Line {target + 1} matches '{search_pattern.pattern}' ({match_index} of {len(match_lines)})"
                elif not search_pattern:
                    status_message = "No previous search"
            elif key == "N":
                if search_pattern and match_lines:
                    target = find_next(match_lines, cursor_row, -search_direction, True)
                    if target is not None:
                        cursor_row = target
                        match_index = match_lines.index(target) + 1
                        status_message = f"Line {target + 1} matches '{search_pattern.pattern}' ({match_index} of {len(match_lines)})"
                elif not search_pattern:
                    status_message = "No previous search"
    finally:
        termios.tcsetattr(tty_fd, termios.TCSADRAIN, old_settings)
        write(SHOW_CURSOR)
        write(CLEAR_SCREEN + HOME)
        tty_file.flush()
        tty_file.close()


# Sentinel for match set (initialized on first search)
_match_set = set()


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

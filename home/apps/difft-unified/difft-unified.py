#!/usr/bin/env python3
"""Git external diff driver: wraps difftastic JSON into tig-style unified diff."""

import json
import os
import subprocess
import sys

RESET = "\033[0m"
YELLOW = "\033[33m"
BLUE = "\033[34m"
MAGENTA = "\033[35m"
RED = "\033[31m"
GREEN = "\033[32m"
DEFAULT = "\033[39m"
GRAY240 = "\033[38;5;240m"
BOLD = "\033[1m"
EMPHASIS_DEL = "\033[38;5;210;48;5;52m"
EMPHASIS_ADD = "\033[38;5;120;48;5;22m"


def get_terminal_width():
    try:
        return os.get_terminal_size().columns
    except OSError:
        return 80


def detect_status(old_hex, old_file, new_hex, new_file):
    if all(character == "0" for character in old_hex) or old_file == "/dev/null":
        return "created"
    if all(character == "0" for character in new_hex) or new_file == "/dev/null":
        return "deleted"
    return "changed"


def read_lines(filepath):
    if filepath == "/dev/null":
        return []
    with open(filepath) as source:
        return [line.rstrip("\n") for line in source]


def is_binary(filepath):
    # Mirrors git's own heuristic (a NUL byte anywhere in the content means binary), since
    # git's external diff protocol hands us real files on disk with no advance notice of
    # content type. This also catches git-lfs-tracked files: git materializes the external
    # diff's temporary files through the smudge filter, so they hold the real (often binary)
    # content even though a plain `git diff` only ever sees the small text pointer blob.
    if filepath == "/dev/null":
        return False
    with open(filepath, "rb") as source:
        chunk = source.read(8192)
    return b"\x00" in chunk


def render_binary_notice(old_path, new_path, status):
    old_side = "/dev/null" if status == "created" else f"a/{old_path}"
    new_side = "/dev/null" if status == "deleted" else f"b/{new_path}"
    return f"{YELLOW}Binary files {old_side} and {new_side} differ{RESET}"


def render_file_header(
    old_path, new_path, old_hex, old_mode, new_hex, new_mode, status, rename_description=None
):
    terminal_width = get_terminal_width()
    parts = []

    header_text = f"diff --git a/{old_path} b/{new_path}"
    fill_length = max(0, terminal_width - len(header_text) - 1)
    parts.append(f"{YELLOW}{header_text}{GRAY240} {'─' * fill_length}{RESET}")

    if rename_description is not None:
        # Git precomputes the whole rename/copy extended header (similarity index,
        # rename/copy from/to, and an index line with abbreviated hashes) as one
        # opaque, pre-formatted, newline-separated block, because only git's own
        # diff engine can compute the similarity percentage. Print it verbatim
        # rather than re-deriving it — it already includes its own index line.
        for line in rename_description.rstrip("\n").split("\n"):
            parts.append(f"{YELLOW}{line}{RESET}")
    else:
        if status == "created":
            parts.append(f"{YELLOW}new file mode {new_mode}{RESET}")
        elif status == "deleted":
            parts.append(f"{YELLOW}deleted file mode {old_mode}{RESET}")

        mode = new_mode if status != "deleted" else old_mode
        parts.append(f"{BLUE}index {old_hex}..{new_hex} {mode}{RESET}")

    old_side = "/dev/null" if status == "created" else f"a/{old_path}"
    new_side = "/dev/null" if status == "deleted" else f"b/{new_path}"
    parts.append(f"{YELLOW}--- {old_side}{RESET}")
    parts.append(f"{YELLOW}+++ {new_side}{RESET}")

    return "\n".join(parts)


def render_full_addition(rhs_lines):
    if not rhs_lines:
        return ""
    parts = [f"{MAGENTA}@@ -0,0 +1,{len(rhs_lines)} @@{RESET}"]
    for line in rhs_lines:
        parts.append(f"{GREEN}+{line}{RESET}")
    return "\n".join(parts)


def render_full_deletion(lhs_lines):
    if not lhs_lines:
        return ""
    parts = [f"{MAGENTA}@@ -1,{len(lhs_lines)} +0,0 @@{RESET}"]
    for line in lhs_lines:
        parts.append(f"{RED}-{line}{RESET}")
    return "\n".join(parts)


KNOWN_TOP_KEYS = {"aligned_lines", "chunks", "language", "path", "status"}
KNOWN_STATUSES = {"changed", "created", "deleted", "unchanged"}
KNOWN_CHANGE_KEYS = {"start", "end", "content", "highlight"}
KNOWN_SIDE_KEYS = {"line_number", "changes"}


def validate_difft_json(data, file_path):
    unknown_keys = set(data.keys()) - KNOWN_TOP_KEYS
    if unknown_keys:
        raise ValueError(
            f"difft-unified: unexpected key {unknown_keys} in JSON for {file_path}"
        )

    status = data.get("status")
    if status not in KNOWN_STATUSES:
        raise ValueError(
            f"difft-unified: unexpected status {status!r} in JSON for {file_path}"
        )

    if status == "changed":
        if "chunks" not in data:
            raise ValueError(
                f"difft-unified: missing 'chunks' for changed file {file_path}"
            )
        if "aligned_lines" not in data:
            raise ValueError(
                f"difft-unified: missing 'aligned_lines' for changed file {file_path}"
            )
        for chunk_group in data["chunks"]:
            for entry in chunk_group:
                entry_keys = set(entry.keys())
                unknown_entry_keys = entry_keys - {"lhs", "rhs"}
                if unknown_entry_keys:
                    raise ValueError(
                        f"difft-unified: unexpected chunk entry key "
                        f"{unknown_entry_keys} in {file_path}"
                    )
                if "lhs" not in entry and "rhs" not in entry:
                    raise ValueError(
                        f"difft-unified: chunk entry has neither lhs nor rhs "
                        f"in {file_path}"
                    )
                for side_name in ("lhs", "rhs"):
                    if side_name not in entry:
                        continue
                    side = entry[side_name]
                    unknown_side_keys = set(side.keys()) - KNOWN_SIDE_KEYS
                    if unknown_side_keys:
                        raise ValueError(
                            f"difft-unified: unexpected {side_name} key "
                            f"{unknown_side_keys} in {file_path}"
                        )
                    for change in side.get("changes", []):
                        unknown_change_keys = set(change.keys()) - KNOWN_CHANGE_KEYS
                        if unknown_change_keys:
                            raise ValueError(
                                f"difft-unified: unexpected change key "
                                f"{unknown_change_keys} in {file_path}"
                            )


def build_chunk_lookup(chunks):
    lhs_changes = {}
    rhs_changes = {}
    modified_pairs = set()

    for chunk_group in chunks:
        for entry in chunk_group:
            has_lhs = "lhs" in entry
            has_rhs = "rhs" in entry
            if has_lhs:
                line_number = entry["lhs"]["line_number"]
                lhs_changes[line_number] = entry["lhs"]["changes"]
            if has_rhs:
                line_number = entry["rhs"]["line_number"]
                rhs_changes[line_number] = entry["rhs"]["changes"]
            if has_lhs and has_rhs:
                modified_pairs.add(
                    (entry["lhs"]["line_number"], entry["rhs"]["line_number"])
                )

    return lhs_changes, rhs_changes, modified_pairs


def classify_lines(aligned_lines, lhs_changes, rhs_changes, modified_pairs):
    operations = []
    for lhs_index, rhs_index in aligned_lines:
        if lhs_index is None:
            operations.append(("add", None, rhs_index))
        elif rhs_index is None:
            operations.append(("delete", lhs_index, None))
        else:
            if (lhs_index, rhs_index) in modified_pairs:
                operations.append(("modify", lhs_index, rhs_index))
            elif lhs_index in lhs_changes or rhs_index in rhs_changes:
                operations.append(("modify", lhs_index, rhs_index))
            else:
                operations.append(("context", lhs_index, rhs_index))
    return operations


def demote_identical_modifications(operations, lhs_lines, rhs_lines):
    # Difftastic's structural diff can mark a line "modified" purely because it sits inside a
    # larger node that was restructured elsewhere (for example, an inserted line inside a Nix
    # multi-line string), even when that particular line's text is byte-for-byte identical on
    # both sides. Treat those as context instead, matching what an actual text comparison (and a
    # human reviewer) would consider unchanged; this also keeps unrelated hunks from merging
    # around a stretch of lines difftastic re-annotated but did not actually change.
    demoted = []
    for operation, lhs_index, rhs_index in operations:
        if (
            operation == "modify"
            and lhs_lines[lhs_index] == rhs_lines[rhs_index]
        ):
            demoted.append(("context", lhs_index, rhs_index))
        else:
            demoted.append((operation, lhs_index, rhs_index))
    return demoted


def compute_hunks(operations, context_lines=3):
    change_indices = [
        index
        for index, (operation, _, _) in enumerate(operations)
        if operation != "context"
    ]

    if not change_indices:
        return []

    hunks = []
    hunk_start = max(0, change_indices[0] - context_lines)
    hunk_end = min(len(operations), change_indices[0] + context_lines + 1)

    for index in change_indices[1:]:
        candidate_start = max(0, index - context_lines)
        candidate_end = min(len(operations), index + context_lines + 1)

        if candidate_start <= hunk_end:
            hunk_end = candidate_end
        else:
            hunks.append((hunk_start, hunk_end))
            hunk_start = candidate_start
            hunk_end = candidate_end

    hunks.append((hunk_start, hunk_end))
    return hunks


def render_line_with_emphasis(line_text, changes, base_color, emphasis_color):
    if not changes:
        return f"{base_color}{line_text}{RESET}"

    emphasis_ranges = sorted((change["start"], change["end"]) for change in changes)

    result = [base_color]
    in_emphasis = False

    for column, character in enumerate(line_text):
        should_emphasize = any(start <= column < end for start, end in emphasis_ranges)
        if should_emphasize and not in_emphasis:
            result.append(emphasis_color)
            in_emphasis = True
        elif not should_emphasize and in_emphasis:
            result.append(RESET + base_color)
            in_emphasis = False
        result.append(character)

    result.append(RESET)
    return "".join(result)


def render_hunk_header(operations):
    lhs_line_numbers = []
    rhs_line_numbers = []

    for operation, lhs_index, rhs_index in operations:
        if lhs_index is not None:
            lhs_line_numbers.append(lhs_index + 1)
        if rhs_index is not None:
            rhs_line_numbers.append(rhs_index + 1)

    if lhs_line_numbers:
        old_start = min(lhs_line_numbers)
        old_count = len(lhs_line_numbers)
    else:
        old_start = 0
        old_count = 0

    if rhs_line_numbers:
        new_start = min(rhs_line_numbers)
        new_count = len(rhs_line_numbers)
    else:
        new_start = 0
        new_count = 0

    return f"{MAGENTA}@@ -{old_start},{old_count} +{new_start},{new_count} @@{RESET}"


def strip_alignment_sentinel(aligned_lines, lhs_line_count, rhs_line_count):
    if not aligned_lines:
        return aligned_lines

    last_lhs_index, last_rhs_index = aligned_lines[-1]
    if last_lhs_index == lhs_line_count and last_rhs_index == rhs_line_count:
        return aligned_lines[:-1]

    raise ValueError(
        "difft-unified: expected aligned_lines to end with an end-of-file "
        f"sentinel ({lhs_line_count}, {rhs_line_count}), found "
        f"({last_lhs_index}, {last_rhs_index})"
    )


def render_changed_file(path, lhs_lines, rhs_lines, data):
    validate_difft_json(data, path)

    # With DFT_SKIP_UNCHANGED, difft reports "unchanged" (and omits chunks/aligned_lines)
    # whenever it considers the two sides equivalent, which includes byte-identical content
    # and, for structurally parsed languages, purely cosmetic differences such as an added or
    # removed blank line that git still hashes as a real change. There is nothing to render.
    if data["status"] == "unchanged":
        return ""

    aligned = strip_alignment_sentinel(
        data["aligned_lines"], len(lhs_lines), len(rhs_lines)
    )
    chunks = data["chunks"]

    lhs_changes, rhs_changes, modified_pairs = build_chunk_lookup(chunks)
    operations = classify_lines(aligned, lhs_changes, rhs_changes, modified_pairs)
    operations = demote_identical_modifications(operations, lhs_lines, rhs_lines)
    hunks = compute_hunks(operations)

    output_parts = []

    for hunk_start, hunk_end in hunks:
        hunk_operations = operations[hunk_start:hunk_end]
        output_parts.append(render_hunk_header(hunk_operations))

        for operation, lhs_index, rhs_index in hunk_operations:
            if operation == "context":
                output_parts.append(f"{DEFAULT} {rhs_lines[rhs_index]}{RESET}")
            elif operation == "add":
                changes = rhs_changes.get(rhs_index, [])
                emphasized = render_line_with_emphasis(
                    rhs_lines[rhs_index], changes, GREEN, EMPHASIS_ADD
                )
                output_parts.append(f"{GREEN}+{RESET}{emphasized}")
            elif operation == "delete":
                changes = lhs_changes.get(lhs_index, [])
                emphasized = render_line_with_emphasis(
                    lhs_lines[lhs_index], changes, RED, EMPHASIS_DEL
                )
                output_parts.append(f"{RED}-{RESET}{emphasized}")
            elif operation == "modify":
                lhs_emphasized = render_line_with_emphasis(
                    lhs_lines[lhs_index], lhs_changes.get(lhs_index, []),
                    RED, EMPHASIS_DEL
                )
                rhs_emphasized = render_line_with_emphasis(
                    rhs_lines[rhs_index], rhs_changes.get(rhs_index, []),
                    GREEN, EMPHASIS_ADD
                )
                output_parts.append(f"{RED}-{RESET}{lhs_emphasized}")
                output_parts.append(f"{GREEN}+{RESET}{rhs_emphasized}")

    return "\n".join(output_parts)


def run_difft(old_file, new_file):
    environment = os.environ.copy()
    environment["DFT_DISPLAY"] = "json"
    environment["DFT_SKIP_UNCHANGED"] = "true"
    environment["DFT_SYNTAX_HIGHLIGHT"] = "off"
    environment["DFT_UNSTABLE"] = "true"
    result = subprocess.run(
        ["difft", old_file, new_file],
        capture_output=True,
        text=True,
        env=environment,
    )
    output = result.stdout.strip()
    if not output:
        return None
    return json.loads(output)


def parse_arguments(argv):
    # Git's external diff protocol calls the driver with 7 positional parameters:
    # path old-file old-hex old-mode new-file new-hex new-mode
    # When diff.renames detects a rename or copy with content changes, it appends two
    # more positional parameters: the destination path and a rename/copy description
    # line (for example "similarity index 93%"), with the leading path then holding the
    # source (pre-rename) path instead of the single shared path.
    usage_message = (
        f"Usage: {argv[0]} <path> <old-file> <old-hex> <old-mode> <new-file> <new-hex>"
        " <new-mode> [<new-path> <rename-description>]"
    )

    if len(argv) == 8:
        old_path = argv[1]
        old_file = argv[2]
        old_hex = argv[3]
        old_mode = argv[4]
        new_file = argv[5]
        new_hex = argv[6]
        new_mode = argv[7]
        new_path = old_path
        rename_description = None
    elif len(argv) == 10:
        old_path = argv[1]
        old_file = argv[2]
        old_hex = argv[3]
        old_mode = argv[4]
        new_file = argv[5]
        new_hex = argv[6]
        new_mode = argv[7]
        new_path = argv[8]
        rename_description = argv[9]
    else:
        raise ValueError(usage_message)

    return (
        old_path,
        old_file,
        old_hex,
        old_mode,
        new_file,
        new_hex,
        new_mode,
        new_path,
        rename_description,
    )


def main():
    try:
        (
            old_path,
            old_file,
            old_hex,
            old_mode,
            new_file,
            new_hex,
            new_mode,
            new_path,
            rename_description,
        ) = parse_arguments(sys.argv)
    except ValueError as error:
        print(error, file=sys.stderr)
        sys.exit(1)

    status = detect_status(old_hex, old_file, new_hex, new_file)
    print(
        render_file_header(
            old_path, new_path, old_hex, old_mode, new_hex, new_mode, status, rename_description
        )
    )

    if is_binary(old_file) or is_binary(new_file):
        print(render_binary_notice(old_path, new_path, status))
        return

    if status == "created":
        body = render_full_addition(read_lines(new_file))
        if body:
            print(body)
        return

    if status == "deleted":
        body = render_full_deletion(read_lines(old_file))
        if body:
            print(body)
        return

    lhs_lines = read_lines(old_file)
    rhs_lines = read_lines(new_file)

    data = run_difft(old_file, new_file)
    if data is None:
        return

    error_path = old_path if old_path == new_path else f"{old_path} -> {new_path}"
    body = render_changed_file(error_path, lhs_lines, rhs_lines, data)
    if body:
        print(body)


if __name__ == "__main__":
    main()

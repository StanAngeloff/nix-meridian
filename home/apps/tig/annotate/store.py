"""The note store behind tig-annotate: one Markdown note per anchored diff line, and its export.

Notes live in {git_dir}/tig-annotate/ as "{encoded_key}.md". The key is "{path}:{line}" for added and
context lines (new-file numbering) and "{path}:-{line}" for deleted lines (old-file numbering); the
encoding replaces "/" with U+00B7 MIDDLE DOT. tig computes the same key for %(annotation) and for its
※ marks (pkgs/tig/patches/annotation-marks.patch), so the two formats change together.

Beside each note sits a JSON sidecar holding the side and the diff line as tig showed it. It is written
once, when the note is first prepared, and never rewritten. Notes made before sidecars existed have
none and export without the quoted line. File-level notes from before notes had lines ("{path}:file.md")
are listed, so they can still be read, edited and trashed, but export skips them.
"""

import errno
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

STORE_DIRECTORY_NAME = "tig-annotate"
ENCODED_SEPARATOR = "\u00b7"
NOTE_SUFFIX = ".md"
LEGACY_FILE_SUFFIX = ":file"
SIDECAR_SUFFIX = ".json"
# tig copies %(text) into a SIZEOF_STR (1024-byte) buffer, so a longer line arrives cut to its first 1023 bytes.
TIG_TEXT_LIMIT_BYTES = 1023
DIFF_MARKERS = "+- "
OUTDATED_LABEL = "[Outdated — the code changed after this comment]"
KEY_SUFFIX_RE = re.compile(r"(-?)([1-9][0-9]*)")
BACKTICK_RUN_RE = re.compile(r"`+")
USAGE = "Usage: tig-annotate-store {prepare|settle|export|copy|cut|entries|trash} ..."


@dataclass(frozen=True)
class Anchor:
    path: str
    line_number: int
    side: str

    @property
    def key_suffix(self):
        return f"-{self.line_number}" if self.side == "old" else str(self.line_number)

    @property
    def sort_key(self):
        # On the same line number the deletion comes first, as it does in the diff.
        return (self.path, self.line_number, 0 if self.side == "old" else 1)


@dataclass(frozen=True)
class Note:
    note_path: Path
    anchor: Anchor
    body: str
    line_text: str | None


def side_label(anchor, line_text):
    """The side a label shows: "unchanged" for a context line, which keeps the new file's number."""
    if anchor.side == "new" and line_text is not None and line_text.startswith(" "):
        return "unchanged"
    return anchor.side


def line_label(anchor, line_text):
    return f"{anchor.path}:{anchor.line_number} ({side_label(anchor, line_text)})"


def parse_key(key):
    """The Anchor for an unencoded key such as "src/app.ts:42" or "src/app.ts:-8", or None."""
    path, separator, suffix = key.rpartition(":")
    match = KEY_SUFFIX_RE.fullmatch(suffix)
    if not separator or not path or not match:
        return None
    return Anchor(path, int(match.group(2)), "old" if match.group(1) else "new")


def encode_path(path):
    return path.replace("/", ENCODED_SEPARATOR)


def decode_path(encoded_path):
    return encoded_path.replace(ENCODED_SEPARATOR, "/")


def note_file_name(anchor):
    return f"{encode_path(anchor.path)}:{anchor.key_suffix}{NOTE_SUFFIX}"


def anchor_from_note_name(note_name):
    """The Anchor a note's file name encodes, or None for names this store did not write."""
    if not note_name.endswith(NOTE_SUFFIX):
        return None
    return parse_key(decode_path(note_name[: -len(NOTE_SUFFIX)]))


def sidecar_path(note_path):
    return note_path.with_suffix(SIDECAR_SUFFIX)


def resolve_git_dir(git_dir):
    """The real git directory: in a linked worktree ".git" is a file that points at it."""
    git_path = Path(git_dir)
    if git_path.is_file():
        first_line = git_path.read_text(encoding="utf-8").splitlines()[0]
        git_path = git_path.parent / first_line.removeprefix("gitdir: ")
    return git_path.absolute()


def store_directory(git_dir):
    return resolve_git_dir(git_dir) / STORE_DIRECTORY_NAME


def is_blank(text):
    return not text.strip()


def text_bytes(text):
    """Text as the bytes it came from: lines that are not UTF-8 travel as surrogate escapes."""
    return text.encode("utf-8", "surrogateescape")


def read_body(note_path):
    """The note's text, or None when it is gone or holds only whitespace."""
    try:
        body = note_path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return None
    return None if is_blank(body) else body


def write_sidecar_once(note_path, anchor, line_text):
    """Record the side and the diff line beside a note, unless an earlier prepare already did."""
    target_path = sidecar_path(note_path)
    if target_path.exists():
        return
    file_descriptor, temporary_name = tempfile.mkstemp(
        dir=note_path.parent, prefix=".sidecar-", suffix=".tmp"
    )
    try:
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as temporary_file:
            json.dump({"side": anchor.side, "text": line_text}, temporary_file)
            temporary_file.write("\n")
        # Some file systems refuse a name that is too long only here, when it is created.
        os.replace(temporary_name, target_path)
    except BaseException:
        Path(temporary_name).unlink(missing_ok=True)
        raise


def read_line_text(note_path):
    """The diff line recorded when the note was prepared, or None for notes without a sidecar."""
    try:
        sidecar = json.loads(sidecar_path(note_path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    text = sidecar.get("text") if isinstance(sidecar, dict) else None
    return text if isinstance(text, str) and text else None


def load_notes(directory, only=None):
    """Non-empty notes in export order, and the names of notes that have no line to anchor to.

    `only` limits the result to the given note paths (the fzf selection). Listing with os.listdir
    keeps dot-files, which a shell glob would skip: a note on ".circleci/config.yml" is one.
    """
    wanted_names = (
        None if only is None else {Path(note_path).name for note_path in only}
    )
    try:
        names = os.listdir(directory)
    except FileNotFoundError:
        return [], []
    notes, unplaceable_names = [], []
    for name in names:
        if not name.endswith(NOTE_SUFFIX):
            continue
        if wanted_names is not None and name not in wanted_names:
            continue
        note_path = Path(directory) / name
        body = read_body(note_path)
        if body is None:
            continue
        anchor = anchor_from_note_name(name)
        if anchor is None:
            unplaceable_names.append(name)
            continue
        notes.append(Note(note_path, anchor, body, read_line_text(note_path)))
    notes.sort(key=lambda note: note.anchor.sort_key)
    return notes, sorted(unplaceable_names)


def resolve_toplevel(working_directory=None):
    """The working tree root, or None when there is none."""
    try:
        completed = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=working_directory,
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return Path(completed.stdout.rstrip("\n"))


def working_tree_line(toplevel, path, line_number):
    """Line `line_number` of the working-tree file, split the way git splits lines, or None when gone."""
    try:
        data = (toplevel / path).read_bytes()
    except OSError:
        return None
    lines = data.split(b"\n")
    if data.endswith(b"\n"):
        lines.pop()
    if line_number > len(lines):
        return None
    return lines[line_number - 1].decode("utf-8", "surrogateescape")


def line_contents(line_text):
    """The diff line without its prefix: one marker, or two when it may come from a combined (merge) diff."""
    contents = [line_text[1:]]
    if (
        len(line_text) >= 2
        and line_text[0] in DIFF_MARKERS
        and line_text[1] in DIFF_MARKERS
    ):
        contents.append(line_text[2:])
    return contents


def is_outdated(note, toplevel):
    """Whether the working tree no longer has the new-side line the note was made on.

    Deleted lines are not in the working tree, and notes without a sidecar have nothing to compare,
    so neither is ever flagged. A line tig cut at its limit is compared as a prefix, and in bytes,
    because the cut can fall inside a character.
    """
    if note.anchor.side != "new" or note.line_text is None or toplevel is None:
        return False
    current = working_tree_line(toplevel, note.anchor.path, note.anchor.line_number)
    if current is None:
        return True
    current_bytes = text_bytes(current.removesuffix("\r"))
    was_cut = len(text_bytes(note.line_text)) >= TIG_TEXT_LIMIT_BYTES
    for content in line_contents(note.line_text):
        content_bytes = text_bytes(content.removesuffix("\r"))
        if current_bytes == content_bytes:
            return False
        if was_cut and current_bytes.startswith(content_bytes):
            return False
    return True


def fence_for(text):
    """A code fence one backtick longer than the longest backtick run in `text`, at least three."""
    longest_run = max((len(run) for run in BACKTICK_RUN_RE.findall(text)), default=0)
    return "`" * max(3, longest_run + 1)


def format_note(note, outdated):
    parts = [
        f"### Line {note.anchor.line_number} ({side_label(note.anchor, note.line_text)})"
    ]
    if outdated:
        parts.append(OUTDATED_LABEL)
    if note.line_text is not None:
        fence = fence_for(note.line_text)
        parts.append(f"{fence}diff\n{note.line_text}\n{fence}")
    parts.append(note.body.strip("\n").rstrip())
    return "\n".join(parts)


def export_markdown(notes, toplevel):
    """Plannotator's review layout: one "## path" section per file, its notes in line order."""
    sections = []
    current_path = None
    for note in notes:
        if note.anchor.path != current_path:
            current_path = note.anchor.path
            sections.append(f"## {current_path}")
        sections.append(format_note(note, is_outdated(note, toplevel)))
    return "\n\n".join(sections) + "\n"


def first_line(body):
    return body.strip("\n").splitlines()[0]


def format_entry(note):
    return f"{note.note_path}\t{line_label(note.anchor, note.line_text)} — {first_line(note.body)}"


def format_legacy_entry(note_path, body):
    """The entry for a note without a line, such as a "{path}:file.md" note from before notes had lines."""
    key = decode_path(note_path.name.removesuffix(NOTE_SUFFIX))
    path = key.removesuffix(LEGACY_FILE_SUFFIX)
    return f"{note_path}\t{path} (legacy file note) — {first_line(body)}"


def copy_summary(copied_count, unplaceable_names, cut=False):
    summary = f"{'Cut' if cut else 'Copied'} {copied_count} annotation(s) to clipboard"
    if unplaceable_names:
        skipped = ", ".join(unplaceable_names)
        summary += (
            f"; skipped {len(unplaceable_names)} note(s) without a line: {skipped}"
        )
    return summary


def parse_assignments(arguments):
    """tig bindings pass key=value arguments because tig drops empty ones, which shifts positions."""
    values = {}
    for argument in arguments:
        key, separator, value = argument.partition("=")
        if separator:
            values[key] = value
    return values


def is_tracked(path):
    completed = subprocess.run(
        ["git", "ls-files", "--error-unmatch", "--", f":(top,literal){path}"],
        capture_output=True,
    )
    return completed.returncode == 0


def command_prepare(git_dir, arguments):
    values = parse_assignments(arguments)
    anchor = parse_key(values.get("annotation", ""))
    if anchor is None:
        print("Not an annotatable line")
        return 1
    # A deleted line always comes from a commit or the index, even when its file is no longer tracked.
    if anchor.side == "new" and not is_tracked(anchor.path):
        print("Cannot annotate untracked files")
        return 1
    directory = store_directory(git_dir)
    directory.mkdir(parents=True, exist_ok=True)
    note_path = directory / note_file_name(anchor)
    try:
        write_sidecar_once(note_path, anchor, values.get("text", ""))
    except OSError as error:
        if error.errno != errno.ENAMETOOLONG:
            raise
        print("Path too long to annotate")
        return 1
    print(note_path)
    # The sidecar keeps the line from when the note was first made, and the export quotes that line.
    print(line_label(anchor, read_line_text(note_path)))
    return 0


def command_settle(note_path_argument):
    note_path = Path(note_path_argument)
    try:
        body = note_path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        body = ""
    if is_blank(body):
        note_path.unlink(missing_ok=True)
        sidecar_path(note_path).unlink(missing_ok=True)
        return 0
    anchor = anchor_from_note_name(note_path.name)
    label = line_label(anchor, read_line_text(note_path)) if anchor else note_path.name
    print(f"Annotated: {label}")
    return 0


def command_export(git_dir, note_paths):
    notes, unplaceable_names = load_notes(store_directory(git_dir), note_paths or None)
    for name in unplaceable_names:
        print(
            f"tig-annotate: skipped {name}: it has no line to anchor to",
            file=sys.stderr,
        )
    if not notes:
        return 1
    sys.stdout.write(export_markdown(notes, resolve_toplevel()))
    return 0


def command_copy(git_dir, note_paths, cut=False):
    """Copy the export to the clipboard; `cut` then trashes the notes it copied, and keeps the ones it skipped."""
    notes, unplaceable_names = load_notes(store_directory(git_dir), note_paths or None)
    if not notes:
        print("No annotations to copy")
        return 0
    markdown = export_markdown(notes, resolve_toplevel())
    # wl-copy forks a child that keeps serving the clipboard; pipes left open to it would block run().
    completed = subprocess.run(
        ["wl-copy"],
        input=text_bytes(markdown),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if completed.returncode != 0:
        print("wl-copy failed; nothing was copied")
        return 1
    if cut:
        # tig shows the first line a binding prints, stderr included, so gio's own messages are kept out of it.
        trashed = subprocess.run(
            ["gio", "trash", *trash_targets(note.note_path for note in notes)],
            capture_output=True,
        )
        if trashed.returncode != 0:
            print(
                f"Copied {len(notes)} annotation(s) to clipboard, but gio trash failed"
            )
            return 1
    print(copy_summary(len(notes), unplaceable_names, cut))
    return 0


def command_entries(git_dir):
    directory = store_directory(git_dir)
    notes, unplaceable_names = load_notes(directory)
    for note in notes:
        print(format_entry(note))
    for name in unplaceable_names:
        body = read_body(directory / name)
        if body is not None:
            print(format_legacy_entry(directory / name, body))
    return 0


def trash_targets(note_paths):
    """Each note followed by its sidecar, when it has one."""
    targets = []
    for note_path_argument in note_paths:
        note_path = Path(note_path_argument)
        targets.append(str(note_path))
        if sidecar_path(note_path).exists():
            targets.append(str(sidecar_path(note_path)))
    return targets


def command_trash(note_paths):
    targets = trash_targets(note_paths)
    if targets:
        return subprocess.run(["gio", "trash", *targets]).returncode
    return 0


def main(arguments):
    command = arguments[0] if arguments else ""
    rest = arguments[1:]
    if command == "prepare" and rest:
        return command_prepare(rest[0], rest[1:])
    if command == "settle" and len(rest) == 1:
        return command_settle(rest[0])
    if command == "export" and rest:
        return command_export(rest[0], rest[1:])
    if command in ("copy", "cut") and rest:
        return command_copy(rest[0], rest[1:], cut=command == "cut")
    if command == "entries" and len(rest) == 1:
        return command_entries(rest[0])
    if command == "trash":
        return command_trash(rest)
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    # Lines from files that are not UTF-8 travel as surrogate escapes; write them back out as bytes.
    sys.stdout.reconfigure(errors="surrogateescape")
    sys.exit(main(sys.argv[1:]))

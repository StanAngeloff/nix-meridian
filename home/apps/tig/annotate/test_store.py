import contextlib
import errno
import io
import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest import mock

import store

MIDDLE_DOT = "\u00b7"


def git(repository_path, *arguments):
    subprocess.run(
        ["git", "-C", str(repository_path), *arguments],
        check=True,
        capture_output=True,
        env={**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"},
    )


def write_note(directory, name, body, line_text=None, side="new"):
    note_path = Path(directory) / name
    note_path.write_text(body, encoding="utf-8")
    if line_text is not None:
        store.sidecar_path(note_path).write_text(
            json.dumps({"side": side, "text": line_text}), encoding="utf-8"
        )
    return note_path


class Keys(unittest.TestCase):
    def test_new_side_key(self):
        self.assertEqual(
            store.parse_key("src/app.ts:42"), store.Anchor("src/app.ts", 42, "new")
        )

    def test_old_side_key(self):
        self.assertEqual(
            store.parse_key("src/app.ts:-8"), store.Anchor("src/app.ts", 8, "old")
        )

    def test_path_may_contain_colons(self):
        self.assertEqual(
            store.parse_key("a:b/c.txt:3"), store.Anchor("a:b/c.txt", 3, "new")
        )

    def test_keys_without_a_line_are_rejected(self):
        for key in [
            "src/app.ts:file",
            "src/app.ts:0",
            "src/app.ts:-0",
            "",
            "no-separator",
            ":5",
            "a:+5",
        ]:
            with self.subTest(key=key):
                self.assertIsNone(store.parse_key(key))

    def test_note_file_name_encodes_slashes_and_side(self):
        anchor = store.Anchor("src/app.ts", 8, "old")
        self.assertEqual(store.note_file_name(anchor), f"src{MIDDLE_DOT}app.ts:-8.md")

    def test_dot_file_note_name_round_trips(self):
        name = f".circleci{MIDDLE_DOT}config.yml:12.md"
        self.assertEqual(
            store.anchor_from_note_name(name),
            store.Anchor(".circleci/config.yml", 12, "new"),
        )

    def test_encoding_uses_the_middle_dot_bytes_tig_expects(self):
        self.assertEqual(store.encode_path("a/b").encode("utf-8"), b"a\xc2\xb7b")

    def test_line_label_names_the_side(self):
        old_anchor = store.Anchor("src/app.ts", 8, "old")
        new_anchor = store.Anchor("src/app.ts", 8, "new")
        self.assertEqual(store.line_label(old_anchor, "-gone"), "src/app.ts:8 (old)")
        self.assertEqual(store.line_label(new_anchor, "+added"), "src/app.ts:8 (new)")
        self.assertEqual(store.line_label(new_anchor, None), "src/app.ts:8 (new)")

    def test_line_label_calls_a_context_line_unchanged(self):
        anchor = store.Anchor("flake.lock", 16, "new")
        self.assertEqual(
            store.line_label(anchor, '        "type": "github"'),
            "flake.lock:16 (unchanged)",
        )


class GitDirectory(unittest.TestCase):
    def test_linked_worktree_git_file_is_followed(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "real").mkdir()
            (root / "checkout").mkdir()
            (root / "checkout" / ".git").write_text(
                "gitdir: ../real\n", encoding="utf-8"
            )
            resolved = store.resolve_git_dir(root / "checkout" / ".git")
            self.assertEqual(resolved.resolve(), (root / "real").resolve())

    def test_plain_git_directory_is_kept(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            git_dir = Path(temporary_directory) / ".git"
            git_dir.mkdir()
            self.assertEqual(
                store.store_directory(git_dir), git_dir.absolute() / "tig-annotate"
            )


class Sidecars(unittest.TestCase):
    def test_written_once_and_never_rewritten(self):
        with tempfile.TemporaryDirectory() as directory:
            note_path = Path(directory) / "app.txt:2.md"
            anchor = store.Anchor("app.txt", 2, "new")
            store.write_sidecar_once(note_path, anchor, "+first")
            store.write_sidecar_once(note_path, anchor, "+second")
            sidecar = json.loads(
                store.sidecar_path(note_path).read_text(encoding="utf-8")
            )
            self.assertEqual(sidecar, {"side": "new", "text": "+first"})
            self.assertEqual(sorted(os.listdir(directory)), ["app.txt:2.json"])

    def test_missing_or_broken_sidecar_reads_as_none(self):
        with tempfile.TemporaryDirectory() as directory:
            note_path = Path(directory) / "app.txt:2.md"
            self.assertIsNone(store.read_line_text(note_path))
            store.sidecar_path(note_path).write_text("{not json", encoding="utf-8")
            self.assertIsNone(store.read_line_text(note_path))

    def test_a_failed_write_leaves_no_temporary_file(self):
        with tempfile.TemporaryDirectory() as directory:
            note_path = Path(directory) / "app.txt:2.md"
            anchor = store.Anchor("app.txt", 2, "new")
            refusal = OSError(errno.EIO, "Input/output error")
            with mock.patch.object(store.os, "replace", side_effect=refusal):
                with self.assertRaises(OSError):
                    store.write_sidecar_once(note_path, anchor, "+first")
            self.assertEqual(os.listdir(directory), [])


class Loading(unittest.TestCase):
    def test_order_blank_notes_and_unplaceable_names(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in [
                "b.txt:10.md",
                "b.txt:9.md",
                "b.txt:-9.md",
                "a.txt:263.md",
                "a.txt:41.md",
            ]:
                write_note(directory, name, f"note {name}\n")
            write_note(
                directory, f".circleci{MIDDLE_DOT}config.yml:1.md", "dot-file note\n"
            )
            write_note(directory, "blank.txt:1.md", "  \n\n")
            write_note(directory, "legacy.txt:file.md", "file-level note\n")
            write_note(directory, ".sidecar-abc.tmp", "not a note")
            notes, unplaceable_names = store.load_notes(directory)
            self.assertEqual(
                [store.line_label(note.anchor, note.line_text) for note in notes],
                [
                    ".circleci/config.yml:1 (new)",
                    "a.txt:41 (new)",
                    "a.txt:263 (new)",
                    "b.txt:9 (old)",
                    "b.txt:9 (new)",
                    "b.txt:10 (new)",
                ],
            )
            self.assertEqual(unplaceable_names, ["legacy.txt:file.md"])

    def test_only_limits_to_the_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            chosen_path = write_note(directory, "a.txt:1.md", "chosen\n")
            write_note(directory, "a.txt:2.md", "left out\n")
            notes, _ = store.load_notes(directory, only=[str(chosen_path)])
            self.assertEqual([note.note_path for note in notes], [chosen_path])

    def test_missing_store_is_empty(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(store.load_notes(Path(directory) / "absent"), ([], []))

    def test_line_text_comes_from_the_sidecar(self):
        with tempfile.TemporaryDirectory() as directory:
            write_note(directory, "a.txt:1.md", "note\n", line_text="+alpha")
            notes, _ = store.load_notes(directory)
            self.assertEqual(notes[0].line_text, "+alpha")


def note(path, line_number, side, body, line_text=None):
    anchor = store.Anchor(path, line_number, side)
    return store.Note(
        Path("/store") / store.note_file_name(anchor), anchor, body, line_text
    )


class Formatting(unittest.TestCase):
    def test_fence_grows_past_backtick_runs(self):
        self.assertEqual(store.fence_for("plain"), "```")
        self.assertEqual(store.fence_for("`inline`"), "```")
        self.assertEqual(store.fence_for("a ``` b"), "````")
        self.assertEqual(store.fence_for("a ````` b"), "``````")

    def test_legacy_note_has_no_quote(self):
        self.assertEqual(
            store.format_note(note("a.txt", 5, "new", "\nLegacy.\n\n"), outdated=False),
            "### Line 5 (new)\nLegacy.",
        )

    def test_outdated_label_precedes_the_quote(self):
        self.assertEqual(
            store.format_note(
                note("a.txt", 5, "new", "Why?\n", "+x = 1"), outdated=True
            ),
            "### Line 5 (new)\n"
            "[Outdated — the code changed after this comment]\n"
            "```diff\n+x = 1\n```\n"
            "Why?",
        )

    def test_golden_export(self):
        notes = [
            note(
                ".circleci/config.yml",
                12,
                "new",
                "Why run this twice?\n",
                "+    run: make test",
            ),
            note(
                "drift.txt",
                8,
                "old",
                "Keep this; the importer still reads it.\n",
                "-line8",
            ),
            note("drift.txt", 14, "new", "Legacy note without a sidecar.\n"),
        ]
        self.assertEqual(
            store.export_markdown(notes, toplevel=None),
            "## .circleci/config.yml\n"
            "\n"
            "### Line 12 (new)\n"
            "```diff\n"
            "+    run: make test\n"
            "```\n"
            "Why run this twice?\n"
            "\n"
            "## drift.txt\n"
            "\n"
            "### Line 8 (old)\n"
            "```diff\n"
            "-line8\n"
            "```\n"
            "Keep this; the importer still reads it.\n"
            "\n"
            "### Line 14 (new)\n"
            "Legacy note without a sidecar.\n",
        )

    def test_entry_shows_label_and_first_line(self):
        entry = store.format_entry(note("a.txt", 3, "old", "\nFirst line\nsecond\n"))
        self.assertEqual(entry, "/store/a.txt:-3.md\ta.txt:3 (old) — First line")

    def test_context_line_heading_says_unchanged(self):
        context_note = note("a.txt", 5, "new", "Why?\n", " alpha")
        self.assertEqual(
            store.format_note(context_note, outdated=False),
            "### Line 5 (unchanged)\n```diff\n alpha\n```\nWhy?",
        )

    def test_context_line_entry_says_unchanged(self):
        entry = store.format_entry(note("a.txt", 3, "new", "First\n", " alpha"))
        self.assertEqual(entry, "/store/a.txt:3.md\ta.txt:3 (unchanged) — First")

    def test_copy_summary(self):
        self.assertEqual(
            store.copy_summary(2, []), "Copied 2 annotation(s) to clipboard"
        )
        self.assertEqual(
            store.copy_summary(1, ["x.txt:file.md"]),
            "Copied 1 annotation(s) to clipboard; skipped 1 note(s) without a line: x.txt:file.md",
        )
        self.assertEqual(
            store.copy_summary(2, [], cut=True), "Cut 2 annotation(s) to clipboard"
        )


class Outdated(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.toplevel = Path(self.temporary_directory.name)
        git(self.toplevel, "init", "-q")
        (self.toplevel / "app.txt").write_text("alpha\nbeta\n", encoding="utf-8")
        (self.toplevel / "windows.txt").write_bytes(b"alpha\r\nbeta\r\n")

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_toplevel_resolves_from_inside_the_repository(self):
        (self.toplevel / "nested").mkdir()
        resolved = store.resolve_toplevel(self.toplevel / "nested")
        self.assertEqual(resolved.resolve(), self.toplevel.resolve())

    def test_toplevel_outside_a_repository_is_none(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertIsNone(store.resolve_toplevel(directory))

    def test_matching_line_is_current(self):
        self.assertFalse(
            store.is_outdated(note("app.txt", 2, "new", "n", "+beta"), self.toplevel)
        )

    def test_context_line_prefix_is_a_space(self):
        self.assertFalse(
            store.is_outdated(note("app.txt", 1, "new", "n", " alpha"), self.toplevel)
        )

    def test_changed_line_is_outdated(self):
        self.assertTrue(
            store.is_outdated(note("app.txt", 2, "new", "n", "+gamma"), self.toplevel)
        )

    def test_line_past_the_end_is_outdated(self):
        self.assertTrue(
            store.is_outdated(note("app.txt", 3, "new", "n", "+beta"), self.toplevel)
        )

    def test_deleted_file_is_outdated(self):
        self.assertTrue(
            store.is_outdated(note("gone.txt", 1, "new", "n", "+x"), self.toplevel)
        )

    def test_carriage_returns_are_ignored(self):
        self.assertFalse(
            store.is_outdated(
                note("windows.txt", 2, "new", "n", "+beta"), self.toplevel
            )
        )

    def test_old_side_and_legacy_notes_are_never_flagged(self):
        self.assertFalse(
            store.is_outdated(note("app.txt", 2, "old", "n", "-gone"), self.toplevel)
        )
        self.assertFalse(
            store.is_outdated(note("app.txt", 2, "new", "n"), self.toplevel)
        )

    def test_a_shorter_line_is_not_a_match(self):
        self.assertTrue(
            store.is_outdated(note("app.txt", 1, "new", "n", "+alph"), self.toplevel)
        )

    def test_a_line_cut_at_tigs_limit_is_compared_as_a_prefix(self):
        long_line = "x" * 2000
        (self.toplevel / "long.txt").write_text(long_line + "\n", encoding="utf-8")
        cut_text = ("+" + long_line)[: store.TIG_TEXT_LIMIT_BYTES]
        self.assertFalse(
            store.is_outdated(note("long.txt", 1, "new", "n", cut_text), self.toplevel)
        )
        changed_text = "+y" + cut_text[2:]
        self.assertTrue(
            store.is_outdated(
                note("long.txt", 1, "new", "n", changed_text), self.toplevel
            )
        )

    def test_a_cut_through_a_multibyte_character_still_matches(self):
        # Three-byte characters after a one-byte prefix put tig's cut inside a character.
        long_line = chr(0x20AC) * 1000
        (self.toplevel / "wide.txt").write_text(long_line + "\n", encoding="utf-8")
        cut_bytes = ("+" + long_line).encode("utf-8")[: store.TIG_TEXT_LIMIT_BYTES]
        cut_text = cut_bytes.decode("utf-8", "surrogateescape")
        self.assertFalse(
            store.is_outdated(note("wide.txt", 1, "new", "n", cut_text), self.toplevel)
        )

    def test_combined_diff_lines_have_a_two_character_prefix(self):
        for line_text in ["++beta", "+ beta", " +beta"]:
            with self.subTest(line_text=line_text):
                self.assertFalse(
                    store.is_outdated(
                        note("app.txt", 2, "new", "n", line_text), self.toplevel
                    )
                )
        self.assertTrue(
            store.is_outdated(note("app.txt", 2, "new", "n", "++gamma"), self.toplevel)
        )

    def test_export_marks_only_the_outdated_note(self):
        notes = [
            note("app.txt", 1, "new", "Still true.", " alpha"),
            note("app.txt", 2, "new", "Changed since.", "+BETA"),
        ]
        markdown = store.export_markdown(notes, self.toplevel)
        self.assertEqual(markdown.count(store.OUTDATED_LABEL), 1)
        self.assertIn(f"### Line 2 (new)\n{store.OUTDATED_LABEL}\n", markdown)


class Commands(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repository_path = Path(self.temporary_directory.name)
        git(self.repository_path, "init", "-q")
        (self.repository_path / "app.txt").write_text("alpha\nbeta\n", encoding="utf-8")
        (self.repository_path / "untracked.txt").write_text("new\n", encoding="utf-8")
        git(self.repository_path, "add", "app.txt")
        self.git_dir = self.repository_path / ".git"
        self.previous_directory = os.getcwd()
        (self.repository_path / "nested").mkdir()
        os.chdir(self.repository_path / "nested")

    def tearDown(self):
        os.chdir(self.previous_directory)
        self.temporary_directory.cleanup()

    def run_main(self, *arguments):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exit_code = store.main(list(arguments))
        return exit_code, output.getvalue()

    def test_prepare_rejects_lines_without_an_anchor(self):
        exit_code, output = self.run_main(
            "prepare", str(self.git_dir), "annotation=", "text=@@"
        )
        self.assertEqual((exit_code, output), (1, "Not an annotatable line\n"))

    def test_prepare_rejects_untracked_files(self):
        exit_code, output = self.run_main(
            "prepare", str(self.git_dir), "annotation=untracked.txt:1", "text=+new"
        )
        self.assertEqual((exit_code, output), (1, "Cannot annotate untracked files\n"))

    def test_prepare_accepts_old_side_keys_of_files_that_are_gone(self):
        exit_code, output = self.run_main(
            "prepare", str(self.git_dir), "annotation=gone.txt:-1", "text=-bye"
        )
        note_path = self.git_dir.absolute() / "tig-annotate" / "gone.txt:-1.md"
        self.assertEqual((exit_code, output), (0, f"{note_path}\ngone.txt:1 (old)\n"))
        self.assertEqual(store.read_line_text(note_path), "-bye")

    def test_prepare_rejects_a_path_too_long_for_a_file_name(self):
        # Encoded, the three 100-byte directories alone make the note's name longer than 255 bytes.
        long_path = "/".join(["d" * 100] * 3) + "/f.txt"
        (self.repository_path / long_path).parent.mkdir(parents=True)
        (self.repository_path / long_path).write_text("x\n", encoding="utf-8")
        git(self.repository_path, "add", long_path)
        exit_code, output = self.run_main(
            "prepare", str(self.git_dir), f"annotation={long_path}:1", "text=+x"
        )
        self.assertEqual((exit_code, output), (1, "Path too long to annotate\n"))
        self.assertEqual(os.listdir(self.git_dir / "tig-annotate"), [])

    def test_prepare_fails_cleanly_when_the_rename_is_refused(self):
        # Some file systems report a name that is too long only when it is created.
        refusal = OSError(errno.ENAMETOOLONG, "File name too long")
        with mock.patch.object(store.os, "replace", side_effect=refusal):
            exit_code, output = self.run_main(
                "prepare", str(self.git_dir), "annotation=app.txt:1", "text= alpha"
            )
        self.assertEqual((exit_code, output), (1, "Path too long to annotate\n"))
        self.assertEqual(os.listdir(self.git_dir / "tig-annotate"), [])

    def test_prepare_writes_the_sidecar_and_prints_path_and_title(self):
        exit_code, output = self.run_main(
            "prepare", str(self.git_dir), "annotation=app.txt:-2", "text=-beta"
        )
        note_path = self.git_dir.absolute() / "tig-annotate" / "app.txt:-2.md"
        self.assertEqual((exit_code, output), (0, f"{note_path}\napp.txt:2 (old)\n"))
        self.assertFalse(note_path.exists())
        self.assertEqual(store.read_line_text(note_path), "-beta")

    def test_settle_removes_an_empty_note_and_its_sidecar(self):
        _, output = self.run_main(
            "prepare", str(self.git_dir), "annotation=app.txt:1", "text= alpha"
        )
        note_path = Path(output.splitlines()[0])
        note_path.write_text("\n", encoding="utf-8")
        self.assertEqual(self.run_main("settle", str(note_path)), (0, ""))
        self.assertEqual(os.listdir(note_path.parent), [])

    def test_settle_reports_a_kept_note(self):
        _, output = self.run_main(
            "prepare", str(self.git_dir), "annotation=app.txt:1", "text= alpha"
        )
        note_path = Path(output.splitlines()[0])
        note_path.write_text("Rename this.\n", encoding="utf-8")
        self.assertEqual(
            self.run_main("settle", str(note_path)),
            (0, "Annotated: app.txt:1 (unchanged)\n"),
        )

    def test_prepare_titles_a_context_line_unchanged(self):
        exit_code, output = self.run_main(
            "prepare", str(self.git_dir), "annotation=app.txt:1", "text= alpha"
        )
        self.assertEqual(
            (exit_code, output.splitlines()[1]), (0, "app.txt:1 (unchanged)")
        )

    def test_export_and_entries(self):
        _, output = self.run_main(
            "prepare", str(self.git_dir), "annotation=app.txt:2", "text=+beta"
        )
        note_path = Path(output.splitlines()[0])
        note_path.write_text("Why beta?\n", encoding="utf-8")
        exit_code, markdown = self.run_main("export", str(self.git_dir))
        self.assertEqual(exit_code, 0)
        self.assertEqual(
            markdown, "## app.txt\n\n### Line 2 (new)\n```diff\n+beta\n```\nWhy beta?\n"
        )
        self.assertEqual(
            self.run_main("entries", str(self.git_dir)),
            (0, f"{note_path}\tapp.txt:2 (new) — Why beta?\n"),
        )

    def annotate_beside_a_legacy_note(self):
        """A note on app.txt:2 beside a legacy file note and a blank one; returns the first two paths."""
        _, output = self.run_main(
            "prepare", str(self.git_dir), "annotation=app.txt:2", "text=+beta"
        )
        note_path = Path(output.splitlines()[0])
        note_path.write_text("Why beta?\n", encoding="utf-8")
        legacy_path = write_note(
            note_path.parent, f"src{MIDDLE_DOT}app.txt:file.md", "Old file note\nmore\n"
        )
        write_note(note_path.parent, "blank.txt:file.md", "\n")
        return note_path, legacy_path

    def test_entries_list_legacy_file_notes_last(self):
        note_path, legacy_path = self.annotate_beside_a_legacy_note()
        self.assertEqual(
            self.run_main("entries", str(self.git_dir)),
            (
                0,
                f"{note_path}\tapp.txt:2 (new) — Why beta?\n"
                f"{legacy_path}\tsrc/app.txt (legacy file note) — Old file note\n",
            ),
        )

    def test_export_warns_about_the_legacy_notes_it_skips(self):
        self.annotate_beside_a_legacy_note()
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            exit_code, markdown = self.run_main("export", str(self.git_dir))
        self.assertEqual(
            (exit_code, markdown),
            (0, "## app.txt\n\n### Line 2 (new)\n```diff\n+beta\n```\nWhy beta?\n"),
        )
        self.assertEqual(
            stderr.getvalue(),
            f"tig-annotate: skipped src{MIDDLE_DOT}app.txt:file.md: it has no line to anchor to\n",
        )

    def test_export_with_no_notes_fails_quietly(self):
        self.assertEqual(self.run_main("export", str(self.git_dir)), (1, ""))

    def install_fake_tools(self, wl_copy_exit_code=0, gio_exit_code=0):
        """wl-copy and gio stand-ins on PATH; returns the clipboard file and the file gio logs its arguments to.

        The fake wl-copy writes the clipboard to a file; the fake gio removes the files it is asked to trash.
        """
        tools_directory = tempfile.TemporaryDirectory()
        self.addCleanup(tools_directory.cleanup)
        tools_path = Path(tools_directory.name)
        clipboard_path = tools_path / "clipboard"
        gio_log_path = tools_path / "gio.json"
        scripts = {
            "wl-copy": f"""
                from pathlib import Path
                Path({str(clipboard_path)!r}).write_bytes(sys.stdin.buffer.read())
                sys.exit({wl_copy_exit_code})
            """,
            "gio": f"""
                from pathlib import Path
                Path({str(gio_log_path)!r}).write_text(json.dumps(sys.argv[1:]))
                if {gio_exit_code}:
                    print("gio: Error trashing file", file=sys.stderr)
                    sys.exit({gio_exit_code})
                for target in sys.argv[2:]:
                    os.remove(target)
            """,
        }
        for name, body in scripts.items():
            script_path = tools_path / name
            script_path.write_text(
                f"#!{sys.executable}\nimport json, os, sys\n" + textwrap.dedent(body),
                encoding="utf-8",
            )
            script_path.chmod(0o755)
        path_patcher = mock.patch.dict(
            os.environ, {"PATH": f"{tools_path}{os.pathsep}{os.environ['PATH']}"}
        )
        path_patcher.start()
        self.addCleanup(path_patcher.stop)
        return clipboard_path, gio_log_path

    def test_cut_trashes_what_it_copied_and_keeps_what_it_skipped(self):
        note_path, legacy_path = self.annotate_beside_a_legacy_note()
        clipboard_path, gio_log_path = self.install_fake_tools()
        self.assertEqual(
            self.run_main("cut", str(self.git_dir)),
            (
                0,
                "Cut 1 annotation(s) to clipboard; skipped 1 note(s) without a line: "
                f"src{MIDDLE_DOT}app.txt:file.md\n",
            ),
        )
        self.assertEqual(
            clipboard_path.read_text(encoding="utf-8"),
            "## app.txt\n\n### Line 2 (new)\n```diff\n+beta\n```\nWhy beta?\n",
        )
        self.assertEqual(
            json.loads(gio_log_path.read_text(encoding="utf-8")),
            ["trash", str(note_path), str(store.sidecar_path(note_path))],
        )
        self.assertTrue(legacy_path.exists())

    def test_copy_keeps_the_notes(self):
        note_path, _ = self.annotate_beside_a_legacy_note()
        _, gio_log_path = self.install_fake_tools()
        exit_code, output = self.run_main("copy", str(self.git_dir))
        self.assertEqual(
            (exit_code, output.split(";")[0]),
            (0, "Copied 1 annotation(s) to clipboard"),
        )
        self.assertTrue(note_path.exists())
        self.assertFalse(gio_log_path.exists())

    def test_cut_trashes_nothing_when_the_copy_fails(self):
        note_path, _ = self.annotate_beside_a_legacy_note()
        _, gio_log_path = self.install_fake_tools(wl_copy_exit_code=1)
        self.assertEqual(
            self.run_main("cut", str(self.git_dir)),
            (1, "wl-copy failed; nothing was copied\n"),
        )
        self.assertTrue(note_path.exists())
        self.assertFalse(gio_log_path.exists())

    def test_cut_reports_a_failed_trash(self):
        self.annotate_beside_a_legacy_note()
        self.install_fake_tools(gio_exit_code=2)
        self.assertEqual(
            self.run_main("cut", str(self.git_dir)),
            (1, "Copied 1 annotation(s) to clipboard, but gio trash failed\n"),
        )

    def test_unknown_command_prints_usage(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual(store.main(["bogus"]), 2)
        self.assertIn("Usage:", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()

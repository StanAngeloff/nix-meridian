import importlib.machinery
import importlib.util
import os

import pytest

# The script under test lives at ~/bin/difft-unified with no file extension, so
# spec_from_file_location() cannot infer a loader from the suffix (it only matches
# .py, .pyc, and .so) and returns None. Passing an explicit SourceFileLoader
# sidesteps the suffix lookup entirely.
_SCRIPT_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "home",
    "apps",
    "difft-unified",
    "difft-unified.py",
)
_LOADER = importlib.machinery.SourceFileLoader("difft_unified", _SCRIPT_PATH)
spec = importlib.util.spec_from_loader("difft_unified", _LOADER)
difft_unified = importlib.util.module_from_spec(spec)
spec.loader.exec_module(difft_unified)


def test_detect_status_created():
    assert difft_unified.detect_status("/dev/null", "/tmp/new") == "created"


def test_detect_status_deleted():
    assert difft_unified.detect_status("/tmp/old", "/dev/null") == "deleted"


def test_detect_status_changed():
    assert difft_unified.detect_status("/tmp/old", "/tmp/new") == "changed"


def test_detect_status_unstaged_modification():
    assert difft_unified.detect_status("/tmp/old", "path/to/file.ts") == "changed"


def test_is_binary_dev_null_is_not_binary():
    assert difft_unified.is_binary("/dev/null") is False


def test_is_binary_detects_null_byte(tmp_path):
    binary_file = tmp_path / "binary.dat"
    binary_file.write_bytes(b"\x00\x01\x02some binary content")
    assert difft_unified.is_binary(str(binary_file)) is True


def test_is_binary_text_file_is_not_binary(tmp_path):
    text_file = tmp_path / "text.txt"
    text_file.write_text("just some ordinary text\nwith multiple lines\n")
    assert difft_unified.is_binary(str(text_file)) is False


def test_render_binary_notice_changed():
    result = difft_unified.render_binary_notice(
        "path/file.bin", "path/file.bin", "changed"
    )
    assert result == (
        f"{difft_unified.YELLOW}Binary files a/path/file.bin and b/path/file.bin differ"
        f"{difft_unified.RESET}"
    )


def test_render_binary_notice_created():
    result = difft_unified.render_binary_notice(
        "path/file.bin", "path/file.bin", "created"
    )
    assert "/dev/null and b/path/file.bin differ" in result


def test_render_binary_notice_deleted():
    result = difft_unified.render_binary_notice(
        "path/file.bin", "path/file.bin", "deleted"
    )
    assert "a/path/file.bin and /dev/null differ" in result


def test_render_file_header_simple_changed():
    result = difft_unified.render_file_header(
        "path/file.nix",
        "path/file.nix",
        "aaaaaaa",
        "100644",
        "bbbbbbb",
        "100644",
        "changed",
    )
    assert "diff --git a/path/file.nix b/path/file.nix" in result
    assert "index aaaaaaa..bbbbbbb 100644" in result
    assert "--- a/path/file.nix" in result
    assert "+++ b/path/file.nix" in result
    assert "rename from" not in result


def test_render_file_header_rename_prints_git_supplied_block_verbatim():
    # Git precomputes the entire rename/copy extended header (similarity index, rename
    # from/to, and an index line with abbreviated hashes) as one pre-formatted block,
    # because only git's own diff engine can compute the similarity percentage.
    rename_description = (
        "similarity index 93%\n"
        "rename from old/path.nix\n"
        "rename to new/path.nix\n"
        "index 1ab4e9f..e006035 100644\n"
    )
    result = difft_unified.render_file_header(
        "old/path.nix",
        "new/path.nix",
        "1ab4e9f80e30a5dff2ac75f692fe0c0bcf972269",
        "100644",
        "e00603502e436c18196f815c322d5099321a7b64",
        "100644",
        "changed",
        rename_description,
    )
    assert "diff --git a/old/path.nix b/new/path.nix" in result
    assert "similarity index 93%" in result
    assert "rename from old/path.nix" in result
    assert "rename to new/path.nix" in result
    assert "index 1ab4e9f..e006035 100644" in result
    # The pre-formatted block already supplies its own (abbreviated) index line; the
    # full-hash index line the non-rename path constructs must not also appear.
    assert "1ab4e9f80e30a5dff2ac75f692fe0c0bcf972269" not in result
    assert "--- a/old/path.nix" in result
    assert "+++ b/new/path.nix" in result


def test_render_full_addition():
    lines = ["line one", "line two", "line three"]
    output = difft_unified.render_full_addition(lines)
    assert f"{difft_unified.MAGENTA}@@ -0,0 +1,3 @@{difft_unified.RESET}" in output
    assert f"{difft_unified.GREEN}+line one{difft_unified.RESET}" in output
    assert f"{difft_unified.GREEN}+line two{difft_unified.RESET}" in output
    assert f"{difft_unified.GREEN}+line three{difft_unified.RESET}" in output


def test_render_full_deletion():
    lines = ["old line one", "old line two"]
    output = difft_unified.render_full_deletion(lines)
    assert f"{difft_unified.MAGENTA}@@ -1,2 +0,0 @@{difft_unified.RESET}" in output
    assert f"{difft_unified.RED}-old line one{difft_unified.RESET}" in output
    assert f"{difft_unified.RED}-old line two{difft_unified.RESET}" in output


def test_render_full_addition_empty():
    assert difft_unified.render_full_addition([]) == ""


def test_render_full_deletion_empty():
    assert difft_unified.render_full_deletion([]) == ""


def test_validate_difft_json_valid_changed():
    data = {
        "aligned_lines": [[0, 0], [1, 1]],
        "chunks": [],
        "language": "Bash",
        "path": "test.sh",
        "status": "changed",
    }
    difft_unified.validate_difft_json(data, "test.sh")


def test_validate_difft_json_valid_created():
    data = {
        "language": "Nix",
        "path": "test.nix",
        "status": "created",
    }
    difft_unified.validate_difft_json(data, "test.nix")


def test_validate_difft_json_unknown_key():
    data = {
        "aligned_lines": [],
        "chunks": [],
        "language": "Bash",
        "path": "test.sh",
        "status": "changed",
        "surprise": True,
    }
    with pytest.raises(ValueError, match="unexpected key.*surprise.*test.sh"):
        difft_unified.validate_difft_json(data, "test.sh")


def test_validate_difft_json_unknown_status():
    data = {
        "language": "Bash",
        "path": "test.sh",
        "status": "renamed",
    }
    with pytest.raises(ValueError, match="unexpected status.*renamed.*test.sh"):
        difft_unified.validate_difft_json(data, "test.sh")


def test_validate_difft_json_missing_chunks_for_changed():
    data = {
        "aligned_lines": [[0, 0]],
        "language": "Bash",
        "path": "test.sh",
        "status": "changed",
    }
    with pytest.raises(ValueError, match="missing.*chunks.*test.sh"):
        difft_unified.validate_difft_json(data, "test.sh")


def test_build_chunk_lookup_modified_pair():
    chunks = [
        [
            {
                "lhs": {
                    "line_number": 10,
                    "changes": [
                        {
                            "start": 5,
                            "end": 10,
                            "content": "hello",
                            "highlight": "normal",
                        }
                    ],
                },
                "rhs": {
                    "line_number": 12,
                    "changes": [
                        {
                            "start": 5,
                            "end": 12,
                            "content": "goodbye",
                            "highlight": "normal",
                        }
                    ],
                },
            }
        ]
    ]
    lhs_changes, rhs_changes, modified_pairs = difft_unified.build_chunk_lookup(chunks)
    assert 10 in lhs_changes
    assert 12 in rhs_changes
    assert (10, 12) in modified_pairs


def test_build_chunk_lookup_addition_only():
    chunks = [
        [
            {
                "rhs": {
                    "line_number": 5,
                    "changes": [
                        {"start": 0, "end": 3, "content": "new", "highlight": "normal"}
                    ],
                }
            }
        ]
    ]
    lhs_changes, rhs_changes, modified_pairs = difft_unified.build_chunk_lookup(chunks)
    assert lhs_changes == {}
    assert 5 in rhs_changes
    assert modified_pairs == set()


def test_build_chunk_lookup_deletion_only():
    chunks = [
        [
            {
                "lhs": {
                    "line_number": 7,
                    "changes": [
                        {"start": 0, "end": 3, "content": "old", "highlight": "normal"}
                    ],
                }
            }
        ]
    ]
    lhs_changes, rhs_changes, modified_pairs = difft_unified.build_chunk_lookup(chunks)
    assert 7 in lhs_changes
    assert rhs_changes == {}
    assert modified_pairs == set()


def test_classify_lines_context():
    aligned = [[0, 0], [1, 1], [2, 2]]
    lhs_changes = {}
    rhs_changes = {}
    modified_pairs = set()
    result = difft_unified.classify_lines(
        aligned, lhs_changes, rhs_changes, modified_pairs
    )
    assert result == [("context", 0, 0), ("context", 1, 1), ("context", 2, 2)]


def test_classify_lines_addition():
    aligned = [[0, 0], [None, 1], [1, 2]]
    lhs_changes = {}
    rhs_changes = {1: []}  # 0-based, matches the added line's rhs_index
    modified_pairs = set()
    result = difft_unified.classify_lines(
        aligned, lhs_changes, rhs_changes, modified_pairs
    )
    assert result[1] == ("add", None, 1)


def test_classify_lines_deletion():
    aligned = [[0, 0], [1, None], [2, 1]]
    lhs_changes = {1: []}  # 0-based, matches the deleted line's lhs_index
    rhs_changes = {}
    modified_pairs = set()
    result = difft_unified.classify_lines(
        aligned, lhs_changes, rhs_changes, modified_pairs
    )
    assert result[1] == ("delete", 1, None)


def test_classify_lines_modification():
    aligned = [[0, 0], [1, 1], [2, 2]]
    lhs_changes = {1: []}  # 0-based
    rhs_changes = {1: []}
    modified_pairs = {(1, 1)}
    result = difft_unified.classify_lines(
        aligned, lhs_changes, rhs_changes, modified_pairs
    )
    assert result[1] == ("modify", 1, 1)
    assert result[0] == ("context", 0, 0)
    assert result[2] == ("context", 2, 2)


def test_demote_identical_modifications_downgrades_identical_text():
    # Regression test: difftastic can mark a line "modified" (for example, because it sits
    # inside a Nix multi-line string that was restructured elsewhere) even though the line's
    # own text is byte-for-byte identical on both sides. Such a pair must render as context.
    operations = [("context", 0, 0), ("modify", 1, 1), ("context", 2, 2)]
    lhs_lines = ["same line one", "identical text", "same line three"]
    rhs_lines = ["same line one", "identical text", "same line three"]
    result = difft_unified.demote_identical_modifications(
        operations, lhs_lines, rhs_lines
    )
    assert result == [("context", 0, 0), ("context", 1, 1), ("context", 2, 2)]


def test_demote_identical_modifications_keeps_real_modifications():
    operations = [("modify", 0, 0)]
    lhs_lines = ["old text"]
    rhs_lines = ["new text"]
    result = difft_unified.demote_identical_modifications(
        operations, lhs_lines, rhs_lines
    )
    assert result == [("modify", 0, 0)]


def test_demote_identical_modifications_leaves_add_and_delete_untouched():
    operations = [("add", None, 0), ("delete", 0, None)]
    lhs_lines = ["deleted line"]
    rhs_lines = ["added line"]
    result = difft_unified.demote_identical_modifications(
        operations, lhs_lines, rhs_lines
    )
    assert result == operations


def test_classify_lines_format_add_when_no_chunks():
    aligned = [[0, 0], [None, 1], [None, 2], [1, 3]]
    lhs_changes = {}
    rhs_changes = {}
    modified_pairs = set()
    result = difft_unified.classify_lines(
        aligned, lhs_changes, rhs_changes, modified_pairs
    )
    assert result[1] == ("format_add", None, 1)
    assert result[2] == ("format_add", None, 2)


def test_classify_lines_format_del_when_no_chunks():
    aligned = [[0, 0], [1, None], [2, None], [3, 1]]
    lhs_changes = {}
    rhs_changes = {}
    modified_pairs = set()
    result = difft_unified.classify_lines(
        aligned, lhs_changes, rhs_changes, modified_pairs
    )
    assert result[1] == ("format_del", 1, None)
    assert result[2] == ("format_del", 2, None)


def test_compute_hunks_format_operations_are_not_changes():
    operations = [
        ("context", 0, 0),
        ("format_add", None, 1),
        ("format_add", None, 2),
        ("context", 1, 3),
    ]
    hunks = difft_unified.compute_hunks(operations, context_lines=3)
    assert hunks == []


def test_compute_hunks_single_change():
    operations = [
        ("context", 0, 0),
        ("context", 1, 1),
        ("context", 2, 2),
        ("context", 3, 3),
        ("context", 4, 4),
        ("add", None, 5),
        ("context", 5, 6),
        ("context", 6, 7),
        ("context", 7, 8),
        ("context", 8, 9),
    ]
    hunks = difft_unified.compute_hunks(operations, context_lines=3)
    assert len(hunks) == 1
    start, end = hunks[0]
    assert start == 2  # 3 lines before the change at index 5
    assert end == 9  # 3 lines after the change at index 5


def test_compute_hunks_merged():
    operations = [
        ("context", 0, 0),
        ("add", None, 1),
        ("context", 1, 2),
        ("context", 2, 3),
        ("context", 3, 4),
        ("context", 4, 5),
        ("delete", 5, None),
        ("context", 6, 6),
    ]
    hunks = difft_unified.compute_hunks(operations, context_lines=3)
    # Gap between changes is 4 context lines (indices 2-5), which is <= 6, so they merge
    assert len(hunks) == 1


def test_compute_hunks_separate():
    operations = (
        [("context", i, i) for i in range(10)]
        + [("add", None, 10)]
        + [("context", i, i + 1) for i in range(10, 25)]
        + [("delete", 25, None)]
        + [("context", i, i - 1) for i in range(26, 30)]
    )
    hunks = difft_unified.compute_hunks(operations, context_lines=3)
    # Gap between changes is 14 context lines, well over 6 — separate hunks
    assert len(hunks) == 2


def test_compute_hunks_no_changes():
    operations = [("context", i, i) for i in range(10)]
    hunks = difft_unified.compute_hunks(operations, context_lines=3)
    assert hunks == []


def test_render_line_with_emphasis_no_changes():
    result = difft_unified.render_line_with_emphasis(
        "hello world", [], difft_unified.RED, difft_unified.EMPHASIS_DEL
    )
    assert result == f"{difft_unified.RED}hello world{difft_unified.RESET}"


def test_render_line_with_emphasis_with_changes():
    changes = [{"start": 6, "end": 11, "content": "world", "highlight": "normal"}]
    result = difft_unified.render_line_with_emphasis(
        "hello world", changes, difft_unified.GREEN, difft_unified.EMPHASIS_ADD
    )
    assert difft_unified.EMPHASIS_ADD in result
    assert difft_unified.GREEN in result
    emphasis_start = result.index(difft_unified.EMPHASIS_ADD)
    assert emphasis_start > result.index("h")


def test_render_line_with_emphasis_multiple_spans():
    changes = [
        {"start": 0, "end": 3, "content": "aaa", "highlight": "normal"},
        {"start": 5, "end": 8, "content": "bbb", "highlight": "normal"},
    ]
    result = difft_unified.render_line_with_emphasis(
        "aaa--bbb--ccc", changes, difft_unified.RED, difft_unified.EMPHASIS_DEL
    )
    assert result.count(difft_unified.EMPHASIS_DEL) == 2


def test_render_hunk_header():
    operations = [
        ("context", 4, 4),
        ("delete", 5, None),
        ("add", None, 5),
        ("context", 6, 6),
    ]
    result = difft_unified.render_hunk_header(operations)
    # lhs lines: 5, 6, 7 (1-based from indices 4, 5, 6) -> start=5, count=3
    # rhs lines: 5, 6, 7 (1-based from indices 4, 5, 6) -> start=5, count=3
    assert f"{difft_unified.MAGENTA}@@ -5,3 +5,3 @@{difft_unified.RESET}" == result


def test_render_hunk_header_pure_addition():
    operations = [
        ("context", 4, 4),
        ("add", None, 5),
        ("add", None, 6),
        ("context", 5, 7),
    ]
    result = difft_unified.render_hunk_header(operations)
    # lhs: indices 4, 5 -> lines 5, 6 -> start=5, count=2
    # rhs: indices 4, 5, 6, 7 -> lines 5, 6, 7, 8 -> start=5, count=4
    assert f"{difft_unified.MAGENTA}@@ -5,2 +5,4 @@{difft_unified.RESET}" == result


def test_strip_alignment_sentinel_removes_trailing_entry():
    # difft's JSON always appends one trailing (lhs_line_count, rhs_line_count)
    # pair to aligned_lines representing an end-of-file alignment anchor, which
    # is one past the last valid 0-based index on both sides simultaneously.
    aligned_lines = [[0, 0], [1, 1], [2, 2], [None, 3], [3, 4]]
    result = difft_unified.strip_alignment_sentinel(
        aligned_lines, lhs_line_count=3, rhs_line_count=4
    )
    assert result == [[0, 0], [1, 1], [2, 2], [None, 3]]


def test_strip_alignment_sentinel_empty_input():
    result = difft_unified.strip_alignment_sentinel(
        [], lhs_line_count=0, rhs_line_count=0
    )
    assert result == []


def test_strip_alignment_sentinel_raises_on_unexpected_last_entry():
    aligned_lines = [[0, 0], [1, 1]]
    with pytest.raises(ValueError, match="end-of-file sentinel"):
        difft_unified.strip_alignment_sentinel(
            aligned_lines, lhs_line_count=5, rhs_line_count=5
        )


def test_render_changed_file_strips_end_of_file_sentinel_no_crash():
    # Regression test for the reported crash: real difft output on a 3-line ->
    # 4-line file (one appended line) ends aligned_lines with a [3, 4] sentinel
    # pair that is out of range for both 3-line lhs_lines and 4-line rhs_lines.
    # Reproduced empirically against real difft 0.70.0 JSON output before this
    # fix (see task-5-report.md for the full investigation).
    lhs_lines = ["line1", "line2", "line3"]
    rhs_lines = ["line1", "line2", "line3", "line4"]
    data = {
        "aligned_lines": [[0, 0], [1, 1], [2, 2], [None, 3], [3, 4]],
        "chunks": [
            [
                {
                    "rhs": {
                        "line_number": 3,
                        "changes": [
                            {
                                "start": 0,
                                "end": 5,
                                "content": "line4",
                                "highlight": "normal",
                            }
                        ],
                    }
                }
            ]
        ],
        "language": "Text",
        "path": "sample.txt",
        "status": "changed",
    }
    result = difft_unified.render_changed_file("sample.txt", lhs_lines, rhs_lines, data)
    assert f"{difft_unified.GREEN}+line4{difft_unified.RESET}" in result
    assert "line4" in result


def test_parse_arguments_standard_seven_parameter_form():
    argv = [
        "difft-unified",
        "path/file.nix",
        "/tmp/old",
        "aaaaaaa",
        "100644",
        "/tmp/new",
        "bbbbbbb",
        "100644",
    ]
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
    ) = difft_unified.parse_arguments(argv)
    assert old_path == "path/file.nix"
    assert new_path == "path/file.nix"
    assert old_file == "/tmp/old"
    assert old_hex == "aaaaaaa"
    assert old_mode == "100644"
    assert new_file == "/tmp/new"
    assert new_hex == "bbbbbbb"
    assert new_mode == "100644"
    assert rename_description is None


def test_parse_arguments_rename_nine_parameter_form():
    # Regression test for the reported crash: git's diff.renames invokes the external diff
    # driver with 9 positional parameters (not 7) for a rename or copy with content changes —
    # the leading path becomes the source path, and two parameters are appended: the
    # destination path and a pre-formatted rename/copy extended-header block. Before this fix,
    # parse_arguments (formerly inline in main()) rejected anything but exactly 7 parameters,
    # which aborted the entire `git diff` invocation, not just the renamed file.
    argv = [
        "difft-unified",
        "old/path.nix",
        "/tmp/old",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "100644",
        "/tmp/new",
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "100644",
        "new/path.nix",
        "similarity index 93%\nrename from old/path.nix\nrename to new/path.nix\n",
    ]
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
    ) = difft_unified.parse_arguments(argv)
    assert old_path == "old/path.nix"
    assert new_path == "new/path.nix"
    assert (
        rename_description
        == "similarity index 93%\nrename from old/path.nix\nrename to new/path.nix\n"
    )


def test_parse_arguments_invalid_argument_count_raises():
    with pytest.raises(ValueError, match="Usage:"):
        difft_unified.parse_arguments(["difft-unified", "only-one-arg"])

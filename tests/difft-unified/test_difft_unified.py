import importlib.machinery
import importlib.util
import os
import sys

import pytest

# The script under test lives at ~/bin/difft-unified with no file extension, so
# spec_from_file_location() cannot infer a loader from the suffix (it only matches
# .py, .pyc, and .so) and returns None. Passing an explicit SourceFileLoader
# sidesteps the suffix lookup entirely.
_SCRIPT_PATH = os.path.expanduser("~/bin/difft-unified")
_LOADER = importlib.machinery.SourceFileLoader("difft_unified", _SCRIPT_PATH)
spec = importlib.util.spec_from_loader("difft_unified", _LOADER)
difft_unified = importlib.util.module_from_spec(spec)
spec.loader.exec_module(difft_unified)


def test_detect_status_created():
    assert difft_unified.detect_status("0000000", "/dev/null", "c5be89d", "/tmp/new") == "created"


def test_detect_status_deleted():
    assert difft_unified.detect_status("05839b0", "/tmp/old", "0000000", "/dev/null") == "deleted"


def test_detect_status_changed():
    assert difft_unified.detect_status("05839b0", "/tmp/old", "23c608e", "/tmp/new") == "changed"


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
    chunks = [[
        {
            "lhs": {"line_number": 10, "changes": [{"start": 5, "end": 10, "content": "hello", "highlight": "normal"}]},
            "rhs": {"line_number": 12, "changes": [{"start": 5, "end": 12, "content": "goodbye", "highlight": "normal"}]},
        }
    ]]
    lhs_changes, rhs_changes, modified_pairs = difft_unified.build_chunk_lookup(chunks)
    assert 10 in lhs_changes
    assert 12 in rhs_changes
    assert (10, 12) in modified_pairs


def test_build_chunk_lookup_addition_only():
    chunks = [[
        {"rhs": {"line_number": 5, "changes": [{"start": 0, "end": 3, "content": "new", "highlight": "normal"}]}}
    ]]
    lhs_changes, rhs_changes, modified_pairs = difft_unified.build_chunk_lookup(chunks)
    assert lhs_changes == {}
    assert 5 in rhs_changes
    assert modified_pairs == set()


def test_build_chunk_lookup_deletion_only():
    chunks = [[
        {"lhs": {"line_number": 7, "changes": [{"start": 0, "end": 3, "content": "old", "highlight": "normal"}]}}
    ]]
    lhs_changes, rhs_changes, modified_pairs = difft_unified.build_chunk_lookup(chunks)
    assert 7 in lhs_changes
    assert rhs_changes == {}
    assert modified_pairs == set()

import importlib.machinery
import importlib.util
import os

_SCRIPT_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "home",
    "apps",
    "difft-unified",
    "pager.py",
)
_LOADER = importlib.machinery.SourceFileLoader("pager", _SCRIPT_PATH)
spec = importlib.util.spec_from_loader("pager", _LOADER)
pager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pager)


def test_detect_moved_blocks_cross_file():
    plain_lines = [
        "diff --git a/old.py b/old.py",
        "--- a/old.py",
        "+++ b/old.py",
        "@@ -1,6 +1,2 @@",
        " keep",
        "-def moved_function():",
        '-    value = compute_something()',
        '-    return value',
        " keep",
        "diff --git a/new.py b/new.py",
        "--- a/new.py",
        "+++ b/new.py",
        "@@ -1,2 +1,6 @@",
        " keep",
        "+def moved_function():",
        '+    value = compute_something()',
        '+    return value',
        " keep",
    ]
    moved = pager.detect_moved_blocks(plain_lines)
    assert moved[5] == "moved_del"
    assert moved[6] == "moved_del"
    assert moved[7] == "moved_del"
    assert moved[14] == "moved_add"
    assert moved[15] == "moved_add"
    assert moved[16] == "moved_add"
    assert 4 not in moved
    assert 8 not in moved


def test_detect_moved_blocks_rejects_short_blocks():
    plain_lines = [
        "diff --git a/a.py b/a.py",
        "@@ -1,2 +1,1 @@",
        "-}",
        " x",
        "diff --git a/b.py b/b.py",
        "@@ -1,1 +1,2 @@",
        " x",
        "+}",
    ]
    moved = pager.detect_moved_blocks(plain_lines)
    assert moved == {}


def test_detect_moved_blocks_no_match_different_content():
    plain_lines = [
        "diff --git a/a.py b/a.py",
        "@@ -1,2 +1,1 @@",
        "-old_function_name_that_is_very_long()",
        " x",
        "diff --git a/b.py b/b.py",
        "@@ -1,1 +1,2 @@",
        " x",
        "+new_function_name_that_is_very_long()",
    ]
    moved = pager.detect_moved_blocks(plain_lines)
    assert moved == {}


def test_detect_moved_blocks_within_same_file():
    plain_lines = [
        "diff --git a/file.py b/file.py",
        "@@ -1,10 +1,10 @@",
        "+def moved_function_with_long_name():",
        '+    value = compute_something_important()',
        '+    return value',
        " ",
        " def other():",
        "     pass",
        " ",
        "-def moved_function_with_long_name():",
        '-    value = compute_something_important()',
        '-    return value',
    ]
    moved = pager.detect_moved_blocks(plain_lines)
    assert moved[2] == "moved_add"
    assert moved[3] == "moved_add"
    assert moved[4] == "moved_add"
    assert moved[9] == "moved_del"
    assert moved[10] == "moved_del"
    assert moved[11] == "moved_del"


def test_detect_moved_blocks_rejects_two_line_block():
    plain_lines = [
        "diff --git a/a.py b/a.py",
        "@@ -1,3 +1,1 @@",
        "-def some_function_with_long_name():",
        '-    return compute_value_here()',
        " x",
        "diff --git a/b.py b/b.py",
        "@@ -1,1 +1,3 @@",
        " x",
        "+def some_function_with_long_name():",
        '+    return compute_value_here()',
    ]
    moved = pager.detect_moved_blocks(plain_lines)
    assert moved == {}


def test_detect_moved_blocks_context_breaks_block_below_minimum():
    plain_lines = [
        "diff --git a/a.py b/a.py",
        "@@ -1,4 +1,1 @@",
        "-def function_with_very_long_name():",
        " context_breaks_the_block",
        '-    return "some_long_value_here"',
        " x",
        "diff --git a/b.py b/b.py",
        "@@ -1,1 +1,4 @@",
        " x",
        "+def function_with_very_long_name():",
        " context_breaks_the_block",
        '+    return "some_long_value_here"',
    ]
    moved = pager.detect_moved_blocks(plain_lines)
    assert moved == {}

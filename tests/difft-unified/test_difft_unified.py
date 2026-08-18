import importlib.machinery
import importlib.util
import os
import sys

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

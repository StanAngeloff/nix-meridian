import contextlib
import fcntl
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import helper

ABSENT = "0" * 40


def git(repository_path, *arguments):
    result = subprocess.run(
        ["git", "-C", str(repository_path), *arguments],
        check=True,
        capture_output=True,
        text=True,
        env={**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"},
    )
    return result.stdout.strip()


def magick(*arguments):
    subprocess.run(["magick", *arguments], check=True, capture_output=True)


def pixel(raw_path, width, x, y):
    data = Path(raw_path).read_bytes()
    offset = (y * width + x) * 4
    return tuple(data[offset : offset + 4])


class HelperTest(unittest.TestCase):
    def setUp(self):
        temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(temporary_directory.cleanup)
        root_path = Path(temporary_directory.name)
        self.repository_path = root_path / "repository"
        self.cache_path = root_path / "runtime" / helper.CACHE_PARENT_NAME / "4242"
        git(root_path, "init", "-q", str(self.repository_path))
        git(self.repository_path, "config", "user.email", "test@example.com")
        git(self.repository_path, "config", "user.name", "Test")
        previous_directory = os.getcwd()
        os.chdir(self.repository_path)
        self.addCleanup(os.chdir, previous_directory)

    def commit(self, *paths):
        git(self.repository_path, "add", *paths)
        git(self.repository_path, "commit", "-q", "-m", "commit")

    def run_helper(self, *arguments):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exit_code = helper.main(list(arguments))
        facts = {}
        for line in output.getvalue().splitlines():
            name, _, value = line.partition(" ")
            facts[name] = value
        return exit_code, facts

    def prepare(self, path, old, new, opacity=50):
        return self.run_helper(
            "prepare",
            "--cache",
            str(self.cache_path),
            "--path",
            path,
            "--old",
            old,
            "--new",
            new,
            "--opacity",
            str(opacity),
        )

    def test_same_size_change_reports_the_changed_share_and_offers_a_mask(self):
        magick("-size", "100x100", "xc:white", "a.png")
        self.commit("a.png")
        magick("a.png", "-fill", "black", "-draw", "rectangle 0,0 9,9", "a.png")
        self.commit("a.png")

        exit_code, facts = self.prepare(
            "a.png",
            git(self.repository_path, "rev-parse", "HEAD~1:a.png"),
            git(self.repository_path, "rev-parse", "HEAD:a.png"),
        )

        self.assertEqual(exit_code, 0)
        self.assertIn("mask", facts)
        self.assertEqual(facts["note"], "1.00% of pixels changed")
        width, height, raw_path = facts["new"].split(" ", 2)
        self.assertEqual((width, height), ("100", "100"))
        self.assertEqual(Path(raw_path).stat().st_size, 100 * 100 * 4)

    def test_the_worktree_side_is_read_from_disk(self):
        magick("-size", "20x20", "xc:white", "a.png")
        self.commit("a.png")
        magick("-size", "20x20", "xc:black", "a.png")

        exit_code, facts = self.prepare(
            "a.png",
            git(self.repository_path, "rev-parse", ":a.png"),
            "worktree",
            opacity=0,
        )

        self.assertEqual(exit_code, 0)
        self.assertEqual(facts["note"], "100.00% of pixels changed")
        self.assertEqual(pixel(facts["new"].split(" ", 2)[2], 20, 5, 5), (0, 0, 0, 255))

    def test_git_lfs_pointers_are_smudged_into_the_image(self):
        git(self.repository_path, "lfs", "install", "--local")
        git(self.repository_path, "lfs", "track", "*.png")
        magick("-size", "30x10", "xc:white", "a.png")
        self.commit(".gitattributes", "a.png")
        self.assertIn(
            "git-lfs", git(self.repository_path, "cat-file", "blob", "HEAD:a.png")
        )

        exit_code, facts = self.prepare(
            "a.png", ABSENT, git(self.repository_path, "rev-parse", "HEAD:a.png")
        )

        self.assertEqual(exit_code, 0)
        self.assertEqual(facts["note"], "new image, 30x10")

    def test_a_size_change_shows_both_sides_without_a_mask(self):
        magick("-size", "20x20", "xc:white", "a.png")
        self.commit("a.png")
        magick("-size", "30x20", "xc:white", "a.png")

        exit_code, facts = self.prepare(
            "a.png", git(self.repository_path, "rev-parse", ":a.png"), "worktree"
        )

        self.assertEqual(exit_code, 0)
        self.assertNotIn("mask", facts)
        self.assertIn("old", facts)
        self.assertIn("new", facts)
        self.assertEqual(facts["note"], "size changed: 20x20 → 30x20")

    def test_an_untracked_image_has_only_a_new_side(self):
        magick("-size", "8x8", "xc:white", "a.png")

        exit_code, facts = self.prepare("a.png", ABSENT, "worktree")

        self.assertEqual(exit_code, 0)
        self.assertNotIn("old", facts)
        self.assertEqual(facts["note"], "new image, 8x8")

    def test_a_deleted_image_has_only_an_old_side(self):
        magick("-size", "8x8", "xc:white", "a.png")
        self.commit("a.png")
        os.remove("a.png")

        exit_code, facts = self.prepare(
            "a.png", git(self.repository_path, "rev-parse", ":a.png"), "worktree"
        )

        self.assertEqual(exit_code, 0)
        self.assertNotIn("new", facts)
        self.assertEqual(facts["note"], "deleted image, 8x8")

    def test_large_images_shrink_to_the_panel_limit(self):
        magick("-size", "3200x800", "xc:white", "a.png")

        _, facts = self.prepare("a.png", ABSENT, "worktree")

        self.assertEqual(
            facts["new"].split(" ")[:2],
            [str(helper.PANEL_LIMIT), str(helper.PANEL_LIMIT // 4)],
        )

    def test_a_binary_that_is_not_an_image_is_refused(self):
        Path("a.bin").write_bytes(bytes(range(256)) * 8)

        exit_code, facts = self.prepare("a.bin", ABSENT, "worktree")

        self.assertEqual(exit_code, 1)
        self.assertEqual(facts["skip"], "not an image")

    def test_oversized_sources_are_refused(self):
        magick("-size", "8x8", "xc:white", "a.png")

        with mock.patch.object(helper, "SOURCE_LIMIT", 10):
            exit_code, facts = self.prepare("a.png", ABSENT, "worktree")

        self.assertEqual(exit_code, 1)
        self.assertTrue(facts["error"].startswith("larger than"))

    def test_tint_paints_changed_pixels_and_leaves_the_rest(self):
        magick("-size", "10x10", "xc:white", "a.png")
        self.commit("a.png")
        magick("a.png", "-fill", "black", "-draw", "point 2,2", "a.png")
        self.prepare(
            "a.png", git(self.repository_path, "rev-parse", ":a.png"), "worktree"
        )

        exit_code, facts = self.run_helper(
            "tint", "--cache", str(self.cache_path), "--opacity", "100"
        )

        self.assertEqual(exit_code, 0)
        raw_path = facts["new"].split(" ", 2)[2]
        self.assertEqual(pixel(raw_path, 10, 2, 2), (255, 0, 255, 255))
        self.assertEqual(pixel(raw_path, 10, 7, 7), (255, 255, 255, 255))

    def test_tint_is_refused_without_a_mask(self):
        magick("-size", "8x8", "xc:white", "a.png")
        self.prepare("a.png", ABSENT, "worktree")

        exit_code, facts = self.run_helper(
            "tint", "--cache", str(self.cache_path), "--opacity", "40"
        )

        self.assertEqual(exit_code, 1)
        self.assertEqual(facts["error"], "no highlight for this diff")

    def test_cleanup_removes_the_cache(self):
        magick("-size", "8x8", "xc:white", "a.png")
        self.prepare("a.png", ABSENT, "worktree")

        self.cache_path.with_name("4242.lock").touch()

        self.run_helper("cleanup", "--cache", str(self.cache_path))

        self.assertFalse(self.cache_path.exists())
        self.assertFalse(self.cache_path.with_name("4242.lock").exists())

    def test_prepare_sweeps_the_caches_of_tig_processes_that_are_gone(self):
        abandoned_path = self.cache_path.with_name("999")
        abandoned_path.mkdir(parents=True)
        abandoned_path.with_name("999.lock").touch()
        unlocked_path = self.cache_path.with_name("998")
        unlocked_path.mkdir()
        magick("-size", "8x8", "xc:white", "a.png")

        self.prepare("a.png", ABSENT, "worktree")

        self.assertFalse(abandoned_path.exists())
        self.assertFalse(abandoned_path.with_name("999.lock").exists())
        self.assertFalse(unlocked_path.exists())
        self.assertTrue(self.cache_path.exists())

    def test_prepare_keeps_the_caches_of_running_tig_processes(self):
        running_path = self.cache_path.with_name("997")
        running_path.mkdir(parents=True)
        with open(running_path.with_name("997.lock"), "w") as lock_file:
            fcntl.flock(lock_file, fcntl.LOCK_EX)
            magick("-size", "8x8", "xc:white", "a.png")

            self.prepare("a.png", ABSENT, "worktree")

            self.assertTrue(running_path.exists())

    def test_a_cache_directory_not_named_by_tig_is_refused(self):
        exit_code, facts = self.run_helper(
            "cleanup", "--cache", str(self.repository_path)
        )

        self.assertEqual(exit_code, 1)
        self.assertTrue(facts["error"].startswith("unexpected cache directory"))
        self.assertTrue(self.repository_path.exists())


if __name__ == "__main__":
    unittest.main()

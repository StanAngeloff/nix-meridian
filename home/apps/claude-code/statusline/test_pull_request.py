import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import pull_request

# The real clock, not a fixed instant: taking the lock and backing off after a failure stamp files with it.
NOW = int(time.time())
REPOSITORY_URL = "https://github.com/owner/repo"
FOUND = {"number": 17212, "url": "https://github.com/owner/repo/pull/17212"}

# Stand-ins for gh, each recording its arguments and working directory before answering. Python rather
# than shell, so the shebang resolves inside the Nix build sandbox too.
FAKE_GH_SOURCES = {
    "found": 'print(json.dumps({"number": 17212, "url": "https://github.com/owner/repo/pull/17212", "state": "OPEN"}))',
    "absent": 'sys.stderr.write("no pull requests found for branch \\"trunk\\"\\n"); sys.exit(1)',
    "offline": 'sys.stderr.write("error connecting to api.github.com\\n"); sys.exit(1)',
}


def install_fake_gh(bin_directory, behaviour):
    script_path = Path(bin_directory) / "gh"
    script_path.write_text(
        f"#!{sys.executable}\n"
        "import json, os, sys\n"
        "with open(os.environ['FAKE_GH_LOG'], 'w') as log:\n"
        "    json.dump({'arguments': sys.argv[1:], 'directory': os.getcwd()}, log)\n"
        f"{FAKE_GH_SOURCES[behaviour]}\n"
    )
    script_path.chmod(0o755)


class FakeGh:
    """A temporary PATH holding only a fake gh, plus the log it writes its invocation to."""

    def __init__(self, behaviour):
        self.behaviour = behaviour

    def __enter__(self):
        self._temporary = tempfile.TemporaryDirectory()
        root = Path(self._temporary.name)
        (root / "bin").mkdir()
        if self.behaviour is not None:
            install_fake_gh(root / "bin", self.behaviour)
        self.log_path = root / "invocation.json"
        self._patch = mock.patch.dict(
            os.environ, {"PATH": str(root / "bin"), "FAKE_GH_LOG": str(self.log_path)}
        )
        self._patch.start()
        return self

    def invocation(self):
        return json.loads(self.log_path.read_text())

    def __exit__(self, *exception):
        self._patch.stop()
        self._temporary.cleanup()


class Lookup(unittest.TestCase):
    def test_returns_the_pull_request_number_and_url(self):
        with tempfile.TemporaryDirectory() as directory, FakeGh("found"):
            self.assertEqual(pull_request.lookup(directory, "feature"), FOUND)

    def test_names_the_branch_after_a_double_dash_and_runs_in_the_directory(self):
        with tempfile.TemporaryDirectory() as directory, FakeGh("found") as gh:
            pull_request.lookup(directory, "--web")
            invocation = gh.invocation()
        self.assertEqual(invocation["arguments"][-2:], ["--", "--web"])
        self.assertEqual(
            os.path.realpath(invocation["directory"]), os.path.realpath(directory)
        )

    def test_is_none_for_a_branch_without_a_pull_request(self):
        with tempfile.TemporaryDirectory() as directory, FakeGh("absent"):
            self.assertIsNone(pull_request.lookup(directory, "trunk"))

    def test_fails_when_gh_cannot_answer(self):
        with tempfile.TemporaryDirectory() as directory, FakeGh("offline"):
            self.assertIs(
                pull_request.lookup(directory, "feature"), pull_request.LOOKUP_FAILED
            )

    def test_fails_when_gh_is_missing(self):
        with tempfile.TemporaryDirectory() as directory, FakeGh(None):
            self.assertIs(
                pull_request.lookup(directory, "feature"), pull_request.LOOKUP_FAILED
            )


class Read(unittest.TestCase):
    def test_a_missing_file_is_empty_and_due(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(
                pull_request.read(Path(directory) / "absent.json", NOW), (None, True)
            )

    def test_a_fresh_answer_is_not_due(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "answer.json"
            pull_request.write(path, FOUND)
            os.utime(path, (NOW - 10, NOW - 10))
            self.assertEqual(pull_request.read(path, NOW), (FOUND, False))

    def test_an_old_answer_is_still_shown_but_due(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "answer.json"
            pull_request.write(path, FOUND)
            age = pull_request.CACHE_SECONDS
            os.utime(path, (NOW - age, NOW - age))
            self.assertEqual(pull_request.read(path, NOW), (FOUND, True))

    def test_a_cached_absence_is_not_due(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "answer.json"
            pull_request.write(path, None)
            os.utime(path, (NOW, NOW))
            self.assertEqual(pull_request.read(path, NOW), (None, False))

    def test_a_corrupt_file_is_empty_and_due(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "answer.json"
            path.write_text("{not json")
            self.assertEqual(pull_request.read(path, NOW), (None, True))


class Refresh(unittest.TestCase):
    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self._temporary.cleanup)
        self.directory = self._temporary.name
        self.cache_directory = Path(self._temporary.name) / "cache"
        self.path = pull_request.cache_path(
            self.cache_directory, REPOSITORY_URL, "feature"
        )
        self.lock_path = self.path.with_name(f"{self.path.name}.lock")

    def refresh(self):
        pull_request.refresh(
            self.directory, REPOSITORY_URL, "feature", self.cache_directory
        )

    def stored(self):
        return json.loads(self.path.read_text())

    def test_stores_the_pull_request(self):
        with FakeGh("found"):
            self.refresh()
        self.assertEqual(self.stored(), FOUND)

    def test_stores_an_absence(self):
        with FakeGh("absent"):
            self.refresh()
        self.assertIsNone(self.stored())

    def test_a_failure_keeps_the_last_answer_and_waits_a_full_period(self):
        pull_request.write(self.path, FOUND)
        os.utime(self.path, (NOW - 3600, NOW - 3600))
        with FakeGh("offline"):
            self.refresh()
        self.assertEqual(self.stored(), FOUND)
        self.assertGreater(self.path.stat().st_mtime, NOW - 3600)

    def test_a_failure_with_nothing_cached_stores_an_absence(self):
        with FakeGh("offline"):
            self.refresh()
        self.assertIsNone(self.stored())

    def test_releases_the_lock_and_leaves_no_scratch_file(self):
        self.cache_directory.mkdir()
        self.lock_path.touch()
        with FakeGh("found"):
            self.refresh()
        self.assertEqual(os.listdir(self.cache_directory), [self.path.name])


class Current(unittest.TestCase):
    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self._temporary.cleanup)
        self.cache_directory = Path(self._temporary.name) / "cache"
        self.path = pull_request.cache_path(
            self.cache_directory, REPOSITORY_URL, "feature"
        )
        self.lock_path = self.path.with_name(f"{self.path.name}.lock")
        self.started = []

    def current(self, repository_url=REPOSITORY_URL, branch="feature"):
        return pull_request.current(
            "/repository",
            repository_url,
            branch,
            self.cache_directory,
            NOW,
            start_refresh=lambda *arguments: self.started.append(arguments),
        )

    def cache(self, answer, age_seconds):
        pull_request.write(self.path, answer)
        os.utime(self.path, (NOW - age_seconds, NOW - age_seconds))

    def test_shows_a_fresh_answer_without_asking_again(self):
        self.cache(FOUND, 10)
        self.assertEqual(self.current(), FOUND)
        self.assertEqual(self.started, [])

    def test_shows_an_old_answer_and_starts_one_refresh(self):
        self.cache(FOUND, pull_request.CACHE_SECONDS)
        self.assertEqual(self.current(), FOUND)
        self.assertEqual(self.started, [("/repository", REPOSITORY_URL, "feature")])

    def test_shows_nothing_for_a_branch_never_asked_about_and_starts_a_refresh(self):
        self.assertIsNone(self.current())
        self.assertEqual(len(self.started), 1)

    def test_a_running_refresh_holds_off_the_next_render(self):
        self.current()
        self.current()
        self.assertEqual(len(self.started), 1)

    def test_a_dead_refresh_does_not_hold_off_renders_forever(self):
        self.current()
        stale = NOW - pull_request.LOCK_STALE_SECONDS
        os.utime(self.lock_path, (stale, stale))
        self.current()
        self.assertEqual(len(self.started), 2)

    def test_releases_the_lock_when_the_refresh_cannot_start(self):
        def unstartable(*arguments):
            raise OSError("no python")

        pull_request.current(
            "/repository",
            REPOSITORY_URL,
            "feature",
            self.cache_directory,
            NOW,
            start_refresh=unstartable,
        )
        self.assertFalse(self.lock_path.exists())

    def test_asks_nothing_outside_a_github_repository(self):
        self.assertIsNone(self.current(repository_url=""))
        self.assertIsNone(self.current(branch=""))
        self.assertEqual(self.started, [])

    def test_keys_the_answer_on_repository_and_branch(self):
        self.assertNotEqual(
            pull_request.cache_path(self.cache_directory, REPOSITORY_URL, "a"),
            pull_request.cache_path(self.cache_directory, REPOSITORY_URL, "b"),
        )
        self.assertNotEqual(
            pull_request.cache_path(self.cache_directory, REPOSITORY_URL, "a"),
            pull_request.cache_path(self.cache_directory, f"{REPOSITORY_URL}2", "a"),
        )


class CacheDirectoryFrom(unittest.TestCase):
    def test_follows_xdg_cache_home(self):
        self.assertEqual(
            pull_request.cache_directory_from({"XDG_CACHE_HOME": "/cache"}),
            Path("/cache/claude-code-statusline"),
        )

    def test_falls_back_to_the_home_cache(self):
        self.assertEqual(
            pull_request.cache_directory_from({}),
            Path.home() / ".cache" / "claude-code-statusline",
        )

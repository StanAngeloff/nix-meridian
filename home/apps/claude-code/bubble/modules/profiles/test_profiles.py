"""Behavior tests for claude-profiles (profiles.sh beside this file), run by its build after shellcheck.

Each test arranges a ~/.claude in a temporary HOME and sources the built command, which runs nothing when sourced.
Shell functions stand in for the process and systemd queries, and then the test calls _profile_main. The tokens are
fake, so nothing here can reach an account.
"""

import json
import os
import pathlib
import subprocess
import tempfile
import unittest

COMMAND_FILE = os.environ["PROFILES_COMMAND"]

# No Claude Code process, no running session, and any process counts as bubbled: the quiet machine most tests want.
QUIET_MACHINE = """
_profile_claude_process_ids() { :; }
_profile_process_is_bubbled() { return 0; }
_profile_session_profiles() { :; }
"""

WORK_TOKENS = {
    "accessToken": "fake-work-access",
    "refreshToken": "fake-work-refresh",
    "expiresAt": 1,
    "subscriptionType": "team",
}
STALE_WORK_TOKENS = {
    "accessToken": "fake-stale-work-access",
    "refreshToken": "fake-stale-work-refresh",
    "expiresAt": 1,
    "subscriptionType": "team",
}
PERSONAL_TOKENS = {
    "accessToken": "fake-personal-access",
    "refreshToken": "fake-personal-refresh",
    "expiresAt": 1,
    "subscriptionType": "max",
}
PRO_TOKENS = {
    "accessToken": "fake-pro-access",
    "refreshToken": "fake-pro-refresh",
    "expiresAt": 1,
    "subscriptionType": "pro",
}
ENTERPRISE_TOKENS = {
    "accessToken": "fake-enterprise-access",
    "refreshToken": "fake-enterprise-refresh",
    "expiresAt": 1,
    "subscriptionType": "enterprise",
}
# A login that recorded no subscription type: Claude Code treats it as an organization account.
UNTYPED_TOKENS = {
    "accessToken": "fake-untyped-access",
    "refreshToken": "fake-untyped-refresh",
    "expiresAt": 1,
}
MCP_TOKENS = {"server|0000": {"accessToken": "fake-mcp-access"}}
WORK_ACCOUNT = {
    "emailAddress": "someone@work.example",
    "organizationName": "Example Org",
}
# Claude.ai names a personal account's own organization after its email.
PERSONAL_ACCOUNT = {
    "emailAddress": "someone@personal.example",
    "organizationName": "someone@personal.example's Organization",
}
# Server caches every profile shares; nothing in the profile layout touches them.
SHARED_CACHE_FILES = ["remote-settings.json", "policy-limits.json"]


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))


def read_json(path):
    return json.loads(path.read_text())


class Home:
    """A temporary HOME whose ~/.claude each test arranges."""

    def __init__(self):
        self._directory = tempfile.TemporaryDirectory()
        self.path = pathlib.Path(self._directory.name)
        self.claude = self.path / ".claude"
        self.profiles = self.claude / "profiles"
        self.claude.mkdir()

    def close(self):
        self._directory.cleanup()

    def run(self, *arguments, machine=QUIET_MACHINE, environment=None):
        script = (
            'command_file="$1"; shift; source "$command_file"\n'
            + machine
            + '\n_profile_main "$@"'
        )
        full_environment = {
            "HOME": str(self.path),
            "PATH": os.environ["PATH"],
            "NO_COLOR": "1",
        }
        full_environment.update(environment or {})
        return subprocess.run(
            ["bash", "-c", script, "bash", COMMAND_FILE, *arguments],
            env=full_environment,
            # bash with a socket on stdin takes itself for a remote shell and sources the system bashrc.
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            check=False,
        )

    def profile(self, name, tokens=None, account=None):
        """A profile directory: its credentials when tokens are given, else an empty credentials/, and its .claude.json."""
        credentials_path = self.profiles / name / "credentials"
        credentials_path.mkdir(parents=True, exist_ok=True)
        if tokens is not None:
            write_json(
                credentials_path / ".credentials.json", {"claudeAiOauth": tokens}
            )
        config = {"numStartups": 1}
        if account is not None:
            config["oauthAccount"] = account
        write_json(self.profiles / name / ".claude.json", config)

    def v2(self, active="work"):
        """The layout before profiles ran side by side: one live account, the other parked in its token file."""
        write_json(
            self.claude / ".credentials.json",
            {"claudeAiOauth": WORK_TOKENS, "mcpOAuth": MCP_TOKENS},
        )
        write_json(
            self.claude / ".claude.json",
            {
                "oauthAccount": WORK_ACCOUNT,
                "projects": {"/project": {"allowedTools": []}},
                "cachedGrowthBookFeatures": {"flag": True},
                "numStartups": 7,
            },
        )
        write_json(
            self.profiles / "work.json",
            {"claudeAiOauth": STALE_WORK_TOKENS, "oauthAccount": WORK_ACCOUNT},
        )
        write_json(
            self.profiles / "personal.json",
            {"claudeAiOauth": PERSONAL_TOKENS, "oauthAccount": PERSONAL_ACCOUNT},
        )
        os.symlink(f"{active}.json", self.profiles / "active")
        for name in SHARED_CACHE_FILES:
            write_json(self.claude / name, {"cached": "work"})

    def slot(self, default="work"):
        """The migrated layout: a work and a personal profile, with the server caches as ordinary shared files."""
        self.profile("work", WORK_TOKENS, WORK_ACCOUNT)
        self.profile("personal", PERSONAL_TOKENS, PERSONAL_ACCOUNT)
        os.symlink(default, self.profiles / "active")
        os.symlink("profiles/active/.claude.json", self.claude / ".claude.json")
        for name in SHARED_CACHE_FILES:
            write_json(self.claude / name, {"cached": "work"})


class HomeTestCase(unittest.TestCase):
    def setUp(self):
        self.home = Home()
        self.addCleanup(self.home.close)


class Check(HomeTestCase):
    def test_passes_a_clean_slot_layout(self):
        self.home.slot()
        result = self.home.run("check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")

    def test_passes_without_profiles(self):
        result = self.home.run("check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")

    def test_notes_the_v2_layout_and_passes(self):
        self.home.v2()
        result = self.home.run("check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("cc profiles migrate", result.stderr)

    def test_names_the_account_in_a_claude_json_that_replaced_its_link(self):
        self.home.slot()
        (self.home.claude / ".claude.json").unlink()
        write_json(
            self.home.claude / ".claude.json", {"oauthAccount": PERSONAL_ACCOUNT}
        )
        result = self.home.run("check")
        self.assertEqual(result.returncode, 1)
        self.assertIn("someone@personal.example", result.stderr)
        self.assertIn("replaced the link", result.stderr)

    def test_fails_on_shared_credentials(self):
        self.home.slot()
        write_json(
            self.home.claude / ".credentials.json", {"claudeAiOauth": WORK_TOKENS}
        )
        result = self.home.run("check")
        self.assertEqual(result.returncode, 1)
        self.assertIn(".credentials.json exists", result.stderr)

    def test_fails_when_active_links_no_profile(self):
        self.home.slot()
        (self.home.profiles / "active").unlink()
        os.symlink("nobody", self.home.profiles / "active")
        result = self.home.run("check")
        self.assertEqual(result.returncode, 1)
        self.assertIn("links 'nobody'", result.stderr)

    def test_fails_on_two_organization_profiles_naming_both(self):
        self.home.slot()
        self.home.profile("second", ENTERPRISE_TOKENS)
        result = self.home.run("check")
        self.assertEqual(result.returncode, 1)
        self.assertIn("'second', 'work' are organization accounts", result.stderr)

    def test_a_profile_without_a_login_is_not_an_organization(self):
        self.home.slot()
        self.home.profile("second")
        result = self.home.run("check")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_login_without_a_subscription_type_counts_as_an_organization(self):
        self.home.slot()
        self.home.profile("second", UNTYPED_TOKENS)
        result = self.home.run("check")
        self.assertEqual(result.returncode, 1)
        self.assertIn("'second', 'work' are organization accounts", result.stderr)

    def test_passes_with_any_number_of_personal_profiles_beside_one_organization(self):
        self.home.slot()
        self.home.profile("second", PRO_TOKENS)
        self.home.profile("third", PERSONAL_TOKENS)
        result = self.home.run("check")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_without_a_command_prints_usage(self):
        result = self.home.run()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Usage: cc profiles", result.stderr)


class Migrate(HomeTestCase):
    def test_moves_v2_into_one_directory_per_profile(self):
        self.home.v2()
        result = self.home.run("migrate")
        self.assertEqual(result.returncode, 0, result.stderr)
        profiles = self.home.profiles
        self.assertEqual(os.readlink(profiles / "active"), "work")
        # The live tokens are the freshest copy: they move into the default profile, MCP tokens included.
        self.assertEqual(
            read_json(profiles / "work" / "credentials" / ".credentials.json"),
            {"claudeAiOauth": WORK_TOKENS, "mcpOAuth": MCP_TOKENS},
        )
        self.assertEqual(
            read_json(profiles / "personal" / "credentials" / ".credentials.json"),
            {"claudeAiOauth": PERSONAL_TOKENS, "mcpOAuth": MCP_TOKENS},
        )
        work_config = read_json(profiles / "work" / ".claude.json")
        self.assertEqual(work_config["oauthAccount"], WORK_ACCOUNT)
        self.assertEqual(work_config["numStartups"], 7)
        personal_config = read_json(profiles / "personal" / ".claude.json")
        self.assertEqual(personal_config["oauthAccount"], PERSONAL_ACCOUNT)
        self.assertEqual(
            personal_config["projects"], {"/project": {"allowedTools": []}}
        )
        self.assertNotIn("cachedGrowthBookFeatures", personal_config)
        self.assertEqual(
            os.readlink(self.home.claude / ".claude.json"),
            "profiles/active/.claude.json",
        )
        self.assertFalse(os.path.lexists(self.home.claude / ".credentials.json"))
        self.assertEqual(list(profiles.glob("*.json")), [])

    def test_leaves_the_server_caches_alone(self):
        self.home.v2()
        result = self.home.run("migrate")
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in SHARED_CACHE_FILES:
            self.assertFalse((self.home.claude / name).is_symlink(), name)
            self.assertEqual(read_json(self.home.claude / name), {"cached": "work"})

    def test_keeps_a_private_backup_of_what_it_replaced(self):
        self.home.v2()
        self.home.run("migrate")
        backup = self.home.profiles / ".v2-backup"
        self.assertEqual(
            sorted(path.name for path in backup.iterdir()),
            [".claude.json", ".credentials.json", "personal.json", "work.json"],
        )
        self.assertEqual(
            read_json(backup / "personal.json")["claudeAiOauth"], PERSONAL_TOKENS
        )
        self.assertEqual(backup.stat().st_mode & 0o777, 0o700)

    def test_writes_profile_files_privately(self):
        self.home.v2()
        self.home.run("migrate")
        for path in (
            self.home.profiles / "personal" / "credentials" / ".credentials.json",
            self.home.profiles / "personal" / ".claude.json",
            self.home.profiles / "work" / "credentials" / ".credentials.json",
        ):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600, path)
        self.assertEqual(
            (self.home.profiles / "personal" / "credentials").stat().st_mode & 0o777,
            0o700,
        )

    def test_refuses_while_claude_code_runs(self):
        self.home.v2()
        machine = QUIET_MACHINE + "_profile_claude_process_ids() { echo 4242; }\n"
        result = self.home.run("migrate", machine=machine)
        self.assertEqual(result.returncode, 1)
        self.assertIn("4242", result.stderr)
        self.assertEqual(os.readlink(self.home.profiles / "active"), "work.json")
        self.assertFalse((self.home.profiles / ".v2-backup").exists())

    def test_refuses_inside_a_session(self):
        self.home.v2()
        result = self.home.run("migrate", environment={"CLAUDE_BUBBLE": "1"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("runs on the host", result.stderr)

    def test_finishes_an_interrupted_migration(self):
        self.home.v2()
        # Interrupted after the shared files were retired, before profiles/active moved.
        work = self.home.profiles / "work"
        write_json(
            work / "credentials" / ".credentials.json",
            {"claudeAiOauth": WORK_TOKENS, "mcpOAuth": MCP_TOKENS},
        )
        write_json(work / ".claude.json", read_json(self.home.claude / ".claude.json"))
        (self.home.claude / ".claude.json").unlink()
        os.symlink("profiles/active/.claude.json", self.home.claude / ".claude.json")
        (self.home.claude / ".credentials.json").unlink()
        result = self.home.run("migrate")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(os.readlink(self.home.profiles / "active"), "work")
        self.assertEqual(
            read_json(self.home.profiles / "personal" / ".claude.json")["oauthAccount"],
            PERSONAL_ACCOUNT,
        )

    def test_bootstraps_one_profile_from_the_live_files(self):
        write_json(
            self.home.claude / ".credentials.json", {"claudeAiOauth": PERSONAL_TOKENS}
        )
        write_json(
            self.home.claude / ".claude.json", {"oauthAccount": PERSONAL_ACCOUNT}
        )
        result = self.home.run("migrate", "personal")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(os.readlink(self.home.profiles / "active"), "personal")
        self.assertEqual(
            read_json(
                self.home.profiles / "personal" / "credentials" / ".credentials.json"
            ),
            {"claudeAiOauth": PERSONAL_TOKENS},
        )
        self.assertFalse(os.path.lexists(self.home.claude / ".credentials.json"))

    def test_needs_a_name_when_there_are_no_profiles(self):
        write_json(
            self.home.claude / ".credentials.json", {"claudeAiOauth": PERSONAL_TOKENS}
        )
        result = self.home.run("migrate")
        self.assertEqual(result.returncode, 1)
        self.assertIn("usage: cc profiles migrate <name>", result.stderr)

    def test_on_the_slot_layout_restores_a_missing_link(self):
        self.home.slot()
        (self.home.claude / ".claude.json").unlink()
        result = self.home.run("migrate")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            os.readlink(self.home.claude / ".claude.json"),
            "profiles/active/.claude.json",
        )

    def test_on_the_slot_layout_never_overwrites_a_regular_file(self):
        self.home.slot()
        (self.home.claude / ".claude.json").unlink()
        write_json(
            self.home.claude / ".claude.json", {"oauthAccount": PERSONAL_ACCOUNT}
        )
        result = self.home.run("migrate")
        # check still fails on the regular file, which may hold an account's newer state.
        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            read_json(self.home.claude / ".claude.json"),
            {"oauthAccount": PERSONAL_ACCOUNT},
        )

    def test_on_a_clean_slot_layout_changes_nothing(self):
        self.home.slot()
        result = self.home.run("migrate")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already", result.stderr)


UNBUBBLED_PROCESS = QUIET_MACHINE + """
_profile_claude_process_ids() { echo 4242; }
_profile_process_is_bubbled() { return 1; }
"""
BUBBLED_PROCESS = QUIET_MACHINE + """
_profile_claude_process_ids() { echo 4242; }
_profile_process_is_bubbled() { return 0; }
"""
PERSONAL_SESSIONS = QUIET_MACHINE + """
_profile_session_profiles() { printf 'personal\\npersonal\\nwork\\n'; }
"""
NO_USER_MANAGER = QUIET_MACHINE + """
_profile_session_profiles() { return 1; }
"""


class Select(HomeTestCase):
    def test_makes_a_profile_the_default(self):
        self.home.slot()
        result = self.home.run("select", "personal")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(os.readlink(self.home.profiles / "active"), "personal")
        self.assertIn("someone@personal.example", result.stderr)

    def test_goes_ahead_while_bubbled_sessions_run(self):
        self.home.slot()
        result = self.home.run("select", "personal", machine=BUBBLED_PROCESS)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(os.readlink(self.home.profiles / "active"), "personal")

    def test_refuses_while_a_session_outside_the_bubble_runs(self):
        self.home.slot()
        result = self.home.run("select", "personal", machine=UNBUBBLED_PROCESS)
        self.assertEqual(result.returncode, 1)
        self.assertIn("outside the bubble (PIDs: 4242)", result.stderr)
        self.assertEqual(os.readlink(self.home.profiles / "active"), "work")

    def test_refuses_an_unknown_profile(self):
        self.home.slot()
        result = self.home.run("select", "nobody")
        self.assertEqual(result.returncode, 1)
        self.assertIn("does not exist", result.stderr)

    def test_refuses_the_link_name_itself(self):
        self.home.slot()
        result = self.home.run("select", "active")
        self.assertEqual(result.returncode, 1)
        self.assertIn("invalid profile name", result.stderr)

    def test_refuses_inside_a_session(self):
        self.home.slot()
        result = self.home.run("select", "personal", environment={"CLAUDE_BUBBLE": "1"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("runs on the host", result.stderr)

    def test_refuses_the_older_layout(self):
        self.home.v2()
        result = self.home.run("select", "personal")
        self.assertEqual(result.returncode, 1)
        self.assertIn("cc profiles migrate", result.stderr)


class List(HomeTestCase):
    def test_marks_the_default_and_counts_sessions(self):
        self.home.slot()
        result = self.home.run("list", machine=PERSONAL_SESSIONS)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stderr.splitlines()
        personal_line = next(
            line for line in lines if "someone@personal.example" in line
        )
        work_line = next(line for line in lines if "someone@work.example" in line)
        self.assertIn("(max)", personal_line)
        self.assertIn("2 sessions", personal_line)
        self.assertIn("(team, Example Org)", work_line)
        self.assertIn("1 session", work_line)
        self.assertTrue(work_line.lstrip().startswith("* "), work_line)
        self.assertNotIn("* ", personal_line)

    def test_leaves_out_the_organization_named_after_a_personal_account(self):
        self.home.slot()
        result = self.home.run("list", machine=PERSONAL_SESSIONS)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("'s Organization", result.stderr)

    def test_says_so_when_systemd_cannot_be_asked(self):
        self.home.slot()
        result = self.home.run("list", machine=NO_USER_MANAGER)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("sessions unknown", result.stderr)


class Which(HomeTestCase):
    def test_names_the_default_on_the_host(self):
        self.home.slot()
        result = self.home.run("which")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "work someone@work.example\n")

    def test_names_the_session_profile_inside_a_session(self):
        # Inside a bubble profiles/active is the session's own profile, bound there by the launcher.
        self.home.slot(default="personal")
        result = self.home.run(
            "which",
            environment={"CLAUDE_BUBBLE": "1", "CLAUDE_BUBBLE_PROFILE": "personal"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "personal someone@personal.example\n")


class Remove(HomeTestCase):
    def test_removes_a_profile_without_sessions(self):
        self.home.slot()
        result = self.home.run("remove", "personal")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home.profiles / "personal").exists())

    def test_refuses_the_default(self):
        self.home.slot()
        result = self.home.run("remove", "work")
        self.assertEqual(result.returncode, 1)
        self.assertIn("default profile", result.stderr)
        self.assertTrue((self.home.profiles / "work").exists())

    def test_refuses_a_profile_with_running_sessions(self):
        self.home.slot()
        result = self.home.run("remove", "personal", machine=PERSONAL_SESSIONS)
        self.assertEqual(result.returncode, 1)
        self.assertIn("running sessions", result.stderr)
        self.assertTrue((self.home.profiles / "personal").exists())

    def test_refuses_when_systemd_cannot_be_asked(self):
        self.home.slot()
        result = self.home.run("remove", "personal", machine=NO_USER_MANAGER)
        self.assertEqual(result.returncode, 1)
        self.assertIn("cannot ask systemd", result.stderr)
        self.assertTrue((self.home.profiles / "personal").exists())


def logging_in_bubble(subscription_type):
    """Stands in for claude-bubble: records how it was called, then logs in by writing tokens where the bubble binds them."""
    return f"""#!/bin/sh
printf '%s\\n' "$*" >"$HOME/bubble-arguments"
printf '%s\\n' "$BROWSER" >"$HOME/bubble-browser"
printf '{{"claudeAiOauth":{{"accessToken":"fake-new-access","refreshToken":"fake-new-refresh","subscriptionType":"{subscription_type}"}}}}' \\
  >"$HOME/.claude/profiles/$2/credentials/.credentials.json"
"""


# Stands in for a login that was abandoned in the browser.
ABANDONED_BUBBLE = """#!/bin/sh
exit 1
"""


class Add(HomeTestCase):
    def install_bubble(self, script):
        bubble_file = self.home.path / "fake-bubble"
        bubble_file.write_text(script)
        bubble_file.chmod(0o755)
        return {"CLAUDE_BUBBLE_COMMAND": str(bubble_file)}

    def test_logs_in_through_a_bubble_on_the_new_profile(self):
        self.home.slot()
        write_json(
            self.home.profiles / "work" / ".claude.json",
            {
                "oauthAccount": WORK_ACCOUNT,
                "projects": {"/project": {}},
                "cachedStatsigGates": {"gate": True},
            },
        )
        result = self.home.run(
            "add", "second", environment=self.install_bubble(logging_in_bubble("max"))
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (self.home.path / "bubble-arguments").read_text(),
            "--profile second auth login\n",
        )
        self.assertTrue(
            (self.home.path / "bubble-browser")
            .read_text()
            .strip()
            .endswith("claude-bubble-www-browser")
        )
        config = read_json(self.home.profiles / "second" / ".claude.json")
        self.assertEqual(config["projects"], {"/project": {}})
        self.assertNotIn("oauthAccount", config)
        self.assertNotIn("cachedStatsigGates", config)
        self.assertEqual(os.readlink(self.home.profiles / "active"), "work")

    def test_removes_the_profile_again_when_the_login_does_not_finish(self):
        self.home.slot()
        result = self.home.run(
            "add", "second", environment=self.install_bubble(ABANDONED_BUBBLE)
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("did not finish", result.stderr)
        self.assertFalse((self.home.profiles / "second").exists())

    def test_refuses_a_second_organization_login_and_removes_the_profile(self):
        self.home.slot()
        result = self.home.run(
            "add", "second", environment=self.install_bubble(logging_in_bubble("team"))
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("profile 'work' already is one", result.stderr)
        self.assertFalse((self.home.profiles / "second").exists())

    def test_refuses_an_existing_profile(self):
        self.home.slot()
        result = self.home.run(
            "add", "personal", environment=self.install_bubble(logging_in_bubble("max"))
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("already exists", result.stderr)
        self.assertFalse((self.home.path / "bubble-arguments").exists())


# Anthropic's client metadata document as served on 2026-10-20; every profile's document is spliced from the live one.
UPSTREAM_CLIENT_METADATA = {
    "client_id": "https://claude.ai/oauth/claude-code-client-metadata",
    "client_name": "Claude Code",
    "client_uri": "https://claude.ai",
    "redirect_uris": ["http://localhost/callback", "http://127.0.0.1/callback"],
    "grant_types": ["authorization_code", "refresh_token"],
    "response_types": ["code"],
    "token_endpoint_auth_method": "none",
}
BASE_URL = "https://pages.example"


def document_path(name):
    return "oauth/" + name + ".json"


class ClientUrl(HomeTestCase):
    def test_names_the_document_after_the_profile(self):
        result = self.home.run(
            "client-url",
            "work",
            environment={"CLAUDE_PROFILES_OAUTH_CLIENTS_BASE_URL": BASE_URL + "/"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), BASE_URL + "/oauth/work.json")

    def test_prints_nothing_without_a_base_url(self):
        result = self.home.run(
            "client-url",
            "work",
            environment={"CLAUDE_PROFILES_OAUTH_CLIENTS_BASE_URL": ""},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_refuses_an_invalid_name(self):
        result = self.home.run("client-url", "active")
        self.assertEqual(result.returncode, 1)
        self.assertIn("invalid profile name", result.stderr)


class Publish(HomeTestCase):
    """The publisher against a bare origin on disk and an upstream document served from a file."""

    def setUp(self):
        super().setUp()
        self.home.slot()
        self.origin = self.home.path / "origin.git"
        self.repository = self.home.path / "checkout"
        self.git("init", "-q", "--bare", str(self.origin))
        self.git("init", "-q", str(self.repository))
        self.git(
            "-C", str(self.repository), "remote", "add", "origin", str(self.origin)
        )
        self.upstream_file = self.home.path / "upstream.json"
        write_json(self.upstream_file, UPSTREAM_CLIENT_METADATA)

    def git(self, *arguments):
        return subprocess.run(
            ["git", *arguments],
            env={"HOME": str(self.home.path), "PATH": os.environ["PATH"]},
            capture_output=True,
            text=True,
            check=True,
        ).stdout

    def publish(self, base_url=BASE_URL, upstream=None):
        return self.home.run(
            "publish",
            str(self.repository),
            environment={
                "CLAUDE_PROFILES_OAUTH_CLIENTS_BASE_URL": base_url,
                "CLAUDE_PROFILES_UPSTREAM_CLIENT_METADATA_URL": upstream
                or self.upstream_file.as_uri(),
                "GIT_AUTHOR_NAME": "Test",
                "GIT_AUTHOR_EMAIL": "test@example",
                "GIT_COMMITTER_NAME": "Test",
                "GIT_COMMITTER_EMAIL": "test@example",
            },
        )

    def published_files(self):
        return self.git(
            "-C", str(self.origin), "ls-tree", "-r", "--name-only", "gh-pages"
        ).split()

    def published_document(self, name):
        return json.loads(
            self.git("-C", str(self.origin), "show", "gh-pages:" + document_path(name))
        )

    def commit_count(self):
        return int(self.git("-C", str(self.origin), "rev-list", "--count", "gh-pages"))

    def test_creates_the_branch_with_one_document_per_profile(self):
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("published:", result.stderr)
        self.assertEqual(
            sorted(self.published_files()),
            sorted(
                [".nojekyll", "CNAME", document_path("personal"), document_path("work")]
            ),
        )
        self.assertEqual(
            self.git("-C", str(self.origin), "show", "gh-pages:CNAME"),
            "pages.example\n",
        )
        document = self.published_document("work")
        self.assertEqual(document["client_id"], BASE_URL + "/" + document_path("work"))
        self.assertEqual(document["client_name"], "Claude Code (work)")
        for key in (
            "redirect_uris",
            "grant_types",
            "token_endpoint_auth_method",
            "client_uri",
        ):
            self.assertEqual(document[key], UPSTREAM_CLIENT_METADATA[key])
        # The checkout's own index and branches are not touched.
        self.assertEqual(
            self.git("-C", str(self.repository), "status", "--porcelain"), ""
        )
        self.assertEqual(self.git("-C", str(self.repository), "branch", "--list"), "")

    def test_pushes_nothing_when_the_documents_are_current(self):
        self.publish()
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("are current", result.stderr)
        self.assertEqual(self.commit_count(), 1)

    def test_a_new_profile_publishes_a_new_commit(self):
        self.publish()
        self.home.profile("second", PRO_TOKENS)
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.commit_count(), 2)
        self.assertEqual(
            self.published_document("second")["client_name"], "Claude Code (second)"
        )
        self.assertIn(document_path("second"), result.stderr)

    def test_an_unreachable_origin_is_a_note_not_a_failure(self):
        self.git(
            "-C",
            str(self.repository),
            "remote",
            "set-url",
            "origin",
            str(self.home.path / "missing.git"),
        )
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("origin is unreachable", result.stderr)

    def test_an_unreachable_upstream_is_a_note_not_a_failure(self):
        result = self.publish(upstream=(self.home.path / "missing.json").as_uri())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("could not fetch", result.stderr)
        self.assertFalse((self.origin / "refs" / "heads" / "gh-pages").exists())

    def test_an_upstream_of_another_shape_is_refused(self):
        write_json(
            self.upstream_file,
            {
                **UPSTREAM_CLIENT_METADATA,
                "token_endpoint_auth_method": "client_secret_basic",
            },
        )
        result = self.publish()
        self.assertEqual(result.returncode, 1)
        self.assertIn("changed shape", result.stderr)
        self.assertFalse((self.origin / "refs" / "heads" / "gh-pages").exists())

    def test_refuses_without_a_base_url(self):
        result = self.publish(base_url="")
        self.assertEqual(result.returncode, 1)
        self.assertIn("no base URL", result.stderr)


if __name__ == "__main__":
    unittest.main()

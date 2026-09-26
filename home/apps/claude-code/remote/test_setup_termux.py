import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT_FILE = pathlib.Path(__file__).with_name("setup-termux.sh")
# What earlier versions of setup-termux.sh appended to ~/.ssh/config and ~/.bashrc, verbatim.
LEGACY_BLOCK = "Host cc\n  HostName stan-latitude.local\n  Port 7222\n  User stan\n  IdentityFile ~/.ssh/id_ed25519\n"
LEGACY_FINGERPRINT_PROFILE = (
    "\n# cc remote: fingerprint-based SSH key unlock\n"
    'export SSH_ASKPASS="/data/data/com.termux/files/home/.local/bin/ssh-askpass-fingerprint"\n'
    "export SSH_ASKPASS_REQUIRE=force\n"
)
LEGACY_AGENT_PROFILE = (
    "\n# cc remote: ssh-agent (type passphrase once per session)\n"
    'if [ -z "$SSH_AUTH_SOCK" ]; then\n'
    '  eval "$(ssh-agent -s)" >/dev/null\n'
    "fi\n"
)
# The ssh-agent block after an earlier version's cleanup deleted its comment line.
STRANDED_AGENT_PROFILE = (
    'if [ -z "$SSH_AUTH_SOCK" ]; then\n  eval "$(ssh-agent -s)" >/dev/null\nfi\n'
)
USER_PROFILE = "alias ll='ls -l'\nexport EDITOR=nvim\n"


def run_script_function(home_path, command, extra_environment=None, stub_path=None):
    """Source the script (which must not run main) and call one of its functions."""
    search_path = os.environ["PATH"]
    if stub_path is not None:
        search_path = f"{stub_path}:{search_path}"
    environment = {"HOME": str(home_path), "PATH": search_path}
    environment.update(extra_environment or {})
    return subprocess.run(
        ["bash", "-c", f'source "$1"; {command}', "bash", str(SCRIPT_FILE)],
        env=environment,
        capture_output=True,
        text=True,
        check=True,
    )


class ScriptTestCase(unittest.TestCase):
    def setUp(self):
        temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(temporary_directory.cleanup)
        self.home_path = pathlib.Path(temporary_directory.name) / "home"
        self.home_path.mkdir()
        self.stub_path = pathlib.Path(temporary_directory.name) / "bin"
        self.stub_path.mkdir()
        self.ssh_path = self.home_path / ".ssh"

    def run_function(self, command, extra_environment=None):
        return run_script_function(
            self.home_path, command, extra_environment, self.stub_path
        )

    def write_keyscan_stub(self, output):
        stub_file = self.stub_path / "ssh-keyscan"
        stub_file.write_text(f"#!{shutil.which('sh')}\nprintf '%s' '{output}'\n")
        stub_file.chmod(0o755)

    def write_keyscan_stub_logging_arguments(self, output, arguments_file):
        stub_file = self.stub_path / "ssh-keyscan"
        stub_file.write_text(
            f"#!{shutil.which('sh')}\nprintf '%s\\n' \"$*\" >> {arguments_file}\nprintf '%s' '{output}'\n"
        )
        stub_file.chmod(0o755)

    def write_ssh_file(self, name, text):
        self.ssh_path.mkdir(exist_ok=True)
        (self.ssh_path / name).write_text(text)

    def read_ssh_file(self, name):
        return (self.ssh_path / name).read_text()

    @property
    def profile_text(self):
        return (self.home_path / ".bashrc").read_text()

    @property
    def cc_profile_text(self):
        return (self.home_path / ".config" / "cc-remote" / "profile.sh").read_text()

    @property
    def source_line(self):
        cc_profile_file = self.home_path / ".config" / "cc-remote" / "profile.sh"
        return f"[ -f {cc_profile_file} ] && . {cc_profile_file}"


class WriteSshConfigTest(ScriptTestCase):
    def test_fresh_home_gets_only_the_include(self):
        self.run_function("write_ssh_config 100.64.0.7")
        self.assertEqual(self.read_ssh_file("config"), "Include cc_config\n")
        self.assertIn(
            "Host cc\n  HostName 100.64.0.7\n  HostKeyAlias cc\n  Port 7222\n",
            self.read_ssh_file("cc_config"),
        )
        for option in (
            "ConnectTimeout 10",
            "ServerAliveInterval 15",
            "ServerAliveCountMax 4",
        ):
            self.assertIn(f"  {option}\n", self.read_ssh_file("cc_config"))

    def test_the_identity_is_the_absolute_key_path_under_home(self):
        # The askpass helper recognizes the passphrase prompt by the key path built from $HOME, while ssh would expand
        # "~" from the passwd entry, which need not be the same directory.
        self.run_function("write_ssh_config 100.64.0.7")
        key_file = self.ssh_path / "id_ed25519"
        self.assertIn(f'  IdentityFile "{key_file}"\n', self.read_ssh_file("cc_config"))
        result = subprocess.run(
            ["ssh", "-G", "-F", str(self.ssh_path / "cc_config"), "cc"],
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertIn(f"\nidentityfile {key_file}\n", result.stdout)

    def test_legacy_block_is_removed_and_other_hosts_kept(self):
        self.write_ssh_file("config", "Host github.com\n  User git\n\n" + LEGACY_BLOCK)
        self.run_function("write_ssh_config 100.64.0.7")
        self.assertEqual(
            self.read_ssh_file("config"),
            "Include cc_config\nHost github.com\n  User git\n",
        )

    def test_a_hand_edited_cc_stanza_is_removed_wherever_it_is(self):
        self.write_ssh_file(
            "config",
            "host  cc\n  Hostname 192.168.1.10\n  Port 7222\n  ServerAliveInterval 60\n\n"
            "Host github.com\n  User git\n",
        )
        self.run_function("write_ssh_config 100.64.0.7")
        self.assertEqual(
            self.read_ssh_file("config"),
            "Include cc_config\nHost github.com\n  User git\n",
        )

    def test_other_hosts_that_mention_cc_are_kept(self):
        other_hosts = "Host cc-build\n  User builder\nHost cc other\n  User shared\n"
        self.write_ssh_file("config", other_hosts)
        self.run_function("write_ssh_config 100.64.0.7")
        self.assertEqual(
            self.read_ssh_file("config"), "Include cc_config\n" + other_hosts
        )

    def test_legacy_block_alone_leaves_only_the_include(self):
        self.write_ssh_file("config", "\n" + LEGACY_BLOCK)
        self.run_function("write_ssh_config 100.64.0.7")
        self.assertEqual(self.read_ssh_file("config"), "Include cc_config\n")

    def test_rerun_keeps_one_include_and_updates_the_host(self):
        self.run_function("write_ssh_config 100.64.0.7")
        self.run_function("write_ssh_config stan-latitude.example.ts.net")
        self.assertEqual(self.read_ssh_file("config"), "Include cc_config\n")
        self.assertIn(
            "  HostName stan-latitude.example.ts.net\n", self.read_ssh_file("cc_config")
        )
        self.assertNotIn("100.64.0.7", self.read_ssh_file("cc_config"))

    def test_an_include_further_down_moves_to_the_top(self):
        self.write_ssh_file(
            "config", "Host github.com\n  User git\nInclude cc_config\n"
        )
        self.run_function("write_ssh_config 100.64.0.7")
        self.assertEqual(
            self.read_ssh_file("config"),
            "Include cc_config\nHost github.com\n  User git\n",
        )

    def test_files_are_private(self):
        self.run_function("write_ssh_config 100.64.0.7")
        self.assertEqual(self.ssh_path.stat().st_mode & 0o777, 0o700)
        for name in ("config", "cc_config"):
            self.assertEqual((self.ssh_path / name).stat().st_mode & 0o777, 0o600)


class HostKeyTest(ScriptTestCase):
    def test_record_replaces_the_previous_key_and_keeps_other_hosts(self):
        self.write_ssh_file(
            "known_hosts", "github.com ssh-ed25519 AAAAgithub\ncc ssh-ed25519 AAAAold\n"
        )
        self.write_keyscan_stub("[100.64.0.7]:7222 ssh-ed25519 AAAAnew")
        self.run_function("record_host_key 100.64.0.7")
        self.assertEqual(
            self.read_ssh_file("known_hosts"),
            "github.com ssh-ed25519 AAAAgithub\ncc ssh-ed25519 AAAAnew\n",
        )
        self.assertFalse((self.ssh_path / "known_hosts.old").exists())

    def test_record_removes_a_hashed_previous_key(self):
        scratch_path = pathlib.Path(tempfile.mkdtemp(dir=self.stub_path.parent))
        (scratch_path / "known_hosts").write_text("cc ssh-ed25519 AAAAold\n")
        subprocess.run(
            ["ssh-keygen", "-H", "-f", str(scratch_path / "known_hosts")],
            capture_output=True,
            check=True,
        )
        self.write_ssh_file("known_hosts", (scratch_path / "known_hosts").read_text())
        self.write_keyscan_stub("[100.64.0.7]:7222 ssh-ed25519 AAAAnew")
        self.run_function("record_host_key 100.64.0.7")
        self.assertEqual(self.read_ssh_file("known_hosts"), "cc ssh-ed25519 AAAAnew\n")

    def test_a_silent_scan_keeps_the_previous_key(self):
        self.write_ssh_file("known_hosts", "cc ssh-ed25519 AAAAold\n")
        self.write_keyscan_stub("")
        result = self.run_function("record_host_key 100.64.0.7")
        self.assertEqual(self.read_ssh_file("known_hosts"), "cc ssh-ed25519 AAAAold\n")
        self.assertIn("re-run this script", result.stdout)

    def test_marker_lines_for_the_alias_are_kept(self):
        self.write_ssh_file(
            "known_hosts",
            "@cert-authority cc ssh-ed25519 AAAAca\n@revoked cc ssh-ed25519 AAAArevoked\ncc ssh-ed25519 AAAAold\n",
        )
        self.write_keyscan_stub("[100.64.0.7]:7222 ssh-ed25519 AAAAnew")
        self.run_function("record_host_key 100.64.0.7")
        self.assertEqual(
            self.read_ssh_file("known_hosts"),
            "@cert-authority cc ssh-ed25519 AAAAca\n@revoked cc ssh-ed25519 AAAArevoked\ncc ssh-ed25519 AAAAnew\n",
        )

    def test_legacy_keys_are_forgotten_including_a_hand_edited_address(self):
        self.write_ssh_file(
            "config",
            "Host cc\n  HostName 192.168.1.10\n  Port 7222\nHost github.com\n  User git\n",
        )
        self.write_ssh_file(
            "known_hosts",
            "github.com ssh-ed25519 AAAAgithub\n"
            "[192.168.1.10]:7222 ssh-ed25519 AAAAlan\n"
            "[stan-latitude.local]:7222 ssh-ed25519 AAAAmdns\n",
        )
        self.run_function("forget_legacy_host_keys")
        self.assertEqual(
            self.read_ssh_file("known_hosts"), "github.com ssh-ed25519 AAAAgithub\n"
        )
        self.assertFalse((self.ssh_path / "known_hosts.old").exists())

    def test_forgetting_without_a_known_hosts_file_is_quiet(self):
        self.run_function("forget_legacy_host_keys")
        self.assertFalse((self.ssh_path / "known_hosts").exists())


class ShellProfileTest(ScriptTestCase):
    def test_fresh_home_gets_one_source_line(self):
        self.run_function("write_shell_profile fingerprint")
        self.assertEqual(self.profile_text, self.source_line + "\n")
        self.assertIn("export SSH_ASKPASS=", self.cc_profile_text)
        self.assertIn("export SSH_ASKPASS_REQUIRE=force\n", self.cc_profile_text)

    def test_agent_mode_writes_only_the_agent_block(self):
        self.run_function("write_shell_profile agent")
        self.assertIn('eval "$(ssh-agent -s)"', self.cc_profile_text)
        self.assertNotIn("SSH_ASKPASS", self.cc_profile_text)

    def test_every_legacy_block_is_removed_and_user_lines_kept(self):
        (self.home_path / ".bashrc").write_text(
            USER_PROFILE
            + LEGACY_AGENT_PROFILE
            + LEGACY_FINGERPRINT_PROFILE
            + LEGACY_FINGERPRINT_PROFILE
        )
        self.run_function("write_shell_profile fingerprint")
        self.assertEqual(
            self.profile_text, USER_PROFILE + "\n" + self.source_line + "\n"
        )

    def test_stranded_agent_blocks_are_removed(self):
        (self.home_path / ".bashrc").write_text(
            USER_PROFILE + "\n" + STRANDED_AGENT_PROFILE + "\n" + STRANDED_AGENT_PROFILE
        )
        self.run_function("write_shell_profile agent")
        self.assertEqual(
            self.profile_text, USER_PROFILE + "\n" + self.source_line + "\n"
        )

    def test_a_user_block_testing_ssh_auth_sock_is_kept(self):
        user_block = 'if [ -z "$SSH_AUTH_SOCK" ]; then\n  echo "no agent"\nfi\n'
        (self.home_path / ".bashrc").write_text(user_block)
        self.run_function("write_shell_profile agent")
        self.assertEqual(self.profile_text, user_block + "\n" + self.source_line + "\n")

    def test_rerun_and_switching_modes_change_only_the_owned_file(self):
        (self.home_path / ".bashrc").write_text(USER_PROFILE + LEGACY_AGENT_PROFILE)
        self.run_function("write_shell_profile agent")
        first_profile_text = self.profile_text
        self.run_function("write_shell_profile fingerprint")
        self.assertEqual(self.profile_text, first_profile_text)
        self.assertNotIn("ssh-agent", self.cc_profile_text)

    def test_a_user_agent_block_with_extra_lines_is_kept(self):
        # Only the exact three-line block (if, a line with "ssh-agent -s", a bare fi) is ours; anything else is the
        # user's, even when it starts the same way.
        user_block = 'if [ -z "$SSH_AUTH_SOCK" ]; then\n  eval "$(ssh-agent -s)" >/dev/null\n  ssh-add\nfi\n'
        (self.home_path / ".bashrc").write_text(user_block)
        self.run_function("write_shell_profile agent")
        self.assertEqual(self.profile_text, user_block + "\n" + self.source_line + "\n")

    def test_a_stray_comment_on_the_closing_fi_keeps_the_block_and_the_next_one(self):
        user_text = (
            'if [ -z "$SSH_AUTH_SOCK" ]; then\n'
            '  eval "$(ssh-agent -s)" >/dev/null\n'
            "fi # start an agent\n"
            'if [ -n "$PS1" ]; then\n'
            "  echo interactive\n"
            "fi\n"
        )
        (self.home_path / ".bashrc").write_text(user_text)
        self.run_function("write_shell_profile agent")
        self.assertEqual(self.profile_text, user_text + "\n" + self.source_line + "\n")
        subprocess.run(["bash", "-n", str(self.home_path / ".bashrc")], check=True)

    def test_a_legacy_askpass_line_without_export_is_removed(self):
        legacy_line = "SSH_ASKPASS=/data/data/com.termux/files/home/.local/bin/ssh-askpass-fingerprint\n"
        (self.home_path / ".bashrc").write_text(USER_PROFILE + legacy_line)
        self.run_function("write_shell_profile fingerprint")
        self.assertEqual(
            self.profile_text, USER_PROFILE + "\n" + self.source_line + "\n"
        )

    def test_a_cleanup_that_would_not_parse_leaves_bashrc_unchanged(self):
        # The legacy ssh-agent block as the only body of the user's own if: without it, "then" runs straight into
        # "fi", which bash rejects, and a ~/.bashrc that does not parse breaks every new Termux session.
        user_text = (
            'if [ -n "$TERMUX_VERSION" ]; then\n'
            '  if [ -z "$SSH_AUTH_SOCK" ]; then\n'
            '    eval "$(ssh-agent -s)" >/dev/null\n'
            "  fi\n"
            "fi\n"
        )
        (self.home_path / ".bashrc").write_text(user_text)
        result = self.run_function("write_shell_profile fingerprint")
        self.assertEqual(
            (self.home_path / ".bashrc").read_bytes(), user_text.encode("ascii")
        )
        self.assertFalse((self.home_path / ".bashrc.tmp").exists())
        self.assertIn("export SSH_ASKPASS_REQUIRE=force\n", self.cc_profile_text)
        self.assertIn(self.source_line, result.stdout)

    def test_a_user_askpass_require_setting_other_than_force_is_kept(self):
        user_line = "export SSH_ASKPASS_REQUIRE=prefer\n"
        (self.home_path / ".bashrc").write_text(user_line)
        self.run_function("write_shell_profile agent")
        self.assertEqual(self.profile_text, user_line + "\n" + self.source_line + "\n")


class AuthenticationFallbackTest(ScriptTestCase):
    def test_without_fingerprint_unlock_the_stored_passphrase_and_helper_go(self):
        (self.home_path / ".local" / "bin").mkdir(parents=True)
        (self.home_path / ".local" / "bin" / "ssh-askpass-fingerprint").write_text(
            "#!/bin/sh\n"
        )
        self.write_ssh_file(".cc-passphrase", "secret")
        # A PATH without termux-fingerprint takes the ssh-agent fallback.
        self.run_function("setup_authentication")
        self.assertFalse(
            (self.home_path / ".local" / "bin" / "ssh-askpass-fingerprint").exists()
        )
        self.assertFalse((self.ssh_path / ".cc-passphrase").exists())
        self.assertIn('eval "$(ssh-agent -s)"', self.cc_profile_text)


class AskpassHelperTest(ScriptTestCase):
    def write_termux_fingerprint_stub(self):
        stub_file = self.stub_path / "termux-fingerprint"
        stub_file.write_text(
            f"#!{shutil.which('sh')}\nprintf '%s' '{{\"auth_result\": \"AUTH_RESULT_SUCCESS\"}}'\n"
        )
        stub_file.chmod(0o755)

    def run_helper(self, prompt_text):
        helper_file = self.home_path / ".local" / "bin" / "ssh-askpass-fingerprint"
        environment = {
            "HOME": str(self.home_path),
            "PATH": f"{self.stub_path}:{os.environ['PATH']}",
        }
        # No controlling terminal and no stdin, so a prompt the helper does not recognize fails fast on /dev/tty
        # instead of blocking.
        return subprocess.run(
            ["bash", str(helper_file), prompt_text],
            env=environment,
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
            check=True,
        )

    def test_the_helper_only_answers_the_cc_key_passphrase_prompt(self):
        self.ssh_path.mkdir()
        subprocess.run(
            [
                "ssh-keygen",
                "-q",
                "-t",
                "ed25519",
                "-N",
                "secret-passphrase",
                "-f",
                str(self.ssh_path / "id_ed25519"),
            ],
            check=True,
        )
        self.write_ssh_file(".cc-passphrase", "secret-passphrase")
        self.write_termux_fingerprint_stub()
        self.run_function("write_askpass_helper")

        key_prompt = f"Enter passphrase for key '{self.home_path}/.ssh/id_ed25519': "
        result = self.run_helper(key_prompt)
        # .cc-passphrase holds the passphrase with no trailing newline (setup_authentication writes it with printf
        # '%s'), and the helper's "cat" does not add one.
        self.assertEqual(result.stdout, "secret-passphrase")

        password_prompt = "stan@example.org's password: "
        result = self.run_helper(password_prompt)
        self.assertNotIn("secret-passphrase", result.stdout)


class ConfiguredPhoneTest(ScriptTestCase):
    def test_rerun_on_a_phone_set_up_by_an_earlier_version(self):
        self.write_ssh_file("config", "Host github.com\n  User git\n\n" + LEGACY_BLOCK)
        self.write_ssh_file(
            "known_hosts",
            "github.com ssh-ed25519 AAAAgithub\n[stan-latitude.local]:7222 ssh-ed25519 AAAAmdns\n",
        )
        self.write_keyscan_stub("[100.64.0.7]:7222 ssh-ed25519 AAAAtailnet")
        self.run_function("configure_ssh stan-latitude.example.ts.net 100.64.0.7")
        self.run_function("configure_ssh stan-latitude.example.ts.net 100.64.0.7")
        self.assertEqual(
            self.read_ssh_file("config"),
            "Include cc_config\nHost github.com\n  User git\n",
        )
        self.assertEqual(
            self.read_ssh_file("known_hosts"),
            "github.com ssh-ed25519 AAAAgithub\ncc ssh-ed25519 AAAAtailnet\n",
        )
        self.assertEqual(
            sorted(path.name for path in self.ssh_path.iterdir()),
            ["cc_config", "config", "known_hosts"],
        )

    def test_the_key_is_scanned_from_the_address_not_the_name(self):
        # A spoofed DNS answer for the name must not be able to hand back a key HostKeyAlias would then trust.
        arguments_file = self.stub_path.parent / "keyscan-arguments"
        self.write_keyscan_stub_logging_arguments(
            "[100.64.0.7]:7222 ssh-ed25519 AAAAtailnet", arguments_file
        )
        self.run_function("configure_ssh stan-latitude.example.ts.net 100.64.0.7")
        self.assertEqual(arguments_file.read_text(), "-T 5 -p 7222 100.64.0.7\n")
        self.assertIn(
            "  HostName stan-latitude.example.ts.net\n", self.read_ssh_file("cc_config")
        )


class ChooseHostNameTest(ScriptTestCase):
    def choose(self, host_name):
        return self.run_function(
            "choose_host_name",
            {"CC_HOST_ADDRESS": "100.64.0.7", "CC_HOST_NAME": host_name},
        ).stdout.strip()

    def test_uses_the_name_when_ssh_can_resolve_and_reach_it(self):
        self.write_keyscan_stub("stan-latitude.example.ts.net ssh-ed25519 AAAA")
        self.assertEqual(
            self.choose("stan-latitude.example.ts.net"), "stan-latitude.example.ts.net"
        )

    def test_falls_back_to_the_address_when_the_scan_is_silent(self):
        self.write_keyscan_stub("")
        self.assertEqual(self.choose("stan-latitude.example.ts.net"), "100.64.0.7")

    def test_uses_the_address_when_there_is_no_name(self):
        self.write_keyscan_stub("unused ssh-ed25519 AAAA")
        self.assertEqual(self.choose(""), "100.64.0.7")


class MainTest(ScriptTestCase):
    def test_refuses_without_the_bootstrap_variables(self):
        result = subprocess.run(
            ["bash", str(SCRIPT_FILE)],
            env={"HOME": str(self.home_path), "PATH": os.environ["PATH"]},
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("/cc | sh", result.stderr)
        self.assertFalse(self.ssh_path.exists())


if __name__ == "__main__":
    unittest.main()

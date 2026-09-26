import shutil
import subprocess
import unittest

import pairing

PHONE_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGl0IGlzIG5vdCBhIHJlYWwga2V5IGF0IGFsbCBvaw== stan-galaxy@termux"
OTHER_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG90aGVyIGtleSB0aGF0IHN0YXlzIHB1dCBvaw== laptop"
RUNNING_STATUS = {
    "BackendState": "Running",
    "Self": {
        "DNSName": "stan-latitude.example.ts.net.",
        "TailscaleIPs": ["fd7a:115c:a1e0::1", "100.64.0.7"],
    },
}


class PublicKeyTest(unittest.TestCase):
    def test_accepts_an_ed25519_key_with_comment(self):
        self.assertTrue(pairing.is_public_key(PHONE_KEY))

    def test_accepts_a_key_without_comment(self):
        self.assertTrue(pairing.is_public_key(" ".join(PHONE_KEY.split()[:2])))

    def test_rejects_a_second_line(self):
        # A second line would become its own authorized_keys entry, without the forced command.
        self.assertFalse(pairing.is_public_key(PHONE_KEY + "\n" + OTHER_KEY))

    def test_rejects_text_that_is_not_a_key(self):
        self.assertFalse(pairing.is_public_key("hello"))
        self.assertFalse(pairing.is_public_key(""))
        self.assertFalse(pairing.is_public_key('command="/bin/sh" ' + PHONE_KEY))

    def test_rejects_every_line_separator_python_knows(self):
        # str.splitlines() breaks lines at all of these, not just "\n" and "\r"; one hiding in a comment would let
        # a key smuggle a second, unrestricted authorized_keys entry past the "no second line" check above.
        separators = [
            "\n",
            "\r",
            "\v",
            "\f",
            "\x1c",
            "\x1d",
            "\x1e",
            "\x85",
            "\u2028",
            "\u2029",
        ]
        for separator in separators:
            with self.subTest(separator=repr(separator)):
                self.assertFalse(
                    pairing.is_public_key(PHONE_KEY + separator + OTHER_KEY)
                )

    def test_rejects_the_utf8_decode_replacement_character(self):
        # What bytes.decode("utf-8", errors="replace") produces for a malformed byte; not printable ASCII either.
        self.assertFalse(pairing.is_public_key(PHONE_KEY + "\ufffd"))

    def test_identity_is_the_type_and_blob_without_the_comment(self):
        key_type, key_blob = PHONE_KEY.split()[:2]
        self.assertEqual(pairing.key_identity(PHONE_KEY), (key_type, key_blob))
        self.assertEqual(
            pairing.key_identity(f"{key_type} {key_blob} another-comment"),
            pairing.key_identity(PHONE_KEY),
        )
        self.assertEqual(
            pairing.key_identity(f"{key_type} {key_blob}"),
            pairing.key_identity(PHONE_KEY),
        )
        self.assertNotEqual(
            pairing.key_identity(OTHER_KEY), pairing.key_identity(PHONE_KEY)
        )


class AuthorizedKeysTest(unittest.TestCase):
    def test_first_registration_writes_one_restricted_entry(self):
        text = pairing.replace_hub_key("", PHONE_KEY)
        self.assertEqual(text, f"{pairing.KEY_RESTRICTIONS} {PHONE_KEY}\n")

    def test_replaces_the_previous_phone_and_keeps_other_keys(self):
        existing = (
            f"{OTHER_KEY}\n{pairing.KEY_RESTRICTIONS} ssh-ed25519 AAAAold old-phone\n"
        )
        text = pairing.replace_hub_key(existing, PHONE_KEY)
        self.assertEqual(text, f"{OTHER_KEY}\n{pairing.KEY_RESTRICTIONS} {PHONE_KEY}\n")

    def test_an_entry_split_by_a_unicode_separator_is_dropped_whole(self):
        # The earlier pairing server (hub-server.py) accepted any comment, so it could have written this entry.
        # sshd reads it as one line (it splits authorized_keys on real newlines only), so replacing on the same
        # real-newline split drops it whole, not just its first half.
        existing = (
            f"{pairing.KEY_RESTRICTIONS} ssh-ed25519 AAAAold phone"
            "\u2028ssh-ed25519 AAAAattacker attacker\n"
        )
        text = pairing.replace_hub_key(existing, PHONE_KEY)
        self.assertNotIn("attacker", text)
        self.assertEqual(len(text.splitlines()), 1)

    def test_restrictions_lock_the_key_to_the_hub(self):
        self.assertTrue(
            pairing.KEY_RESTRICTIONS.startswith(f'command="{pairing.FORCED_COMMAND}"')
        )
        for restriction in (
            "no-port-forwarding",
            "no-agent-forwarding",
            "no-X11-forwarding",
        ):
            self.assertIn(restriction, pairing.KEY_RESTRICTIONS)

    def test_verification_matches_a_registered_hub_key(self):
        report = pairing.verification_report(
            pairing.replace_hub_key("", PHONE_KEY), PHONE_KEY
        )
        self.assertIn("Match: YES", report)

    def test_verification_ignores_the_same_key_without_restrictions(self):
        report = pairing.verification_report(PHONE_KEY + "\n", PHONE_KEY)
        self.assertIn("Match: NO", report)


class PreflightTest(unittest.TestCase):
    def test_refuses_inside_the_bubble(self):
        with self.assertRaises(pairing.PreflightError) as caught:
            pairing.check_environment({"CLAUDE_BUBBLE": "1"})
        self.assertIn("normal terminal", " ".join(caught.exception.remedies))

    def test_accepts_a_normal_terminal(self):
        pairing.check_environment({"CLAUDE_BUBBLE": ""})
        pairing.check_environment({})

    def test_identity_takes_the_ipv4_address_and_the_bare_name(self):
        self.assertEqual(
            pairing.tailnet_identity(RUNNING_STATUS, "tailscale up"),
            ("100.64.0.7", "stan-latitude.example.ts.net"),
        )

    def test_identity_without_magic_dns_has_an_empty_name(self):
        status = {
            "BackendState": "Running",
            "Self": {"DNSName": "", "TailscaleIPs": ["100.64.0.7"]},
        }
        self.assertEqual(
            pairing.tailnet_identity(status, "tailscale up"), ("100.64.0.7", "")
        )

    def test_identity_drops_a_name_that_is_not_a_plain_host_name(self):
        # The name lands unquoted in the phone's ~/.ssh/cc_config, where a newline or a space would add ssh options.
        for hostile_name in (
            "stan-latitude.example.ts.net.\n  ProxyCommand touch /tmp/owned",
            "stan-latitude.example.ts.net ProxyCommand=touch",
            "stan latitude.example.ts.net.",
            "-oProxyCommand=x.example.ts.net.",
            "-oProxyCommand.x.example.ts.net.",
        ):
            with self.subTest(name=hostile_name):
                status = {
                    "BackendState": "Running",
                    "Self": {"DNSName": hostile_name, "TailscaleIPs": ["100.64.0.7"]},
                }
                self.assertEqual(
                    pairing.tailnet_identity(status, "tailscale up"), ("100.64.0.7", "")
                )

    def test_identity_refuses_when_not_logged_in_and_names_the_first_login(self):
        with self.assertRaises(pairing.PreflightError) as caught:
            pairing.tailnet_identity(
                {"BackendState": "NeedsLogin"}, "tailscale up --operator=stan"
            )
        self.assertIn("NeedsLogin", caught.exception.problem)
        self.assertIn(
            "tailscale up --operator=stan", " ".join(caught.exception.remedies)
        )

    def test_identity_refuses_without_an_ipv4_address(self):
        status = {
            "BackendState": "Running",
            "Self": {"TailscaleIPs": ["fd7a:115c:a1e0::1"]},
        }
        with self.assertRaises(pairing.PreflightError):
            pairing.tailnet_identity(status, "tailscale up")

    def test_identity_takes_only_a_real_ipv4_address(self):
        # The address is embedded in the served shell script, so a string that merely contains a dot must not pass.
        hostile_address = "100.64.0.7\ntouch /tmp/owned"
        status = {
            "BackendState": "Running",
            "Self": {"TailscaleIPs": [hostile_address, "100.64.0.8"]},
        }
        self.assertEqual(
            pairing.tailnet_identity(status, "tailscale up")[0], "100.64.0.8"
        )
        status["Self"]["TailscaleIPs"] = [hostile_address]
        with self.assertRaises(pairing.PreflightError):
            pairing.tailnet_identity(status, "tailscale up")

    def test_prefs_as_declared_pass(self):
        pairing.check_prefs({"NetfilterMode": 1, "CorpDNS": False})

    def test_netfilter_on_is_refused_with_the_fix(self):
        with self.assertRaises(pairing.PreflightError) as caught:
            pairing.check_prefs({"NetfilterMode": 2, "CorpDNS": False})
        self.assertIn(
            "tailscale set --netfilter-mode=nodivert",
            " ".join(caught.exception.remedies),
        )

    def test_both_reverted_by_a_bare_first_login_are_named(self):
        with self.assertRaises(pairing.PreflightError) as caught:
            pairing.check_prefs({"NetfilterMode": 2, "CorpDNS": True})
        self.assertIn(
            "tailscale set --netfilter-mode=nodivert --accept-dns=false",
            " ".join(caught.exception.remedies),
        )


class BootstrapTest(unittest.TestCase):
    def shell_syntax_check(self, text):
        shell = shutil.which("dash") or shutil.which("sh")
        return subprocess.run(
            [shell, "-n"], input=text, text=True, capture_output=True, check=False
        )

    def test_is_valid_posix_shell(self):
        text = pairing.render_bootstrap("100.64.0.7", "stan-latitude.example.ts.net")
        result = self.shell_syntax_check(text)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_fetches_the_setup_script_and_passes_the_laptop(self):
        text = pairing.render_bootstrap("100.64.0.7", "stan-latitude.example.ts.net")
        self.assertIn("curl -fsS http://100.64.0.7:8081/setup-termux.sh", text)
        self.assertIn("CC_HOST_ADDRESS=100.64.0.7", text)
        self.assertIn("CC_HOST_NAME=stan-latitude.example.ts.net", text)
        self.assertIn("CC_PAIRING_URL=http://100.64.0.7:8081", text)
        self.assertIn('bash "$script_file" </dev/tty', text)

    def test_quotes_hostile_values(self):
        text = pairing.render_bootstrap("100.64.0.7", "x'; touch /tmp/owned; '")
        self.assertEqual(self.shell_syntax_check(text).returncode, 0)
        self.assertNotIn("\ntouch /tmp/owned", text)

    def test_checklist_carries_the_exact_phone_command(self):
        self.assertIn(
            "curl -sS 100.64.0.7:8081/cc | sh", pairing.checklist("100.64.0.7")
        )

    def test_checklist_says_the_command_needs_tailscale_connected(self):
        # 100.64.0.0/10 is carrier-grade NAT space, so on mobile data without Tailscale the address is the carrier's.
        text = pairing.checklist("100.64.0.7")
        self.assertIn("only safe with Tailscale connected", text)
        self.assertIn("carrier-grade NAT", text)


class FormatErrorTest(unittest.TestCase):
    def test_plain_output_hangs_remedies_under_the_message(self):
        self.assertEqual(
            pairing.format_error("broken", ["do this", "", "then that"], colour=False),
            "error: broken\n       do this\n\n       then that\n",
        )

    def test_colour_wraps_only_the_severity_word(self):
        self.assertEqual(
            pairing.format_error("broken", [], colour=True),
            "\033[31merror:\033[0m broken\n",
        )


if __name__ == "__main__":
    unittest.main()

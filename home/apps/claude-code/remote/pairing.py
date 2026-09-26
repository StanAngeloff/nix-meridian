"""Pure decisions for `cc remote setup`: key validation, the authorized_keys entry, preflight, and the served text.

Everything here is a function of its arguments, so test_pairing.py covers it without a network, a tailscaled, or a
real ~/.ssh. pairing_server.py is the I/O around it.
"""

import ipaddress
import re
import shlex

FORCED_COMMAND = "/etc/profiles/per-user/stan/bin/cc-hub"
KEY_RESTRICTIONS = f'command="{FORCED_COMMAND}",no-port-forwarding,no-agent-forwarding,no-X11-forwarding'
PAIRING_PORT = 8081
# preftype.NetfilterMode in tailscaled 1.98.10: 0 off, 1 nodivert, 2 on.
NETFILTER_NODIVERT = 1

# One key on one line: type, base64 blob, optional comment. The comment is restricted to printable ASCII: besides
# \r and \n, str.splitlines() also breaks lines at \v, \f, \x1c, \x1d, \x1e, \x85, U+2028 and U+2029, and any of
# those hiding in a comment would let a key smuggle a second, unrestricted authorized_keys entry past this check.
_PUBLIC_KEY_PATTERN = re.compile(
    r"(?:ssh|ecdsa|sk)-[A-Za-z0-9@.-]+ [A-Za-z0-9+/]+={0,3}(?: [\x20-\x7e]*)?"
)
_HOST_NAME_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]*")


class PreflightError(Exception):
    """Why `cc remote setup` will not start: a one-line problem, then lines saying what to do about it."""

    def __init__(self, problem, *remedies):
        super().__init__(problem)
        self.problem = problem
        self.remedies = remedies


def is_public_key(text):
    return _PUBLIC_KEY_PATTERN.fullmatch(text) is not None


def key_identity(public_key):
    """Type and base64 blob: what sshd matches; the comment is not part of the key."""
    return tuple(public_key.split()[:2])


def replace_hub_key(authorized_keys_text, public_key):
    """Drop every previous cc-hub entry and append this key's; other keys are kept as they are."""
    marker = f'command="{FORCED_COMMAND}"'
    # Split the way sshd does (real newlines only), not with str.splitlines(): an entry written by the earlier pairing
    # server (hub-server.py), which accepted any comment, could carry another separator that splitlines() honors, and
    # splitting there too would keep the half after it as its own, unrestricted line instead of dropping the entry.
    kept_lines = [
        line for line in authorized_keys_text.split("\n") if line and marker not in line
    ]
    kept_lines.append(f"{KEY_RESTRICTIONS} {public_key}")
    return "\n".join(kept_lines) + "\n"


def verification_report(authorized_keys_text, public_key):
    """Plain-text answer for /verify-key; setup-termux.sh looks for the "Match: YES" line."""
    key_type, key_blob = public_key.split()[:2]
    registered_prefix = f"{KEY_RESTRICTIONS} {key_type} {key_blob}"
    registered_lines = [
        line
        for line in authorized_keys_text.split("\n")
        if line and line.startswith(f'command="{FORCED_COMMAND}"')
    ]
    is_registered = any(line.startswith(registered_prefix) for line in registered_lines)
    report_lines = [
        f"Phone key: {public_key[:80]}...",
        f"Match: {'YES' if is_registered else 'NO'}",
    ]
    if not is_registered:
        report_lines += [
            f"Registered: {line[len(KEY_RESTRICTIONS) + 1:][:70]}..."
            for line in registered_lines
        ]
    return "\n".join(report_lines) + "\n"


def check_environment(environment):
    """Refuse inside the bubble: ~/.ssh there is assembled from selected binds without authorized_keys, so a key
    written from inside would land in a throwaway view and silently vanish."""
    if environment.get("CLAUDE_BUBBLE"):
        raise PreflightError(
            "running inside a cc session",
            "~/.ssh/authorized_keys is not visible in here, so a registered key would vanish.",
            "Run `cc remote setup` from a normal terminal.",
        )


def _is_ipv4_address(value):
    try:
        return isinstance(value, str) and ipaddress.ip_address(value).version == 4
    except ValueError:
        return False


def _plain_host_name(value):
    """The MagicDNS name without its trailing dot, or "" unless it holds only letters, digits, dots and hyphens."""
    name = value.rstrip(".") if isinstance(value, str) else ""
    return name if _HOST_NAME_PATTERN.fullmatch(name) else ""


def tailnet_identity(status, first_login_command):
    """(IPv4 address, MagicDNS name) of this machine from `tailscale status --json`.
    Only strings that parse as IPv4 count: the address is embedded in the served bootstrap script and in URLs.
    The name counts only as a plain host name: it lands unquoted in the phone's ~/.ssh/cc_config.
    """
    backend_state = status.get("BackendState")
    if backend_state != "Running":
        raise PreflightError(
            f"Tailscale is not running on this laptop (state: {backend_state})",
            f"First login: {first_login_command}",
        )
    self_status = status.get("Self") or {}
    ipv4_addresses = [
        address
        for address in self_status.get("TailscaleIPs") or []
        if _is_ipv4_address(address)
    ]
    if not ipv4_addresses:
        raise PreflightError("Tailscale has no IPv4 address for this laptop")
    return ipv4_addresses[0], _plain_host_name(self_status.get("DNSName"))


def check_prefs(prefs):
    """Refuse unless tailscaled runs with the settings system/components/tailscale.nix declares.
    A first `tailscale up` without the flags resets them to defaults, and netfilter-mode "on" accepts every port on
    tailscale0 ahead of the NixOS firewall."""
    fixes = []
    if prefs.get("NetfilterMode") != NETFILTER_NODIVERT:
        fixes.append("--netfilter-mode=nodivert")
    if prefs.get("CorpDNS") is not False:
        fixes.append("--accept-dns=false")
    if fixes:
        raise PreflightError(
            "Tailscale's settings on this laptop differ from the NixOS configuration",
            "netfilter-mode must be nodivert so the NixOS firewall, not tailscaled, decides what the tailnet reaches.",
            f"Fix with: tailscale set {' '.join(fixes)}",
        )


def render_bootstrap(address, dns_name, port=PAIRING_PORT):
    """POSIX sh served at /cc. A script piped into sh cannot re-execute itself, so this one downloads the bash setup
    script to a file and runs that with the terminal as its input."""
    base_url = f"http://{address}:{port}"
    return (
        "#!/bin/sh\n"
        f"# Served by `cc remote setup`; run in Termux as: curl -sS {address}:{port}/cc | sh\n"
        "set -eu\n"
        'script_file="$(mktemp)"\n'
        "trap 'rm -f \"$script_file\"' EXIT\n"
        f'curl -fsS {shlex.quote(base_url + "/setup-termux.sh")} -o "$script_file"\n'
        f"CC_HOST_ADDRESS={shlex.quote(address)} CC_HOST_NAME={shlex.quote(dns_name)} "
        f'CC_PAIRING_URL={shlex.quote(base_url)} bash "$script_file" </dev/tty\n'
    )


def checklist(address, port=PAIRING_PORT):
    return (
        f"Pairing server listening on {address}:{port} (Tailscale only).\n"
        "\n"
        "On the phone:\n"
        "  1. Tailscale app installed (F-Droid or Play Store), signed in to this laptop's account, and connected.\n"
        "  2. In Termux, run:\n"
        "\n"
        f"       curl -sS {address}:{port}/cc | sh\n"
        "\n"
        "     This is only safe with Tailscale connected on the phone: 100.64.0.0/10 is carrier-grade NAT space on\n"
        "     mobile networks, so without Tailscale that address can belong to a machine at the carrier, not this laptop.\n"
        "\n"
        '  3. When Termux prints "To connect from this phone: ssh cc", press Ctrl-C here.\n'
    )


def format_error(problem, remedies, colour):
    """Same shape as bubble/utilities/log.sh for untagged output: the severity word leads, continuations hang under
    the message, blank continuations stay blank."""
    lead = "\033[31merror:\033[0m " if colour else "error: "
    indent = " " * (len("error:") + 1)
    lines = [f"{lead}{problem}\n"]
    lines += [f"{indent}{remedy}\n" if remedy else "\n" for remedy in remedies]
    return "".join(lines)

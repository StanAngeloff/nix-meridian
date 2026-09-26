"""`cc remote setup`: pair a phone with the cc session hub over the tailnet.

Serves the phone's bootstrap (/cc) and setup script (/setup-termux.sh) on this laptop's Tailscale address only, and
takes the phone's public key back (/pubkey, /verify-key) into ~/.ssh/authorized_keys, locked to the cc-hub forced
command. The decisions live in pairing.py; this file is the I/O around them.
"""

import argparse
import http.server
import json
import os
import subprocess
import sys
import tempfile

import pairing

AUTHORIZED_KEYS_FILE = os.path.expanduser("~/.ssh/authorized_keys")
SETUP_SCRIPT_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "setup-termux.sh"
)
MAXIMUM_BODY_LENGTH = 16384
# Set by package.nix from services.tailscale.extraSetFlags; the fallback only shows when run from the repository.
FIRST_LOGIN_COMMAND = os.environ.get(
    "CC_REMOTE_FIRST_LOGIN_COMMAND",
    "tailscale up with the flags in services.tailscale.extraSetFlags (system/components/tailscale.nix)",
)


def tailscale_json(*arguments):
    try:
        completed = subprocess.run(
            ["tailscale", *arguments], capture_output=True, text=True, check=False
        )
    except FileNotFoundError:
        raise pairing.PreflightError(
            "the tailscale command is not installed",
            "Enable system/components/tailscale.nix and run make switch.",
        ) from None
    if completed.returncode != 0:
        raise pairing.PreflightError(
            f"`tailscale {' '.join(arguments)}` failed: {completed.stderr.strip() or completed.returncode}",
            f"Is tailscaled running? First login: {FIRST_LOGIN_COMMAND}",
        )
    try:
        parsed = json.loads(completed.stdout)
    except json.JSONDecodeError:
        parsed = None
    if not isinstance(parsed, dict):
        raise pairing.PreflightError(
            f"`tailscale {' '.join(arguments)}` did not print a JSON object"
        )
    return parsed


def read_authorized_keys():
    try:
        # newline="": sshd splits entries on "\n" only, so a "\r" inside one must not start a new line here.
        with open(AUTHORIZED_KEYS_FILE, encoding="utf-8", newline="") as handle:
            return handle.read()
    except FileNotFoundError:
        return ""


def write_authorized_keys(text):
    """Replace the file atomically, so an interrupted write cannot leave sshd a truncated key list."""
    directory = os.path.dirname(AUTHORIZED_KEYS_FILE)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    descriptor, temporary_file = tempfile.mkstemp(
        dir=directory, prefix=".authorized_keys."
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        # mkstemp already created the file 0600.
        os.replace(temporary_file, AUTHORIZED_KEYS_FILE)
    except BaseException:
        if os.path.exists(temporary_file):
            os.unlink(temporary_file)
        raise


class Handler(http.server.BaseHTTPRequestHandler):
    """Four routes and nothing else: every other path is an empty 404, so no other file is ever served."""

    # A peer that stalls mid-request would otherwise hold this single-threaded server, and the phone with it.
    timeout = 10

    def do_GET(self):
        if self.path == "/cc":
            self.respond(200, self.server.bootstrap_text.encode())
        elif self.path == "/setup-termux.sh":
            with open(SETUP_SCRIPT_FILE, "rb") as handle:
                self.respond(200, handle.read())
        else:
            self.respond(404, b"")

    def do_POST(self):
        if self.path not in ("/pubkey", "/verify-key"):
            self.respond(404, b"")
            return
        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            length = 0
        if length <= 0:
            self.respond(411, b"Content-Length required.\n")
            return
        if length > MAXIMUM_BODY_LENGTH:
            self.respond(413, b"Too large.\n")
            return
        try:
            body = self.rfile.read(length)
        except TimeoutError:
            self.close_connection = True
            return
        public_key = body.decode("utf-8", errors="replace").strip()
        if not pairing.is_public_key(public_key):
            self.respond(400, b"Invalid key format.\n")
            return
        if self.path == "/pubkey":
            # One phone per run: the first key registered wins, so nothing else that reaches this port while pairing
            # runs (another tailnet device, or a local process such as a cc session) can displace it afterwards.
            key_identity = pairing.key_identity(public_key)
            registered_key = self.server.registered_key
            if registered_key is not None and registered_key != key_identity:
                self.respond(
                    409,
                    b"This run already registered a different key; restart `cc remote setup` to pair again.\n",
                )
                print(
                    f"\n>>> Refused a second, different key from {self.client_address[0]}",
                    flush=True,
                )
                return
            write_authorized_keys(
                pairing.replace_hub_key(read_authorized_keys(), public_key)
            )
            self.server.registered_key = key_identity
            self.respond(200, b"Key registered. Ready to connect.\n")
            key_parts = public_key.split(maxsplit=2)
            key_type = key_parts[0]
            key_comment = key_parts[2] if len(key_parts) > 2 else "(no comment)"
            print(
                f"\n>>> Public key registered in {AUTHORIZED_KEYS_FILE}: {key_type} {key_comment}"
            )
            print(">>> The phone can now connect: ssh cc\n")
        else:
            report = pairing.verification_report(read_authorized_keys(), public_key)
            self.respond(200, report.encode())
            print(
                f"\n>>> Key verification: {'MATCH' if 'Match: YES' in report else 'MISMATCH'}"
            )

    def respond(self, status, body):
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # The client is already gone; nothing left to tell it.


def main():
    argparse.ArgumentParser(
        prog="cc remote setup",
        description=(
            "Pair a phone with cc remote access: serve its setup script on this laptop's Tailscale address "
            "and register its public key in ~/.ssh/authorized_keys."
        ),
    ).parse_args()
    colour = sys.stderr.isatty() and not os.environ.get("NO_COLOR")

    try:
        pairing.check_environment(os.environ)
        address, dns_name = pairing.tailnet_identity(
            tailscale_json("status", "--json"), FIRST_LOGIN_COMMAND
        )
        pairing.check_prefs(tailscale_json("debug", "prefs"))
    except pairing.PreflightError as error:
        sys.stderr.write(pairing.format_error(error.problem, error.remedies, colour))
        return 1

    try:
        server = http.server.HTTPServer((address, pairing.PAIRING_PORT), Handler)
    except OSError as error:
        sys.stderr.write(
            pairing.format_error(
                f"cannot listen on {address}:{pairing.PAIRING_PORT}: {error.strerror}",
                ["Is another server (an Expo dev server?) already using that port?"],
                colour,
            )
        )
        return 1

    server.bootstrap_text = pairing.render_bootstrap(address, dns_name)
    server.registered_key = None
    print(pairing.checklist(address), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

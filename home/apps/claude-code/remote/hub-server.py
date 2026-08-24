#!/usr/bin/env python3
"""Temporary HTTP server for phone setup: serves files and accepts the public key back via POST.

Usage:
    python3 hub-server.py [port]

Serves this directory on the given port (default 8081) and prints the curl
command to run on the phone. The setup script generates an SSH key, posts it
back via /pubkey, and verifies the registration via /verify-key.
"""

import http.server
import os
import re
import socket
import sys

AUTHORIZED_KEYS = os.path.expanduser("~/.ssh/authorized_keys")
FORCED_COMMAND = "/etc/profiles/per-user/stan/bin/cc-hub"
KEY_RESTRICTIONS = (
    f'command="{FORCED_COMMAND}",'
    "no-port-forwarding,no-agent-forwarding,no-X11-forwarding"
)
SERVE_DIR = os.path.dirname(os.path.abspath(__file__))


def get_local_ip():
    """Best-effort LAN IP by opening a UDP socket to a public address (no traffic sent)."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.168.1.1", 1))
            return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def save_key(raw_key):
    """Write the key to ~/.ssh/authorized_keys with forced command restrictions.

    Replaces any existing cc-hub entry idempotently.
    """
    entry = f"{KEY_RESTRICTIONS} {raw_key}\n"
    os.makedirs(os.path.dirname(AUTHORIZED_KEYS), exist_ok=True)

    existing = ""
    if os.path.exists(AUTHORIZED_KEYS):
        with open(AUTHORIZED_KEYS) as f:
            existing = f.read()

    marker = f'command="{FORCED_COMMAND}"'
    lines = [line for line in existing.splitlines() if marker not in line]
    lines.append(entry.rstrip())

    with open(AUTHORIZED_KEYS, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.chmod(AUTHORIZED_KEYS, 0o600)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=SERVE_DIR, **kwargs)

    def do_POST(self):
        if self.path == "/pubkey":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode().strip()
            if re.match(r"^ssh-\w+\s+\S+", body):
                save_key(body)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"Key registered. Ready to connect.\n")
                print(f"\n>>> Public key registered in {AUTHORIZED_KEYS}")
                print(">>> Phone can now connect: ssh cc\n")
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Invalid key format.\n")
        elif self.path == "/verify-key":
            length = int(self.headers.get("Content-Length", 0))
            phone_key = self.rfile.read(length).decode().strip()
            existing = ""
            if os.path.exists(AUTHORIZED_KEYS):
                with open(AUTHORIZED_KEYS) as f:
                    existing = f.read()
            phone_parts = phone_key.split()[:2] if phone_key else []
            phone_sig = " ".join(phone_parts)
            match = phone_sig in existing if phone_sig else False
            self.send_response(200)
            self.end_headers()
            result = (
                f"Phone key: {phone_key[:80]}...\nMatch: {'YES' if match else 'NO'}\n"
            )
            if not match:
                for line in existing.splitlines():
                    if "cc-hub" in line:
                        parts = line.split("ssh-")
                        if len(parts) >= 2:
                            result += f"Registered: ssh-{parts[-1][:70]}...\n"
            self.wfile.write(result.encode())
            print(f"\n>>> Key verification: {'MATCH' if match else 'MISMATCH'}")
        else:
            self.send_response(404)
            self.end_headers()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
    hostname = socket.gethostname()
    ip = get_local_ip()

    server = http.server.HTTPServer(("", port), Handler)
    print(f"Serving {SERVE_DIR} on port {port}")
    print(f"POST /pubkey → register key in {AUTHORIZED_KEYS}")
    print("POST /verify-key → compare phone key against registered key")
    print()
    print("On the phone (Termux), run:")
    print(f"  curl -sS http://{ip}:{port}/setup-termux.sh | bash")
    print()
    print(f"  (or try: http://{hostname}.local:{port}/setup-termux.sh)")
    print()
    server.serve_forever()

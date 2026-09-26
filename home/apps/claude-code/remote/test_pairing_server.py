"""HTTP behavior of pairing_server.Handler: routes, one key per run, malformed requests, a stalled client.
pairing.py's own decisions (key validation, the authorized_keys entry) are covered without a server in test_pairing.py.
"""

import http.client
import http.server
import os
import socket
import stat
import tempfile
import threading
import unittest

import pairing
import pairing_server

PHONE_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGl0IGlzIG5vdCBhIHJlYWwga2V5IGF0IGFsbCBvaw== stan-galaxy@termux"
OTHER_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG90aGVyIGtleSB0aGF0IHN0YXlzIHB1dCBvaw== laptop"
BOOTSTRAP_TEXT = "#!/bin/sh\necho bootstrap\n"


class HandlerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Port 0 picks an unused port; never bind the real pairing port from a test.
        cls.server = http.server.HTTPServer(("127.0.0.1", 0), pairing_server.Handler)
        cls.server.bootstrap_text = BOOTSTRAP_TEXT
        cls.port = cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        # Point the module's authorized_keys path at a fresh, absent file for every test.
        self.original_authorized_keys_file = pairing_server.AUTHORIZED_KEYS_FILE
        descriptor, self.authorized_keys_file = tempfile.mkstemp()
        os.close(descriptor)
        os.unlink(self.authorized_keys_file)
        pairing_server.AUTHORIZED_KEYS_FILE = self.authorized_keys_file
        # Every test starts a fresh pairing run, as main() does.
        self.server.registered_key = None

    def tearDown(self):
        pairing_server.AUTHORIZED_KEYS_FILE = self.original_authorized_keys_file
        if os.path.exists(self.authorized_keys_file):
            os.unlink(self.authorized_keys_file)

    def connection(self):
        return http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)

    def read_authorized_keys(self):
        # newline="": the text exactly as sshd sees it, with no "\r" turned into a line break.
        with open(self.authorized_keys_file, encoding="utf-8", newline="") as handle:
            return handle.read()

    def post(self, path, body):
        connection = self.connection()
        connection.request("POST", path, body=body)
        response = connection.getresponse()
        return response.status, response.read()

    def raw_post(self, content_length_header, body=b"", read_amount=200, wait=5):
        """A POST with headers we control byte-for-byte; http.client would compute a correct Content-Length itself.
        A content_length_header of None sends no Content-Length line at all."""
        content_length_line = (
            b""
            if content_length_header is None
            else b"Content-Length: " + content_length_header + b"\r\n"
        )
        connection = socket.create_connection(("127.0.0.1", self.port), timeout=wait)
        try:
            connection.sendall(
                b"POST /verify-key HTTP/1.1\r\n"
                b"Host: 127.0.0.1\r\n"
                + content_length_line
                + b"Connection: close\r\n\r\n"
                + body
            )
            try:
                return connection.recv(read_amount)
            except TimeoutError:
                return None
        finally:
            connection.close()

    def status_line(self, data):
        return data.split(b"\r\n", 1)[0] if data else b""

    def test_get_cc_serves_the_bootstrap_text(self):
        connection = self.connection()
        connection.request("GET", "/cc")
        response = connection.getresponse()
        self.assertEqual(response.status, 200)
        self.assertEqual(response.read(), BOOTSTRAP_TEXT.encode())

    def test_unknown_paths_are_404_with_an_empty_body(self):
        for path in ("/hub.sh", "/pairing_server.py"):
            with self.subTest(path=path):
                connection = self.connection()
                connection.request("GET", path)
                response = connection.getresponse()
                self.assertEqual(response.status, 404)
                self.assertEqual(response.read(), b"")

    def test_pubkey_registers_a_valid_key(self):
        connection = self.connection()
        connection.request("POST", "/pubkey", body=PHONE_KEY)
        response = connection.getresponse()
        self.assertEqual(response.status, 200)
        response.read()
        lines = self.read_authorized_keys().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertTrue(lines[0].startswith(pairing.KEY_RESTRICTIONS))
        mode = stat.S_IMODE(os.stat(self.authorized_keys_file).st_mode)
        self.assertEqual(mode, 0o600)

    def test_pubkey_rejects_an_injected_separator_and_leaves_the_file_unchanged(self):
        connection = self.connection()
        connection.request("POST", "/pubkey", body=PHONE_KEY)
        connection.getresponse().read()
        before = self.read_authorized_keys()

        hostile_key = (PHONE_KEY + "\u2028ssh-ed25519 AAAAattacker attacker").encode(
            "utf-8"
        )
        connection = self.connection()
        connection.request("POST", "/pubkey", body=hostile_key)
        response = connection.getresponse()
        self.assertEqual(response.status, 400)
        response.read()
        self.assertEqual(self.read_authorized_keys(), before)

    def test_pubkey_drops_a_hub_entry_split_by_a_carriage_return_whole(self):
        # The earlier pairing server (hub-server.py) accepted any comment, so it could have written this entry.
        # sshd reads it as one restricted line; read with universal newlines, its second half would survive the
        # replacement as its own, unrestricted line.
        with open(
            self.authorized_keys_file, "w", encoding="utf-8", newline=""
        ) as handle:
            handle.write(
                f"{pairing.KEY_RESTRICTIONS} ssh-ed25519 AAAAold phone"
                "\rssh-ed25519 AAAAattacker attacker\n"
            )
        status, _ = self.post("/pubkey", PHONE_KEY)
        self.assertEqual(status, 200)
        text = self.read_authorized_keys()
        self.assertNotIn("attacker", text)
        self.assertEqual(text, f"{pairing.KEY_RESTRICTIONS} {PHONE_KEY}\n")

    def test_a_different_key_later_in_the_same_run_is_refused(self):
        status, _ = self.post("/pubkey", PHONE_KEY)
        self.assertEqual(status, 200)
        status, body = self.post("/pubkey", OTHER_KEY)
        self.assertEqual(status, 409)
        self.assertIn(b"restart `cc remote setup`", body)
        self.assertEqual(
            self.read_authorized_keys(), f"{pairing.KEY_RESTRICTIONS} {PHONE_KEY}\n"
        )

    def test_the_same_key_again_in_the_same_run_is_registered_again(self):
        # A phone re-running its setup script sends the key it already registered.
        for attempt in range(2):
            with self.subTest(attempt=attempt):
                status, _ = self.post("/pubkey", PHONE_KEY)
                self.assertEqual(status, 200)
        self.assertEqual(
            self.read_authorized_keys(), f"{pairing.KEY_RESTRICTIONS} {PHONE_KEY}\n"
        )

    def test_missing_or_malformed_content_length_is_411(self):
        for content_length in (None, b"0", b"-1", b"abc"):
            with self.subTest(content_length=content_length):
                data = self.raw_post(content_length)
                self.assertIn(b" 411 ", self.status_line(data))

    def test_body_over_the_maximum_is_413(self):
        content_length = str(pairing_server.MAXIMUM_BODY_LENGTH + 1).encode()
        data = self.raw_post(content_length)
        self.assertIn(b" 413 ", self.status_line(data))

    def test_a_stalled_peer_can_hold_the_server_for_at_most_ten_seconds(self):
        # test_a_stalled_body_is_closed_and_does_not_wedge_the_server overrides this to run quickly; this checks the
        # value that actually ships.
        self.assertEqual(pairing_server.Handler.timeout, 10)

    def test_a_stalled_body_is_closed_and_does_not_wedge_the_server(self):
        original_timeout = pairing_server.Handler.timeout
        pairing_server.Handler.timeout = 1
        try:
            connection = socket.create_connection(("127.0.0.1", self.port), timeout=5)
            try:
                # Promise 50 bytes, send 10, and never send the rest: the server's own socket timeout, not this
                # test, has to be what ends it.
                connection.sendall(
                    b"POST /verify-key HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 50\r\n\r\nssh-ed2551"
                )
                self.assertEqual(connection.recv(200), b"")
            finally:
                connection.close()

            # A single-threaded server that a stalled client can wedge would fail this, not the assertion above.
            connection = self.connection()
            connection.request("POST", "/verify-key", body=PHONE_KEY)
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            response.read()
        finally:
            pairing_server.Handler.timeout = original_timeout


if __name__ == "__main__":
    unittest.main()

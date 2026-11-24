"""The Android client's Java against the server's Python, compiled with a JDK (installCheckPhase provides one).

Pairing codes, commitments and proofs must agree byte for byte, or pairing and every connection fail; Reasons turns
Android's connection errors into the sentences the client shows.
"""

import os
import secrets
import shutil
import subprocess
import tempfile
import unittest

from voxize_remote import pairing

ANDROID = os.environ.get("VOXIZE_REMOTE_ANDROID")
PACKAGE = "dev/flemma/voxize/remote"


@unittest.skipUnless(
    ANDROID and shutil.which("javac"),
    "needs VOXIZE_REMOTE_ANDROID and a JDK (installCheckPhase)",
)
class ClientAgreementTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.classes = tempfile.mkdtemp(prefix="voxize-remote-java.")
        sources = [
            os.path.join(ANDROID, "src", PACKAGE, name)
            for name in ("Pairing.java", "Reasons.java")
        ]
        sources += [
            os.path.join(ANDROID, "tests", name)
            for name in ("PairingAgreement.java", "ReasonsCheck.java")
        ]
        subprocess.run(
            ["javac", "-encoding", "UTF-8", "-d", cls.classes, *sources],
            check=True,
            timeout=300,
        )

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.classes, ignore_errors=True)

    def java(self, main: str, stdin: str = "") -> str:
        completed = subprocess.run(
            ["java", "-cp", self.classes, f"dev.flemma.voxize.remote.{main}"],
            input=stdin,
            capture_output=True,
            text=True,
            timeout=120,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return completed.stdout

    def test_proofs_commitments_and_codes_agree(self):
        cases = [[secrets.token_bytes(32) for _ in range(4)] for _ in range(50)]
        answers = self.java(
            "PairingAgreement",
            "".join(" ".join(part.hex() for part in case) + "\n" for case in cases),
        )
        lines = answers.splitlines()
        self.assertEqual(len(lines), len(cases))
        for (secret, client_nonce, server_nonce, pairing_nonce), line in zip(
            cases, lines
        ):
            self.assertEqual(
                line.split(" "),
                [
                    pairing.server_proof(secret, client_nonce, server_nonce),
                    pairing.client_proof(secret, client_nonce, server_nonce),
                    pairing.commitment(pairing_nonce),
                    pairing.confirmation_code(secret, pairing_nonce).replace(" ", "_"),
                ],
            )

    def test_connection_failures_read_as_sentences(self):
        self.assertIn("checks pass", self.java("ReasonsCheck"))


if __name__ == "__main__":
    unittest.main()

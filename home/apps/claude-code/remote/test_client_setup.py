"""client_setup end to end with fakes: a scripted adb, a scripted console and a fake Voxize Remote control socket."""

import io
import json
import os
import shutil
import socket
import subprocess
import tempfile
import threading
import unittest

import client_setup

SERIAL = "R5CW1234"


class Completed:
    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode, self.stdout, self.stderr = returncode, stdout, stderr


class FakeDevice:
    """Answers adb (and keytool and apksigner) calls the way a device and the tools would; records every call."""

    def __init__(
        self,
        devices=((SERIAL, "device", "model:SM_A546B"),),
        packages=("com.termux", "com.tailscale.ipn"),
        install_results=("Success",),
        failing=(),
        stuck=(),
        keytool_fails=False,
        hardware=None,
    ):
        self.devices = list(devices)
        self.packages = set(packages)
        self.install_results = list(install_results)
        # Shell commands (by prefix) that fail, adb subcommands that never finish.
        self.failing = failing
        self.stuck = stuck
        self.keytool_fails = keytool_fails
        # adb serial → ro.serialno; by default each entry is its own device.
        self.hardware = hardware or {}
        self.locked = False
        self.calls = []
        self.shell_commands = []

    def __call__(
        self, command, capture_output=True, text=True, timeout=None, check=False
    ):
        self.calls.append(command)
        tool = os.path.basename(command[0])
        if tool == "keytool" and self.keytool_fails:
            open(command[command.index("-keystore") + 1], "w").close()
            return Completed(returncode=1, stderr="keytool error: interrupted")
        if tool == "keytool":
            keystore = command[command.index("-keystore") + 1]
            open(keystore, "w").close()
            return Completed()
        if tool == "apksigner":
            open(command[command.index("--out") + 1], "w").close()
            return Completed()
        arguments = command[1:]
        target = arguments[1] if arguments[:1] == ["-s"] else None
        if arguments[:1] == ["-s"]:
            arguments = arguments[2:]
        if arguments[:2] == ["devices", "-l"]:
            lines = ["List of devices attached"] + [
                f"{serial} {state} {description}"
                for serial, state, description in self.devices
            ]
            return Completed(stdout="\n".join(lines) + "\n")
        if arguments[:1] == ["pair"]:
            return Completed(
                stdout="Successfully paired to 192.168.1.10:37123 [guid=adb-x]\n"
            )
        if arguments[:1] == ["connect"]:
            self.devices = [(arguments[1], "device", "model:SM_A546B")]
            return Completed(stdout=f"connected to {arguments[1]}\n")
        if arguments[:1] and arguments[0] in self.stuck:
            raise subprocess.TimeoutExpired(command, timeout)
        if arguments[:1] == ["install"]:
            result = self.install_results.pop(0) if self.install_results else "Success"
            return Completed(
                returncode=0 if result == "Success" else 1, stdout=result + "\n"
            )
        if arguments[:1] == ["shell"]:
            shell = arguments[1]
            self.shell_commands.append(shell)
            if any(shell.startswith(prefix) for prefix in self.failing):
                return Completed(
                    returncode=255,
                    stdout="Exception occurred while executing: SecurityException\n",
                )
            if shell.startswith("pm list packages "):
                package = shell.split()[-1]
                return Completed(
                    stdout=f"package:{package}\n" if package in self.packages else ""
                )
            if shell == "getprop ro.serialno":
                return Completed(stdout=self.hardware.get(target, target) + "\n")
            if shell.startswith("pm clear "):
                return Completed(stdout="Success\n")
            if shell.startswith("dumpsys power"):
                return Completed(stdout="  mWakefulness=Awake\n")
            if shell.startswith("dumpsys window"):
                if self.locked:
                    return Completed(
                        stdout="  mCurrentFocus=Window{1 u0 NotificationShade}\n    isKeyguardShowing=true\n"
                    )
                return Completed(
                    stdout="  mCurrentFocus=Window{2 u0 com.termux/com.termux.app.TermuxActivity}\n"
                    "    isKeyguardShowing=false\n"
                )
            return Completed()
        return Completed()


class FakeConsole:
    def __init__(self, answers=(), waiting=()):
        self.answers = list(answers)
        self.waiting = list(waiting)
        self.said = []
        self.asked = []

    def say(self, text=""):
        self.said.append(text)

    def step(self, number, title):
        self.said.append(f"[{number}/{client_setup.STEPS}] {title}")

    def ask(self, prompt):
        self.asked.append(prompt)
        return self.answers.pop(0) if self.answers else ""

    def key_waiting(self, seconds):
        return self.waiting.pop(0) if self.waiting else None


class FakeVoxizeServer:
    """The control socket's pair and status commands, as voxize-remote serve speaks them."""

    def __init__(self, path, code="123 456", connects=True):
        self.path, self.code, self.connects = path, code, connects
        self.typed = []
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(path)
        self.listener.listen()
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self):
        while True:
            try:
                connection, _ = self.listener.accept()
            except OSError:
                return
            with connection, connection.makefile("rwb", buffering=0) as stream:
                command = stream.readline().strip()
                if command == b"status":
                    stream.write(
                        json.dumps(
                            {"client": "samsung SM-A546B" if self.connects else None}
                        ).encode()
                        + b"\n"
                    )
                elif command == b"pair":
                    stream.write(b'{"event": "open", "seconds": 120}\n')
                    stream.write(
                        b'{"event": "code_requested", "device": "samsung SM-A546B", "node": "stans-a54"}\n'
                    )
                    typed = stream.readline().decode().strip()
                    self.typed.append(typed)
                    if typed.replace(" ", "") == self.code.replace(" ", ""):
                        stream.write(
                            b'{"event": "paired", "device_id": "abc", "device": "samsung SM-A546B"}\n'
                        )
                    else:
                        stream.write(b'{"event": "rejected", "reason": "wrong code"}\n')
                        stream.write(b'{"event": "expired"}\n')

    def close(self):
        self.listener.close()


class ClientSetupTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.mkdtemp(prefix="client-setup-test.")
        self.addCleanup(shutil.rmtree, self.directory, True)
        self.control = os.path.join(self.directory, "voxize-remote.sock")
        self.signing = os.path.join(self.directory, "signing")
        client_setup.CONNECT_CHECK_SECONDS = 2
        client_setup.DEVICE_POLL_SECONDS = 0

    def run_setup(self, device, console, voxize=None, key_registered=lambda: True):
        voxize = voxize or FakeVoxizeServer(self.control)
        self.addCleanup(voxize.close)
        result = client_setup.run(
            "/fake/adb",
            "/fake/apksigner",
            "/fake/keytool",
            "/fake/client.apk",
            self.control,
            "stan-latitude.example.ts.net",
            7223,
            "curl -sS 100.64.0.7:8081/cc | sh",
            key_registered,
            console=console,
            runner=device,
            signing_directory=self.signing,
        )
        return result, voxize

    def test_usb_end_to_end(self):
        device = FakeDevice()
        console = FakeConsole(answers=["", "123 456"])
        result, voxize = self.run_setup(device, console)
        self.assertTrue(result)
        self.assertEqual(voxize.typed, ["123 456"])
        shell = device.shell_commands
        # Installed signed with this machine's key, made once, private.
        self.assertTrue(os.path.exists(os.path.join(self.signing, "voxize-remote.p12")))
        self.assertEqual(oct(os.stat(self.signing).st_mode & 0o777), "0o700")
        installs = [call for call in device.calls if "install" in call]
        self.assertTrue(installs and installs[0][-1].endswith("voxize-remote.apk"))
        # Every permission granted, the earlier pairing cleared first.
        for expected in (
            "pm clear dev.flemma.voxize.remote",
            "pm grant dev.flemma.voxize.remote android.permission.RECORD_AUDIO",
            "pm grant dev.flemma.voxize.remote android.permission.POST_NOTIFICATIONS",
            "appops set dev.flemma.voxize.remote SYSTEM_ALERT_WINDOW allow",
            "appops set dev.flemma.voxize.remote GET_USAGE_STATS allow",
        ):
            self.assertIn(expected, shell)
        self.assertLess(
            shell.index("pm clear dev.flemma.voxize.remote"),
            shell.index(
                "pm grant dev.flemma.voxize.remote android.permission.RECORD_AUDIO"
            ),
        )
        # The bootstrap typed into Termux, spaces escaped for input text.
        self.assertIn("input text 'curl%s-sS%s100.64.0.7:8081/cc%s|%ssh'", shell)
        self.assertIn("input keyevent ENTER", shell)
        # Pairing started on the client with this server's name and port; then armed as ssh cc will.
        self.assertIn(
            "am start -n dev.flemma.voxize.remote/.MainActivity --es server stan-latitude.example.ts.net "
            "--ei port 7223 --ez pair true",
            shell,
        )
        self.assertIn("am start -n dev.flemma.voxize.remote/.ArmActivity", shell)
        self.assertIn("The client is connected over Tailscale.", console.said)
        # Connected: the device is handed back to Termux, and the shell to use is a new one (it has the settings).
        self.assertEqual(shell[-1], "am start -n com.termux/.app.TermuxActivity")
        self.assertTrue(
            any(
                line.startswith("Done. On the phone, in a new Termux session")
                for line in console.said
            )
        )
        self.assertEqual(
            [line for line in console.said if line.startswith("[")],
            [
                "[1/5] The phone",
                "[2/5] Voxize Remote on the phone",
                "[3/5] ssh cc in Termux",
                "[4/5] Pairing Voxize Remote with this machine",
                "[5/5] Checking the connection",
            ],
        )
        # USB: Wireless debugging is left alone.
        self.assertNotIn("settings put global adb_wifi_enabled 0", shell)

    def test_wireless_debugging_is_switched_off_afterwards(self):
        device = FakeDevice(devices=())
        console = FakeConsole(
            answers=[
                "192.168.1.10:37123",
                "482913",
                "192.168.1.10:40601",
                "",
                "123 456",
            ],
            waiting=["w"],
        )
        result, _ = self.run_setup(device, console)
        self.assertTrue(result)
        self.assertIn(
            ["/fake/adb", "pair", "192.168.1.10:37123", "482913"], device.calls
        )
        self.assertIn(["/fake/adb", "connect", "192.168.1.10:40601"], device.calls)
        self.assertIn("settings put global adb_wifi_enabled 0", device.shell_commands)
        self.assertIn(["/fake/adb", "disconnect", "192.168.1.10:40601"], device.calls)

    def test_skipping_the_device(self):
        result, _ = self.run_setup(FakeDevice(devices=()), FakeConsole(waiting=["s"]))
        self.assertFalse(result)

    def test_a_client_signed_with_another_key_is_replaced_on_request(self):
        device = FakeDevice(
            install_results=[
                "Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]",
                "Success",
            ]
        )
        console = FakeConsole(answers=["y", "", "123 456"])
        result, _ = self.run_setup(device, console)
        self.assertTrue(result)
        self.assertIn(
            ["/fake/adb", "-s", SERIAL, "uninstall", "dev.flemma.voxize.remote"],
            device.calls,
        )

    def test_a_newer_client_after_a_rollback_is_replaced_on_request(self):
        device = FakeDevice(
            install_results=[
                "Failure [INSTALL_FAILED_VERSION_DOWNGRADE: Downgrade detected]",
                "Success",
            ]
        )
        console = FakeConsole(answers=["y", "", "123 456"])
        result, _ = self.run_setup(device, console)
        self.assertTrue(result)
        self.assertIn(
            "The Voxize Remote on the phone is newer than this one (this machine rolled back?), so it cannot "
            "be updated in place.",
            console.said,
        )
        self.assertIn(
            ["/fake/adb", "-s", SERIAL, "uninstall", "dev.flemma.voxize.remote"],
            device.calls,
        )

    def test_a_missing_termux_is_asked_for(self):
        device = FakeDevice(packages=("com.tailscale.ipn",))
        asked = []

        class InstallingConsole(FakeConsole):
            def ask(self, prompt):
                asked.append(prompt)
                if "Termux is not installed" in prompt:
                    device.packages.add("com.termux")
                return super().ask(prompt)

        result, _ = self.run_setup(
            device, InstallingConsole(answers=["", "", "123 456"])
        )
        self.assertTrue(result)
        self.assertTrue(any("Termux is not installed" in prompt for prompt in asked))

    def test_a_wrong_code_ends_in_a_clear_error(self):
        device = FakeDevice()
        console = FakeConsole(answers=["", "000 000"])
        with self.assertRaises(client_setup.SetupError) as raised:
            self.run_setup(device, console)
        self.assertIn("pairing window closed", str(raised.exception))
        self.assertIn(
            "Voxize Remote's screen on the phone says why", str(raised.exception)
        )
        self.assertIn("Not paired: wrong code. The phone can try again.", console.said)
        # Said as soon as the client was asked, so a client that never reaches the server is not two silent minutes.
        self.assertIn(
            "Asked Voxize Remote to pair; it shows a six-digit code once it reaches "
            "stan-latitude.example.ts.net.",
            console.said,
        )

    def test_no_connection_explains_the_split_tunnel(self):
        device = FakeDevice()
        console = FakeConsole(answers=["", "123 456"])
        voxize = FakeVoxizeServer(self.control, connects=False)
        result, _ = self.run_setup(device, console, voxize=voxize)
        self.assertTrue(result)
        self.assertTrue(any("Split tunneling" in line for line in console.said))
        # The client's screen, which says what is wrong, stays in front.
        self.assertNotEqual(
            device.shell_commands[-1], "am start -n com.termux/.app.TermuxActivity"
        )

    def test_wireless_debugging_found_by_mdns_is_switched_off_too(self):
        # adb connects a device paired before under its mDNS service name, which has no colon.
        serial = "adb-R5CW1234-AbCdEf._adb-tls-connect._tcp"
        device = FakeDevice(devices=((serial, "device", "model:SM_A546B"),))
        result, _ = self.run_setup(device, FakeConsole(answers=["", "123 456"]))
        self.assertTrue(result)
        self.assertIn("settings put global adb_wifi_enabled 0", device.shell_commands)
        self.assertIn(["/fake/adb", "disconnect", serial], device.calls)

    def test_a_failed_switch_off_says_so(self):
        device = FakeDevice(
            devices=(("192.168.1.10:40601", "device", "model:SM_A546B"),),
            failing=("settings put global adb_wifi_enabled",),
        )
        console = FakeConsole(answers=["", "123 456"])
        self.run_setup(device, console)
        self.assertNotIn("Wireless debugging is off again.", console.said)
        self.assertTrue(
            any(
                line.startswith("Could not switch Wireless debugging off")
                for line in console.said
            )
        )

    def test_nothing_is_typed_on_a_locked_screen(self):
        # Keys sent to a lock screen are a wrong PIN; the setup waits for Termux to be in front.
        device = FakeDevice()
        device.locked = True

        class UnlockingConsole(FakeConsole):
            def ask(self, prompt):
                if any(
                    line.startswith("Not typed: The phone is locked")
                    for line in self.said
                ):
                    device.locked = False
                return super().ask(prompt)

        console = UnlockingConsole(answers=["", "", "123 456"])
        result, _ = self.run_setup(device, console)
        self.assertTrue(result)
        typed = [
            index
            for index, command in enumerate(device.shell_commands)
            if command.startswith("input text ")
        ]
        self.assertEqual(len(typed), 1)
        self.assertIn(
            "Not typed: The phone is locked: unlock it (Termux is open behind the lock screen).",
            console.said,
        )

    def test_a_refused_permission_stops_the_setup(self):
        device = FakeDevice(
            failing=(
                "pm grant dev.flemma.voxize.remote android.permission.RECORD_AUDIO",
            )
        )
        with self.assertRaisesRegex(
            client_setup.SetupError,
            "could not grant Voxize Remote android.permission.RECORD_AUDIO",
        ):
            self.run_setup(device, FakeConsole(answers=["", "123 456"]))

    def test_a_stuck_adb_command_is_a_clear_error(self):
        device = FakeDevice(stuck=("install",))
        with self.assertRaises(client_setup.SetupError) as raised:
            self.run_setup(device, FakeConsole(answers=["", "123 456"]))
        message = str(raised.exception)
        self.assertTrue(message.startswith("adb install -r "), message)
        self.assertIn("is the phone showing a question on its screen?", message)
        self.assertNotIn(SERIAL, message)

    def test_an_interrupted_key_leaves_nothing_behind(self):
        with self.assertRaises(client_setup.SetupError):
            self.run_setup(
                FakeDevice(keytool_fails=True), FakeConsole(answers=["", "123 456"])
            )
        self.assertEqual(os.listdir(self.signing), [])

    def test_the_end_of_input_ends_the_setup(self):
        console = client_setup.Console(stream=io.StringIO(), keyboard=io.StringIO(""))
        with self.assertRaisesRegex(client_setup.SetupError, "no more input"):
            console.ask("Which phone? ")

    def test_one_device_on_the_cable_and_on_wifi_is_one_device(self):
        # Wireless debugging left connected, then the cable plugged in: adb lists the device twice.
        wifi = "192.168.1.10:45657"
        device = FakeDevice(
            devices=(
                (wifi, "device", "model:SM_A546B"),
                (SERIAL, "device", "model:SM_A546B"),
            ),
            hardware={wifi: SERIAL, SERIAL: SERIAL},
        )
        console = FakeConsole(answers=["", "123 456"])
        result, _ = self.run_setup(device, console)
        self.assertTrue(result)
        self.assertNotIn("Which phone? ", console.asked)
        self.assertIn("Found SM A546B.", console.said)
        # The cable's serial is used, so nothing switches Wireless debugging off.
        self.assertIn(
            ["/fake/adb", "-s", SERIAL, "install", "-r"],
            [call[:5] for call in device.calls],
        )
        self.assertNotIn(
            "settings put global adb_wifi_enabled 0", device.shell_commands
        )

    def test_two_devices_are_asked_about(self):
        device = FakeDevice(
            devices=(
                (SERIAL, "device", "model:SM_A546B"),
                ("R9OTHER", "device", "model:Pixel_8"),
            )
        )
        console = FakeConsole(answers=["2", "", "123 456"])
        result, _ = self.run_setup(device, console)
        self.assertTrue(result)
        self.assertIn("Which phone? ", console.asked)
        self.assertIn(
            ["/fake/adb", "-s", "R9OTHER", "install", "-r"],
            [call[:5] for call in device.calls],
        )

    def test_typed_text(self):
        self.assertEqual(
            client_setup.typed_text("curl -sS a:1/cc | sh"),
            "'curl%s-sS%sa:1/cc%s|%ssh'",
        )
        with self.assertRaises(ValueError):
            client_setup.typed_text("echo 'x'")


if __name__ == "__main__":
    unittest.main()

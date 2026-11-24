"""client_setup end to end with fakes: a scripted adb, a scripted console and a stand-in for voxize-remote setup-client."""

import io
import subprocess
import unittest

import client_setup

SERIAL = "R5CW1234"
VOXIZE_REMOTE = "/fake/voxize-remote"


class Completed:
    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode, self.stdout, self.stderr = returncode, stdout, stderr


class FakeDevice:
    """Answers adb calls the way a device would; records every call."""

    def __init__(
        self,
        devices=((SERIAL, "device", "model:SM_A546B"),),
        packages=("com.termux", "com.tailscale.ipn"),
        failing=(),
        stuck=(),
        hardware=None,
    ):
        self.devices = list(devices)
        self.packages = set(packages)
        # Shell commands (by prefix) that fail, adb subcommands that never finish.
        self.failing = failing
        self.stuck = stuck
        # adb serial → ro.serialno; by default each entry is its own device.
        self.hardware = hardware or {}
        self.locked = False
        self.calls = []
        self.shell_commands = []

    def __call__(
        self, command, capture_output=True, text=True, timeout=None, check=False
    ):
        self.calls.append(command)
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


class FakeLauncher:
    """voxize-remote setup-client: records how it was run, exits with ``status`` (0 connected, 2 not, 1 failed)."""

    def __init__(self, status=0):
        self.status = status
        self.commands = []

    def __call__(self, command, check=False):
        self.commands.append(command)
        return Completed(returncode=self.status)


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


class ClientSetupTest(unittest.TestCase):
    def setUp(self):
        client_setup.DEVICE_POLL_SECONDS = 0

    def run_setup(self, device, console, launcher=None, key_registered=lambda: True):
        launcher = launcher or FakeLauncher()
        result = client_setup.run(
            "/fake/adb",
            VOXIZE_REMOTE,
            "stan-latitude.example.ts.net",
            7223,
            "curl -sS 100.64.0.7:8081/cc | sh",
            key_registered,
            console=console,
            runner=device,
            launcher=launcher,
        )
        return result, launcher

    def test_usb_end_to_end(self):
        device = FakeDevice()
        console = FakeConsole(answers=[""])
        result, launcher = self.run_setup(device, console)
        self.assertTrue(result)
        shell = device.shell_commands
        # The bootstrap typed into Termux, spaces escaped for input text.
        self.assertIn("input text 'curl%s-sS%s100.64.0.7:8081/cc%s|%ssh'", shell)
        self.assertIn("input keyevent ENTER", shell)
        # Then Voxize's own setup, on this device, for this server's name and port.
        self.assertEqual(
            launcher.commands,
            [
                [
                    VOXIZE_REMOTE,
                    "setup-client",
                    "--serial",
                    SERIAL,
                    "--server",
                    "stan-latitude.example.ts.net",
                    "--port",
                    "7223",
                    "--adb",
                    "/fake/adb",
                ]
            ],
        )
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
            ["[1/3] The phone", "[2/3] ssh cc in Termux", "[3/3] Voxize Remote"],
        )
        # USB: Wireless debugging is left alone.
        self.assertNotIn("settings put global adb_wifi_enabled 0", shell)

    def test_no_connection_leaves_the_clients_screen_up(self):
        # setup-client said why (2: paired, not connected); its screen on the device says it too.
        device = FakeDevice()
        console = FakeConsole(answers=[""])
        result, _ = self.run_setup(device, console, launcher=FakeLauncher(status=2))
        self.assertTrue(result)
        self.assertNotEqual(
            device.shell_commands[-1], "am start -n com.termux/.app.TermuxActivity"
        )
        self.assertTrue(
            any(
                line.startswith("Done, apart from the connection above")
                for line in console.said
            )
        )

    def test_a_failed_voxize_setup_is_an_error(self):
        with self.assertRaisesRegex(client_setup.SetupError, "did not finish"):
            self.run_setup(
                FakeDevice(), FakeConsole(answers=[""]), launcher=FakeLauncher(status=1)
            )

    def test_wireless_debugging_is_switched_off_afterwards(self):
        device = FakeDevice(devices=())
        console = FakeConsole(
            answers=["192.168.1.10:37123", "482913", "192.168.1.10:40601", ""],
            waiting=["w"],
        )
        result, launcher = self.run_setup(device, console)
        self.assertTrue(result)
        self.assertIn(
            ["/fake/adb", "pair", "192.168.1.10:37123", "482913"], device.calls
        )
        self.assertIn(["/fake/adb", "connect", "192.168.1.10:40601"], device.calls)
        self.assertEqual(launcher.commands[0][3], "192.168.1.10:40601")
        self.assertIn("settings put global adb_wifi_enabled 0", device.shell_commands)
        self.assertIn(["/fake/adb", "disconnect", "192.168.1.10:40601"], device.calls)

    def test_wireless_debugging_is_switched_off_after_a_failure_too(self):
        device = FakeDevice(
            devices=(("192.168.1.10:40601", "device", "model:SM_A546B"),)
        )
        with self.assertRaises(client_setup.SetupError):
            self.run_setup(
                device, FakeConsole(answers=[""]), launcher=FakeLauncher(status=1)
            )
        self.assertIn("settings put global adb_wifi_enabled 0", device.shell_commands)

    def test_skipping_the_device(self):
        result, launcher = self.run_setup(
            FakeDevice(devices=()), FakeConsole(waiting=["s"])
        )
        self.assertFalse(result)
        self.assertEqual(launcher.commands, [])

    def test_a_missing_termux_is_asked_for(self):
        device = FakeDevice(packages=("com.tailscale.ipn",))
        asked = []

        class InstallingConsole(FakeConsole):
            def ask(self, prompt):
                asked.append(prompt)
                if "Termux is not installed" in prompt:
                    device.packages.add("com.termux")
                return super().ask(prompt)

        result, _ = self.run_setup(device, InstallingConsole(answers=["", ""]))
        self.assertTrue(result)
        self.assertTrue(any("Termux is not installed" in prompt for prompt in asked))

    def test_wireless_debugging_found_by_mdns_is_switched_off_too(self):
        # adb connects a device paired before under its mDNS service name, which has no colon.
        serial = "adb-R5CW1234-AbCdEf._adb-tls-connect._tcp"
        device = FakeDevice(devices=((serial, "device", "model:SM_A546B"),))
        result, _ = self.run_setup(device, FakeConsole(answers=[""]))
        self.assertTrue(result)
        self.assertIn("settings put global adb_wifi_enabled 0", device.shell_commands)
        self.assertIn(["/fake/adb", "disconnect", serial], device.calls)

    def test_a_failed_switch_off_says_so(self):
        device = FakeDevice(
            devices=(("192.168.1.10:40601", "device", "model:SM_A546B"),),
            failing=("settings put global adb_wifi_enabled",),
        )
        console = FakeConsole(answers=[""])
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

        console = UnlockingConsole(answers=["", ""])
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

    def test_a_stuck_adb_command_is_a_clear_error(self):
        device = FakeDevice(stuck=("shell",))
        with self.assertRaises(client_setup.SetupError) as raised:
            self.run_setup(device, FakeConsole(answers=[""]))
        message = str(raised.exception)
        self.assertTrue(message.startswith("adb shell "), message)
        self.assertIn("is the phone showing a question on its screen?", message)
        self.assertNotIn(SERIAL, message)

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
        console = FakeConsole(answers=[""])
        result, launcher = self.run_setup(device, console)
        self.assertTrue(result)
        self.assertNotIn("Which phone? ", console.asked)
        self.assertIn("Found SM A546B.", console.said)
        # The cable's serial is used, so nothing switches Wireless debugging off.
        self.assertEqual(launcher.commands[0][3], SERIAL)
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
        console = FakeConsole(answers=["2", ""])
        result, launcher = self.run_setup(device, console)
        self.assertTrue(result)
        self.assertIn("Which phone? ", console.asked)
        self.assertEqual(launcher.commands[0][3], "R9OTHER")

    def test_typed_text(self):
        self.assertEqual(
            client_setup.typed_text("curl -sS a:1/cc | sh"),
            "'curl%s-sS%sa:1/cc%s|%ssh'",
        )
        with self.assertRaises(ValueError):
            client_setup.typed_text("echo 'x'")


if __name__ == "__main__":
    unittest.main()

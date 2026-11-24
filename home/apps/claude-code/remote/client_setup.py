"""`cc remote setup`'s client half: Termux's ssh cc and the Voxize Remote client, set up over adb.

With the device on a USB cable (or Wireless debugging), this types the Termux bootstrap, then hands the device to
`voxize-remote setup-client` (Voxize's own: it installs the release's client, allows it, pairs it with this machine's
server and checks it connects), and switches Wireless debugging off again. What is left on the device are Android's own
prompts: allowing USB debugging, and the fingerprint test Termux's setup asks for.

Every outside effect goes through Adb, Console and the control socket, so the tests drive the whole flow with fakes.
"""

import os
import select
import shlex
import subprocess
import sys
import time

TERMUX_PACKAGE = "com.termux"
TAILSCALE_PACKAGE = "com.tailscale.ipn"
DEVICE_POLL_SECONDS = 1.0
KEY_REGISTRATION_SECONDS = 600.0
STEPS = 3


class SetupError(Exception):
    """A step that cannot go on; the message says what to do."""


class Console:
    """Stan's terminal. Lines are flushed; answers are read with anything typed ahead thrown away."""

    def __init__(self, stream=sys.stdout, keyboard=sys.stdin):
        self.stream = stream
        self.keyboard = keyboard

    def say(self, text=""):
        print(text, file=self.stream, flush=True)

    def step(self, number, title):
        """A heading for each of the steps, bold on a terminal."""
        heading = f"[{number}/{STEPS}] {title}"
        if self.stream.isatty() and not os.environ.get("NO_COLOR"):
            heading = f"\033[1m{heading}\033[0m"
        print(f"\n{heading}", file=self.stream, flush=True)

    def ask(self, prompt):
        if self.keyboard.isatty():
            import termios

            termios.tcflush(self.keyboard, termios.TCIFLUSH)
        self.stream.write(prompt)
        self.stream.flush()
        return self._line()

    def key_waiting(self, seconds):
        """A line typed while waiting, or None after ``seconds``."""
        ready, _, _ = select.select([self.keyboard], [], [], seconds)
        if not ready:
            return None
        return self._line()

    def _line(self):
        line = self.keyboard.readline()
        if not line:
            raise SetupError("the terminal has no more input to answer with")
        return line.strip()


class Adb:
    def __init__(self, executable, serial=None, runner=subprocess.run):
        self.executable = executable
        self.serial = serial
        self.runner = runner

    def run(self, *arguments, timeout=120):
        command = (
            [self.executable]
            + (["-s", self.serial] if self.serial else [])
            + list(arguments)
        )
        completed = self.runner(
            command, capture_output=True, text=True, timeout=timeout, check=False
        )
        return completed.returncode, (completed.stdout or "") + (completed.stderr or "")

    def shell(self, command, timeout=60):
        """One device shell command line (adb joins its arguments into one anyway)."""
        return self.run("shell", command, timeout=timeout)

    def devices(self):
        """[(serial, state, description)] from `adb devices -l`; state is device, unauthorized, offline or no."""
        status, output = Adb(self.executable, runner=self.runner).run(
            "devices", "-l", timeout=15
        )
        if status != 0:
            raise SetupError(f"adb cannot list devices: {output.strip()}")
        found = []
        for line in output.splitlines()[1:]:
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("*"):
                found.append((parts[0], parts[1], " ".join(parts[2:])))
        return found

    def has_package(self, package):
        status, output = self.shell(f"pm list packages {shlex.quote(package)}")
        if status != 0:
            raise SetupError(f"cannot list the phone's apps: {output.strip()}")
        return f"package:{package}" in output.split()


def typed_text(text):
    """`input text` argument for ``text``: spaces as %s, the whole quoted for the device's shell."""
    if "'" in text or "%" in text:
        raise ValueError(f"cannot type {text!r} with input text")
    return "'" + text.replace(" ", "%s") + "'"


# ── finding the device ──


def over_wifi(serial):
    """Wireless debugging's serials: IP:port after adb connect, an mDNS service name when adb found the device itself."""
    return ":" in serial or "._adb-tls-connect." in serial


def distinct_devices(adb, ready):
    """One entry per device: a device on the cable and on Wireless debugging at once is listed twice by adb (the
    cable is kept). Devices tell themselves apart by their hardware serial."""
    chosen = {}
    for entry in ready:
        serial = entry[0]
        _, hardware = Adb(adb.executable, serial=serial, runner=adb.runner).shell(
            "getprop ro.serialno", timeout=15
        )
        identity = hardware.strip() or serial
        if (
            identity not in chosen
            or over_wifi(chosen[identity][0])
            and not over_wifi(serial)
        ):
            chosen[identity] = entry
    return list(chosen.values())


def find_device(adb, console):
    """The serial of the device to set up, and whether it came over Wireless debugging; None to skip it."""
    console.say(
        "Connect the phone with a USB cable (Developer options → USB debugging on) and allow this computer when"
    )
    console.say(
        "it asks, or type w and Enter to use Wireless debugging, or s and Enter to skip the phone (SSH only)."
    )
    console.say(
        "No Developer options? Settings → About phone → Software information → tap Build number seven times."
    )
    told = set()
    while True:
        devices = adb.devices()
        ready = [device for device in devices if device[1] == "device"]
        if len(ready) > 1:
            ready = distinct_devices(adb, ready)
        if len(ready) == 1:
            serial, _, description = ready[0]
            console.say(f"Found {model_name(description) or serial}.")
            return serial, over_wifi(serial)
        if len(ready) > 1:
            serial = choose_device(ready, console)
            return serial, over_wifi(serial)
        for serial, state, description in devices:
            if state in told:
                continue
            if state == "unauthorized":
                console.say("On the phone, allow USB debugging for this computer.")
            elif state == "no":
                console.say(
                    f"adb may not use {serial} ({state} {description}); unplug the cable and plug it in again."
                )
            elif state == "offline":
                console.say(
                    f"{serial} is offline; unplug the cable and plug it in again."
                )
            else:
                continue
            told.add(state)
        answer = console.key_waiting(DEVICE_POLL_SECONDS)
        if answer is None:
            continue
        if answer.lower() == "s":
            return None
        if answer.lower() == "w":
            serial = wireless_connect(adb, console)
            if serial:
                return serial, True


def model_name(description):
    for part in description.split():
        if part.startswith("model:"):
            return part.split(":", 1)[1].replace("_", " ")
    return ""


def choose_device(ready, console):
    for number, (serial, _, description) in enumerate(ready, 1):
        console.say(f"  {number}. {model_name(description) or serial} ({serial})")
    while True:
        answer = console.ask("Which phone? ")
        if answer.isdigit() and 1 <= int(answer) <= len(ready):
            return ready[int(answer) - 1][0]


def wireless_connect(adb, console):
    """adb pair, then adb connect; the serial, or None when Stan gives up."""
    console.say(
        "On the phone: Developer options → Wireless debugging → Pair device with pairing code."
    )
    pairing_address = console.ask(
        "Pairing IP address and port (as shown there, like 192.168.1.10:37123): "
    )
    code = console.ask("Pairing code: ")
    if not pairing_address or not code:
        return None
    status, output = adb.run("pair", pairing_address, code, timeout=30)
    if status != 0 or "Successfully paired" not in output:
        console.say(f"Pairing failed: {output.strip()}")
        return None
    console.say(
        'Paired. Now the address under "IP address & Port" on the Wireless debugging screen.'
    )
    connect_address = console.ask("IP address and port: ")
    status, output = adb.run("connect", connect_address, timeout=30)
    if status != 0 or "connected" not in output:
        console.say(f"Connecting failed: {output.strip()}")
        return None
    return connect_address


# ── Termux ──


def termux_not_ready(adb):
    """Why typing now would not reach Termux's prompt (a locked or dark screen, another app), or None."""
    _, power = adb.shell("dumpsys power | grep mWakefulness=")
    if "mWakefulness=" in power and "mWakefulness=Awake" not in power:
        return "The phone's screen is off: wake it and unlock it."
    _, window = adb.shell(
        "dumpsys window | grep -E 'mCurrentFocus=|isKeyguardShowing='"
    )
    focus = next(
        (line.strip() for line in window.splitlines() if "mCurrentFocus=" in line), ""
    )
    if "isKeyguardShowing=true" in window or "NotificationShade" in focus:
        return "The phone is locked: unlock it (Termux is open behind the lock screen)."
    if f" {TERMUX_PACKAGE}/" not in focus:
        return "Termux is not in front on the phone: open it again."
    return None


def run_termux_bootstrap(adb, console, bootstrap_command, key_registered):
    """Types the bootstrap into Termux once Stan says it shows a prompt; waits for Termux's SSH key.

    Nothing is typed unless Termux has the focus on an unlocked screen: keys sent to a lock screen are a wrong PIN.
    """
    adb.shell("input keyevent KEYCODE_WAKEUP")
    adb.shell("am start -n com.termux/.app.TermuxActivity")
    console.say(
        "Termux is open on the phone. It must show its shell prompt (leave any ssh cc session first)."
    )
    while True:
        answer = console.ask(
            "Press Enter to have the setup command typed into Termux, or s and Enter to type it yourself: "
        )
        if answer.lower() == "s":
            console.say(f"In Termux, run:  {bootstrap_command}")
            break
        problem = termux_not_ready(adb)
        if problem is None:
            adb.shell(f"input text {typed_text(bootstrap_command)}")
            adb.shell("input keyevent ENTER")
            console.say(
                "Typed it. Follow Termux on the phone (it may ask for your fingerprint once)."
            )
            break
        console.say(f"Not typed: {problem}")
    deadline = time.monotonic() + KEY_REGISTRATION_SECONDS
    while not key_registered():
        if time.monotonic() > deadline:
            raise SetupError(
                "the phone's SSH key never arrived; run the command in Termux and try again"
            )
        time.sleep(0.5)


# ── the whole flow ──


def command_text(command):
    """A failed command for a message: the tool's name, then its arguments without the device serial."""
    arguments = [str(part) for part in command[1:]]
    if arguments[:1] == ["-s"]:
        arguments = arguments[2:]
    return " ".join([os.path.basename(str(command[0]))] + arguments)


def switch_off_wireless_debugging(adb, adb_executable, runner, serial, console):
    try:
        status, output = adb.shell("settings put global adb_wifi_enabled 0", timeout=15)
        Adb(adb_executable, runner=runner).run("disconnect", serial, timeout=15)
    except (subprocess.TimeoutExpired, OSError) as error:
        status, output = 1, str(error)
    if status == 0:
        console.say("Wireless debugging is off again.")
    else:
        console.say(
            f"Could not switch Wireless debugging off ({output.strip() or 'no answer'}); switch it off on the "
            "phone: Developer options → Wireless debugging."
        )


def run(
    adb_executable,
    voxize_remote,
    server_name,
    port,
    bootstrap_command,
    key_registered,
    console=None,
    runner=subprocess.run,
    launcher=subprocess.run,
):
    """The client half of `cc remote setup`; False when Stan skipped it. SetupError says what went wrong.

    ``runner`` runs adb (its output captured); ``launcher`` runs `voxize-remote setup-client` on this terminal.
    """
    try:
        return _run(
            adb_executable,
            voxize_remote,
            server_name,
            port,
            bootstrap_command,
            key_registered,
            console or Console(),
            runner,
            launcher,
        )
    except subprocess.TimeoutExpired as error:
        raise SetupError(
            f"{command_text(error.cmd)} did not finish in {error.timeout:.0f} seconds; is the phone "
            "showing a question on its screen?"
        ) from None
    except OSError as error:
        raise SetupError(str(error)) from None


def _run(
    adb_executable,
    voxize_remote,
    server_name,
    port,
    bootstrap_command,
    key_registered,
    console,
    runner,
    launcher,
):
    adb = Adb(adb_executable, runner=runner)
    console.step(1, "The phone")
    found = find_device(adb, console)
    if found is None:
        return False
    serial, wireless = found
    adb = Adb(adb_executable, serial=serial, runner=runner)
    try:
        for package, name, where in (
            (TERMUX_PACKAGE, "Termux", "F-Droid (the Google Play build is outdated)"),
            (
                TAILSCALE_PACKAGE,
                "Tailscale",
                "Google Play or F-Droid, signed in to this machine's tailnet",
            ),
        ):
            while not adb.has_package(package):
                console.ask(
                    f"{name} is not installed on the phone. Install it from {where}, then press Enter: "
                )

        console.step(2, "ssh cc in Termux")
        run_termux_bootstrap(adb, console, bootstrap_command, key_registered)
        console.say("ssh cc is set up.")

        console.step(3, "Voxize Remote")
        # Voxize's own setup: install, allow, pair (Stan types the code here) and check the connection. It talks to
        # Stan on this terminal itself; 0 means connected, 2 paired but not connected (it said why), 1 failed.
        result = launcher(
            [
                voxize_remote,
                "setup-client",
                "--serial",
                serial,
                "--server",
                server_name,
                "--port",
                str(int(port)),
                "--adb",
                adb_executable,
            ],
            check=False,
        )
        if result.returncode not in (0, 2):
            raise SetupError(
                "voxize-remote setup-client did not finish; the lines above say why"
            )
        connected = result.returncode == 0
        if connected:
            # Termux is where Stan goes next; without a connection the client's screen stays up to say why.
            adb.shell("am start -n com.termux/.app.TermuxActivity")
    finally:
        if wireless:
            switch_off_wireless_debugging(adb, adb_executable, runner, serial, console)
    console.say("")
    # The shell that ran the bootstrap predates its settings (the fingerprint unlock): ssh cc wants a new one.
    new_session = "in a new Termux session (swipe in from the left edge, New session)"
    console.say(
        f"Done. On the phone, {new_session}: ssh cc, open a session, tap the floating microphone and talk."
        if connected
        else f"Done, apart from the connection above. Once it is fixed, {new_session}: ssh cc."
    )
    if not wireless:
        console.say(
            "Nothing needs USB debugging any more: switch it off in Developer options if you like."
        )
    return True

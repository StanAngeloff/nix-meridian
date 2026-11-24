"""`cc remote setup`'s client half: the Voxize Remote client and Termux's ssh cc, set up over adb.

With the device on a USB cable (or Wireless debugging), this installs the client signed with this machine's key, grants
every permission it needs, types the Termux bootstrap, pairs the client with the Voxize Remote server (Stan types the
code the client shows) and checks the client connects. What is left on the device are Android's own prompts: allowing
USB debugging, and the fingerprint test Termux's setup asks for.

Every outside effect goes through Adb, Console and the control socket, so the tests drive the whole flow with fakes.
"""

import json
import os
import select
import shlex
import socket
import subprocess
import sys
import tempfile
import time

CLIENT_PACKAGE = "dev.flemma.voxize.remote"
TERMUX_PACKAGE = "com.termux"
TAILSCALE_PACKAGE = "com.tailscale.ipn"
GRANTED_PERMISSIONS = (
    "android.permission.RECORD_AUDIO",
    "android.permission.POST_NOTIFICATIONS",
)
# appops: "Display over other apps" for the floating button, Usage access so it shows only over Termux.
ALLOWED_OPERATIONS = ("SYSTEM_ALERT_WINDOW", "GET_USAGE_STATS")
SIGNING_DIRECTORY = os.path.expanduser("~/.local/share/voxize-remote/signing")
KEYSTORE_NAME = "voxize-remote.p12"
KEY_ALIAS = "voxize-remote"
DEVICE_POLL_SECONDS = 1.0
KEY_REGISTRATION_SECONDS = 600.0
CONNECT_CHECK_SECONDS = 20.0
STEPS = 5


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

    def checked_shell(self, command, what):
        """A device command that must work; SetupError saying ``what`` failed otherwise."""
        status, output = self.shell(command)
        if status != 0:
            raise SetupError(f"could not {what}: {output.strip() or f'exit {status}'}")
        return output


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


# ── the client app ──


def ensure_signing_key(keytool, directory=SIGNING_DIRECTORY, runner=subprocess.run):
    """This machine's key for the client app (made once, outside the Nix store): (keystore, password file).

    Made beside the final names and moved into place only when whole, so an interrupted run leaves nothing half-made.
    """
    keystore = os.path.join(directory, KEYSTORE_NAME)
    password_file = os.path.join(directory, "password")
    if os.path.exists(keystore) and os.path.exists(password_file):
        return keystore, password_file
    os.makedirs(directory, mode=0o700, exist_ok=True)
    os.chmod(directory, 0o700)
    with tempfile.TemporaryDirectory(prefix=".new-key.", dir=directory) as scratch:
        new_password_file = os.path.join(scratch, "password")
        new_keystore = os.path.join(scratch, KEYSTORE_NAME)
        descriptor = os.open(
            new_password_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600
        )
        with os.fdopen(descriptor, "w") as handle:
            handle.write(os.urandom(24).hex())
        completed = runner(
            [
                keytool,
                "-genkeypair",
                "-keystore",
                new_keystore,
                "-storetype",
                "PKCS12",
                "-storepass:file",
                new_password_file,
                "-alias",
                KEY_ALIAS,
                "-keyalg",
                "RSA",
                "-keysize",
                "3072",
                "-validity",
                "10000",
                "-dname",
                "CN=Voxize Remote",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode != 0:
            raise SetupError(
                f"could not make the signing key: {completed.stderr.strip()}"
            )
        os.chmod(new_keystore, 0o600)
        os.replace(new_password_file, password_file)
        os.replace(new_keystore, keystore)
    return keystore, password_file


def signed_client(
    apksigner, unsigned_apk, keystore, password_file, directory, runner=subprocess.run
):
    signed = os.path.join(directory, "voxize-remote.apk")
    completed = runner(
        [
            apksigner,
            "sign",
            "--ks",
            keystore,
            "--ks-pass",
            f"file:{password_file}",
            "--ks-key-alias",
            KEY_ALIAS,
            "--out",
            signed,
            unsigned_apk,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise SetupError(f"could not sign the client: {completed.stderr.strip()}")
    return signed


def install_client(adb, apk, console):
    status, output = adb.run("install", "-r", apk, timeout=180)
    if status == 0 and "Success" in output:
        return
    # Installs only an uninstall gets past; the pairing is redone below either way, so nothing else is lost.
    reasons = {
        "INSTALL_FAILED_UPDATE_INCOMPATIBLE": "was signed with another key",
        "INSTALL_FAILED_VERSION_DOWNGRADE": "is newer than this one (this machine rolled back?)",
    }
    reason = next((text for code, text in reasons.items() if code in output), None)
    if reason is not None:
        console.say(
            f"The Voxize Remote on the phone {reason}, so it cannot be updated in place."
        )
        if console.ask(
            "Uninstall it and install this one (its pairing goes with it)? [y/N] "
        ).lower() in ("y", "yes"):
            adb.run("uninstall", CLIENT_PACKAGE, timeout=60)
            status, output = adb.run("install", apk, timeout=180)
            if status == 0 and "Success" in output:
                return
    raise SetupError(f"could not install the client: {output.strip()}")


def grant_client(adb):
    for permission in GRANTED_PERMISSIONS:
        adb.checked_shell(
            f"pm grant {CLIENT_PACKAGE} {permission}",
            f"grant Voxize Remote {permission}",
        )
    for operation in ALLOWED_OPERATIONS:
        adb.checked_shell(
            f"appops set {CLIENT_PACKAGE} {operation} allow",
            f"allow Voxize Remote {operation}",
        )


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


# ── pairing with the Voxize Remote server ──


def pair_client(adb, console, control_path, server_name, port):
    """A pairing window on the server, the client asked to pair over adb, the code typed here."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        try:
            connection.connect(control_path)
        except OSError as error:
            raise SetupError(
                f"the Voxize Remote server is not reachable at {control_path} ({error}); is the "
                "configuration switched in (make switch)?"
            ) from None
        stream = connection.makefile("rwb", buffering=0)
        stream.write(b"pair\n")
        for line in stream:
            event = json.loads(line)
            kind = event.get("event")
            if kind == "busy":
                raise SetupError(
                    "another voxize-remote pair is already waiting on this machine"
                )
            if kind == "open":
                adb.shell(
                    f"am start -n {CLIENT_PACKAGE}/.MainActivity --es server {shlex.quote(server_name)} "
                    f"--ei port {int(port)} --ez pair true"
                )
                console.say(
                    f"Asked Voxize Remote to pair; it shows a six-digit code once it reaches {server_name}."
                )
            elif kind == "code_requested":
                console.say(f"{event['device']} ({event['node']}) asks to pair.")
                typed = console.ask("Type the code the phone shows: ")
                stream.write(f"{typed}\n".encode())
            elif kind == "paired":
                console.say(f"Paired {event['device']}.")
                return
            elif kind == "rejected":
                console.say(
                    f"Not paired: {event.get('reason', 'refused')}. The phone can try again."
                )
            elif kind == "expired":
                raise SetupError(
                    "the pairing window closed before the client paired; Voxize Remote's screen on the "
                    "phone says why (most often Tailscale's split tunneling leaves it out)"
                )
    raise SetupError("the Voxize Remote server closed the pairing")


def client_status(control_path):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(10)
        connection.connect(control_path)
        connection.sendall(b"status\n")
        reply = b""
        while chunk := connection.recv(65536):
            reply += chunk
    return json.loads(reply)


def check_connection(adb, console, control_path):
    """Arms the client as ssh cc will, and waits for it to connect; says what to fix when it does not."""
    adb.shell(f"am start -n {CLIENT_PACKAGE}/.ArmActivity")
    deadline = time.monotonic() + CONNECT_CHECK_SECONDS
    while time.monotonic() < deadline:
        try:
            if client_status(control_path).get("client"):
                console.say("The client is connected over Tailscale.")
                return True
        except (OSError, ValueError):
            pass
        time.sleep(1)
    console.say(
        "The client did not connect. Most likely Tailscale's split tunneling leaves Voxize Remote out:"
    )
    console.say(
        "in the Tailscale app, Settings → Split tunneling, include Voxize Remote. Its screen also says why."
    )
    return False


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
    apksigner,
    keytool,
    unsigned_apk,
    control_path,
    server_name,
    port,
    bootstrap_command,
    key_registered,
    console=None,
    runner=subprocess.run,
    signing_directory=SIGNING_DIRECTORY,
):
    """The client half of `cc remote setup`; False when Stan skipped it. SetupError says what went wrong."""
    try:
        return _run(
            adb_executable,
            apksigner,
            keytool,
            unsigned_apk,
            control_path,
            server_name,
            port,
            bootstrap_command,
            key_registered,
            console or Console(),
            runner,
            signing_directory,
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
    apksigner,
    keytool,
    unsigned_apk,
    control_path,
    server_name,
    port,
    bootstrap_command,
    key_registered,
    console,
    runner,
    signing_directory,
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

        console.step(2, "Voxize Remote on the phone")
        keystore, password_file = ensure_signing_key(keytool, signing_directory, runner)
        with tempfile.TemporaryDirectory(prefix="voxize-remote-apk.") as directory:
            install_client(
                adb,
                signed_client(
                    apksigner, unsigned_apk, keystore, password_file, directory, runner
                ),
                console,
            )
        # A fresh start: setup pairs again, so the client forgets an earlier pairing (the server replaces its own).
        adb.shell(f"am force-stop {CLIENT_PACKAGE}")
        if "Success" not in adb.checked_shell(
            f"pm clear {CLIENT_PACKAGE}", "clear Voxize Remote's earlier pairing"
        ):
            raise SetupError(
                "could not clear Voxize Remote's earlier pairing (pm clear did not succeed)"
            )
        grant_client(adb)
        console.say(
            "Installed, with the microphone, notifications, the floating button and Usage access allowed."
        )

        console.step(3, "ssh cc in Termux")
        run_termux_bootstrap(adb, console, bootstrap_command, key_registered)
        console.say("ssh cc is set up.")

        console.step(4, "Pairing Voxize Remote with this machine")
        pair_client(adb, console, control_path, server_name, port)
        console.step(5, "Checking the connection")
        connected = check_connection(adb, console, control_path)
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

# Voxize Remote

Dictate on the phone into the Claude Code session it is showing. A floating microphone sits over Termux while a session is open: tap it, speak, tap again, and this machine's Voxize transcribes and cleans up the speech and pastes it into that session's prompt, unsent. The phone only records; everything else runs here.

```
client: Voxize Remote (Android)  ── TCP over Tailscale, port 7223 ──►  server: voxize-remote serve (systemd user service)
  floating button, microphone service                                    one Voxize backend per dictation, then
  shown over Termux with a session, or while recording                   paste-buffer -p into the session's pane
```

## Setting up a phone

```sh
cc remote setup
```

Connect the phone with a USB cable (Developer options → USB debugging) when it asks, or type `w` to use Wireless debugging. Setup installs Voxize Remote signed with this machine's key, grants it the microphone, notifications, "Display over other apps" and Usage access, opens Termux and types the `ssh cc` bootstrap (after you press Enter), then pairs the client: the phone shows six digits, you type them here. Once the client connects, the phone is back in Termux; Wireless debugging is switched off again. What stays on the phone is Android's own prompt to allow USB debugging and Termux's fingerprint test. Afterwards use a new Termux session (swipe in from the left edge, New session): the shell that ran the setup predates its settings.

Tailscale on the phone must carry Voxize Remote: with split tunneling set to selected apps, include it. The client refuses to talk to anything but a Tailscale address through Tailscale, and its screen says when this is the problem.

## Using it

`ssh cc` in Termux arms the client (the `Host cc` stanza runs `am start …/.ArmActivity` as its LocalCommand). Open a session from the hub: the floating microphone appears.

- **Tap**: record (red, with the time recorded); **tap** again: stop. Orange with a ring while Voxize works (its own progress estimate, or a spinner for short dictations), green once pasted. A tap on the green check or the "!" puts it away. While it records, the button stays on screen in any app, so it can always be stopped.
- **Long press**: cancel. **Drag**: move it; it stays where you leave it.
- The bubble above the button shows the newest words; older lines fade out at its top.
- The notification has Record/Stop and Quit, and says only the phase ("Recording", "Transcribing", "Pasted").

The client disarms itself after 15 minutes awake with no session open (or no server reachable; time asleep does not count), and the server exits 5 minutes after its last client leaves; systemd starts it again at the next connection. The paste never presses Enter: Claude Code takes it as one bracketed paste, and a pane that does not ask for bracketed paste gets the lines joined with spaces.

## On this machine

```sh
voxize-remote status          # the connected client and the dictation in progress (--json for scripts)
voxize-remote devices         # paired clients
voxize-remote unpair DEVICE   # forget one (a dictation of its in progress is dropped)
voxize-remote pair            # pair by hand: tap "Pair with server" in the app, type the code it shows
voxize-remote cancel          # stop a dictation; this machine can never start one
journalctl --user -u voxize-remote    # the server's log
```

Every dictation is a normal Voxize session under `~/.local/state/voxize/`.

## Security

- **Network**: port 7223 is open on `tailscale0` only (`firewall.nix`); the server refuses peers Tailscale cannot vouch for, peers of another Tailscale user, this machine's own address, and loopback (except `serve --debug-adb`). The client binds its socket to the VPN network Android routes it through, and refuses to connect without one.
- **Pairing**: once per client, in a window `voxize-remote pair` opens: the client commits to a nonce, receives a 256-bit secret, reveals the nonce, and shows a code derived from both, which you type here. The server keeps one GNOME keyring item per client with its Tailscale node; the client keeps the secret in app-private storage.
- **Every connection**: HMAC challenges both ways; the server proves itself first, and the client obeys nothing before that. The client must also come from the Tailscale node it paired from.
- **Recording**: only a tap on the client starts one. Even a server that proves itself cannot open the microphone without a tap in the last 10 seconds.
- **Voxize**: each backend is Voxize's own (`python -P -m voxize.backend --audio-fd FD`, Voxize 0.4.0's option for the client's audio from a pipe). It runs in `/` with Python's safe path (`-P`), so code planted in a session's directory is never imported; the directory reaches Voxize only as data (`WHISPER.txt`).

## Layout

| Path | What |
| --- | --- |
| `server/voxize_remote/server.py` | the server: connections, pairing, dictations, tmux, the CLI |
| `server/voxize_remote/pairing.py` | secrets, proofs, codes, the keyring and file stores |
| `server/voxize_remote/frames.py` | the wire format: a kind byte, a big-endian length, JSON or PCM |
| `server/voxize_remote/fake_client.py` | a client for tests |
| `android/` | the client: `VoxService`, `Link`, `Pairing`, `Tailnet`, `Capture`, `Overlay`, `OrbView`, `MainActivity`, … |
| `tests/` | the server's tests (`installCheckPhase` runs them, with a JDK for `test_client_agreement.py`) |
| `android/tests/` | Java mains those tests compile beside `Pairing.java` and `Reasons.java`: Java and Python must agree |
| `package.nix` | the server, `passthru.apk` (unsigned, no Gradle) and `passthru.tools` (adb, apksigner, keytool) |
| `default.nix`, `firewall.nix`, `port.nix` | the systemd user units, the tailnet-only port |

`cc remote setup`'s phone half is `home/apps/claude-code/remote/phone_setup.py`; the signing key lives in `~/.local/share/voxize-remote/signing/` (never in the Nix store).

## Developing

From the repository root (`path:` reaches files git does not track yet):

```sh
remote='(builtins.getFlake "path:'"$PWD"'").nixosConfigurations.stan-latitude.pkgs.callPackage ./home/apps/voxize/remote/package.nix { }'
nix build --impure -L --expr "$remote" -o result-voxize-remote             # the server, with its tests
nix build --impure --expr "($remote).apk" -o result-voxize-remote-apk      # the client, unsigned
adb logcat -s VoxizeService VoxizeLink VoxizeCapture                      # the client's log
```

To try the client against the mock backend (no OpenAI calls), stop the service and its sockets, then run the server in a terminal on the same port; the paired client connects to it as it would to the service. A server run by hand while the service still holds the port or the control socket says so and exits:

```sh
systemctl --user stop voxize-remote.service voxize-remote-clients.socket voxize-remote-control.socket
voxize-remote serve --mock --port 7223
systemctl --user start voxize-remote-clients.socket voxize-remote-control.socket   # afterwards
```

The client talks to Tailscale addresses only, so `adb reverse` and `127.0.0.1` are of no use for it; the server's `--debug-adb` (loopback) exists for the fake client in the tests.

#!/data/data/com.termux/files/usr/bin/bash
# shellcheck shell=bash
# Bootstrap script for phone-side cc remote access, run on stan-galaxy (Samsung Galaxy, Termux).
# Idempotent — safe to re-run after a phone reset.
set -euo pipefail

green=$'\033[32m'
yellow=$'\033[33m'
cyan=$'\033[36m'
bold=$'\033[1m'
reset=$'\033[0m'

step() { printf '\n%s==>%s %s%s\n' "$green" "$reset" "$bold$1" "$reset"; }

# 1. Install packages.
step "Installing packages"
pkg install -y openssh termux-api 2>/dev/null || {
	echo "Note: if this fails, make sure you have a recent Termux from F-Droid."
}
echo "Note: fingerprint unlock also needs the separate Termux:API app (from F-Droid) installed alongside Termux — the termux-api package alone only provides the command-line scripts."

# 2. Generate SSH key.
step "SSH key"
if [ -f "$HOME/.ssh/id_ed25519" ]; then
	echo "Key already exists, skipping generation."
else
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"
	echo "Generate a key with a passphrase (you will unlock it with your fingerprint)."
	ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -C "stan-galaxy@termux" </dev/tty
fi

# 3. Write SSH config.
step "SSH config"
mkdir -p "$HOME/.ssh"
if grep -qx 'Host cc' "$HOME/.ssh/config" 2>/dev/null; then
	echo "Host cc entry already exists in ~/.ssh/config, skipping."
else
	cat >>"$HOME/.ssh/config" <<'SSHCONFIG'

Host cc
  HostName stan-latitude.local
  Port 7222
  User stan
  IdentityFile ~/.ssh/id_ed25519
SSHCONFIG
	chmod 600 "$HOME/.ssh/config"
	echo "Added Host cc to ~/.ssh/config."
fi

# 4. Set up passphrase handling — fingerprint if available, ssh-agent fallback.
step "Authentication"
profile="$HOME/.bashrc"
fdroid_api_url="https://f-droid.org/packages/com.termux.api/"

# Clean up any broken SSH_ASKPASS from previous runs.
if grep -q 'SSH_ASKPASS.*ssh-askpass-fingerprint\|SSH_ASKPASS_REQUIRE' "$profile" 2>/dev/null; then
	sed -i '/# cc remote:/d; /SSH_ASKPASS.*ssh-askpass-fingerprint/d; /SSH_ASKPASS_REQUIRE/d' "$profile"
fi

fingerprint_ok=0
if command -v termux-fingerprint >/dev/null 2>&1; then
	echo "Testing fingerprint support (touch the sensor when prompted)..."
	if result=$(timeout 10 termux-fingerprint -t "Setup Test" -s "cc remote" -d "Testing fingerprint for SSH unlock" 2>/dev/null); then
		auth_result=$(echo "$result" | grep -o '"auth_result" *: *"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"')
		if [ "$auth_result" = "AUTH_RESULT_SUCCESS" ]; then
			fingerprint_ok=1
			echo "${green}Fingerprint works.${reset}"
		else
			echo "${yellow}Fingerprint test failed (auth_result: ${auth_result:-empty}).${reset}"
		fi
	else
		echo ""
		echo "${yellow}╔══════════════════════════════════════════════════════════════╗${reset}"
		echo "${yellow}║  Fingerprint timed out — Termux:API companion app missing.  ║${reset}"
		echo "${yellow}║  Install it from F-Droid:                                   ║${reset}"
		echo "${yellow}║  ${bold}${fdroid_api_url}${reset}${yellow}    ║${reset}"
		echo "${yellow}║  Then re-run this script.                                   ║${reset}"
		echo "${yellow}╚══════════════════════════════════════════════════════════════╝${reset}"
		echo ""
		command -v termux-open-url >/dev/null 2>&1 && termux-open-url "$fdroid_api_url" 2>/dev/null
	fi
else
	echo ""
	echo "${yellow}╔══════════════════════════════════════════════════════════════╗${reset}"
	echo "${yellow}║  termux-fingerprint not found.                              ║${reset}"
	echo "${yellow}║  1. pkg install termux-api                                  ║${reset}"
	echo "${yellow}║  2. Install the Termux:API app from F-Droid:                ║${reset}"
	echo "${yellow}║     ${bold}${fdroid_api_url}${reset}${yellow}   ║${reset}"
	echo "${yellow}║  Then re-run this script.                                   ║${reset}"
	echo "${yellow}╚══════════════════════════════════════════════════════════════╝${reset}"
	echo ""
fi

if [ "$fingerprint_ok" -eq 1 ]; then
	# Fingerprint works — use SSH_ASKPASS with termux-fingerprint.
	askpass_script="$HOME/.local/bin/ssh-askpass-fingerprint"
	mkdir -p "$HOME/.local/bin"
	cat >"$askpass_script" <<'ASKPASS'
#!/data/data/com.termux/files/usr/bin/bash
passfile="$HOME/.ssh/.cc-passphrase"
if [ ! -f "$passfile" ]; then
  echo "No stored passphrase. Run setup-termux.sh again." >&2
  exit 1
fi
result=$(termux-fingerprint -t "Unlock SSH Key" -s "cc remote access" -d "Authenticate to connect to your laptop" 2>/dev/null)
auth_result=$(echo "$result" | grep -o '"auth_result" *: *"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"')
if [ "$auth_result" = "AUTH_RESULT_SUCCESS" ]; then
  cat "$passfile"
else
  echo "Fingerprint authentication failed." >&2
  exit 1
fi
ASKPASS
	chmod 700 "$askpass_script"

	passfile="$HOME/.ssh/.cc-passphrase"
	# Always verify the stored passphrase can actually decrypt the key.
	# If it fails (typo on first entry, or key was regenerated), re-prompt.
	needs_passphrase=1
	if [ -f "$passfile" ]; then
		stored=$(cat "$passfile")
		if echo "$stored" | SSH_ASKPASS_REQUIRE=force SSH_ASKPASS=/bin/cat ssh-keygen -y -f "$HOME/.ssh/id_ed25519" -P "$stored" >/dev/null 2>&1; then
			echo "Stored passphrase verified."
			needs_passphrase=0
		else
			echo "${yellow}Stored passphrase is incorrect — re-enter it.${reset}"
			rm -f "$passfile"
		fi
	fi
	if [ "$needs_passphrase" -eq 1 ]; then
		while true; do
			echo ""
			echo "${yellow}Enter your SSH key passphrase to store for fingerprint unlock:${reset}"
			read -rs passphrase </dev/tty
			echo ""
			if ssh-keygen -y -f "$HOME/.ssh/id_ed25519" -P "$passphrase" >/dev/null 2>&1; then
				printf '%s' "$passphrase" >"$passfile"
				chmod 600 "$passfile"
				echo "${green}Passphrase verified and stored.${reset}"
				break
			else
				echo "${yellow}Wrong passphrase — try again.${reset}"
			fi
		done
	fi

	cat >>"$profile" <<PROFILE

# cc remote: fingerprint-based SSH key unlock
export SSH_ASKPASS="$askpass_script"
export SSH_ASKPASS_REQUIRE=force
PROFILE
	echo "Fingerprint unlock configured."
else
	# Fallback: ssh-agent remembers the passphrase for the session.
	if ! grep -q 'cc remote: ssh-agent' "$profile" 2>/dev/null; then
		cat >>"$profile" <<'PROFILE'

# cc remote: ssh-agent (type passphrase once per session)
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" >/dev/null
fi
PROFILE
	fi
	echo ""
	echo "Using ${bold}ssh-agent${reset} as fallback (type passphrase once per Termux session)."
	echo "Re-run this script after installing Termux:API for fingerprint unlock."
fi

# 5. Send the public key back to the laptop.
step "Registering public key"
public_key="$(cat "$HOME/.ssh/id_ed25519.pub")"

# Extract the host and port from the URL this script was fetched from (set by the curl | bash pipeline).
# Falls back to the SSH config host if not available.
hub_host="stan-latitude.local"
hub_port="8081"

if curl -sS --max-time 5 -X POST -d "$public_key" "http://${hub_host}:${hub_port}/pubkey" 2>/dev/null; then
	echo ""
	echo "${green}Public key sent to the laptop.${reset}"

	# Verify the registered key matches what this phone has.
	check_result=$(curl -sS --max-time 5 -X POST -d "$public_key" "http://${hub_host}:${hub_port}/verify-key" 2>/dev/null)
	if echo "$check_result" | grep -q "Match: YES"; then
		echo "${green}Key verified — registered key matches this phone.${reset}"
	else
		echo "${yellow}WARNING: key mismatch after registration!${reset}"
		echo "$check_result"
	fi
else
	echo ""
	echo "${yellow}Could not reach the laptop server to send the key automatically.${reset}"
	echo "Manually append this to ~/.ssh/authorized_keys on the laptop:"
	echo ""
	echo "${cyan}command=\"/etc/profiles/per-user/stan/bin/cc-hub\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding ${public_key}${reset}"
fi
echo ""
echo "To connect from this phone: ${bold}ssh cc${reset}"

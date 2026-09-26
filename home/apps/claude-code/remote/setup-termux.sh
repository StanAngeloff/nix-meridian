#!/data/data/com.termux/files/usr/bin/bash
# shellcheck shell=bash
# Phone-side setup for cc remote access, run in Termux on stan-galaxy (Samsung Galaxy).
# Started by the /cc bootstrap that `cc remote setup` serves on the laptop. The bootstrap passes the laptop's Tailscale
# address in CC_HOST_ADDRESS, its MagicDNS name in CC_HOST_NAME, and the pairing server's base URL in CC_PAIRING_URL.
# Idempotent — safe to re-run after a phone reset, when the laptop's address changes, or on a phone set up by an earlier
# version of this script: everything earlier versions wrote is removed before the current settings are written.
set -euo pipefail

green=$'\033[32m'
yellow=$'\033[33m'
cyan=$'\033[36m'
bold=$'\033[1m'
reset=$'\033[0m'

fdroid_api_url="https://f-droid.org/packages/com.termux.api/"
key_file="$HOME/.ssh/id_ed25519"
known_hosts_file="$HOME/.ssh/known_hosts"
profile_file="$HOME/.bashrc"
cc_profile_file="$HOME/.config/cc-remote/profile.sh"
passphrase_file="$HOME/.ssh/.cc-passphrase"
askpass_file="$HOME/.local/bin/ssh-askpass-fingerprint"
# The name the laptop's host key is recorded under, whatever address cc_config points at.
host_key_alias="cc"
# Every earlier version of this script pointed ssh at the laptop's mDNS name.
legacy_known_host="[stan-latitude.local]:7222"
printf -v profile_source_line '[ -f %q ] && . %q' "$cc_profile_file" "$cc_profile_file"

step() { printf '\n%s==>%s %s%s\n' "$green" "$reset" "$bold$1" "$reset"; }

# Drops leading and trailing blank lines and squeezes each run of blank lines into one, so removing a block leaves no gap.
squeeze_blank_lines() {
	awk '/^[ \t]*$/ { pending = printed; next } { if (pending) print ""; pending = 0; print; printed = 1 }'
}

install_packages() {
	pkg install -y openssh termux-api 2>/dev/null || {
		echo "Note: if this fails, make sure you have a recent Termux from F-Droid."
	}
	echo "Note: fingerprint unlock also needs the separate Termux:API app (from F-Droid) installed alongside Termux — the termux-api package alone only provides the command-line scripts."
}

ensure_key() {
	if [ -f "$key_file" ]; then
		echo "Key already exists, skipping generation."
		return
	fi
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"
	echo "Generate a key with a passphrase (you will unlock it with your fingerprint)."
	ssh-keygen -t ed25519 -f "$key_file" -C "stan-galaxy@termux" </dev/tty
}

# Prints the host name ssh should use: the MagicDNS name when this phone's ssh can resolve it, otherwise the address.
# The name survives the laptop re-registering with Tailscale; the address does not.
# ssh-keyscan resolves names exactly as ssh does, and a reply means the name reaches an sshd on 7222 over the tailnet.
choose_host_name() {
	local scan_output=""
	if [[ -n "${CC_HOST_NAME:-}" ]]; then
		scan_output="$(ssh-keyscan -T 5 -p 7222 "$CC_HOST_NAME" 2>/dev/null || true)"
	fi
	if [[ -n "$scan_output" ]]; then
		printf '%s\n' "$CC_HOST_NAME"
	else
		printf '%s\n' "$CC_HOST_ADDRESS"
	fi
}

# Removes every known_hosts entry for the given names, hashed or not.
# ssh-keygen -F finds the lines (it can match hashed names); deleting them here, rather than with ssh-keygen -R, leaves no
# known_hosts.old behind.
remove_known_hosts() {
	local host_name line_numbers=""
	[[ -f "$known_hosts_file" ]] || return 0
	for host_name in "$@"; do
		line_numbers+=" $(ssh-keygen -F "$host_name" -f "$known_hosts_file" 2>/dev/null |
			sed -n 's/^# Host .* found: line \([0-9][0-9]*\) *$/\1/p' | tr '\n' ' ' || true)"
	done
	awk -v line_numbers="$line_numbers" '
		BEGIN { count = split(line_numbers, numbers, " "); for (i = 1; i <= count; i++) dropped[numbers[i]] = 1 }
		!(FNR in dropped)
	' "$known_hosts_file" >"$known_hosts_file.tmp"
	chmod 600 "$known_hosts_file.tmp"
	mv "$known_hosts_file.tmp" "$known_hosts_file"
}

# Forgets the host keys recorded for the cc entries earlier versions of this script appended to ~/.ssh/config: the
# mDNS name they wrote, and whatever HostName and Port each "Host cc" stanza holds now, in case it was edited by hand.
# Runs before write_ssh_config removes those stanzas.
forget_legacy_host_keys() {
	local config_file="$HOME/.ssh/config" legacy_host_names=()
	if [[ -f "$config_file" ]]; then
		mapfile -t legacy_host_names < <(awk '
			function finish() { if (in_cc && name != "") print (port == "22" ? name : "[" name "]:" port) }
			tolower($1) == "host" || tolower($1) == "match" {
				finish(); in_cc = (tolower($1) == "host" && NF == 2 && $2 == "cc"); name = ""; port = "22"; next
			}
			in_cc && tolower($1) == "hostname" { name = $2 }
			in_cc && tolower($1) == "port" { port = $2 }
			END { finish() }
		' "$config_file")
	fi
	remove_known_hosts "$legacy_known_host" "${legacy_host_names[@]}"
}

# Writes the cc entry to ~/.ssh/cc_config and makes ~/.ssh/config include it first.
# cc_config is owned outright and rewritten on every run, so re-running corrects a stale address instead of skipping.
write_ssh_config() {
	local host_name="$1"
	local ssh_path="$HOME/.ssh"
	local config_file="$ssh_path/config"
	local cc_config_file="$ssh_path/cc_config"

	mkdir -p "$ssh_path"
	chmod 700 "$ssh_path"

	# The key path is written out in full: the askpass helper recognizes the passphrase prompt by that path built from
	# $HOME, while ssh would expand "~" from the passwd entry, which need not be the same directory.
	cat >"$cc_config_file" <<SSHCONFIG
Host cc
  HostName $host_name
  HostKeyAlias $host_key_alias
  Port 7222
  User stan
  IdentityFile "$key_file"
  ConnectTimeout 10
  ServerAliveInterval 15
  ServerAliveCountMax 4
SSHCONFIG
	chmod 600 "$cc_config_file"

	# Every "Host cc" stanza goes, whatever it holds: earlier versions of this script appended one to ~/.ssh/config, and it
	# may have been edited by hand since. cc_config now owns the entry.
	local remaining_text=""
	if [[ -f "$config_file" ]]; then
		remaining_text="$(awk '
			tolower($1) == "host" || tolower($1) == "match" { skipping = (tolower($1) == "host" && NF == 2 && $2 == "cc") }
			skipping { next }
			tolower($1) == "include" && NF == 2 && $2 == "cc_config" { next }
			{ print }
		' "$config_file" | squeeze_blank_lines)"
	fi

	# ssh keeps the first value it reads for each option, and an Include applies to every host only before the first
	# Host line, so the include goes at the very top — which also lets it win over anything left further down.
	{
		printf 'Include cc_config\n'
		if [[ -n "$remaining_text" ]]; then
			printf '%s\n' "$remaining_text"
		fi
	} >"$config_file.tmp"
	chmod 600 "$config_file.tmp"
	mv "$config_file.tmp" "$config_file"
}

# Records the laptop's host key under the alias cc_config names, replacing the one recorded before, so a new address or
# a reinstalled laptop needs a re-run of this script rather than hand-editing known_hosts.
# A silent scan keeps the recorded key: with fingerprint unlock, ssh cannot ask to confirm an unknown one.
record_host_key() {
	local host_address="$1" key_text
	key_text="$(ssh-keyscan -T 5 -p 7222 "$host_address" 2>/dev/null |
		awk -v alias="$host_key_alias" '!/^#/ && NF >= 3 { $1 = alias; print }' || true)"
	if [[ -z "$key_text" ]]; then
		echo "${yellow}Could not read the laptop's host key; re-run this script once the laptop is reachable.${reset}"
		return 0
	fi
	remove_known_hosts "$host_key_alias"
	printf '%s\n' "$key_text" >>"$known_hosts_file"
	chmod 600 "$known_hosts_file"
}

# Everything ssh needs to reach the laptop as "cc", replacing whatever an earlier run or an earlier version left behind.
# The host key is scanned from the Tailscale address, which only the laptop answers over the tailnet, whatever name ssh
# connects to: HostKeyAlias makes that key cover the name too, so a spoofed DNS answer for the name fails verification.
configure_ssh() {
	local host_name="$1" host_address="$2"
	forget_legacy_host_keys
	write_ssh_config "$host_name"
	record_host_key "$host_address"
}

# Writes the shell settings for the unlock method ("fingerprint" or "agent") to an owned file, rewritten on every run,
# and makes ~/.bashrc source it exactly once.
# Earlier versions appended their blocks to ~/.bashrc directly, and their cleanup could strand the ssh-agent block's
# if/fi or append it twice; every one of those lines is removed, recognized by pattern rather than exact text.
write_shell_profile() {
	local unlock_method="$1"
	mkdir -p "$(dirname "$cc_profile_file")"
	if [[ "$unlock_method" == fingerprint ]]; then
		printf '# Written by setup-termux.sh (cc remote) on every run.\nexport SSH_ASKPASS=%q\nexport SSH_ASKPASS_REQUIRE=force\n' \
			"$askpass_file" >"$cc_profile_file"
	else
		cat >"$cc_profile_file" <<'PROFILE'
# Written by setup-termux.sh (cc remote) on every run.
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" >/dev/null
fi
PROFILE
	fi

	local remaining_text=""
	if [[ -f "$profile_file" ]]; then
		# An "if [ -z "$SSH_AUTH_SOCK" ]" line and the line after it are held until the block shows whether it is exactly
		# the three-line ssh-agent block (if, ssh-agent -s, fi); any other block is printed back untouched.
		remaining_text="$(awk -v source_line="$profile_source_line" '
			held_eval != "" {
				if ($0 ~ /^[ \t]*fi[ \t]*$/) { held_if = held_eval = ""; next }
				print held_if; print held_eval; held_if = held_eval = ""
			}
			held_if != "" {
				if ($0 ~ /ssh-agent -s/) { held_eval = $0; next }
				print held_if; held_if = ""
			}
			/^[ \t]*# cc remote:/ || $0 == source_line { next }
			/^[ \t]*(export[ \t]+)?SSH_ASKPASS=.*ssh-askpass-fingerprint/ || /^[ \t]*export SSH_ASKPASS_REQUIRE=force[ \t]*$/ { next }
			/^[ \t]*if \[ -z "\$SSH_AUTH_SOCK" \]; then[ \t]*$/ { held_if = $0; next }
			{ print }
			END { if (held_if != "") print held_if; if (held_eval != "") print held_eval }
		' "$profile_file" | squeeze_blank_lines)"
	fi
	{
		if [[ -n "$remaining_text" ]]; then
			printf '%s\n\n' "$remaining_text"
		fi
		printf '%s\n' "$profile_source_line"
	} >"$profile_file.tmp"
	# Removal by pattern can, in rare nestings, take away the only body of the user's own block. A ~/.bashrc that no longer
	# parses would break every new Termux session, so a current one that parses is kept and the source line left to add.
	if [[ -f "$profile_file" ]] && ! bash -n "$profile_file.tmp" 2>/dev/null && bash -n "$profile_file" 2>/dev/null; then
		rm -f "$profile_file.tmp"
		echo "${yellow}~/.bashrc left unchanged: without the lines earlier versions of this script added, it would not parse.${reset}"
		echo "By hand, remove those older lines and any if/fi block they leave empty (bash -n ~/.bashrc must stay silent), then add this line:"
		echo "${cyan}${profile_source_line}${reset}"
		return 0
	fi
	mv "$profile_file.tmp" "$profile_file"
}

# SSH_ASKPASS_REQUIRE=force sends every ssh prompt in Termux to this helper, so it answers only the passphrase prompt for
# the cc key, from the stored passphrase after a fingerprint; any other prompt (another server's password, a host key
# confirmation) is asked on the terminal instead.
write_askpass_helper() {
	mkdir -p "$HOME/.local/bin"
	cat >"$askpass_file" <<'ASKPASS'
#!/data/data/com.termux/files/usr/bin/bash
prompt_text="${1:-}"
passfile="$HOME/.ssh/.cc-passphrase"
# ssh passes the prompt as the first argument; OpenSSH's is "Enter passphrase for key '<path>': ".
if [[ "$prompt_text" != "Enter passphrase for key '$HOME/.ssh/id_ed25519':"* ]]; then
  printf '%s' "$prompt_text" >/dev/tty
  if [[ "$prompt_text" == *"(yes/no"* ]]; then
    IFS= read -r answer </dev/tty
  else
    IFS= read -rs answer </dev/tty
    printf '\n' >/dev/tty
  fi
  printf '%s\n' "$answer"
  exit 0
fi
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
	chmod 700 "$askpass_file"
}

# Passphrase handling — fingerprint if available, ssh-agent fallback.
setup_authentication() {
	local fingerprint_ok=0 result auth_result
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
		write_askpass_helper

		# Always verify the stored passphrase can actually decrypt the key.
		# If it fails (typo on first entry, or key was regenerated), re-prompt.
		local needs_passphrase=1 stored passphrase
		if [ -f "$passphrase_file" ]; then
			stored=$(cat "$passphrase_file")
			if echo "$stored" | SSH_ASKPASS_REQUIRE=force SSH_ASKPASS=/bin/cat ssh-keygen -y -f "$key_file" -P "$stored" >/dev/null 2>&1; then
				echo "Stored passphrase verified."
				needs_passphrase=0
			else
				echo "${yellow}Stored passphrase is incorrect — re-enter it.${reset}"
				rm -f "$passphrase_file"
			fi
		fi
		if [ "$needs_passphrase" -eq 1 ]; then
			while true; do
				echo ""
				echo "${yellow}Enter your SSH key passphrase to store for fingerprint unlock:${reset}"
				read -rs passphrase </dev/tty
				echo ""
				if ssh-keygen -y -f "$key_file" -P "$passphrase" >/dev/null 2>&1; then
					printf '%s' "$passphrase" >"$passphrase_file"
					chmod 600 "$passphrase_file"
					echo "${green}Passphrase verified and stored.${reset}"
					break
				else
					echo "${yellow}Wrong passphrase — try again.${reset}"
				fi
			done
		fi

		write_shell_profile fingerprint
		echo "Fingerprint unlock configured."
	else
		# Without fingerprint unlock nothing reads these, and the passphrase file holds the passphrase in plain text.
		rm -f "$askpass_file" "$passphrase_file"
		write_shell_profile agent
		echo ""
		echo "Using ${bold}ssh-agent${reset} as fallback (type passphrase once per Termux session)."
		echo "Re-run this script after installing Termux:API for fingerprint unlock."
	fi
}

# Sends the public key to the pairing server, then asks it to confirm the registered key matches this phone's.
register_key() {
	local public_key check_result
	public_key="$(cat "$key_file.pub")"
	if curl -sS --max-time 5 -X POST -d "$public_key" "$CC_PAIRING_URL/pubkey" 2>/dev/null; then
		echo ""
		echo "${green}Public key sent to the laptop.${reset}"
		check_result="$(curl -sS --max-time 5 -X POST -d "$public_key" "$CC_PAIRING_URL/verify-key" 2>/dev/null || true)"
		if [[ "$check_result" == *"Match: YES"* ]]; then
			echo "${green}Key verified — registered key matches this phone.${reset}"
		else
			echo "${yellow}WARNING: key mismatch after registration!${reset}"
			echo "$check_result"
		fi
	else
		echo ""
		echo "${yellow}Could not reach the laptop's pairing server to send the key automatically.${reset}"
		echo "Manually append this to ~/.ssh/authorized_keys on the laptop:"
		echo ""
		echo "${cyan}command=\"/etc/profiles/per-user/stan/bin/cc-hub\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding ${public_key}${reset}"
	fi
}

main() {
	if [[ -z "${CC_HOST_ADDRESS:-}" || -z "${CC_PAIRING_URL:-}" ]]; then
		echo "Run this through the bootstrap that 'cc remote setup' prints on the laptop: curl -sS <address>:8081/cc | sh" >&2
		exit 1
	fi

	step "Installing packages"
	install_packages

	step "SSH key"
	ensure_key

	step "SSH config"
	local host_name
	host_name="$(choose_host_name)"
	if [[ "$host_name" == "$CC_HOST_ADDRESS" ]]; then
		if [[ -z "${CC_HOST_NAME:-}" ]]; then
			echo "Using the laptop's Tailscale address $host_name (no MagicDNS name was offered)."
		else
			echo "Using the laptop's Tailscale address $host_name (its name did not resolve from Termux's ssh)."
		fi
	else
		echo "Using the laptop's Tailscale name $host_name."
	fi
	configure_ssh "$host_name" "$CC_HOST_ADDRESS"
	echo "Wrote ~/.ssh/cc_config (included first by ~/.ssh/config) and recorded the laptop's host key as \"$host_key_alias\"."

	step "Authentication"
	setup_authentication

	step "Registering public key"
	register_key

	echo ""
	echo "Open a new Termux session so the shell picks up the settings above."
	echo "To connect from this phone: ${bold}ssh cc${reset}"
}

# Sourcing (as the tests do) only defines the functions.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi

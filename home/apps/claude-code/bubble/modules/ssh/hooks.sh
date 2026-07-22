ssh_prepare() {
	# SSH requires config files to be owned by root or the current user. On NixOS both /etc/ssh/ssh_config and ~/.ssh/config are symlinks into the nix store, which shows as nobody:nogroup inside the bubble (bwrap maps unmapped UIDs) and OpenSSH rejects with "Bad owner or permissions". The fix for both is the same: copy the resolved content into scratch so it is owned by the bubble user.
	ssh_config_path="$scratch_path/ssh_config"
	ssh_config_target=""
	if [[ -r /etc/ssh/ssh_config ]]; then
		grep -v '^Include /nix/store/' /etc/ssh/ssh_config >"$ssh_config_path"
		# On NixOS /etc/ssh/ssh_config is a symlink into the nix store; bwrap cannot overlay a symlink on a read-only mount, so resolve to the real path and bind there — a later, more specific --ro-bind layers over the broad --ro-bind /nix /nix.
		ssh_config_target="$(readlink -f /etc/ssh/ssh_config)"
	fi

	ssh_user_config_path=""
	if [[ -e "$home_path/.ssh/config" ]]; then
		ssh_user_config_path="$scratch_path/ssh_user_config"
		cat "$(readlink -f "$home_path/.ssh/config")" >"$ssh_user_config_path"
		chmod 600 "$ssh_user_config_path"
	fi
}

ssh_mount() {
	# Agent-only model: the config, its drop-ins and PUBLIC keys ride in; private key files never do. Signing happens in the forwarded agent (gpg smart card), so any key must be loaded there — ssh_before_run warns about any that isn't.
	# known_hosts (public) so host keys verify.
	bwrap_args+=(--ro-bind-try "$home_path/.ssh/known_hosts" "$home_path/.ssh/known_hosts")
	# Public keys only: ssh needs the .pub to know which identity to offer; the agent does the signing.
	local ssh_pub
	for ssh_pub in "$home_path"/.ssh/*.pub; do
		bwrap_args+=(--ro-bind-try "$ssh_pub" "$ssh_pub")
	done
	# config.d drop-ins (real user-owned files, e.g. the bastion host block).
	bwrap_args+=(--ro-bind-try "$home_path/.ssh/config.d" "$home_path/.ssh/config.d")
	# User config: a user-owned copy in place of the nix-store symlink (see ssh_prepare). Bound directly — $HOME is a fresh tmpfs, so there is no symlink here to overlay.
	if [[ -n "$ssh_user_config_path" ]]; then
		bwrap_args+=(--ro-bind "$ssh_user_config_path" "$home_path/.ssh/config")
	fi
	# The gpg-agent's ssh socket; the gpg module creates $xdg_runtime_path/gnupg.
	bwrap_args+=(--ro-bind-try "$xdg_runtime_path/gnupg/S.gpg-agent.ssh" "$xdg_runtime_path/gnupg/S.gpg-agent.ssh")
	# Shadow the system ssh_config with one that drops nix-store Includes (see ssh_prepare).
	if [[ -f "$ssh_config_path" && -n "$ssh_config_target" ]]; then
		bwrap_args+=(--ro-bind "$ssh_config_path" "$ssh_config_target")
	fi
}

ssh_environment() {
	bwrap_args+=(--setenv SSH_AUTH_SOCK "$xdg_runtime_path/gnupg/S.gpg-agent.ssh")
}

ssh_before_run() {
	# Agent-only model: private keys stay out of the bubble, so a key named by IdentityFile must be loaded in the agent or auth fails cryptically mid-session. Warn (host-side) about referenced keys the agent lacks — e.g. the bastion key before its one-time host `ssh-add`.
	command -v ssh-add >/dev/null 2>&1 || return 0

	# Public-key blobs the agent currently holds (field 2 of each ssh-add -L line).
	local ssh_agent_blobs="" ssh_blob
	while read -r _ ssh_blob _; do
		[[ -n "$ssh_blob" ]] && ssh_agent_blobs+="$ssh_blob"$'\n'
	done < <(SSH_AUTH_SOCK="$xdg_runtime_path/gnupg/S.gpg-agent.ssh" ssh-add -L 2>/dev/null)

	# Every config file the bubble provisions.
	local -a ssh_config_files=()
	[[ -e "$home_path/.ssh/config" ]] && ssh_config_files+=("$(readlink -f "$home_path/.ssh/config")")
	local ssh_drop
	for ssh_drop in "$home_path"/.ssh/config.d/*; do
		[[ -f "$ssh_drop" ]] && ssh_config_files+=("$ssh_drop")
	done
	[[ ${#ssh_config_files[@]} -gt 0 ]] || return 0

	# For each IdentityFile referenced, compare its public key against the agent; warn on a miss.
	local ssh_file ssh_keyword ssh_identity ssh_display ssh_pub ssh_pub_blob ssh_seen=""
	for ssh_file in "${ssh_config_files[@]}"; do
		while read -r ssh_keyword ssh_identity _; do
			[[ "${ssh_keyword,,}" == identityfile ]] || continue
			[[ -n "$ssh_identity" ]] || continue
			ssh_display="$ssh_identity"
			ssh_identity="${ssh_identity%\"}"
			ssh_identity="${ssh_identity#\"}"
			ssh_identity="${ssh_identity/#\~\//$home_path/}"
			case $'\n'"$ssh_seen" in *$'\n'"$ssh_identity"$'\n'*) continue ;; esac
			ssh_seen+="$ssh_identity"$'\n'
			ssh_pub="$ssh_identity"
			[[ "$ssh_pub" == *.pub ]] || ssh_pub="$ssh_pub.pub"
			[[ -r "$ssh_pub" ]] || continue
			read -r _ ssh_pub_blob _ <"$ssh_pub" || true
			[[ -n "$ssh_pub_blob" ]] || continue
			case $'\n'"$ssh_agent_blobs" in
			*$'\n'"$ssh_pub_blob"$'\n'*) : ;;
			*)
				echo "${highlight_on}claude-bubble: ssh key ${ssh_display} is referenced in your ssh config but not loaded in the agent.${highlight_off}" >&2
				echo "  keys never enter the bubble — load it on the host: ssh-add ${ssh_display}" >&2
				;;
			esac
		done <"$ssh_file"
	done
}

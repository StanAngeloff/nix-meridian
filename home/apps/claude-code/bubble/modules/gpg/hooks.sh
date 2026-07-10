# Synthetic gnupg: public keyring only, so in-bubble gpg finds the signing pubkey; the secret key never enters — the forwarded restricted agent socket does the crypto.
gpg_prepare() {
	gnupg_seed_path="$scratch_path/gnupg"
	mkdir -p "$gnupg_seed_path"
	chmod 700 "$gnupg_seed_path"
	gpg --export 2>/dev/null | GNUPGHOME="$gnupg_seed_path" gpg --import 2>/dev/null || true
}

gpg_mount() {
	# Synthetic gnupg (rw so gpg can update trustdb/random_seed; contains no secret keys).
	bwrap_args+=(--bind "$gnupg_seed_path" "$home_path/.gnupg")
	bwrap_args+=(--dir "$xdg_runtime_path/gnupg")
	# Restricted "extra" socket (requires services.gpg-agent.enableExtraSocket): signing and decryption allowed, key management refused, secret keys never cross.
	# Spike-verified: in-bubble gpg rejects the tmpfs runtime dir (secure-directory check) and resolves its agent socket at ~/.gnupg/S.gpg-agent, so bind the socket THERE (inside the seeded public-only gnupg directory); also expose it at the runtime path for tools that resolve via gpgconf.
	# On a miss gpg silently autostarts a throwaway agent and reports a misleading "No secret key". Diagnose with `gpg-connect-agent 'getinfo pid'`: "restricted mode" + ERR Forbidden means the host agent's extra socket answered (healthy); a PID reply means a throwaway did.
	bwrap_args+=(--ro-bind-try "$xdg_runtime_path/gnupg/S.gpg-agent.extra" "$home_path/.gnupg/S.gpg-agent")
	bwrap_args+=(--ro-bind-try "$xdg_runtime_path/gnupg/S.gpg-agent.extra" "$xdg_runtime_path/gnupg/S.gpg-agent")
}

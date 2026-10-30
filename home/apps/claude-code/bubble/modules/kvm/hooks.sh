# /dev/kvm (off by default), for virtual machines started in the bubble; without it QEMU falls back to software emulation.
# The kernel's KVM driver becomes reachable from inside, so a bug in it would be a way out; --with-kvm opts in per session.
# A grant that cannot be honoured stops the launch, since virtual machines silently running in software report timings that mean nothing.
kvm_prepare() {
	if [[ -n "${bubble_grants[kvm]:-}" ]]; then
		local open_error
		if [[ ! -c /dev/kvm ]]; then
			bubble_error "--with-kvm: this host has no /dev/kvm" \
				"check that virtualisation is enabled in the firmware and the kvm-intel or kvm-amd module is loaded"
			exit 1
		fi
		# Opening the device proves both access and a loaded driver without creating a virtual machine.
		# The failed redirection's message ends in the reason (Permission denied, No such device), which is all that is kept.
		if ! open_error="$(: 2>&1 3<>/dev/kvm)"; then
			bubble_error "--with-kvm: /dev/kvm cannot be opened (${open_error##*: })"
			exit 1
		fi
	fi
}

kvm_mount() {
	if [[ -n "${bubble_grants[kvm]:-}" ]]; then
		bwrap_args+=(--dev-bind /dev/kvm /dev/kvm)
	fi
}

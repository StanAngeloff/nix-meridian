# shellcheck shell=bash
# Runs a command in a new user and network namespace whose only link is loopback: the plannotator wrapper's last step,
# so the server, and every program it starts, the review window included, can reach nothing off this machine.
# A network namespace alone isolates nothing here: pathname Unix sockets cross it, and some lead out,
# such as resolved's DNS API, the nix daemon, which downloads on request, or an MCP daemon under $HOME.
# So no socket crosses but the compositor's.
# Empty tmpfs mounts cover /tmp, /run and the nix daemon's and garbage collector's socket directories;
# /dev/null covers every other socket found at the start, whether bound there or bind-mounted,
# as the bubble mounts the gpg agent's.
# A socket that appears later, or one bound from another network namespace, is not covered.
# The PID namespace stays the caller's, since /plannotator-last finds its conversation by walking up parent processes.
# Usage: plannotator-isolate <command> [argument...]

# The compositor socket is the review window's one way out; resolved as the bubble's clipboard module does.
wayland_display="${WAYLAND_DISPLAY:-wayland-0}"
if [[ "$wayland_display" == /* ]]; then
	wayland_socket_path="$wayland_display"
else
	wayland_socket_path="${XDG_RUNTIME_DIR:-}/$wayland_display"
fi

masked_paths=(/tmp /run /nix/var/nix/daemon-socket /nix/var/nix/gc-socket)

declare -A candidate_paths=()
# Whether a path needs a cover of its own: absolute, not the compositor's, and outside the masked directories.
needs_cover() { # <path>
	local masked_path
	[[ "$1" == /* && "$1" != "$wayland_socket_path" ]] || return 1
	# NixOS links /var/run to /run.
	for masked_path in "${masked_paths[@]}" /var/run; do
		[[ "$1" != "$masked_path"/* ]] || return 1
	done
}
add_candidate() { # <path>
	if needs_cover "$1"; then
		candidate_paths["$1"]=1
	fi
}
# Sockets bound to a path, from the socket table of this network namespace: the host's, which the bubble shares.
# Read whole first: bash reads a /proc file byte by byte, which costs a third of a second here.
socket_table="$(</proc/net/unix)"
while read -r _ _ _ _ _ _ _ socket_path; do
	add_candidate "$socket_path"
done <<<"$socket_table"
# Sockets bind-mounted elsewhere. A file bind mount always has a root other than /, so mount points whose root is /,
# every network file system's among them, are skipped without a stat. Special characters come escaped in octal.
mount_table="$(</proc/self/mountinfo)"
while read -r _ _ _ mount_root mount_point _; do
	[[ "$mount_root" != / ]] || continue
	# Each \ooo becomes \0ooo, the form %b reads, so a digit right after an escape stays a digit.
	printf -v mount_point '%b' "${mount_point//\\/\\0}"
	add_candidate "$mount_point"
done <<<"$mount_table"

# --chdir: a working directory the masks hide fails loudly, where bwrap would quietly fall back to $HOME.
bwrap_args=(--unshare-user --unshare-net --die-with-parent --bind / / --dev /dev --chdir "$PWD")
# The GPU's render nodes, which the fresh /dev leaves out, so the review window draws on the GPU.
# The card nodes beside them, which reach the display, stay out; the kernel's GPU driver becomes reachable from inside.
for render_node_path in /dev/dri/renderD*; do
	if [[ -c "$render_node_path" ]]; then
		bwrap_args+=(--dev-bind "$render_node_path" "$render_node_path")
	fi
done
# Each cover goes on the socket's real path: bwrap mounts before it enters the new root,
# so a path through an absolute symbolic link would resolve outside it and stop bwrap.
# One realpath call resolves them all and drops paths that no longer exist.
declare -A covered_socket_paths=()
if ((${#candidate_paths[@]} > 0)); then
	while IFS= read -r -d '' socket_path; do
		if needs_cover "$socket_path" && [[ -S "$socket_path" ]]; then
			covered_socket_paths["$socket_path"]=1
		fi
	done < <(@realpath@ --canonicalize-existing --zero -- "${!candidate_paths[@]}" 2>/dev/null || true)
fi
for socket_path in "${!covered_socket_paths[@]}"; do
	bwrap_args+=(--ro-bind /dev/null "$socket_path")
done
# Only where the directory exists: the Nix build sandbox, where installCheck runs the wrapper, has no /run.
for masked_path in "${masked_paths[@]}"; do
	if [[ -d "$masked_path" ]]; then
		bwrap_args+=(--tmpfs "$masked_path")
	fi
done
# NixOS resolves PATH entries and /etc links through /run/current-system.
if [[ -e /run/current-system ]]; then
	bwrap_args+=(--ro-bind /run/current-system /run/current-system)
fi
# NixOS's graphics drivers, which the render nodes need.
if [[ -e /run/opengl-driver ]]; then
	bwrap_args+=(--ro-bind /run/opengl-driver /run/opengl-driver)
fi
if [[ -S "$wayland_socket_path" ]]; then
	bwrap_args+=(--ro-bind "$wayland_socket_path" "$wayland_socket_path")
fi

exec @bwrap@ "${bwrap_args[@]}" -- "$@"

# The GPU's render nodes (on by default), for windows started in the bubble, such as Plannotator's review window.
# A render node submits work to the GPU and holds its memory; the card nodes beside it, which reach the display, stay out.
# The kernel's GPU driver becomes reachable from inside, so a bug in it would be a way out; --without-gpu takes it away.
gpu_mount() {
	if [[ -n "${bubble_grants[gpu]:-}" ]]; then
		local render_node_path
		for render_node_path in /dev/dri/renderD*; do
			if [[ -c "$render_node_path" ]]; then
				bwrap_args+=(--dev-bind "$render_node_path" "$render_node_path")
			fi
		done
	fi
}

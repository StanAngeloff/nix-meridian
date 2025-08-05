pid_file="/run/user/$(id -u)/VoxInput.pid"

if tty -s && [ -n "$TERM" ]; then
	c_dim="$(tput setaf 8)"
	c_reset="$(tput sgr0)"
else
	c_dim=""
	c_reset=""
fi

prg_name='@name@'

log() {
	echo "${c_dim}[${prg_name}] $(date '+%Y-%m-%d %H:%M:%S') ┃ ${c_reset}$*"
}

indent() {
	local prefix="$1"
	shift
	while IFS= read -r line; do
		log "${prefix}${line}"
	done
}

log "🎤 Starting…"

# Clean up previous instances if they exist.
if [[ -f "$pid_file" ]]; then
	pid_to_kill=$(cat "$pid_file")
	if kill -0 "$pid_to_kill" &>/dev/null; then
		log "Terminating existing process ($pid_to_kill)…"
		kill "$pid_to_kill"
		# Give it time to shut down gracefully, checking frequently.
		if ! wait "$pid_to_kill" 2>/dev/null; then
			for ((i = 0; i < 10; i++)); do
				if ! kill -0 "$pid_to_kill" &>/dev/null; then
					break
				fi
				sleep 0.5
			done
			if kill -0 "$pid_to_kill" &>/dev/null; then
				log "Process did not terminate, sending SIGKILL."
				kill -9 "$pid_to_kill"
			fi
		fi
	fi
	rm -f "$pid_file"
fi

# Check for rogue processes and kill those, too.
rogue_pids=$(pgrep -f 'voxinput listen' || true)
if [[ -n "$rogue_pids" ]]; then
	log "Terminating rogue processes: $rogue_pids"
	# shellcheck disable=SC2086 # double quote not wanted, word splitting is intended.
	kill $rogue_pids
fi

# Start the listener in the background and capture its output.
coproc voxinput_listen { @voxinput@ listen --no-realtime 2>&1; }

cleanup() {
	log "Cleaning up…"

	# Kill the coprocess if it's still running.
	# shellcheck disable=SC2154 # voxinput_listen_PID is defined by coproc.
	if kill -0 "${voxinput_listen_PID}" &>/dev/null; then
		kill "${voxinput_listen_PID}"
	fi

	if [[ -f "$pid_file" ]]; then
		pid_to_kill=$(cat "$pid_file")
		if kill -0 "$pid_to_kill" &>/dev/null; then
			log "Terminating listener process ($pid_to_kill)…"
			kill "$pid_to_kill"
		fi
		rm -f "$pid_file"
	fi

	log "Finished cleanup."
}
trap cleanup EXIT

# Wait for the listener to be ready.
while read -r -u "${voxinput_listen[0]}" line; do
	echo "$line" | indent "${c_dim}voxinput │ ${c_reset}"
	if [[ "$line" == *"Waiting for record signal..."* ]]; then
		break
	fi
done

# Start recording.
(@voxinput@ record 2>&1 | indent "${c_dim}voxinput │ ${c_reset}") &

# Wait for confirmation that recording has started.
while read -r -u "${voxinput_listen[0]}" line; do
	echo "$line" | indent "${c_dim}voxinput │ ${c_reset}"
	if [[ "$line" == *"Recording..."* ]]; then
		break
	fi
done

# Show a dialog to the user to stop recording (or bail out).
if ! @zenity@ --info --width=300 --title="voxinput" --icon="@icon@" --text="<span size='large'>Recording…</span>" --ok-label="Stop" --extra-button="Cancel" 2>/dev/null 1>&2; then
	# "Cancel" was clicked or dialog closed.
	log "Cancelling recording…"
	# This assumes killing the coproc also stops the recording without transcription.
	# The cleanup trap will handle killing the coproc.
	exit 1
fi

log "Stopping recording…"
# Stop recording and let transcription happen.
(@voxinput@ stop 2>&1 | indent "${c_dim}voxinput │ ${c_reset}") &

@notify-send@ --app-name="$prg_name" --icon="@icon@" "Transcribing…" "Your recording is being transcribed – once ready the transcribed text will be sent to the active window."

# Wait for the listener to return to the waiting state, then exit.
while read -r -u "${voxinput_listen[0]}" line; do
	echo "$line" | indent "${c_dim}voxinput │ ${c_reset}"
	if [[ "$line" == *"Waiting for record signal..."* ]]; then
		break
	fi
done

log "✅ Transcription complete. Exiting."

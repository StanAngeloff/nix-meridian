pid_file="/run/user/$(id -u)/VoxInput.pid"

if tty -s && [[ -n "$TERM" ]]; then
	c_dim="$(tput setaf 8)"
	c_yellow="$(tput setaf 3)"
	c_reset="$(tput sgr0)"
else
	c_dim=""
	c_yellow=""
	c_reset=""
fi

prg_name='@name@'

log_file="/run/user/$(id -u)/${prg_name}.log"
echo -n >"$log_file"

log() {
	echo "${c_dim}[${prg_name}] $(date '+%Y-%m-%d %H:%M:%S') ┃ ${c_reset}$*" | tee -a >(sed -r "s/\x1B\[[0-9;]*[mK]//g" >>"$log_file")
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

# Let's determine if we have a nearest prompt file we can read.
window_in_focus_cwd=
# Start by grabbing the currently focused window PID.
window_in_focus_pid=$(@busctl@ --user -j call org.gnome.Shell /org/gnome/Shell/Extensions/Windows org.gnome.Shell.Extensions.Windows List | jq -r '.data[0]' | jq '.[] | select(.focus == true) | .pid' || true)
# If we were invoked as a command within a terminal, we can use the current working directory.
if tty -s && [[ -n "$TERM" ]]; then
	window_in_focus_cwd=$(readlink -f "$PWD" || true)
elif [[ -n "$window_in_focus_pid" ]]; then
	# Let's capture the command-line of the focused window.
	window_in_focus_cmd="$(tr '\0' ' ' </proc/"$window_in_focus_pid"/cmdline || true)"
	log "Focused window PID: $window_in_focus_pid"
	log "Focused window command-line: $window_in_focus_cmd"
	# If the command running is Ghostty with nested tmux, we want to delve deeper.
	if [[ "$window_in_focus_cmd" == *"/bin/ghostty"* && "$window_in_focus_cmd" == *"/bin/tmux"* ]]; then
		log "Focused window is Ghostty with nested tmux."
		# Let's grab the process name in the current tmux pane.
		tmux_active_pane_command=$(@tmux@ display-message -p '#{pane_current_command}' || true)
		log "tmux pane command: $tmux_active_pane_command"
		# If the command is `nvim`, we want to delve even deeper.
		if [[ "$tmux_active_pane_command" == "nvim" ]]; then
			log "tmux pane is running Neovim."
			# Let's grab the PID of the Neovim process in the current tmux pane.
			nvim_pid=$(@pgrep@ -t "$(@tmux@ display-message -p -F "#{pane_tty}" | sed 's|/dev/||')" nvim || true)
			if [[ -n "$nvim_pid" ]]; then
				log "Neovim PID: $nvim_pid"
				# If we have a Neovim PID, we can read the current working directory from it.
				window_in_focus_cwd=$(readlink -f "/proc/$nvim_pid/cwd" || true)
			else
				log "tmux is running Neovim, but no PID found."
			fi
		else
			# Otherwise, we can just use the current working directory of the tmux pane.
			window_in_focus_cwd=$(readlink -f "$(@tmux@ display-message -p -F "#{pane_current_path}" || true)" || true)
		fi
	else
		# Otherwise, we can just use the current working directory of the process.
		window_in_focus_cwd=$(readlink -f "/proc/$window_in_focus_pid/cwd" || true)
	fi
fi

# Look for a WHISPER.txt prompt file in the working directory.
if [[ -n "$window_in_focus_cwd" && -d "$window_in_focus_cwd" ]]; then
	prompt_file="$window_in_focus_cwd/WHISPER.txt"
	if [[ -f "$prompt_file" ]]; then
		log "Using WHISPER.txt prompt file: $prompt_file"
		# Read the prompt file and export it as an environment variable.
		VOXINPUT_PROMPT="$(tr '\r\n' ' ' <"$prompt_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)"
		export VOXINPUT_PROMPT
	else
		log "No WHISPER.txt prompt file found in $window_in_focus_cwd."
	fi
else
	log "No valid working directory found for the focused window."
fi

# Check for rogue processes and kill those, too.
rogue_pids=$(@pgrep@ -f 'voxinput listen' || true)
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
if ! @zenity@ --info \
	--width="$([[ -n "${VOXINPUT_PROMPT:-}" ]] && echo 520 || echo 300)" \
	--title="voxinput" \
	--icon="@icon@" \
	--text="<span size='large'>Recording…</span>${VOXINPUT_PROMPT:+"\\n\\n<span foreground='gray'>Prompt: <i>${VOXINPUT_PROMPT//&/\\&amp;}</i></span>"}" \
	--ok-label="Stop" \
	--extra-button="Cancel" 2>/dev/null 1>&2; then
	# "Cancel" was clicked or dialog closed.
	log "Cancelling recording…"
	# This assumes killing the coproc also stops the recording without transcription.
	# The cleanup trap will handle killing the coproc.
	exit 1
fi

log "Stopping recording…"
# Stop recording and let transcription happen.
(@voxinput@ stop 2>&1 | indent "${c_dim}voxinput │ ${c_reset}") &

notification_id=$(@notify-send@ --app-name="$prg_name" --category=task --icon="@icon@" --urgency=normal --expire-time=3000 --transient --print-id "⏳ Transcribing…" "Your recording is being transcribed – once ready the transcribed text will be sent to the clipboard.")

# Wait for the listener to return to the waiting state, then exit.
while read -r -u "${voxinput_listen[0]}" line; do
	echo "$line" | indent "${c_dim}voxinput │ ${c_reset}"
	if [[ "$line" == *"Waiting for record signal..."* ]]; then
		break
	fi
done

# At this point the transcription should be complete and in the clipboard.
# However, Whisper isn't great at sentence prediction or punctuation, let's do a bit of post-processing via Haiku (not going to break the bank with that one).
@llm@ -m claude-haiku-4.5 \
	--key "$(secret-tool lookup service anthropic key api 2>/dev/null)" \
	--system "$( echo -e "You will be given a transcription of the user's microphone.${VOXINPUT_PROMPT:+" The transcription agent was given the following additional context: <transcription_context>${VOXINPUT_PROMPT}</transcription_context>"}\nFix spelling mistakes, apply punctuation, correctly separate sentences and re-format as readable paragraphs.\nApply Markdown **bold** and _emphasis_, use CAPITALS sparingly ONLY when and where appropriate.\n\nDo not add any additional text or commentary.\nDo not modify the meaning of the transcription in any way - do not summarize.\n\nYour job is to fixup, not rewrite.\nAfter you are done, if certain parts do not make sense, remember the user is technical - attempt to replace one or two words which might have been mistranscribed with popular SaaS product names." )" \
	"$(wl-paste)" |	wl-copy

# Let's try and paste into the active window. If we call busctl just once, it doesn't correctly refresh the focused window PID, so we call it again.
@busctl@ --user -j call org.gnome.Shell /org/gnome/Shell/Extensions/Windows org.gnome.Shell.Extensions.Windows List >/dev/null || true
window_in_focus_pid=$(@busctl@ --user -j call org.gnome.Shell /org/gnome/Shell/Extensions/Windows org.gnome.Shell.Extensions.Windows List | jq -r '.data[0]' | jq '.[] | select(.focus == true) | .pid' || true)
if tty -s && [[ -n "$TERM" ]]; then
	echo "$c_yellow"
	wl-paste --no-newline
	echo "$c_reset"
	echo
elif [[ -n "$window_in_focus_pid" ]]; then
	window_in_focus_cmd="$(tr '\0' ' ' </proc/"$window_in_focus_pid"/cmdline || true)"
	log "Focused window PID: $window_in_focus_pid"
	log "Focused window command-line: $window_in_focus_cmd"
	if [[ "$window_in_focus_cmd" == *"/bin/ghostty"* ]]; then
		if [[ "$window_in_focus_cmd" == *"/bin/tmux"* ]]; then
			log "Focused window is Ghostty with nested tmux."
			tmux_active_pane_command=$(@tmux@ display-message -p '#{pane_current_command}' || true)
			log "tmux pane command: $tmux_active_pane_command"
			if [[ "$tmux_active_pane_command" == "nvim" ]]; then
				log "tmux pane is running Neovim."
				log "Sending sequence to paste into Neovim."
				@tmux@ send-keys 'C-c' 'C-c' ',pa'
			else
				log "tmux pane is running: $tmux_active_pane_command"
				log "Sending Ctrl+Shift+V to tmux pane."
				echo 'key ctrl+shift+v' | @dotool@
			fi
		else
			log "Focused window is Ghostty. Sending Ctrl+Shift+V."
			echo 'key ctrl+shift+v' | @dotool@
		fi
	else
		log "Sending Ctrl+V to focused window."
		echo 'key ctrl+v' | @dotool@
	fi
fi

@notify-send@ --app-name="$prg_name" --category=task --icon="@icon@" --urgency=low --expire-time=1000 --transient --replace-id="$notification_id" "✅ Transcribed" "Your recording has finished transcribing."

log "✅ Transcription complete. Exiting."

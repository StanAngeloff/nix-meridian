{
  writeShellScript,
  name,
  inotify-tools,
  swappy,
}:
(writeShellScript name ''
  # Configuration
  watch_path="''${HOME}/Pictures/Screenshots"

  log_path="''${XDG_STATE_HOME:-$HOME/.local/state}/swappy"
  log_file="launcher.log"

  # Create the watch and log directories if they don't exist
  mkdir -p "$watch_path"
  mkdir -p "$log_path"

  # Set up logging
  log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$log_path/$log_file"
  }

  log "Starting screenshot monitor for $watch_path"

  # Export display variables to allow GUI apps to work
  export DISPLAY=":0"
  export WAYLAND_DISPLAY="wayland-0"
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"

  # Get the current DBUS session address
  export DBUS_SESSION_BUS_ADDRESS="unix:path=''${XDG_RUNTIME_DIR}/bus"

  # Array to store Swappy PIDs
  declare -a swappy_pids=()

  # Function to clean up the PIDs list
  cleanup_pids() {
    local new_pids=()
    for pid in "''${swappy_pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        new_pids+=("$pid")
      else
        log "Swappy process $pid has terminated"
      fi
    done
    swappy_pids=("''${new_pids[@]}")
  }

  # Function to check if any Swappy process is running
  is_swappy_running() {
    cleanup_pids
    if [ ''${#swappy_pids[@]} -gt 0 ]; then
      return 0 # true, Swappy is running
    else
      return 1 # false, no Swappy running
    fi
  }

  # Monitor the directory for new files
  ${inotify-tools}/bin/inotifywait -m "$watch_path" -e create -e moved_to |
    while read -r directory action file; do
      # Skip files with .o.png extension (Swappy output files)
      if [[ "$file" == *.o.png ]]; then
        log "Skipping Swappy output file: $file"
        continue
      fi

      # Check if Swappy is already running
      if is_swappy_running; then
        log "Ignoring new file $file as Swappy is already running"
        continue
      fi

      # Sleep for a short time to allow the file to be fully written.
      sleep 0.3

      # Full path to the new file
      filepath="''${directory}''${file}"

      # Log the event
      log "New screenshot detected: $filepath (Action: $action)"

      # Check if the file exists and is readable
      if [[ -f "$filepath" && -r "$filepath" ]]; then
        log "Launching swappy for $filepath"

        # Launch swappy in the background and capture its PID
        ${swappy}/bin/swappy -f "$filepath" &
        new_pid=$!
        swappy_pids+=("$new_pid")
        log "Launched Swappy with PID: $new_pid"
      else
        log "Error: File $filepath is not accessible"
      fi
    done

  log "Screenshot monitor stopped"
'')

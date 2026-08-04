{ lib, pkgs }:
let
  jq = lib.getExe pkgs.jq;
in
{
  # Merge a jq filter into a JSON file that a running Claude Code session also owns and writes.
  #
  # Reading such a file, transforming it and writing it back races the session: Claude Code publishes its writes by
  # renaming a fresh file into place, so a write landing between our read and our write would be reverted by ours,
  # silently and without either side erroring. Every settings.json and .claude.json writer in this directory goes
  # through here for that reason.
  #
  # The guard fingerprints the file — inode, size, nanosecond mtime — builds the merged result beside it, then re-reads
  # the fingerprint immediately before renaming it into place. Any concurrent write changes at least one of the three,
  # and the rename is abandoned rather than allowed to clobber. After three attempts the merge declines and says so:
  # a setting that arrives one rebuild late is cheaper than a lost write.
  #
  # The window is narrowed, not closed. A program that read the file before our rename can still publish over us
  # afterwards, so filters must be idempotent — the next activation then simply re-applies. Idempotence is also what
  # makes the no-op check below correct: when the merge would change nothing, which is every rebuild after the first,
  # nothing is written and the file is only ever read.
  #
  # file   — absolute path, created holding {} when absent
  # filter — jq expression, applied to the whole document
  # label  — subject of the decline message, e.g. "Claude Code settings"
  # mode   — mode the file is created with; an existing file keeps its own
  mergeIntoLiveFile =
    {
      file,
      filter,
      label,
      mode ? "644",
    }:
    ''
      targetFile=${lib.strings.escapeShellArg file}

      if [[ ! -f "$targetFile" ]]; then
        echo "Creating $targetFile..."

        mkdir -p "$(dirname "$targetFile")"
        # Created at its final mode, so a file holding credentials is never briefly readable by anyone else.
        install -m ${mode} /dev/null "$targetFile"
        echo "{}" > "$targetFile"
      fi

      for attempt in 1 2 3; do
        fingerprint="$(stat -c '%i:%s:%.9Y' "$targetFile")"

        tmpFile="$(mktemp "$targetFile.nix-XXXXXX")"
        ${jq} ${lib.strings.escapeShellArg filter} "$targetFile" > "$tmpFile"
        chmod --reference="$targetFile" "$tmpFile"

        if ${jq} -e --slurpfile current "$targetFile" '. == $current[0]' "$tmpFile" > /dev/null; then
          rm -f "$tmpFile"
          break
        fi

        if [[ "$fingerprint" == "$(stat -c '%i:%s:%.9Y' "$targetFile")" ]]; then
          mv "$tmpFile" "$targetFile"
          break
        fi

        rm -f "$tmpFile"

        if [[ "$attempt" == 3 ]]; then
          echo "${label} left unchanged: $targetFile kept being written during the merge (a session is running)." >&2
        fi
      done
    '';
}

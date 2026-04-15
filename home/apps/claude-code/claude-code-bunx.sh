# Workaround for "[BUG] apply-seccomp binary loses execute bit after auto-update (Linux)"
#
# bunx drops the executable bit on vendor/seccomp/<arch>/apply-seccomp,
# so race a watcher against the extraction and chmod it before Claude Code spawns the binary.
#
# Learn more at https://github.com/anthropics/claude-code/issues/43367
cache_dir="/tmp/bunx-$(id -u)-@package@@@version@"
seccomp_bin="$cache_dir/node_modules/@package@/vendor/seccomp/x64/apply-seccomp"

fix_seccomp() {
	if [[ -e "$seccomp_bin" && ! -x "$seccomp_bin" ]]; then
		chmod +x "$seccomp_bin" 2>/dev/null || true
	fi
}

fix_seccomp

# Keep polling for 30s even after we see +x: bunx unlinks the file and extracts a fresh 0644 copy during startup (new inode),
# so a one-shot fix misses the replacement. Cheap enough — 600 stats in the background.
{
	for _ in {1..600}; do
		fix_seccomp
		sleep 0.05
	done
} &

exec bunx --silent @package@@@version@ @args@ "$@"

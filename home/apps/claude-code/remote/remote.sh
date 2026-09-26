# `cc remote`: reach cc sessions from the phone over Tailscale. Built by package.nix; the launcher hands `cc remote …` here.

_remote_usage() {
	cat <<'USAGE'
Usage: cc remote <command>

Commands:
  setup    Pair a phone: serve its setup script on this laptop's Tailscale address and register its key

First login on this laptop (once, without sudo; the flags must match the NixOS configuration):
  @firstLoginCommand@
Then disable key expiry for this machine in the Tailscale admin console (Machines → … → Disable Key Expiry).

On the phone, once paired: ssh cc
USAGE
}

case "${1:-}" in
setup)
	shift
	exec @setupExe@ "$@"
	;;
-h | --help | help)
	_remote_usage
	;;
*)
	_remote_usage >&2
	exit 2
	;;
esac

set -euo pipefail

usage() {
	echo "Usage: @name@ [options] <pkg>..." >&2
	echo "" >&2
	echo "Options:" >&2
	echo "  -h, --help             Display this help message and exit" >&2
	echo "  -c, --channel CHANNEL  Specify NixOS channel (default: nixos-unstable)" >&2
	exit 1
}

channel="nixos-unstable"

# Parse options
while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		usage
		;;
	-c | --channel)
		if [[ $# -lt 2 ]]; then
			echo "Error: Missing argument for $1" >&2
			usage
		fi
		channel="$2"
		shift
		;;
	-c=* | --channel=*)
		channel="''${1#*=}"
		;;
	-*)
		echo "Error: Unknown option: $1" >&2
		usage
		;;
	*)
		break
		;;
	esac
	shift
done

# Check if there are packages specified
if [ $# -eq 0 ]; then
	echo "Error: No packages specified" >&2
	usage
fi

packages=()
for arg in "$@"; do
	packages+=("github:NixOS/nixpkgs/$channel#''${arg}")
done

exec nix shell "${packages[@]}"

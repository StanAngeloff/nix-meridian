usage() {
	echo "Usage: @name@ [options] <pkg>..." >&2
	echo "" >&2
	echo "Options:" >&2
	echo "  -h, --help             Display this help message and exit" >&2
	echo "  -c, --channel CHANNEL  Specify NixOS channel (default: nixos-unstable)" >&2
	exit 1
}

channel="nixos-unstable"

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
		channel="${1#*=}"
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

if [ $# -eq 0 ]; then
	echo "Error: No packages specified" >&2
	usage
fi

cli_packages=()
command=()
did_end_of_options=false

for arg in "$@"; do
	if ! $did_end_of_options && [[ "$arg" == "--" ]]; then
		did_end_of_options=true
	elif $did_end_of_options; then
		command+=("$arg")
	else
		cli_packages+=("$arg")
	fi
done

if [ ${#cli_packages[@]} -eq 0 ]; then
	echo "Error: No packages specified" >&2
	usage
fi

packages=()
for arg in "${cli_packages[@]}"; do
	packages+=("github:NixOS/nixpkgs/$channel#${arg}")
done

if [ ${#command[@]} -gt 0 ]; then
	exec nix shell "${packages[@]}" --command "${command[@]}"
else
	exec nix shell "${packages[@]}"
fi

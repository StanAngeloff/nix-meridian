#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo >&2 "Usage: ${0##*/} <owner/repo[.git]> <rev>"
	exit 1
fi

repo="${1%.git}"
nix32=$(nix-prefetch-url --unpack --type sha256 \
	"https://github.com/${repo}/archive/${2}.tar.gz" 2>/dev/null) || {
	echo >&2 "Failed to fetch archive"
	exit 1
}
printf '%s' "$(nix hash convert --from nix32 --to sri --hash-algo sha256 "$nix32")"

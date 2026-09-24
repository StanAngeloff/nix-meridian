#!/usr/bin/env bash
# This script updates the slopsift package to another release. Run it as pkgs/slopsift/update.sh <version>.
# It first shows how the release changes SKILL.md, the file Claude Code reads as instructions.
# Nothing changes until you answer yes.
# On yes, it regenerates package-lock.json inside the unpacked npm package.
# It then writes the new version, source hash, dependency hash and skill checksum into package.nix.
# Last, it builds the package, leaving the result for review in git diff.
# Giving the current version refreshes only the npm dependencies.
set -euo pipefail

owner_name=NikhilVerma
repository_name=writinglint
package_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_path="$(git -C "$package_path" rev-parse --show-toplevel)"
package_file="$package_path/package.nix"
lock_file="$package_path/package-lock.json"

new_version="${1:-}"
if [[ ! "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "usage: $0 <version>, for example $0 0.12.0" >&2
	exit 2
fi

for command_name in curl diff jq nix npm sha256sum; do
	if ! command -v "$command_name" >/dev/null; then
		echo "error: $command_name is not on PATH" >&2
		exit 1
	fi
done

current_version="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$package_file")"
# The script rewrites each value in place, so each must appear exactly once, in the shape it expects.
for line_pattern in '^  version = ".*";$' '^    hash = "sha256-.*";$' '^  npmDepsHash = "sha256-.*";$' '^  skillSha256 = ".*";$'; do
	if [[ "$(grep -c "$line_pattern" "$package_file")" != 1 ]]; then
		echo "error: expected exactly one line matching $line_pattern in $package_file" >&2
		exit 1
	fi
done

work_path="$(mktemp -d)"
trap 'rm -rf "$work_path"' EXIT
export npm_config_cache="$work_path/npm-cache"

skill_url() {
	echo "https://raw.githubusercontent.com/$owner_name/$repository_name/slopsift@$1/skills/slopsift/SKILL.md"
}
if ! curl -sfL "$(skill_url "$current_version")" -o "$work_path/skill-current.md"; then
	echo "error: cannot download SKILL.md for the current version $current_version" >&2
	exit 1
fi
if ! curl -sfL "$(skill_url "$new_version")" -o "$work_path/skill-new.md"; then
	echo "error: GitHub has no slopsift release $new_version (tag slopsift@$new_version)" >&2
	exit 1
fi
if [[ "$(npm view "slopsift@$new_version" version 2>/dev/null)" != "$new_version" ]]; then
	echo "error: npm has no slopsift $new_version" >&2
	exit 1
fi

echo "slopsift $current_version -> $new_version"
echo "SKILL.md changes (Claude Code reads this file as instructions):"
if diff --color=auto -u --label "SKILL.md $current_version" --label "SKILL.md $new_version" \
	"$work_path/skill-current.md" "$work_path/skill-new.md"; then
	echo "(none)"
fi
echo
read -r -p "Apply slopsift $new_version? [y/N] " answer || answer=""
if [[ "$answer" != [yY] ]]; then
	echo "Nothing changed."
	exit 0
fi

echo "Fetching the npm package..."
source_json="$(nix store prefetch-file --json --unpack --name source \
	"https://registry.npmjs.org/slopsift/-/slopsift-$new_version.tgz")"
source_hash="$(jq -r .hash <<<"$source_json")"
# package.nix fetches SKILL.md from the address above, so this checksum pins exactly the file shown.
skill_sha256="$(sha256sum "$work_path/skill-new.md" | cut -d' ' -f1)"

echo "Resolving the npm dependencies..."
cp -r "$(jq -r .storePath <<<"$source_json")" "$work_path/package"
chmod -R u+w "$work_path/package"
(
	cd "$work_path/package"
	npm install --package-lock-only --ignore-scripts --no-audit --no-fund >/dev/null
)
npm_deps_hash="$(nix run --inputs-from "$repository_path" nixpkgs#prefetch-npm-deps -- \
	"$work_path/package/package-lock.json" | tail -n 1)"

cp "$lock_file" "$work_path/package-lock.previous.json"
cp "$work_path/package/package-lock.json" "$lock_file"
sed -i \
	-e "s|^  version = \".*\";\$|  version = \"$new_version\";|" \
	-e "s|^    hash = \"sha256-.*\";\$|    hash = \"$source_hash\";|" \
	-e "s|^  npmDepsHash = \"sha256-.*\";\$|  npmDepsHash = \"$npm_deps_hash\";|" \
	-e "s|^  skillSha256 = \".*\";\$|  skillSha256 = \"$skill_sha256\";|" \
	"$package_file"

echo "Building..."
built_path="$(nix build --no-link --print-out-paths "$repository_path#nixosConfigurations.$HOSTNAME.pkgs.slopsift")"
printf 'The build passes.\n' >"$work_path/probe.md"
if ! "$built_path/bin/slopsift" "$work_path/probe.md" >/dev/null 2>&1; then
	echo "error: the built slopsift failed to lint a one-line file: $built_path/bin/slopsift" >&2
	exit 1
fi

echo
echo "Dependency changes:"
versions() {
	jq -r '.packages | to_entries[] | select(.key != "") | "\(.key | sub("^node_modules/"; "")) \(.value.version)"' "$1" | LC_ALL=C sort
}
LC_ALL=C join -a 1 -a 2 -e none -o 0,1.2,2.2 <(versions "$work_path/package-lock.previous.json") <(versions "$lock_file") |
	awk '$2 != $3 { print "  " $1 ": " $2 " -> " $3; changed = 1 } END { if (!changed) print "  (none)" }'
echo
echo "Updated to slopsift $new_version and built $built_path"
echo "Review with: git -C $repository_path diff pkgs/slopsift"

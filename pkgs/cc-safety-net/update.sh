#!/usr/bin/env bash
# This script updates the cc-safety-net package to another release. Run it as pkgs/cc-safety-net/update.sh <version>.
# It first shows the release notes, since claude-arbiter trusts this engine to decide which tool calls need a person.
# Nothing changes until you answer yes.
# On yes, it regenerates package-lock.json inside the unpacked npm package, without upstream's development dependencies.
# It then writes the new version, source hash and dependency hash into package.nix.
# Last, it builds the package and checks that the hook still denies `git reset --hard`, leaving the result for review in git diff.
# Giving the current version refreshes only the lockfile.
set -euo pipefail

owner_name=kenryu42
repository_name=cc-safety-net
package_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_path="$(git -C "$package_path" rev-parse --show-toplevel)"
package_file="$package_path/package.nix"
lock_file="$package_path/package-lock.json"

new_version="${1:-}"
if [[ ! "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "usage: $0 <version>, for example $0 2.5.0" >&2
	exit 2
fi

for command_name in curl jq nix npm; do
	if ! command -v "$command_name" >/dev/null; then
		echo "error: $command_name is not on PATH" >&2
		exit 1
	fi
done

current_version="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$package_file")"
# The script rewrites each value in place, so each must appear exactly once, in the shape it expects.
for line_pattern in '^  version = ".*";$' '^    hash = "sha256-.*";$' '^  npmDepsHash = "sha256-.*";$'; do
	if [[ "$(grep -c "$line_pattern" "$package_file")" != 1 ]]; then
		echo "error: expected exactly one line matching $line_pattern in $package_file" >&2
		exit 1
	fi
done

work_path="$(mktemp -d)"
trap 'rm -rf "$work_path"' EXIT
export npm_config_cache="$work_path/npm-cache" npm_config_update_notifier=false

if [[ "$(npm view "cc-safety-net@$new_version" version 2>/dev/null)" != "$new_version" ]]; then
	echo "error: npm has no cc-safety-net $new_version" >&2
	exit 1
fi

echo "cc-safety-net $current_version -> $new_version"
if [[ "$new_version" != "$current_version" ]]; then
	echo "Release notes (https://github.com/$owner_name/$repository_name/releases/tag/v$new_version):"
	if ! curl -sfL "https://api.github.com/repos/$owner_name/$repository_name/releases/tags/v$new_version" | jq -r '.body'; then
		echo "(GitHub has no release notes for v$new_version)"
	fi
fi
echo
read -r -p "Apply cc-safety-net $new_version? [y/N] " answer || answer=""
if [[ "$answer" != [yY] ]]; then
	echo "Nothing changed."
	exit 0
fi

echo "Fetching the npm package..."
source_json="$(nix store prefetch-file --json --unpack --name source \
	"https://registry.npmjs.org/cc-safety-net/-/cc-safety-net-$new_version.tgz")"
source_hash="$(jq -r .hash <<<"$source_json")"

echo "Resolving the npm dependencies..."
cp -r "$(jq -r .storePath <<<"$source_json")" "$work_path/package"
chmod -R u+w "$work_path/package"
(
	cd "$work_path/package"
	# package.nix drops the same field before npm reads the lockfile.
	jq 'del(.devDependencies)' package.json >package.json.new
	mv package.json.new package.json
	npm install --package-lock-only --ignore-scripts --no-audit --no-fund >/dev/null
)
# The bundle has no dependencies, so the cache is empty; package.nix sets forceEmptyCache for the same reason.
npm_deps_hash="$(FORCE_EMPTY_CACHE=true nix run --inputs-from "$repository_path" nixpkgs#prefetch-npm-deps -- \
	"$work_path/package/package-lock.json" | tail -n 1)"

cp "$lock_file" "$work_path/package-lock.previous.json"
cp "$work_path/package/package-lock.json" "$lock_file"
sed -i \
	-e "s|^  version = \".*\";\$|  version = \"$new_version\";|" \
	-e "s|^    hash = \"sha256-.*\";\$|    hash = \"$source_hash\";|" \
	-e "s|^  npmDepsHash = \"sha256-.*\";\$|  npmDepsHash = \"$npm_deps_hash\";|" \
	"$package_file"

echo "Building..."
built_path="$(nix build --no-link --print-out-paths "$repository_path#nixosConfigurations.$HOSTNAME.pkgs.cc-safety-net")"
# The hook must still refuse a built-in destructive command and stay silent on a harmless one, with no configuration at all.
mkdir -p "$work_path/home" "$work_path/configuration"
hook_decision() {
	local hook_output
	hook_output="$(jq -cn --arg command "$1" --arg cwd "$work_path" \
		'{hook_event_name: "PreToolUse", permission_mode: "default", cwd: $cwd, tool_name: "Bash", tool_input: {command: $command}}' |
		HOME="$work_path/home" CC_SAFETY_NET_HOME="$work_path/configuration" CC_SAFETY_NET_NO_UPDATE_CHECK=1 \
			"$built_path/bin/cc-safety-net" hook --coding-cli)"
	# An allowed call prints nothing at all.
	if [[ -z "$hook_output" ]]; then
		echo none
	else
		jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"$hook_output"
	fi
}
reset_decision="$(hook_decision 'git reset --hard')"
listing_decision="$(hook_decision 'ls -la')"
if [[ "$reset_decision" != deny ]]; then
	echo "error: the built hook answered '$reset_decision' to git reset --hard instead of deny: $built_path" >&2
	exit 1
fi
if [[ "$listing_decision" != none ]]; then
	echo "error: the built hook answered '$listing_decision' to ls -la instead of nothing: $built_path" >&2
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
echo "Updated to cc-safety-net $new_version and built $built_path"
echo "Review with: git -C $repository_path diff pkgs/cc-safety-net"

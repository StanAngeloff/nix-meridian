#!/usr/bin/env bash
# This script updates the plannotator package to another release. Run it as pkgs/plannotator/update.sh <version>.
# It first checks the release binary against its published checksum and its SLSA provenance against upstream's release workflow;
# either failure stops it.
# It then shows how the release changes the three SKILL.md files, which Claude Code reads as instructions,
# whether the review window's icon changed, and whether it expects another sem. Nothing changes until you answer yes.
# On yes, it writes the new version, binary hash, skill checksums and icon checksum into package.nix,
# bumps pkgs/ataraxy-sem when the sem version changed, builds the package with its skills,
# checks the version it reports and runs tests/plannotator against it, leaving the result for review in git diff.
# Giving the current version re-verifies the pinned release without changing anything.
set -euo pipefail

owner_name=backnotprop
repository_name=plannotator
package_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_path="$(git -C "$package_path" rev-parse --show-toplevel)"
package_file="$package_path/package.nix"
sem_package_file="$repository_path/pkgs/ataraxy-sem/package.nix"
skill_names=(plannotator-review plannotator-annotate plannotator-last)
# A path: flake reads the working tree as it is, untracked files included, which is what this script just edited.
flake_url="path:$repository_path"
packages_attribute="nixosConfigurations.$HOSTNAME.pkgs"
fake_hash="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

new_version="${1:-}"
if [[ ! "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "usage: $0 <version>, for example $0 0.28.0" >&2
	exit 2
fi

for command_name in curl cut diff gh jq nix sed sha256sum; do
	if ! command -v "$command_name" >/dev/null; then
		echo "error: $command_name is not on PATH" >&2
		exit 1
	fi
done

# The script rewrites each value in place, so each must appear exactly once, in the shape it expects.
require_single_line() { # <file> <pattern>
	if [[ "$(grep -c "$2" "$1")" != 1 ]]; then
		echo "error: expected exactly one line matching $2 in $1" >&2
		exit 1
	fi
}
require_single_line "$package_file" '^  version = ".*";$'
require_single_line "$package_file" '^    hash = "sha256-.*";$'
for skill_name in "${skill_names[@]}"; do
	require_single_line "$package_file" "^    $skill_name = \"[0-9a-f]*\";\$"
done
require_single_line "$package_file" '^  iconSha256 = "[0-9a-f]*";$'
require_single_line "$sem_package_file" '^  version = ".*";$'
require_single_line "$sem_package_file" '^    hash = "sha256-.*";$'
require_single_line "$sem_package_file" '^  cargoHash = "sha256-.*";$'

current_version="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$package_file")"
current_sem_version="$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$sem_package_file")"

work_path="$(mktemp -d)"
trap 'rm -rf "$work_path"' EXIT
binary_file="$work_path/plannotator-linux-x64"

raw_url() { # <version> <path in the repository>
	echo "https://raw.githubusercontent.com/$owner_name/$repository_name/v$1/$2"
}

echo "Downloading the plannotator $new_version release binary..."
release_url="https://github.com/$owner_name/$repository_name/releases/download/v$new_version/plannotator-linux-x64"
if ! curl -sfL "$release_url" -o "$binary_file" || ! curl -sfL "$release_url.sha256" -o "$binary_file.sha256"; then
	echo "error: GitHub has no plannotator release v$new_version with a linux-x64 binary" >&2
	exit 1
fi
binary_sha256="$(sha256sum "$binary_file" | cut -d' ' -f1)"
if [[ "$(cut -d' ' -f1 "$binary_file.sha256")" != "$binary_sha256" ]]; then
	echo "error: the binary does not match its published checksum" >&2
	exit 1
fi
echo "Verifying that upstream's release workflow built it from v$new_version..."
if ! gh attestation verify "$binary_file" --repo "$owner_name/$repository_name" \
	--source-ref "refs/tags/v$new_version" --deny-self-hosted-runners \
	--signer-workflow "$owner_name/$repository_name/.github/workflows/release.yml" >/dev/null; then
	echo "error: the binary's attestation does not verify against upstream's release workflow at v$new_version" >&2
	exit 1
fi

echo
echo "plannotator $current_version -> $new_version"
echo "SKILL.md changes (Claude Code reads these files as instructions):"
for skill_name in "${skill_names[@]}"; do
	skill_path="apps/skills/claude/$skill_name/SKILL.md"
	if ! curl -sfL "$(raw_url "$current_version" "$skill_path")" -o "$work_path/$skill_name-current.md"; then
		echo "error: cannot download $skill_path for the current version $current_version" >&2
		exit 1
	fi
	# The baseline must be the text package.nix pins; a tag moved since would hide changes from the diff below.
	pinned_sha256="$(sed -n "s/^    $skill_name = \"\([0-9a-f]*\)\";\$/\1/p" "$package_file")"
	if [[ "$(sha256sum "$work_path/$skill_name-current.md" | cut -d' ' -f1)" != "$pinned_sha256" ]]; then
		echo "error: $skill_path at v$current_version no longer matches its pinned checksum; upstream moved the tag" >&2
		exit 1
	fi
	if ! curl -sfL "$(raw_url "$new_version" "$skill_path")" -o "$work_path/$skill_name-new.md"; then
		echo "error: v$new_version has no $skill_path; the skill set changed, so update package.nix by hand" >&2
		exit 1
	fi
	if diff --color=auto -u --label "$skill_name $current_version" --label "$skill_name $new_version" \
		"$work_path/$skill_name-current.md" "$work_path/$skill_name-new.md"; then
		echo "$skill_name: (none)"
	fi
done

# An image, so there is no diff to show; the checksum written below pins exactly the file downloaded here.
icon_path="apps/marketing/public/favicon.png"
if ! curl -sfL "$(raw_url "$new_version" "$icon_path")" -o "$work_path/icon.png"; then
	echo "error: v$new_version has no $icon_path, the review window's icon; update package.nix by hand" >&2
	exit 1
fi
icon_sha256="$(sha256sum "$work_path/icon.png" | cut -d' ' -f1)"
if [[ "$icon_sha256" == "$(sed -n 's/^  iconSha256 = "\([0-9a-f]*\)";$/\1/p' "$package_file")" ]]; then
	echo "review window icon: unchanged"
else
	echo "review window icon: changed, see $(raw_url "$new_version" "$icon_path")"
fi

if ! curl -sfL "$(raw_url "$new_version" packages/shared/semantic-diff.ts)" -o "$work_path/semantic-diff.ts"; then
	echo "error: cannot download packages/shared/semantic-diff.ts at v$new_version" >&2
	exit 1
fi
new_sem_version="$(sed -n 's/^export const PLANNOTATOR_SEM_VERSION = "v\(.*\)";$/\1/p' "$work_path/semantic-diff.ts")"
if [[ ! "$new_sem_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "error: cannot read PLANNOTATOR_SEM_VERSION from packages/shared/semantic-diff.ts at v$new_version" >&2
	exit 1
fi
if [[ "$new_sem_version" == "$current_sem_version" ]]; then
	echo "sem stays at $current_sem_version"
else
	echo "sem $current_sem_version -> $new_sem_version (pkgs/ataraxy-sem is bumped as well)"
fi
echo
read -r -p "Apply plannotator $new_version? [y/N] " answer || answer=""
if [[ "$answer" != [yY] ]]; then
	echo "Nothing changed."
	exit 0
fi

# Everything that can fail on the network runs before the first file is rewritten.
if [[ "$new_sem_version" != "$current_sem_version" ]]; then
	echo "Fetching sem $new_sem_version..."
	sem_source_hash="$(nix store prefetch-file --json --unpack --name source \
		"https://github.com/Ataraxy-Labs/sem/archive/refs/tags/v$new_sem_version.tar.gz" | jq -r .hash)"
fi

binary_hash="$(nix hash convert --hash-algo sha256 --to sri "$binary_sha256")"
package_substitutions=(
	-e "s|^  version = \".*\";\$|  version = \"$new_version\";|"
	-e "s|^    hash = \"sha256-.*\";\$|    hash = \"$binary_hash\";|"
	-e "s|^  iconSha256 = \"[0-9a-f]*\";\$|  iconSha256 = \"$icon_sha256\";|"
)
for skill_name in "${skill_names[@]}"; do
	# package.nix fetches each SKILL.md from the address above, so this checksum pins exactly the file shown.
	skill_sha256="$(sha256sum "$work_path/$skill_name-new.md" | cut -d' ' -f1)"
	package_substitutions+=(-e "s|^    $skill_name = \"[0-9a-f]*\";\$|    $skill_name = \"$skill_sha256\";|")
done
sed -i "${package_substitutions[@]}" "$package_file"

if [[ "$new_sem_version" != "$current_sem_version" ]]; then
	sed -i \
		-e "s|^  version = \".*\";\$|  version = \"$new_sem_version\";|" \
		-e "s|^    hash = \"sha256-.*\";\$|    hash = \"$sem_source_hash\";|" \
		-e "s|^  cargoHash = \"sha256-.*\";\$|  cargoHash = \"$fake_hash\";|" \
		"$sem_package_file"
	# The source fetches cleanly first, so the only hash mismatch left in the next build is the crates'.
	nix build --no-link "$flake_url#$packages_attribute.ataraxy-sem.src"
	echo "Resolving sem's crate hash..."
	# The first build fails on the placeholder and names the hash of the vendored crates.
	cargo_hash="$(nix build --no-link "$flake_url#$packages_attribute.ataraxy-sem" 2>&1 |
		sed -n 's/^ *got: *\(sha256-[A-Za-z0-9+\/=]*\)$/\1/p' | tail -n 1 || true)"
	if [[ -z "$cargo_hash" ]]; then
		echo "error: no crate hash in the build output; run nix build $flake_url#$packages_attribute.ataraxy-sem" >&2
		exit 1
	fi
	sed -i "s|^  cargoHash = \"sha256-.*\";\$|  cargoHash = \"$cargo_hash\";|" "$sem_package_file"
fi

echo "Building..."
# With installSkills the build also fetches the three skills, which checks their checksums, and the tests need them,
# as they need spellcheckLanguage's dictionary.
built_path="$(nix build --no-link --print-out-paths --impure --expr \
	"(builtins.getFlake \"$flake_url\").$packages_attribute.plannotator.override { installSkills = true; spellcheckLanguage = \"en-GB\"; }")"
reported_version="$(HOME="$work_path" "$built_path/bin/plannotator" --version)"
if [[ "$reported_version" != "plannotator $new_version" ]]; then
	echo "error: the built plannotator reports '$reported_version'" >&2
	exit 1
fi

echo "Running the behavior tests..."
# The wrapper's protections rest on upstream's variable names and install paths, which a release can change silently.
# Node is on PATH so the runtime installs get as far as writing into vendor/; Weston hosts the review windows, headless.
if ! PLANNOTATOR_PACKAGE="$built_path" nix shell --inputs-from "$flake_url" \
	nixpkgs#python3Packages.pytest nixpkgs#nodejs nixpkgs#git nixpkgs#iproute2 nixpkgs#weston \
	--command pytest -p no:cacheprovider "$repository_path/tests/plannotator"; then
	echo "error: plannotator $new_version fails tests/plannotator; the bump stays in the working tree for review" >&2
	exit 1
fi

echo
echo "Updated to plannotator $new_version and built $built_path"
echo "Review with: git -C $repository_path diff pkgs/plannotator pkgs/ataraxy-sem"

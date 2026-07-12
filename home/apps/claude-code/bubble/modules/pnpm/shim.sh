# Bubble-only pnpm shim: injects --store-dir so pnpm records the default store path in .modules.yaml, keeping host and bubble installs compatible.
# Finds the real pnpm by filtering this shim's directory out of PATH (it may sit at any position due to writeShellApplication's runtimeInputs prepend).
shim_dir="$(cd "$(dirname "$0")" && pwd -P)"
real_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$shim_dir" | paste -sd ':')"
real_pnpm="$(PATH="$real_path" command -v pnpm)"
exec "$real_pnpm" --store-dir "$HOME/.local/share/pnpm/store" "$@"

#!/usr/bin/env bash

# Update the local Happy + VibeProxy fork from Happy upstream.
# This intentionally performs no GitHub push, release, or remote publish.

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: update-happy-vibeproxy"
  echo "Fetch upstream Happy, test, install, and restart the local daemon."
  echo "No commits are pushed and no releases are published."
  exit 0
fi

script_path="$(realpath -- "${BASH_SOURCE[0]}")"
repo_dir="$(cd -- "$(dirname -- "$script_path")/.." && pwd)"
cd "$repo_dir"

if [[ -n "${HAPPY_VIBEPROXY_BRANCH:-}" ]]; then
  target_branch="$HAPPY_VIBEPROXY_BRANCH"
else
  target_branch="$(git branch --show-current)"
fi

if [[ -z "$target_branch" ]]; then
  echo "Run this from a named Git branch." >&2
  exit 1
fi

echo "Updating local branch: $target_branch"
git fetch --prune origin main
git fetch --prune upstream main

# A local main may lag behind the fork's tested dynamic-picker commit.
if [[ "$target_branch" == "main" ]]; then
  git merge --ff-only origin/main
fi

git merge --no-edit upstream/main

if command -v pnpm >/dev/null 2>&1; then
  pnpm_command=(pnpm)
else
  pnpm_command=(npx -y pnpm@10.11.0)
fi

echo "Running Happy CLI tests"
"${pnpm_command[@]}" --filter happy test

package_dir="$(mktemp -d "${TMPDIR:-/tmp}/happy-vibeproxy-update.XXXXXX")"
cleanup() {
  rm -rf "$package_dir"
}
trap cleanup EXIT

echo "Packing the tested CLI"
"${pnpm_command[@]}" --filter happy pack --pack-destination "$package_dir" >/dev/null
package_file="$(find "$package_dir" -maxdepth 1 -type f -name '*.tgz' -print -quit)"
if [[ -z "$package_file" ]]; then
  echo "The Happy package was not created." >&2
  exit 1
fi

npm_prefix="${HAPPY_NPM_PREFIX:-$(npm config get prefix)}"
echo "Installing locally with npm prefix: $npm_prefix"
npm install --global --prefix "$npm_prefix" "$package_file"

happy_bin="$npm_prefix/bin/happy"
status_output=""
if [[ -x "$happy_bin" ]]; then
  status_output="$($happy_bin daemon status 2>&1 || true)"
fi

if [[ "$status_output" == *"Daemon is running"* ]]; then
  echo "Restarting Happy daemon"
  "$happy_bin" daemon stop
  "$happy_bin" daemon start
fi

echo "Local Happy + VibeProxy update complete"
"$happy_bin" --version

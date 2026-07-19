#!/usr/bin/env bash

# Install the latest CI-tested Happy + VibeProxy rolling release locally.
# This intentionally performs no Git merge, push, build, or release publish.

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: update-happy-vibeproxy [--check|--force]"
  echo "Install the latest CI-tested Happy + VibeProxy rolling release."
  echo "No source checkout, Git branch, or GitHub release is modified."
  exit 0
fi

check_only=false
force_update=false
case "${1:-}" in
  "") ;;
  --check) check_only=true ;;
  --force) force_update=true ;;
  *)
    echo "Unknown option: $1" >&2
    exit 2
    ;;
esac

release_repo="${HAPPY_VIBEPROXY_REPO:-cakeseyboy/happy-vibeproxy}"
release_tag="${HAPPY_VIBEPROXY_RELEASE_TAG:-vibeproxy-latest}"
npm_prefix="${HAPPY_NPM_PREFIX:-$(npm config get prefix)}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/happy-vibeproxy-updater"
state_file="$state_dir/installed-release"
installed_package="$npm_prefix/lib/node_modules/happy/package.json"

release_sha="$(gh api "repos/$release_repo/git/ref/tags/$release_tag" --jq '.object.sha')"
asset_name="$(gh release view "$release_tag" --repo "$release_repo" --json assets --jq '[.assets[] | select(.name | endswith(".tgz"))] | sort_by(.updatedAt) | last | .name')"

if [[ -z "$release_sha" || -z "$asset_name" || "$asset_name" == "null" ]]; then
  echo "The rolling release is missing its commit or npm package." >&2
  exit 1
fi

installed_release=""
if [[ -f "$state_file" ]]; then
  installed_release="$(tr -d '[:space:]' < "$state_file")"
fi

installed_is_fork=false
if [[ -f "$installed_package" ]] && node -e "const p=require(process.argv[1]); process.exit(p.happyVibeProxyFork === true ? 0 : 1)" "$installed_package"; then
  installed_is_fork=true
fi

if [[ "$installed_release" == "$release_sha" && "$installed_is_fork" == true && "$force_update" == false ]]; then
  echo "Happy + VibeProxy is already current at ${release_sha:0:12}."
  exit 0
fi

if [[ "$check_only" == true ]]; then
  echo "Happy + VibeProxy update available: ${release_sha:0:12}."
  exit 0
fi

package_dir="$(mktemp -d "${TMPDIR:-/tmp}/happy-vibeproxy-release.XXXXXX")"
cleanup() {
  rm -rf "$package_dir"
}
trap cleanup EXIT

checksum_name="$asset_name.sha256"
echo "Downloading tested release ${release_sha:0:12}"
gh release download "$release_tag" \
  --repo "$release_repo" \
  --pattern "$asset_name" \
  --pattern "$checksum_name" \
  --pattern 'commit.txt' \
  --dir "$package_dir"

artifact_sha="$(tr -d '[:space:]' < "$package_dir/commit.txt")"
if [[ "$artifact_sha" != "$release_sha" ]]; then
  echo "Rolling release is being updated; commit and package do not match yet." >&2
  exit 1
fi

(
  cd "$package_dir"
  sha256sum --check "$checksum_name"
)

package_file="$package_dir/$asset_name"
tar -tzf "$package_file" | grep -qx 'package/LICENSE'
tar -tzf "$package_file" | grep -qx 'package/FORK_NOTICE.md'
tar -xOf "$package_file" package/package.json | node -e "let value=''; process.stdin.on('data', chunk => value += chunk); process.stdin.on('end', () => { const p=JSON.parse(value); process.exit(p.happyVibeProxyFork === true ? 0 : 1); });"

happy_bin="$npm_prefix/bin/happy"
daemon_was_running=false
if [[ -x "$happy_bin" ]]; then
  status_output="$($happy_bin daemon status 2>&1 || true)"
  if [[ "$status_output" == *"Daemon is running"* ]]; then
    daemon_was_running=true
  fi
fi

echo "Installing the verified package locally"
npm install --global --prefix "$npm_prefix" "$package_file"

if ! node -e "const p=require(process.argv[1]); process.exit(p.happyVibeProxyFork === true ? 0 : 1)" "$installed_package"; then
  echo "Installed package is not marked as the Happy + VibeProxy fork." >&2
  exit 1
fi

if [[ "$daemon_was_running" == true ]]; then
  echo "Restarting Happy daemon; managed sessions stay alive"
  "$happy_bin" daemon stop
  "$happy_bin" daemon start
fi

mkdir -p "$state_dir"
state_temp="$state_file.tmp.$$"
printf '%s\n' "$release_sha" > "$state_temp"
mv "$state_temp" "$state_file"

echo "Happy + VibeProxy updated to ${release_sha:0:12}."
"$happy_bin" --version

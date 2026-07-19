# Happy + VibeProxy

This fork makes Happy's mobile model picker follow the model registry owned by
VibeProxy/`claude-code-proxy`. Each new Claude session runs:

```text
claude-code-proxy models --full
```

Happy checks provider authentication, publishes the usable model IDs through
session metadata, and sends the selected ID back to Claude Code unchanged.
Adding, removing, or renaming a proxy model therefore requires no Happy patch.

## Configuration

- `HAPPY_VIBEPROXY_BIN=/path/to/binary` selects a compatible proxy binary.
- `HAPPY_VIBEPROXY_PROVIDERS=codex,kimi` explicitly selects providers.
- `HAPPY_VIBEPROXY_PROVIDERS=all` publishes every provider in the catalog.

Without overrides, the fork tries `vibeproxy` and `claude-code-proxy`, including
their common user-local install paths. It publishes providers whose `auth
status` command succeeds. If a compatible binary has no auth-status command,
all parsed providers are retained.

## Automated builds

The `VibeProxy Happy CLI` workflow tests, builds, packs, and uploads an
installable npm tarball on each change. Successful pushes to `main` replace the
asset in the `vibeproxy-latest` rolling release.

The daily `Sync Happy upstream` workflow merges `slopus/happy:main`, validates
the model-discovery tests and CLI build, then pushes the tested merge. Merge
conflicts stop the workflow for manual resolution instead of overwriting fork
changes.

## Local update

From this checkout, run:

```bash
./scripts/update-local-vibeproxy.sh
```

The helper fetches Happy upstream, merges it into the current local fork
branch, runs the Happy CLI tests, packs the CLI, installs it into the local npm
prefix, and restarts the Happy daemon only after the tests pass. It does not
push commits or publish releases.

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
their common user-local install paths. It publishes only providers whose `auth
status` command succeeds. Compatible binaries without that command must set
`HAPPY_VIBEPROXY_PROVIDERS=all` or an explicit provider list.

## Automated builds

The `VibeProxy Happy CLI` workflow runs the complete Happy CLI unit suite on
Node 20 and 24 before packaging. Successful pushes to `main` move the rolling
tag to the tested commit and publish a checksummed npm tarball in the
`vibeproxy-latest` release.

The daily `Sync Happy upstream` workflow merges `slopus/happy:main`, runs the
complete Happy CLI test suite, then pushes the tested merge and dispatches the
rolling-release workflow. Merge conflicts or failed tests stop the workflow
before it can publish broken changes.

## Local update

Run:

```bash
update-happy-vibeproxy
```

The helper compares the installed commit with the CI-tested rolling release.
When an update exists, it downloads the package and checksum, verifies the
checksum, license, and fork identity, installs it into the local npm prefix,
and restarts the Happy daemon. It does not modify a source checkout, push
commits, build locally, or publish releases.

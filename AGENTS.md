# Development workflow

- Develop from a normal source checkout, not from a copy installed in an Omarchy plugin directory. Omarchy recursively watches its plugin directory and may reload the shell for every file changed beneath it, potentially causing Quickshell to crash during development.

# Releases

- Follow [`RELEASING.md`](RELEASING.md) for every release.
- Keep `master` stable and releasable because Omarchy plugin updates fast-forward the default branch rather than resolving release tags.
- Keep the `manifest.json` version, `v<version>` Git tag, and GitHub release version identical.
- Never move or replace a published release tag; publish a new patch release for corrections.

# Extensions

- Read [`EXTENSIONS.md`](EXTENSIONS.md) before adding or changing launcher extensions.
- Optional extensions are independent Omarchy plugins that contribute extension definitions through their manifests; they must not be bundled with Omalaunch.

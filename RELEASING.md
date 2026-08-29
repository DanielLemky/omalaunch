# Release workflow

Omalaunch follows [Semantic Versioning](https://semver.org/). The version in
`manifest.json`, the Git tag, and the GitHub release must match. Tags use a `v`
prefix; for example, manifest version `0.2.0` is released as `v0.2.0`.

Omarchy installs the repository's default branch and updates plugins by
fast-forwarding that checkout. It does not currently resolve releases or use
`manifest.json` to select a version. Therefore, `master` must always remain
stable and releasable. Tags and GitHub releases provide immutable reference and
rollback points rather than controlling plugin updates.

## Versioning

Choose the next version according to the user-visible impact:

- **Patch** (`0.1.1`): compatible fixes and documentation corrections.
- **Minor** (`0.2.0`): compatible features or meaningful behavior changes.
- **Major** (`1.0.0`): incompatible changes after the project reaches 1.0.

While the project is pre-1.0, increment the minor version for changes that may
require users or extension authors to adapt.

## Prepare the release

1. Start from an up-to-date release branch created from `master` in a dedicated
   worktree.
2. Confirm the intended release changes are already documented in the README or
   other relevant documentation.
3. Update `version` in `manifest.json`.
4. Run the complete test suite:

   ```bash
   node tests/menu-model-test.js
   bash tests/manifest-test.sh
   bash tests/qalc-integration-test.sh
   bash tests/timezone-integration-test.sh
   ```

   The integration tests require their documented system dependencies.
5. Review the complete diff and commit the version bump with a message such as
   `Release v0.2.0`.
6. Merge the release change into `master`. Do not tag an unmerged branch.

## Publish the release

From an up-to-date, clean `master` checkout:

```bash
version=$(jq -r '.version' manifest.json)
git tag -a "v$version" -m "Omalaunch v$version"
git push origin master
git push origin "v$version"
```

Create a GitHub release from the tag and summarize user-visible features,
fixes, compatibility notes, and any new dependencies. With the GitHub CLI:

```bash
gh release create "v$version" --verify-tag --generate-notes
```

Review generated notes before publishing when the release needs migration,
compatibility, or dependency guidance.

## Verify

After publishing:

1. Confirm the GitHub release and tag point to the same commit on `master`.
2. Confirm the tag matches `v` plus the version in `manifest.json`.
3. On a test installation, run:

   ```bash
   omarchy plugin update quantumfire.omalaunch
   omarchy restart shell
   ```

   The restart ensures the smoke test uses the updated QML rather than a stale
   component cached by the running shell.
4. Open Omalaunch and smoke-test the primary launcher and extension flows.

If a release is broken, fix it with a new patch release. Do not move or replace
a published tag.

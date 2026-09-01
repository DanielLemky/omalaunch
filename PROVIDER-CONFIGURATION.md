# Bundled provider storage

This document defines the version-1 storage contract for `omalaunch.apps`, `omalaunch.files`, and `omalaunch.extensions`.

## Ownership and locations

Each provider ID owns two independent namespaces:

- User configuration: `~/.config/omarchy/omalaunch/extensions/<provider-id>.jsonc`
- Machine-managed state: `${XDG_STATE_HOME:-~/.local/state}/omarchy/omalaunch/extensions/<provider-id>.json`

Provider selection does not copy or merge these files. A replacement has a different provider ID and never inherits either file. Selecting the original provider restores its data.

Configuration is read-only at runtime. It accepts UTF-8 JSONC comments and trailing commas. UI actions never create, normalize, or rewrite it. State is strict UTF-8 JSON and is normalized after a successful mutation. State writes use a lock for that provider ID, a private temporary file, `fsync`, and atomic replacement. Thus, concurrent mutations do not lose updates.

Both file types have a 64 KiB limit and a maximum depth of eight. The root is an object, `version` is `1`, and unknown fields are errors. An invalid file is ignored with a bounded diagnostic and is not overwritten. A missing file supplies defaults. Files for providers with no setting are not created.

The schemas in [`schemas/provider-config`](schemas/provider-config) describe user configuration. The schemas in [`schemas/provider-state`](schemas/provider-state) describe state. JSON Schema applies after JSONC parsing and does not specify byte or depth limits.

Identities are case-sensitive and are not trimmed or Unicode-normalized. IDs cannot contain control characters or `/`. Duplicate identities invalidate the complete file. Arrays preserve their order.

## Apps

Apps has no version-1 user configuration file. Interactive favorites are in `omalaunch.apps.json`:

```json
{"version": 1, "favorites": ["org.gnome.Nautilus.desktop"]}
```

`favorites` defaults to `[]`, has at most 256 unique desktop-entry IDs, and keeps missing applications for a later return.

## Files

The optional `omalaunch.files.jsonc` configuration contains only the user setting:

```jsonc
{
  "version": 1,
  // Also search paths ignored by Git.
  "includeGitIgnored": true,
}
```

`includeGitIgnored` defaults to `false`. Omalaunch does not create this file when the default is used.

Typed favorites are in state:

```json
{
  "version": 1,
  "favorites": [
    {"type": "directory", "path": "/home/alice/Documents"},
    {"type": "file", "path": "/home/alice/notes.txt"}
  ]
}
```

There are at most 256 favorites. `type` is `file` or `directory`. A path is 1 to 4096 characters and starts with `/` or `~/`. Before storage, the provider expands a leading `~/`, removes repeated separators and `.` parts, resolves `..` lexically, and removes a trailing separator except at `/`. It does not access the filesystem or resolve symlinks. Identity is `(type, normalized absolute path)`.

## Extensions

Extensions has no version-1 user configuration file. Exact provider-ID favorites are in `omalaunch.extensions.json`:

```json
{"version": 1, "favorites": ["omalaunch.files", "example.calculator"]}
```

The array defaults to `[]` and has at most 256 unique values. A replacement provider is not starred unless its own ID is present.

## Released shared-favorites migration

At startup, Omalaunch reads `${XDG_STATE_HOME:-~/.local/state}/omarchy/starred-launcher-items.json` and writes provider state, not configuration. It keeps the source, uses migration and provider locks, backs up existing targets, writes atomically, verifies writes, and records completion only after success. Repeated runs do not duplicate data.

- `apps.<desktop-id>` becomes an Apps favorite after removal of `apps.`.
- Bundled `file.favorite` file and directory forms become normalized Files favorites.
- `extension.root:<capability>` resolves the provider active during migration and stores that provider ID in Extensions state.
- Non-bundled, dynamic, malformed, missing, and unknown values stay in the shared source and produce bounded diagnostics.

Existing valid state entries win. Migrated entries append in source order. Invalid target state is never overwritten, and the migration retries later.

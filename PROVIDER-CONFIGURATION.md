# Bundled provider storage

This document defines the provider storage contract for `omalaunch.apps`, `omalaunch.files`, `omalaunch.quicklinks`, `omalaunch.web-search`, and `omalaunch.extensions`. Provider state and most user configuration use version 1. Web Search user configuration also supports version 2.

## Ownership and locations

Each provider ID owns two independent namespaces:

- User configuration: `~/.config/omarchy/omalaunch/extensions/<provider-id>.jsonc`
- Machine-managed state: `${XDG_STATE_HOME:-~/.local/state}/omarchy/omalaunch/extensions/<provider-id>.json`

Provider selection does not copy or merge these files. A replacement has a different provider ID and never inherits either file. Selecting the original provider restores its data.

Configuration is read-only at runtime. It accepts UTF-8 JSONC comments and trailing commas. UI actions never create, normalize, or rewrite it. State is strict UTF-8 JSON and is normalized after a successful mutation. State writes use a lock for that provider ID, a private temporary file, `fsync`, and atomic replacement. Thus, concurrent mutations do not lose updates.

Both file types have a 64 KiB limit and a maximum depth of eight. The root is an object. State and most configuration require `version` to be `1`; Web Search configuration accepts `1` or `2`. Unknown fields are errors. An invalid file is ignored with a bounded diagnostic and is not overwritten. A missing file supplies defaults. Files for providers with no setting are not created.

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

## Web Search

The optional `omalaunch.web-search.jsonc` configuration customizes 1 to 32 search engines. A missing file supplies Google, DuckDuckGo, Bing, Brave Search, and Ecosia. Each engine has a stable ID, display name, and absolute HTTP(S) URL template with exactly one `{query}` placeholder.

Version 2 starts with the bundled engines and applies at most 27 entries from its `engines` object. A new ID with `name` and `url` adds an engine. An existing bundled ID can override its name or URL. Set `enabled` to `false` to disable a bundled engine. This example adds Kagi and disables Bing:

```jsonc
{
  "version": 2,
  // Rank engines from successful searches.
  "rankByUsage": true,
  "engines": {
    "kagi": {
      "name": "Kagi",
      "url": "https://kagi.com/search?q={query}",
    },
    "bing": {
      "enabled": false,
    },
  },
}
```

Version 1 remains supported for existing configurations. Its `engines` array replaces the complete bundled list:

```jsonc
{
  "version": 1,
  "engines": [
    { "id": "google", "name": "Google", "url": "https://www.google.com/search?q={query}" },
  ],
}
```

The launcher percent-encodes the query before it replaces the placeholder. `rankByUsage` defaults to `true` and learns one rank for each engine from successful searches. Set it to `false` to disable learned ranking for the complete extension. Every engine remains available in the Web Search menu. Its action adds it to or removes it from global search and changes only `globalSearchExcludedEngines` in machine-managed state. Ctrl+S and the contextual Star action add its ID to `starredEngines`, which puts the engine on the launcher's starting view. A star implies global search: starring adds the engine to global search, and removing it from global search removes its star. Thus, UI changes do not rewrite the user JSONC file. New configured engines appear in global search unless their ID is in that state list. The menu sorts global engines first and excluded engines last, with each group sorted by name.

## Quicklinks

The optional `omalaunch.quicklinks.jsonc` configuration controls usage ranking:

```jsonc
{
  "version": 1,
  // Learn the order of links from successful Open commands.
  "rankByUsage": false,
}
```

`rankByUsage` defaults to `true`. The setting applies only when the selected provider ID is exactly `omalaunch.quicklinks`. A replacement Quicklinks provider does not inherit this file. Invalid configuration is diagnosed, is not overwritten, and uses the safe default of `true`.

Links, stars, and open method are one coherent machine-managed collection in `omalaunch.quicklinks.json`:

```json
{
  "version": 1,
  "links": [{
    "id": "docs",
    "name": "Omalaunch docs",
    "url": "https://github.com/DanielLemky/omalaunch",
    "starred": true,
    "openWith": {"type": "profile", "profile": "Work"}
  }]
}
```

This state JSON is the authoritative editable location for assigning each link's `openWith` value. Stop Omalaunch mutations while editing it. A later add, edit, star, or delete validates and normalizes the complete file, including explicit default values and field formatting. This policy avoids a fragile cross-file override keyed to mutable collection records.

`links` is required and has at most 256 entries. IDs are immutable, unique, 1 to 64 characters, start with an ASCII alphanumeric character, and then use ASCII letters, digits, `.`, `_`, or `-`. New links receive random lowercase 32-hex IDs. Names are 1 to 120 characters. URLs are absolute `http` or `https` URLs with a hostname and no user information. `starred` defaults to `false`. `openWith` defaults to `{"type":"default"}`; a profile name is 1 to 120 characters. Quicklinks accepts no file path, private URI scheme, application ID, or command.

There is no migration from any external or unreleased Quicklinks implementation.

## Released shared-favorites migration

At startup, Omalaunch reads `${XDG_STATE_HOME:-~/.local/state}/omarchy/starred-launcher-items.json` and writes provider state, not configuration. It keeps the source, uses migration and provider locks, backs up existing targets, writes atomically, verifies writes, and records completion only after success. Repeated runs do not duplicate data.

- `apps.<desktop-id>` becomes an Apps favorite after removal of `apps.`.
- Bundled `file.favorite` file and directory forms become normalized Files favorites.
- `extension.root:<capability>` resolves the provider active during migration and stores that provider ID in Extensions state.
- Non-bundled, dynamic, malformed, missing, and unknown values stay in the shared source and produce bounded diagnostics.

Existing valid state entries win. Migrated entries append in source order. Invalid target state is never overwritten, and the migration retries later.

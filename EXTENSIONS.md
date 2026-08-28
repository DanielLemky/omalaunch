# Omalaunch extensions

Every optional launcher feature is an **extension**. Omalaunch supports two delivery methods:

- **Bundled extensions** ship with Omalaunch and are enabled by default.
- **External extensions** are independent, enabled Omarchy plugins.

Both use the same extension format. An external extension with the same `capability` replaces a bundled extension; disabling or removing it restores the bundled extension.

## External plugin manifest

An Omarchy plugin declares its extension files in `manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "example.omalaunch-pi",
  "name": "Omalaunch: Pi",
  "version": "1.0.0",
  "author": "Example",
  "description": "Launch Pi prompts from Omalaunch",
  "kinds": ["extension"],
  "entryPoints": {},
  "omalaunch": {
    "extensions": ["omalaunch.json"]
  }
}
```

Paths must be relative to the plugin directory and may not contain `..`. Omalaunch only loads contributions from plugins reported as enabled by `omarchy plugin list --json`.

The original `omalaunch.queryProviders` manifest field remains accepted as an alias for compatibility.

## Prefix extension

Prefix extensions turn a prefix and prompt into an action:

```json
{
  "schemaVersion": 1,
  "id": "pi-agent",
  "capability": "pi-agent",
  "mode": "prefix",
  "label": "Pi Agent",
  "prefixes": ["pi"],
  "icon": "",
  "iconFont": "omarchy",
  "description": "Start new session",
  "command": ["omarchy-launch-terminal", "pi", "--", "{prompt}"]
}
```

Typing part of a prefix shows the extension as a result. Activating it completes the prefix and keeps Omalaunch focused for prompt entry.

## Live-query extension

Live-query extensions recognize input, run asynchronously, and display the command output:

```json
{
  "schemaVersion": 1,
  "id": "example.calculator",
  "capability": "calculator",
  "mode": "query",
  "label": "Calculator",
  "icon": "󰃬",
  "description": "Press Enter to copy",
  "priority": 10,
  "match": {
    "all": ["^\\s*\\d"],
    "any": ["[+\\-*/%]"] ,
    "none": ["[+\\-*/%(]\\s*$"]
  },
  "command": ["example-calculator", "{query}"],
  "resultCommand": ["wl-copy", "--", "{result}"]
}
```

Match rules are case-insensitive regular expressions:

- Every expression in `all` must match.
- At least one expression in `any` must match when `any` is present.
- No expression in `none` may match.

The highest-priority matching live-query extension runs. Stale results are discarded as the query changes.

## Replacement

`capability` identifies interchangeable behavior. For each capability Omalaunch selects one extension:

1. Higher `priority` wins.
2. At equal priority, an external extension wins over a bundled extension.
3. If the external extension is disabled, the bundled extension becomes active again.

## Common fields

- `schemaVersion`: Extension format version; currently `1`.
- `id`: Stable, unique extension identifier.
- `capability`: Stable behavior being supplied or replaced; defaults to `id`.
- `mode`: `prefix` or `query`; defaults to `prefix`.
- `label`, `icon`, `iconFont`, `description`: Result presentation.
- `priority`: Selection priority; defaults to `0`.
- `command`: Argument array. Prefix mode supports `{prompt}`; query mode supports `{query}`.

Commands are argument arrays. Omalaunch substitutes placeholders and shell-quotes action arguments. Do not embed pipes, redirects, or other shell syntax.

Malformed extensions are ignored. Omarchy plugins are trusted local software and extension commands run as the current user.

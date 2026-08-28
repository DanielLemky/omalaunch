# Omalaunch extensions

Omalaunch extensions are standard Omarchy plugins. Omalaunch reads query-provider contributions from enabled plugin manifests; it does not maintain a separate extension directory or installation mechanism.

## Plugin manifest

Declare provider files under the `omalaunch.queryProviders` field in `manifest.json`:

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
    "queryProviders": ["omalaunch.json"]
  }
}
```

Provider paths must be relative to the plugin directory and may not contain `..`. A plugin can contribute more than one provider file.

Install and enable the plugin through Omarchy's normal plugin workflow. Omalaunch only loads contributions from plugins reported as enabled by `omarchy plugin list --json`.

## Query provider

Each provider file contains one JSON object:

```json
{
  "schemaVersion": 1,
  "id": "pi-agent",
  "label": "Pi Agent",
  "prefixes": ["pi"],
  "icon": "",
  "iconFont": "omarchy",
  "description": "Start new session",
  "command": ["omarchy-launch-terminal", "pi", "--", "{prompt}"]
}
```

Typing part of a prefix shows the extension as a launcher result. Activating that result fills in the complete prefix and keeps the launcher focused for prompt entry.

Typing `pi explain this code` produces:

```text
Pi Agent: explain this code
Start new session
```

The command is represented as an argument array. Omalaunch replaces `{prompt}` in each argument and shell-quotes every argument before launching it. Do not put shell syntax such as pipes or redirects in `command`.

## Provider fields

- `schemaVersion`: Provider format version. Currently `1`.
- `id`: Stable, unique provider identifier.
- `label`: Text shown before the prompt.
- `prefixes`: One or more case-insensitive query prefixes.
- `icon`: Optional icon glyph.
- `iconFont`: Optional font family for the icon.
- `description`: Optional secondary text; defaults to `Start new session`.
- `command`: Required command argument array. Use `{prompt}` where the entered prompt belongs.

Malformed or incomplete providers are ignored. Omarchy plugins are trusted local software and provider commands run as the current user.

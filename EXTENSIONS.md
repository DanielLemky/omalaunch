# Omalaunch extensions

Every optional launcher feature is an **extension**. Omalaunch supports two delivery methods:

- **Bundled extensions** ship with Omalaunch and are enabled by default.
- **External extensions** are independent, enabled Omarchy plugins.

Both use the same extension format. An external extension with the same `capability` replaces a bundled extension; disabling or removing it restores the bundled extension.

## Extensions directory

Omalaunch gives every resolved bundled and external extension one shortcut in the fixed top-level **Extensions** directory. The directory is always present and cannot be starred. Its shortcuts are ordered with starred extensions first and then alphabetically.

Extension shortcuts do not otherwise appear on the launcher's starting view. Press Ctrl+S on a shortcut to promote it there; the same shortcut remains in **Extensions**, and Ctrl+S removes it from both views. Favorites use the extension's stable `capability`, so replacing a bundled provider with an external provider preserves the shortcut and its starred state. Extension roots are also included in global search whether or not they are starred.

Activating a shortcut enters the interface appropriate to its mode:

- `files` opens the file browser.
- A prefixed `query` or `prefix` extension focuses input with its prefix prepared.
- A query-only extension focuses an empty, extension-specific input (for example Calculator and Currency conversion).
- `workflow` opens its first host-rendered workflow stage.

Unavailable extensions remain listed with their missing dependency detail. Only dependencies in Omalaunch's own trusted setup allow-list offer an installation confirmation; other unavailable shortcuts cannot dispatch a command.

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

Paths must be relative to the plugin directory, may not contain `..` segments, and must resolve inside that directory (including through symlinks). Omalaunch only loads contributions from plugins reported as enabled by `omarchy plugin list --json`.

The original `omalaunch.queryProviders` manifest field remains accepted as an alias for compatibility.

## Dynamic extension catalogs

An enabled plugin may generate extension definitions when Omalaunch loads or refreshes its catalog:

```json
{
  "omalaunch": {
    "extensions": ["static-extension.json"],
    "extensionProviders": [
      ["./bin/generate-extensions", "--format", "json"],
      ["catalog-tool", "--plugin", "example.omalaunch-tools"]
    ]
  }
}
```

Each `extensionProviders` entry is a non-empty argument array. Omalaunch invokes it directly, never through a shell, with the plugin directory as its working directory and no stdin. Arguments are passed literally: shell expansion, pipes, redirects, variable expansion, and command substitution do not occur.

Executable resolution is explicit:

- An executable containing `/` is a plugin-relative path. It must resolve inside the plugin directory and have its executable bit set. Absolute paths and paths that escape through `..` or a symlink are rejected.
- An executable without `/` is looked up on Omalaunch's `PATH`.
- Other arguments are opaque strings; Omalaunch does not resolve or interpolate them.

A provider writes either one extension object or an array of extension objects to stdout. These are the same schema-version-1 definitions used by static extension files and pass through the same `MenuModel` validation, dependency checks, capability resolution, and duplicate detection. Provider definitions are external (not bundled), and their source directory is the plugin root. This is a one-shot catalog-generation contract: providers are not persistent processes and cannot answer launcher queries as an RPC service.

Providers have a five-second timeout and a 256 KiB limit on each output stream. Failure, timeout, oversized or malformed output, unsafe paths, missing executables, invalid definitions, and duplicate IDs or prefixes are logged with the plugin/provider source. One provider's failure does not discard bundled, static, or other provider extensions. The full generated catalog is limited to 768 KiB. Disabling or removing a plugin removes both its static and generated definitions on the next catalog reload; an explicit Omalaunch refresh reloads immediately.

### Trust boundary

Omarchy plugins are trusted local software. A provider and every extension command it emits run as the current user with the launcher's environment and can access that user's files and services. Argument-array execution prevents accidental shell-string injection but is **not** a sandbox or a defense against a malicious plugin. Only install and enable plugins you trust. Providers should keep generation deterministic, fast, read-only, and free of network access where possible; secrets must not be written into generated definitions or diagnostics.

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
  "requires": ["pi"],
  "command": ["omarchy-launch-terminal", "pi", "--", "{prompt}"]
}
```

Typing part of a prefix shows the extension as a result. Activating it completes the prefix and keeps Omalaunch focused for prompt entry.

## File browser extension

File browser extensions provide navigation, recursive search, opening, and path copying:

```json
{
  "schemaVersion": 1,
  "id": "example.files",
  "capability": "files",
  "mode": "files",
  "label": "Files",
  "prefixes": ["files"],
  "root": "~",
  "requires": ["fd", "fzf", "jq", "python", "xdg-open", "xdg-terminal-exec", "wl-copy"],
  "command": ["xdg-open", "{path}"],
  "directoryCommand": ["xdg-open", "{path}"],
  "terminalCommand": ["xdg-terminal-exec", "--dir={path}"],
  "copyCommand": ["wl-copy", "--", "{path}"],
  "copyFileCommand": ["copy-file-uri", "{path}"]
}
```

Ctrl+K opens the contextual Action Panel. `command` opens files, `directoryCommand` opens directories in the file manager, `terminalCommand` opens a terminal, `copyCommand` copies the path, and `copyFileCommand` places a file URI on the clipboard. All command fields support `{path}`. Files and directories can be starred from the Action Panel or with Ctrl+S and then opened directly from the launcher’s starting view. Each star retains the extension capability that created it, so the currently selected provider for that capability handles it. The bundled implementation starts at the home directory, uses `fd` traversal and fzf path ranking, omits hidden and ignored paths, and limits each ranked result set to 100 entries. Recursive candidates are indexed once per active directory and reused while typing; the index refreshes after 30 seconds or when navigation changes directories.

## Workflow extension

Workflow extensions contribute a launcher entry and a bounded tree of host-rendered stages. They can compose menus, text input, and Omalaunch's host-provided directory picker without shipping QML or implementing filesystem navigation:

```json
{
  "schemaVersion": 1,
  "id": "example.projects",
  "mode": "workflow",
  "label": "Example",
  "prefixes": ["example"],
  "requires": ["example-cli", "xdg-terminal-exec", "fd", "fzf", "python"],
  "workflow": {
    "items": [{
      "id": "projects",
      "kind": "menu",
      "label": "Projects",
      "items": [{
        "id": "add",
        "kind": "directoryPicker",
        "label": "Add Project…",
        "next": {
          "id": "name",
          "kind": "input",
          "label": "Name project",
          "prompt": "Project name",
          "default": "{basename}",
          "maxLength": 120,
          "command": ["{extensionDir}/bin/projects", "add", "{path}", "{input}"]
        }
      }]
    }]
  }
}
```

Supported node kinds are `menu`, `directoryPicker`, and `input`. Menus contain `items`; a directory picker requires a `next` node; an input may run `command` and then enter `next`. Directory selection supplies `{path}` and `{basename}`. Input supplies `{input}`. `{extensionDir}` is the contributing extension's source directory. A node's bounded string-only `context` is inherited by its descendants. `default` initializes an input, `maxLength` bounds it, and `allowEmpty` permits submission without text. `emptyCommand` selects a distinct argument array for empty input. `refreshExtensions` reloads dynamic catalogs after a successful action. `nextBackSteps` can collapse transient input/picker history after a successful save.

Commands are executed directly as argument arrays. Placeholder substitution never invokes a shell, so paths, names, and prompts remain literal arguments. Workflow trees are capped at 256 nodes and eight levels. Extensions cannot contribute QML. Escape returns through workflow stages. The directory picker reuses the Files index/browse implementation but selects directories instead of opening them. Contextual workflow Ctrl+K actions are intentionally left as a future extension point; workflow definitions do not opt into the global Files Action Panel.

A validated terminal leaf command whose executable is `xdg-terminal-exec` or `omarchy-launch-terminal` closes and resets Omalaunch as soon as it is dispatched; the launcher does not wait for a terminal wrapper to exit. Empty-input and other pre-dispatch validation failures leave the workflow open. Non-terminal commands and commands with a following stage wait for successful completion before navigating or closing.

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
  "requires": ["example-calculator", "wl-copy"],
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
- `mode`: `prefix`, `query`, `files`, or `workflow`; defaults to `prefix`.
- `label`, `icon`, `iconFont`, `description`: Result presentation.
- `priority`: Selection priority; defaults to `0`.
- `requires`: Executable names that must be available on `PATH`.
- `command`: Argument array. Prefix mode supports `{prompt}`; query mode supports `{query}`.

Commands are argument arrays. Omalaunch substitutes placeholders and shell-quotes action arguments. Do not embed pipes, redirects, or other shell syntax.

Missing dependencies leave an extension visible but unavailable with a clear message; its command cannot be activated. Omalaunch logs diagnostics for malformed definitions, unsupported schemas, duplicate IDs or prefixes, invalid regular expressions, and missing dependencies.

The `requires` field declares executable requirements only. It does not authorize package installation, and external extensions cannot provide commands for Omalaunch to install system packages. Omalaunch may offer explicit installation only for dependencies in its own trusted allow-list, after showing the exact command and receiving user confirmation.

Malformed extensions are ignored. Omarchy plugins are trusted local software and extension commands run as the current user.

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
- `emoji` opens the emoji grid.
- A prefixed `query` or `prefix` extension focuses input with its prefix prepared.
- A query-only extension focuses an empty, extension-specific input (for example Calculator and Currency conversion).
- `workflow` opens its first host-rendered workflow stage.

Unavailable extensions remain listed with their missing dependency detail. Only dependencies in Omalaunch's own trusted setup allow-list offer an installation confirmation; other unavailable shortcuts cannot dispatch a command.

A summon may name an extension capability instead of a menu id, so a compositor
keybinding can open one directly:

```bash
omarchy-shell shell summon quantumfire.omalaunch '{"extension":"emoji"}'
```

The capability is resolved through the same replacement rules as its shortcut,
so a configured or higher-priority provider answers the summon. The extension
catalog loads asynchronously; the request is held until it resolves and then
enters the extension, so the launcher never appears to ignore the keybinding.
An unknown capability is diagnosed and leaves the ordinary starting view.

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

Paths must be relative to the plugin directory, may not contain `..` segments, and must resolve inside that directory (including through symlinks). Omalaunch only loads contributions from plugins reported as enabled by `omarchy plugin list --json`. If the same enabled plugin `id` has manifests in both roots, the Omarchy-managed `OMARCHY_PATH/shell/plugins` manifest wins over `~/.config/omarchy/plugins`; lexical path order breaks ties within one root. Shadowed manifests are diagnosed and do not receive a second provider or definition budget.

The original `omalaunch.queryProviders` manifest field remains accepted as an alias for compatibility.

### Development layout

Develop every external extension in its own source repository. Do not develop inside `~/.config/omarchy/plugins/`: Omarchy watches that directory recursively and can repeatedly reload the shell while files change. For live testing, install a stable snapshot of the extension repository as the Omarchy plugin, then restore the normal installed plugin after the test.

The extension directory repository lists available extensions; it does not contain their source code. One plugin repository can provide several extension definitions, but each definition provides one capability and has its own stable extension `id`.

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

Provider loading is deliberately bounded: at most 16 providers per plugin and 64 providers total are considered; each provider has a five-second timeout and a 256 KiB limit on each output stream; all providers together receive at most 15 seconds of execution time. Plugin discovery across the managed and user roots examines at most 4,096 immediate filesystem entries, discovers/parses at most 512 manifests, and reads at most 4 MiB of manifest data in aggregate. The managed root is considered first and bounded candidate batches are processed lexically; exhausting any shared discovery budget emits one diagnostic and skips the remainder. Each individual manifest is capped at 256 KiB and may contribute at most 128 static file declarations. Bundled and external static extension files may consume at most 1 MiB of input in aggregate, and one static file or provider result may contribute at most 256 definitions. The resulting catalog accepts at most 1,024 definitions and its complete JSON output is capped at 768 KiB, with definition bytes enforced incrementally as entries are appended. Diagnostics are capped at 256 messages of 1,024 characters each.

Every parsed JSON source—the enabled-plugin list, plugin manifests, static definitions, and provider output—is limited to 32 nested object/array levels, counting its outer container as level one. Depth is checked iteratively before annotation or serialization; level 32 is accepted and level 33 is rejected. All JSON inputs are also strict: `NaN`, `Infinity`, `-Infinity`, floating-point overflow, and integers outside JavaScript's interoperable safe-integer range are rejected; catalog serialization forbids non-finite values and defensively converts recursion/serialization failures into a valid incomplete loader response. Failure, timeout, oversized, over-depth or malformed output, unsafe paths, missing executables, invalid definitions, duplicate IDs or prefixes, shadowed manifests, and every exhausted aggregate limit are logged with bounded, actionable provenance. One provider's failure or limit does not discard bundled, static, or earlier valid provider extensions.

The loader is a Python 3 program. Python is part of the current standard Omarchy installation and is also an explicit Omalaunch requirement; installations that remove it cannot load or refresh extensions or use the host file index. A transient loader/process failure, oversized loader output, or temporary failure to list enabled plugins leaves the launcher's last known-good catalog active and emits diagnostics instead of replacing it with an empty/partial catalog. Disabling or removing a plugin removes both its static and generated definitions after the next *complete* catalog reload; an explicit Omalaunch refresh reloads immediately.

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

Ctrl+K opens the contextual Action Panel. `command` opens files, `directoryCommand` opens directories in the file manager, `terminalCommand` opens a terminal, `copyCommand` copies the path, and `copyFileCommand` places a file URI on the clipboard. All command fields support `{path}`. Files and directories can be starred from the Action Panel or with Ctrl+S and then opened directly from the launcher’s starting view. Each star retains the extension capability that created it, so the currently selected provider for that capability handles it. The bundled implementation starts at the home directory, uses `fd` traversal and fzf path ranking, omits hidden and ignored paths, and limits each ranked result set to 100 entries. Exact basename matches rank before paths that match only through a parent directory, so many descendants cannot hide a matching file or directory. Recursive candidates are indexed once per active directory and reused while typing; the index refreshes after 30 seconds or when navigation changes directories.

## Emoji picker extension

Emoji picker extensions contribute a searchable grid of emoji:

```json
{
  "schemaVersion": 1,
  "id": "example.emoji",
  "capability": "emoji",
  "mode": "emoji",
  "label": "Emoji",
  "prefixes": ["emoji"],
  "icon": "",
  "description": "Press Enter to paste",
  "requires": ["omarchy-menu-emoji-insert", "wl-copy"],
  "data": "{extensionDir}/emojis.json",
  "command": ["omarchy-menu-emoji-insert", "{emoji}"],
  "copyCommand": ["wl-copy", "--", "{emoji}"]
}
```

`data` is the dataset the grid searches. Only `{omarchyPath}` and
`{extensionDir}` expand in it, the result must be an absolute path, and a path
containing `..` is rejected. It defaults to
`{omarchyPath}/shell/plugins/emojis/emojis.json`, the set Omarchy already
ships, so the bundled provider carries no second copy of the data. The file
holds an array of `{"e": "😀", "k": "grinning face smile happy"}` objects;
`{"emoji": …, "keywords": …}` and an `{"emojis": [ … ]}` wrapper are also
accepted. Duplicate glyphs, empty glyphs, non-objects, and malformed JSON are
dropped, and the grid reads at most 8192 entries and displays at most 1000
results.

`command` pastes the selected emoji and `copyCommand` places it on the
clipboard; both support `{emoji}`. Enter pastes and closes the launcher, Ctrl+C
copies and keeps the grid open so several emoji can be collected in one
session. Both record usage, so recently and frequently used emoji lead an
unfiltered grid.

Searching matches whole words and word prefixes across an entry's keywords —
`smi fac` finds `smiling face`, and every term must match. A keyword at the
front of an entry outranks one at the back. Ctrl+S pins the selected emoji to
the front of the grid; pins are keyed by capability, so replacing the provider
preserves them. Pinned emoji stay inside the picker rather than appearing on
the launcher's starting view, and match quality always outranks pins and usage
history, so a search never leads with an emoji that does not match it.

Left and Right move one cell, Up and Down move one row, PageUp and PageDown
move one screen, and Escape clears the query and then leaves the picker.

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

A validated terminal leaf command whose executable is `xdg-terminal-exec` or `omarchy-launch-terminal` is dispatched detached, then Omalaunch closes and resets immediately; the launcher does not wait for a terminal wrapper to exit. Empty-input and other pre-dispatch validation failures leave the workflow open. Non-terminal commands and commands with a following stage wait for successful completion before navigating or closing. After 30 seconds, or when their workflow/session/catalog is left or replaced, Omalaunch sends SIGTERM to the tracked direct child; if it has not exited after a one-second grace period, Omalaunch sends that same generation's direct child SIGKILL. This guarantees release of the reusable Quickshell `Process` even when the direct child ignores SIGTERM. Quickshell's `Process.signal()` targets the direct process, not a process group, so independently surviving descendants are not guaranteed to be terminated. Generation checks prevent a stale process exit or kill timer from changing a later launcher session.

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

The highest-priority matching live-query extension runs. Live queries debounce for 140 ms, run for at most five seconds, and retain only the latest pending query while a prior direct child exits. Query text, provider identity, command, and generation metadata remain immutable for that child. Replacement, timeout, empty input, focus/catalog changes, and launcher close send SIGTERM; after a 500 ms grace period a generation-matched direct child receives SIGKILL. Only `onExited` releases the reusable process and launches the latest pending query, and revision/provider/query checks reject stale output. As with workflow actions, independently surviving descendants are outside this direct-child lifecycle guarantee.

## Replacement

`capability` identifies interchangeable behavior. For each capability Omalaunch selects one extension:

1. An available provider selected in the user configuration wins.
2. Without an available configured provider, higher `priority` wins.
3. At equal priority, an external extension wins over a bundled extension.
4. If the configured provider is missing or unavailable, Omalaunch reports a diagnostic and uses the normal rules above.
5. If an external extension is disabled or removed, another available provider, including the bundled provider, becomes active.

## Common fields

- `schemaVersion`: Extension format version; currently `1`.
- `id`: Stable, unique extension identifier.
- `capability`: Stable behavior being supplied or replaced; defaults to `id`.
- `mode`: `prefix`, `query`, `files`, `workflow`, or `emoji`; defaults to `prefix`.
- `label`, `icon`, `iconFont`, `description`: Result presentation.
- `rootDescription`: Optional description for the extension shortcut in Extensions and global search. Use it when activating the extension differs from activating one of its results; defaults to `description`.
- `priority`: Selection priority; defaults to `0`.
- `requires`: Executable names that must be available on `PATH`.
- `command`: Argument array. Prefix mode supports `{prompt}`; query mode supports `{query}`.

Commands are argument arrays. Omalaunch substitutes placeholders and shell-quotes action arguments. Do not embed pipes, redirects, or other shell syntax.

Missing dependencies leave an extension visible but unavailable with a clear message; its command cannot be activated. Omalaunch logs diagnostics for malformed definitions, unsupported schemas, duplicate IDs or prefixes, invalid regular expressions, and missing dependencies.

The `requires` field declares executable requirements only. It does not authorize package installation, and external extensions cannot provide commands for Omalaunch to install system packages. Omalaunch may offer explicit installation only for dependencies in its own trusted allow-list, after showing the exact command and receiving user confirmation.

Malformed extensions are ignored. Omarchy plugins are trusted local software and extension commands run as the current user.

## Configuration

Omalaunch reads its core settings from the dedicated `~/.config/omarchy/omalaunch/config.jsonc` file. JSONC comments and trailing commas are accepted. Invalid, oversized (more than 64 KiB), over-depth, or unsupported configuration is ignored with a diagnostic. Only settings that Omalaunch validates are copied into its runtime configuration; other data does not become an extension setting.

Select a provider by extension `id` in `config.jsonc`. The key is the capability identity. If the requested provider is missing or unavailable, Omalaunch reports it and uses normal priority and replacement resolution.

```jsonc
{
  "version": 1,
  "capabilities": {
    "files": { "provider": "example.files" },
  },
}
```

Host-supported capability settings are independent of the selected provider and use one file per capability. Omalaunch does not load arbitrary configuration files for external capabilities. The first supported file is `~/.config/omarchy/omalaunch/extensions/files.jsonc`:

```jsonc
{
  "version": 1,
  // Include paths ignored by Git, but continue to honor other fd ignore rules.
  "includeGitIgnored": true,
}
```

`includeGitIgnored` defaults to `false`. When true, both directory browsing and the recursive Files index use `fd --no-ignore-vcs`.

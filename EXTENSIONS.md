# Omalaunch extensions

Every optional launcher feature is an **extension**. Omalaunch supports two delivery methods:

- **Bundled extensions** ship with Omalaunch and are enabled by default.
- **External extensions** are independent, enabled Omarchy plugins.

Both use the same extension format. An external extension with the same `capability` replaces a bundled extension; disabling or removing it restores the bundled extension.

## Extensions directory

Omalaunch gives every resolved bundled and external extension one shortcut in the fixed top-level **Extensions** directory. The directory is always present and cannot be starred. Its shortcuts are ordered with starred extensions first and then alphabetically.

Extension shortcuts do not otherwise appear on the launcher's starting view. Press Ctrl+S on a shortcut to promote it there; the same shortcut remains in **Extensions**, and Ctrl+S removes it from both views. Favorites use the extension provider's stable `id`, so a replacement does not inherit the shortcut or its starred state. Extension roots are also included in global search whether or not they are starred.

Activating a shortcut enters the interface appropriate to its mode:

- `files` opens the file browser.
- A prefixed `query` or `prefix` extension focuses input with its prefix prepared.
- A query-only extension focuses an empty, extension-specific input (for example Calculator and Currency conversion).
- `workflow` opens its first host-rendered workflow stage.
- `menu` runs its provider and opens the returned host-rendered action menu.

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

Ctrl+H toggles hidden files for the current file-browser session. Ctrl+K opens the contextual Action Panel. `command` opens files, `directoryCommand` opens directories in the file manager, `terminalCommand` opens a terminal, `copyCommand` copies the path, and `copyFileCommand` places a file URI on the clipboard. All command fields support `{path}`. Files and directories can be starred from the Action Panel or with Ctrl+S and then opened directly from the launcher’s starting view. Each star belongs to the exact provider that created it, so a replacement does not inherit bundled Files favorites. The bundled implementation starts at the home directory, uses `fd` traversal and fzf path ranking, omits hidden and ignored paths by default, includes hidden paths except `.git` internals for the current session after Ctrl+H, and limits each ranked result set to 100 entries. Exact basename matches rank before paths that match only through a parent directory, so many descendants cannot hide a matching file or directory. Recursive candidates are indexed once per active directory and reused while typing; the index refreshes after 30 seconds or when navigation changes directories.

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

Supported node kinds are `menu`, `directoryPicker`, `input`, `action`, and `confirm`. Menus contain `items`; a directory picker requires a `next` node; an input may run `command` and then enter `next`. Action and confirmation nodes run a direct command; confirmation nodes use `confirm` and optional `confirmLabel` text. Directory selection supplies `{path}` and `{basename}`. Input supplies `{input}`. `{extensionDir}` is the contributing extension's source directory. A node's bounded string-only `context` is inherited by its descendants. `default` initializes an input, `maxLength` bounds it, and `allowEmpty` permits submission without text. `emptyCommand` selects a distinct argument array for empty input. `refreshExtensions` reloads dynamic catalogs after a successful action. `nextBackSteps` can collapse transient input/picker history after a successful save.

Commands are executed directly as argument arrays. Placeholder substitution never invokes a shell, so paths, names, and prompts remain literal arguments. Workflow trees are capped at 256 nodes and eight levels. Extensions cannot contribute QML. Escape returns through workflow stages. The directory picker reuses the Files index/browse implementation but selects directories instead of opening them. Contextual workflow Ctrl+K actions are intentionally left as a future extension point; workflow definitions do not opt into the global Files Action Panel.

A validated terminal leaf command whose executable is `xdg-terminal-exec` or `omarchy-launch-terminal` is dispatched detached, then Omalaunch closes and resets immediately; the launcher does not wait for a terminal wrapper to exit. Empty-input and other pre-dispatch validation failures leave the workflow open. Non-terminal commands and commands with a following stage wait for successful completion before navigating or closing. After 30 seconds, or when their workflow/session/catalog is left or replaced, Omalaunch sends SIGTERM to the tracked direct child; if it has not exited after a one-second grace period, Omalaunch sends that same generation's direct child SIGKILL. This guarantees release of the reusable Quickshell `Process` even when the direct child ignores SIGTERM. Quickshell's `Process.signal()` targets the direct process, not a process group, so independently surviving descendants are not guaranteed to be terminated. Generation checks prevent a stale process exit or kill timer from changing a later launcher session.

## Actionable dynamic-menu extension

Dynamic-menu extensions let a trusted external plugin calculate a short menu when the user opens its shortcut. The provider is a direct argument-array command:

```json
{
  "schemaVersion": 1,
  "id": "example.quicklinks",
  "capability": "quicklinks",
  "mode": "menu",
  "label": "Quicklinks",
  "prefixes": ["links"],
  "requires": ["quicklinks"],
  "command": ["quicklinks", "menu", "--json"]
}
```

The provider receives no stdin. It writes one JSON object with an `items` array, or writes the array directly. A result can contain at most 100 rows. The process has a five-second timeout and a 256 KiB stdout limit. Invalid JSON, a nonzero exit, excessive output, duplicate row IDs, an invalid row, or an excessive row count rejects the complete snapshot. Omalaunch does not run a partial menu. Leaving the menu or closing the launcher makes the old generation stale, so its result cannot replace a later menu. Providers must be fast and should only read state.

A basic row runs `command` directly:

```json
{
  "items": [{
    "id": "docs",
    "label": "Project documentation",
    "description": "example.test/docs",
    "icon": "󰈙",
    "command": ["xdg-open", "https://example.test/docs"]
  }]
}
```

Every row requires a unique, nonempty `id` and a nonempty `label`. An ordinary row also requires a nonempty argument-array `command`. Presentation strings and command arguments are bounded. Omalaunch does not invoke a shell and does not expand command text. `{extensionDir}` and form `{input}` values are substituted as complete literal arguments. Set `closeOnSuccess: true` for launch/open rows that should close Omalaunch after the command exits successfully. Other successful menu commands reload the provider so mutations appear immediately.

A row can open an on-demand, host-rendered detail document instead of running a primary action:

```json
{
  "id": "issue:142",
  "label": "Fix authentication timeout",
  "description": "example/project #142",
  "context": { "repository": "example/project", "number": "142" },
  "document": {
    "command": ["{extensionDir}/bin/provider", "issue", "{repository}", "{number}"]
  }
}
```

The detail command uses the row context and writes one structured JSON object:

```json
{
  "title": "Fix authentication timeout",
  "subtitle": "example/project #142",
  "status": "Open",
  "fields": [
    { "label": "Author", "value": "octocat" },
    { "label": "Updated", "value": "2 hours ago" }
  ],
  "sections": [
    { "heading": "Description", "text": "Users are signed out during a slow token refresh." }
  ],
  "actions": [
    { "id": "open", "label": "Open on GitHub", "command": ["xdg-open", "https://github.com/example/project/issues/142"], "closeOnSuccess": true }
  ]
}
```

`title` is required. `subtitle` and `status` are optional. A document accepts at most 32 label/value fields, 16 plain-text sections, and 16 host-rendered actions. The complete normalized document text is limited to 64 KiB. HTML, Markdown, images, and extension QML are not accepted or interpreted. Ctrl+K opens the document actions. Escape returns to the source list.

Omalaunch runs the detail provider only after activation. It receives no stdin, has a five-second timeout, and has a 256 KiB limit on each output stream. Leaving the document, closing the launcher, replacing its session, or changing its provider invalidates the request. Cancellation sends SIGTERM and then sends SIGKILL to the same direct child after a 500 ms grace period. Detail commands run directly as argument arrays and support the row context plus `{extensionDir}` placeholders.

A row can ask for confirmation before dispatch:

```json
{
  "id": "remove",
  "label": "Remove link",
  "confirm": "Remove this saved link?",
  "confirmLabel": "Remove",
  "command": ["quicklinks", "remove", "docs"],
  "refreshExtensions": true
}
```

A row can open a host-rendered text input form. The input object supports the workflow input fields `prompt`, `default`, `maxLength`, `allowEmpty`, `emptyCommand`, `command`, and `next`. An input with `capture` stores its literal value under that named context key for interpolation by the next stage. This permits multi-step forms without temporary plugin state; backing out cancels the unfinished flow.

```json
{
  "id": "add",
  "label": "Add link",
  "input": {
    "prompt": "URL",
    "maxLength": 2048,
    "command": ["quicklinks", "add", "{input}"]
  },
  "refreshExtensions": true
}
```

A row can include up to 16 `actions`. Press Ctrl+K on that row to open its contextual action list. Each contextual action has the same direct command, confirmation, input, and refresh fields as a row, but actions cannot contain more nested actions. A row can set `starAction` to the ID of one direct contextual action; Ctrl+S then runs that action through the normal tracked lifecycle. Providers should update the row's `starred` value and the action label/command in the next snapshot.

Menu and action commands use the workflow action lifecycle. A non-terminal direct child runs for at most 30 seconds. Cancellation sends SIGTERM and then sends SIGKILL to the same direct child after one second. Stale generation checks prevent old exits from changing a new session. A successful menu mutation reloads the provider so the visible rows show current state. `refreshExtensions: true` also reloads the extension catalog after success. Failed commands leave the current menu open and do not refresh it.

Set the extension field `globalSearch: true` to include its current top-level actionable rows in Omalaunch general search. The default is `false`, so omitted and false values keep the current shortcut-only behavior. An opted-in provider can set `globalSearch: false` on an individual row to keep that row in its extension menu but omit it from general search. Omalaunch preloads opted-in, available providers and searches each row by `label`, `description`, and optional string or string-array `aliases`. A row with `starred: true` also appears on the launcher's top-level starting view; non-starred rows remain search-only. The extension root remains visible as a separate search result. Activating a cached row runs the same primary command, including confirmation or input handling, and honors `closeOnSuccess`. Ctrl+K opens the row's cached contextual actions.

The preload is one atomic cached snapshot. Omalaunch keeps the last complete snapshot if one provider fails, times out, returns invalid or excessive output, or exceeds an aggregate safeguard. At most 16 opted-in providers, 1,000 searchable rows, 1 MiB of output, and ten seconds of aggregate preload time are accepted; the existing five-second, 256 KiB, and 100-row limits still apply to each provider. Catalog changes and successful menu mutations invalidate and reload the snapshot. Generation checks reject stale provider exits. Providers must return all searchable state in the normal bounded menu response; Omalaunch does not run providers for each keystroke.

Dynamic menus are for small actionable collections, not unbounded search results or a persistent RPC protocol. The plugin remains trusted local software; argument arrays prevent accidental shell parsing but do not sandbox it.

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
- `mode`: `prefix`, `query`, `files`, `workflow`, or `menu`; defaults to `prefix`.
- `label`, `icon`, `iconFont`, `description`: Result presentation.
- `rootDescription`: Optional description for the extension shortcut in Extensions and global search. Use it when activating the extension differs from activating one of its results; defaults to `description`.
- `priority`: Selection priority; defaults to `0`.
- `requires`: Executable names that must be available on `PATH`.
- `command`: Argument array. Prefix mode supports `{prompt}`; query mode supports `{query}`; menu providers support `{extensionDir}`.

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

Provider settings are separate from capability selection. User-edited JSONC is under `~/.config/omarchy/omalaunch/extensions/`; machine-managed JSON state is under `${XDG_STATE_HOME:-~/.local/state}/omarchy/omalaunch/extensions/`. Both use the exact provider ID as the filename. A replacement provider never inherits, merges, or shares either namespace. UI mutations write only state and never rewrite JSONC comments or formatting.

The exact structures, supported versions, defaults, limits, identities, path rules, and separate configuration and state schemas are in [PROVIDER-CONFIGURATION.md](PROVIDER-CONFIGURATION.md). Apps and Extensions have no user configuration file. Files has only `includeGitIgnored` in configuration. Web Search defines its engine IDs, names, URL templates, and extension-wide `rankByUsage` setting in configuration; menu actions store global-search exclusions in state without removing engines from the Web Search menu. Quicklinks has only `rankByUsage`, which defaults to true and applies only to the exact bundled provider ID. Quicklinks uses state as the authoritative editable location for each link's `openWith` assignment and does not import external or unreleased Quicklinks data.

The bundled `omalaunch.quicklinks` extension is URL-only. It supports add, name and URL edits, delete, URL copy, default or configured browser-profile opening, filtering, global search, and extension-owned stars. It does not use favicons, file paths, or profile-editing UI.

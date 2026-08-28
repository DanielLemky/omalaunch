# Omalaunch

An extensible command launcher for [Omarchy](https://omarchy.org/).

Omalaunch keeps the familiar Omarchy command tree while adding fast global search, application results, favorites, usage-aware ranking, calculations and conversions, and independently installable extensions.

![Omalaunch demo](assets/omalaunch-demo.gif)

## Installation

```bash
omarchy plugin add https://github.com/daniellemky/omalaunch --enable
```

If needed, place the widget in the left bar section:

```bash
omarchy plugin enable quantumfire.omalaunch --section left
```

Click the Omalaunch icon to open it. Right-clicking the icon opens a terminal.

## Features

- Search the complete Omarchy command tree and installed applications
- Pin favorites and rank frequently used results
- Run arithmetic, unit conversions, and currency conversions with `qalc`
- Copy calculation results directly to the clipboard
- Browse, recursively search, open, and copy paths for local files
- Accept dmenu-style select and input requests
- Load extensions contributed by enabled Omarchy plugins
- Launch agent prompts such as Pi and Codex through optional extensions

## Starred favorites

Pin frequently used applications and commands to the launcher’s starting view.

![Starred favorites in Omalaunch](assets/starred-favorites.png)

## Calculator

Evaluate arithmetic, units, and currency conversions without leaving the launcher. Press Enter to copy the result.

![Calculator result in Omalaunch](assets/calculator.png)

## Currency conversion

Convert currencies inline using `qalc` exchange-rate data. Press Enter to copy the result.

![Currency conversion in Omalaunch](assets/currency-conversion.png)

## Files

Type `files` and activate the **Files** result to browse from your home directory. Select folders to navigate, type to search recursively within the current folder, and select a file to open it with the default application. Search uses `fd` with fzf's path-aware relevance ranking. Hidden and ignored files are excluded.

Press Ctrl+K on a selected item to open its Action Panel. Directories can be opened in Files or a terminal; files can be opened with their default application. Every item supports copying its path or copying the item to the file clipboard. Ctrl+C remains a shortcut for copying the selected path.

## Requirements

- A current Omarchy installation with the manifest-based shell plugin system
- [`libqalculate`](https://qalculate.github.io/) (`qalc`) for calculations and conversions
- `fd`, `fzf`, `jq`, Bash, and `wl-clipboard` (provided by a standard Omarchy installation)

Install the calculation dependency through Omarchy:

```bash
omarchy pkg add libqalculate
```

Omalaunch does not install system packages automatically.

## Usage

Start typing to search commands and applications. Use the arrow keys to move, Enter to activate, and Escape to go back or close the launcher.

Examples:

```text
10 USD to CAD
25 * 4
browser
wifi
files
```

Calculation results appear first and are copied to the clipboard when activated.

### Extensions

Omalaunch includes replaceable bundled extensions and also loads extensions from enabled Omarchy plugins:

```json
"omalaunch": {
  "extensions": ["omalaunch.json"]
}
```

Browse community integrations in the [Omalaunch Extension Directory](https://github.com/DanielLemky/omalaunch-extensions). See [EXTENSIONS.md](EXTENSIONS.md) for the complete extension contract and examples.

## Configuration

Omalaunch reads the stock Omarchy menu and the standard user menu override:

```text
~/.config/omarchy/extensions/omarchy-menu.jsonc
```

Favorites and usage data are stored in the user's state directory. Currency refreshes use `qalc` and respect a persistent cooldown to avoid unnecessary network requests.

## Updating

```bash
omarchy plugin update quantumfire.omalaunch
```

## Removal

```bash
omarchy plugin remove quantumfire.omalaunch
```

Removing Omalaunch does not remove its optional extension plugins or system dependencies.

## Security

Omarchy plugins are unsandboxed and run with the current user's permissions. Install plugins only from sources you trust.

Omalaunch executes commands supplied by the stock menu, user menu configuration, and enabled extension plugins. Extension commands are represented as argument arrays; Omalaunch substitutes the prompt and shell-quotes each argument. Dependency installation is never performed silently.

Currency conversion may cause `qalc` to retrieve updated exchange-rate data from its configured upstream source.

## Development

Run the tests with:

```bash
node tests/menu-model-test.js
bash tests/manifest-test.sh
bash tests/qalc-integration-test.sh
```

The integration test requires `qalc`.

## Acknowledgements

Omalaunch began as a customization of Omarchy's built-in menu and continues to consume Omarchy's standard menu definitions and shell APIs.

## License

[MIT](LICENSE) © Daniel Lemky

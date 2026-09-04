#!/usr/bin/env python3
"""Create an Omalaunch extension workspace and open the default agent in it."""

from __future__ import annotations

import getpass
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

DEFAULT_DIRECTORY = "~/.config/omarchy/plugins"
MAX_CONFIG_BYTES = 64 * 1024


def fail(message: str) -> None:
    print(f"Could not create extension: {message}", file=sys.stderr)
    raise SystemExit(1)


def strip_jsonc(text: str) -> str:
    """Remove JSONC comments without changing comment markers in strings."""
    output: list[str] = []
    index = 0
    in_string = False
    escaped = False
    while index < len(text):
        char = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            output.append(char)
            index += 1
        elif char == "/" and following == "/":
            index += 2
            while index < len(text) and text[index] not in "\r\n":
                index += 1
        elif char == "/" and following == "*":
            end = text.find("*/", index + 2)
            if end < 0:
                fail("the Omalaunch configuration contains an unterminated comment")
            index = end + 2
        else:
            output.append(char)
            index += 1
    return re.sub(r",\s*([}\]])", r"\1", "".join(output))


def development_root(home: Path) -> Path:
    config_path = home / ".config/omarchy/omalaunch/config.jsonc"
    configured = DEFAULT_DIRECTORY
    if config_path.exists():
        try:
            if config_path.stat().st_size > MAX_CONFIG_BYTES:
                fail("the Omalaunch configuration is larger than 64 KiB")
            config = json.loads(strip_jsonc(config_path.read_text(encoding="utf-8")))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            fail(f"cannot read {config_path}: {error}")
        value = config.get("extensionDevelopmentDirectory") if isinstance(config, dict) else None
        if value is not None:
            if not isinstance(value, str) or not value.strip() or "\0" in value:
                fail("extensionDevelopmentDirectory must be a nonempty path")
            configured = value.strip()
    expanded = os.path.expandvars(os.path.expanduser(configured))
    path = Path(expanded)
    if not path.is_absolute():
        fail("extensionDevelopmentDirectory must resolve to an absolute path")
    return path


def slug(value: str, fallback: str = "") -> str:
    result = re.sub(r"[^a-z0-9]+", "-", value.strip().lower()).strip("-")
    if not result and not fallback:
        fail("enter a name that contains a letter or number")
    return result or fallback


def scaffold(target: Path, name: str, plugin_id: str, prefix: str, username: str) -> None:
    manifest = {
        "schemaVersion": 1,
        "id": plugin_id,
        "name": name,
        "version": "0.1.0",
        "author": username,
        "description": f"{name} for Omalaunch",
        "kinds": ["extension"],
        "entryPoints": {},
        "omalaunch": {"extensions": ["omalaunch.json"]},
    }
    extension = {
        "schemaVersion": 1,
        "id": plugin_id,
        "capability": plugin_id,
        "mode": "workflow",
        "label": name,
        "prefixes": [prefix],
        "workflow": {
            "items": [{
                "id": "getting-started",
                "kind": "action",
                "label": "Getting Started",
                "command": ["/usr/bin/true"],
            }],
        },
    }
    files = {
        "manifest.json": json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        "omalaunch.json": json.dumps(extension, indent=2, ensure_ascii=False) + "\n",
        ".gitignore": "__pycache__/\n*.pyc\n",
        "README.md": f"# {name}\n\nAn Omalaunch extension plugin.\n",
        "AGENTS.md": f'''# Extension development instructions

- Read the active Omalaunch `EXTENSIONS.md` contract before you change this plugin.
- This plugin ID is `{plugin_id}`. Keep it consistent in `manifest.json` and `omalaunch.json`.
- Omarchy watches this plugin directory. Use atomic file replacement when possible and do not create temporary files inside it.
- Validate the plugin with `omarchy plugin validate .` after changes.
- Finish each implementation turn by enabling the plugin with `omarchy plugin enable {plugin_id}` so the user can review it.
- Do not store secrets, local state, caches, or machine-specific paths in the plugin.
- Add clear installation and usage instructions to `README.md` before publication.
- When the extension is ready, ask whether the user wants to publish it for other people. Keep it local if they do not.
- Do not create a remote repository, publish a release, or submit to the Omalaunch Extension Directory without explicit user approval.
- If the user wants to share the extension, offer the Omalaunch Extension Directory as one publishing option and ask before preparing a submission: https://github.com/DanielLemky/omalaunch-extensions.
''',
        "CLAUDE.md": "See [AGENTS.md](AGENTS.md) for project instructions.\n",
    }
    try:
        for filename, content in files.items():
            path = target / filename
            with path.open("x", encoding="utf-8") as output:
                output.write(content)
    except OSError as error:
        fail(f"cannot create the extension scaffold: {error}")


def is_starter_scaffold(target: Path, plugin_id: str) -> bool:
    try:
        names = {path.name for path in target.iterdir()}
        if not names.issubset({
            "manifest.json", "omalaunch.json", ".gitignore", "README.md", "AGENTS.md", "CLAUDE.md",
        }):
            return False
        manifest = json.loads((target / "manifest.json").read_text(encoding="utf-8"))
        extension = json.loads((target / "omalaunch.json").read_text(encoding="utf-8"))
        return manifest.get("id") == plugin_id and extension.get("id") == plugin_id
    except (OSError, json.JSONDecodeError, AttributeError):
        return False


def main() -> int:
    if len(sys.argv) != 2 or not sys.argv[1].strip():
        fail("an extension name is required")
    name = sys.argv[1].strip()
    home = Path.home()
    extension_slug = slug(name)
    username = getpass.getuser().strip() or "local"
    username_slug = slug(username, "local")
    plugin_id = f"{username_slug}.{extension_slug}"
    root = development_root(home)
    target = root / plugin_id
    root.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if not target.is_dir() or not is_starter_scaffold(target, plugin_id):
            fail(f"{target} already exists and is not an unchanged starter scaffold")
    else:
        stage = Path(tempfile.mkdtemp(prefix=".omalaunch-create-", dir=root))
        try:
            scaffold(stage, name, plugin_id, extension_slug, username)
            stage.rename(target)
        except OSError as error:
            shutil.rmtree(stage, ignore_errors=True)
            fail(f"cannot create {target}: {error}")
    contract = Path(__file__).resolve().parents[2] / "EXTENSIONS.md"
    prompt = (
        f'I am creating a new extension plugin for Omalaunch called "{name}". '
        f"A valid starter manifest and extension definition already exist in {target}. "
        f"Review the Omalaunch extension contract at {contract}, the scaffold files, and {target / 'AGENTS.md'} now. "
        "Do not change files yet. When you finish this review, tell me that you are ready. "
        "I will then provide direction for the extension. When you later make changes, remember that Omarchy watches "
        "this directory: use atomic file replacement when possible and do not create temporary files inside it. "
        f"Finish each implementation turn with `omarchy plugin validate .` and `omarchy plugin enable {plugin_id}` "
        "so I can review it."
    )
    launcher = Path(__file__).resolve().parents[2] / "libexec/omalaunch-launch-agent"
    try:
        os.execv(str(launcher), [str(launcher), "--dir", str(target), "--prompt", prompt])
    except OSError as error:
        fail(f"cannot open the default agent launcher: {error}")


if __name__ == "__main__":
    raise SystemExit(main())

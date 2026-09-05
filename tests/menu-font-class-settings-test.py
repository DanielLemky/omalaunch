#!/usr/bin/env python3
import json
import os
from pathlib import Path
import runpy
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COMMAND = ROOT / "libexec/omalaunch-config"
PARSE_JSONC = runpy.run_path(str(COMMAND))["parse_jsonc"]


def run(home: Path, value: str):
    env = os.environ.copy(); env["HOME"] = str(home)
    return subprocess.run([str(COMMAND), "set-font-class", value], env=env, text=True, capture_output=True)


def check(condition, message):
    if not condition: raise AssertionError(message)


def executable(path: Path, content: str):
    path.write_text(content); path.chmod(0o755)


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary); config = root / ".config/omarchy/omalaunch/config.jsonc"
    config.parent.mkdir(parents=True)
    original = '''{
  // Keep this provider choice.
  "version": 1,
  "menuItemFontClass": "body",
  "menuItemFontSize": 17, // explicit override
  "capabilities": {
    "files": { "provider": "example.files" },
  },
}
'''
    config.write_text(original)
    result = run(root, "displayLarge")
    check(result.returncode == 0, result.stderr)
    changed = config.read_text()
    check('"menuItemFontClass": "displayLarge"' in changed, "class is changed")
    check("menuItemFontSize" not in changed, "pixel override is removed")
    parsed = PARSE_JSONC(changed)
    check(parsed["menuItemFontClass"] == "displayLarge" and "menuItemFontSize" not in parsed,
          "updated configuration remains valid JSONC")
    check("// Keep this provider choice." in changed and '"files": { "provider": "example.files" },' in changed,
          "unrelated comments and formatting remain")
    check(stat.S_IMODE(config.stat().st_mode) == 0o600, "configuration is private")
    check(stat.S_IMODE(config.with_name("config.jsonc.lock").stat().st_mode) == 0o600, "lock is private")

for invalid_existing_value in ('{"bad":true}', '["bad"]'):
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary); config = root / ".config/omarchy/omalaunch/config.jsonc"
        config.parent.mkdir(parents=True)
        config.write_text('{"version":1,"menuItemFontClass":' + invalid_existing_value + ',"capabilities":{}}')
        result = run(root, "title")
        check(result.returncode == 0, result.stderr)
        parsed = PARSE_JSONC(config.read_text())
        check(parsed == {"version": 1, "menuItemFontClass": "title", "capabilities": {}},
              f"complete {invalid_existing_value[0]} font-class value is replaced")

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    result = run(root, "caption")
    check(result.returncode == 0, result.stderr)
    config = root / ".config/omarchy/omalaunch/config.jsonc"
    check(config.read_text() == '{\n  "menuItemFontClass": "caption"\n}\n', "missing configuration is created")

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary); config = root / ".config/omarchy/omalaunch/config.jsonc"
    config.parent.mkdir(parents=True); malformed = '{ "version": 1, /* broken'
    config.write_text(malformed)
    result = run(root, "title")
    check(result.returncode == 1 and config.read_text() == malformed, "malformed input is not changed")

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary); config = root / ".config/omarchy/omalaunch/config.jsonc"
    config.parent.mkdir(parents=True)
    duplicate = '{"version":1,"menuItemFontSize":12,"menuItemFontSize":13}'
    config.write_text(duplicate)
    result = run(root, "body")
    check(result.returncode == 1 and config.read_text() == duplicate,
          "duplicate font settings are rejected without changing configuration")

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary); config = root / ".config/omarchy/omalaunch/config.jsonc"
    config.parent.mkdir(parents=True)
    target = root / "target.jsonc"; target.write_text('{"version":1}')
    config.symlink_to(target)
    result = run(root, "body")
    check(result.returncode == 1 and target.read_text() == '{"version":1}',
          "symbolic-link configuration is rejected without reading or changing its target")

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary); empty_path = root / "bin"; empty_path.mkdir()
    env = {**os.environ, "HOME": str(root), "PATH": str(empty_path)}
    editor = subprocess.run([sys.executable, COMMAND, "open-config"], env=env, text=True, capture_output=True)
    agent = subprocess.run([sys.executable, COMMAND, "edit-config-agent"], env=env, text=True, capture_output=True)
    check(editor.returncode != 0 and agent.returncode != 0, "missing editor and agent tools report action failures")

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary); bin_dir = root / "bin"; bin_dir.mkdir(); record = root / "agent.json"
    (bin_dir / "python3").symlink_to(sys.executable)
    executable(bin_dir / "omarchy-default-agent", "#!/bin/sh\nprintf 'pi\\n'\n")
    executable(bin_dir / "omarchy-agent", "#!/usr/bin/env python3\nimport json,os,sys\nopen(os.environ['RECORD'],'w').write(json.dumps({'cwd':os.getcwd(),'args':sys.argv[1:]}))\n")
    env = {**os.environ, "HOME": str(root), "PATH": str(bin_dir), "RECORD": str(record)}
    result = subprocess.run([sys.executable, COMMAND, "edit-config-agent"], env=env, text=True, capture_output=True)
    launch = json.loads(record.read_text())
    config_dir = root / ".config/omarchy/omalaunch"
    prompt = launch["args"][1]
    check(result.returncode == 0 and launch["cwd"] == str(config_dir), "settings agent starts in the configuration directory")
    check(str(ROOT / "README.md") in prompt and str(ROOT / "EXTENSIONS.md") in prompt, "settings agent prompt uses absolute documentation paths")
    check(stat.S_IMODE(config_dir.stat().st_mode) == 0o700, "settings configuration directory is private")

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    result = run(root, "large")
    check(result.returncode == 2, "unsupported class is rejected")
    check(not (root / ".config/omarchy/omalaunch/config.jsonc").exists(), "invalid input does not create configuration")

print("menu font class settings tests passed")

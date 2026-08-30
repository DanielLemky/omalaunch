#!/usr/bin/env python3

import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LOADER = ROOT / "libexec" / "load-extensions.py"


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"ok - {message}")


def write_executable(path, content):
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def run_loader(plugin_root, omarchy_root, home, env, timeout="0.15"):
    result = subprocess.run(
        [str(LOADER), str(plugin_root), str(omarchy_root), "--home", str(home),
         "--provider-timeout", timeout],
        env=env,
        text=True,
        capture_output=True,
        check=True,
        timeout=10,
    )
    return json.loads(result.stdout)


with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    plugin_root = base / "omalaunch"
    bundled_dir = plugin_root / "extensions" / "fixture"
    bundled_dir.mkdir(parents=True)
    bundled_dir.joinpath("extension.json").write_text(json.dumps({
        "schemaVersion": 1,
        "id": "bundled",
        "label": "Bundled",
        "prefixes": ["bundled"],
        "command": ["printf", "%s", "{prompt}"],
    }), encoding="utf-8")

    home = base / "home"
    plugins_root = home / ".config" / "omarchy" / "plugins"
    plugin_dir = plugins_root / "dynamic"
    plugin_dir.mkdir(parents=True)
    provider = plugin_dir / "provider.py"
    write_executable(provider, """#!/usr/bin/env python3
import json, sys, time
mode = sys.argv[1]
if mode == 'valid':
    print(json.dumps([{'schemaVersion': 1, 'id': 'dynamic', 'label': 'Dynamic', 'prefixes': ['dyn'], 'command': ['printf', '%s', '{prompt}']}]))
elif mode == 'argument':
    print(json.dumps({'schemaVersion': 1, 'id': 'argument', 'label': sys.argv[2], 'prefixes': ['arg'], 'command': ['printf', '%s', '{prompt}']}))
elif mode == 'invalid':
    print('{not json')
elif mode == 'fail':
    print('provider setup failed', file=sys.stderr)
    raise SystemExit(7)
elif mode == 'timeout':
    time.sleep(2)
elif mode == 'oversized':
    print('x' * (300 * 1024))
""")
    static_file = plugin_dir / "static.json"
    static_file.write_text(json.dumps({
        "schemaVersion": 1,
        "id": "static",
        "label": "Static",
        "prefixes": ["static"],
        "command": ["printf", "%s", "{prompt}"],
    }), encoding="utf-8")
    marker = base / "shell-injection-marker"
    hostile_argument = f"; touch {marker}"
    manifest = {
        "id": "example.dynamic",
        "omalaunch": {
            "extensions": ["static.json"],
            "extensionProviders": [
                ["./provider.py", "valid"],
                ["./provider.py", "argument", hostile_argument],
                ["./provider.py", "invalid"],
                ["./provider.py", "fail"],
                ["./provider.py", "timeout"],
                ["./provider.py", "oversized"],
                ["missing-provider-command"],
                ["../outside-provider"],
            ],
        },
    }
    plugin_dir.joinpath("manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    bin_dir = base / "bin"
    bin_dir.mkdir()
    enabled_file = base / "enabled.json"
    enabled_file.write_text(json.dumps([{"id": "example.dynamic", "enabled": True}]), encoding="utf-8")
    write_executable(bin_dir / "omarchy", f"#!/bin/sh\ncat {enabled_file}\n")
    env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
    omarchy_root = base / "omarchy"
    omarchy_root.mkdir()

    catalog = run_loader(plugin_root, omarchy_root, home, env)
    ids = [item.get("id") for item in catalog["extensions"]]
    messages = "\n".join(catalog["diagnostics"])
    check(ids == ["bundled", "static", "dynamic", "argument"],
          "bundled, static, and successful dynamic definitions coexist")
    check(not marker.exists() and next(item for item in catalog["extensions"] if item.get("id") == "argument")["label"] == hostile_argument,
          "provider arguments are passed literally without shell interpretation")
    check("emitted invalid JSON" in messages, "malformed provider output produces a diagnostic")
    check("exited with code 7" in messages and "provider setup failed" in messages,
          "provider failures include exit status and bounded stderr")
    check("timed out" in messages, "provider timeouts produce a diagnostic")
    check("exceeded the 262144-byte stdout limit" in messages,
          "oversized provider output produces a diagnostic")
    check("was not found on PATH" in messages, "missing provider executables produce a diagnostic")
    check("escapes the plugin directory" in messages, "unsafe relative executable paths are rejected")
    check(all(item.get("_source") for item in catalog["extensions"]),
          "catalog definitions retain actionable source provenance")

    enabled_file.write_text(json.dumps([{"id": "example.dynamic", "enabled": False}]), encoding="utf-8")
    disabled_catalog = run_loader(plugin_root, omarchy_root, home, env)
    check([item.get("id") for item in disabled_catalog["extensions"]] == ["bundled"],
          "disabled plugin providers and static files disappear on reload")

    enabled_file.write_text(json.dumps([{"id": "example.dynamic", "enabled": True}]), encoding="utf-8")
    plugin_dir.rename(plugins_root / "removed")
    (plugins_root / "removed" / "manifest.json").unlink()
    removed_catalog = run_loader(plugin_root, omarchy_root, home, env)
    check([item.get("id") for item in removed_catalog["extensions"]] == ["bundled"],
          "removed plugin providers disappear on reload")

    write_executable(bin_dir / "omarchy", "#!/bin/sh\necho plugin registry unavailable >&2\nexit 9\n")
    missing_list = run_loader(plugin_root, omarchy_root, home, env)
    check([item.get("id") for item in missing_list["extensions"]] == ["bundled"]
          and "external extensions were skipped" in "\n".join(missing_list["diagnostics"]),
          "plugin-list failure preserves bundled extensions and explains skipped external plugins")

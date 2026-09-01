#!/usr/bin/env python3

import fcntl
import importlib.util
import json
import os
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "libexec" / "migrate-provider-config.py"
spec = importlib.util.spec_from_file_location("migration", HELPER)
migration = importlib.util.module_from_spec(spec); spec.loader.exec_module(migration)


def check(value, message):
    if not value: raise AssertionError(message)
    print("ok - " + message)


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def paths(base):
    home = base / "home"; config = base / "config"; state = base / "state"
    return home, config, state, state / "omarchy/omalaunch/extensions"


def run(home, config, state, catalog=None, preferences=None):
    return migration.run(home, catalog or [], preferences or {}, config_home=config,
                         state_home=state)


catalog = [
    {"id": "omalaunch.files", "capability": "files", "priority": 0, "_bundled": True, "_missingRequires": []},
    {"id": "external.files", "capability": "files", "priority": 10, "_bundled": False, "_missingRequires": []},
    {"id": "external.calc", "capability": "calculator", "priority": 0, "_bundled": False, "_missingRequires": []},
]

with tempfile.TemporaryDirectory() as temporary:
    home, config, state, targets = paths(Path(temporary))
    legacy = state / "omarchy/starred-launcher-items.json"
    write(legacy, {"version": 1, "ids": [
        "apps.Fastmail", "apps.org.gnome.Nautilus.desktop",
        "file.favorite.directory:/tmp/Projects/../Docs//",
        'file.favorite:["files","file","/tmp/notes.txt"]',
        'file.favorite:["other-files","file","/tmp/private"]',
        'extension.root:"files"', 'extension.root:"calculator"',
        'extension.root:"missing"', 'extension.menu:["quicklinks","docs"]',
        'extension.menu:["missing","item"]', "unknown.temporary",
    ]})
    diagnostics, complete = run(home, config, state, catalog)
    check(complete, "valid legacy favorites migrate successfully")
    apps = migration.read_data(targets / "omalaunch.apps.json")
    files = migration.read_data(targets / "omalaunch.files.json")
    extensions = migration.read_data(targets / "omalaunch.extensions.json")
    check(apps["favorites"] == ["Fastmail", "org.gnome.Nautilus.desktop"], "real legacy app IDs lose only the apps namespace")
    check(files["favorites"] == [{"type": "directory", "path": "/tmp/Docs"}, {"type": "file", "path": "/tmp/notes.txt"}], "legacy and current JSON-array file IDs normalize in source order")
    check(extensions["favorites"] == ["external.files", "external.calc"], "extension capabilities resolve to active provider IDs without shared configuration")
    check(any("non-bundled capability" in item for item in diagnostics)
          and any('extension.menu:["quicklinks","docs"]' in item for item in diagnostics)
          and any('extension.menu:["missing","item"]' in item for item in diagnostics)
          and any("unknown legacy" in item for item in diagnostics)
          and any("Could not resolve" in item for item in diagnostics),
          "unknown, missing, dynamic, and provider-owned values remain and produce bounded diagnostics")
    before = {path: path.read_bytes() for path in targets.iterdir()}
    second, complete = run(home, config, state, catalog)
    check(complete and before == {path: path.read_bytes() for path in targets.iterdir()}, "completed migrations are idempotent")
    check(legacy.exists(), "migration does not delete or rewrite the legacy favorites source")

with tempfile.TemporaryDirectory() as temporary:
    home, config, state, targets = paths(Path(temporary))
    write(targets / "omalaunch.apps.json", {"version": 1, "favorites": ["Fastmail", "Existing"]})
    write(targets / "omalaunch.files.json", {"version": 1, "favorites": [{"type": "file", "path": "/tmp/a"}]})
    write(state / "omarchy/starred-launcher-items.json", {"version": 1, "ids": ["apps.Fastmail", "apps.New", 'file.favorite:["files","file","/tmp/a"]', 'file.favorite:["files","directory","/tmp/b"]']})
    run(home, config, state, catalog)
    check(migration.read_data(targets / "omalaunch.apps.json")["favorites"] == ["Fastmail", "Existing", "New"], "existing valid target entries win and migrated entries append")
    file_target = migration.read_data(targets / "omalaunch.files.json")
    check(len(file_target["favorites"]) == 2, "duplicate merge preserves normalized identities")
    check((targets / "omalaunch.apps.json.pre-migration.bak").exists(), "an existing target receives a non-overwriting backup")

with tempfile.TemporaryDirectory() as temporary:
    home, config, state, targets = paths(Path(temporary))
    malformed = state / "omarchy/starred-launcher-items.json"
    malformed.parent.mkdir(parents=True); malformed.write_text('{"version":1,"ids":[NaN]}')
    diagnostics, complete = run(home, config, state)
    marker_path = state / "omarchy/omalaunch-provider-migrations.json"
    marker = migration.read_data(marker_path) if marker_path.exists() else {"completed": []}
    check(not complete and migration.MIGRATION_STARRED not in marker["completed"] and any("will retry" in item for item in diagnostics), "malformed strict JSON does not mark its migration complete")
    malformed.write_text('{"version":1,"ids":["apps.Retry"]}')
    diagnostics, complete = run(home, config, state)
    check(complete and migration.read_data(targets / "omalaunch.apps.json")["favorites"] == ["Retry"], "a failed migration retries on the next startup")

with tempfile.TemporaryDirectory() as temporary:
    home, config, state, targets = paths(Path(temporary))
    write(targets / "omalaunch.apps.json", {"version": 2, "favorites": []})
    write(state / "omarchy/starred-launcher-items.json", {"version": 1, "ids": ["apps.Skip"]})
    diagnostics, complete = run(home, config, state)
    check(not complete and migration.read_data(targets / "omalaunch.apps.json")["version"] == 2, "invalid existing provider state is skipped and never rewritten")

with tempfile.TemporaryDirectory() as temporary:
    home, config, state, targets = paths(Path(temporary))
    invalid = {"version": 1, "favorites": [], "includeGitIgnored": True}
    write(targets / "omalaunch.files.json", invalid)
    write(state / "omarchy/starred-launcher-items.json", {"version": 1, "ids": ['file.favorite:["files","file","/tmp/new"]']})
    diagnostics, complete = run(home, config, state)
    check(not complete and migration.read_data(targets / "omalaunch.files.json") == invalid,
          "migration rejects configuration fields in provider state")

with tempfile.TemporaryDirectory() as temporary:
    home, config, state, targets = paths(Path(temporary))
    target = targets / "omalaunch.apps.json"
    original = {"version": 1, "favorites": ["keep"]}
    write(target, original)
    try: migration.atomic_write(target, {"version": 1, "favorites": ["x" * migration.MAX_BYTES]})
    except ValueError: pass
    else: raise AssertionError("migration wrote provider state above the runtime byte limit")
    check(migration.read_data(target) == original and not (targets / "omalaunch.apps.json.pre-migration.bak").exists(),
          "oversized migration output leaves state unchanged without a misleading backup")

with tempfile.TemporaryDirectory() as temporary:
    home, config, state, targets = paths(Path(temporary))
    write(state / "omarchy/starred-launcher-items.json", {"version": 1, "ids": ["apps.One"]})
    original = migration.atomic_write
    def fail_apps(path, value, **kwargs):
        if path.name == "omalaunch.apps.json": raise OSError("injected write failure")
        return original(path, value, **kwargs)
    migration.atomic_write = fail_apps
    diagnostics, complete = run(home, config, state)
    migration.atomic_write = original
    marker = migration.read_data(state / "omarchy/omalaunch-provider-migrations.json") if (state / "omarchy/omalaunch-provider-migrations.json").exists() else {"completed": []}
    check(not complete and migration.MIGRATION_STARRED not in marker["completed"], "failed favorites migration remains incomplete")
    run(home, config, state)
    check(migration.read_data(targets / "omalaunch.apps.json")["favorites"] == ["One"], "failed migration retries safely")

with tempfile.TemporaryDirectory() as temporary:
    home, config, state, targets = paths(Path(temporary))
    lock_path = state / "omarchy/omalaunch-provider-migrations.lock"; lock_path.parent.mkdir(parents=True)
    descriptor = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600); fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    diagnostics, complete = run(home, config, state)
    os.close(descriptor)
    check(not complete and any("already running" in item for item in diagnostics), "migration lock is nonblocking and retains compatibility behavior")

with tempfile.TemporaryDirectory() as temporary:
    home, config, state, targets = paths(Path(temporary))
    write(state / "omarchy/starred-launcher-items.json", {"version": 1, "ids": ["apps.One"]})
    targets.mkdir(parents=True)
    lock_path = targets / "omalaunch.apps.lock"
    descriptor = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600); fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    diagnostics, complete = run(home, config, state)
    os.close(descriptor)
    check(not complete and any("state is busy" in item for item in diagnostics), "provider state locks do not block startup migration")

with tempfile.TemporaryDirectory() as temporary:
    home, config, state, targets = paths(Path(temporary))
    diagnostics, complete = run(home, config, state)
    check(complete and not targets.exists(), "missing legacy sources complete without creating provider state files")

print("ok - provider state startup migration suite")

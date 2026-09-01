#!/usr/bin/env python3
"""Migrate released shared favorites into provider-owned state."""

from __future__ import annotations

import argparse
import fcntl
import json
import math
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
from typing import Any

MAX_BYTES = 64 * 1024
MAX_DEPTH = 8
MAX_DIAGNOSTICS = 64
MAX_DIAGNOSTIC_CHARS = 512
MAX_SAFE_INTEGER = 9007199254740991
MIGRATION_STARRED = "provider-config.legacy-starred.v1"
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f]")


class Diagnostics:
    def __init__(self) -> None:
        self.values: list[str] = []

    def add(self, value: str) -> None:
        text = str(value).replace("\x00", "�")
        if len(text) > MAX_DIAGNOSTIC_CHARS:
            text = text[:MAX_DIAGNOSTIC_CHARS - 1] + "…"
        if len(self.values) < MAX_DIAGNOSTICS:
            self.values.append(text)
        elif self.values and not self.values[-1].startswith("Further migration diagnostics"):
            self.values[-1] = f"Further migration diagnostics were omitted after {MAX_DIAGNOSTICS} messages"


def reject_constant(value: str) -> Any:
    raise ValueError(f"non-finite JSON number {value!r} is not permitted")


def parse_float(value: str) -> float:
    result = float(value)
    if not math.isfinite(result):
        raise ValueError(f"non-finite JSON number {value!r} is not permitted")
    return result


def parse_int(value: str) -> int:
    result = int(value)
    if abs(result) > MAX_SAFE_INTEGER:
        raise ValueError("JSON integer exceeds the interoperable safe-integer range")
    return result


def check_depth(value: Any, maximum: int = MAX_DEPTH) -> None:
    stack = [(value, 0)]
    while stack:
        current, parent = stack.pop()
        if isinstance(current, (dict, list)):
            depth = parent + 1
            if depth > maximum:
                raise ValueError(f"JSON nesting exceeds the {maximum}-level limit")
            children = current.values() if isinstance(current, dict) else current
            stack.extend((child, depth) for child in children if isinstance(child, (dict, list)))


def strip_jsonc(data: bytes) -> str:
    text = data.decode("utf-8")
    output: list[str] = []
    index = 0
    string = escaped = False
    while index < len(text):
        char = text[index]
        if string:
            output.append(char)
            if escaped: escaped = False
            elif char == "\\": escaped = True
            elif char == '"': string = False
            index += 1
        elif char == '"':
            string = True; output.append(char); index += 1
        elif text.startswith("//", index):
            end = text.find("\n", index + 2); index = len(text) if end < 0 else end
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            if end < 0: raise ValueError("unterminated block comment")
            output.extend("\n" for char in text[index:end + 2] if char == "\n"); index = end + 2
        else:
            output.append(char); index += 1
    text = "".join(output); output = []; index = 0; string = escaped = False
    while index < len(text):
        char = text[index]
        if string:
            output.append(char)
            if escaped: escaped = False
            elif char == "\\": escaped = True
            elif char == '"': string = False
        elif char == '"': string = True; output.append(char)
        elif char == ",":
            look = index + 1
            while look < len(text) and text[look].isspace(): look += 1
            if look >= len(text) or text[look] not in "]}": output.append(char)
        else: output.append(char)
        index += 1
    return "".join(output)


def read_data(path: Path, *, jsonc: bool = False) -> Any:
    size = path.stat().st_size
    if size > MAX_BYTES: raise ValueError(f"file is {size} bytes; limit is {MAX_BYTES} bytes")
    raw: str | bytes = strip_jsonc(path.read_bytes()) if jsonc else path.read_bytes()
    try:
        value = json.loads(raw, parse_constant=reject_constant, parse_float=parse_float, parse_int=parse_int)
    except RecursionError as error:
        raise ValueError("JSON parsing exceeded Python's recursion limit") from error
    check_depth(value)
    return value


def valid_identity(value: Any, maximum: int = 255) -> bool:
    return isinstance(value, str) and 1 <= len(value) <= maximum and "/" not in value and not CONTROL_RE.search(value)


def normalize_path(value: Any, home: Path) -> str | None:
    if not isinstance(value, str) or not 1 <= len(value) <= 4096: return None
    if value.startswith("~/"): value = str(home) + value[1:]
    if not value.startswith("/"): return None
    parts: list[str] = []
    for part in value.split("/"):
        if not part or part == ".": continue
        if part == "..":
            if not parts: return None
            parts.pop()
        else: parts.append(part)
    return "/" + "/".join(parts)


def default_config(provider: str) -> dict[str, Any]:
    return {"version": 1, "favorites": []}


def validate_config(provider: str, value: Any, home: Path) -> None:
    if not isinstance(value, dict) or value.get("version") != 1: raise ValueError("expected an object with version 1")
    if not set(value) <= {"version", "favorites"}: raise ValueError("state has unknown fields")
    if provider == "omalaunch.files":
        entries = value.get("favorites", [])
        identities = []
        if not isinstance(entries, list) or len(entries) > 256: raise ValueError("favorites are invalid")
        for item in entries:
            if not isinstance(item, dict) or set(item) != {"type", "path"} or item.get("type") not in ("file", "directory"):
                raise ValueError("file favorite is invalid")
            path = normalize_path(item.get("path"), home)
            if path is None or path != item["path"]: raise ValueError("file favorite path is not normalized")
            identities.append((item["type"], path))
        if len(set(identities)) != len(identities): raise ValueError("file favorites are duplicated")
    else:
        entries = value.get("favorites", [])
        if not isinstance(entries, list) or len(entries) > 256 or not all(valid_identity(item) for item in entries) or len(set(entries)) != len(entries):
            raise ValueError("favorites are invalid or duplicated")


def load_target(path: Path, provider: str, home: Path) -> dict[str, Any]:
    if not path.exists(): return default_config(provider)
    value = read_data(path); validate_config(provider, value, home); return value


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try: os.fsync(descriptor)
    finally: os.close(descriptor)


def backup(path: Path) -> None:
    if not path.exists(): return
    suffix = 0
    while True:
        candidate = path.with_name(path.name + ".pre-migration.bak" + (f".{suffix}" if suffix else ""))
        try:
            descriptor = os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            break
        except FileExistsError: suffix += 1
    try:
        with os.fdopen(descriptor, "wb") as output, path.open("rb") as source:
            shutil.copyfileobj(source, output); output.flush(); os.fsync(output.fileno())
    except Exception:
        candidate.unlink(missing_ok=True); raise
    fsync_directory(path.parent)


def atomic_write(path: Path, value: Any, *, make_backup: bool = True) -> None:
    data = (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode()
    if len(data) > MAX_BYTES:
        raise ValueError(f"result is {len(data)} bytes; limit is {MAX_BYTES} bytes")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if make_backup: backup(path)
    descriptor, temporary = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            output.write(data); output.flush(); os.fsync(output.fileno())
        os.replace(temporary, path); fsync_directory(path.parent)
        if read_data(path) != value:
            raise OSError(f"atomic write verification failed for {path}")
    except Exception:
        try: os.unlink(temporary)
        except FileNotFoundError: pass
        raise


def active_providers(catalog: list[Any], preferences: dict[str, str]) -> dict[str, str]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    seen: set[str] = set()
    for raw in catalog:
        if not isinstance(raw, dict) or not valid_identity(raw.get("id")) or raw["id"] in seen: continue
        seen.add(raw["id"])
        capability = raw.get("capability", raw["id"])
        if not valid_identity(capability) or raw.get("_missingRequires"): continue
        grouped.setdefault(capability, []).append(raw)
    result = {}
    for capability, values in grouped.items():
        preferred = preferences.get(capability)
        selected = next((item for item in values if item["id"] == preferred), None)
        if selected is None:
            selected = max(values, key=lambda item: (item.get("priority", 0) if isinstance(item.get("priority", 0), (int, float)) else 0,
                                                     not bool(item.get("_bundled", False))))
        result[capability] = selected["id"]
    return result


def parse_legacy_favorite(value: Any, home: Path, active: dict[str, str], diagnostics: Diagnostics) -> tuple[str, Any] | None:
    if not isinstance(value, str) or not value: return None
    if value.startswith("apps."):
        item = value[5:]
        return ("omalaunch.apps", item) if valid_identity(item) else None
    for prefix, kind in (("file.favorite.directory:", "directory"), ("file.favorite.file:", "file")):
        if value.startswith(prefix):
            path = normalize_path(value[len(prefix):], home)
            return ("omalaunch.files", {"type": kind, "path": path}) if path else None
    if value.startswith("file.favorite:"):
        try: parts = json.loads(value[len("file.favorite:"):], parse_constant=reject_constant)
        except (ValueError, TypeError, RecursionError): return None
        if not isinstance(parts, list) or len(parts) != 3 or parts[1] not in ("file", "directory"): return None
        path = normalize_path(parts[2], home)
        if parts[0] != "files":
            diagnostics.add(f"Preserved favorite for non-bundled capability {parts[0]!r}"); return ("preserved", None)
        return ("omalaunch.files", {"type": parts[1], "path": path}) if path else None
    if value.startswith("extension.root:"):
        try: capability = json.loads(value[len("extension.root:"):], parse_constant=reject_constant)
        except (ValueError, TypeError, RecursionError): return None
        provider = active.get(capability) if isinstance(capability, str) else None
        if not provider:
            diagnostics.add(f"Could not resolve extension favorite capability {capability!r}"); return ("preserved", None)
        return "omalaunch.extensions", provider
    return None


def migrate_starred(source: Path, targets: Path, home: Path, active: dict[str, str], diagnostics: Diagnostics) -> bool:
    if not source.exists(): return True
    raw = read_data(source)
    if not isinstance(raw, dict) or raw.get("version") != 1 or not isinstance(raw.get("ids"), list):
        raise ValueError(f"legacy favorites {source} is not a version-1 ids object")
    targets.mkdir(parents=True, exist_ok=True, mode=0o700)
    providers=("omalaunch.apps", "omalaunch.files", "omalaunch.extensions")
    locks=[]
    try:
        for provider in providers:
            descriptor=os.open(targets / f"{provider}.lock", os.O_RDWR | os.O_CREAT, 0o600)
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                os.close(descriptor)
                raise ValueError(f"{provider} state is busy; migration will retry")
            locks.append(descriptor)
        configs = {provider: load_target(targets / f"{provider}.json", provider, home) for provider in providers}
        changed: set[str] = set()
        for value in raw["ids"][:1025]:
            mapped = parse_legacy_favorite(value, home, active, diagnostics)
            if mapped is None:
                diagnostics.add(f"Preserved unknown legacy favorite {value!r}"); continue
            provider, entry = mapped
            if provider == "preserved": continue
            entries = configs[provider]["favorites"]
            identity = (entry["type"], entry["path"]) if isinstance(entry, dict) else entry
            identities = {(item["type"], item["path"]) if isinstance(item, dict) else item for item in entries}
            if identity in identities: continue
            if len(entries) >= 256: diagnostics.add(f"{provider} favorites are full; skipped {entry!r}"); continue
            entries.append(entry); changed.add(provider)
        if len(raw["ids"]) > 1024: diagnostics.add("Legacy favorites has more than 1024 ids; trailing ids were skipped")
        for provider in sorted(changed): atomic_write(targets / f"{provider}.json", configs[provider])
        return True
    finally:
        for descriptor in reversed(locks): os.close(descriptor)


def run(home: Path, catalog: list[Any], preferences: dict[str, str], *, config_home: Path | None = None,
        state_home: Path | None = None) -> tuple[list[str], bool]:
    diagnostics = Diagnostics()
    config_home = config_home or home / ".config"
    state_home = state_home or Path(os.environ.get("XDG_STATE_HOME", home / ".local/state"))
    targets = state_home / "omarchy" / "omalaunch" / "extensions"
    marker = state_home / "omarchy" / "omalaunch-provider-migrations.json"
    lock_path = state_home / "omarchy" / "omalaunch-provider-migrations.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            diagnostics.add("Provider configuration migration is already running; this startup kept compatibility state")
            return diagnostics.values, False
        completed: list[str] = []
        if marker.exists():
            try:
                value = read_data(marker)
                if isinstance(value, dict) and value.get("version") == 1 and isinstance(value.get("completed"), list):
                    completed = [item for item in value["completed"] if item == MIGRATION_STARRED]
            except (OSError, UnicodeDecodeError, ValueError) as error:
                diagnostics.add(f"Could not read migration marker {marker}: {error}; migrations will retry")
        steps = [
            (MIGRATION_STARRED, lambda: migrate_starred(state_home / "omarchy/starred-launcher-items.json", targets, home, active_providers(catalog, preferences), diagnostics)),
        ]
        all_complete = True
        for migration_id, operation in steps:
            if migration_id in completed: continue
            try:
                operation()
                completed.append(migration_id)
                atomic_write(marker, {"version": 1, "completed": completed}, make_backup=False)
            except (OSError, UnicodeDecodeError, ValueError) as error:
                all_complete = False; diagnostics.add(f"Migration {migration_id} failed and will retry: {error}")
        return diagnostics.values, all_complete
    finally:
        os.close(lock)


def main() -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("--home", type=Path, default=Path.home()); parser.add_argument("--catalog", type=Path)
    args = parser.parse_args(); catalog = []
    if args.catalog: catalog = read_data(args.catalog)
    diagnostics, complete = run(args.home.resolve(), catalog if isinstance(catalog, list) else [], {})
    print(json.dumps({"diagnostics": diagnostics, "complete": complete}, ensure_ascii=False)); return 0


if __name__ == "__main__": raise SystemExit(main())

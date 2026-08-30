#!/usr/bin/env python3
"""Build Omalaunch's extension catalog from bundled and enabled plugins."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import time
from typing import Any

PROVIDER_TIMEOUT_SECONDS = 5.0
PROVIDER_OUTPUT_BYTES = 256 * 1024
COMMAND_OUTPUT_BYTES = 1024 * 1024
CATALOG_OUTPUT_BYTES = 768 * 1024
DIAGNOSTIC_STDERR_BYTES = 512


def run_bounded(command: list[str], *, cwd: Path | None, timeout: float, limit: int) -> tuple[str, bytes, bytes]:
    """Run argv directly and return (status, stdout, stderr), with hard bounds."""
    try:
        process = subprocess.Popen(
            command,
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
    except (FileNotFoundError, PermissionError, OSError) as error:
        return f"start:{error}", b"", b""

    selector = selectors.DefaultSelector()
    assert process.stdout is not None and process.stderr is not None
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    output = {"stdout": bytearray(), "stderr": bytearray()}
    deadline = time.monotonic() + timeout
    status = "ok"

    while selector.get_map():
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            status = "timeout"
            break
        events = selector.select(remaining)
        if not events:
            status = "timeout"
            break
        for key, _ in events:
            chunk = os.read(key.fileobj.fileno(), 65536)
            if not chunk:
                selector.unregister(key.fileobj)
                continue
            target = output[key.data]
            target.extend(chunk)
            if len(target) > limit:
                status = f"oversized:{key.data}"
                break
        if status != "ok":
            break

    if status == "ok" and process.poll() is None:
        try:
            process.wait(timeout=max(0, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            status = "timeout"
    if status != "ok":
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    return_code = process.wait()
    if status == "ok" and return_code != 0:
        status = f"exit:{return_code}"
    return status, bytes(output["stdout"][:limit]), bytes(output["stderr"][:limit])


def safe_plugin_file(plugin_dir: Path, relative: Any) -> Path | None:
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        return None
    if any(part in ("", ".", "..") for part in Path(relative).parts):
        return None
    try:
        candidate = (plugin_dir / relative).resolve(strict=True)
        candidate.relative_to(plugin_dir.resolve(strict=True))
    except (OSError, ValueError):
        return None
    return candidate if candidate.is_file() else None


def command_for_provider(plugin_dir: Path, raw: Any) -> tuple[list[str] | None, str | None]:
    if not isinstance(raw, list) or not raw or not all(isinstance(item, str) and item for item in raw):
        return None, "must be a non-empty array of non-empty strings"
    command = list(raw)
    executable = command[0]
    if "/" in executable:
        resolved = safe_plugin_file(plugin_dir, executable)
        if resolved is None:
            return None, f"executable path is missing or escapes the plugin directory: {executable}"
        if not os.access(resolved, os.X_OK):
            return None, f"executable is not executable: {executable}"
        command[0] = str(resolved)
    else:
        resolved_executable = shutil.which(executable)
        if resolved_executable is None:
            return None, f"executable was not found on PATH: {executable}"
        command[0] = resolved_executable
    return command, None


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def annotate(raw: Any, *, bundled: bool, source_dir: Path, source: str) -> Any:
    # Preserve provenance even for malformed definitions so MenuModel can
    # identify the provider/file it rejected.
    value = dict(raw) if isinstance(raw, dict) else {"_invalidDefinition": raw}
    value["_bundled"] = bundled
    value["_sourceDir"] = str(source_dir)
    value["_source"] = source
    requirements = value.get("requires", [])
    if isinstance(requirements, list):
        value["_missingRequires"] = [
            item for item in requirements
            if isinstance(item, str) and item and shutil.which(item) is None
        ]
    else:
        value["_missingRequires"] = []
    return value


def append_definitions(catalog: list[Any], raw: Any, *, bundled: bool, source_dir: Path, source: str) -> None:
    values = raw if isinstance(raw, list) else [raw]
    catalog.extend(annotate(value, bundled=bundled, source_dir=source_dir, source=source) for value in values)


def enabled_plugin_ids(timeout: float) -> tuple[set[str], list[str]]:
    status, stdout, stderr = run_bounded(
        ["omarchy", "plugin", "list", "--json"], cwd=None, timeout=timeout, limit=COMMAND_OUTPUT_BYTES
    )
    if status != "ok":
        detail = stderr.decode("utf-8", "replace").strip()[:DIAGNOSTIC_STDERR_BYTES]
        suffix = f": {detail}" if detail else ""
        return set(), [f"Could not list enabled Omarchy plugins ({status}){suffix}; external extensions were skipped"]
    try:
        plugins = json.loads(stdout)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return set(), ["Could not list enabled Omarchy plugins: output was not valid JSON; external extensions were skipped"]
    if not isinstance(plugins, list):
        return set(), ["Could not list enabled Omarchy plugins: expected a JSON array; external extensions were skipped"]
    return {
        item.get("id") for item in plugins
        if isinstance(item, dict) and item.get("enabled") is True and isinstance(item.get("id"), str)
    }, []


def provider_failure(source: str, status: str, stderr: bytes) -> str:
    if status == "timeout":
        reason = "timed out"
    elif status.startswith("oversized:"):
        reason = f"exceeded the {PROVIDER_OUTPUT_BYTES}-byte {status.split(':', 1)[1]} limit"
    elif status.startswith("exit:"):
        reason = f"exited with code {status.split(':', 1)[1]}"
    else:
        reason = f"could not start ({status.split(':', 1)[-1]})"
    detail = stderr.decode("utf-8", "replace").strip()[:DIAGNOSTIC_STDERR_BYTES]
    return f"Extension provider {source} {reason}" + (f": {detail}" if detail else "")


def load_catalog(plugin_path: Path, omarchy_path: Path, home: Path, timeout: float) -> dict[str, Any]:
    catalog: list[Any] = []
    diagnostics: list[str] = []

    for extension_file in sorted(plugin_path.glob("extensions/*/extension.json")):
        source = f"bundled file {extension_file}"
        try:
            append_definitions(catalog, read_json(extension_file), bundled=True,
                               source_dir=extension_file.parent, source=source)
        except (OSError, json.JSONDecodeError, UnicodeDecodeError) as error:
            diagnostics.append(f"Could not load {source}: {error}")

    enabled, enabled_diagnostics = enabled_plugin_ids(timeout)
    diagnostics.extend(enabled_diagnostics)
    manifest_roots = (omarchy_path / "shell" / "plugins", home / ".config" / "omarchy" / "plugins")
    for root in manifest_roots:
        for manifest_path in sorted(root.glob("*/manifest.json")):
            try:
                manifest = read_json(manifest_path)
            except (OSError, json.JSONDecodeError, UnicodeDecodeError):
                continue
            if not isinstance(manifest, dict) or manifest.get("id") not in enabled:
                continue
            plugin_id = manifest["id"]
            plugin_dir = manifest_path.parent.resolve()
            omalaunch = manifest.get("omalaunch", {})
            if not isinstance(omalaunch, dict):
                diagnostics.append(f"Plugin {plugin_id} has an invalid omalaunch manifest object")
                continue

            static_entries = []
            for field in ("extensions", "queryProviders"):
                entries = omalaunch.get(field, [])
                if not isinstance(entries, list):
                    diagnostics.append(f"Plugin {plugin_id} omalaunch.{field} must be an array")
                    continue
                static_entries.extend(entries)
            for entry in static_entries:
                extension_file = safe_plugin_file(plugin_dir, entry)
                if extension_file is None:
                    diagnostics.append(f"Plugin {plugin_id} extension path is missing or unsafe: {entry!r}")
                    continue
                source = f"plugin {plugin_id} file {entry}"
                try:
                    append_definitions(catalog, read_json(extension_file), bundled=False,
                                       source_dir=extension_file.parent, source=source)
                except (OSError, json.JSONDecodeError, UnicodeDecodeError) as error:
                    diagnostics.append(f"Could not load {source}: {error}")

            providers = omalaunch.get("extensionProviders", [])
            if not isinstance(providers, list):
                diagnostics.append(f"Plugin {plugin_id} omalaunch.extensionProviders must be an array")
                continue
            for index, raw_command in enumerate(providers):
                source = f"plugin {plugin_id} provider #{index + 1}"
                command, command_error = command_for_provider(plugin_dir, raw_command)
                if command_error:
                    diagnostics.append(f"Extension provider {source} {command_error}")
                    continue
                assert command is not None
                status, stdout, stderr = run_bounded(command, cwd=plugin_dir, timeout=timeout, limit=PROVIDER_OUTPUT_BYTES)
                if status != "ok":
                    diagnostics.append(provider_failure(source, status, stderr))
                    continue
                try:
                    definitions = json.loads(stdout)
                except (json.JSONDecodeError, UnicodeDecodeError) as error:
                    diagnostics.append(f"Extension provider {source} emitted invalid JSON: {error}")
                    continue
                if not isinstance(definitions, (dict, list)):
                    diagnostics.append(f"Extension provider {source} must emit one extension object or an array of extension objects")
                    continue
                append_definitions(catalog, definitions, bundled=False, source_dir=plugin_dir, source=source)

    result = {"extensions": catalog, "diagnostics": diagnostics}
    encoded = json.dumps(result, ensure_ascii=False, separators=(",", ":")).encode()
    if len(encoded) > CATALOG_OUTPUT_BYTES:
        diagnostics.append(f"Extension catalog exceeded the {CATALOG_OUTPUT_BYTES}-byte total limit; trailing definitions were ignored")
        # Keep valid definitions where possible, then keep earlier bundled/
        # static/provider definitions instead of invalidating every extension.
        while len(diagnostics) > 1 and len(json.dumps(result, ensure_ascii=False, separators=(",", ":")).encode()) > CATALOG_OUTPUT_BYTES:
            diagnostics.pop(0)
        while catalog and len(json.dumps(result, ensure_ascii=False, separators=(",", ":")).encode()) > CATALOG_OUTPUT_BYTES:
            catalog.pop()
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("plugin_path", type=Path)
    parser.add_argument("omarchy_path", type=Path)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--provider-timeout", type=float, default=PROVIDER_TIMEOUT_SECONDS,
                        help=argparse.SUPPRESS)
    args = parser.parse_args()
    result = load_catalog(args.plugin_path.resolve(), args.omarchy_path.resolve(), args.home.resolve(),
                          max(0.01, args.provider_timeout))
    json.dump(result, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

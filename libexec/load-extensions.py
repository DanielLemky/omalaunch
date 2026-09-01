#!/usr/bin/env python3
"""Build Omalaunch's extension catalog from bundled and enabled plugins."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import math
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
MAX_PROVIDERS_PER_PLUGIN = 16
MAX_TOTAL_PROVIDERS = 64
MAX_TOTAL_DEFINITIONS = 1024
MAX_STATIC_INPUT_BYTES = 1024 * 1024
MAX_MANIFEST_INPUT_BYTES = 256 * 1024
MAX_TOTAL_MANIFEST_BYTES = 4 * 1024 * 1024
MAX_DISCOVERED_MANIFESTS = 512
MAX_MANIFEST_FILESYSTEM_ENTRIES = 4096
MAX_STATIC_ENTRIES_PER_PLUGIN = 128
MAX_DEFINITIONS_PER_SOURCE = 256
MAX_JSON_NESTING_DEPTH = 32
MAX_DIAGNOSTICS = 256
MAX_DIAGNOSTIC_CHARS = 1024
MAX_SAFE_JSON_INTEGER = 9007199254740991
AGGREGATE_PROVIDER_SECONDS = 15.0
MAX_CONFIG_INPUT_BYTES = 64 * 1024
MAX_CONFIG_CAPABILITIES = 128


@dataclass(frozen=True)
class Limits:
    provider_timeout: float = PROVIDER_TIMEOUT_SECONDS
    provider_output_bytes: int = PROVIDER_OUTPUT_BYTES
    catalog_output_bytes: int = CATALOG_OUTPUT_BYTES
    providers_per_plugin: int = MAX_PROVIDERS_PER_PLUGIN
    total_providers: int = MAX_TOTAL_PROVIDERS
    definitions: int = MAX_TOTAL_DEFINITIONS
    static_input_bytes: int = MAX_STATIC_INPUT_BYTES
    aggregate_provider_seconds: float = AGGREGATE_PROVIDER_SECONDS
    manifest_input_bytes: int = MAX_MANIFEST_INPUT_BYTES
    total_manifest_bytes: int = MAX_TOTAL_MANIFEST_BYTES
    discovered_manifests: int = MAX_DISCOVERED_MANIFESTS
    manifest_filesystem_entries: int = MAX_MANIFEST_FILESYSTEM_ENTRIES
    static_entries_per_plugin: int = MAX_STATIC_ENTRIES_PER_PLUGIN
    definitions_per_source: int = MAX_DEFINITIONS_PER_SOURCE
    json_nesting_depth: int = MAX_JSON_NESTING_DEPTH
    diagnostics: int = MAX_DIAGNOSTICS
    diagnostic_chars: int = MAX_DIAGNOSTIC_CHARS


class CatalogBuilder:
    """Incrementally bounds definitions; serializes the full envelope once."""

    def __init__(self, limits: Limits) -> None:
        self.limits = limits
        self.catalog: list[Any] = []
        self.diagnostics: list[str] = []
        self.definition_bytes = 0
        self.definition_limit_reported = False
        self.byte_limit_reported = False
        self.diagnostic_limit_reported = False
        self.provider_preferences: dict[str, str] = {}
        # This normalized object is the stable loader-to-host envelope for
        # current and future Omalaunch core settings. Only validated settings
        # are copied from the user-owned config file.
        self.omalaunch_config: dict[str, Any] = {}
        self.capability_config: dict[str, dict[str, Any]] = {}
        # Capabilities the user has switched off. Bundled extensions are always
        # present on disk, so this is the only way to remove one.
        self.disabled_capabilities: list[str] = []
        # Reserve room for useful diagnostics. The final envelope still uses
        # the exact public catalog limit and trims diagnostics linearly.
        reserve = min(64 * 1024, max(64, limits.catalog_output_bytes // 4))
        self.definition_byte_limit = max(2, limits.catalog_output_bytes - reserve)

    @staticmethod
    def encoded(value: Any) -> bytes:
        try:
            return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode()
        except RecursionError as error:
            raise ValueError("JSON serialization exceeded Python's recursion limit") from error

    def diagnostic(self, message: str) -> None:
        clean = str(message).replace("\x00", "�")
        if len(clean) > self.limits.diagnostic_chars:
            clean = clean[:max(0, self.limits.diagnostic_chars - 1)] + "…"
        if len(self.diagnostics) < self.limits.diagnostics:
            self.diagnostics.append(clean)
        elif not self.diagnostic_limit_reported:
            # Replace the final diagnostic so the bounded omission is visible
            # without allowing adversarial manifests to grow this list.
            notice = f"Further diagnostics were omitted after the {self.limits.diagnostics}-message limit"
            if self.diagnostics:
                self.diagnostics[-1] = notice[:self.limits.diagnostic_chars]
            self.diagnostic_limit_reported = True

    def append(self, raw: Any, *, bundled: bool, source_dir: Path, source: str) -> None:
        values = raw if isinstance(raw, list) else [raw]
        if len(values) > self.limits.definitions_per_source:
            self.diagnostic(
                f"{source} contains {len(values)} extension definitions; only the first "
                f"{self.limits.definitions_per_source} were considered"
            )
        for value in values[:self.limits.definitions_per_source]:
            if len(self.catalog) >= self.limits.definitions:
                if not self.definition_limit_reported:
                    self.diagnostic(
                        f"Extension definition limit ({self.limits.definitions}) reached; trailing definitions were ignored"
                    )
                    self.definition_limit_reported = True
                return
            try:
                validate_json_depth(value, self.limits.json_nesting_depth)
                annotated = annotate(value, bundled=bundled, source_dir=source_dir, source=source)
                validate_json_depth(annotated, self.limits.json_nesting_depth)
                encoded_size = len(self.encoded(annotated)) + (1 if self.catalog else 0)
            except (RecursionError, ValueError) as error:
                self.diagnostic(f"Ignored extension definition from {source}: {error}")
                continue
            if self.definition_bytes + encoded_size > self.definition_byte_limit:
                if not self.byte_limit_reported:
                    self.diagnostic(
                        f"Extension catalog definition data exceeded its incremental byte budget "
                        f"under the {self.limits.catalog_output_bytes}-byte total limit; trailing definitions were ignored"
                    )
                    self.byte_limit_reported = True
                return
            self.catalog.append(annotated)
            self.definition_bytes += encoded_size

    def finish(self, *, complete: bool) -> dict[str, Any]:
        """Return a bounded envelope even if defensive final encoding fails."""
        try:
            validate_json_depth(self.catalog, self.limits.json_nesting_depth + 1)
            result = {
                "extensions": self.catalog,
                "diagnostics": [],
                "complete": complete,
                "providerPreferences": self.provider_preferences,
                "disabledCapabilities": self.disabled_capabilities,
                "omalaunchConfig": self.omalaunch_config,
                "capabilityConfig": self.capability_config,
            }
            base_size = len(self.encoded(result))
            used = base_size
            omitted = False
            for message in self.diagnostics:
                size = len(self.encoded(message)) + (1 if result["diagnostics"] else 0)
                if used + size <= self.limits.catalog_output_bytes:
                    result["diagnostics"].append(message)
                    used += size
                else:
                    omitted = True
            if omitted:
                notice = f"Diagnostics were truncated to keep the catalog within {self.limits.catalog_output_bytes} bytes"
                notice_size = len(self.encoded(notice)) + (1 if result["diagnostics"] else 0)
                while result["diagnostics"] and used + notice_size > self.limits.catalog_output_bytes:
                    removed = result["diagnostics"].pop()
                    used -= len(self.encoded(removed)) + (1 if result["diagnostics"] else 0)
                    notice_size = len(self.encoded(notice)) + (1 if result["diagnostics"] else 0)
                if used + notice_size <= self.limits.catalog_output_bytes:
                    result["diagnostics"].append(notice)
            return result
        except (RecursionError, ValueError) as error:
            message = f"Could not serialize extension catalog safely: {error}"
            return {"extensions": [], "diagnostics": [message[:self.limits.diagnostic_chars]], "complete": False}


def run_bounded(command: list[str], *, cwd: Path | None, timeout: float, limit: int) -> tuple[str, bytes, bytes]:
    """Run argv directly and return (status, stdout, stderr), with hard bounds."""
    try:
        process = subprocess.Popen(
            command, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=True,
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
            output[key.data].extend(chunk)
            if len(output[key.data]) > limit:
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


def reject_json_constant(value: str) -> Any:
    raise ValueError(f"non-finite JSON number {value!r} is not permitted")


def strict_json_float(value: str) -> float:
    result = float(value)
    if not math.isfinite(result):
        raise ValueError(f"non-finite or out-of-range JSON number {value!r} is not permitted")
    return result


def strict_json_int(value: str) -> int:
    result = int(value)
    if abs(result) > MAX_SAFE_JSON_INTEGER:
        raise ValueError(f"JSON integer {value!r} exceeds the interoperable safe-integer range")
    return result


def validate_json_depth(value: Any, maximum: int) -> None:
    """Reject containers nested deeper than maximum without recursive walking."""
    stack: list[tuple[Any, int]] = [(value, 0)]
    while stack:
        current, parent_depth = stack.pop()
        if isinstance(current, dict):
            depth = parent_depth + 1
            if depth > maximum:
                raise ValueError(f"JSON nesting exceeds the {maximum}-level limit")
            for key, child in current.items():
                # JSON object keys are scalar strings, but validate defensively.
                if not isinstance(key, str):
                    raise ValueError("JSON object contains a non-string key")
                if isinstance(child, (dict, list)):
                    stack.append((child, depth))
        elif isinstance(current, list):
            depth = parent_depth + 1
            if depth > maximum:
                raise ValueError(f"JSON nesting exceeds the {maximum}-level limit")
            for child in current:
                if isinstance(child, (dict, list)):
                    stack.append((child, depth))


def parse_json(value: str | bytes, *, maximum_depth: int = MAX_JSON_NESTING_DEPTH) -> Any:
    try:
        parsed = json.loads(
            value,
            parse_constant=reject_json_constant,
            parse_float=strict_json_float,
            parse_int=strict_json_int,
        )
    except RecursionError as error:
        raise ValueError("JSON parsing exceeded Python's recursion limit") from error
    validate_json_depth(parsed, maximum_depth)
    return parsed


def strip_jsonc(value: bytes) -> str:
    """Remove JSONC comments and trailing commas without changing strings."""
    text = value.decode("utf-8")
    output: list[str] = []
    index = 0
    in_string = False
    escaped = False
    while index < len(text):
        char = text[index]
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
        elif text.startswith("//", index):
            end = text.find("\n", index + 2)
            index = len(text) if end < 0 else end
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            if end < 0:
                raise ValueError("unterminated block comment")
            output.append(" ")
            output.extend("\n" for item in text[index:end + 2] if item == "\n")
            index = end + 2
        else:
            output.append(char)
            index += 1
    # A second string-aware pass removes only commas followed by ] or }.
    text = "".join(output)
    output = []
    index = 0
    in_string = escaped = False
    while index < len(text):
        char = text[index]
        if in_string:
            output.append(char)
            if escaped: escaped = False
            elif char == "\\": escaped = True
            elif char == '"': in_string = False
        elif char == '"':
            in_string = True
            output.append(char)
        elif char == ',':
            lookahead = index + 1
            while lookahead < len(text) and text[lookahead].isspace(): lookahead += 1
            if lookahead >= len(text) or text[lookahead] not in "]}": output.append(char)
        else:
            output.append(char)
        index += 1
    return "".join(output)


def read_jsonc(path: Path, *, size_limit: int = MAX_CONFIG_INPUT_BYTES,
               maximum_depth: int = MAX_JSON_NESTING_DEPTH) -> Any:
    size = path.stat().st_size
    if size > size_limit:
        raise ValueError(f"file is {size} bytes; limit is {size_limit} bytes")
    return parse_json(strip_jsonc(path.read_bytes()), maximum_depth=maximum_depth)


def read_json(path: Path, *, size_limit: int | None = None,
              maximum_depth: int = MAX_JSON_NESTING_DEPTH) -> Any:
    if size_limit is not None:
        size = path.stat().st_size
        if size > size_limit:
            raise ValueError(f"file is {size} bytes; limit is {size_limit} bytes")
    try:
        return parse_json(path.read_bytes(), maximum_depth=maximum_depth)
    except RecursionError as error:
        raise ValueError("JSON file handling exceeded Python's recursion limit") from error


def annotate(raw: Any, *, bundled: bool, source_dir: Path, source: str) -> Any:
    value = dict(raw) if isinstance(raw, dict) else {"_invalidDefinition": raw}
    value["_bundled"] = bundled
    value["_sourceDir"] = str(source_dir)
    value["_source"] = source
    requirements = value.get("requires", [])
    value["_missingRequires"] = [
        item for item in requirements
        if isinstance(requirements, list) and isinstance(item, str) and item and shutil.which(item) is None
    ] if isinstance(requirements, list) else []
    return value


def enabled_plugin_ids(timeout: float, maximum_depth: int = MAX_JSON_NESTING_DEPTH) -> tuple[set[str], list[str], bool]:
    status, stdout, stderr = run_bounded(
        ["omarchy", "plugin", "list", "--json"], cwd=None, timeout=timeout, limit=COMMAND_OUTPUT_BYTES
    )
    if status != "ok":
        detail = stderr.decode("utf-8", "replace").strip()[:DIAGNOSTIC_STDERR_BYTES]
        suffix = f": {detail}" if detail else ""
        return set(), [f"Could not list enabled Omarchy plugins ({status}){suffix}; external extensions were skipped"], False
    try:
        plugins = parse_json(stdout, maximum_depth=maximum_depth)
    except (RecursionError, ValueError, UnicodeDecodeError) as error:
        return set(), [f"Could not list enabled Omarchy plugins: output was not valid JSON ({error}); external extensions were skipped"], False
    if not isinstance(plugins, list):
        return set(), ["Could not list enabled Omarchy plugins: expected a JSON array; external extensions were skipped"], False
    return {
        item.get("id") for item in plugins
        if isinstance(item, dict) and item.get("enabled") is True and isinstance(item.get("id"), str)
    }, [], True


def provider_failure(source: str, status: str, stderr: bytes, output_limit: int) -> str:
    if status == "timeout":
        reason = "timed out"
    elif status.startswith("oversized:"):
        reason = f"exceeded the {output_limit}-byte {status.split(':', 1)[1]} limit"
    elif status.startswith("exit:"):
        reason = f"exited with code {status.split(':', 1)[1]}"
    else:
        reason = f"could not start ({status.split(':', 1)[-1]})"
    detail = stderr.decode("utf-8", "replace").strip()[:DIAGNOSTIC_STDERR_BYTES]
    return f"Extension provider {source} {reason}" + (f": {detail}" if detail else "")


def load_user_configuration(home: Path, builder: CatalogBuilder, limits: Limits) -> None:
    config_root = home / ".config" / "omarchy" / "omalaunch"
    main_path = config_root / "config.jsonc"
    if main_path.exists():
        try:
            value = read_jsonc(main_path, maximum_depth=limits.json_nesting_depth)
            if not isinstance(value, dict) or value.get("version") != 1:
                raise ValueError("expected an object with version 1")
            capabilities = value.get("capabilities", {})
            if not isinstance(capabilities, dict):
                raise ValueError("capabilities must be an object")
            if len(capabilities) > MAX_CONFIG_CAPABILITIES:
                builder.diagnostic(f"Configuration {main_path} has more than {MAX_CONFIG_CAPABILITIES} capabilities; trailing entries were ignored")
            normalized_capabilities: dict[str, dict[str, Any]] = {}
            for capability, setting in list(capabilities.items())[:MAX_CONFIG_CAPABILITIES]:
                if not isinstance(capability, str) or not capability or not isinstance(setting, dict):
                    builder.diagnostic(f"Ignored invalid capability selection in {main_path}: {capability!r}")
                    continue
                normalized: dict[str, Any] = {}

                # A capability may be switched off, given a provider, or both.
                # Each key is reported only when it is actually present, so one
                # mistake does not also complain about a key the user omitted.
                if "enabled" in setting:
                    enabled = setting["enabled"]
                    # Strictly boolean: a truthy string would let a typo
                    # silently disable a feature.
                    if not isinstance(enabled, bool):
                        builder.diagnostic(f"Ignored non-boolean enabled for capability {capability!r} in {main_path}")
                    else:
                        normalized["enabled"] = enabled
                        if not enabled:
                            builder.disabled_capabilities.append(capability)

                if "provider" in setting:
                    provider = setting["provider"]
                    if not isinstance(provider, str) or not provider:
                        builder.diagnostic(f"Ignored invalid provider for capability {capability!r} in {main_path}")
                    else:
                        builder.provider_preferences[capability] = provider
                        normalized["provider"] = provider

                if "enabled" not in setting and "provider" not in setting:
                    builder.diagnostic(f"Ignored invalid provider for capability {capability!r} in {main_path}")

                if normalized:
                    normalized_capabilities[capability] = normalized
            builder.omalaunch_config = {
                "version": 1,
                "capabilities": normalized_capabilities,
            }
        except (OSError, UnicodeDecodeError, ValueError) as error:
            builder.diagnostic(f"Could not load configuration {main_path}: {error}")

    # Capability configuration is independent of provider identity. Load only
    # host-supported capability schemas, so files cannot select arbitrary paths.
    files_path = config_root / "extensions" / "files.jsonc"
    if files_path.exists():
        try:
            value = read_jsonc(files_path, maximum_depth=limits.json_nesting_depth)
            if not isinstance(value, dict) or value.get("version") != 1:
                raise ValueError("expected an object with version 1")
            include = value.get("includeGitIgnored", False)
            if not isinstance(include, bool):
                raise ValueError("includeGitIgnored must be a boolean")
            builder.capability_config["files"] = {"includeGitIgnored": include}
        except (OSError, UnicodeDecodeError, ValueError) as error:
            builder.diagnostic(f"Could not load configuration {files_path}: {error}")


def load_catalog(plugin_path: Path, omarchy_path: Path, home: Path, limits: Limits) -> dict[str, Any]:
    builder = CatalogBuilder(limits)
    static_bytes = 0

    def load_static(extension_file: Path, *, bundled: bool, source_dir: Path, source: str) -> None:
        nonlocal static_bytes
        try:
            size = extension_file.stat().st_size
        except OSError as error:
            builder.diagnostic(f"Could not load {source}: {error}")
            return
        if static_bytes + size > limits.static_input_bytes:
            builder.diagnostic(
                f"Ignored {source}: aggregate static extension input exceeded {limits.static_input_bytes} bytes"
            )
            return
        static_bytes += size
        try:
            builder.append(read_json(extension_file, maximum_depth=limits.json_nesting_depth),
                           bundled=bundled, source_dir=source_dir, source=source)
        except (OSError, RecursionError, ValueError, UnicodeDecodeError) as error:
            builder.diagnostic(f"Could not load {source}: {error}")

    for extension_file in sorted(plugin_path.glob("extensions/*/extension.json")):
        load_static(extension_file, bundled=True, source_dir=extension_file.parent,
                    source=f"bundled file {extension_file}")

    enabled, enabled_diagnostics, complete = enabled_plugin_ids(
        limits.provider_timeout, limits.json_nesting_depth
    )
    for message in enabled_diagnostics:
        builder.diagnostic(message)
    manifest_roots = (omarchy_path / "shell" / "plugins", home / ".config" / "omarchy" / "plugins")
    total_providers = 0
    provider_runtime = 0.0
    provider_deadline_reported = False
    total_provider_limit_reported = False

    # Root order is the explicit precedence: the Omarchy-managed shell root
    # wins over the user plugin root, and lexical path order breaks ties inside
    # one root. Discovery first collects at most the bounded filesystem-work
    # budget, then sorts that bounded batch; no unbounded glob list is built.
    selected_manifests: dict[str, tuple[Path, dict[str, Any]]] = {}
    filesystem_entries = 0
    discovered_manifests = 0
    manifest_bytes = 0
    discovery_exhausted: str | None = None
    filesystem_discovery_exhausted: str | None = None
    for manifest_root in manifest_roots:
        if discovery_exhausted or filesystem_discovery_exhausted:
            break
        candidates: list[Path] = []
        try:
            with os.scandir(manifest_root) as entries:
                for entry in entries:
                    if filesystem_entries >= limits.manifest_filesystem_entries:
                        filesystem_discovery_exhausted = (
                            f"filesystem entry limit ({limits.manifest_filesystem_entries})"
                        )
                        break
                    filesystem_entries += 1
                    try:
                        if entry.is_dir(follow_symlinks=True):
                            candidates.append(Path(entry.path) / "manifest.json")
                    except OSError:
                        # A raced or unreadable entry still consumes work; the
                        # candidate cannot safely contribute a manifest.
                        continue
        except OSError as error:
            builder.diagnostic(f"Could not scan plugin manifest root {manifest_root}: {error}")
            continue

        for manifest_path in sorted(candidates):
            if discovery_exhausted:
                break
            try:
                if not manifest_path.is_file():
                    continue
                if discovered_manifests >= limits.discovered_manifests:
                    discovery_exhausted = f"manifest count limit ({limits.discovered_manifests})"
                    break
                discovered_manifests += 1
                size = manifest_path.stat().st_size
                if manifest_bytes + size > limits.total_manifest_bytes:
                    discovery_exhausted = (
                        f"aggregate manifest byte limit ({limits.total_manifest_bytes} bytes)"
                    )
                    break
                manifest_bytes += size
                manifest = read_json(
                    manifest_path, size_limit=limits.manifest_input_bytes,
                    maximum_depth=limits.json_nesting_depth,
                )
            except (OSError, RecursionError, ValueError, UnicodeDecodeError) as error:
                builder.diagnostic(f"Could not load plugin manifest {manifest_path}: {error}")
                continue
            if not isinstance(manifest, dict) or not isinstance(manifest.get("id"), str):
                builder.diagnostic(f"Ignored invalid plugin manifest {manifest_path}: expected an object with a string id")
                continue
            plugin_id = manifest["id"]
            if plugin_id not in enabled:
                continue
            if plugin_id in selected_manifests:
                selected_path = selected_manifests[plugin_id][0]
                builder.diagnostic(
                    f"Ignored shadowed manifest for plugin {plugin_id} at {manifest_path}; "
                    f"using higher-precedence {selected_path}"
                )
                continue
            selected_manifests[plugin_id] = (manifest_path, manifest)

    exhausted_reason = discovery_exhausted or filesystem_discovery_exhausted
    if exhausted_reason:
        builder.diagnostic(
            f"Plugin manifest discovery budget exhausted at the {exhausted_reason}; "
            "remaining manifests across both roots were skipped"
        )

    for plugin_id, (manifest_path, manifest) in selected_manifests.items():
        plugin_dir = manifest_path.parent.resolve()
        omalaunch = manifest.get("omalaunch", {})
        if not isinstance(omalaunch, dict):
            builder.diagnostic(f"Plugin {plugin_id} has an invalid omalaunch manifest object in {manifest_path}")
            continue

        static_entries: list[Any] = []
        static_entries_declared = 0
        for field in ("extensions", "queryProviders"):
            entries = omalaunch.get(field, [])
            if not isinstance(entries, list):
                builder.diagnostic(f"Plugin {plugin_id} omalaunch.{field} must be an array in {manifest_path}")
                continue
            static_entries_declared += len(entries)
            remaining = max(0, limits.static_entries_per_plugin - len(static_entries))
            static_entries.extend(entries[:remaining])
        if static_entries_declared > limits.static_entries_per_plugin:
            builder.diagnostic(
                f"Plugin {plugin_id} declares {static_entries_declared} static extension entries; only the first "
                f"{limits.static_entries_per_plugin} were considered"
            )
        for entry in static_entries:
            extension_file = safe_plugin_file(plugin_dir, entry)
            if extension_file is None:
                builder.diagnostic(f"Plugin {plugin_id} extension path is missing or unsafe: {entry!r}")
                continue
            load_static(extension_file, bundled=False, source_dir=extension_file.parent,
                        source=f"plugin {plugin_id} file {entry}")

        providers = omalaunch.get("extensionProviders", [])
        if not isinstance(providers, list):
            builder.diagnostic(f"Plugin {plugin_id} omalaunch.extensionProviders must be an array in {manifest_path}")
            continue
        if len(providers) > limits.providers_per_plugin:
            builder.diagnostic(
                f"Plugin {plugin_id} declares {len(providers)} extension providers; only the first "
                f"{limits.providers_per_plugin} were considered"
            )
        for index, raw_command in enumerate(providers[:limits.providers_per_plugin]):
            source = f"plugin {plugin_id} provider #{index + 1}"
            if total_providers >= limits.total_providers:
                if not total_provider_limit_reported:
                    builder.diagnostic(
                        f"Total extension provider limit ({limits.total_providers}) reached; remaining providers were skipped"
                    )
                    total_provider_limit_reported = True
                continue
            total_providers += 1
            remaining_runtime = limits.aggregate_provider_seconds - provider_runtime
            if remaining_runtime <= 0:
                if not provider_deadline_reported:
                    builder.diagnostic(
                        f"Aggregate extension provider runtime limit ({limits.aggregate_provider_seconds:g} seconds) reached; remaining providers were skipped"
                    )
                    provider_deadline_reported = True
                continue
            command, command_error = command_for_provider(plugin_dir, raw_command)
            if command_error:
                builder.diagnostic(f"Extension provider {source} {command_error}")
                continue
            assert command is not None
            started = time.monotonic()
            status, stdout, stderr = run_bounded(
                command, cwd=plugin_dir,
                timeout=max(0.01, min(limits.provider_timeout, remaining_runtime)),
                limit=limits.provider_output_bytes,
            )
            provider_runtime += time.monotonic() - started
            if status != "ok":
                builder.diagnostic(provider_failure(source, status, stderr, limits.provider_output_bytes))
                continue
            try:
                definitions = parse_json(stdout, maximum_depth=limits.json_nesting_depth)
            except (RecursionError, ValueError, UnicodeDecodeError) as error:
                builder.diagnostic(f"Extension provider {source} emitted invalid JSON: {error}")
                continue
            if not isinstance(definitions, (dict, list)):
                builder.diagnostic(f"Extension provider {source} must emit one extension object or an array of extension objects")
                continue
            builder.append(definitions, bundled=False, source_dir=plugin_dir, source=source)

    load_user_configuration(home, builder, limits)
    return builder.finish(complete=complete)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("plugin_path", type=Path)
    parser.add_argument("omarchy_path", type=Path)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--provider-timeout", type=float, default=PROVIDER_TIMEOUT_SECONDS, help=argparse.SUPPRESS)
    parser.add_argument("--provider-output-bytes", type=int, default=PROVIDER_OUTPUT_BYTES, help=argparse.SUPPRESS)
    parser.add_argument("--catalog-output-bytes", type=int, default=CATALOG_OUTPUT_BYTES, help=argparse.SUPPRESS)
    parser.add_argument("--max-providers-per-plugin", type=int, default=MAX_PROVIDERS_PER_PLUGIN, help=argparse.SUPPRESS)
    parser.add_argument("--max-total-providers", type=int, default=MAX_TOTAL_PROVIDERS, help=argparse.SUPPRESS)
    parser.add_argument("--max-definitions", type=int, default=MAX_TOTAL_DEFINITIONS, help=argparse.SUPPRESS)
    parser.add_argument("--max-static-bytes", type=int, default=MAX_STATIC_INPUT_BYTES, help=argparse.SUPPRESS)
    parser.add_argument("--aggregate-provider-timeout", type=float, default=AGGREGATE_PROVIDER_SECONDS, help=argparse.SUPPRESS)
    parser.add_argument("--max-manifests", type=int, default=MAX_DISCOVERED_MANIFESTS, help=argparse.SUPPRESS)
    parser.add_argument("--max-total-manifest-bytes", type=int, default=MAX_TOTAL_MANIFEST_BYTES, help=argparse.SUPPRESS)
    parser.add_argument("--max-manifest-fs-entries", type=int, default=MAX_MANIFEST_FILESYSTEM_ENTRIES, help=argparse.SUPPRESS)
    parser.add_argument("--max-json-depth", type=int, default=MAX_JSON_NESTING_DEPTH, help=argparse.SUPPRESS)
    args = parser.parse_args()
    limits = Limits(
        provider_timeout=max(0.01, args.provider_timeout),
        provider_output_bytes=max(128, args.provider_output_bytes),
        catalog_output_bytes=max(256, args.catalog_output_bytes),
        providers_per_plugin=max(0, args.max_providers_per_plugin),
        total_providers=max(0, args.max_total_providers),
        definitions=max(0, args.max_definitions),
        static_input_bytes=max(0, args.max_static_bytes),
        aggregate_provider_seconds=max(0, args.aggregate_provider_timeout),
        discovered_manifests=max(0, args.max_manifests),
        total_manifest_bytes=max(0, args.max_total_manifest_bytes),
        manifest_filesystem_entries=max(0, args.max_manifest_fs_entries),
        json_nesting_depth=max(1, args.max_json_depth),
    )
    try:
        result = load_catalog(args.plugin_path.resolve(), args.omarchy_path.resolve(), args.home.resolve(), limits)
        output = json.dumps(result, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    except (RecursionError, ValueError) as error:
        # The command's protocol must remain valid JSON even if a future code
        # path accidentally bypasses the iterative depth checks.
        fallback = {
            "extensions": [],
            "diagnostics": [f"Extension loader could not serialize its result safely: {error}"[:MAX_DIAGNOSTIC_CHARS]],
            "complete": False,
        }
        output = json.dumps(fallback, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    sys.stdout.write(output + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

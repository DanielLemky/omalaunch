#!/usr/bin/env python3

import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import runpy

ROOT = Path(__file__).resolve().parents[1]
LOADER = ROOT / "libexec" / "load-extensions.py"


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"ok - {message}")


def write_executable(path, content):
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def run_loader(plugin_root, omarchy_root, home, env, timeout="0.15", extra_args=None):
    result = subprocess.run(
        [str(LOADER), str(plugin_root), str(omarchy_root), "--home", str(home),
         "--provider-timeout", timeout] + list(extra_args or []),
        env=env,
        text=True,
        capture_output=True,
        check=True,
        timeout=10,
    )
    return json.loads(result.stdout)


loader_module = runpy.run_path(str(LOADER))
try:
    loader_module["parse_json"]("[" * 1500 + "0" + "]" * 1500)
    parser_recursion_bounded = False
except ValueError:
    parser_recursion_bounded = True
check(parser_recursion_bounded, "parser RecursionError is converted to a bounded JSON failure")
very_deep = 0
for _ in range(1500):
    very_deep = [very_deep]
defensive_builder = loader_module["CatalogBuilder"](loader_module["Limits"]())
defensive_builder.catalog = [very_deep]
defensive_result = defensive_builder.finish(complete=True)
check(defensive_result["complete"] is False and defensive_result["extensions"] == [],
      "final catalog helper converts over-recursive serialization state to an incomplete response")


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
elif mode == 'nan':
    print('{"schemaVersion":1,"id":"nan","label":"NaN","prefixes":["nan"],"command":["true"],"priority":NaN}')
elif mode == 'infinity':
    print('{"schemaVersion":1,"id":"infinity","label":"Infinity","prefixes":["infinity"],"command":["true"],"priority":Infinity}')
elif mode == 'negative-infinity':
    print('{"schemaVersion":1,"id":"negative-infinity","label":"Negative Infinity","prefixes":["negative-infinity"],"command":["true"],"priority":-Infinity}')
elif mode == 'float-overflow':
    print('{"schemaVersion":1,"id":"float-overflow","label":"Float overflow","prefixes":["float-overflow"],"command":["true"],"priority":1e400}')
elif mode in ('deep-boundary', 'deep-over'):
    nested = 0
    for _ in range(31 if mode == 'deep-boundary' else 32):
        nested = [nested]
    print(json.dumps({'schemaVersion': 1, 'id': mode, 'label': mode,
                      'prefixes': [mode], 'command': ['true'], 'extra': nested}))
elif mode == 'integer-overflow':
    print('{"schemaVersion":1,"id":"integer-overflow","label":"Integer overflow","prefixes":["integer-overflow"],"command":["true"],"priority":9007199254740992}')
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
                ["./provider.py", "nan"],
                ["./provider.py", "infinity"],
                ["./provider.py", "negative-infinity"],
                ["./provider.py", "float-overflow"],
                ["./provider.py", "integer-overflow"],
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

    config_root = home / ".config" / "omarchy" / "omalaunch"
    (config_root / "extensions").mkdir(parents=True)
    (config_root / "config.jsonc").write_text('{\n// selection\n"version": 1, "capabilities": {"files": {"provider": "chosen",},},\n}')
    (config_root / "extensions" / "files.jsonc").write_text('{"version": 1, "includeGitIgnored": true,}')

    catalog = run_loader(plugin_root, omarchy_root, home, env)
    check(catalog["providerPreferences"] == {"files": "chosen"}
          and catalog["omalaunchConfig"] == {
              "version": 1,
              "capabilities": {"files": {"provider": "chosen"}},
          }
          and catalog["capabilityConfig"] == {"files": {"includeGitIgnored": True}},
          "bounded JSONC loads core and capability configuration")
    check(catalog["disabledCapabilities"] == [],
          "no capability is disabled without being asked for")

    # A separate home: the shared one above is also used by the catalog
    # byte-limit check, which budgets for the envelope that config produces.
    disable_home = base / "disable-home"
    disable_config = disable_home / ".config" / "omarchy" / "omalaunch"
    disable_config.mkdir(parents=True)
    (disable_config / "config.jsonc").write_text(
        '{"version": 1, "capabilities": {'
        '"bundled": {"enabled": false},'
        '"both": {"enabled": false, "provider": "either"},'
        '"on": {"enabled": true},'
        '"typo": {"enabled": "false"},'
        '"empty": {}'
        '}}')
    disabled_catalog = run_loader(plugin_root, omarchy_root, disable_home, env)
    check(disabled_catalog["disabledCapabilities"] == ["bundled", "both"],
          "capabilities switched off are reported to the host")
    check(disabled_catalog["omalaunchConfig"]["capabilities"] == {
              "bundled": {"enabled": False},
              "both": {"enabled": False, "provider": "either"},
              "on": {"enabled": True},
          },
          "an enabled flag is recorded alongside any provider selection")
    check(disabled_catalog["providerPreferences"] == {"both": "either"},
          "a disabled capability still records its provider selection for when it is switched back on")
    disable_messages = "\n".join(disabled_catalog["diagnostics"])
    check("Ignored non-boolean enabled for capability 'typo'" in disable_messages,
          "a non-boolean enabled is refused rather than treated as truthy")
    check("Ignored invalid provider for capability 'typo'" not in disable_messages,
          "one malformed key does not also complain about a key the user omitted")
    check("Ignored invalid provider for capability 'empty'" in disable_messages,
          "a capability with no recognized setting is diagnosed")
    # The loader reports the user's choice; MenuModel is what drops the
    # capability, so a disabled bundled extension still appears here.
    check(any(item.get("id") == "bundled" for item in disabled_catalog["extensions"]),
          "the loader reports disabled capabilities rather than filtering them itself")

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
    check(all(value in messages for value in ("NaN", "Infinity", "-Infinity"))
          and not any(item.get("id") in {"nan", "infinity", "negative-infinity"} for item in catalog["extensions"]),
          "provider JSON constants are rejected independently with provider provenance")
    check("1e400" in messages and "9007199254740992" in messages
          and not any(item.get("id") in {"float-overflow", "integer-overflow"} for item in catalog["extensions"]),
          "provider numeric overflow is rejected before Python-to-QML serialization")
    check(all(item.get("_source") for item in catalog["extensions"]),
          "catalog definitions retain actionable source provenance")
    check(catalog["complete"] is True, "successful plugin discovery marks the catalog complete")

    provider_limited = run_loader(plugin_root, omarchy_root, home, env, extra_args=[
        "--max-providers-per-plugin", "2", "--max-total-providers", "1"
    ])
    limited_messages = "\n".join(provider_limited["diagnostics"])
    check([item.get("id") for item in provider_limited["extensions"]] == ["bundled", "static", "dynamic"],
          "per-plugin and total provider bounds preserve earlier bundled, static, and provider definitions")
    check("only the first 2 were considered" in limited_messages and "Total extension provider limit (1)" in limited_messages,
          "provider aggregate bounds produce actionable diagnostics")

    definition_limited = run_loader(plugin_root, omarchy_root, home, env, extra_args=[
        "--max-definitions", "3"
    ])
    check(len(definition_limited["extensions"]) == 3
          and "Extension definition limit (3)" in "\n".join(definition_limited["diagnostics"]),
          "aggregate definition limits are injectable and preserve accepted definitions")

    bundled_size = bundled_dir.joinpath("extension.json").stat().st_size
    static_limited = run_loader(plugin_root, omarchy_root, home, env, extra_args=[
        "--max-static-bytes", str(bundled_size)
    ])
    check([item.get("id") for item in static_limited["extensions"]][:1] == ["bundled"]
          and "aggregate static extension input exceeded" in "\n".join(static_limited["diagnostics"]),
          "aggregate static input bytes are bounded without discarding earlier valid definitions")

    runtime_limited = run_loader(plugin_root, omarchy_root, home, env, extra_args=[
        "--aggregate-provider-timeout", "0"
    ])
    check("Aggregate extension provider runtime limit" in "\n".join(runtime_limited["diagnostics"]),
          "aggregate provider execution runtime is bounded")

    byte_limited_result = subprocess.run(
        [str(LOADER), str(plugin_root), str(omarchy_root), "--home", str(home),
         "--provider-timeout", "0.15", "--catalog-output-bytes", "900"],
        env=env, capture_output=True, check=True, timeout=10,
    )
    byte_limited = json.loads(byte_limited_result.stdout)
    check(len(byte_limited_result.stdout) <= 901 and byte_limited["extensions"],
          "incremental catalog byte enforcement stays within the injected output limit and preserves valid entries")

    # Every parsed source has an iterative 32-level nesting bound. A definition
    # object plus 31 nested arrays is exactly the boundary.
    deep_static = plugin_dir / "deep-static.json"
    boundary_nested = 0
    for _ in range(31):
        boundary_nested = [boundary_nested]
    deep_static.write_text(json.dumps({
        "schemaVersion": 1, "id": "deep-static", "label": "Deep static",
        "prefixes": ["deep-static"], "command": ["true"], "extra": boundary_nested,
    }), encoding="utf-8")
    manifest["omalaunch"]["extensions"].append("deep-static.json")
    plugin_dir.joinpath("manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    boundary_static = run_loader(plugin_root, omarchy_root, home, env)
    check("deep-static" in [item.get("id") for item in boundary_static["extensions"]],
          "static JSON accepts exactly the documented 32 nesting levels")
    deep_static.write_text(json.dumps({
        "schemaVersion": 1, "id": "too-deep-static", "label": "Too deep",
        "prefixes": ["too-deep-static"], "command": ["true"], "extra": [boundary_nested],
    }), encoding="utf-8")
    overdeep_static = run_loader(plugin_root, omarchy_root, home, env)
    check("too-deep-static" not in [item.get("id") for item in overdeep_static["extensions"]]
          and "JSON nesting exceeds the 32-level limit" in "\n".join(overdeep_static["diagnostics"]),
          "byte-bounded over-depth static JSON is isolated with source diagnostics")
    manifest["omalaunch"]["extensions"].remove("deep-static.json")
    deep_static.unlink()

    manifest["omalaunch"]["extensionProviders"].append(["./provider.py", "deep-boundary"])
    plugin_dir.joinpath("manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    boundary_provider = run_loader(plugin_root, omarchy_root, home, env)
    check("deep-boundary" in [item.get("id") for item in boundary_provider["extensions"]],
          "provider JSON accepts exactly the documented 32 nesting levels")
    manifest["omalaunch"]["extensionProviders"][-1] = ["./provider.py", "deep-over"]
    plugin_dir.joinpath("manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    overdeep_provider = run_loader(plugin_root, omarchy_root, home, env)
    check("deep-over" not in [item.get("id") for item in overdeep_provider["extensions"]]
          and "provider #14 emitted invalid JSON: JSON nesting exceeds the 32-level limit"
              in "\n".join(overdeep_provider["diagnostics"]),
          "byte-bounded over-depth provider JSON is isolated with provider diagnostics")
    manifest["omalaunch"]["extensionProviders"].pop()
    plugin_dir.joinpath("manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    # Strict static JSON is isolated exactly like provider output.
    invalid_static = plugin_dir / "invalid-static.json"
    invalid_static.write_text('{"schemaVersion":1,"id":"bad-static","label":"Bad","priority":NaN}', encoding="utf-8")
    manifest["omalaunch"]["extensions"].append("invalid-static.json")
    plugin_dir.joinpath("manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    strict_static = run_loader(plugin_root, omarchy_root, home, env)
    check("plugin example.dynamic file invalid-static.json" in "\n".join(strict_static["diagnostics"])
          and "NaN" in "\n".join(strict_static["diagnostics"])
          and "bad-static" not in [item.get("id") for item in strict_static["extensions"]],
          "non-finite static JSON is rejected with file provenance without poisoning other definitions")
    manifest["omalaunch"]["extensions"].remove("invalid-static.json")
    plugin_dir.joinpath("manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    invalid_static.unlink()

    # The managed root has explicit precedence and duplicate ids consume one
    # plugin budget rather than running both manifests.
    managed_plugin = omarchy_root / "shell" / "plugins" / "managed-dynamic"
    managed_plugin.mkdir(parents=True)
    managed_plugin.joinpath("managed.json").write_text(json.dumps({
        "schemaVersion": 1, "id": "managed", "label": "Managed",
        "prefixes": ["managed"], "command": ["true"]
    }), encoding="utf-8")
    managed_plugin.joinpath("manifest.json").write_text(json.dumps({
        "id": "example.dynamic", "omalaunch": {"extensions": ["managed.json"], "extensionProviders": []}
    }), encoding="utf-8")
    shadowed = run_loader(plugin_root, omarchy_root, home, env)
    shadowed_ids = [item.get("id") for item in shadowed["extensions"]]
    check("managed" in shadowed_ids and "static" not in shadowed_ids and "dynamic" not in shadowed_ids,
          "higher-precedence duplicate manifest is the only materialized plugin definition set")
    check("Ignored shadowed manifest for plugin example.dynamic" in "\n".join(shadowed["diagnostics"])
          and str(managed_plugin / "manifest.json") in "\n".join(shadowed["diagnostics"]),
          "shadowed manifests are diagnosed with deterministic selected provenance")
    shutil.rmtree(omarchy_root / "shell")

    # Per-source definition and per-plugin static declaration caps apply before
    # all entries are materialized into the catalog.
    cap_plugin = plugins_root / "caps"
    cap_plugin.mkdir()
    many_definitions = [{
        "schemaVersion": 1, "id": f"cap-{index}", "label": f"Cap {index}",
        "prefixes": [f"cap-{index}"], "command": ["true"]
    } for index in range(257)]
    cap_plugin.joinpath("many.json").write_text(json.dumps(many_definitions), encoding="utf-8")
    cap_plugin.joinpath("one.json").write_text(json.dumps(many_definitions[0]), encoding="utf-8")
    cap_plugin.joinpath("manifest.json").write_text(json.dumps({
        "id": "example.caps", "omalaunch": {"extensions": ["many.json"] + ["one.json"] * 128}
    }), encoding="utf-8")
    enabled_file.write_text(json.dumps([
        {"id": "example.dynamic", "enabled": True}, {"id": "example.caps", "enabled": True}
    ]), encoding="utf-8")
    capped = run_loader(plugin_root, omarchy_root, home, env)
    capped_messages = "\n".join(capped["diagnostics"])
    check(sum(1 for item in capped["extensions"] if str(item.get("id", "")).startswith("cap-")) == 383,
          "per-source and static declaration limits bound materialization while preserving accepted entries")
    check("only the first 256 were considered" in capped_messages
          and "only the first 128 were considered" in capped_messages,
          "definition and static declaration caps are diagnosed")
    shutil.rmtree(cap_plugin)

    # Discovery work, manifest count, and aggregate bytes are shared by both
    # roots. Bounded batches retain managed-root then lexical precedence.
    managed_budget_root = omarchy_root / "shell" / "plugins"
    for root_name, root_path in (("managed", managed_budget_root), ("user", plugins_root)):
        for index in range(6):
            budget_plugin = root_path / f"budget-{root_name}-{index:02d}"
            budget_plugin.mkdir(parents=True)
            budget_plugin.joinpath("extension.json").write_text(json.dumps({
                "schemaVersion": 1, "id": f"budget-{root_name}-{index:02d}",
                "label": "Budget", "prefixes": [f"budget-{root_name}-{index:02d}"],
                "command": ["true"],
            }), encoding="utf-8")
            budget_plugin.joinpath("manifest.json").write_text(json.dumps({
                "id": f"example.budget.{root_name}.{index:02d}",
                "omalaunch": {"extensions": ["extension.json"]},
            }), encoding="utf-8")
    enabled_file.write_text(json.dumps([
        {"id": f"example.budget.{root_name}.{index:02d}", "enabled": True}
        for root_name in ("managed", "user") for index in range(6)
    ]), encoding="utf-8")
    manifest_count_limited = run_loader(plugin_root, omarchy_root, home, env, extra_args=[
        "--max-manifests", "3"
    ])
    check([item.get("id") for item in manifest_count_limited["extensions"] if str(item.get("id", "")).startswith("budget-")]
          == ["budget-managed-00", "budget-managed-01", "budget-managed-02"]
          and sum("Plugin manifest discovery budget exhausted" in message
                  for message in manifest_count_limited["diagnostics"]) == 1,
          "aggregate manifest count is bounded once across roots with deterministic precedence")
    first_manifest_size = (managed_budget_root / "budget-managed-00" / "manifest.json").stat().st_size
    manifest_byte_limited = run_loader(plugin_root, omarchy_root, home, env, extra_args=[
        "--max-total-manifest-bytes", str(first_manifest_size)
    ])
    check([item.get("id") for item in manifest_byte_limited["extensions"] if str(item.get("id", "")).startswith("budget-")]
          == ["budget-managed-00"]
          and "aggregate manifest byte limit" in "\n".join(manifest_byte_limited["diagnostics"]),
          "aggregate manifest bytes stop parsing across both roots while preserving prior definitions")
    manifest_fs_limited = run_loader(plugin_root, omarchy_root, home, env, extra_args=[
        "--max-manifest-fs-entries", "2"
    ])
    fs_limited_budget_ids = [item.get("id") for item in manifest_fs_limited["extensions"]
                             if str(item.get("id", "")).startswith("budget-")]
    check(len(fs_limited_budget_ids) == 2
          and all(str(item_id).startswith("budget-managed-") for item_id in fs_limited_budget_ids)
          and "filesystem entry limit (2)" in "\n".join(manifest_fs_limited["diagnostics"]),
          "filesystem exhaustion preserves the bounded candidate batch before skipping later entries")
    shutil.rmtree(omarchy_root / "shell")
    for root_name in ("managed", "user"):
        for index in range(6):
            path = plugins_root / f"budget-{root_name}-{index:02d}"
            if path.exists(): shutil.rmtree(path)
    enabled_file.write_text(json.dumps([
        {"id": "example.dynamic", "enabled": True}
    ]), encoding="utf-8")

    # Manifests are size-bounded before parsing; malformed-manifest floods and
    # individual diagnostic text are bounded as well.
    oversized_plugin = plugins_root / "000-oversized-manifest"
    oversized_plugin.mkdir()
    oversized_plugin.joinpath("manifest.json").write_text(
        '{"id":"example.oversized","padding":"' + ('x' * (256 * 1024)) + '"}', encoding="utf-8")
    malformed_root = plugins_root / "malformed-000"
    malformed_root.mkdir()
    malformed_root.joinpath("manifest.json").write_text('{not-json', encoding="utf-8")
    for index in range(1, 270):
        malformed = plugins_root / f"malformed-{index:03d}"
        malformed.mkdir()
        malformed.joinpath("manifest.json").write_text('{not-json', encoding="utf-8")
    bounded_diagnostics = run_loader(plugin_root, omarchy_root, home, env)
    check(any("000-oversized-manifest/manifest.json" in message and "limit is 262144 bytes" in message
              for message in bounded_diagnostics["diagnostics"]),
          "manifest bytes are bounded before JSON loading with source provenance")
    check(len(bounded_diagnostics["diagnostics"]) <= 256
          and all(len(message) <= 1024 for message in bounded_diagnostics["diagnostics"])
          and any("Further diagnostics were omitted" in message for message in bounded_diagnostics["diagnostics"]),
          "diagnostic count and individual length are bounded under adversarial manifests")
    shutil.rmtree(oversized_plugin)
    for index in range(270):
        shutil.rmtree(plugins_root / f"malformed-{index:03d}")

    # Manifest and enabled-plugin JSON use the same strict depth parser.
    deep_manifest = plugins_root / "deep-manifest"
    deep_manifest.mkdir()
    manifest_nested = 0
    # The manifest root plus this chain is exactly 32 levels.
    for _ in range(31):
        manifest_nested = [manifest_nested]
    deep_manifest.joinpath("manifest.json").write_text(json.dumps({
        "id": "example.deep-manifest", "omalaunch": {}, "extra": manifest_nested,
    }), encoding="utf-8")
    enabled_file.write_text(json.dumps([
        {"id": "example.dynamic", "enabled": True},
        {"id": "example.deep-manifest", "enabled": True},
    ]), encoding="utf-8")
    boundary_manifest = run_loader(plugin_root, omarchy_root, home, env)
    check(not any("deep-manifest/manifest.json" in message and "nesting exceeds" in message
                  for message in boundary_manifest["diagnostics"]),
          "plugin manifest JSON accepts exactly 32 nesting levels")
    deep_manifest.joinpath("manifest.json").write_text(json.dumps({
        "id": "example.deep-manifest", "omalaunch": {}, "extra": [manifest_nested],
    }), encoding="utf-8")
    overdeep_manifest = run_loader(plugin_root, omarchy_root, home, env)
    check(any("deep-manifest/manifest.json" in message and "JSON nesting exceeds the 32-level limit" in message
              for message in overdeep_manifest["diagnostics"]),
          "over-depth plugin manifest JSON is rejected with bounded provenance")
    shutil.rmtree(deep_manifest)

    strict_manifest = plugins_root / "strict-manifest"
    strict_manifest.mkdir()
    strict_manifest.joinpath("manifest.json").write_text(
        '{"id":"example.strict","omalaunch":{},"priority":Infinity}', encoding="utf-8")
    enabled_file.write_text(json.dumps([
        {"id": "example.dynamic", "enabled": True}, {"id": "example.strict", "enabled": True}
    ]), encoding="utf-8")
    strict_manifest_catalog = run_loader(plugin_root, omarchy_root, home, env)
    check(any("strict-manifest/manifest.json" in message and "Infinity" in message
              for message in strict_manifest_catalog["diagnostics"]),
          "non-finite manifest JSON is rejected with manifest provenance")
    shutil.rmtree(strict_manifest)
    enabled_file.write_text('[{"id":"example.dynamic","enabled":true,"value":-Infinity}]', encoding="utf-8")
    strict_enabled = run_loader(plugin_root, omarchy_root, home, env)
    check(strict_enabled["complete"] is False and "-Infinity" in "\n".join(strict_enabled["diagnostics"]),
          "non-finite enabled-plugin registry JSON marks the catalog transient")
    registry_nested = 0
    for _ in range(31):
        registry_nested = [registry_nested]
    enabled_file.write_text(json.dumps([
        {"id": "example.dynamic", "enabled": True, "extra": registry_nested}
    ]), encoding="utf-8")
    overdeep_enabled = run_loader(plugin_root, omarchy_root, home, env)
    check(overdeep_enabled["complete"] is False
          and "JSON nesting exceeds the 32-level limit" in "\n".join(overdeep_enabled["diagnostics"]),
          "over-depth enabled-plugin output is rejected without crashing the loader protocol")

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
          and "external extensions were skipped" in "\n".join(missing_list["diagnostics"])
          and missing_list["complete"] is False,
          "plugin-list failure preserves bundled extensions and marks the catalog transient")

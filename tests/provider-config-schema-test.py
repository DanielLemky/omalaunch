#!/usr/bin/env python3
"""Check separate strict configuration and state schema contracts."""
import importlib.util, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("pc",ROOT/"libexec/provider_config.py"); pc=importlib.util.module_from_spec(spec); spec.loader.exec_module(pc)
def check(v,m):
    if not v: raise AssertionError(m)
    print("ok - "+m)
def schema(path):
    value=json.loads(path.read_text())
    check(value["$schema"]=="https://json-schema.org/draft/2020-12/schema" and value["additionalProperties"] is False,path.name+" is a strict draft-2020-12 schema")
    return value
config_dir=ROOT/"schemas/provider-config"; state_dir=ROOT/"schemas/provider-state"
check(sorted(x.name for x in config_dir.glob("*.json"))==["omalaunch.files.v1.schema.json","omalaunch.quicklinks.v1.schema.json","omalaunch.web-search.v1.schema.json"],"configurable bundled providers have user configuration schemas")
files_config=schema(config_dir/"omalaunch.files.v1.schema.json")
quicklinks_config=schema(config_dir/"omalaunch.quicklinks.v1.schema.json")
web_search_config=schema(config_dir/"omalaunch.web-search.v1.schema.json")
check(set(files_config["properties"])=={"version","includeGitIgnored"},"Files configuration contains no machine state")
check(set(quicklinks_config["properties"])=={"version","rankByUsage"},"Quicklinks configuration contains only usage ranking")
check(set(web_search_config["properties"])=={"version","engines"},"Web Search configuration owns search engine definitions")
for provider in pc.PROVIDERS:
    value=schema(state_dir/f"{provider}.v1.schema.json")
    check("includeGitIgnored" not in value["properties"],provider+" state excludes user configuration")
valid={
 "omalaunch.apps":{"version":1,"favorites":["app.desktop"]},
 "omalaunch.files":{"version":1,"favorites":[{"type":"directory","path":"/tmp/docs"}]},
 "omalaunch.quicklinks":{"version":1,"links":[{"id":"docs","name":"Docs","url":"https://example.test","starred":True,"openWith":{"type":"profile","profile":"Work"}}]},
 "omalaunch.web-search":{"version":1,"disabledEngines":["bing"]},
 "omalaunch.extensions":{"version":1,"favorites":["omalaunch.files"]},
}
for provider,value in valid.items():
    check(pc.validate_state(provider,value,Path("/home/test"))==value,provider+" valid state passes strict runtime validation")
    bad={**value,"unknown":True}
    try: pc.validate_state(provider,bad,Path("/home/test"))
    except ValueError: pass
    else: raise AssertionError(provider+" accepted unknown state")
check(pc.validate_config("omalaunch.files",{"version":1,"includeGitIgnored":True})["includeGitIgnored"],"valid Files JSONC shape passes")
check(pc.validate_config("omalaunch.quicklinks",{"version":1})["rankByUsage"],"Quicklinks usage ranking defaults to true")
check(not pc.validate_config("omalaunch.quicklinks",{"version":1,"rankByUsage":False})["rankByUsage"],"Quicklinks usage ranking can be disabled")
check(len(pc.config_default("omalaunch.web-search")["engines"])==5,"Web Search supplies five default engines")
check(pc.validate_config("omalaunch.web-search",{"version":1,"engines":[{"id":"example","name":"Example","url":"https://example.test/?q={query}"}]})["engines"][0]["id"]=="example","Web Search accepts a safe engine template")
for bad in ({"version":1,"favorites":[]},{"version":2},{"version":1,"includeGitIgnored":"yes"}):
    try: pc.validate_config("omalaunch.files",bad)
    except ValueError: pass
    else: raise AssertionError("invalid Files config passed")
print("ok - separate provider configuration and state schema suite")

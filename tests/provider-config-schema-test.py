#!/usr/bin/env python3
"""Check separate strict configuration and state schema contracts."""
import importlib.util, json
import fastjsonschema
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
check(sorted(x.name for x in config_dir.glob("*.json"))==["omalaunch.files.v1.schema.json","omalaunch.quicklinks.v1.schema.json","omalaunch.web-search.v1.schema.json","omalaunch.web-search.v2.schema.json"],"configurable bundled providers have user configuration schemas")
files_config=schema(config_dir/"omalaunch.files.v1.schema.json")
quicklinks_config=schema(config_dir/"omalaunch.quicklinks.v1.schema.json")
web_search_v1_config=schema(config_dir/"omalaunch.web-search.v1.schema.json")
web_search_v2_config=schema(config_dir/"omalaunch.web-search.v2.schema.json")
check(set(files_config["properties"])=={"version","includeGitIgnored"},"Files configuration contains no machine state")
check(set(quicklinks_config["properties"])=={"version","rankByUsage"},"Quicklinks configuration contains only usage ranking")
check(set(web_search_v1_config["properties"])=={"version","rankByUsage","engines"},"Web Search version 1 keeps its replacement engine list")
check(set(web_search_v2_config["properties"])=={"version","rankByUsage","engines"},"Web Search version 2 owns engine overrides and usage ranking")
validate_web_search_v1=fastjsonschema.compile(web_search_v1_config)
validate_web_search_v2=fastjsonschema.compile(web_search_v2_config)
valid_v1={"version":1,"engines":[{"id":"example","name":"Example","url":"https://example.test/?q={query}"}]}
valid_v2={"version":2,"engines":{"example":{"name":"Example","url":"https://example.test/?q={query}"},"bing":{"enabled":False}}}
validate_web_search_v1(valid_v1); validate_web_search_v2(valid_v2)
check(True,"Web Search schemas accept valid version 1 and version 2 documents")
schema_invalid=(
    (validate_web_search_v1,{"version":1,"engines":[valid_v1["engines"][0],valid_v1["engines"][0]]}),
    (validate_web_search_v2,{"version":2,"engines":{f"custom-{i}":{"name":f"Custom {i}","url":"https://example.test/?q={query}"} for i in range(28)}}),
    (validate_web_search_v2,{"version":2,"engines":{"example":{"name":"Example"}}}),
    (validate_web_search_v2,{"version":2,"engines":{"bing":{"enabled":False,"name":"Hidden Bing"}}}),
)
for validate,value in schema_invalid:
    try: validate(value)
    except fastjsonschema.JsonSchemaException: pass
    else: raise AssertionError("Web Search schema accepted an invalid structure")
check(True,"Web Search schemas enforce structural engine limits and shapes")
v2_engines=web_search_v2_config["properties"]["engines"]
check(set(v2_engines["properties"])=={"google","duckduckgo","bing","brave","ecosia"} and v2_engines["additionalProperties"]=={"$ref":"#/$defs/newEngine"},"Web Search version 2 schema separates bundled overrides from new engines")
for provider in pc.PROVIDERS:
    value=schema(state_dir/f"{provider}.v1.schema.json")
    check("includeGitIgnored" not in value["properties"],provider+" state excludes user configuration")
valid={
 "omalaunch.apps":{"version":1,"favorites":["app.desktop"]},
 "omalaunch.files":{"version":1,"favorites":[{"type":"directory","path":"/tmp/docs"}]},
 "omalaunch.quicklinks":{"version":1,"links":[{"id":"docs","name":"Docs","url":"https://example.test","starred":True,"openWith":{"type":"profile","profile":"Work"}}]},
 "omalaunch.web-search":{"version":1,"globalSearchExcludedEngines":["bing"],"starredEngines":["google"]},
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
check(len(pc.config_default("omalaunch.web-search")["engines"])==5 and pc.config_default("omalaunch.web-search")["rankByUsage"] is True,"Web Search supplies five default engines and enables usage ranking")
v1=pc.validate_config("omalaunch.web-search",{"version":1,"engines":[{"id":"example","name":"Example","url":"https://example.test/?q={query}"}]})
check([x["id"] for x in v1["engines"]]==["example"],"Web Search version 1 keeps complete replacement behavior")
v2=pc.validate_config("omalaunch.web-search",{"version":2,"engines":{"kagi":{"name":"Kagi","url":"https://kagi.com/search?q={query}"},"bing":{"enabled":False}}})
check([x["id"] for x in v2["engines"]]==["google","duckduckgo","brave","ecosia","kagi"],"Web Search version 2 adds and disables engines")
override=pc.validate_config("omalaunch.web-search",{"version":2,"engines":{"google":{"name":"Private Google","url":"https://example.test/?q={query}"}}})
check(len(override["engines"])==5 and override["engines"][0]["name"]=="Private Google","Web Search version 2 overrides a bundled engine")
check(len(pc.validate_config("omalaunch.web-search",{"version":2,"engines":{}})["engines"])==5,"Web Search version 2 can retain all defaults")
check(pc.validate_config("omalaunch.web-search",{"version":2,"rankByUsage":False,"engines":{}})["rankByUsage"] is False,"Web Search usage ranking can be disabled")
for name,url in (
    ("Example","https://example.test/"),
    ("Example","https://example.test/?a={query}&b={query}"),
    ("Example","ftp://example.test/?q={query}"),
    ("Example","https://user@example.test/?q={query}"),
    ("Example","https://exa mple.test/?q={query}"),
    ("Example","https://example.test:bad/?q={query}"),
    ("Example","https://example.test:99999/?q={query}"),
    ("Example","https://[::1/?q={query}"),
    ("Bad\nName","https://example.test/?q={query}"),
):
    for value in (
        {"version":1,"engines":[{"id":"example","name":name,"url":url}]},
        {"version":2,"engines":{"example":{"name":name,"url":url}}},
    ):
        try: pc.validate_config("omalaunch.web-search",value)
        except ValueError: pass
        else: raise AssertionError("Web Search runtime accepted an unsafe engine")
check(True,"Web Search runtime rejects unsafe engine names and URLs")
for bad in (
    {"version":1,"engines":[{"id":"same","name":"One","url":"https://one.test/?q={query}"},{"id":"same","name":"Two","url":"https://two.test/?q={query}"}]},
    {"version":2,"engines":{"kagi":{"name":"Kagi"}}},
    {"version":2,"engines":{"kagi":{"enabled":False}}},
    {"version":2,"engines":{"bing":{"enabled":False,"name":"Hidden Bing"}}},
    {"version":2,"engines":{"bad/id":{"name":"Bad","url":"https://example.test/?q={query}"}}},
    {"version":2,"engines":{f"custom-{i}":{"name":f"Custom {i}","url":"https://example.test/?q={query}"} for i in range(28)}},
    {"version":3,"engines":{}},
):
    try: pc.validate_config("omalaunch.web-search",bad)
    except ValueError: pass
    else: raise AssertionError("Web Search accepted invalid version 2 engine customization")
print("ok - Web Search rejects duplicate IDs and invalid version 2 engine customization")
try: pc.validate_state("omalaunch.web-search",{"version":1,"globalSearchExcludedEngines":["google"],"starredEngines":["google"]},Path("/home/test"))
except ValueError: pass
else: raise AssertionError("Web Search accepted a starred engine excluded from global search")
print("ok - Web Search rejects contradictory star and global-search state")
for bad in ({"version":1,"favorites":[]},{"version":2},{"version":1,"includeGitIgnored":"yes"}):
    try: pc.validate_config("omalaunch.files",bad)
    except ValueError: pass
    else: raise AssertionError("invalid Files config passed")
print("ok - separate provider configuration and state schema suite")

#!/usr/bin/env python3
import importlib.util, json, os, pathlib, stat, subprocess, sys, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("pc",ROOT/"libexec/provider_config.py"); pc=importlib.util.module_from_spec(spec); spec.loader.exec_module(pc)
def check(v,m):
    if not v: raise AssertionError(m)
    print("ok - "+m)
with tempfile.TemporaryDirectory() as raw:
    base=pathlib.Path(raw); home=base/"home"; state=base/"state"; home.mkdir()
    env={**os.environ,"HOME":str(home),"XDG_STATE_HOME":str(state)}; os.environ["XDG_STATE_HOME"]=str(state); cli=ROOT/"libexec/provider-config"
    for provider in pc.PROVIDERS: check(pc.load_state(provider,home)==pc.state_default(provider),provider+" has missing-state defaults")
    check(pc.load_config("omalaunch.files",home)=={"version":1,"includeGitIgnored":False},"Files has a missing-config default")
    check(pc.load_config("omalaunch.quicklinks",home)=={"version":1,"rankByUsage":True},"Quicklinks has an enabled missing-config default")
    check(len(pc.load_config("omalaunch.web-search",home)["engines"])==5,"Web Search has default engines")
    for extension in ("quicklinks","web-search"):
        definition=json.loads((ROOT/"extensions"/extension/"extension.json").read_text())
        check("omarchy-launch-editor" not in definition["requires"] and "omarchy-agent" not in definition["requires"],extension+" stays available without optional settings tools")
    quicklinks_created=pc.ensure_config("omalaunch.quicklinks",home)
    web_search_created=pc.ensure_config("omalaunch.web-search",home)
    check(json.loads(quicklinks_created.read_text())=={"version":1,"rankByUsage":True},"Quicklinks creates its editable default configuration")
    check(json.loads(web_search_created.read_text())=={"version":2,"rankByUsage":True,"engines":{}},"Web Search creates its additive editable default configuration")
    check(quicklinks_created.stat().st_mode&0o777==0o600 and web_search_created.stat().st_mode&0o777==0o600,"created provider configurations are private")
    quicklinks_created.unlink(); web_search_created.unlink()
    target=base/"provider-target.jsonc"; target.write_text('{"version":1,"rankByUsage":false}')
    quicklinks_created.symlink_to(target)
    try: pc.ensure_config("omalaunch.quicklinks",home)
    except OSError: pass
    else: raise AssertionError("symbolic-link provider configuration must be rejected")
    check(target.read_text()=='{"version":1,"rankByUsage":false}',"symbolic-link provider configuration is rejected without changing its target")
    quicklinks_created.unlink()
    for provider in ("omalaunch.apps","omalaunch.extensions"):
        check(not pc.config_path(provider,home).exists(),provider+" has no meaningless config file")
    config=pc.config_path("omalaunch.files",home); config.parent.mkdir(parents=True,exist_ok=True)
    original=b'{\n  // preserve this comment and layout\n  "version": 1,\n  "includeGitIgnored": true,\n}\n'; config.write_bytes(original)
    quicklinks_config=pc.config_path("omalaunch.quicklinks",home)
    quicklinks_original=b'{\n  // keep ranking preference\n  "version": 1,\n  "rankByUsage": false,\n}\n'; quicklinks_config.write_bytes(quicklinks_original)
    subprocess.run([cli,"toggle","omalaunch.apps","app.desktop"],env=env,check=True)
    subprocess.run([cli,"toggle","omalaunch.files","directory:/tmp/a/../docs"],env=env,check=True)
    subprocess.run([cli,"toggle","omalaunch.extensions","omalaunch.files"],env=env,check=True)
    subprocess.run([cli,"add","omalaunch.quicklinks","https://example.test/docs","Docs"],env=env,check=True)
    subprocess.run([cli,"toggle-global-search","omalaunch.web-search","bing"],env=env,check=True)
    subprocess.run([cli,"toggle-star","omalaunch.web-search","google"],env=env,check=True)
    check(config.read_bytes()==original and quicklinks_config.read_bytes()==quicklinks_original,"UI mutations preserve JSONC comments and formatting byte for byte")
    check(pc.load("omalaunch.files",home)["includeGitIgnored"] is True,"runtime merges read-only Files configuration with state")
    check(pc.load("omalaunch.quicklinks",home)["rankByUsage"] is False,"runtime merges read-only Quicklinks configuration with state")
    check(pc.load_state("omalaunch.files",home)["favorites"]==[{"type":"directory","path":"/tmp/docs"}],"Files stores normalized typed favorites in state")
    check(pc.load_state("omalaunch.web-search",home)=={"version":1,"globalSearchExcludedEngines":["bing"],"starredEngines":["google"]},"Web Search stores global search exclusions and stars in state")
    web_search=subprocess.run([ROOT/"extensions/web-search/web-search","menu"],env=env,check=True,capture_output=True,text=True)
    search_items=json.loads(web_search.stdout)["items"]
    check([item["id"] for item in search_items]==["search-brave","search-duckduckgo","search-ecosia","search-google","search-bing"],"Web Search sorts global engines by name before excluded engines")
    bing=next(item for item in search_items if item["id"]=="search-bing")
    check(bing["globalSearch"] is False and bing["description"]=="Web Search menu","excluded engines remain usable in the Web Search menu")
    check(search_items[0]["trailingIcon"] and bing["trailingIcon"]=="","only global engines receive the trailing globe icon")
    missing_tools=base/"missing-tools"; missing_tools.mkdir()
    unavailable=json.loads(subprocess.run([sys.executable,cli,"configuration-menu","omalaunch.web-search","omalaunch.web-search"],env={**env,"PATH":str(missing_tools)},check=True,capture_output=True,text=True).stdout)["items"]
    check(all("(unavailable)" in item["label"] and item["description"].startswith("Unavailable:") for item in unavailable),"missing editor and agent tools disable only their settings actions")
    mismatch=subprocess.run([cli,"configuration-menu","omalaunch.web-search","replacement.web-search"],env=env,capture_output=True,text=True)
    check(mismatch.returncode!=0 and "identity does not match" in mismatch.stderr,"a replacement cannot open bundled provider settings")
    unknown=subprocess.run([cli,"configuration-menu","unknown.provider","unknown.provider"],env=env,capture_output=True,text=True)
    check(unknown.returncode!=0 and "no configuration menu" in unknown.stderr,"an unknown provider cannot open settings")
    google=next(item for item in search_items if item["id"]=="search-google")
    check(google["starred"] is True and google["starAction"]=="toggle-star","starred engines expose the dynamic-menu star action")
    subprocess.run([cli,"toggle-global-search","omalaunch.web-search","google"],env=env,check=True)
    check(pc.load_state("omalaunch.web-search",home)["starredEngines"]==[] and "google" in pc.load_state("omalaunch.web-search",home)["globalSearchExcludedEngines"],"removing a starred engine from global search also unstars it")
    check(next(item for item in search_items if item["id"]=="search-google")["input"]["closeOnSuccess"] is True,"Web Search closes after a successful query dispatch")
    bin_dir=base/"bin"; bin_dir.mkdir(); opened=base/"opened-url"
    opener=bin_dir/"xdg-open"; opener.write_text("#!/bin/sh\nprintf '%s' \"$1\" > \"$OPENED_URL\"\n"); opener.chmod(0o755)
    editor_record=base/"editor-path"; editor=bin_dir/"omarchy-launch-editor"; editor.write_text("#!/bin/sh\nprintf '%s' \"$1\" > \"$EDITOR_RECORD\"\n"); editor.chmod(0o755)
    agent_record=base/"agent.json"; default_agent=bin_dir/"omarchy-default-agent"; default_agent.write_text("#!/bin/sh\nprintf 'pi\\n'\n"); default_agent.chmod(0o755)
    agent=bin_dir/"omarchy-agent"; agent.write_text("#!/usr/bin/env python3\nimport json,os,sys\nopen(os.environ['AGENT_RECORD'],'w').write(json.dumps({'cwd':os.getcwd(),'args':sys.argv[1:]}))\n"); agent.chmod(0o755)
    open_env={**env,"PATH":str(bin_dir)+os.pathsep+env["PATH"],"OPENED_URL":str(opened),"EDITOR_RECORD":str(editor_record),"AGENT_RECORD":str(agent_record)}
    web_config_menu=json.loads(subprocess.run([cli,"configuration-menu","omalaunch.web-search","omalaunch.web-search"],env=open_env,check=True,capture_output=True,text=True).stdout)["items"]
    check([item["id"] for item in web_config_menu]==["open-config","edit-config-agent"] and all(item["closeOnDispatch"] for item in web_config_menu),"Web Search settings actions are available when their tools exist")
    subprocess.run([cli,"open-config","omalaunch.web-search"],env=open_env,check=True)
    web_config_path=pc.config_path("omalaunch.web-search",home)
    check(editor_record.read_text()==str(web_config_path) and json.loads(web_config_path.read_text())["version"]==2,"Open config creates and opens the Web Search configuration")
    check(stat.S_IMODE(web_config_path.stat().st_mode)==0o600 and stat.S_IMODE(web_config_path.parent.stat().st_mode)==0o700,"provider configuration and its directory are private")
    subprocess.run([cli,"edit-config-agent","omalaunch.quicklinks"],env=open_env,check=True)
    agent_launch=json.loads(agent_record.read_text())
    check(agent_launch["cwd"]==str(quicklinks_config.parent) and agent_launch["args"][0]=="--prompt" and "Quicklinks" in agent_launch["args"][1],"Edit with agent uses the shared launcher with provider context")
    subprocess.run([ROOT/"extensions/web-search/web-search","open","google","two words & more"],env=open_env,check=True)
    check(opened.read_text()=="https://www.google.com/search?q=two+words+%26+more","Web Search percent-encodes the complete query before opening it")
    links=pc.load_state("omalaunch.quicklinks",home)["links"]
    check(len(links)==1 and len(links[0]["id"])==32 and links[0]["openWith"]=={"type":"default"},"Quicklinks state has stable IDs and normalized openWith")
    link_id=links[0]["id"]
    state_file=pc.state_path("omalaunch.quicklinks",home); value=json.loads(state_file.read_text()); value["links"][0]["openWith"]={"type":"profile","profile":"Work"}; state_file.write_text(json.dumps(value))
    subprocess.run([cli,"star","omalaunch.quicklinks",link_id,"true"],env=env,check=True)
    link=pc.load_state("omalaunch.quicklinks",home)["links"][0]
    check(link["openWith"]=={"type":"profile","profile":"Work"} and link["starred"],"Quicklinks preserves an authoritative manual openWith assignment during normalization")
    quicklinks=subprocess.run([ROOT/"extensions/quicklinks/quicklinks","menu"],env=env,check=True,capture_output=True,text=True)
    quicklink_items=json.loads(quicklinks.stdout)["items"]
    quicklink_item=quicklink_items[1]
    quicklinks_config_menu=json.loads(subprocess.run([cli,"configuration-menu","omalaunch.quicklinks","omalaunch.quicklinks"],env=open_env,check=True,capture_output=True,text=True).stdout)["items"]
    check([item["id"] for item in quicklinks_config_menu]==["open-config","edit-config-agent"] and all(item["closeOnDispatch"] for item in quicklinks_config_menu),"Quicklinks settings actions are available when their tools exist")
    copy_action=next(action for action in quicklink_item["actions"] if action["id"]=="copy")
    check(copy_action["command"]==["wl-copy","--",link["url"]] and copy_action["closeOnSuccess"] is True,"Quicklinks Copy URL uses the tracked close-on-success action contract")
    for unsafe_url in ("https://example.test\\path", "https://exa mple.test", "https://example.test:bad"):
        result=subprocess.run([cli,"set-url","omalaunch.quicklinks",link_id,unsafe_url],env=env)
        check(result.returncode!=0 and pc.load_state("omalaunch.quicklinks",home)["links"][0]["url"]==link["url"],"Quicklinks rejects ambiguous URL: "+unsafe_url)
    result=subprocess.run([cli,"delete","omalaunch.quicklinks","missing-id"],env=env)
    check(result.returncode!=0 and len(pc.load_state("omalaunch.quicklinks",home)["links"])==1,"Quicklinks delete rejects an unknown identity without rewriting state")
    bad=b'{"version":1,"favorites":[],"bad":true}'; app_state=pc.state_path("omalaunch.apps",home); app_state.write_bytes(bad)
    result=subprocess.run([cli,"toggle","omalaunch.apps","other.desktop"],env=env)
    check(result.returncode!=0 and app_state.read_bytes()==bad,"invalid state is not overwritten")
    bad_config=b'{/*keep*/"version":1,"includeGitIgnored":"yes"}'; config.write_bytes(bad_config)
    result=subprocess.run([cli,"read-all"],env=env,check=True,capture_output=True,text=True); payload=json.loads(result.stdout)
    check(config.read_bytes()==bad_config and payload["configs"]["omalaunch.files"]["includeGitIgnored"] is False and payload["diagnostics"],"invalid config is not overwritten and gets a bounded diagnostic")
    app_state.unlink(); workers=[subprocess.Popen([cli,"toggle","omalaunch.apps",f"app-{i}"],env=env) for i in range(24)]
    check(all(p.wait()==0 for p in workers) and len(pc.load_state("omalaunch.apps",home)["favorites"])==24,"per-provider locks prevent lost concurrent updates")
    check(pc.state_path("omalaunch.apps",home).is_relative_to(state),"runtime honors XDG_STATE_HOME")
    replacement=pc.state_path("example.apps",home); check(not replacement.exists(),"replacement IDs do not inherit bundled state")
    check(pc.state_path("omalaunch.apps",home).stat().st_mode&0o777==0o600,"state writes are private")
print("ok - bundled provider runtime suite")

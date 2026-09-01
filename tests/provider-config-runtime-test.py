#!/usr/bin/env python3
import importlib.util, json, os, pathlib, subprocess, tempfile
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
    for provider in ("omalaunch.apps","omalaunch.extensions"):
        check(not pc.config_path(provider,home).exists(),provider+" has no meaningless config file")
    config=pc.config_path("omalaunch.files",home); config.parent.mkdir(parents=True)
    original=b'{\n  // preserve this comment and layout\n  "version": 1,\n  "includeGitIgnored": true,\n}\n'; config.write_bytes(original)
    subprocess.run([cli,"toggle","omalaunch.apps","app.desktop"],env=env,check=True)
    subprocess.run([cli,"toggle","omalaunch.files","directory:/tmp/a/../docs"],env=env,check=True)
    subprocess.run([cli,"toggle","omalaunch.extensions","omalaunch.files"],env=env,check=True)
    check(config.read_bytes()==original,"UI mutations preserve JSONC comments and formatting byte for byte")
    check(pc.load("omalaunch.files",home)["includeGitIgnored"] is True,"runtime merges read-only Files configuration with state")
    check(pc.load_state("omalaunch.files",home)["favorites"]==[{"type":"directory","path":"/tmp/docs"}],"Files stores normalized typed favorites in state")
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

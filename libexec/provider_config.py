#!/usr/bin/env python3
"""Strict provider configuration readers and locked provider state writers."""
from __future__ import annotations
import fcntl, json, math, os, re, stat, tempfile, urllib.parse
from pathlib import Path
from typing import Any, Callable

MAX_BYTES=64*1024; MAX_DEPTH=8; MAX_ITEMS=256; MAX_SAFE=9007199254740991
CONTROL=re.compile(r"[\x00-\x1f\x7f]"); LINK_ID=re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
PROVIDERS=("omalaunch.apps","omalaunch.files","omalaunch.quicklinks","omalaunch.web-search","omalaunch.extensions")
CONFIG_PROVIDERS=("omalaunch.files","omalaunch.quicklinks","omalaunch.web-search")
CONFIG_METADATA={
    "omalaunch.quicklinks":{"label":"Quicklinks","schemaVersion":1},
    "omalaunch.web-search":{"label":"Web Search","schemaVersion":2},
}
DEFAULT_SEARCH_ENGINES=[
    {"id":"google","name":"Google","url":"https://www.google.com/search?q={query}"},
    {"id":"duckduckgo","name":"DuckDuckGo","url":"https://duckduckgo.com/?q={query}"},
    {"id":"bing","name":"Bing","url":"https://www.bing.com/search?q={query}"},
    {"id":"brave","name":"Brave Search","url":"https://search.brave.com/search?q={query}"},
    {"id":"ecosia","name":"Ecosia","url":"https://www.ecosia.org/search?q={query}"},
]


def reject_constant(v:str)->Any: raise ValueError(f"non-finite number {v}")
def parse_int(v:str)->int:
    n=int(v)
    if abs(n)>MAX_SAFE: raise ValueError("integer exceeds safe range")
    return n
def parse_float(v:str)->float:
    n=float(v)
    if not math.isfinite(n): raise ValueError("non-finite number")
    return n
def depth(value:Any)->None:
    stack=[(value,0)]
    while stack:
        item,parent=stack.pop()
        if isinstance(item,(dict,list)):
            level=parent+1
            if level>MAX_DEPTH: raise ValueError("nesting exceeds 8 levels")
            children=item.values() if isinstance(item,dict) else item
            stack.extend((x,level) for x in children if isinstance(x,(dict,list)))
def strip_jsonc(raw:bytes)->str:
    text=raw.decode("utf-8"); out=[]; i=0; string=False; escaped=False
    while i<len(text):
        c=text[i]
        if string:
            out.append(c)
            if escaped: escaped=False
            elif c=="\\": escaped=True
            elif c=='"': string=False
            i+=1
        elif c=='"': string=True; out.append(c); i+=1
        elif text.startswith("//",i):
            end=text.find("\n",i+2); i=len(text) if end<0 else end
        elif text.startswith("/*",i):
            end=text.find("*/",i+2)
            if end<0: raise ValueError("unterminated block comment")
            out.extend("\n" for c in text[i:end+2] if c=="\n"); i=end+2
        else: out.append(c); i+=1
    text="".join(out); out=[]; i=0; string=False; escaped=False
    while i<len(text):
        c=text[i]
        if string:
            out.append(c)
            if escaped: escaped=False
            elif c=="\\": escaped=True
            elif c=='"': string=False
        elif c=='"': string=True; out.append(c)
        elif c==",":
            j=i+1
            while j<len(text) and text[j].isspace(): j+=1
            if j>=len(text) or text[j] not in "]}": out.append(c)
        else: out.append(c)
        i+=1
    return "".join(out)
def read_json(path:Path,*,jsonc:bool)->Any:
    raw=path.read_bytes()
    if len(raw)>MAX_BYTES: raise ValueError("file exceeds 64 KiB")
    value=json.loads(strip_jsonc(raw) if jsonc else raw,parse_constant=reject_constant,parse_int=parse_int,parse_float=parse_float)
    depth(value); return value

def config_default(provider:str)->dict[str,Any]:
    if provider=="omalaunch.files": return {"version":1,"includeGitIgnored":False}
    if provider=="omalaunch.quicklinks": return {"version":1,"rankByUsage":True}
    if provider=="omalaunch.web-search": return {"version":1,"rankByUsage":True,"engines":[dict(engine) for engine in DEFAULT_SEARCH_ENGINES]}
    return {}
def state_default(provider:str)->dict[str,Any]:
    if provider=="omalaunch.quicklinks": return {"version":1,"links":[]}
    if provider=="omalaunch.web-search": return {"version":1,"globalSearchExcludedEngines":[],"starredEngines":[]}
    return {"version":1,"favorites":[]}
def identity(v:Any,maxlen:int=255)->bool:
    return isinstance(v,str) and 1<=len(v)<=maxlen and "/" not in v and CONTROL.search(v) is None
def normalize_path(v:Any,home:Path)->str:
    if not isinstance(v,str) or not 1<=len(v)<=4096: raise ValueError("invalid path")
    if v.startswith("~/"): v=str(home)+v[1:]
    if not v.startswith("/"): raise ValueError("path is not absolute")
    parts=[]
    for part in v.split("/"):
        if not part or part==".": continue
        if part=="..":
            if not parts: raise ValueError("path moves above root")
            parts.pop()
        else: parts.append(part)
    return "/"+"/".join(parts)
def valid_url(v:Any)->bool:
    if (not isinstance(v,str) or not 10<=len(v)<=2048 or CONTROL.search(v)
            or "\\" in v or any(c.isspace() for c in v)): return False
    try:
        p=urllib.parse.urlsplit(v)
        hostname=p.hostname
        p.port # Reject malformed and out-of-range explicit ports.
    except (UnicodeError,ValueError): return False
    if p.scheme not in ("http","https") or not hostname or p.username is not None or p.password is not None: return False
    try: hostname.encode("idna")
    except UnicodeError: return False
    return True
def validate_config(provider:str,value:Any)->dict[str,Any]:
    if provider not in CONFIG_PROVIDERS: raise ValueError("provider has no configuration")
    if provider=="omalaunch.files":
        if not isinstance(value,dict) or value.get("version")!=1 or set(value)-{"version","includeGitIgnored"}: raise ValueError("invalid files configuration")
        include=value.get("includeGitIgnored",False)
        if not isinstance(include,bool): raise ValueError("includeGitIgnored must be boolean")
        return {"version":1,"includeGitIgnored":include}
    if provider=="omalaunch.quicklinks":
        if not isinstance(value,dict) or value.get("version")!=1 or set(value)-{"version","rankByUsage"}: raise ValueError("invalid Quicklinks configuration")
        track=value.get("rankByUsage",True)
        if not isinstance(track,bool): raise ValueError("rankByUsage must be boolean")
        return {"version":1,"rankByUsage":track}
    if not isinstance(value,dict) or value.get("version") not in (1,2) or set(value)-{"version","rankByUsage","engines"} or "engines" not in value: raise ValueError("invalid Web Search configuration")
    rank=value.get("rankByUsage",True)
    if not isinstance(rank,bool): raise ValueError("rankByUsage must be boolean")
    raw_engines=value["engines"]
    if value["version"]==1:
        if not isinstance(raw_engines,list) or not 1<=len(raw_engines)<=32: raise ValueError("invalid search engines")
        result=[]; seen=set()
        for engine in raw_engines:
            if not isinstance(engine,dict) or set(engine)!={"id","name","url"}: raise ValueError("invalid search engine fields")
            ident=engine.get("id"); name=engine.get("name"); url=engine.get("url")
            if not isinstance(ident,str) or not LINK_ID.fullmatch(ident) or ident in seen: raise ValueError("invalid or duplicate search engine id")
            if not isinstance(name,str) or not 1<=len(name)<=120 or CONTROL.search(name): raise ValueError("invalid search engine name")
            if not isinstance(url,str) or url.count("{query}")!=1 or not valid_url(url.replace("{query}","search")): raise ValueError("invalid search engine URL template")
            seen.add(ident); result.append({"id":ident,"name":name,"url":url})
    else:
        if not isinstance(raw_engines,dict) or len(raw_engines)>27: raise ValueError("invalid search engines")
        merged={engine["id"]:dict(engine) for engine in DEFAULT_SEARCH_ENGINES}
        for ident,changes in raw_engines.items():
            if not isinstance(ident,str) or not LINK_ID.fullmatch(ident) or not isinstance(changes,dict) or not changes or set(changes)-{"name","url","enabled"}: raise ValueError("invalid search engine override")
            if "enabled" in changes and not isinstance(changes["enabled"],bool): raise ValueError("search engine enabled must be boolean")
            if changes.get("enabled") is False:
                if ident not in merged or set(changes)!={"enabled"}: raise ValueError("only a bundled search engine can be disabled")
                del merged[ident]; continue
            current=merged.get(ident)
            if current is None and set(changes)-{"enabled"}!={"name","url"}: raise ValueError("new search engines require name and url")
            name=changes.get("name",current["name"] if current else None); url=changes.get("url",current["url"] if current else None)
            if not isinstance(name,str) or not 1<=len(name)<=120 or CONTROL.search(name): raise ValueError("invalid search engine name")
            if not isinstance(url,str) or url.count("{query}")!=1 or not valid_url(url.replace("{query}","search")): raise ValueError("invalid search engine URL template")
            merged[ident]={"id":ident,"name":name,"url":url}
        result=list(merged.values())
    if not 1<=len(result)<=32: raise ValueError("invalid search engines")
    return {"version":value["version"],"rankByUsage":rank,"engines":result}
def validate_state(provider:str,value:Any,home:Path)->dict[str,Any]:
    if provider not in PROVIDERS or not isinstance(value,dict) or value.get("version")!=1: raise ValueError("expected version-1 provider state")
    allowed={"version","links"} if provider=="omalaunch.quicklinks" else ({"version","globalSearchExcludedEngines","starredEngines"} if provider=="omalaunch.web-search" else {"version","favorites"})
    if set(value)-allowed: raise ValueError("unknown state fields")
    result=state_default(provider)
    if provider=="omalaunch.quicklinks":
        links=value.get("links")
        if not isinstance(links,list) or len(links)>MAX_ITEMS: raise ValueError("invalid links")
        seen=set()
        for raw in links:
            if not isinstance(raw,dict) or set(raw)-{"id","name","url","starred","openWith"}: raise ValueError("invalid link fields")
            ident=raw.get("id"); name=raw.get("name"); url=raw.get("url"); starred=raw.get("starred",False); ow=raw.get("openWith",{"type":"default"})
            if not isinstance(ident,str) or not LINK_ID.fullmatch(ident) or ident in seen: raise ValueError("invalid or duplicate link id")
            if not isinstance(name,str) or not 1<=len(name)<=120 or CONTROL.search(name): raise ValueError("invalid link name")
            if not valid_url(url) or not isinstance(starred,bool) or not isinstance(ow,dict): raise ValueError("invalid link")
            if ow.get("type")=="default" and set(ow)=={"type"}: pass
            elif ow.get("type")=="profile" and set(ow)=={"type","profile"} and isinstance(ow.get("profile"),str) and 1<=len(ow["profile"])<=120 and not CONTROL.search(ow["profile"]): pass
            else: raise ValueError("invalid openWith")
            seen.add(ident); result["links"].append({"id":ident,"name":name,"url":url,"starred":starred,"openWith":dict(ow)})
    elif provider=="omalaunch.web-search":
        entries=value.get("globalSearchExcludedEngines",[]); starred=value.get("starredEngines",[])
        for values,label in ((entries,"global search exclusions"),(starred,"starred search engines")):
            if not isinstance(values,list) or len(values)>32 or any(not identity(x,64) for x in values) or len(set(values))!=len(values): raise ValueError("invalid "+label)
        if set(entries)&set(starred): raise ValueError("starred search engines must be in global search")
        result["globalSearchExcludedEngines"]=list(entries); result["starredEngines"]=list(starred)
    elif provider=="omalaunch.files":
        entries=value.get("favorites",[])
        if not isinstance(entries,list) or len(entries)>MAX_ITEMS: raise ValueError("invalid file favorites")
        seen=set()
        for raw in entries:
            if not isinstance(raw,dict) or set(raw)!={"type","path"} or raw["type"] not in ("file","directory"): raise ValueError("invalid file favorite")
            path=normalize_path(raw["path"],home); key=(raw["type"],path)
            if key in seen: raise ValueError("duplicate file favorite")
            seen.add(key); result["favorites"].append({"type":raw["type"],"path":path})
    else:
        entries=value.get("favorites",[])
        if not isinstance(entries,list) or len(entries)>MAX_ITEMS or any(not identity(x) for x in entries) or len(set(entries))!=len(entries): raise ValueError("invalid favorites")
        result["favorites"]=list(entries)
    return result

def config_path(provider:str,home:Path)->Path: return home/".config/omarchy/omalaunch/extensions"/(provider+".jsonc")
def state_root(home:Path,state_home:Path|None=None)->Path:
    return (state_home or Path(os.environ.get("XDG_STATE_HOME",home/".local/state")))/"omarchy/omalaunch/extensions"
def state_path(provider:str,home:Path,state_home:Path|None=None)->Path: return state_root(home,state_home)/(provider+".json")
def editable_config_default(provider:str)->dict[str,Any]:
    if provider=="omalaunch.web-search": return {"version":2,"rankByUsage":True,"engines":{}}
    return config_default(provider)
def ensure_config(provider:str,home:Path)->Path:
    if provider not in CONFIG_PROVIDERS: raise ValueError("provider has no user configuration")
    path=config_path(provider,home)
    path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    os.chmod(path.parent,0o700)
    try:
        fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    except FileNotFoundError:
        value=editable_config_default(provider); validate_config(provider,value)
        data=(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+"\n").encode()
        if len(data)>MAX_BYTES: raise ValueError("result exceeds 64 KiB")
        try: fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        except FileExistsError: return ensure_config(provider,home)
        with os.fdopen(fd,"wb") as output:
            output.write(data); output.flush(); os.fsync(output.fileno())
        return path
    with os.fdopen(fd,"rb") as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode): raise ValueError("configuration must be a regular file")
        os.fchmod(source.fileno(),0o600)
    return path
def load_config(provider:str,home:Path)->dict[str,Any]:
    path=config_path(provider,home)
    return config_default(provider) if not path.exists() else validate_config(provider,read_json(path,jsonc=True))
def load_state(provider:str,home:Path,state_home:Path|None=None)->dict[str,Any]:
    path=state_path(provider,home,state_home)
    return state_default(provider) if not path.exists() else validate_state(provider,read_json(path,jsonc=False),home)
def load(provider:str,home:Path,state_home:Path|None=None)->dict[str,Any]:
    value=load_state(provider,home,state_home)
    if provider in CONFIG_PROVIDERS: value={**value,**load_config(provider,home)}
    return value

def atomic_write_state(provider:str,home:Path,value:dict[str,Any],state_home:Path|None=None)->None:
    path=state_path(provider,home,state_home); value=validate_state(provider,value,home); path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    data=(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+"\n").encode()
    if len(data)>MAX_BYTES: raise ValueError("result exceeds 64 KiB")
    fd,tmp=tempfile.mkstemp(prefix="."+path.name+".",dir=path.parent)
    try:
        os.fchmod(fd,0o600)
        with os.fdopen(fd,"wb") as f: f.write(data); f.flush(); os.fsync(f.fileno())
        os.replace(tmp,path)
        d=os.open(path.parent,os.O_RDONLY|getattr(os,"O_DIRECTORY",0)); os.fsync(d); os.close(d)
    finally:
        try: os.unlink(tmp)
        except FileNotFoundError: pass
def mutate(provider:str,home:Path,fn:Callable[[dict[str,Any]],None],state_home:Path|None=None)->dict[str,Any]:
    root=state_root(home,state_home); root.mkdir(parents=True,exist_ok=True,mode=0o700)
    lock_path=root/(provider+".lock"); lock=os.open(lock_path,os.O_RDWR|os.O_CREAT,0o600)
    try:
        fcntl.flock(lock,fcntl.LOCK_EX)
        value=load_state(provider,home,state_home) # Invalid state stops before write.
        fn(value); atomic_write_state(provider,home,value,state_home)
        return load_state(provider,home,state_home)
    finally: os.close(lock)

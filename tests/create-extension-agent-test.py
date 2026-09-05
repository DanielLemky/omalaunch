#!/usr/bin/env python3

import getpass
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "extensions/add/create-with-agent.py"


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"ok - {message}")


def executable(path: Path, content: str):
    path.write_text(content)
    path.chmod(0o755)


with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    home = base / "home"
    bin_dir = base / "bin"
    home.mkdir()
    bin_dir.mkdir()
    launch_record = base / "launch.json"
    executable(bin_dir / "omarchy-default-agent", "#!/bin/sh\nprintf 'pi\\n'\n")
    executable(bin_dir / "omarchy-agent", f'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
Path({str(launch_record)!r}).write_text(json.dumps({{"cwd": os.getcwd(), "args": sys.argv[1:]}}))
''')
    env = dict(os.environ, HOME=str(home), PATH=f"{bin_dir}:{os.environ['PATH']}")

    result = subprocess.run([str(SCRIPT), "My Useful Extension"], env=env, capture_output=True, text=True)
    plugin_id = f"{getpass.getuser()}.my-useful-extension"
    target = home / ".config/omarchy/plugins" / plugin_id
    for _ in range(50):
        if launch_record.exists():
            break
        time.sleep(0.02)
    record = json.loads(launch_record.read_text())
    check(result.returncode == 0 and target.is_dir(), "the default extension workspace is created")
    manifest = json.loads((target / "manifest.json").read_text())
    extension = json.loads((target / "omalaunch.json").read_text())
    check(manifest["id"] == plugin_id and manifest["omalaunch"]["extensions"] == ["omalaunch.json"]
          and extension["id"] == plugin_id and extension["capability"] == plugin_id,
          "the workspace contains a valid username-prefixed plugin scaffold")
    check((target / ".gitignore").is_file() and (target / "README.md").is_file()
          and (target / "AGENTS.md").is_file() and (target / "CLAUDE.md").is_file(),
          "the workspace contains starter repository and agent instruction files")
    agent_instructions = (target / "AGENTS.md").read_text()
    check("Omarchy watches this plugin directory" in agent_instructions
          and "atomic file replacement" in agent_instructions
          and "omarchy plugin disable" not in agent_instructions,
          "agent instructions describe the watched-directory development model accurately")
    check("ask whether the user wants to publish" in agent_instructions
          and "without explicit user approval" in agent_instructions
          and "Omalaunch Extension Directory as one publishing option" in agent_instructions
          and "ask before preparing a submission" in agent_instructions,
          "publication instructions require the user's explicit choice")
    check(record["cwd"] == str(target), "the default agent starts in the new workspace")
    check(record["args"][0] == "--prompt"
          and 'called "My Useful Extension"' in record["args"][1]
          and "Review the Omalaunch extension contract" in record["args"][1]
          and "Do not change files yet" in record["args"][1]
          and "I will then provide direction" in record["args"][1]
          and "Omarchy watches this directory" in record["args"][1]
          and "atomic file replacement" in record["args"][1]
          and "omarchy plugin validate ." in record["args"][1]
          and f"omarchy plugin enable {plugin_id}" in record["args"][1],
          "the agent receives the review-first handoff and exact safe reload commands")
    retry = subprocess.run([str(SCRIPT), "My Useful Extension"], env=env, capture_output=True, text=True)
    check(retry.returncode == 0, "an unchanged starter scaffold can retry its agent launch")
    check(not any(path.name.startswith(".omalaunch-create-") for path in target.parent.iterdir()),
          "atomic scaffold staging leaves no temporary plugin directory")

with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    home = base / "home"
    bin_dir = base / "bin"
    custom = base / "custom workspaces"
    (home / ".config/omarchy/omalaunch").mkdir(parents=True)
    bin_dir.mkdir()
    (home / ".config/omarchy/omalaunch/config.jsonc").write_text(
        '{\n// custom location\n"version": 1, "extensionDevelopmentDirectory": '
        + json.dumps(str(custom)) + ',\n}'
    )
    executable(bin_dir / "omarchy-default-agent", "#!/bin/sh\nprintf 'codex\\n'\n")
    executable(bin_dir / "omarchy-agent", "#!/bin/sh\nexit 0\n")
    env = dict(os.environ, HOME=str(home), PATH=f"{bin_dir}:{os.environ['PATH']}")
    result = subprocess.run([str(SCRIPT), "Custom"], env=env, capture_output=True, text=True)
    check(result.returncode == 0 and (custom / f"{getpass.getuser()}.custom").is_dir(),
          "the configured workspace location is used")

with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    home = base / "home"
    bin_dir = base / "bin"
    home.mkdir()
    bin_dir.mkdir()
    executable(bin_dir / "omarchy-default-agent", "#!/bin/sh\nexit 0\n")
    executable(bin_dir / "omarchy-agent", "#!/bin/sh\nexit 0\n")
    env = dict(os.environ, HOME=str(home), PATH=f"{bin_dir}:{os.environ['PATH']}")
    result = subprocess.run([str(SCRIPT), "No Agent"], env=env, capture_output=True, text=True)
    check(result.returncode != 0
          and (home / ".config/omarchy/plugins" / f"{getpass.getuser()}.no-agent").is_dir(),
          "the shared launcher reports an unset default agent after workspace preparation")

with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    bin_dir = base / "bin"
    workspace = base / "workspace"
    record = base / "agent.json"
    bin_dir.mkdir(); workspace.mkdir()
    executable(bin_dir / "omarchy-default-agent", "#!/bin/sh\nprintf 'pi\\n'\n")
    executable(bin_dir / "omarchy-agent", f'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
Path({str(record)!r}).write_text(json.dumps({{"cwd": os.getcwd(), "args": sys.argv[1:]}}))
''')
    env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
    result = subprocess.run([str(ROOT / "libexec/omalaunch-launch-agent"), "--dir", str(workspace)],
                            env=env, capture_output=True, text=True)
    started = json.loads(record.read_text())
    check(result.returncode == 0 and started == {"cwd": str(workspace), "args": []},
          "the shared launcher can start an agent without an initial prompt")

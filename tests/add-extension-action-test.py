#!/usr/bin/env python3

import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "extensions/add/add-extension-action.py"


def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print(f"ok - {message}")


def executable(path, content):
    path.write_text(content)
    path.chmod(0o755)


with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    bin_dir = base / "bin"
    bin_dir.mkdir()
    record = base / "record.json"
    executable(bin_dir / "xdg-open", f"#!/bin/sh\nprintf '%s' \"$1\" > {record}\n")
    env = dict(os.environ, PATH=str(bin_dir))
    result = subprocess.run(["/usr/bin/python", str(HELPER), "marketplace"], env=env, capture_output=True, text=True)
    check(result.returncode == 0 and record.read_text() == "https://daniellemky.github.io/omalaunch-extensions/",
          "marketplace checks and runs only its browser tool")
    missing = subprocess.run(["/usr/bin/python", str(HELPER), "git", "https://example.test/repo"], env=env,
                             capture_output=True, text=True)
    check(missing.returncode != 0 and "missing required tools: xdg-terminal-exec, omarchy" in missing.stderr,
          "Git selection reports its missing tools")

with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    bin_dir = base / "bin"
    bin_dir.mkdir()
    record = base / "args.json"
    executable(bin_dir / "omarchy", "#!/bin/sh\nexit 99\n")
    executable(bin_dir / "xdg-terminal-exec", f'''#!/usr/bin/python3
import json, sys
from pathlib import Path
Path({str(record)!r}).write_text(json.dumps(sys.argv[1:]))
''')
    repository = "https://example.test/repo;$(touch nope)"
    env = dict(os.environ, PATH=f"{bin_dir}:/usr/bin")
    result = subprocess.run(["/usr/bin/python", str(HELPER), "git", repository], env=env,
                            capture_output=True, text=True)
    check(result.returncode == 0 and json.loads(record.read_text()) ==
          ["--hold", "--", "omarchy", "plugin", "add", repository, "--enable"],
          "Git URL stays one literal argument and terminal install keeps interactive confirmation")
    empty = subprocess.run(["/usr/bin/python", str(HELPER), "git", ""], env=env,
                           capture_output=True, text=True)
    check(empty.returncode != 0 and "URL is required" in empty.stderr,
          "empty Git input cannot dispatch")

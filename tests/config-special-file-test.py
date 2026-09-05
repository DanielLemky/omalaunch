#!/usr/bin/env python3
"""Configuration actions must reject special files without blocking."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
for kind in ("fifo", "directory"):
    for provider in (None, "omalaunch.quicklinks", "omalaunch.web-search"):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            config = home / ".config/omarchy/omalaunch"
            path = config / "config.jsonc" if provider is None else config / "extensions" / (provider + ".jsonc")
            path.parent.mkdir(parents=True)
            if kind == "fifo":
                os.mkfifo(path)
            else:
                path.mkdir()
            command = [str(ROOT / "libexec/omalaunch-config"), "open-config"] if provider is None else [str(ROOT / "libexec/provider-config"), "open-config", provider]
            result = subprocess.run(command, env=dict(os.environ, HOME=str(home)), capture_output=True, text=True, timeout=3)
            assert result.returncode != 0, (kind, provider, result)
            assert ("regular file" in result.stderr if kind == "fifo" else "Is a directory" in result.stderr), result.stderr
print("Configuration special-file tests passed")

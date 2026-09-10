#!/usr/bin/env python3
"""Run one Add Extension action after checking only its own tools."""

from __future__ import annotations

import os
import shutil
import sys

MARKETPLACE = "https://daniellemky.github.io/omalaunch-extensions/"


def fail(message: str) -> None:
    print(f"Could not add extension: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(*commands: str) -> None:
    missing = [command for command in commands if shutil.which(command) is None]
    if missing:
        fail("missing required tool" + ("s" if len(missing) != 1 else "") + ": " + ", ".join(missing))


def main() -> int:
    if len(sys.argv) < 2:
        fail("an action is required")
    action = sys.argv[1]
    if action == "marketplace" and len(sys.argv) == 2:
        require("xdg-open")
        os.execvp("xdg-open", ["xdg-open", MARKETPLACE])
    if action == "git" and len(sys.argv) == 3:
        repository = sys.argv[2]
        if not repository.strip():
            fail("a Git repository URL is required")
        require("xdg-terminal-exec", "omarchy")
        os.execvp("xdg-terminal-exec", [
            "xdg-terminal-exec", "--hold", "--", "omarchy", "plugin", "add",
            repository, "--enable",
        ])
    fail("the action or its arguments are invalid")


if __name__ == "__main__":
    raise SystemExit(main())

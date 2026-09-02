#!/usr/bin/env python3
"""Build and query the temporary file index used by Omalaunch."""

from __future__ import annotations

import heapq
import json
import os
import signal
import subprocess
import sys
import tempfile
from collections.abc import Iterator
from pathlib import Path
from typing import BinaryIO

MAX_RESULTS = 100
_child: subprocess.Popen[bytes] | None = None


def _stop_child(_signum: int, _frame: object) -> None:
    if _child is not None and _child.poll() is None:
        _child.terminate()
    raise SystemExit(130)


signal.signal(signal.SIGTERM, _stop_child)
signal.signal(signal.SIGINT, _stop_child)


def _nul_records(stream: BinaryIO) -> Iterator[bytes]:
    pending = b""
    while True:
        chunk = stream.read(64 * 1024)
        if not chunk:
            break
        parts = (pending + chunk).split(b"\0")
        pending = parts.pop()
        yield from parts
    if pending:
        yield pending


def _entry(raw_path: bytes) -> dict[str, str] | None:
    path = os.fsdecode(raw_path).rstrip("/")
    if not path:
        return None
    return {
        "path": path,
        "name": os.path.basename(path),
        "type": "directory" if os.path.isdir(path) else "file",
    }


def _emit(raw_paths: Iterator[bytes], *, limit: int = MAX_RESULTS,
          excluded: set[bytes] | None = None) -> int:
    emitted = 0
    skipped = excluded or set()
    for raw_path in raw_paths:
        if raw_path.rstrip(b"/") in skipped:
            continue
        entry = _entry(raw_path)
        if entry is None:
            continue
        # ensure_ascii keeps arbitrary Linux filenames representable as one
        # UTF-8-safe JSON line, including names containing literal newlines.
        print(json.dumps(entry, ensure_ascii=True, separators=(",", ":")))
        emitted += 1
        if emitted >= limit:
            break
    return emitted


def _fd_command(
    root: str, *, max_depth: int | None = None, directories_only: bool = False,
    include_git_ignored: bool = False, include_hidden: bool = False,
) -> list[str]:
    command = [
        "fd",
        "--color",
        "never",
        "--absolute-path",
        "--print0",
        "--exclude",
        ".git",
    ]
    if include_git_ignored:
        command.append("--no-ignore-vcs")
    if include_hidden:
        command.append("--hidden")
    if not directories_only:
        command.extend(["--type", "file"])
    command.extend(["--type", "directory"])
    if max_depth is not None:
        command.extend(["--max-depth", str(max_depth)])
    command.extend(["--", ".", root])
    return command


def build_index(root: str, output_path: str, *, directories_only: bool = False,
                include_git_ignored: bool = False, include_hidden: bool = False) -> int:
    global _child

    output = Path(output_path)
    output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f"{output.name}.tmp-",
        dir=output.parent,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as destination:
            _child = subprocess.Popen(
                _fd_command(root, directories_only=directories_only, include_git_ignored=include_git_ignored,
                            include_hidden=include_hidden),
                stdout=destination,
                stderr=subprocess.DEVNULL,
            )
            exit_code = _child.wait()
        _child = None
        if exit_code != 0:
            return exit_code
        os.replace(temporary, output)
        return 0
    finally:
        _child = None
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def browse(root: str, *, directories_only: bool = False,
           include_git_ignored: bool = False, include_hidden: bool = False) -> int:
    global _child

    _child = subprocess.Popen(
        _fd_command(root, max_depth=1, directories_only=directories_only, include_git_ignored=include_git_ignored,
                    include_hidden=include_hidden),
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    assert _child.stdout is not None
    rows: list[tuple[float, bytes]] = []
    for raw_path in _nul_records(_child.stdout):
        try:
            modified_at = os.stat(raw_path.rstrip(b"/"), follow_symlinks=False).st_mtime
        except OSError:
            continue
        row = (modified_at, raw_path)
        if len(rows) < MAX_RESULTS:
            heapq.heappush(rows, row)
        elif row > rows[0]:
            heapq.heapreplace(rows, row)
    exit_code = _child.wait()
    _child = None
    if exit_code != 0:
        return exit_code
    rows.sort(reverse=True)
    _emit(iter(raw_path for _, raw_path in rows))
    return 0


def query(index_path: str, needle: str) -> int:
    global _child

    try:
        index = open(index_path, "rb")
    except OSError:
        return 2

    with index:
        # Exact basename matches must not be displaced by many descendants
        # whose parent path contains the query. Find only this small priority
        # set before asking fzf to rank all path matches.
        exact: list[bytes] = []
        exact_key = needle.casefold()
        for raw_path in _nul_records(index):
            name = os.path.basename(os.fsdecode(raw_path).rstrip("/"))
            if name.casefold() == exact_key:
                exact.append(raw_path)
                if len(exact) >= MAX_RESULTS:
                    break
        emitted = _emit(iter(exact))
        if emitted >= MAX_RESULTS:
            return 0

        index.seek(0)
        _child = subprocess.Popen(
            [
                "fzf",
                "--read0",
                "--print0",
                f"--filter={needle}",
                "--scheme=path",
                "--tiebreak=begin,length",
            ],
            stdin=index,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        assert _child.stdout is not None
        exact_paths = {raw_path.rstrip(b"/") for raw_path in exact}
        _emit(_nul_records(_child.stdout), limit=MAX_RESULTS - emitted, excluded=exact_paths)
        # fzf may still be writing matches after the display limit. Closing its
        # pipe lets it stop without forcing Python to materialize every match.
        _child.stdout.close()
        if _child.poll() is None:
            _child.terminate()
        exit_code = _child.wait()
    _child = None
    # fzf uses 1 for a valid query with no matches. Once the display limit is
    # reached it exits through either our SIGTERM or SIGPIPE from the closed
    # output pipe; both are successful query outcomes.
    return 0 if exit_code in (0, 1, -signal.SIGTERM, -signal.SIGPIPE) else exit_code


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: file-index.py <mode> [--hidden] [--include-git-ignored] -- <arguments>", file=sys.stderr)
        return 2

    mode = argv[1]
    if mode == "query" and len(argv) == 4:
        return query(argv[2], argv[3])

    arguments = argv[2:]
    if "--" in arguments:
        separator = arguments.index("--")
        options = arguments[:separator]
        values = arguments[separator + 1:]
    else:
        options = []
        values = arguments
    if any(option not in ("--include-git-ignored", "--hidden") for option in options):
        print(f"invalid option for {mode}", file=sys.stderr)
        return 2
    include_git_ignored = "--include-git-ignored" in options
    include_hidden = "--hidden" in options
    positional = argv[:2] + values
    if mode in ("index", "index-dirs") and len(positional) == 4:
        return build_index(positional[2], positional[3], directories_only=mode == "index-dirs",
                           include_git_ignored=include_git_ignored, include_hidden=include_hidden)
    if mode in ("browse", "browse-dirs") and len(positional) == 3:
        return browse(positional[2], directories_only=mode == "browse-dirs",
                      include_git_ignored=include_git_ignored, include_hidden=include_hidden)
    print(f"invalid arguments for {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

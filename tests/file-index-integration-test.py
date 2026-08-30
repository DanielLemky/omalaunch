#!/usr/bin/env python3

import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "extensions" / "files" / "file-index.py"


def run(*arguments: str) -> list[dict[str, str]]:
    result = subprocess.run(
        ["python", str(HELPER), *arguments],
        check=True,
        capture_output=True,
        text=True,
    )
    return [json.loads(line) for line in result.stdout.splitlines() if line]


with tempfile.TemporaryDirectory() as temporary:
    workspace = Path(temporary)
    files = workspace / "files"
    files.mkdir()
    alpha = files / "Alpha"
    beta = files / "Beta"
    alpha.mkdir()
    beta.mkdir()
    (alpha / "report final.txt").write_text("report", encoding="utf-8")
    (beta / "notes.txt").write_text("notes", encoding="utf-8")
    (files / ".hidden.txt").write_text("hidden", encoding="utf-8")
    strange = alpha / "strange\nname.txt"
    strange.write_text("newline", encoding="utf-8")
    os.utime(alpha, (100, 100))
    os.utime(beta, (200, 200))

    browsed = run("browse", str(files))
    assert [row["name"] for row in browsed[:2]] == ["Beta", "Alpha"]
    assert all(row["name"] != ".hidden.txt" for row in browsed)
    print("ok - browsing is modification-sorted and excludes hidden entries")

    index = workspace / "index.nul"
    run("index", str(files), str(index))
    assert index.stat().st_mode & 0o777 == 0o600
    reports = run("query", str(index), "report")
    assert [row["name"] for row in reports] == ["report final.txt"]
    print("ok - indexed queries use a private cache and return recursively ranked paths")

    unusual = run("query", str(index), "strange")
    assert unusual[0]["name"] == "strange\nname.txt"
    print("ok - indexed queries preserve filenames containing newlines")

    added_later = files / "added-after-index.txt"
    added_later.write_text("new", encoding="utf-8")
    assert run("query", str(index), "added-after-index") == []
    run("index", str(files), str(index))
    assert run("query", str(index), "added-after-index")[0]["path"] == str(added_later)
    print("ok - rebuilding refreshes the index snapshot")

    newest_base = time.time() + 1000
    for number in range(110):
        nested = beta / f"limit-match-{number:03}.txt"
        nested.write_text("", encoding="utf-8")
        direct = files / f"direct-{number:03}.txt"
        direct.write_text("", encoding="utf-8")
        os.utime(direct, (newest_base + number, newest_base + number))
    limited_browse = run("browse", str(files))
    assert len(limited_browse) == 100
    assert limited_browse[0]["name"] == "direct-109.txt"
    run("index", str(files), str(index))
    assert len(run("query", str(index), "limit-match")) == 100
    print("ok - browse and indexed query output are capped at 100 rows")

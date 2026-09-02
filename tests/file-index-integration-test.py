#!/usr/bin/env python3

import json
import os
import subprocess
import tempfile
import runpy
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "extensions" / "files" / "file-index.py"


def run(*arguments: str, cwd: Path | None = None) -> list[dict[str, str]]:
    result = subprocess.run(
        ["python", str(HELPER), *arguments],
        check=True,
        capture_output=True,
        text=True,
        cwd=cwd,
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
    hidden_directory = files / ".hidden-directory"
    hidden_directory.mkdir()
    hidden_child = hidden_directory / "nested.txt"
    hidden_child.write_text("nested", encoding="utf-8")
    strange = alpha / "strange\nname.txt"
    strange.write_text("newline", encoding="utf-8")
    os.utime(alpha, (100, 100))
    os.utime(beta, (200, 200))

    browsed = run("browse", str(files))
    assert [row["name"] for row in browsed[:2]] == ["Beta", "Alpha"]
    assert all(row["name"] != ".hidden.txt" for row in browsed)
    print("ok - browsing is modification-sorted and excludes hidden entries")

    hidden_browse = run("browse", "--hidden", "--", str(files))
    assert any(row["name"] == ".hidden.txt" for row in hidden_browse)
    assert any(row["path"] == str(hidden_directory) for row in hidden_browse)
    hidden_index = workspace / "hidden-index.nul"
    run("index", "--hidden", "--", str(files), str(hidden_index))
    assert run("query", str(hidden_index), ".hidden.txt")[0]["path"] == str(files / ".hidden.txt")
    assert run("query", str(hidden_index), "nested.txt")[0]["path"] == str(hidden_child)
    print("ok - hidden browsing and indexing include hidden directories only with the hidden option")

    option_root = workspace / "--root"
    option_root.mkdir()
    (option_root / "option-path.txt").write_text("path", encoding="utf-8")
    assert run("browse", "--", "--root", cwd=workspace)[0]["name"] == "option-path.txt"
    print("ok - the helper and fd preserve option-like root paths")

    directory_browse = run("browse-dirs", str(files))
    assert [row["name"] for row in directory_browse] == ["Beta", "Alpha"]
    assert all(row["type"] == "directory" for row in directory_browse)
    directory_index = workspace / "directory-index.nul"
    run("index-dirs", str(files), str(directory_index))
    assert run("query", str(directory_index), "Alpha")[0]["path"] == str(alpha)
    assert run("query", str(directory_index), "report") == []
    print("ok - the host directory-picker modes reuse browsing and search without files")

    index = workspace / "index.nul"
    run("index", str(files), str(index))
    assert index.stat().st_mode & 0o777 == 0o600
    reports = run("query", str(index), "report")
    assert [row["name"] for row in reports] == ["report final.txt"]
    print("ok - indexed queries use a private cache and return recursively ranked paths")

    unusual = run("query", str(index), "strange")
    assert unusual[0]["name"] == "strange\nname.txt"
    assert run("query", str(index), "--") == []
    print("ok - indexed queries preserve filenames containing newlines and option-like text")

    subprocess.run(["git", "init", "-q", str(files)], check=True)
    hidden_git_index = workspace / "hidden-git-index.nul"
    run("index", "--hidden", "--", str(files), str(hidden_git_index))
    assert run("query", str(hidden_git_index), "HEAD") == []
    assert all(row["name"] != ".git" for row in run("browse", "--hidden", "--", str(files)))
    print("ok - hidden mode excludes Git repository internals")

    (files / ".gitignore").write_text("git-ignored.txt\n", encoding="utf-8")
    ignored = files / "git-ignored.txt"
    ignored.write_text("ignored", encoding="utf-8")
    run("index", str(files), str(index))
    assert run("query", str(index), "git-ignored") == []
    run("index", "--include-git-ignored", "--", str(files), str(index))
    assert run("query", str(index), "git-ignored")[0]["path"] == str(ignored)
    assert all(row["name"] != "git-ignored.txt" for row in run("browse", str(files)))
    assert any(row["name"] == "git-ignored.txt" for row in run("browse", "--include-git-ignored", "--", str(files)))
    combined = run("browse", "--hidden", "--include-git-ignored", "--", str(files))
    assert any(row["name"] == ".hidden.txt" for row in combined)
    assert any(row["name"] == "git-ignored.txt" for row in combined)
    print("ok - includeGitIgnored combines with hidden browsing without changing default rules")

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

    first_exact = files / "first" / "local-spotlights"
    second_exact = files / "second" / "local-spotlights"
    first_exact.mkdir(parents=True)
    second_exact.mkdir(parents=True)
    for number in range(110):
        (first_exact / f"descendant-{number:03}.txt").write_text("", encoding="utf-8")
    run("index", str(files), str(index))
    exact_ranked = run("query", str(index), "local-spotlights")
    assert {row["path"] for row in exact_ranked[:2]} == {str(first_exact), str(second_exact)}
    assert len(exact_ranked) == 100
    print("ok - exact basename matches rank before descendants and remain within the result limit")

# Configuration uses one explicit helper flag for both fd traversal modes.
module = runpy.run_path(str(HELPER))
assert "--no-ignore-vcs" in module["_fd_command"]("/tmp", include_git_ignored=True)
print("ok - includeGitIgnored adds fd --no-ignore-vcs")
assert "--no-ignore-vcs" not in module["_fd_command"]("/tmp")
print("ok - Git-ignored paths remain excluded by default")

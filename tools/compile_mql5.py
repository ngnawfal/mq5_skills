#!/usr/bin/env python3
"""Compile every MQL5 template with MetaEditor and fail on any error or warning.

Windows only (MetaEditor is a Windows program). Nothing is written into the
terminal's data folder: the standard Include tree is copied into a temporary
MQL5 tree together with the SkillKit includes, and MetaEditor compiles there.

Usage:
    python tools/compile_mql5.py                      # auto-detect MetaEditor and terminal
    python tools/compile_mql5.py --metaeditor "C:/Program Files/MetaTrader 5/MetaEditor64.exe"
    python tools/compile_mql5.py --include "C:/Users/me/AppData/Roaming/MetaQuotes/Terminal/<id>/MQL5/Include"
    python tools/compile_mql5.py path/to/MyEA.mq5     # compile your own files with the same rules
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / "mql5-ea-expert" / "templates"
RESULT_RE = re.compile(r"Result:\s*(\d+)\s+errors?,\s*(\d+)\s+warnings?", re.I)
ISSUE_RE = re.compile(r":\s*(error|warning)\s+\d+:", re.I)


def find_metaeditor(explicit: str | None) -> Path:
    candidates = [explicit, os.environ.get("METAEDITOR")]
    for base in (os.environ.get("ProgramFiles", r"C:\Program Files"), os.environ.get("ProgramFiles(x86)", "")):
        if base and Path(base).exists():
            candidates += [str(p) for p in Path(base).glob("*/MetaEditor64.exe")]
    for c in candidates:
        if c and Path(c).is_file():
            return Path(c)
    sys.exit("FAIL: MetaEditor64.exe not found (use --metaeditor or METAEDITOR env var)")


def find_include(explicit: str | None, metaeditor: Path) -> Path:
    if explicit:
        p = Path(explicit)
        if (p / "Trade" / "Trade.mqh").is_file():
            return p
        sys.exit(f"FAIL: {p} does not contain Trade/Trade.mqh")
    # portable install keeps MQL5 next to the executable
    portable = metaeditor.parent / "MQL5" / "Include"
    if (portable / "Trade" / "Trade.mqh").is_file():
        return portable
    terminals = Path(os.environ.get("APPDATA", "")) / "MetaQuotes" / "Terminal"
    fallback = None
    for origin in terminals.glob("*/origin.txt"):
        inc = origin.parent / "MQL5" / "Include"
        if not (inc / "Trade" / "Trade.mqh").is_file():
            continue
        text = origin.read_bytes().decode("utf-16", errors="ignore") or origin.read_text(errors="ignore")
        if str(metaeditor.parent).lower() in text.lower():
            return inc
        fallback = fallback or inc
    if fallback:
        return fallback
    sys.exit("FAIL: no MQL5/Include with Trade/Trade.mqh found (use --include)")


def compile_one(metaeditor: Path, src: Path, mql5_root: Path) -> tuple[int, int, list[str]]:
    log = src.with_suffix(".log")
    subprocess.run([str(metaeditor), f"/compile:{src}", f"/log:{log}", f"/inc:{mql5_root}"],
                   capture_output=True, timeout=300)
    if not log.exists():
        return 1, 0, ["MetaEditor produced no log"]
    raw = log.read_bytes()
    text = raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("utf-8", errors="ignore")
    m = RESULT_RE.search(text)
    issues = [line.strip() for line in text.splitlines() if ISSUE_RE.search(line)]
    if not m:
        return 1, 0, issues or ["no 'Result:' line in log"]
    return int(m.group(1)), int(m.group(2)), issues


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="extra .mq5 files to compile (default: all templates)")
    ap.add_argument("--metaeditor")
    ap.add_argument("--include", help="MQL5/Include folder of a terminal")
    ap.add_argument("--keep", action="store_true", help="keep the temporary build tree")
    args = ap.parse_args()
    if os.name != "nt":
        print("SKIP: MetaEditor compilation requires Windows")
        return 0

    metaeditor = find_metaeditor(args.metaeditor)
    include = find_include(args.include, metaeditor)
    work = Path(tempfile.mkdtemp(prefix="mq5skill_"))
    mql5 = work / "MQL5"
    shutil.copytree(include, mql5 / "Include")
    if (TEMPLATES / "Include").exists():
        shutil.copytree(TEMPLATES / "Include", mql5 / "Include", dirs_exist_ok=True)

    sources: list[tuple[Path, Path]] = []
    for kind in ("Experts", "Indicators", "Scripts"):
        for f in sorted((TEMPLATES / kind).glob("*.mq5")):
            sources.append((f, mql5 / kind / f.name))
    for extra in args.files:
        f = Path(extra).resolve()
        sources.append((f, mql5 / "Experts" / f.name))

    print(f"MetaEditor: {metaeditor}\nInclude:    {include}\n")
    failed = 0
    for original, target in sources:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, target)
        errors, warnings, issues = compile_one(metaeditor, target, mql5)
        ok = errors == 0 and warnings == 0
        failed += not ok
        rel = original.relative_to(ROOT) if original.is_relative_to(ROOT) else original
        print(f"{'OK  ' if ok else 'FAIL'} {rel}: {errors} errors, {warnings} warnings")
        for line in issues:
            print(f"     {line.replace(str(mql5), 'MQL5')}")

    if args.keep:
        print(f"\nBuild tree kept at {work}")
    else:
        shutil.rmtree(work, ignore_errors=True)
    if failed:
        print(f"\nFAIL: {failed} file(s) with errors or warnings")
        return 1
    print(f"\nOK: {len(sources)} file(s) compiled with 0 errors, 0 warnings")
    return 0


if __name__ == "__main__":
    sys.exit(main())

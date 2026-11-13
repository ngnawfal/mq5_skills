#!/usr/bin/env python3
"""Compile an EA, run it in the local MetaTrader 5 Strategy Tester, and summarise the result.

Windows only. MetaTrader 5 must be installed, logged in to the broker whose
history you want, and NOT running (the tester config is ignored by a running
terminal). The EA is copied to <data>/MQL5/Experts/SkillKitTester/ for the run
and removed afterwards; the report and the EA's log lines are saved to --out.

Example:
    python tools/run_mt5_tester.py mql5-ea-expert/templates/Experts/SkillKit_StructureBreakout.mq5 ^
        --symbol XAUUSD --period M15 --from 2025.01.01 --to 2026.01.01 --model 4 ^
        --deposit 1000 --set InpRiskMoney=14 --set InpDailyLimit=25

Models: 0 every tick (generated), 1 1-minute OHLC, 2 open prices, 4 every tick based on real ticks.
Use --model 4 for any verdict; 1 is for smoke tests only.
"""

from __future__ import annotations

import argparse
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import compile_mql5 as cm  # noqa: E402

PERIODS = {"M1", "M2", "M3", "M4", "M5", "M6", "M10", "M12", "M15", "M20", "M30",
           "H1", "H2", "H3", "H4", "H6", "H8", "H12", "D1", "W1", "MN1"}
SUMMARY_KEYS = ["Total Net Profit", "Gross Profit", "Gross Loss", "Profit Factor", "Expected Payoff",
                "Recovery Factor", "Sharpe Ratio", "Balance Drawdown Maximal", "Equity Drawdown Maximal",
                "Total Trades", "Profit Trades (% of total)", "Loss Trades (% of total)",
                "Largest loss trade", "Maximum consecutive losses ($)", "History Quality", "Bars", "Ticks"]


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16")
    return raw.decode("utf-8", errors="ignore")


def data_dir_for(metaeditor: Path, explicit: str | None) -> Path:
    if explicit:
        return Path(explicit)
    inc = cm.find_include(None, metaeditor)
    return inc.parent.parent  # .../Terminal/<id>/MQL5/Include -> .../Terminal/<id>


def terminal_running() -> bool:
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq terminal64.exe"], capture_output=True, text=True)
    return "terminal64.exe" in out.stdout.lower()


def parse_report(text: str) -> tuple[dict[str, str], list[list[str]]]:
    cells_re = re.compile(r"<td[^>]*>(.*?)</td>", re.S | re.I)
    summary: dict[str, str] = {}
    deals: list[list[str]] = []
    for row in re.findall(r"<tr[^>]*>(.*?)</tr>", text, re.S | re.I):
        cells = [html.unescape(re.sub(r"<[^>]+>", "", c)).strip() for c in cells_re.findall(row)]
        cells = [c for c in cells if c != ""]
        for i, c in enumerate(cells[:-1]):
            key = c.rstrip(":")
            if key in SUMMARY_KEYS and key not in summary:
                summary[key] = cells[i + 1]
        if len(cells) >= 11 and re.match(r"\d{4}\.\d\d\.\d\d \d\d:\d\d", cells[0]) and cells[4] in ("in", "out", "in/out"):
            deals.append(cells)
    return summary, deals


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ea", help=".mq5 file")
    ap.add_argument("--symbol", required=True)
    ap.add_argument("--period", default="M15")
    ap.add_argument("--from", dest="date_from", required=True, help="YYYY.MM.DD")
    ap.add_argument("--to", dest="date_to", required=True, help="YYYY.MM.DD")
    ap.add_argument("--model", type=int, default=4, choices=[0, 1, 2, 4])
    ap.add_argument("--deposit", type=float, default=10000)
    ap.add_argument("--currency", default="USD")
    ap.add_argument("--leverage", default="1:100")
    ap.add_argument("--delay-ms", type=int, default=0, help="execution delay; >0 adds latency (ExecutionMode)")
    ap.add_argument("--set", action="append", default=[], help="input override NAME=VALUE (repeatable)")
    ap.add_argument("--metaeditor")
    ap.add_argument("--terminal", help="terminal64.exe (default: next to MetaEditor)")
    ap.add_argument("--data-dir", help="terminal data folder (default: auto)")
    ap.add_argument("--out", default="tester_runs", help="folder for report + EA log")
    ap.add_argument("--timeout", type=int, default=3600)
    args = ap.parse_args()

    if os.name != "nt":
        sys.exit("FAIL: the MetaTrader 5 tester requires Windows")
    if args.period.upper() not in PERIODS:
        sys.exit(f"FAIL: unknown period {args.period}")
    if terminal_running():
        sys.exit("FAIL: terminal64.exe is running; close MetaTrader 5 first (a running terminal ignores /config)")

    ea = Path(args.ea).resolve()
    metaeditor = cm.find_metaeditor(args.metaeditor)
    terminal = Path(args.terminal) if args.terminal else metaeditor.parent / "terminal64.exe"
    data = data_dir_for(metaeditor, args.data_dir)
    include = data / "MQL5" / "Include"

    # 1. compile in an isolated tree (templates' SkillKit includes available)
    work = Path(tempfile.mkdtemp(prefix="mq5tester_"))
    mql5 = work / "MQL5"
    shutil.copytree(include, mql5 / "Include")
    if (cm.TEMPLATES / "Include").exists():
        shutil.copytree(cm.TEMPLATES / "Include", mql5 / "Include", dirs_exist_ok=True)
    (mql5 / "Experts").mkdir(parents=True)
    src = mql5 / "Experts" / ea.name
    shutil.copy2(ea, src)
    errors, warnings, issues = cm.compile_one(metaeditor, src, mql5)
    if errors or warnings:
        print("\n".join(issues))
        sys.exit(f"FAIL: compile {errors} errors, {warnings} warnings")

    # 2. install the .ex5 for the run
    dest_dir = data / "MQL5" / "Experts" / "SkillKitTester"
    dest_dir.mkdir(parents=True, exist_ok=True)
    ex5 = dest_dir / (ea.stem + ".ex5")
    shutil.copy2(src.with_suffix(".ex5"), ex5)
    report_name = f"SkillKitTester_{ea.stem}"
    inputs = "\n".join(args.set)
    ini = work / "tester.ini"
    ini.write_text(
        "[Tester]\n"
        f"Expert=SkillKitTester\\{ea.stem}.ex5\nSymbol={args.symbol}\nPeriod={args.period.upper()}\n"
        f"Model={args.model}\nExecutionMode={args.delay_ms}\nOptimization=0\n"
        f"FromDate={args.date_from}\nToDate={args.date_to}\nDeposit={args.deposit:g}\n"
        f"Currency={args.currency}\nLeverage={args.leverage}\nReport={report_name}\nReplaceReport=1\n"
        "ShutdownTerminal=1\nVisual=0\n"
        f"[TesterInputs]\n{inputs}\n", encoding="utf-16")

    # 3. run
    started = time.time()
    try:
        subprocess.run([str(terminal), f"/config:{ini}"], timeout=args.timeout)
    finally:
        ex5.unlink(missing_ok=True)
        try:
            dest_dir.rmdir()
        except OSError:
            pass
    elapsed = time.time() - started

    # 4. collect report and the EA's own log lines from the newest agent log
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    report = next((p for p in (data / f"{report_name}.htm", terminal.parent / f"{report_name}.htm") if p.exists()), None)
    if report is None or report.stat().st_mtime < started - 5:
        sys.exit(f"FAIL: no fresh report after {elapsed:.0f}s (history missing, wrong symbol, or terminal not logged in)")
    for f in report.parent.glob(f"{report_name}*"):
        shutil.move(str(f), out / f.name)
    summary, deals = parse_report(read_text(out / report.name))

    agent_logs = sorted((Path(os.environ["APPDATA"]) / "MetaQuotes" / "Tester").glob(f"{data.name}/Agent-*/logs/*.log"),
                        key=lambda p: p.stat().st_mtime)
    ea_lines: list[str] = []
    run_start = time.strftime("%H:%M:%S", time.localtime(started - 1))
    if agent_logs:
        for line in read_text(agent_logs[-1]).splitlines():
            fields = line.split("\t")
            if len(fields) < 5 or fields[2][:8] < run_start:   # the agent log is per day: skip earlier runs
                continue
            if ea.stem in line or "failed" in line.lower():
                ea_lines.append(line)
    (out / f"{report_name}_ealog.txt").write_text("\n".join(ea_lines), encoding="utf-8")

    tags: dict[str, int] = {}
    for line in ea_lines:
        for tag in re.findall(r"\[([A-Z]+)\]", line):
            tags[tag] = tags.get(tag, 0) + 1
    failures = [l for l in ea_lines if "failed" in l.lower()]

    print(f"Tester run: {args.symbol} {args.period} {args.date_from}-{args.date_to} model {args.model} ({elapsed:.0f}s)")
    for k in SUMMARY_KEYS:
        if k in summary:
            print(f"  {k}: {summary[k]}")
    outs = [d for d in deals if d[4] == "out"]
    print(f"  deals: {len(deals)} (exits: {len(outs)})")
    print(f"  EA log tags: {tags}")
    print(f"  failed operations: {len(failures)}")
    for l in failures[:5]:
        print("   ", l.split("\t")[-1][:160])
    print(f"Saved: {out}")
    shutil.rmtree(work, ignore_errors=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Repository validator for mq5_skills (runs anywhere; no MetaTrader needed).

Checks: required files, SKILL.md frontmatter and size, every reference/template the skill
mentions exists and every reference file is mentioned, evals.json schema, README links,
and forbidden patterns in the MQL5 templates. Compilation itself is tools/compile_mql5.py
(Windows + MetaEditor).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILL_DIR = ROOT / "mql5-ea-expert"
SKILL = SKILL_DIR / "SKILL.md"

REQUIRED_PATHS = [
    "mql5-ea-expert/SKILL.md",
    "mql5-ea-expert/references/critical-thinking.md",
    "mql5-ea-expert/references/risk-and-prop-firms.md",
    "mql5-ea-expert/references/backtesting-validation.md",
    "mql5-ea-expert/references/time-and-sessions.md",
    "mql5-ea-expert/references/mql5-patterns.md",
    "mql5-ea-expert/references/strategy-frameworks.md",
    "mql5-ea-expert/references/indicators-and-ui.md",
    "mql5-ea-expert/references/pitfalls.md",
    "mql5-ea-expert/references/grid-martingale.md",
    "mql5-ea-expert/references/ctrader-porting.md",
    "mql5-ea-expert/references/case-studies.md",
    "mql5-ea-expert/references/ea-blueprint.md",
    "mql5-ea-expert/references/example-prompts.md",
    "mql5-ea-expert/templates/Include/SkillKit/SkillKit_Time.mqh",
    "mql5-ea-expert/templates/Include/SkillKit/SkillKit_Risk.mqh",
    "mql5-ea-expert/templates/Include/SkillKit/SkillKit_Trade.mqh",
    "mql5-ea-expert/templates/Include/SkillKit/SkillKit_Structure.mqh",
    "mql5-ea-expert/templates/Experts/SkillKit_StructureBreakout.mq5",
    "mql5-ea-expert/templates/Experts/SkillKit_ServerTimeProbe.mq5",
    "mql5-ea-expert/templates/Indicators/SkillKit_Swings.mq5",
    "README.md", "CHANGELOG.md", "CONTRIBUTING.md", "LICENSE", "evals.json",
    "docs/AI_SETUP_GUIDE.md", "docs/ROADMAP.md",
    "tools/validate_repo.py", "tools/compile_mql5.py", "tools/run_mt5_tester.py", "tools/edge_check.py",
]

# patterns that must never appear in shipped MQL5 code (reason in the message)
FORBIDDEN_IN_MQL5 = {
    r"#property\s+strict": "#property strict is MQL4-only",
    r"POSITION_COMMISSION": "POSITION_COMMISSION is deprecated; use DEAL_COMMISSION",
    r"\.Commission\(\)": "position commission accessor is deprecated",
    r"PositionClose\(\s*_Symbol": "close by ticket, not by symbol",
    r"MathMax\(\s*min[A-Za-z]*\s*,": "clamping volume up to the minimum multiplies risk",
}

SKILL_MAX_LINES = 500


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def check_required_paths() -> None:
    missing = [p for p in REQUIRED_PATHS if not (ROOT / p).exists()]
    if missing:
        fail("missing required paths: " + ", ".join(missing))


def frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---"):
        fail("SKILL.md has no frontmatter")
    end = text.find("\n---", 3)
    if end == -1:
        fail("SKILL.md frontmatter not closed")
    fields: dict[str, str] = {}
    for line in text[3:end].strip().splitlines():
        if ":" in line and not line.startswith(" "):
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()
    return fields


def check_skill() -> None:
    text = SKILL.read_text(encoding="utf-8")
    fm = frontmatter(text)
    for key in ("name", "version", "description", "license", "tags"):
        if not fm.get(key):
            fail(f"SKILL.md frontmatter missing '{key}'")
    if fm["name"] != SKILL_DIR.name:
        fail(f"frontmatter name '{fm['name']}' must equal the folder name '{SKILL_DIR.name}'")
    if not re.fullmatch(r"\d+\.\d+\.\d+", fm["version"]):
        fail("version must be semantic (x.y.z)")
    if len(fm["description"]) > 1024:
        fail("description longer than 1024 characters")
    lines = text.count("\n") + 1
    if lines > SKILL_MAX_LINES:
        fail(f"SKILL.md has {lines} lines (> {SKILL_MAX_LINES}); move detail into references/")
    # every referenced file exists, every reference file is referenced
    mentioned = set(re.findall(r"`((?:references|templates)/[^`\s]+)`", text))
    for rel in mentioned:
        if not (SKILL_DIR / rel.rstrip("/")).exists():
            fail(f"SKILL.md mentions missing path {rel}")
    for ref in (SKILL_DIR / "references").glob("*.md"):
        if f"references/{ref.name}" not in mentioned:
            fail(f"references/{ref.name} is not listed in SKILL.md")
    version = fm["version"]
    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    if f"[{version}]" not in changelog:
        fail(f"CHANGELOG.md has no entry for {version}")
    evals = json.loads((ROOT / "evals.json").read_text(encoding="utf-8"))
    if evals.get("version") != version:
        fail(f"evals.json version {evals.get('version')} != SKILL.md version {version}")


def check_evals() -> None:
    data = json.loads((ROOT / "evals.json").read_text(encoding="utf-8"))
    evals = data.get("evals")
    if not isinstance(evals, list) or not evals:
        fail("evals.json must contain a non-empty 'evals' list")
    ids = [e.get("id") for e in evals]
    if len(ids) != len(set(ids)):
        fail("evals.json contains duplicate ids")
    for e in evals:
        exp = e.get("expectations", {})
        if not e.get("prompt") or not isinstance(exp.get("must"), list) or not exp["must"]:
            fail(f"eval '{e.get('id')}' needs a prompt and a non-empty expectations.must list")
        if e.get("category") not in {"code", "review", "analysis", "adversarial"}:
            fail(f"eval '{e.get('id')}' has an unknown category")


def check_readme_links() -> None:
    text = (ROOT / "README.md").read_text(encoding="utf-8")
    for link in re.findall(r"\[[^\]]+\]\(([^)]+)\)", text):
        if link.startswith(("http://", "https://", "../../", "#", "mailto:")):
            continue
        if not (ROOT / link.split("#", 1)[0]).exists():
            fail(f"README link target missing: {link}")


def check_mql5_sources() -> None:
    files = list((SKILL_DIR / "templates").rglob("*.mq5")) + list((SKILL_DIR / "templates").rglob("*.mqh"))
    if not files:
        fail("no MQL5 templates found")
    for f in files:
        code = f.read_text(encoding="utf-8")
        for pattern, why in FORBIDDEN_IN_MQL5.items():
            if re.search(pattern, code):
                fail(f"{f.relative_to(ROOT)}: forbidden pattern '{pattern}' ({why})")
        if f.suffix == ".mqh" and "#ifndef" not in code:
            fail(f"{f.relative_to(ROOT)}: include file needs an include guard")


def main() -> int:
    check_required_paths()
    check_skill()
    check_evals()
    check_readme_links()
    check_mql5_sources()
    print("OK: repository structure valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())

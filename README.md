# MQL5 EA Expert - evidence-first AI skill for MetaTrader 5

> **Version 3.0.0** | An AI skill for building MetaTrader 5 Expert Advisors that are verified,
> and for judging strategies with critical thinking instead of hope.

[![validate](https://github.com/nawfdev/mq5_skills/actions/workflows/validate.yml/badge.svg)](https://github.com/nawfdev/mq5_skills/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## What it does

The skill teaches Claude, ChatGPT, Gemini and other assistants to:

- **Write MQL5 that survives contact with a real account**: exact money-at-risk sizing, trades
  skipped (never clamped up) when the minimum volume is too big, prop-firm limits measured the way
  firms measure them, restart-safe state, broker-constraint checks, measured server time.
- **Verify instead of claim**: compile with MetaEditor (0 errors, 0 warnings), run the Strategy
  Tester, read the EA log for failed operations.
- **Think critically about strategies**: default assumption "no edge", feasibility math for
  targets ("pass in 2 weeks"), sample-size requirements, time-block stability, null baselines,
  multiple-testing awareness, honest reporting with provenance on every number.

Everything in it comes from real failures documented in
[`references/case-studies.md`](mql5-ea-expert/references/case-studies.md): a $14 risk that became
a -$92 loss through volume clamping, a server DST assumption that trapped a position, a stop that
filled -$24 at payrolls, an 18-month "edge" that was zero over 5 years.

## Install

```bash
npx skills add nawfdev/mq5_skills          # skills CLI (Claude Code and compatible agents)
```

Or copy the `mql5-ea-expert/` folder into your agent's skills directory. For chat apps see
[docs/AI_SETUP_GUIDE.md](docs/AI_SETUP_GUIDE.md).

## Repository layout

```text
mql5-ea-expert/
  SKILL.md                         core rules, workflow, red flags, reference map
  references/
    critical-thinking.md           edge hypotheses, feasibility math, sample size, gates, honest reports
    risk-and-prop-firms.md         sizing, daily/total/floating limits, buffers, minimum volume
    backtesting-validation.md      tester settings, protocol, OnTester, parity checks
    time-and-sessions.md           server time, US vs EU DST, NY anchoring, holidays
    mql5-patterns.md               canonical code, retcodes, persistence, history
    strategy-frameworks.md         A-B-C structure, ORB, sweep/MSS, SMC/ICT/CRT as testable rules
    indicators-and-ui.md           OnCalculate indexing, objects, dashboard, CSV
    pitfalls.md                    wrong vs right with the reason
    grid-martingale.md             risk-of-ruin math and hard caps
    ctrader-porting.md             cAlgo mapping, ctrader-cli traps, Linux deployment
    case-studies.md                real numbers behind the rules
    ea-blueprint.md                generated EA layout and verification steps
    example-prompts.md             ready prompts, including adversarial ones
  templates/                       compile-verified MQL5 (SkillKit)
    Include/SkillKit/*.mqh         Time, Risk + prop guard, Trade, Structure
    Experts/SkillKit_StructureBreakout.mq5   reference EA (example logic, no edge claimed)
    Experts/SkillKit_ServerTimeProbe.mq5     measures broker GMT offset / DST / early closes
    Indicators/SkillKit_Swings.mq5           confirmed swings, correct indexing
tools/
  compile_mql5.py                  MetaEditor compile of templates or your files; fails on warnings
  run_mt5_tester.py                compile + Strategy Tester run + report and EA-log summary
  edge_check.py                    expectancy with uncertainty, stability, challenge odds vs no-edge control
  validate_repo.py, test_tools.py  CI checks
evals.json                         17 behavioural test cases
```

## Tools (Windows + MetaTrader 5 for the first two)

```bash
python tools/compile_mql5.py                                  # all templates -> 0 errors, 0 warnings
python tools/compile_mql5.py MyEA.mq5                         # your file, same rules

python tools/run_mt5_tester.py MyEA.mq5 --symbol XAUUSD --period M15 \
    --from 2025.01.01 --to 2026.01.01 --model 4 --deposit 1000 --set InpRiskMoney=14

python tools/edge_check.py tester_runs/SkillKitTester_MyEA.htm --risk 14 --blocks 3 \
    --target 80 --daily-limit 30 --max-loss 60 --days 10 --fund-target 45
```

`edge_check.py` output (reference EA, XM GOLDm#, 2026-05..11, real ticks):

```text
expectancy 2.41 per trade, SE 1.66, t = 1.45, p ~ 0.146
95% interval of expectancy: [-0.84, 5.66]   <- includes zero: no evidence of an edge
in R: expectancy +0.172R (SE 0.119R), worst -1.72R
WARNING: 2 trade(s) lost more than 1.05R (worst -1.72R): slippage/gaps, the stop is not a hard cap
                          pass   breach   median days   payout
this strategy             7.6%     4.1%             8     0.2%
no-edge control           3.2%     9.3%             9     0.0%
```

## Try it

```text
Using the mql5-ea-expert skill: I want to pass a $1,000 challenge (target $80, daily limit $30,
max loss $60) and get a payout within 2 weeks, risking $14 per trade. Do the math first.
```

A correct answer computes the R needed (~9R in ~10 trades), gives a probability, and offers
options - it does not promise a pass. More in
[`example-prompts.md`](mql5-ea-expert/references/example-prompts.md).

## Validation

```bash
python tools/validate_repo.py                                 # structure, frontmatter, evals, template lint
python -m unittest discover -s tools -p "test_*.py"           # statistics tools
python tools/compile_mql5.py                                  # Windows + MetaEditor
```

## Philosophy

- The best EA is the one that survives; the best answer is the one that is true.
- A strategy has no edge until a test with real costs, enough trades and unseen data says so.
- Account rules are hard constraints; the stop loss is not a cap.
- Measure the broker (time zone, sessions, minimum volume, spread) instead of assuming it.

## Disclaimer

Educational software. Trading leveraged products carries a high risk of loss. Nothing here is
financial advice, and no result is a promise of future performance. See [LICENSE](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/ROADMAP.md](docs/ROADMAP.md). History in
[CHANGELOG.md](CHANGELOG.md).

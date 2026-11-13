# Roadmap

## Completed in v3.0.0

- Compile-verified SkillKit templates and a MetaEditor compile checker.
- Strategy Tester runner with EA-log summary.
- Edge and challenge-odds calculator with a no-edge control.
- Critical-thinking, risk, time, validation and case-study references.
- CI for structure, evals and the statistics tools.

## Near term

- News blackout helper that works in the tester (imported event CSV) and live (MQL5 calendar).
- Walk-forward helper for `run_mt5_tester.py` (chained optimise/test windows).
- Random-direction null-baseline switch in the reference EA.
- Parity-check script: compare two trade lists (MT5 report vs CSV) by entry time and direction.

## Mid term

- cTrader cAlgo SkillKit equivalent (C#) with the same guards.
- Multi-symbol guard (account exposure, correlated positions).
- Translated quick-start (Bahasa Indonesia).

## Long term

- Automated grading of `evals.json` answers (static checks on generated code + compile).

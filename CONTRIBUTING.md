# Contributing

## Principles

- **Evidence first**: every MQL5 snippet must compile with MetaEditor (0 errors, 0 warnings);
  every number in the docs states its source, period, model and costs.
- **Safety first**: never remove risk controls; never promise results.
- **Measurable**: new guidance comes with an eval case or a test.
- **Educational**: no financial advice.

## Workflow

1. Change `mql5-ea-expert/SKILL.md` only for rules and workflow; put detail in `references/`.
2. Put reusable code in `templates/` (SkillKit) and compile it:

   ```bash
   python tools/compile_mql5.py            # Windows + MetaEditor
   ```

   If you can, run it in the tester and check for failed operations:

   ```bash
   python tools/run_mt5_tester.py mql5-ea-expert/templates/Experts/<EA>.mq5 --symbol ... --from ... --to ...
   ```

3. Add or update cases in `evals.json` for new behaviour.
4. Run the checks:

   ```bash
   python tools/validate_repo.py
   python -m unittest discover -s tools -p "test_*.py"
   ```

5. Document the change in `CHANGELOG.md` and bump the version in `SKILL.md` and `evals.json`.

## Case studies

Real failures are the most valuable contributions. Add them to `references/case-studies.md` with
the numbers, the data source and the rule the case supports. Never include account numbers,
passwords or tokens.

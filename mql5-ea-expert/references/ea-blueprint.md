# MQL5 EA output blueprint v3

The layout every generated Expert Advisor follows. The reference implementation is
`templates/Experts/SkillKit_StructureBreakout.mq5`.

---

## 1. Before the code (in the answer)

- Restate: strategy in testable rules, symbol/timeframe, account type and rules (with source and
  date), risk per trade in money, what happens when the minimum volume is too big.
- Feasibility: if the user has a target or deadline, the R needed and the measured/estimated odds.
- Warnings that apply: grid/martingale, no stop loss, news/holiday gaps, unproven edge.

## 2. File layout

```text
1  Header comment: name, purpose, what is demonstrated, "no edge claimed" unless validated
2  #property copyright / link / version / description   (no #property strict)
3  #include <SkillKit\...>  or local includes
4  Enums
5  Inputs grouped:  STRATEGY / RISK / PROP FIRM RULES / TIME (zone in every comment) / EA
6  Globals: CSkClock, CSkPropGuard, CSkTrader, CSkNewBar, handles = INVALID_HANDLE
7  OnInit: validate inputs -> INIT_PARAMETERS_INCORRECT; create handles; init guard/trader/clock;
          EventSetTimer(1); log [INIT] with server offset and start balance
8  OnDeinit: EventKillTimer, IndicatorRelease, ObjectsDeleteAll(prefix)
9  EnforceGuards(): guard.Update, floating shield, halt on limits/target, flat time, session end
10 OnTimer -> EnforceGuards
11 OnTick -> EnforceGuards, new-bar gate, EvaluateSignal
12 EvaluateSignal: position/session/period-count/spread gates -> closed-bar signal ->
          entry/stop/target -> RiskBudget -> SkLotsForRisk (skip if 0) -> margin -> Market()
13 Trade management (only if validated): ImproveStop, ClosePartial
14 OnTradeTransaction (fills, journal) if needed
15 OnTester: sample-size and drawdown-aware criterion
```

## 3. Mandatory controls

| Control | Implementation |
|---|---|
| Risk per trade | Money input (or % of balance), sized with `SkLotsForRisk` |
| Minimum volume too big | Skip with a `[SKIP]` log line |
| Daily loss | `CSkPropGuard` daily limit with basis + reset zone + persisted snapshot |
| Max loss | From start balance; close on breach |
| Floating loss rule | `InpFloatShield` below the firm's level |
| Profit target lock | Optional, closes and stops |
| Spread | Max spread in points |
| Session/flat | UTC (or anchored) times + minutes before session end |
| Entries per period | Counted from deal history |
| Magic + symbol filter | Every position/deal loop |
| Stops | Stop loss on every position; stops/freeze levels checked |

## 4. Verification steps (in order, report each result)

1. `python tools/compile_mql5.py path\EA.mq5` -> 0 errors, 0 warnings.
2. `python tools/run_mt5_tester.py path\EA.mq5 --symbol ... --model 1 ...` (smoke) -> 0 failed operations;
   read `[SKIP]`, `[EXIT]`, `[PROP]` lines for correct timing.
3. `SkillKit_ServerTimeProbe` on the broker if any time logic exists; set the server-time model.
4. Real-tick run (`--model 4`) over at least 3 time blocks with the account's deposit.
5. `python tools/edge_check.py report.htm --risk <r> --blocks 3 [--target ... --days ...]`.
6. Demo forward test with identical inputs; compare fills and trade count.

## 5. Naming

| Prefix | Use |
|---|---|
| `Inp` | Inputs (`InpRiskMoney`) |
| `g_` | Globals (`g_guard`) |
| `h_` | Indicator handles (`h_atr`) |
| `m_` | Class members |
| `Sk` / `CSk` | SkillKit functions / classes |
| `ALL_CAPS` | Constants |

## 6. Multi-file projects

```text
MQL5\Experts\<Project>\<Project>.mq5        orchestrator only
MQL5\Include\<Project>\Signals.mqh          entry/exit rules on closed bars
MQL5\Include\<Project>\Management.mqh      stop moves, partials (if validated)
MQL5\Include\SkillKit\*.mqh                time, risk/prop guard, trade, structure
```

Each file has its own header; list all paths before the code.

# Nook Economy Architecture Handoff

Date: 2026-06-07

## Purpose

This document captures the current understanding and the validated product/architecture direction for reworking Nook's economy.

It is intentionally a handoff/spec checkpoint, not an implementation plan. The next session should resume from here, finish the design details, then produce a concrete implementation plan before code changes.

## Current Implementation Observed

Nook currently has two persistent economy-related files:

- `~/.pixelvillage/ledger.json`
  - Written by `NookDaemon`.
  - Read by the app.
  - Contains total Bits, pending Bits, agents, sessions, recent Bit events, recent activity events, and bond state.
- `~/.pixelvillage/economy.json`
  - Written by the app through `EconomyStore`.
  - Read by the daemon through `EconomyReader`.
  - Contains per-agent upgrade state: `bitMultiplierLevel`, `bondDividendLevel`, `trickleLevel`, `spentBits`, `bonusAccumulated`, `trickleBitsAccumulated`, and timestamps.

The daemon currently does more than write raw usage history:

- `TranscriptParser` parses Claude JSONL usage and subject/activity signals.
- `ClaudeWatcher` reads only new JSONL lines via byte offsets.
- `AgentAttributor` assigns work to an NPC only when the project has a `.pixelvillage` config.
- `BitRate` converts token usage to Bits using weighted tokens:
  - input: `1.0`
  - output: `5.0`
  - cache creation/write: `1.25`
  - cache read: `0.1`
  - base rate: `5 Bits / 1k weighted tokens`
- `TokenEvent.bits` and `TokenEvent.bondTokens` use the same weights.
- `Ledger.apply` currently:
  - applies a `multiplier`;
  - increments global `totalBits` and `pendingBits`;
  - increments per-agent `totalBits`;
  - increments per-agent weighted `totalTokens`;
  - recalculates bond;
  - upserts `SessionRecord`;
  - appends `BitEvent`;
  - caps recent Bit events to 100.
- The daemon reads `economy.json` and applies `bitMultiplier` when crediting the ledger.

The app currently owns the interactive game economy:

- `UpgradeEconomy` defines upgrade costs and formulas.
- `VillageEngine` loads `ledger.json`, `economy.json`, and NPC memory.
- `availableBits` is derived as:
  - `agent.totalBits + bonusAccumulated + trickleBitsAccumulated - spentBits`
- `bitMultiplier` is `1.0 + level * 0.25`.
- `bondDividend` has costs `[200, 600, 1800]` and scales from bond.
- `trickle` costs `50 * 1.15^level` and grants `1 bit / 10s / unit`, with 1 hour offline catch-up cap.
- `VillageEngine.creditMultiplierBonus` also credits multiplier-derived bonus from incoming `BitEvent`s.

Important issue found: the current code likely has a double-counting risk around multipliers.

- Daemon-side tests confirm `Ledger.apply(event:multiplier:)` stores already-multiplied Bits in `AgentRecord.totalBits` and `recentEvents.bits`.
- App-side `creditMultiplierBonus` then computes another bonus from those events.
- This makes the authority boundary ambiguous and should be addressed by the economy architecture refactor.

## Validation Run During Analysis

Commands run successfully:

- `swift test`
  - 43 tests passed.
- `xcodebuild test -scheme NookApp -project NookApp.xcodeproj`
  - 65 tests passed.

Operational note: the Xcode test run started the app lifecycle and installed a Debug `NookDaemon` LaunchAgent pointing at `DerivedData`. That Debug daemon was booted out afterward. The plist may still point at the Debug binary until the app rewrites it on next launch.

## Product Direction Validated

The desired economy is:

1. Companion/progression-longue first.
2. A dose of idle/clicker satisfaction second.

Meaning:

- Long-term attachment should come from real work with an agent.
- Bond, memory, history, desks, and agent presence should remain tied to actual Claude usage.
- Short-term gamification should give the user something satisfying to do between sessions.
- Idle/clicker mechanics are for pacing, feedback, and small optimization loops, not for replacing the relationship layer.

## Wallet Direction Validated

Use a hybrid economy:

- Per-agent wallets remain important.
- Add a village/global wallet for shared upgrades, unlocks, decoration, or village-wide progression.

Intent:

- Agent wallets preserve attachment to specific NPCs.
- Village wallet gives the player something useful even when work is unattributed or when they want to improve the shared village.
- Global/village progression should not erase per-agent identity.

## Source Of Truth Direction Validated

Use Approach A:

```text
ledger.json = raw facts/history only
economy.json = game economy state
```

The daemon should become raw-history-only:

- Read Claude JSONL.
- Attribute events.
- Convert tokens to raw Bits.
- Persist raw usage/session/activity facts.
- Maintain bond from weighted tokens.

The daemon should stop:

- Reading `economy.json`.
- Applying multipliers.
- Knowing about upgrades.
- Writing game-modified Bits into history.

The app should own the game economy:

- Agent wallets.
- Village wallet.
- Purchases.
- Spending.
- Upgrades.
- Trickle.
- Multiplier/bonus calculations.
- Effective gain animations.

Core principle:

Upgrades must never rewrite or distort the historical ledger. They produce derived game balances and feedback.

Example:

```text
Claude usage creates +100 raw Bits for Radion.
ledger.json records exactly +100 raw Bits.

The app economy may derive:
- Radion wallet +100
- Village wallet +10
- multiplier bonus +25
- trickle +3 later

The historical fact remains:
Radion earned +100 raw Bits from usage.
```

## Proposed Architecture Direction

Keep the schema split:

- `LedgerState`: factual history and progression.
- `EconomyState`: gameplay balances and upgrade state.

Recommended conceptual modules:

- `BitRate`
  - Token weighting and raw Bit conversion.
  - Shared or mirrored carefully across targets if still duplicated.
- `BondScale`
  - Long-term relationship thresholds.
  - Should stay independent from spendable wallet formulas.
- `Ledger`
  - Writes raw facts only.
  - No upgrade or spending logic.
- `EconomyEngine` or expanded `UpgradeEconomy`
  - Pure functions for deriving wallet deltas and applying purchases.
  - App-owned.
  - Unit-tested separately from UI.
- `EconomyStore`
  - Persists `EconomyState`.
  - App-owned writer.
- `VillageEngine`
  - Orchestrates loading ledger/economy and forwarding visual events.
  - Should not contain core balance formulas long term.

## Design Questions Still Open

These should be brainstormed next before writing the implementation plan.

1. Wallet split formula
   - How much raw agent work goes to the agent wallet versus village wallet?
   - Possible defaults:
     - 100% agent, 10% extra village bonus
     - 90% agent, 10% village siphon
     - attributed work goes mostly agent, unattributed work goes village

2. Global pool semantics
   - Should global/village Bits be earned only from unattributed work?
   - Or should every attributed session also feed the village?

3. Multipliers
   - Should multipliers increase only the agent wallet?
   - Should they also increase village income?
   - Should multiplier bonuses be shown as separate "bonus" popups or folded into the gain number?

4. Bond dividend
   - Should bond dividend be an economic multiplier?
   - Or should it unlock utility/quality-of-life perks so bond remains emotionally meaningful?

5. Trickle
   - Should trickle be per-agent, village-wide, or both?
   - Should trickle require recent activity from that agent?
   - Should trickle create raw-looking income or clearly be idle income?

6. Retrofitting existing data
   - Existing ledgers may already contain multiplier-inflated Bits.
   - Need a migration strategy or an explicit decision not to back-correct old ledgers.

7. Naming
   - Current `AgentRecord.totalBits` may need to become `rawBits` or similar to avoid confusion.
   - Any schema rename must preserve backward compatibility in both daemon and app decoders.

## Likely Next Design Recommendation

Use these principles unless the next brainstorm changes them:

- Ledger stores raw historical `rawBits`.
- Bond uses weighted tokens, not spendable Bits.
- Agent wallet derives from raw attributed work.
- Village wallet derives from all work, with unattributed work going fully village.
- Multipliers affect only the game wallet layer, not ledger history.
- Trickle is explicitly idle/game income, stored in economy state, not ledger.
- Spendable balances should be derived from economy state and raw ledger facts, with enough persisted checkpoints to avoid replay bugs.

## Next Session Instructions

Resume from "Design Questions Still Open".

Recommended next step:

1. Decide wallet split and global pool rules.
2. Decide upgrade semantics for multiplier, bond dividend, and trickle.
3. Present a complete design in sections:
   - data model;
   - event flow;
   - balancing formulas;
   - migration;
   - testing.
4. After user approval, write the final design/spec.
5. Then create a separate implementation plan.

Do not implement until the design is approved.

# Nook Economy Redesign

Date: 2026-06-08

## Status

Design approved. This spec defines the target architecture and balance rules for the economy refactor.

Do not implement directly from this document without first writing an implementation plan.

## Goals

Nook's economy should support two complementary experiences:

- Long-term companion progression: the user's real work with an agent should build attachment through Bond, memory, history, desks, and presence.
- Short-term idle/clicker satisfaction: the user should have small, satisfying purchases and visible gains between Claude sessions.

The long-term relationship layer must remain anchored in real Claude usage. The idle/clicker layer may be more game-like, but it must not replace or distort the relationship layer.

## Non-Goals

- Do not replay Claude transcript history to rebuild old balances.
- Do not make the daemon responsible for upgrades, spending, or idle income.
- Do not allow passive income to advance Bond.
- Do not use multiplicative stacking for upgrade bonuses.
- Do not merge historical facts and gameplay state into a single ledger file.

## Architecture Decision

Use a split-source model:

```text
ledger.json  = raw facts and relationship history
economy.json = app-owned gameplay economy state
```

`NookDaemon` writes raw usage facts only. The app owns all gameplay economy behavior.

The daemon must not:

- read `economy.json`;
- know about upgrades;
- apply multipliers;
- write game-modified Bits into ledger history.

The app must:

- process raw ledger deltas;
- maintain per-agent wallets;
- maintain the village wallet;
- apply upgrades;
- apply trickle income;
- handle purchases and spending;
- drive effective gain animations.

## Ledger Model

The ledger remains the durable historical record.

Conceptual daemon/app ledger model:

```swift
struct AgentRecord {
    var name: String
    var totalTokens: Int
    var bond: Int
    var totalBitsRaw: Double
}

struct BitEvent {
    var agentName: String?
    var rawBits: Double
    var seq: Int
}

struct LedgerState {
    var totalBitsRaw: Double
    var globalBitsRaw: Double
    var agents: [String: AgentRecord]
    var recentEvents: [BitEvent]
    var sessions: [String: SessionRecord]
    // Existing pending/activity/session fields remain as needed.
}
```

Naming may remain backward-compatible on disk during migration. For example, existing JSON keys like `totalBits` may decode into `totalBitsRaw`, but code should make clear that these are raw historical Bits.

`globalBitsRaw` tracks unattributed Claude work. Work is unattributed when no `.pixelvillage` file resolves to an agent.

Bond remains based on weighted tokens, not spendable wallets.

## Economy Model

`economy.json` stores gameplay state and processing checkpoints.

Target app model:

```swift
struct EconomyState: Codable, Equatable {
    var schemaVersion: Int
    var agents: [String: AgentEconomyState]
    var villageWallet: Double
    var spentVillageBits: Double
    var lastProcessedGlobalRawBits: Double
    var lastUpdated: Date
    var migration: EconomyMigrationState
}

struct AgentEconomyState: Codable, Equatable {
    var wallet: Double
    var spentBits: Double
    var lastProcessedRawBits: Double
    var bitMultiplierLevel: Int
    var bondDividendLevel: Int
    var trickleCount: Int
    var trickleBitsAccumulated: Double
    var lastTrickleAt: Date?
    var migrationAdjusted: Bool
}
```

Available balances:

```text
agentAvailable = max(0, wallet + trickleBitsAccumulated - spentBits)
villageAvailable = max(0, villageWallet - spentVillageBits)
```

`wallet` is gameplay income already credited to the agent. It is advanced by processing raw ledger deltas. It is not recomputed from scratch on every display.

`lastProcessedRawBits` prevents double-counting and allows the app to catch up after being closed.

## Gain Processing

On app reload, load:

```text
ledger.json
economy.json
```

Then run a pure economy processor, for example:

```swift
EconomyEngine.processLedgerDelta(ledger: LedgerState, economy: inout EconomyState)
```

For each attributed agent:

```text
rawDelta = ledgerAgent.totalBitsRaw - economyAgent.lastProcessedRawBits
```

If `rawDelta > 0`:

```text
effectiveGain = rawDelta * additiveMultiplier(agentBond, economyAgent)
agent.wallet += effectiveGain
economy.villageWallet += effectiveGain * 0.10
agent.lastProcessedRawBits = ledgerAgent.totalBitsRaw
```

If `rawDelta == 0`, do nothing.

If `rawDelta < 0`, do not debit the wallet. Treat it as an abnormal reset/migration condition, log it, and resynchronize the checkpoint conservatively.

For unattributed/global work:

```text
globalRawDelta = ledger.globalBitsRaw - economy.lastProcessedGlobalRawBits
```

If `globalRawDelta > 0`:

```text
economy.villageWallet += globalRawDelta
economy.lastProcessedGlobalRawBits = ledger.globalBitsRaw
```

This gives all Claude activity value, but only attributed activity builds an agent relationship.

## Wallet Rules

Attributed Claude work:

```text
agent wallet += effectiveGain
village wallet += effectiveGain * 0.10
```

Unattributed Claude work:

```text
village wallet += rawBits
agent wallet += 0
Bond += 0
```

Trickle income:

```text
agent trickleBitsAccumulated += trickleGain
village wallet += 0
Bond += 0
ledger += 0
```

Purchases and spending do not generate village bonus.

## Upgrade Stacking

All active-work bonuses stack additively.

```text
effectiveGain = rawBits * (1 + bitMultiplierBonus + bondDividendBonus)
```

Never use multiplicative stacking such as:

```text
rawBits * bitMultiplier * bondDividendMultiplier
```

Additive stacking keeps the economy understandable and prevents runaway compounding.

## Bit Multiplier

Bit Multiplier is a per-agent active-work upgrade. It affects future attributed Claude work for that agent.

It does not alter ledger history.

Recommended levels:

| Level | Total Bonus | Cost |
| --- | ---: | ---: |
| 0 | +0% | 0 |
| 1 | +10% | 500 |
| 2 | +20% | 1,250 |
| 3 | +35% | 3,000 |
| 4 | +50% | 7,500 |
| 5 | +75% | 18,000 |
| 6 | +100% | 45,000 |

The costs intentionally make early progress visible while keeping large scaling upgrades as real goals.

## Bond Dividend

Bond Dividend is a per-agent active-work upgrade that turns earned relationship depth into a gameplay bonus.

It is purchasable by agent and gated by Bond.

Recommended levels:

| Level | Bond Gate | Factor | Cost |
| --- | ---: | ---: | ---: |
| 0 | none | 0.00 | 0 |
| 1 | Bond 3 | 0.03 | 1,500 |
| 2 | Bond 6 | 0.06 | 6,000 |
| 3 | Bond 10 | 0.10 | 20,000 |

Formula:

```text
bondDividendBonus = bond * factor[level]
```

Example:

```text
Bond 6, dividend level 2
bondDividendBonus = 6 * 0.06 = +36%
```

The gate ensures this is a relationship-backed upgrade, not an early-game financial shortcut.

## Trickle

Trickle is a per-agent idle/clicker unit.

Each purchase adds one additive unit. It does not multiply previous trickles.

```text
trickleIncome = trickleCount * ratePerUnit
```

Recommended rule:

```text
ratePerUnit = 0.25 bit / 10s
```

That equals:

```text
90 Bits / hour / trickle unit
```

Recommended cost:

```text
cost(nextUnitIndex) = 100 * 1.25^trickleCount
```

The cost grows to slow mass accumulation, while each unit's marginal production remains constant.

Bond caps:

| Bond | Max Trickle Units |
| ---: | ---: |
| 1-2 | 2 |
| 3-5 | 5 |
| 6-9 | 10 |
| 10+ | 20 |

Offline catch-up:

```text
max elapsed = 1 hour
```

Trickle never credits village wallet and never advances Bond.

## Balance Intent

Current raw Bit rate:

```text
rawBits = weightedTokens / 1000 * 5
```

Examples:

| Weighted Tokens | Raw Bits |
| ---: | ---: |
| 10,000 | 50 |
| 50,000 | 250 |
| 100,000 | 500 |
| 250,000 | 1,250 |
| 1,000,000 | 5,000 |

Target purchase cadence:

- A small improvement should be available after most normal sessions.
- Trickle should provide frequent idle/clicker satisfaction.
- Bit Multiplier should be a stronger, rarer future-work investment.
- Bond Dividend should be a meaningful relationship-gated purchase.

The design intentionally makes small trickle purchases frequent, while multiplier and Bond Dividend upgrades remain slower goals.

## Migration

Do not replay transcript history.

Use a conservative gameplay migration.

Historical relationship data remains intact:

- sessions;
- total weighted tokens;
- Bond;
- activity history;
- NPC memory.

Gameplay economy is normalized.

For each existing agent:

```text
lastProcessedRawBits = ledgerAgent.totalBitsRaw
wallet = conservativeStartingWallet(agent)
spentBits = 0
upgrades = conservatively remapped/clamped
trickleCount = clamp(oldTrickleLevel, bondTrickleCap)
migrationAdjusted = true
```

Recommended wallet normalization:

```text
wallet = min(ledgerAgent.totalBitsRaw * 0.25, walletCapByBond)
```

Wallet caps:

| Bond | Starting Wallet Cap |
| ---: | ---: |
| 1-2 | 500 |
| 3-5 | 1,500 |
| 6-9 | 5,000 |
| 10+ | 12,000 |

Upgrade migration:

- `bitMultiplierLevel`: clamp to the new max level.
- `bondDividendLevel`: keep only if the agent satisfies the new Bond gate; otherwise downgrade to the highest valid level.
- old `trickleLevel`: becomes `trickleCount`, capped by Bond.
- `spentBits`: reset to 0 because wallet has already been normalized.

`schemaVersion` prevents running this migration repeatedly.

## Error Handling

If `economy.json` is missing:

- create a migrated `EconomyState` from the ledger.

If `economy.json` uses an old schema:

- migrate once based on `schemaVersion`.

If `economy.json` is unreadable:

- do not mutate the ledger;
- load a safe empty/migrated state where possible;
- log the failure.

If `rawDelta < 0`:

- do not subtract from wallets;
- log or surface the anomaly;
- resynchronize checkpoints conservatively.

If an agent disappears from the ledger:

- keep its economy state so purchases are not lost.

If a new agent appears:

- create `AgentEconomyState` with `lastProcessedRawBits = 0`;
- process its current raw delta normally.

## UI And Animation Semantics

The app should display gameplay balances, not raw historical totals, for spendable money.

NPC display:

- Bond from ledger.
- Available agent Bits from economy.
- Active multiplier/dividend/trickle indicators as needed.

Village HUD:

- should expose total available agent Bits and/or village wallet clearly.
- village wallet should be distinct from agent wallet.

Gain animations:

- Use `BitEvent`s for immediate feedback when available.
- Use effective gain amounts for attributed work animations.
- If events are missed, checkpoint processing still credits balances.
- Trickle animations use trickle gains only.

`BitEvent`s are not authoritative for balances. Checkpoints are authoritative.

## Testing Plan

Daemon tests:

- `Ledger.apply` stores raw Bits only.
- `Ledger.apply` no longer accepts or applies a multiplier.
- daemon no longer has `EconomyReader`.
- attributed events update agent raw totals and bond tokens.
- unattributed events update global raw totals and no agent.
- `BitEvent` stores raw Bits.
- backward-compatible decoding preserves existing ledger files.

App model/economy tests:

- missing economy creates migrated state from ledger.
- old economy migrates once by `schemaVersion`.
- conservative migration caps starting wallets by Bond.
- old dividend levels are clamped to Bond gates.
- old trickle levels are clamped to Bond caps.
- `processLedgerDelta` credits agent wallet and 10% village bonus.
- multipliers affect effective gain and village receives 10% of effective gain.
- unattributed global delta credits village only.
- trickle credits agent only.
- additive stacking is enforced.
- repeated reload with no raw delta does not double-credit.
- missed `recentEvents` still credit correctly from cumulative ledger delta.
- negative raw delta does not debit wallets.

UI/engine tests where feasible:

- `VillageEngine.availableBits(for:)` reads economy balance.
- shop rejects purchases that fail cost or Bond gates.
- shop accepts purchases and increments `spentBits`.
- trickle timer respects Bond caps and offline cap.

## Implementation Notes

Keep changes staged carefully because the repository may contain unrelated work.

The ledger schema is duplicated across daemon and app. Any ledger field rename or additive field must be mirrored in both:

- `Sources/NookDaemon/Models.swift`
- `Sources/NookApp/LedgerModels.swift`

Use backward-compatible decoders in both copies.

Prefer pure economy functions for balance logic. `VillageEngine` should orchestrate loads/saves and UI events, not own the formulas.

## Open Follow-Up After V1

These are intentionally out of scope for the first implementation:

- richer village-wide purchases and unlocks;
- per-agent prestige loops;
- activity-recency boosts for trickle;
- visual redesign of the shop;
- complete historical raw replay from transcripts.

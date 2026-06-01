# NPC History & Memory — Design Spec

> **Scope:** Build the per-NPC *history/memory* system — the data foundation of the
> attachment experience. NPCs accumulate a visible, layered history (sessions →
> projects → moments) that surfaces in the existing inspector panel.
>
> **Out of scope (future specs that build on this):** NPC presence/voice (dialogue,
> notifications) — feeds on this data; enriched Bond ladder & rewards; visual NPC
> transformation (emergent personality made visible).

---

## Goal

Today, "attachment" to an NPC is just *a number that goes up* (`bond`, `totalTokens`)
plus a promotion animation. There is no sense of a *shared past*. This feature gives
each NPC a longitudinal history derived from real Claude Code work, so the relationship
feels like it accumulates over sessions.

**Success criteria:**
- After working with an agent across several sessions, clicking its NPC shows a history
  that *grew*: which projects you built together, recent sessions, and memorable moments.
- The history keeps producing **new beats over time** (not a static plaque) — living
  moments refresh regularly.
- All derivation logic is pure and unit-tested; the daemon only records raw sessions.

---

## Decisions (locked during brainstorming)

| Decision | Choice |
|---|---|
| Form of history | **All three layered** — sessions = data primitive; projects + moments derived on top |
| Data start point | **Start fresh** — history accrues from ship day; no backfill, no scan, clean attribution |
| Surface | **Enriched inspector panel** (existing right sidebar), no separate view |
| Daemon/app split | **Approach A** — daemon records raw sessions; app derives projects + moments as pure functions |

---

## Architecture

```
Claude Code JSONL  →  Daemon (records SessionRecord)  →  ledger.json
                                                              │
                                                              ▼
                          App reads sessions  →  pure derivations  →  enriched NPCSelection  →  inspector
                                                  (ProjectRollup, Moment)
```

**Principle:** the daemon owns the raw primitive (sessions — it already sees the data
flow by). The app derives *projects* and *moments* as pure functions, mirroring the
existing `BondProgress` helper. "What counts as a moment" lives in the app and can be
iterated without touching the daemon or the persisted schema.

---

## 1. Data model & daemon changes

### `SessionRecord` (new, daemon, `Codable`)

```
struct SessionRecord {
    let sessionId: String        // JSONL filename (UUID) — stable session key
    let project: String          // human-readable project name, derived from cwd ("Radion", "Nook")
    let projectPath: String      // raw encoded ~/.claude/projects dir — stable grouping key
    var agentName: String?       // attributed agent (nil = global pool, excluded from NPC history)
    let startedAt: Date          // first entry timestamp
    var lastActivityAt: Date     // last entry timestamp
    var inputTokens: Int
    var outputTokens: Int
    var totalBits: Double
    // derived: totalTokens = inputTokens + outputTokens; duration = lastActivityAt - startedAt
}
```

### Storage

- `LedgerState.sessions: [String: SessionRecord]`, keyed by `sessionId`.
- Decoded with `try?` defaulting to `[:]` → **backward-compatible** with existing
  `ledger.json` (matches the existing optional-field decoding pattern). No migration —
  consistent with start-fresh.
- `AgentRecord` aggregates (`totalTokens`, `bond`, `totalBits`) are **unchanged**.
  Sessions are an additive layer, not a replacement.
- Retention: keep **all** `SessionRecord`s (~100 bytes each; 10k sessions ≈ 1 MB).
  Display caps to recent N. Splitting into a dedicated `sessions.json` is a future
  evolution if `ledger.json` bloats.

### Daemon changes (3, bounded)

1. **`TranscriptParser.parseLine`** — extract, in addition to token usage:
   - the **real `timestamp`** (ISO8601 from the entry) — *fixes the current `Date()` bug
     where ingestion time was used instead of entry time*;
   - the **`cwd`** field (to derive the human-readable project name).
   - Returns a richer parsed struct.
   - Robustness: if an entry has no valid timestamp, fall back to `Date()` for that event
     (never drop the token data).
2. **`ClaudeWatcher.readNewLines`** — already has `file` (→ `sessionId =
   file.deletingPathExtension().lastPathComponent`) and `projectPath`. Thread `sessionId`
   through the `onEvent` callback.
3. **`Ledger.apply`** — in addition to the existing `AgentRecord` aggregation, **upsert**
   the `SessionRecord`:
   - new session → set `startedAt`, `project`, `projectPath`, `agentName`;
   - existing → update `lastActivityAt`, accumulate tokens/bits.

**Project name derivation:** prefer the JSONL `cwd` field (last path component → "Radion",
"Nook"); fallback to decoding the encoded `~/.claude/projects/<encoded>` dir name.

---

## 2. Derivation layer (app, pure functions)

The app already loads `ledger.json`, so it has `sessions`. Two pure helpers (no SwiftUI /
SpriteKit dependency), built like `BondProgress` → unit-tested in `NookAppTests`.

### `ProjectRollup`

```
static func forAgent(_ sessions: [SessionRecord]) -> [ProjectRollup]
// group by projectPath, sort by totalTokens desc
// each: project, totalTokens, sessionCount, firstSeen, lastSeen
```

### `Moment`

```
static func forAgent(_ sessions: [SessionRecord]) -> [Moment]   // sorted chronologically
```

A `Moment` is an auto-detected memorable beat. Two categories:

**Anchors (one-time, permanent):**

| Moment | Detection |
|---|---|
| First session together | earliest session for the agent |
| First day on a project | first session per distinct project |
| Anniversary | yearly from first session (surfaces only near the date) |
| Bond promotion | replay cumulative tokens, find the session crossing each threshold (10k/50k/200k/1M) |

**Living (refresh regularly):**

| Moment | Detection |
|---|---|
| Consecutive-day streak (+ record) | count consecutive local-calendar days with a session; extends daily, breaks on a skipped day, keeps a record streak |
| Round cumulative milestones | tokens (100k/250k/500k/1M), session count (10th/50th/100th), cumulative hours (10h/50h/100h) |
| Beatable records | longest session (duration), biggest session (tokens), most productive day (tokens in one local day) |
| Rhythm patterns | night session / all-nighter (active between ~00:00–05:00 local); return-after-absence ("back after 2 weeks") |

**Bond / token-palier de-duplication:** the Bond ladder *is* a token-threshold milestone.
When a Bond promotion and a round token milestone coincide (e.g. 1M), emit a single moment
(prefer the Bond framing). Coordinate the two detectors so the same crossing is not shown
twice.

**Altitude note:** the moment catalog lives in the app as a pure function. Adding/removing
a moment type touches neither the daemon nor the persisted schema.

---

## 3. Surface — enriched inspector panel

`NPCInspectorPanel` becomes a **`ScrollView`**. Top to bottom:

- **Header / Status / Stats / Bond progress bar** — *existing, unchanged.*
- **"Live" strip** (top, compact): current streak + active records as small badges →
  `🔥 5d · 4h12 max · 320k`. The frequently-changing part, visible without scrolling.
- **Projects**: top 3–5 rollups, compact rows → `Radion · 45k · 12 sess.`
- **Recent sessions**: last 5 → `Jun 2 · Nook · 1h20 · 8k`
- **Moments**: chronological list of the ~5 **most recent** (the catalog is large, so we
  show only recent ones), with a small per-type icon — not the full history.

**Data flow:** `NPCManager.selection(for:)` computes the derived arrays (projects, recent
sessions, moments) via the pure helpers and packs them into an enriched `NPCSelection`.
SwiftUI stays dumb. This extends the existing selection-refresh path (`refreshSelection`)
already wired into `VillageScene.update(_:)`, so the panel stays fresh as sessions change.

**Width:** bump the panel from 304pt to ~340pt to fit `date · project · duration · tokens`
rows. Still the inspector (honors "everything in the inspector").

---

## 4. Edge cases & testing

### Edge cases (resolved)

- **Session bounds:** one JSONL file = one session; `start`/`end` = first/last entry. An
  idle gap inside a session left open → duration overcounts. Acceptable for MVP; capping
  is a future refinement.
- **Day boundary** (streaks, most-productive-day, night): **local calendar day**. Night =
  session active between ~00:00–05:00 local.
- **Attribution:** `agentName` read from `.pixelvillage` at scan time; `nil` = global
  pool, **excluded** from NPC history. No retroactive attribution (consistent with
  start-fresh).
- **⚠️ Agent rename:** sessions are keyed by `agentName`. A future rename feature must
  migrate `session.agentName`. **Out of scope here**, flagged so it isn't missed.
- **Concurrent sessions, same agent:** multiple active JSONL files → each its own
  `SessionRecord`. The multi-session visual "load" is handled separately by
  `SessionDetector` and is unaffected.
- **Retention:** keep all `SessionRecord`s; display caps to recent N.
- **Timestamp robustness:** entry without a valid timestamp → fallback `Date()` for that
  event.

### Testing

- **App (XCTest, `NookAppTests`):** `ProjectRollupTests`; `MomentTests` with one case per
  type (streak extend / break / record, palier crossed, record beaten, night detection,
  return-after-absence, bond/palier de-dup) using synthetic `SessionRecord` fixtures.
- **Daemon (`swift test`, target `NookTests`):** `parseLine` extracts real timestamp +
  sessionId; `Ledger` upsert (first entry creates the record; subsequent entries update
  `lastActivityAt` and accumulate).

---

## Files

**Daemon:**
- `Sources/NookDaemon/Models.swift` — add `SessionRecord`; add `sessions` to `LedgerState`.
- `Sources/NookDaemon/TranscriptParser.swift` — extract real timestamp + cwd; richer parse result.
- `Sources/NookDaemon/ClaudeWatcher.swift` — thread `sessionId` through.
- `Sources/NookDaemon/Ledger.swift` — upsert `SessionRecord` in `apply`.

**App:**
- `Sources/NookApp/LedgerModels.swift` — mirror `SessionRecord` + `sessions` for app-side decode.
- `Sources/NookApp/ProjectRollup.swift` — new pure helper.
- `Sources/NookApp/Moment.swift` — new pure helper (catalog).
- `Sources/NookApp/NPCSelection.swift` — add `projects`, `recentSessions`, `moments`.
- `Sources/NookApp/NPCManager.swift` — `selection(for:)` computes & packs derived data.
- `Sources/NookApp/NPCInspectorPanel.swift` — `ScrollView` + new sections; width ~340pt.

**Tests:**
- `Tests/NookAppTests/ProjectRollupTests.swift`, `Tests/NookAppTests/MomentTests.swift`
- `Tests/NookTests/` (daemon) — parser timestamp/sessionId + ledger upsert.

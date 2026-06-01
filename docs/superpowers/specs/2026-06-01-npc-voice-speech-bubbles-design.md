# NPC Voice — Subject-Aware Speech Bubbles — Design Spec

> **Scope:** First slice of the NPC "presence/voice" layer (#2 in the attachment roadmap).
> NPCs emit in-world speech bubbles that **react to the concrete subject of the active
> Claude Code session** — the file you just opened, the task you framed, the tests you ran.
>
> **Builds on:** the shipped #3 history system (daemon → `SessionRecord` → app derivations).
>
> **Out of scope (future):** LLM-generated lines (we design a clean seam for it but ship
> heuristic templates first); persistent "messages" feed; system notifications; interactive
> click dialogue; trait/personality-flavored wording; bond-gated richness.

---

## Goal

Make an NPC feel like a present companion that *notices what you are actually doing*.
When the active session's work shifts in a meaningful way (a new file, the first test run,
the task you stated), the responsible NPC speaks a short, relevant line in a bubble above
its head. Not structural beats (streaks/bonds) — the **content** of the work.

**Success criteria:**
- While a session is active, doing concrete work (opening a file, running tests) makes the
  attributed NPC say something relevant within a few seconds.
- Lines reflect the real subject (file name, task, activity type), not generic flavor.
- The village stays calm — bubbles are rare enough to respect "presence without noise"
  (per-NPC cooldown; only significant changes; one bubble at a time).
- All wording lives behind a pure, swappable `SpeechLineComposing` interface so an
  LLM composer can replace the heuristic later without touching detection or rendering.
- Heuristic mode keeps everything local — no transcript content leaves the machine.

---

## Decisions (locked during brainstorming)

| Decision | Choice |
|---|---|
| Surface | **In-world speech bubbles** above the NPC |
| Trigger | **On significant change** in the active session (new file, first test cmd, task framed, deep-work threshold), with per-NPC cooldown |
| Line generation | **Heuristic / templates** now; clean seam to swap in **LLM (Claude API)** later |
| Subject signals captured | **task** (first user prompt), **files touched**, **shell commands**, **activity shape** (counts) |
| Architecture | **Approach A** — daemon detects + emits `SessionActivityEvent`; app composes + renders |

---

## Architecture

```
Claude Code JSONL  →  Daemon (parse subject + detect significant change)
                          │  ├─ enrich SessionRecord (task, files, counts, branch)
                          │  └─ append SessionActivityEvent → ledger.recentActivity
                          ▼
                      ledger.json
                          │  (LedgerWatcher fires on write — existing)
                          ▼
   VillageEngine.reload → newActivityEvents (anchored on first load, no replay)
                          ▼
   VillageScene.update → NPCManager drains events
                          │  cooldown + target-NPC filter
                          │  HeuristicLineComposer.line(for:session:)  ← swappable
                          ▼
              NPCSprite.showSpeech(text)   (pixel bubble, auto-dismiss)
```

**Principle (same as #3):** the daemon owns transcript parsing (single parser, no drift)
and emits discrete, ordered events through the **existing** event pipeline pattern
(`BitEvent`/`recentEvents`/`eventSeq`/`newBitEvents`/`lastSeenEventSeq`). The app consumes
them and isolates all wording in a pure composer.

---

## 1. Daemon — subject capture + activity events

### 1a. Enriched parse result

`TranscriptParser.parseLine` today returns `ParsedEntry { inputTokens, outputTokens,
timestamp, cwd }`. Extend it to also surface subject material:

```swift
struct ToolUse {
    let name: String          // "Edit", "Write", "Read", "MultiEdit", "Bash", ...
    let filePath: String?     // input.file_path (Edit/Write/Read/MultiEdit)
    let command: String?      // input.command (Bash)
}

struct ParsedEntry {
    let inputTokens: Int
    let outputTokens: Int
    let timestamp: Date
    let cwd: String?
    let gitBranch: String?
    let role: String?         // message.role: "user" | "assistant" | nil
    let userText: String?     // plain-text user prompt (nil for tool_result-only user entries)
    let toolUses: [ToolUse]   // tool_use blocks from an assistant entry (may be empty)
}
```

Parsing rules (verified against real JSONL):
- Skip non-message lines (no `message`): snapshots, `permissionMode`, `leafUuid`, etc.
- `message.content` may be a String or an array of blocks (`text`/`thinking`/`tool_use`/`tool_result`).
- `userText`: set only when `role == "user"` and content is a plain text string (or a single
  text block) — i.e. a real prompt, NOT a `tool_result` array.
- `toolUses`: from `role == "assistant"`, each `tool_use` block → `{name, input.file_path,
  input.command}`. Ignore `text`/`thinking`/`tool_result` blocks.
- `gitBranch`, `cwd`, `timestamp`: top-level fields (timestamp already handled, ISO8601 + `Date()` fallback).

### 1b. SessionRecord subject fields (additive, backward-compatible)

Add to `SessionRecord` (both daemon `Models.swift` and app `LedgerModels.swift`), all
decoded with `(try?) ?? default` so existing `ledger.json` still loads:

```swift
var task: String?            // first user prompt, trimmed + truncated to ~120 chars
var gitBranch: String?
var filesTouched: [String]   // FULL paths, append-on-new, capped to last 20
var editCount: Int           // Edit + Write + MultiEdit
var readCount: Int           // Read
var bashCount: Int           // Bash
var firedKinds: [String]     // one-shot activity kinds already emitted (persisted dedup)
```

(These also enrich the #3 inspector later; out of scope here but free.)

### 1c. Significant-change detection + `SessionActivityEvent`

New event type, mirroring `BitEvent`, in a dedicated capped queue on `LedgerState`:

```swift
struct SessionActivityEvent: Codable, Equatable {
    let agentName: String?    // routes to the NPC; nil (global pool) → app drops it
    let sessionId: String
    let kind: String          // "task" | "file" | "testing" | "committing" | "deepWork"
    let payload: String?      // file basename, task snippet, or command summary
    let seq: Int
}
```

Add to `LedgerState` (additive): `var recentActivity: [SessionActivityEvent]` (capped to
100, like `recentEvents`) and `var activitySeq: Int`.

A new `Ledger.ingestSubject(entry: ParsedEntry, sessionId:, agentName:, to:)` runs **per
parsed line** (see §1d). It **upserts** the `SessionRecord` (creating it — with
`startedAt`/`lastActivityAt = entry.timestamp`, `project` derived from `cwd`/`projectPath`,
zero tokens — when this line precedes any usage-bearing line, so subject capture never
depends on `apply` having run first), updates the subject fields, then emits at most the
significant-change events below. Each emission appends to `recentActivity`, increments
`activitySeq`, and trims to 100. Dedup is derived from persisted state so a daemon restart
mid-session does not double-fire:

| kind | Fires when | payload | dedup source |
|---|---|---|---|
| `task` | `session.task == nil` and `entry.userText != nil` (first real prompt) | task snippet | `task != nil` afterward |
| `file` | a tool_use `filePath` whose full path is **not** in `filesTouched` | basename | `filesTouched` |
| `testing` | first Bash whose command summary indicates tests (`test`, `xcodebuild test`, `swift test`, `pytest`, …) | command summary | `firedKinds` contains `testing` |
| `committing` | first Bash git commit (`git commit`) | `"git commit"` | `firedKinds` contains `committing` |
| `deepWork` | `editCount` crosses 10 | project name | `firedKinds` contains `deepWork` |

**Command summary (privacy hardening):** never store/emit the full Bash command line (may
contain secrets). Reduce to a coarse program token: the first word, or `git <subcommand>`
for git. Store nothing else of the command.

### 1d. ClaudeWatcher line loop

Today the watcher skips zero-token lines (`guard pair.0 > 0 || pair.1 > 0`) — which would
skip user-prompt and tool-only lines. Restructure `readNewLines` so that, per parsed line:
1. Always call `ledger.ingestSubject(entry:sessionId:agentName:to:&state)` (captures task,
   files, counts, branch; emits activity events).
2. When `usage` is present (`input > 0 || output > 0`), keep the existing token/bits/session
   accumulation via `ledger.apply(event:agentName:to:)` and the existing consecutive-duplicate
   guard (`lastUsage`) for that path only.

`sessionId` is still derived from the file name; `agentName` from `AgentAttributor`.

After processing, `ledger.save(state)` as today (this triggers the app's `LedgerWatcher`).

---

## 2. App — event consumption + LineComposer

### 2a. VillageEngine consumption (mirror of bits events)

```swift
private(set) var newActivityEvents: [SessionActivityEvent] = []
private var lastSeenActivitySeq: Int = -1
```

Also mirror `SessionActivityEvent` and the two new `LedgerState` fields app-side in
`LedgerModels.swift` (decode-only, `(try?) ?? default`).

In `reload()`, replicate the bits logic exactly:
- First load (`lastSeenActivitySeq == -1`): anchor to `state.activitySeq`, do **not** replay.
- Otherwise: append `state.recentActivity` entries with `seq > lastSeenActivitySeq` to
  `newActivityEvents`; advance `lastSeenActivitySeq` to the max seq seen.

### 2b. LineComposer (pure, swappable)

```swift
protocol SpeechLineComposing {
    func line(for event: SessionActivityEvent, session: SessionRecord?) -> String?
}

struct HeuristicLineComposer: SpeechLineComposing {
    func line(for event: SessionActivityEvent, session: SessionRecord?) -> String? { ... }
}
```

Heuristic mapping (return `nil` to say nothing for an event):

| kind | line (examples) |
|---|---|
| `task` | `"On attaque : \(payload)"` |
| `file` | `"Plongé dans \(payload)"` |
| `testing` | `"TDD, j'aime ça"` |
| `committing` | `"On commit ?"` |
| `deepWork` | `"Grosse session sur \(payload)"` |

A future `LLMLineComposer` implements the same protocol. `NPCManager` holds a
`SpeechLineComposing` defaulting to `HeuristicLineComposer()`.

---

## 3. App — speech bubble rendering + cadence

### 3a. `NPCSprite.showSpeech(_ text: String)`

Modeled on the existing `showBitsGain` / `showBondPromotion`:
- A pixel bubble above the head: rounded-rect `SKShapeNode` + small tail + monospace
  `SKLabelNode`, styled via `PixelNodeFactory` for visual consistency.
- Fade in → hold ~4 s (scaled to text length, clamped) → fade out → remove.
- **One bubble per NPC**: remove any existing bubble node (by name, e.g. `"speech"`) before
  adding a new one.
- Text wraps to ~2 lines max; truncate with an ellipsis beyond that.

### 3b. Cadence / anti-noise in NPCManager

When `VillageScene.update(_:)` drains `engine.newActivityEvents` (same place it drains
`newBitEvents`):
- Maintain `lastSpokeAt: [String: Date]` per agent. Drop an event if `< cooldown` since that
  NPC last spoke. **Cooldown ≈ 45–60 s.**
- Drop events whose `agentName == nil` (global pool — no target NPC).
- Drop events for an NPC with no live sprite (not present in the scene).
- If several retained events target the same NPC in one drain pass, speak only **one** (the
  most recent); discard the rest (no backlog queue).
- For the chosen event: `composer.line(for:session:)`; if `nil`, no bubble. `session` is
  looked up from `engine.sessions[event.sessionId]`.
- On a spoken bubble, set `lastSpokeAt[agentName] = now`.

---

## 4. Edge cases & testing

### Edge cases (resolved)
- **Non-message / tool_result-only lines:** skipped; never produce `task`.
- **Multi-restart dedup:** derived from persisted `task`, `filesTouched`, `firedKinds` — no
  double-fire after a daemon restart mid-session.
- **Privacy:** task truncated; Bash stored only as a coarse program token; everything local
  in heuristic mode (no exfiltration).
- **Non-file tools** (Grep, Glob, ToolSearch, `mcp__…`): no `filePath` → ignored for `file`.
  Bash → command summary.
- **Anti-replay:** `lastSeenActivitySeq` anchors on first load → no stale bubbles for activity
  that happened while the app was closed.
- **No target / cooldown / absent sprite:** event dropped silently.
- **Queue volume:** `recentActivity` capped at 100, consumed once (same as `recentEvents`).
- **file path vs display:** dedup on full path, display basename.

### Testing
- **Daemon (`swift test`, `NookTests`):**
  - `TranscriptParserTests`: enriched `parseLine` extracts `role`, `userText` (and nil for
    tool_result-only user entries), `toolUses` (name + file_path/command), `gitBranch`;
    skips non-message and thinking/text blocks.
  - `LedgerTests` (activity): first user prompt emits one `task` event and sets `session.task`;
    a new file emits one `file` event, a repeat does not; first test Bash emits `testing` once
    (guarded by `firedKinds`); `deepWork` fires when `editCount` crosses 10; command summary
    is coarse (no full command line stored).
- **App (`NookAppTests`):**
  - `HeuristicLineComposerTests`: one case per `kind` (mapping + truncation) and `nil` cases.
  - Activity-event consumption mirrors the already-tested `newBitEvents` pattern.

---

## Files

**Daemon:**
- `Sources/NookDaemon/TranscriptParser.swift` — enriched `ParsedEntry` + `ToolUse`, content-block parsing.
- `Sources/NookDaemon/Models.swift` — `SessionRecord` subject fields; `SessionActivityEvent`; `LedgerState.recentActivity` + `activitySeq`.
- `Sources/NookDaemon/Ledger.swift` — `ingestSubject(...)`: update subject fields + emit activity events.
- `Sources/NookDaemon/ClaudeWatcher.swift` — per-line loop: subject ingest (always) + token emit (when usage).

**App:**
- `Sources/NookApp/LedgerModels.swift` — mirror `SessionRecord` subject fields, `SessionActivityEvent`, `recentActivity`/`activitySeq`.
- `Sources/NookApp/VillageEngine.swift` — `newActivityEvents` + `lastSeenActivitySeq` consumption.
- `Sources/NookApp/SpeechLineComposer.swift` — `SpeechLineComposing` protocol + `HeuristicLineComposer`.
- `Sources/NookApp/NPCSprite.swift` — `showSpeech(_:)` pixel bubble.
- `Sources/NookApp/NPCManager.swift` — drain `newActivityEvents`, cooldown, compose, route to sprite.
- `Sources/NookApp/VillageScene.swift` — drain `newActivityEvents` in `update(_:)` (next to `newBitEvents`).

**Tests:**
- `Tests/NookTests/` — `TranscriptParserTests` (enriched), `LedgerTests` (activity events).
- `Tests/NookAppTests/` — `SpeechLineComposerTests`.

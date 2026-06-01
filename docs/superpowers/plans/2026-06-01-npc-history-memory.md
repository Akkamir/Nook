# NPC History & Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each NPC a longitudinal, layered history (sessions → projects → moments) derived from real Claude Code work, surfaced in the inspector panel.

**Architecture:** The daemon records raw `SessionRecord`s into `ledger.json` (Approach A). The app reads them and derives *projects* and *moments* as pure functions (mirroring the existing `BondProgress` helper), packs the result into an enriched `NPCSelection`, and renders it in a scrollable inspector. Start-fresh: no backfill, additive backward-compatible schema.

**Tech Stack:** Swift 6, SwiftPM (daemon), XcodeGen + SwiftUI/SpriteKit (app), XCTest (`NookTests` via `swift test` for the daemon, `NookAppTests` via `xcodebuild test` for the app).

**Spec:** `docs/superpowers/specs/2026-06-01-npc-history-memory-design.md`

---

## File Structure

**Daemon (`Sources/NookDaemon/`):**
- `Models.swift` — add `SessionRecord`; add `sessionId`/`cwd` to `TokenEvent`; add `sessions` to `LedgerState`.
- `TranscriptParser.swift` — return a `ParsedEntry` (tokens + real timestamp + cwd) instead of a half-filled `TokenEvent`.
- `ClaudeWatcher.swift` — derive `sessionId` from the JSONL filename, build the full `TokenEvent`.
- `Ledger.swift` — upsert the `SessionRecord` inside `apply(...)`.

**App (`Sources/NookApp/`):**
- `LedgerModels.swift` — mirror `SessionRecord` + add `sessions` to the app-side `LedgerState`.
- `VillageEngine.swift` — expose `sessions`, populate in `reload()`.
- `ProjectRollup.swift` — new pure helper (group sessions by project).
- `Moment.swift` — new pure helper (moment catalog + summary).
- `NPCSelection.swift` — add `projects`, `recentSessions`, `moments`, `currentStreakDays`, `longestSessionSeconds`.
- `NPCManager.swift` — `selection(for:)` filters sessions and packs derived data.
- `NPCInspectorPanel.swift` — `ScrollView` + new sections; width 340.

**Tests:**
- `Tests/NookTests/` — `LedgerTests` (upsert), `TranscriptParserTests` (timestamp/cwd), `LedgerStateDecodeTests` (back-compat).
- `Tests/NookAppTests/` — `ProjectRollupTests`, `MomentTests`, `LedgerStateAppDecodeTests`.

---

## Task 1: Daemon — SessionRecord model + LedgerState.sessions

**Files:**
- Modify: `Sources/NookDaemon/Models.swift`
- Test: `Tests/NookTests/LedgerStateDecodeTests.swift`

- [ ] **Step 1: Write the failing back-compat decode test**

Create `Tests/NookTests/LedgerStateDecodeTests.swift`:

```swift
import XCTest
@testable import NookDaemon

final class LedgerStateDecodeTests: XCTestCase {
    private func decode(_ json: String) throws -> LedgerState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LedgerState.self, from: Data(json.utf8))
    }

    func test_legacy_ledger_without_sessions_decodes_to_empty_sessions() throws {
        let json = """
        {"totalBits":10,"pendingBits":0,"agents":{},"lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0}
        """
        let state = try decode(json)
        XCTAssertTrue(state.sessions.isEmpty)
    }

    func test_ledger_with_sessions_decodes_them() throws {
        let json = """
        {"totalBits":10,"pendingBits":0,"agents":{},"lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0,
         "sessions":{"s1":{"sessionId":"s1","project":"Nook","projectPath":"/p","agentName":"Radion",
         "startedAt":"2026-06-01T10:00:00Z","lastActivityAt":"2026-06-01T11:00:00Z","inputTokens":100,"outputTokens":200,"totalBits":3.5}}}
        """
        let state = try decode(json)
        XCTAssertEqual(state.sessions["s1"]?.project, "Nook")
        XCTAssertEqual(state.sessions["s1"]?.totalTokens, 300)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter LedgerStateDecodeTests`
Expected: FAIL — `LedgerState` has no member `sessions` (compile error).

- [ ] **Step 3: Add `SessionRecord` and the `sessions` field**

In `Sources/NookDaemon/Models.swift`, add the new struct after `TokenEvent`:

```swift
struct SessionRecord: Codable, Equatable {
    let sessionId: String
    var project: String
    let projectPath: String
    var agentName: String?
    let startedAt: Date
    var lastActivityAt: Date
    var inputTokens: Int
    var outputTokens: Int
    var totalBits: Double

    var totalTokens: Int { inputTokens + outputTokens }
    var duration: TimeInterval { lastActivityAt.timeIntervalSince(startedAt) }
}
```

In the same file, add `sessions` to `LedgerState`: add the stored property, the memberwise-init parameter (with a default so existing call sites keep working), the `.empty` value, and the back-compat decode line.

```swift
struct LedgerState: Codable {
    var totalBits: Double
    var pendingBits: Double
    var agents: [String: AgentRecord]
    var lastUpdated: Date
    var recentEvents: [BitEvent]
    var eventSeq: Int
    var sessions: [String: SessionRecord]

    init(totalBits: Double, pendingBits: Double, agents: [String: AgentRecord], lastUpdated: Date, recentEvents: [BitEvent], eventSeq: Int, sessions: [String: SessionRecord] = [:]) {
        self.totalBits = totalBits
        self.pendingBits = pendingBits
        self.agents = agents
        self.lastUpdated = lastUpdated
        self.recentEvents = recentEvents
        self.eventSeq = eventSeq
        self.sessions = sessions
    }

    static var empty: LedgerState {
        LedgerState(totalBits: 0, pendingBits: 0, agents: [:], lastUpdated: Date(), recentEvents: [], eventSeq: 0)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalBits = try c.decode(Double.self, forKey: .totalBits)
        pendingBits = try c.decode(Double.self, forKey: .pendingBits)
        agents = try c.decode([String: AgentRecord].self, forKey: .agents)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        recentEvents = (try? c.decode([BitEvent].self, forKey: .recentEvents)) ?? []
        eventSeq = (try? c.decode(Int.self, forKey: .eventSeq)) ?? 0
        sessions = (try? c.decode([String: SessionRecord].self, forKey: .sessions)) ?? [:]
    }
}
```

> Note: the existing `LedgerState` declares some fields as `let`. Change `agents`, `lastUpdated`, `recentEvents`, `eventSeq` to `var` only if the compiler complains; in the daemon they were already `var`. Keep `sessions` as `var` (it is upserted).

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter LedgerStateDecodeTests`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/NookDaemon/Models.swift Tests/NookTests/LedgerStateDecodeTests.swift
git commit -m "feat(daemon): add SessionRecord and backward-compatible sessions store"
```

---

## Task 2: Daemon — parser extracts real timestamp + cwd

**Files:**
- Modify: `Sources/NookDaemon/TranscriptParser.swift`
- Test: `Tests/NookTests/TranscriptParserTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/NookTests/TranscriptParserTests.swift` (create the file if it does not exist; if it exists, append the methods inside the existing `final class TranscriptParserTests: XCTestCase {`):

```swift
import XCTest
@testable import NookDaemon

final class TranscriptParserTests: XCTestCase {
    func test_parses_tokens_real_timestamp_and_cwd() throws {
        let line = """
        {"cwd":"/Users/me/Code/Nook","timestamp":"2026-06-01T10:30:00Z","message":{"usage":{"input_tokens":120,"output_tokens":340}}}
        """
        let entry = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertEqual(entry.inputTokens, 120)
        XCTAssertEqual(entry.outputTokens, 340)
        XCTAssertEqual(entry.cwd, "/Users/me/Code/Nook")
        let expected = ISO8601DateFormatter().date(from: "2026-06-01T10:30:00Z")
        XCTAssertEqual(entry.timestamp, expected)
    }

    func test_missing_timestamp_falls_back_to_now() throws {
        let line = """
        {"message":{"usage":{"input_tokens":1,"output_tokens":1}}}
        """
        let before = Date()
        let entry = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertNil(entry.cwd)
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
    }

    func test_line_without_usage_returns_nil() {
        XCTAssertNil(TranscriptParser.parseLine("{}"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TranscriptParserTests`
Expected: FAIL — `parseLine` returns `TokenEvent?`, which has no `cwd`; compile error.

- [ ] **Step 3: Change `parseLine` to return a `ParsedEntry`**

Replace the contents of `Sources/NookDaemon/TranscriptParser.swift`:

```swift
import Foundation

struct ParsedEntry {
    let inputTokens: Int
    let outputTokens: Int
    let timestamp: Date
    let cwd: String?
}

enum TranscriptParser {
    private static let iso = ISO8601DateFormatter()

    private struct RawLine: Decodable {
        let cwd: String?
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
            let usage: Usage?
        }

        struct Usage: Decodable {
            let input_tokens: Int
            let output_tokens: Int
        }
    }

    static func parseLine(_ line: String) -> ParsedEntry? {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawLine.self, from: data),
              let usage = raw.message?.usage
        else { return nil }

        let timestamp = raw.timestamp.flatMap { iso.date(from: $0) } ?? Date()

        return ParsedEntry(
            inputTokens: usage.input_tokens,
            outputTokens: usage.output_tokens,
            timestamp: timestamp,
            cwd: raw.cwd
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter TranscriptParserTests`
Expected: PASS. (The build of `ClaudeWatcher` will break — fixed in Task 3. If you need a green build between tasks, do Tasks 2 and 3 back-to-back before running the full suite.)

- [ ] **Step 5: Commit**

```bash
git add Sources/NookDaemon/TranscriptParser.swift Tests/NookTests/TranscriptParserTests.swift
git commit -m "feat(daemon): parse real entry timestamp and cwd"
```

---

## Task 3: Daemon — thread sessionId + upsert SessionRecord

**Files:**
- Modify: `Sources/NookDaemon/Models.swift` (extend `TokenEvent`)
- Modify: `Sources/NookDaemon/ClaudeWatcher.swift`
- Modify: `Sources/NookDaemon/Ledger.swift`
- Test: `Tests/NookTests/LedgerTests.swift`

- [ ] **Step 1: Extend `TokenEvent` with `sessionId` and `cwd`**

In `Sources/NookDaemon/Models.swift`, replace the `TokenEvent` struct:

```swift
struct TokenEvent {
    let sessionId: String
    let projectPath: String
    let cwd: String?
    let inputTokens: Int
    let outputTokens: Int
    let timestamp: Date

    var bits: Double {
        Double(inputTokens) / 1000.0 * 5.0 +
        Double(outputTokens) / 1000.0 * 15.0
    }
}
```

- [ ] **Step 2: Write the failing Ledger upsert test**

Add to `Tests/NookTests/LedgerTests.swift` (inside the existing `final class LedgerTests: XCTestCase {`):

```swift
    func test_apply_creates_session_record_on_first_event() {
        var state = LedgerState.empty
        let event = TokenEvent(sessionId: "s1", projectPath: "/p", cwd: "/Users/me/Code/Nook",
                               inputTokens: 100, outputTokens: 200, timestamp: date("2026-06-01T10:00:00Z"))
        ledger.apply(event: event, agentName: "Radion", to: &state)

        let s = state.sessions["s1"]
        XCTAssertEqual(s?.project, "Nook")
        XCTAssertEqual(s?.agentName, "Radion")
        XCTAssertEqual(s?.totalTokens, 300)
        XCTAssertEqual(s?.startedAt, date("2026-06-01T10:00:00Z"))
        XCTAssertEqual(s?.lastActivityAt, date("2026-06-01T10:00:00Z"))
    }

    func test_apply_updates_session_record_on_subsequent_event() {
        var state = LedgerState.empty
        let e1 = TokenEvent(sessionId: "s1", projectPath: "/p", cwd: "/Users/me/Code/Nook",
                            inputTokens: 100, outputTokens: 200, timestamp: date("2026-06-01T10:00:00Z"))
        let e2 = TokenEvent(sessionId: "s1", projectPath: "/p", cwd: "/Users/me/Code/Nook",
                            inputTokens: 50, outputTokens: 50, timestamp: date("2026-06-01T11:00:00Z"))
        ledger.apply(event: e1, agentName: "Radion", to: &state)
        ledger.apply(event: e2, agentName: "Radion", to: &state)

        let s = state.sessions["s1"]
        XCTAssertEqual(s?.totalTokens, 400)
        XCTAssertEqual(s?.startedAt, date("2026-06-01T10:00:00Z"))
        XCTAssertEqual(s?.lastActivityAt, date("2026-06-01T11:00:00Z"))
        XCTAssertEqual(state.sessions.count, 1)
    }

    func test_apply_separate_session_ids_create_separate_records() {
        var state = LedgerState.empty
        let e1 = TokenEvent(sessionId: "s1", projectPath: "/p", cwd: "/c/Nook",
                            inputTokens: 100, outputTokens: 0, timestamp: date("2026-06-01T10:00:00Z"))
        let e2 = TokenEvent(sessionId: "s2", projectPath: "/p", cwd: "/c/Nook",
                            inputTokens: 100, outputTokens: 0, timestamp: date("2026-06-01T10:00:00Z"))
        ledger.apply(event: e1, agentName: "Radion", to: &state)
        ledger.apply(event: e2, agentName: "Radion", to: &state)
        XCTAssertEqual(state.sessions.count, 2)
    }
```

Add this date helper inside the same class if `LedgerTests` does not already have one:

```swift
    private func date(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter LedgerTests`
Expected: FAIL — `TokenEvent` initializer signature changed / `state.sessions` upsert not implemented.

- [ ] **Step 4: Implement the upsert in `Ledger.apply`**

In `Sources/NookDaemon/Ledger.swift`, inside `apply(event:agentName:to:)`, after the existing `AgentRecord` block and before `state.eventSeq += 1`, insert:

```swift
        let project = event.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? URL(fileURLWithPath: event.projectPath).lastPathComponent
        if var session = state.sessions[event.sessionId] {
            session.lastActivityAt = event.timestamp
            session.inputTokens += event.inputTokens
            session.outputTokens += event.outputTokens
            session.totalBits += bits
            session.agentName = agentName
            state.sessions[event.sessionId] = session
        } else {
            state.sessions[event.sessionId] = SessionRecord(
                sessionId: event.sessionId,
                project: project,
                projectPath: event.projectPath,
                agentName: agentName,
                startedAt: event.timestamp,
                lastActivityAt: event.timestamp,
                inputTokens: event.inputTokens,
                outputTokens: event.outputTokens,
                totalBits: bits
            )
        }
```

> The existing early `guard bits > 0 else { return }` at the top of `apply` already skips zero-token events before this block — that is intended (sessions only accrue real activity).

- [ ] **Step 5: Build the full TokenEvent in `ClaudeWatcher`**

In `Sources/NookDaemon/ClaudeWatcher.swift`, replace the body of `readNewLines(in:projectPath:agentName:)` loop so it derives `sessionId` from the file name and constructs the new `TokenEvent`. Replace the `for line in ...` loop:

```swift
        let sessionId = file.deletingPathExtension().lastPathComponent
        let content = String(data: data, encoding: .utf8) ?? ""
        var lastUsage: (Int, Int)? = nil
        for line in content.components(separatedBy: "\n") {
            guard let parsed = TranscriptParser.parseLine(line) else { continue }
            let pair = (parsed.inputTokens, parsed.outputTokens)
            // Skip zero-token streaming deltas and consecutive duplicate entries
            guard pair.0 > 0 || pair.1 > 0 else { continue }
            guard lastUsage.map({ $0 != pair }) ?? true else { continue }
            lastUsage = pair
            let event = TokenEvent(
                sessionId: sessionId,
                projectPath: projectPath,
                cwd: parsed.cwd,
                inputTokens: parsed.inputTokens,
                outputTokens: parsed.outputTokens,
                timestamp: parsed.timestamp
            )
            onEvent(event, agentName)
        }
```

- [ ] **Step 6: Run the daemon test suite to verify it passes**

Run: `swift test`
Expected: PASS — all `NookTests`, including the new `LedgerTests` cases, and the daemon builds cleanly.

- [ ] **Step 7: Commit**

```bash
git add Sources/NookDaemon/Models.swift Sources/NookDaemon/ClaudeWatcher.swift Sources/NookDaemon/Ledger.swift Tests/NookTests/LedgerTests.swift
git commit -m "feat(daemon): record per-session history into the ledger"
```

---

## Task 4: App — mirror SessionRecord + expose sessions from VillageEngine

**Files:**
- Modify: `Sources/NookApp/LedgerModels.swift`
- Modify: `Sources/NookApp/VillageEngine.swift`
- Test: `Tests/NookAppTests/LedgerStateAppDecodeTests.swift`

- [ ] **Step 1: Write the failing app-side decode test**

Create `Tests/NookAppTests/LedgerStateAppDecodeTests.swift`:

```swift
import XCTest
@testable import Nook

final class LedgerStateAppDecodeTests: XCTestCase {
    func test_decodes_sessions_and_defaults_when_absent() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let legacy = """
        {"totalBits":0,"pendingBits":0,"agents":{},"lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0}
        """
        XCTAssertTrue(try decoder.decode(LedgerState.self, from: Data(legacy.utf8)).sessions.isEmpty)

        let withSessions = """
        {"totalBits":0,"pendingBits":0,"agents":{},"lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0,
         "sessions":{"s1":{"sessionId":"s1","project":"Nook","projectPath":"/p","agentName":"Radion",
         "startedAt":"2026-06-01T10:00:00Z","lastActivityAt":"2026-06-01T11:00:00Z","inputTokens":100,"outputTokens":200,"totalBits":3.5}}}
        """
        let state = try decoder.decode(LedgerState.self, from: Data(withSessions.utf8))
        XCTAssertEqual(state.sessions["s1"]?.totalTokens, 300)
        XCTAssertEqual(state.sessions["s1"]?.agentName, "Radion")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' -only-testing:NookAppTests/LedgerStateAppDecodeTests`
Expected: FAIL — app `LedgerState` has no `sessions`.

- [ ] **Step 3: Mirror `SessionRecord` and add `sessions` (app side)**

In `Sources/NookApp/LedgerModels.swift`, add after `TokenEvent`:

```swift
struct SessionRecord: Codable, Equatable {
    let sessionId: String
    let project: String
    let projectPath: String
    let agentName: String?
    let startedAt: Date
    let lastActivityAt: Date
    let inputTokens: Int
    let outputTokens: Int
    let totalBits: Double

    var totalTokens: Int { inputTokens + outputTokens }
    var duration: TimeInterval { lastActivityAt.timeIntervalSince(startedAt) }
}
```

In the same file, add `sessions` to the app `LedgerState`: stored property, memberwise-init param (default `[:]`), `.empty`, and the decode line.

```swift
struct LedgerState: Codable {
    let totalBits: Double
    var pendingBits: Double
    let agents: [String: AgentRecord]
    let lastUpdated: Date
    let recentEvents: [BitEvent]
    let eventSeq: Int
    let sessions: [String: SessionRecord]

    init(totalBits: Double, pendingBits: Double, agents: [String: AgentRecord], lastUpdated: Date, recentEvents: [BitEvent], eventSeq: Int, sessions: [String: SessionRecord] = [:]) {
        self.totalBits = totalBits
        self.pendingBits = pendingBits
        self.agents = agents
        self.lastUpdated = lastUpdated
        self.recentEvents = recentEvents
        self.eventSeq = eventSeq
        self.sessions = sessions
    }

    static var empty: LedgerState {
        LedgerState(totalBits: 0, pendingBits: 0, agents: [:], lastUpdated: Date(), recentEvents: [], eventSeq: 0)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalBits = try c.decode(Double.self, forKey: .totalBits)
        pendingBits = try c.decode(Double.self, forKey: .pendingBits)
        agents = try c.decode([String: AgentRecord].self, forKey: .agents)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        recentEvents = (try? c.decode([BitEvent].self, forKey: .recentEvents)) ?? []
        eventSeq = (try? c.decode(Int.self, forKey: .eventSeq)) ?? 0
        sessions = (try? c.decode([String: SessionRecord].self, forKey: .sessions)) ?? [:]
    }
}
```

- [ ] **Step 4: Expose `sessions` from `VillageEngine`**

In `Sources/NookApp/VillageEngine.swift`, add the stored property next to `agents`:

```swift
    private(set) var sessions: [String: SessionRecord] = [:]
```

In `reload()`, after `agents = state.agents`, add:

```swift
        sessions = state.sessions
```

> Correctness note: the app rewrites `ledger.json` in `consumePendingBits()`. Because
> `sessions` is now a stored `Codable` property, the synthesized encoder includes it on
> rewrite, so the app does not clobber the daemon's session data.

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' -only-testing:NookAppTests/LedgerStateAppDecodeTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/NookApp/LedgerModels.swift Sources/NookApp/VillageEngine.swift Tests/NookAppTests/LedgerStateAppDecodeTests.swift
git commit -m "feat(app): decode sessions and expose them from VillageEngine"
```

---

## Task 5: App — ProjectRollup pure helper

**Files:**
- Create: `Sources/NookApp/ProjectRollup.swift`
- Test: `Tests/NookAppTests/ProjectRollupTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/NookAppTests/ProjectRollupTests.swift`:

```swift
import XCTest
@testable import Nook

final class ProjectRollupTests: XCTestCase {
    private func session(_ id: String, project: String, path: String, tokens: Int, at: String) -> SessionRecord {
        SessionRecord(sessionId: id, project: project, projectPath: path, agentName: "Radion",
                      startedAt: iso(at), lastActivityAt: iso(at), inputTokens: tokens, outputTokens: 0, totalBits: 0)
    }
    private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func test_groups_by_project_path_and_sorts_by_tokens_desc() {
        let sessions = [
            session("a", project: "Nook", path: "/n", tokens: 100, at: "2026-06-01T10:00:00Z"),
            session("b", project: "Radion", path: "/r", tokens: 500, at: "2026-06-02T10:00:00Z"),
            session("c", project: "Nook", path: "/n", tokens: 50, at: "2026-06-03T10:00:00Z"),
        ]
        let rollups = ProjectRollup.forAgent(sessions)
        XCTAssertEqual(rollups.map(\.project), ["Radion", "Nook"])
        XCTAssertEqual(rollups[1].totalTokens, 150)
        XCTAssertEqual(rollups[1].sessionCount, 2)
        XCTAssertEqual(rollups[1].firstSeen, iso("2026-06-01T10:00:00Z"))
        XCTAssertEqual(rollups[1].lastSeen, iso("2026-06-03T10:00:00Z"))
    }

    func test_empty_sessions_produce_no_rollups() {
        XCTAssertTrue(ProjectRollup.forAgent([]).isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' -only-testing:NookAppTests/ProjectRollupTests`
Expected: FAIL — `ProjectRollup` undefined.

- [ ] **Step 3: Implement `ProjectRollup`**

Create `Sources/NookApp/ProjectRollup.swift`:

```swift
import Foundation

struct ProjectRollup: Equatable {
    let project: String
    let projectPath: String
    let totalTokens: Int
    let sessionCount: Int
    let firstSeen: Date
    let lastSeen: Date

    static func forAgent(_ sessions: [SessionRecord]) -> [ProjectRollup] {
        let groups = Dictionary(grouping: sessions, by: { $0.projectPath })
        return groups.compactMap { _, group -> ProjectRollup? in
            guard let first = group.first else { return nil }
            return ProjectRollup(
                project: first.project,
                projectPath: first.projectPath,
                totalTokens: group.reduce(0) { $0 + $1.totalTokens },
                sessionCount: group.count,
                firstSeen: group.map(\.startedAt).min() ?? first.startedAt,
                lastSeen: group.map(\.lastActivityAt).max() ?? first.lastActivityAt
            )
        }
        .sorted { $0.totalTokens > $1.totalTokens }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' -only-testing:NookAppTests/ProjectRollupTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NookApp/ProjectRollup.swift Tests/NookAppTests/ProjectRollupTests.swift
git commit -m "feat(app): add ProjectRollup history helper"
```

---

## Task 6: App — Moment helper (anchors)

**Files:**
- Create: `Sources/NookApp/Moment.swift`
- Test: `Tests/NookAppTests/MomentTests.swift`

This task implements the **anchor** moments only: first session, first day on a project, bond promotion. (Anniversary and all *living* moments come in Task 7.)

- [ ] **Step 1: Write the failing anchor tests**

Create `Tests/NookAppTests/MomentTests.swift`:

```swift
import XCTest
@testable import Nook

final class MomentTests: XCTestCase {
    func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func session(_ id: String, project: String = "Nook", path: String = "/n",
                 input: Int = 0, output: Int = 0, start: String, end: String? = nil) -> SessionRecord {
        SessionRecord(sessionId: id, project: project, projectPath: path, agentName: "Radion",
                      startedAt: iso(start), lastActivityAt: iso(end ?? start),
                      inputTokens: input, outputTokens: output, totalBits: 0)
    }

    func kinds(_ moments: [Moment]) -> [Moment.Kind] { moments.map(\.kind) }

    func test_first_session_moment() {
        let s = [session("a", start: "2026-06-01T10:00:00Z")]
        let moments = Moment.forAgent(s, now: iso("2026-06-02T10:00:00Z"))
        XCTAssertTrue(kinds(moments).contains(.firstSession))
    }

    func test_first_day_on_each_project() {
        let s = [
            session("a", project: "Nook", path: "/n", start: "2026-06-01T10:00:00Z"),
            session("b", project: "Radion", path: "/r", start: "2026-06-02T10:00:00Z"),
            session("c", project: "Nook", path: "/n", start: "2026-06-03T10:00:00Z"),
        ]
        let moments = Moment.forAgent(s, now: iso("2026-06-04T10:00:00Z"))
        XCTAssertTrue(kinds(moments).contains(.firstOnProject("Nook")))
        XCTAssertTrue(kinds(moments).contains(.firstOnProject("Radion")))
        // Only one "first on Nook" even though Nook has two sessions
        XCTAssertEqual(kinds(moments).filter { $0 == .firstOnProject("Nook") }.count, 1)
    }

    func test_bond_promotion_on_crossing_session() {
        // cumulative tokens: 6k, then +6k = 12k crosses the 10k bond-2 threshold
        let s = [
            session("a", input: 6_000, start: "2026-06-01T10:00:00Z"),
            session("b", input: 6_000, start: "2026-06-02T10:00:00Z"),
        ]
        let moments = Moment.forAgent(s, now: iso("2026-06-03T10:00:00Z"))
        XCTAssertTrue(kinds(moments).contains(.bondPromotion(level: 2)))
    }

    func test_moments_sorted_chronologically() {
        let s = [
            session("a", input: 6_000, start: "2026-06-01T10:00:00Z"),
            session("b", input: 6_000, start: "2026-06-02T10:00:00Z"),
        ]
        let dates = Moment.forAgent(s, now: iso("2026-06-03T10:00:00Z")).map(\.date)
        XCTAssertEqual(dates, dates.sorted())
    }

    func test_anniversary_near_date() {
        let s = [session("a", start: "2025-06-01T10:00:00Z")]
        // now = one day after the 1-year anniversary
        let k = kinds(Moment.forAgent(s, now: iso("2026-06-02T10:00:00Z")))
        XCTAssertTrue(k.contains(.anniversary(years: 1)))
    }

    func test_no_anniversary_far_from_date() {
        let s = [session("a", start: "2025-06-01T10:00:00Z")]
        let k = kinds(Moment.forAgent(s, now: iso("2026-09-01T10:00:00Z")))
        XCTAssertFalse(k.contains { if case .anniversary = $0 { return true } else { return false } })
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' -only-testing:NookAppTests/MomentTests`
Expected: FAIL — `Moment` undefined.

- [ ] **Step 3: Implement `Moment` with the anchor detectors**

Create `Sources/NookApp/Moment.swift`:

```swift
import Foundation

struct Moment: Equatable {
    enum Kind: Equatable {
        case firstSession
        case firstOnProject(String)
        case anniversary(years: Int)
        case bondPromotion(level: Int)
        case streakRecord(days: Int)
        case tokenMilestone(Int)
        case sessionMilestone(Int)
        case hoursMilestone(Int)
        case longestSession(seconds: TimeInterval)
        case biggestSession(tokens: Int)
        case mostProductiveDay(tokens: Int)
        case nightSession
        case returnAfterAbsence(days: Int)
    }

    let kind: Kind
    let date: Date
    let label: String

    // Bond thresholds shared with BondProgress / the daemon.
    static let bondThresholds: [(level: Int, tokens: Int)] =
        [(2, 10_000), (3, 50_000), (4, 200_000), (5, 1_000_000)]

    static func forAgent(_ sessions: [SessionRecord], now: Date = Date(),
                         calendar: Calendar = .current) -> [Moment] {
        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }
        guard !ordered.isEmpty else { return [] }

        var moments: [Moment] = []
        moments += anchorMoments(ordered, now: now, calendar: calendar)
        // Task 7 appends living moments here.
        return moments.sorted { $0.date < $1.date }
    }

    private static func anchorMoments(_ ordered: [SessionRecord], now: Date,
                                      calendar: Calendar) -> [Moment] {
        var out: [Moment] = []

        // First session ever.
        if let first = ordered.first {
            out.append(Moment(kind: .firstSession, date: first.startedAt,
                              label: "First session together"))
        }

        // First session on each project (earliest per projectPath).
        var seenProjects = Set<String>()
        for s in ordered where !seenProjects.contains(s.projectPath) {
            seenProjects.insert(s.projectPath)
            out.append(Moment(kind: .firstOnProject(s.project), date: s.startedAt,
                              label: "First day on \(s.project)"))
        }

        // Bond promotions: replay cumulative tokens, flag the crossing session.
        var cumulative = 0
        var awarded = Set<Int>()
        for s in ordered {
            cumulative += s.totalTokens
            for t in bondThresholds where cumulative >= t.tokens && !awarded.contains(t.level) {
                awarded.insert(t.level)
                out.append(Moment(kind: .bondPromotion(level: t.level), date: s.lastActivityAt,
                                  label: "Bond \(t.level) reached"))
            }
        }

        // Anniversary: emitted only within ±3 days of the yearly anniversary of the first session.
        if let first = ordered.first {
            let years = calendar.dateComponents([.year], from: first.startedAt, to: now).year ?? 0
            if years >= 1,
               let anniversary = calendar.date(byAdding: .year, value: years, to: first.startedAt) {
                let daysAway = abs(calendar.dateComponents([.day], from: now, to: anniversary).day ?? 99)
                if daysAway <= 3 {
                    out.append(Moment(kind: .anniversary(years: years), date: anniversary,
                                      label: "\(years) year\(years == 1 ? "" : "s") together"))
                }
            }
        }
        return out
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' -only-testing:NookAppTests/MomentTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NookApp/Moment.swift Tests/NookAppTests/MomentTests.swift
git commit -m "feat(app): add Moment anchor detectors"
```

---

## Task 7: App — Moment living detectors + summary

**Files:**
- Modify: `Sources/NookApp/Moment.swift`
- Modify: `Tests/NookAppTests/MomentTests.swift`

Implements the living moments (streak record, token/session/hours milestones, longest/biggest/most-productive records, night session, return-after-absence), the Bond/token-milestone de-duplication, and a `MomentSummary` for the inspector "live strip".

- [ ] **Step 1: Write the failing living-moment tests**

Append these methods to `MomentTests` in `Tests/NookAppTests/MomentTests.swift`:

```swift
    func test_token_milestone_does_not_duplicate_bond_at_1M() {
        // 1.2M tokens crosses both bond level 5 and the 1M token milestone — expect bond only.
        let s = [session("a", input: 1_200_000, start: "2026-06-01T10:00:00Z")]
        let k = kinds(Moment.forAgent(s, now: iso("2026-06-02T10:00:00Z")))
        XCTAssertTrue(k.contains(.bondPromotion(level: 5)))
        XCTAssertFalse(k.contains(.tokenMilestone(1_000_000)))
        // 100k milestone (no bond there) still emitted
        XCTAssertTrue(k.contains(.tokenMilestone(100_000)))
    }

    func test_session_count_milestone_at_ten() {
        let s = (1...10).map { session("s\($0)", input: 10, start: "2026-06-\(String(format: "%02d", $0))T10:00:00Z") }
        let k = kinds(Moment.forAgent(s, now: iso("2026-07-01T10:00:00Z")))
        XCTAssertTrue(k.contains(.sessionMilestone(10)))
    }

    func test_longest_session_record() {
        let s = [
            session("a", start: "2026-06-01T10:00:00Z", end: "2026-06-01T10:30:00Z"),
            session("b", start: "2026-06-02T10:00:00Z", end: "2026-06-02T14:00:00Z"), // 4h
        ]
        let k = kinds(Moment.forAgent(s, now: iso("2026-06-03T10:00:00Z")))
        XCTAssertTrue(k.contains(.longestSession(seconds: 4 * 3600)))
    }

    func test_night_session_detected() {
        let s = [session("a", start: "2026-06-01T02:30:00Z", end: "2026-06-01T03:00:00Z")] // 02:30 local-ish
        // Force a UTC calendar so the fixture's hour is the local hour under test.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let k = Moment.forAgent(s, now: iso("2026-06-02T10:00:00Z"), calendar: cal).map(\.kind)
        XCTAssertTrue(k.contains(.nightSession))
    }

    func test_return_after_absence() {
        let s = [
            session("a", input: 10, start: "2026-06-01T10:00:00Z"),
            session("b", input: 10, start: "2026-06-20T10:00:00Z"), // 19 days later
        ]
        let k = kinds(Moment.forAgent(s, now: iso("2026-06-21T10:00:00Z")))
        XCTAssertTrue(k.contains(.returnAfterAbsence(days: 19)))
    }

    func test_summary_current_streak_and_longest() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let s = [
            session("a", start: "2026-06-01T10:00:00Z", end: "2026-06-01T11:00:00Z"),
            session("b", start: "2026-06-02T10:00:00Z", end: "2026-06-02T10:30:00Z"),
        ]
        let summary = Moment.summary(s, now: iso("2026-06-02T20:00:00Z"), calendar: cal)
        XCTAssertEqual(summary.currentStreakDays, 2)
        XCTAssertEqual(summary.longestSessionSeconds, 3600)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' -only-testing:NookAppTests/MomentTests`
Expected: FAIL — living detectors / `summary` not implemented; `tokenMilestone` not emitted.

- [ ] **Step 3: Add the living detectors and `MomentSummary`**

In `Sources/NookApp/Moment.swift`, add the milestone constants and the `MomentSummary` struct at file scope:

```swift
struct MomentSummary: Equatable {
    let currentStreakDays: Int
    let longestSessionSeconds: TimeInterval
}

extension Moment {
    static let tokenMilestones = [100_000, 250_000, 500_000, 1_000_000]
    static let sessionMilestones = [10, 50, 100]
    static let hoursMilestones = [10, 50, 100]
}
```

Replace the `forAgent` body's comment line `// Task 7 appends living moments here.` with `moments += livingMoments(ordered, now: now, calendar: calendar)`, then add the implementations inside `struct Moment`:

```swift
    private static func livingMoments(_ ordered: [SessionRecord], now: Date,
                                      calendar: Calendar) -> [Moment] {
        var out: [Moment] = []
        let bondTokenSet = Set(bondThresholds.map(\.tokens))

        // Cumulative token milestones (skip any that coincide with a bond threshold).
        var cumulative = 0
        var tokenAwarded = Set<Int>()
        var sessionIndex = 0
        for s in ordered {
            cumulative += s.totalTokens
            sessionIndex += 1
            for m in tokenMilestones where cumulative >= m && !tokenAwarded.contains(m) && !bondTokenSet.contains(m) {
                tokenAwarded.insert(m)
                out.append(Moment(kind: .tokenMilestone(m), date: s.lastActivityAt,
                                  label: "\(formatTokens(m)) tokens together"))
            }
            if sessionMilestones.contains(sessionIndex) {
                out.append(Moment(kind: .sessionMilestone(sessionIndex), date: s.startedAt,
                                  label: "\(sessionIndex)th session together"))
            }
        }

        // Cumulative hours milestones.
        var cumulativeSeconds: TimeInterval = 0
        var hoursAwarded = Set<Int>()
        for s in ordered {
            cumulativeSeconds += max(0, s.duration)
            let hours = Int(cumulativeSeconds / 3600)
            for h in hoursMilestones where hours >= h && !hoursAwarded.contains(h) {
                hoursAwarded.insert(h)
                out.append(Moment(kind: .hoursMilestone(h), date: s.lastActivityAt,
                                  label: "\(h)h together"))
            }
        }

        // Beatable records (emit one moment for the record holder).
        if let longest = ordered.max(by: { $0.duration < $1.duration }), longest.duration > 0 {
            out.append(Moment(kind: .longestSession(seconds: longest.duration), date: longest.lastActivityAt,
                              label: "Longest session · \(formatDuration(longest.duration))"))
        }
        if let biggest = ordered.max(by: { $0.totalTokens < $1.totalTokens }), biggest.totalTokens > 0 {
            out.append(Moment(kind: .biggestSession(tokens: biggest.totalTokens), date: biggest.lastActivityAt,
                              label: "Biggest session · \(formatTokens(biggest.totalTokens))"))
        }
        let byDay = Dictionary(grouping: ordered) { calendar.startOfDay(for: $0.startedAt) }
        if let best = byDay.map({ (day: $0.key, tokens: $0.value.reduce(0) { $0 + $1.totalTokens }) })
            .max(by: { $0.tokens < $1.tokens }), best.tokens > 0 {
            out.append(Moment(kind: .mostProductiveDay(tokens: best.tokens), date: best.day,
                              label: "Most productive day · \(formatTokens(best.tokens))"))
        }

        // Streak record (longest run of consecutive local days with a session).
        let record = longestStreak(ordered, calendar: calendar)
        if record >= 2, let lastDayStart = ordered.map({ calendar.startOfDay(for: $0.startedAt) }).max() {
            out.append(Moment(kind: .streakRecord(days: record), date: lastDayStart,
                              label: "\(record)-day streak"))
        }

        // Night sessions (active between 00:00 and 05:00 local).
        for s in ordered {
            let hour = calendar.component(.hour, from: s.startedAt)
            if hour >= 0 && hour < 5 {
                out.append(Moment(kind: .nightSession, date: s.startedAt, label: "Late-night session"))
            }
        }

        // Return after absence (>= 14 days gap between consecutive sessions).
        for (prev, next) in zip(ordered, ordered.dropFirst()) {
            let gapDays = calendar.dateComponents([.day], from: prev.startedAt, to: next.startedAt).day ?? 0
            if gapDays >= 14 {
                out.append(Moment(kind: .returnAfterAbsence(days: gapDays), date: next.startedAt,
                                  label: "Back after \(gapDays) days"))
            }
        }

        return out
    }

    static func summary(_ sessions: [SessionRecord], now: Date = Date(),
                        calendar: Calendar = .current) -> MomentSummary {
        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }
        let longest = ordered.map(\.duration).max() ?? 0
        return MomentSummary(
            currentStreakDays: currentStreak(ordered, now: now, calendar: calendar),
            longestSessionSeconds: max(0, longest)
        )
    }

    // MARK: - Streak math

    private static func dayStarts(_ sessions: [SessionRecord], calendar: Calendar) -> [Date] {
        Array(Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })).sorted()
    }

    private static func longestStreak(_ sessions: [SessionRecord], calendar: Calendar) -> Int {
        let days = dayStarts(sessions, calendar: calendar)
        guard !days.isEmpty else { return 0 }
        var best = 1, run = 1
        for (prev, next) in zip(days, days.dropFirst()) {
            if calendar.dateComponents([.day], from: prev, to: next).day == 1 { run += 1 }
            else { run = 1 }
            best = max(best, run)
        }
        return best
    }

    private static func currentStreak(_ sessions: [SessionRecord], now: Date, calendar: Calendar) -> Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        guard !days.isEmpty else { return 0 }
        // A streak is "current" if it includes today or yesterday.
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(yesterday)
            else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    // MARK: - Formatting

    private static func formatTokens(_ v: Int) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
        if v >= 1_000 { return "\(v / 1_000)k" }
        return "\(v)"
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m)m"
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' -only-testing:NookAppTests/MomentTests`
Expected: PASS (all anchor + living tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/NookApp/Moment.swift Tests/NookAppTests/MomentTests.swift
git commit -m "feat(app): add living Moment detectors and summary"
```

---

## Task 8: App — enriched NPCSelection + packed derivation

**Files:**
- Modify: `Sources/NookApp/NPCSelection.swift`
- Modify: `Sources/NookApp/NPCManager.swift`

- [ ] **Step 1: Extend `NPCSelection`**

Replace `Sources/NookApp/NPCSelection.swift`:

```swift
import Foundation

struct NPCSelection: Equatable {
    let id: String
    let name: String
    let bond: Int
    let totalTokens: Int
    let totalBits: Double
    let activeSessionCount: Int
    let trait: NPCWorkTrait

    // History (Task 8)
    let projects: [ProjectRollup]
    let recentSessions: [SessionRecord]
    let moments: [Moment]
    let currentStreakDays: Int
    let longestSessionSeconds: TimeInterval
}
```

- [ ] **Step 2: Pack derived history in `NPCManager.selection(for:)`**

In `Sources/NookApp/NPCManager.swift`, replace `selection(for:)`:

```swift
    func selection(for id: String) -> NPCSelection? {
        guard let model = models[id] else { return nil }
        let visualState = NPCVisualState.derive(
            from: model,
            activeSessionCount: engine.activeSessionCounts[id, default: 0],
            dayPhase: engine.dayPhase
        )

        let agentSessions = engine.sessions.values.filter { $0.agentName == id }
        let projects = ProjectRollup.forAgent(Array(agentSessions))
        let recent = agentSessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
        let moments = Moment.forAgent(Array(agentSessions))
        let summary = Moment.summary(Array(agentSessions))

        return NPCSelection(
            id: id,
            name: model.name,
            bond: model.bond,
            totalTokens: model.totalTokens,
            totalBits: model.totalBits,
            activeSessionCount: visualState.sessionCount,
            trait: visualState.trait,
            projects: Array(projects.prefix(5)),
            recentSessions: Array(recent.prefix(5)),
            moments: moments,
            currentStreakDays: summary.currentStreakDays,
            longestSessionSeconds: summary.longestSessionSeconds
        )
    }
```

> `engine.sessions` is keyed by `sessionId`; we filter by `agentName == id` because the NPC `id` is the agent name (the same key used in `engine.agents[id]`).

- [ ] **Step 3: Build to catch compile errors**

Run: `xcodebuild build -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Sources/NookApp/NPCSelection.swift Sources/NookApp/NPCManager.swift
git commit -m "feat(app): pack derived history into NPCSelection"
```

---

## Task 9: App — enriched inspector UI

**Files:**
- Modify: `Sources/NookApp/NPCInspectorPanel.swift`

- [ ] **Step 1: Wrap the panel in a ScrollView, widen it, and add history sections**

In `Sources/NookApp/NPCInspectorPanel.swift`, replace the `body` and add the new section views + helpers. Replace `body`:

```swift
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                liveStrip
                statusSection
                statsSection
                progressSection
                if !selection.projects.isEmpty { projectsSection }
                if !selection.recentSessions.isEmpty { recentSessionsSection }
                if !selection.moments.isEmpty { momentsSection }
            }
            .padding(16)
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .frame(width: 340)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.76))
        .overlay(Rectangle().stroke(.white.opacity(0.14), lineWidth: 1))
    }
```

Add these computed views and helpers inside `NPCInspectorPanel` (before the closing brace):

```swift
    private var liveStrip: some View {
        HStack(spacing: 8) {
            if selection.currentStreakDays > 0 {
                badge("🔥 \(selection.currentStreakDays)d")
            }
            if selection.longestSessionSeconds > 0 {
                badge(formatDuration(selection.longestSessionSeconds) + " max")
            }
            badge(formatInt(selection.totalTokens))
            Spacer(minLength: 0)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Projects")
            ForEach(selection.projects, id: \.projectPath) { p in
                HStack {
                    Text(p.project).lineLimit(1)
                    Spacer()
                    Text("\(formatInt(p.totalTokens)) · \(p.sessionCount) sess.")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Recent Sessions")
            ForEach(selection.recentSessions, id: \.sessionId) { s in
                HStack {
                    Text(shortDate(s.startedAt))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(s.project).lineLimit(1)
                    Spacer()
                    Text("\(formatDuration(s.duration)) · \(formatInt(s.totalTokens))")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var momentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Moments")
            ForEach(Array(selection.moments.suffix(5).reversed().enumerated()), id: \.offset) { _, m in
                HStack(alignment: .top, spacing: 6) {
                    Text(icon(for: m.kind))
                    Text(m.label).foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func icon(for kind: Moment.Kind) -> String {
        switch kind {
        case .firstSession, .firstOnProject: return "✨"
        case .anniversary: return "🎂"
        case .bondPromotion: return "💛"
        case .streakRecord: return "🔥"
        case .tokenMilestone, .sessionMilestone, .hoursMilestone: return "🏁"
        case .longestSession, .biggestSession, .mostProductiveDay: return "🏆"
        case .nightSession: return "🌙"
        case .returnAfterAbsence: return "👋"
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m)m"
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Sources/NookApp/NPCInspectorPanel.swift
git commit -m "feat(app): show NPC history in the enriched inspector"
```

---

## Task 10: Final verification

**Files:** none (verification only).

- [ ] **Step 1: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: generation succeeds (picks up `ProjectRollup.swift`, `Moment.swift`, and the new test files).

- [ ] **Step 2: Run the daemon test suite**

Run: `swift test`
Expected: PASS (all `NookTests`).

- [ ] **Step 3: Run the app test suite**

Run: `xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'`
Expected: PASS (BondProgress, ClaudeProjectsWatcher, SessionDetector, LedgerStateAppDecode, ProjectRollup, Moment).

- [ ] **Step 4: Build the app**

Run: `xcodebuild build -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual smoke check**

Launch the app. With at least one agent that has accrued sessions since shipping this feature:
- Clicking the NPC opens the inspector; it scrolls.
- The live strip shows streak / longest / tokens badges.
- Projects, Recent Sessions, and Moments sections render with real data (empty sections are hidden for a brand-new agent).
- New token activity refreshes the panel without closing it (existing `refreshSelection` path).

- [ ] **Step 6: Commit any regenerated project changes**

```bash
git add -f NookApp.xcodeproj/project.pbxproj
git add project.yml
git commit -m "chore: regenerate project for history helpers and tests"
```

---

## Notes for the implementer

- **Two test runners:** daemon logic → `swift test` (target `NookTests`); app logic → `xcodebuild test` (target `NookAppTests`). The app target is `Nook` (`@testable import Nook`).
- **Tasks 2 + 3 are coupled:** Task 2 changes `parseLine`'s return type, which breaks `ClaudeWatcher` until Task 3 Step 5. Run them back-to-back; only Task 3 Step 6 expects a fully green daemon build.
- **Bond/token-milestone de-dup:** the 1,000,000 token milestone is intentionally suppressed because it coincides with Bond 5 (`bondTokenSet`). The 100k/250k/500k milestones have no bond at that exact count and are emitted.
- **Timezone in tests:** streak/night tests inject a UTC `Calendar` so fixture timestamps are deterministic regardless of the machine's local zone. Production uses `.current`.

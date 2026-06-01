# NPC Voice — Subject-Aware Speech Bubbles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** NPCs emit in-world speech bubbles that react to the concrete subject of the active Claude Code session (file opened, task framed, tests run).

**Architecture:** The daemon parses subject signals from the JSONL transcript and, on a *significant change*, appends a `SessionActivityEvent` to `ledger.json` — reusing the existing `BitEvent`/`recentEvents`/`eventSeq` pipeline (now a parallel `recentActivity`/`activitySeq` queue). The app consumes new events (anchored on first load, no replay), turns each into a line via a pure swappable `SpeechLineComposing` (heuristic now, LLM later), and renders a pixel bubble above the NPC with a per-NPC cooldown.

**Tech Stack:** Swift 6, SwiftPM daemon (`NookTests` via `swift test`), XcodeGen + SwiftUI/SpriteKit app (`NookAppTests` via `xcodebuild test`, app target module `Nook`).

**Spec:** `docs/superpowers/specs/2026-06-01-npc-voice-speech-bubbles-design.md`

---

## Conventions for every task

- Branch: `nook-npc-village-graphics` (do NOT switch). Commit at the end of each task.
- New `.swift` files under `Sources/NookApp/` or `Tests/NookAppTests/` are globbed by XcodeGen — after creating one, run `xcodegen generate` BEFORE `xcodebuild test`, and `git add -f NookApp.xcodeproj/project.pbxproj` (it is tracked but under a `*.xcodeproj` ignore rule).
- Ignore SourceKit/IDE "No such module 'XCTest'" / "cannot find type" errors — the authoritative build is `swift test` (daemon) / `xcodebuild test` (app).
- App test filter: `xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' -only-testing:NookAppTests/<Class>`.

---

## File Structure

**Daemon:**
- `Sources/NookDaemon/TranscriptParser.swift` — enriched `ParsedEntry` + `ToolUse`; parse content blocks, role, gitBranch.
- `Sources/NookDaemon/Models.swift` — `SessionRecord` subject fields (+ backward-compat `init(from:)` in extension); `SessionActivityEvent`; `LedgerState.recentActivity` + `activitySeq`.
- `Sources/NookDaemon/Ledger.swift` — `ingestSubject(...)` upsert + emit activity events; `commandSummary` helper.
- `Sources/NookDaemon/ClaudeWatcher.swift` + `Sources/NookDaemon/main.swift` — per-line loop: subject ingest (always) + token emit (when usage); wire `onSubject`.

**App:**
- `Sources/NookApp/LedgerModels.swift` — mirror `SessionRecord` fields, `SessionActivityEvent`, `recentActivity`/`activitySeq`.
- `Sources/NookApp/VillageEngine.swift` — `newActivityEvents` + `lastSeenActivitySeq`.
- `Sources/NookApp/SpeechLineComposer.swift` — `SpeechLineComposing` + `HeuristicLineComposer`.
- `Sources/NookApp/NPCSprite.swift` — `showSpeech(_:)`.
- `Sources/NookApp/NPCManager.swift` — `handleActivityEvents(_:)` cooldown/route/compose.
- `Sources/NookApp/VillageScene.swift` — drain `newActivityEvents` in `update(_:)`.

---

## Task 1: Daemon — enriched transcript parser

**Files:**
- Modify: `Sources/NookDaemon/TranscriptParser.swift`
- Test: `Tests/NookTests/TranscriptParserTests.swift`

- [ ] **Step 1: Add failing tests** (append these methods inside the existing `final class TranscriptParserTests: XCTestCase {`):

```swift
    func test_parses_user_task_text() throws {
        let line = #"{"cwd":"/c/Nook","gitBranch":"main","timestamp":"2026-06-01T10:00:00Z","message":{"role":"user","content":"refactor the auth module"}}"#
        let e = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertEqual(e.role, "user")
        XCTAssertEqual(e.userText, "refactor the auth module")
        XCTAssertEqual(e.gitBranch, "main")
        XCTAssertTrue(e.toolUses.isEmpty)
    }

    func test_user_tool_result_only_has_no_task_text() throws {
        let line = #"{"message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#
        let e = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertEqual(e.role, "user")
        XCTAssertNil(e.userText)
    }

    func test_parses_assistant_tool_uses() throws {
        let line = #"{"timestamp":"2026-06-01T10:05:00Z","message":{"role":"assistant","content":[{"type":"thinking","text":"hmm"},{"type":"tool_use","name":"Edit","input":{"file_path":"/c/Nook/Auth.swift"}},{"type":"tool_use","name":"Bash","input":{"command":"swift test"}}],"usage":{"input_tokens":10,"output_tokens":20}}}"#
        let e = try XCTUnwrap(TranscriptParser.parseLine(line))
        XCTAssertEqual(e.role, "assistant")
        XCTAssertEqual(e.inputTokens, 10)
        XCTAssertEqual(e.outputTokens, 20)
        XCTAssertEqual(e.toolUses.count, 2)
        XCTAssertEqual(e.toolUses[0].name, "Edit")
        XCTAssertEqual(e.toolUses[0].filePath, "/c/Nook/Auth.swift")
        XCTAssertEqual(e.toolUses[1].name, "Bash")
        XCTAssertEqual(e.toolUses[1].command, "swift test")
    }

    func test_non_message_line_returns_nil() {
        XCTAssertNil(TranscriptParser.parseLine(#"{"type":"summary","leafUuid":"x"}"#))
    }
```

(Keep the existing tests; `test_bits_calculation` and timestamp tests still pass since `inputTokens`/`outputTokens`/`timestamp`/`cwd` remain on `ParsedEntry`.)

- [ ] **Step 2: Run tests, verify FAIL**

Run: `swift test --filter TranscriptParserTests`
Expected: FAIL — `ParsedEntry` has no `role`/`userText`/`toolUses`/`gitBranch`.

- [ ] **Step 3: Replace `Sources/NookDaemon/TranscriptParser.swift`:**

```swift
import Foundation

struct ToolUse: Equatable {
    let name: String
    let filePath: String?
    let command: String?
}

struct ParsedEntry {
    let inputTokens: Int
    let outputTokens: Int
    let timestamp: Date
    let cwd: String?
    let gitBranch: String?
    let role: String?
    let userText: String?
    let toolUses: [ToolUse]
}

enum TranscriptParser {
    private struct RawLine: Decodable {
        let cwd: String?
        let gitBranch: String?
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
            let role: String?
            let usage: Usage?
            let content: Content?
        }

        struct Usage: Decodable {
            let input_tokens: Int
            let output_tokens: Int
        }

        struct Block: Decodable {
            let type: String?
            let text: String?
            let name: String?
            let input: Input?
        }

        struct Input: Decodable {
            let file_path: String?
            let command: String?
        }

        // message.content is either a String or an array of blocks.
        enum Content: Decodable {
            case text(String)
            case blocks([Block])

            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) {
                    self = .text(s)
                } else {
                    self = .blocks((try? c.decode([Block].self)) ?? [])
                }
            }
        }
    }

    static func parseLine(_ line: String) -> ParsedEntry? {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawLine.self, from: data),
              let message = raw.message
        else { return nil }

        let iso = ISO8601DateFormatter()
        let timestamp = raw.timestamp.flatMap { iso.date(from: $0) } ?? Date()

        var userText: String?
        var toolUses: [ToolUse] = []
        switch message.content {
        case .text(let s):
            if message.role == "user" { userText = s }
        case .blocks(let blocks):
            if message.role == "user" {
                userText = blocks.first(where: { $0.type == "text" })?.text
            }
            if message.role == "assistant" {
                toolUses = blocks.compactMap { b in
                    guard b.type == "tool_use", let name = b.name else { return nil }
                    return ToolUse(name: name, filePath: b.input?.file_path, command: b.input?.command)
                }
            }
        case .none:
            break
        }

        return ParsedEntry(
            inputTokens: message.usage?.input_tokens ?? 0,
            outputTokens: message.usage?.output_tokens ?? 0,
            timestamp: timestamp,
            cwd: raw.cwd,
            gitBranch: raw.gitBranch,
            role: message.role,
            userText: userText,
            toolUses: toolUses
        )
    }
}
```

- [ ] **Step 4: Run tests, verify PASS**

Run: `swift test --filter TranscriptParserTests`
Expected: PASS. Then `swift test` (full) — daemon still builds (ClaudeWatcher uses `parsed.inputTokens/outputTokens/timestamp/cwd`, all still present; its zero-token guard still filters non-usage lines for the token path).

- [ ] **Step 5: Commit**

```bash
git add Sources/NookDaemon/TranscriptParser.swift Tests/NookTests/TranscriptParserTests.swift
git commit -m "feat(daemon): enrich transcript parser with role, task text, tool uses, branch"
```

---

## Task 2: Daemon — SessionRecord subject fields + activity event types

**Files:**
- Modify: `Sources/NookDaemon/Models.swift`
- Test: `Tests/NookTests/LedgerStateDecodeTests.swift`

- [ ] **Step 1: Add failing tests** (append inside the existing `final class LedgerStateDecodeTests: XCTestCase {`):

```swift
    func test_legacy_session_without_subject_fields_decodes_with_defaults() throws {
        let json = #"{"totalBits":0,"pendingBits":0,"agents":{},"lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0,"sessions":{"s1":{"sessionId":"s1","project":"Nook","projectPath":"/p","agentName":"Radion","startedAt":"2026-06-01T10:00:00Z","lastActivityAt":"2026-06-01T11:00:00Z","inputTokens":100,"outputTokens":200,"totalBits":3.5}}}"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(LedgerState.self, from: Data(json.utf8))
        let s = try XCTUnwrap(state.sessions["s1"])
        XCTAssertNil(s.task)
        XCTAssertEqual(s.filesTouched, [])
        XCTAssertEqual(s.editCount, 0)
        XCTAssertEqual(s.firedKinds, [])
        XCTAssertTrue(state.recentActivity.isEmpty)
        XCTAssertEqual(state.activitySeq, 0)
    }
```

- [ ] **Step 2: Run, verify FAIL**

Run: `swift test --filter LedgerStateDecodeTests`
Expected: FAIL — no `task`/`filesTouched`/`recentActivity`/`activitySeq`.

- [ ] **Step 3: Edit `Sources/NookDaemon/Models.swift`.**

(3a) Add the new stored properties to `SessionRecord` (all with defaults so the synthesized memberwise init keeps existing call sites compiling), keeping existing fields and computed properties:

```swift
    // Subject signals (NPC voice)
    var task: String?
    var gitBranch: String?
    var filesTouched: [String] = []
    var editCount: Int = 0
    var readCount: Int = 0
    var bashCount: Int = 0
    var firedKinds: [String] = []
```

(3b) Add a backward-compatible `init(from:)` IN AN EXTENSION (an extension init preserves the synthesized memberwise initializer):

```swift
extension SessionRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        project = try c.decode(String.self, forKey: .project)
        projectPath = try c.decode(String.self, forKey: .projectPath)
        agentName = try? c.decode(String.self, forKey: .agentName)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        lastActivityAt = try c.decode(Date.self, forKey: .lastActivityAt)
        inputTokens = try c.decode(Int.self, forKey: .inputTokens)
        outputTokens = try c.decode(Int.self, forKey: .outputTokens)
        totalBits = try c.decode(Double.self, forKey: .totalBits)
        task = try? c.decode(String.self, forKey: .task)
        gitBranch = try? c.decode(String.self, forKey: .gitBranch)
        filesTouched = (try? c.decode([String].self, forKey: .filesTouched)) ?? []
        editCount = (try? c.decode(Int.self, forKey: .editCount)) ?? 0
        readCount = (try? c.decode(Int.self, forKey: .readCount)) ?? 0
        bashCount = (try? c.decode(Int.self, forKey: .bashCount)) ?? 0
        firedKinds = (try? c.decode([String].self, forKey: .firedKinds)) ?? []
    }
}
```

(3c) Add `SessionActivityEvent` and extend `LedgerState`. Add the struct near `BitEvent`:

```swift
struct SessionActivityEvent: Codable, Equatable {
    let agentName: String?
    let sessionId: String
    let kind: String
    let payload: String?
    let seq: Int
}
```

In `LedgerState`: add stored properties, defaulted memberwise-init params, and decode lines:

```swift
    var recentActivity: [SessionActivityEvent]
    var activitySeq: Int
```

Add to the memberwise `init(...)` signature `recentActivity: [SessionActivityEvent] = [], activitySeq: Int = 0` and assign them. In `init(from:)` add:

```swift
        recentActivity = (try? c.decode([SessionActivityEvent].self, forKey: .recentActivity)) ?? []
        activitySeq = (try? c.decode(Int.self, forKey: .activitySeq)) ?? 0
```

`.empty` is unchanged (relies on the new defaulted params).

- [ ] **Step 4: Run, verify PASS**

Run: `swift test` (full)
Expected: PASS — new decode test green, all existing daemon tests green (the new `SessionRecord` fields default; existing 9-arg construction in `Ledger.apply` still compiles via defaulted memberwise params).

- [ ] **Step 5: Commit**

```bash
git add Sources/NookDaemon/Models.swift Tests/NookTests/LedgerStateDecodeTests.swift
git commit -m "feat(daemon): add SessionRecord subject fields and SessionActivityEvent"
```

---

## Task 3: Daemon — ingestSubject (upsert + emit activity events)

**Files:**
- Modify: `Sources/NookDaemon/Ledger.swift`
- Test: `Tests/NookTests/LedgerTests.swift`

- [ ] **Step 1: Add failing tests** (append inside `final class LedgerTests: XCTestCase {`; reuse the existing `date(_:)` helper):

```swift
    private func entry(role: String? = nil, userText: String? = nil, tools: [ToolUse] = [],
                       at: String = "2026-06-01T10:00:00Z") -> ParsedEntry {
        ParsedEntry(inputTokens: 0, outputTokens: 0, timestamp: date(at), cwd: "/c/Nook",
                    gitBranch: "main", role: role, userText: userText, toolUses: tools)
    }

    func test_ingest_first_user_prompt_sets_task_and_emits_once() {
        var state = LedgerState.empty
        ledger.ingestSubject(entry: entry(role: "user", userText: "refactor auth"), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        XCTAssertEqual(state.sessions["s1"]?.task, "refactor auth")
        XCTAssertEqual(state.recentActivity.filter { $0.kind == "task" }.count, 1)
        // second prompt does not re-emit task
        ledger.ingestSubject(entry: entry(role: "user", userText: "now tests"), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        XCTAssertEqual(state.recentActivity.filter { $0.kind == "task" }.count, 1)
    }

    func test_ingest_new_file_emits_file_event_once() {
        var state = LedgerState.empty
        let tool = ToolUse(name: "Edit", filePath: "/c/Nook/Auth.swift", command: nil)
        ledger.ingestSubject(entry: entry(role: "assistant", tools: [tool]), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        ledger.ingestSubject(entry: entry(role: "assistant", tools: [tool]), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        let fileEvents = state.recentActivity.filter { $0.kind == "file" }
        XCTAssertEqual(fileEvents.count, 1)
        XCTAssertEqual(fileEvents.first?.payload, "Auth.swift")
        XCTAssertEqual(state.sessions["s1"]?.editCount, 2)
    }

    func test_ingest_test_command_emits_testing_once_with_coarse_payload() {
        var state = LedgerState.empty
        let bash = ToolUse(name: "Bash", filePath: nil, command: "swift test --filter Foo")
        ledger.ingestSubject(entry: entry(role: "assistant", tools: [bash]), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        ledger.ingestSubject(entry: entry(role: "assistant", tools: [bash]), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        let testing = state.recentActivity.filter { $0.kind == "testing" }
        XCTAssertEqual(testing.count, 1)
        XCTAssertEqual(testing.first?.payload, "swift")   // coarse summary, not the full command
    }

    func test_ingest_deepwork_fires_when_edit_count_crosses_ten() {
        var state = LedgerState.empty
        let tool = ToolUse(name: "Edit", filePath: nil, command: nil)
        for _ in 0..<10 {
            ledger.ingestSubject(entry: entry(role: "assistant", tools: [tool]), sessionId: "s1", projectPath: "/c/Nook", agentName: "Radion", to: &state)
        }
        XCTAssertEqual(state.recentActivity.filter { $0.kind == "deepWork" }.count, 1)
    }
```

- [ ] **Step 2: Run, verify FAIL**

Run: `swift test --filter LedgerTests`
Expected: FAIL — `ingestSubject` does not exist.

- [ ] **Step 3: Add `ingestSubject` + helpers to `Sources/NookDaemon/Ledger.swift`** (inside `final class Ledger`):

```swift
    func ingestSubject(entry: ParsedEntry, sessionId: String, projectPath: String, agentName: String?, to state: inout LedgerState) {
        // Mirror apply()'s derivation so a session created here keys identically.
        let project = entry.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? URL(fileURLWithPath: projectPath).lastPathComponent

        // Upsert the session (create if this line precedes any usage-bearing line).
        var session = state.sessions[sessionId] ?? SessionRecord(
            sessionId: sessionId, project: project, projectPath: projectPath,
            agentName: agentName, startedAt: entry.timestamp, lastActivityAt: entry.timestamp,
            inputTokens: 0, outputTokens: 0, totalBits: 0
        )
        session.lastActivityAt = entry.timestamp
        if let agentName { session.agentName = agentName }
        if let branch = entry.gitBranch { session.gitBranch = branch }

        // Task: first real user prompt.
        if session.task == nil, let text = entry.userText {
            let snippet = Self.truncate(text, to: 120)
            session.task = snippet
            emitActivity(&state, agentName: agentName, sessionId: sessionId, kind: "task", payload: snippet)
        }

        // Tool uses: files + commands + counts.
        for tool in entry.toolUses {
            switch tool.name {
            case "Edit", "Write", "MultiEdit":
                session.editCount += 1
                if let path = tool.filePath { newFile(&state, &session, path, agentName, sessionId) }
            case "Read":
                session.readCount += 1
                if let path = tool.filePath { newFile(&state, &session, path, agentName, sessionId) }
            case "Bash":
                session.bashCount += 1
                if let cmd = tool.command {
                    let summary = Self.commandSummary(cmd)
                    if cmd.contains("git commit") {
                        fireOnce(&state, &session, kind: "committing", payload: "git commit", agentName, sessionId)
                    } else if Self.looksLikeTests(cmd) {
                        fireOnce(&state, &session, kind: "testing", payload: summary, agentName, sessionId)
                    }
                }
            default:
                break
            }
        }

        // Deep work threshold.
        if session.editCount >= 10 {
            fireOnce(&state, &session, kind: "deepWork", payload: session.project, agentName, sessionId)
        }

        state.sessions[sessionId] = session
    }

    private func newFile(_ state: inout LedgerState, _ session: inout SessionRecord, _ path: String,
                         _ agentName: String?, _ sessionId: String) {
        guard !session.filesTouched.contains(path) else { return }
        session.filesTouched.append(path)
        if session.filesTouched.count > 20 { session.filesTouched.removeFirst(session.filesTouched.count - 20) }
        emitActivity(&state, agentName: agentName, sessionId: sessionId, kind: "file",
                     payload: URL(fileURLWithPath: path).lastPathComponent)
    }

    private func fireOnce(_ state: inout LedgerState, _ session: inout SessionRecord, kind: String,
                          payload: String?, _ agentName: String?, _ sessionId: String) {
        guard !session.firedKinds.contains(kind) else { return }
        session.firedKinds.append(kind)
        emitActivity(&state, agentName: agentName, sessionId: sessionId, kind: kind, payload: payload)
    }

    private func emitActivity(_ state: inout LedgerState, agentName: String?, sessionId: String,
                              kind: String, payload: String?) {
        state.activitySeq += 1
        state.recentActivity.append(SessionActivityEvent(
            agentName: agentName, sessionId: sessionId, kind: kind, payload: payload, seq: state.activitySeq))
        if state.recentActivity.count > 100 {
            state.recentActivity.removeFirst(state.recentActivity.count - 100)
        }
    }

    static func truncate(_ s: String, to n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= n ? t : String(t.prefix(n - 1)) + "…"
    }

    static func commandSummary(_ cmd: String) -> String {
        let parts = cmd.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard let first = parts.first.map(String.init) else { return "" }
        if first == "git", parts.count > 1 { return "git \(parts[1])" }
        return first
    }

    static func looksLikeTests(_ cmd: String) -> Bool {
        let c = cmd.lowercased()
        return c.contains("test") || c.contains("pytest")
    }
```

- [ ] **Step 4: Run, verify PASS**

Run: `swift test --filter LedgerTests` then `swift test` (full)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NookDaemon/Ledger.swift Tests/NookTests/LedgerTests.swift
git commit -m "feat(daemon): ingest session subject signals and emit activity events"
```

---

## Task 4: Daemon — wire subject ingestion into the watcher

**Files:**
- Modify: `Sources/NookDaemon/ClaudeWatcher.swift`
- Modify: `Sources/NookDaemon/main.swift`

No new unit test (the watcher has no existing unit test; its logic is thin and the parsing/ingest are covered by Tasks 1 & 3). Verified by a green build + suite.

- [ ] **Step 1: Add an `onSubject` callback to `ClaudeWatcher`**

In `Sources/NookDaemon/ClaudeWatcher.swift`, add a stored callback and an init parameter. Add the property near `onEvent`:

```swift
    private let onSubject: (ParsedEntry, String, String, String?) -> Void  // entry, sessionId, projectPath, agentName
```

Add to `init(...)` a parameter (after `onEvent`) with a default so existing construction stays valid:

```swift
        onSubject: @escaping (ParsedEntry, String, String, String?) -> Void = { _, _, _, _ in },
```

and assign `self.onSubject = onSubject` in the body.

- [ ] **Step 2: Restructure the line loop in `readNewLines`**

Replace the `for line in content.components(separatedBy: "\n") { ... }` loop with:

```swift
        var lastUsage: (Int, Int)? = nil
        for line in content.components(separatedBy: "\n") {
            guard let parsed = TranscriptParser.parseLine(line) else { continue }

            // Subject ingestion runs for every message line (user prompts included).
            onSubject(parsed, sessionId, projectPath, agentName)

            // Token/bits emission only for usage-bearing lines (with consecutive-dup guard).
            let pair = (parsed.inputTokens, parsed.outputTokens)
            guard pair.0 > 0 || pair.1 > 0 else { continue }
            guard lastUsage.map({ $0 != pair }) ?? true else { continue }
            lastUsage = pair
            let event = TokenEvent(
                sessionId: sessionId, projectPath: projectPath, cwd: parsed.cwd,
                inputTokens: parsed.inputTokens, outputTokens: parsed.outputTokens,
                timestamp: parsed.timestamp
            )
            onEvent(event, agentName)
        }
```

- [ ] **Step 3: Wire `onSubject` in `Sources/NookDaemon/main.swift`**

Replace the `ClaudeWatcher { event, agentName in ... }` construction with one that passes both callbacks and saves after each:

```swift
let watcher = ClaudeWatcher(
    onEvent: { event, agentName in
        ledger.apply(event: event, agentName: agentName, to: &state)
        do {
            try ledger.save(state)
            let bits = String(format: "%.1f", event.bits)
            let agent = agentName ?? "global"
            print("[NookDaemon] +\(bits) Bits → \(agent) | Total: \(String(format: "%.1f", state.totalBits))")
        } catch {
            print("[NookDaemon] Failed to save ledger: \(error)")
        }
    },
    onSubject: { entry, sessionId, projectPath, agentName in
        ledger.ingestSubject(entry: entry, sessionId: sessionId, projectPath: projectPath, agentName: agentName, to: &state)
        try? ledger.save(state)
    }
)
```

(If `ClaudeWatcher`'s init is currently called with a trailing closure, switch to the labeled `onEvent:`/`onSubject:` form as above.)

- [ ] **Step 4: Build + suite**

Run: `swift build` then `swift test`
Expected: build succeeds; all daemon tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/NookDaemon/ClaudeWatcher.swift Sources/NookDaemon/main.swift
git commit -m "feat(daemon): feed every transcript line through subject ingestion"
```

---

## Task 5: App — mirror models + VillageEngine consumption

**Files:**
- Modify: `Sources/NookApp/LedgerModels.swift`
- Modify: `Sources/NookApp/VillageEngine.swift`
- Test: `Tests/NookAppTests/LedgerStateAppDecodeTests.swift`

- [ ] **Step 1: Add a failing decode test** (append inside `final class LedgerStateAppDecodeTests: XCTestCase {`):

```swift
    func test_decodes_activity_and_session_subject_fields() throws {
        let json = #"{"totalBits":0,"pendingBits":0,"agents":{},"lastUpdated":"2026-06-01T00:00:00Z","recentEvents":[],"eventSeq":0,"activitySeq":2,"recentActivity":[{"agentName":"Radion","sessionId":"s1","kind":"file","payload":"Auth.swift","seq":2}],"sessions":{"s1":{"sessionId":"s1","project":"Nook","projectPath":"/p","agentName":"Radion","startedAt":"2026-06-01T10:00:00Z","lastActivityAt":"2026-06-01T11:00:00Z","inputTokens":1,"outputTokens":1,"totalBits":0,"task":"refactor","filesTouched":["/p/Auth.swift"],"editCount":3}}}"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(LedgerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.activitySeq, 2)
        XCTAssertEqual(state.recentActivity.first?.kind, "file")
        XCTAssertEqual(state.sessions["s1"]?.task, "refactor")
        XCTAssertEqual(state.sessions["s1"]?.editCount, 3)
    }
```

- [ ] **Step 2: Run, verify FAIL**

Run: `xcodebuild test ... -only-testing:NookAppTests/LedgerStateAppDecodeTests` (no new file, so no xcodegen needed yet)
Expected: FAIL — app models lack the new fields.

- [ ] **Step 3: Extend `Sources/NookApp/LedgerModels.swift`.**

(3a) Add the subject fields to the app `SessionRecord` (these are decode-only mirrors; keep them `var` with defaults so test constructions and decode work):

```swift
    var task: String?
    var gitBranch: String?
    var filesTouched: [String] = []
    var editCount: Int = 0
    var readCount: Int = 0
    var bashCount: Int = 0
```

(The app does not need `firedKinds`; omit it — the daemon owns dedup.) Add a backward-compatible `init(from:)` in an extension (preserves the memberwise init used by tests):

```swift
extension SessionRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        project = try c.decode(String.self, forKey: .project)
        projectPath = try c.decode(String.self, forKey: .projectPath)
        agentName = try? c.decode(String.self, forKey: .agentName)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        lastActivityAt = try c.decode(Date.self, forKey: .lastActivityAt)
        inputTokens = try c.decode(Int.self, forKey: .inputTokens)
        outputTokens = try c.decode(Int.self, forKey: .outputTokens)
        totalBits = try c.decode(Double.self, forKey: .totalBits)
        task = try? c.decode(String.self, forKey: .task)
        gitBranch = try? c.decode(String.self, forKey: .gitBranch)
        filesTouched = (try? c.decode([String].self, forKey: .filesTouched)) ?? []
        editCount = (try? c.decode(Int.self, forKey: .editCount)) ?? 0
        readCount = (try? c.decode(Int.self, forKey: .readCount)) ?? 0
        bashCount = (try? c.decode(Int.self, forKey: .bashCount)) ?? 0
    }
}
```

> If the app `SessionRecord` declares its fields as `let`, change the new subject fields and any field this `init(from:)` assigns to `var` as needed, or keep originals `let` (an extension init can assign `let` stored properties). Match the file's existing style; the key requirement is the `(try?) ?? default` fallback for the new keys.

(3b) Add `SessionActivityEvent` (mirror) near `BitEvent`:

```swift
struct SessionActivityEvent: Codable, Equatable {
    let agentName: String?
    let sessionId: String
    let kind: String
    let payload: String?
    let seq: Int
}
```

(3c) Add `recentActivity`/`activitySeq` to the app `LedgerState` exactly like `recentEvents`/`eventSeq`: stored props, defaulted memberwise-init params, and `init(from:)` lines:

```swift
        recentActivity = (try? c.decode([SessionActivityEvent].self, forKey: .recentActivity)) ?? []
        activitySeq = (try? c.decode(Int.self, forKey: .activitySeq)) ?? 0
```

- [ ] **Step 4: Add consumption to `Sources/NookApp/VillageEngine.swift`.**

Add stored properties near `newBitEvents`/`lastSeenEventSeq`. Declare `newActivityEvents` as a
plain `var` (NOT `private(set)`) — mirror `newBitEvents`, which the scene resets to `[]`:

```swift
    var newActivityEvents: [SessionActivityEvent] = []
    private var lastSeenActivitySeq: Int = -1
```

In `reload()`, after the existing bit-event block, add the parallel logic:

```swift
        if lastSeenActivitySeq == -1 {
            lastSeenActivitySeq = state.activitySeq
        } else {
            let fresh = state.recentActivity.filter { $0.seq > lastSeenActivitySeq }
            if !fresh.isEmpty {
                newActivityEvents += fresh
                lastSeenActivitySeq = fresh.map(\.seq).max() ?? lastSeenActivitySeq
            }
        }
```

> Note: `reload()` `return`s early on its first call after anchoring `lastSeenEventSeq`. Place the activity anchoring BEFORE that early `return` (or restructure so both seqs anchor on first load). Ensure the first-load path anchors `lastSeenActivitySeq` too, so no replay.

- [ ] **Step 5: Run, verify PASS**

Run: `xcodebuild test ... -only-testing:NookAppTests/LedgerStateAppDecodeTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/NookApp/LedgerModels.swift Sources/NookApp/VillageEngine.swift Tests/NookAppTests/LedgerStateAppDecodeTests.swift
git commit -m "feat(app): mirror activity events and consume them in VillageEngine"
```

---

## Task 6: App — SpeechLineComposer

**Files:**
- Create: `Sources/NookApp/SpeechLineComposer.swift`
- Test: `Tests/NookAppTests/SpeechLineComposerTests.swift`

- [ ] **Step 1: Create `Tests/NookAppTests/SpeechLineComposerTests.swift`:**

```swift
import XCTest
@testable import Nook

final class SpeechLineComposerTests: XCTestCase {
    let c = HeuristicLineComposer()
    func event(_ kind: String, _ payload: String?) -> SessionActivityEvent {
        SessionActivityEvent(agentName: "Radion", sessionId: "s1", kind: kind, payload: payload, seq: 1)
    }

    func test_task_line() {
        XCTAssertEqual(c.line(for: event("task", "refactor auth"), session: nil), "On attaque : refactor auth")
    }
    func test_file_line() {
        XCTAssertEqual(c.line(for: event("file", "Moment.swift"), session: nil), "Plongé dans Moment.swift")
    }
    func test_testing_line() {
        XCTAssertEqual(c.line(for: event("testing", "swift"), session: nil), "TDD, j'aime ça")
    }
    func test_committing_line() {
        XCTAssertEqual(c.line(for: event("committing", "git commit"), session: nil), "On commit ?")
    }
    func test_deepwork_line() {
        XCTAssertEqual(c.line(for: event("deepWork", "Nook"), session: nil), "Grosse session sur Nook")
    }
    func test_unknown_kind_returns_nil() {
        XCTAssertNil(c.line(for: event("mystery", nil), session: nil))
    }
    func test_missing_payload_returns_nil_where_payload_required() {
        XCTAssertNil(c.line(for: event("file", nil), session: nil))
    }
}
```

- [ ] **Step 2: Run, verify FAIL** (`xcodegen generate` first since the test file is new)

Run: `xcodegen generate` then `xcodebuild test ... -only-testing:NookAppTests/SpeechLineComposerTests`
Expected: FAIL — `HeuristicLineComposer` undefined.

- [ ] **Step 3: Create `Sources/NookApp/SpeechLineComposer.swift`:**

```swift
import Foundation

protocol SpeechLineComposing {
    func line(for event: SessionActivityEvent, session: SessionRecord?) -> String?
}

struct HeuristicLineComposer: SpeechLineComposing {
    func line(for event: SessionActivityEvent, session: SessionRecord?) -> String? {
        switch event.kind {
        case "task":
            guard let p = event.payload else { return nil }
            return "On attaque : \(p)"
        case "file":
            guard let p = event.payload else { return nil }
            return "Plongé dans \(p)"
        case "testing":
            return "TDD, j'aime ça"
        case "committing":
            return "On commit ?"
        case "deepWork":
            guard let p = event.payload else { return nil }
            return "Grosse session sur \(p)"
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run, verify PASS**

Run: `xcodebuild test ... -only-testing:NookAppTests/SpeechLineComposerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NookApp/SpeechLineComposer.swift Tests/NookAppTests/SpeechLineComposerTests.swift NookApp.xcodeproj/project.pbxproj
git commit -m "feat(app): add heuristic speech line composer"
```

---

## Task 7: App — speech bubble on NPCSprite

**Files:**
- Modify: `Sources/NookApp/NPCSprite.swift`

Visual SpriteKit code — verified by build (no unit test).

- [ ] **Step 1: Add `showSpeech(_:)` to `NPCSprite`** (place near `showBitsGain`). It reuses the sprite's `Self.charH` (= 64) and the `Monaco` font already used by `showBitsGain`:

```swift
    func showSpeech(_ text: String) {
        // One bubble at a time.
        childNode(withName: "speech")?.removeFromParent()

        let display = text.count > 60 ? String(text.prefix(59)) + "…" : text

        let label = SKLabelNode(fontNamed: "Monaco")
        label.text = display
        label.fontSize = 11
        label.fontColor = .black
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.preferredMaxLayoutWidth = 180
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail

        let padding: CGFloat = 8
        let textSize = label.frame.size
        let bubbleW = min(max(textSize.width + padding * 2, 40), 200)
        let bubbleH = textSize.height + padding * 2

        let bubble = SKShapeNode(rectOf: CGSize(width: bubbleW, height: bubbleH), cornerRadius: 6)
        bubble.name = "speech"
        bubble.fillColor = NSColor(white: 0.97, alpha: 0.96)
        bubble.strokeColor = NSColor(white: 0.2, alpha: 0.9)
        bubble.lineWidth = 1
        bubble.position = CGPoint(x: 0, y: Self.charH + 30)
        bubble.zPosition = 40
        bubble.addChild(label)

        // Little tail.
        let tail = SKShapeNode(rectOf: CGSize(width: 6, height: 6))
        tail.fillColor = bubble.fillColor
        tail.strokeColor = bubble.strokeColor
        tail.lineWidth = 1
        tail.zRotation = .pi / 4
        tail.position = CGPoint(x: 0, y: -bubbleH / 2)
        bubble.addChild(tail)

        bubble.alpha = 0
        bubble.setScale(0.9)
        addChild(bubble)

        let hold = max(2.5, min(5.0, Double(display.count) * 0.06))
        bubble.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1.0, duration: 0.12)]),
            .wait(forDuration: hold),
            .group([.fadeOut(withDuration: 0.3)]),
            .removeFromParent()
        ]))
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Sources/NookApp/NPCSprite.swift
git commit -m "feat(app): render NPC speech bubble"
```

---

## Task 8: App — route activity events to bubbles with cooldown

**Files:**
- Modify: `Sources/NookApp/NPCManager.swift`
- Modify: `Sources/NookApp/VillageScene.swift`

Verified by build (rendering/timing path). Composition is already unit-tested (Task 6).

- [ ] **Step 1: Add composer + cooldown state to `NPCManager`** (near the other private state):

```swift
    private let speechComposer: SpeechLineComposing = HeuristicLineComposer()
    private var lastSpokeAt: [String: Date] = [:]
    private let speechCooldown: TimeInterval = 50
```

- [ ] **Step 2: Add `handleActivityEvents(_:)` to `NPCManager`** (near `handleBitEvents`):

```swift
    func handleActivityEvents(_ events: [SessionActivityEvent]) {
        let now = Date()
        // Keep only the most recent event per agent with a live sprite.
        var latestByAgent: [String: SessionActivityEvent] = [:]
        for event in events {
            guard let agent = event.agentName, sprites[agent] != nil else { continue }
            if let existing = latestByAgent[agent], existing.seq > event.seq { continue }
            latestByAgent[agent] = event
        }
        for (agent, event) in latestByAgent {
            if let last = lastSpokeAt[agent], now.timeIntervalSince(last) < speechCooldown { continue }
            guard let line = speechComposer.line(for: event, session: engine.sessions[event.sessionId]) else { continue }
            sprites[agent]?.showSpeech(line)
            lastSpokeAt[agent] = now
        }
    }
```

- [ ] **Step 3: Drain the queue in `VillageScene.update(_:)`**

In `Sources/NookApp/VillageScene.swift`, in `update(_:)`, next to the existing `newBitEvents` handling, add:

```swift
        if let engine, !engine.newActivityEvents.isEmpty {
            npcManager?.handleActivityEvents(engine.newActivityEvents)
            engine.newActivityEvents = []
        }
```

> This mirrors the existing `newBitEvents` reset in `update(_:)`. `newActivityEvents` was declared as a plain `var` in Task 5, so the scene can reset it the same way.

- [ ] **Step 4: Build**

Run: `xcodebuild build -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Sources/NookApp/NPCManager.swift Sources/NookApp/VillageScene.swift Sources/NookApp/VillageEngine.swift
git commit -m "feat(app): speak subject-aware bubbles from session activity events"
```

---

## Task 9: Final verification

- [ ] **Step 1:** `xcodegen generate` — succeeds, picks up `SpeechLineComposer.swift` + new test files.
- [ ] **Step 2:** `swift test` — all `NookTests` green (TranscriptParser, Ledger activity, decode).
- [ ] **Step 3:** `xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'` — all `NookAppTests` green (incl. SpeechLineComposer, LedgerStateAppDecode).
- [ ] **Step 4:** `xcodebuild build -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'` — BUILD SUCCEEDED.
- [ ] **Step 5: Manual smoke check.** Launch the app with the daemon running. Start a Claude Code session in a `.pixelvillage`-attributed project, then: type a first prompt → the NPC says "On attaque : …"; open/edit a new file → "Plongé dans <file>"; run `swift test` → "TDD, j'aime ça". Verify only one bubble at a time, bubbles auto-dismiss, and rapid activity does not produce a stream (≥50 s cooldown). Activity that happened while the app was closed produces no bubble on launch.
- [ ] **Step 6:** Commit any regenerated project file:

```bash
git add -f NookApp.xcodeproj/project.pbxproj
git add project.yml
git commit -m "chore: regenerate project for speech composer and tests"
```

---

## Notes for the implementer

- **Two test runners:** daemon → `swift test` (`NookTests`); app → `xcodebuild test` (`NookAppTests`, module `Nook`).
- **Backward-compat decode is load-bearing:** existing `ledger.json` has `SessionRecord`s without the new keys. The `init(from:)` in an extension with `(try?) ?? default` for new fields is what prevents the whole `sessions`/`recentActivity` dict from silently emptying on upgrade. Do not skip it.
- **No replay on launch:** `lastSeenActivitySeq` must anchor to `state.activitySeq` on the first `reload()`, exactly like `lastSeenEventSeq`, so closed-app activity never fires stale bubbles.
- **Privacy:** never store/emit a full Bash command — only `commandSummary` (program token / `git <sub>`).
- **Cooldown is the app-side safety net;** most "significant" filtering is already done daemon-side via `filesTouched`/`firedKinds`.

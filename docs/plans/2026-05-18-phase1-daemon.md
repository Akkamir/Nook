# Nook — Phase 1: Daemon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the background daemon that watches Claude Code JSONL transcripts and accumulates Bits in a local ledger — no UI, fully testable standalone.

**Architecture:** A separate macOS executable target (`NookDaemon`) watches `~/.claude/projects/` via FSEvents, parses JSONL transcript lines to extract token counts, attributes tokens to NPCs via `.pixelvillage` config files, and writes results to `~/.pixelvillage/ledger.json`. The main app reads this ledger on launch.

**Tech Stack:** Swift 5.9+, Xcode 15+, XCTest, Foundation (FSEvents via `DispatchSource`), no external dependencies in Phase 1.

---

## File Map

| File | Responsibility |
|---|---|
| `NookDaemon/Sources/main.swift` | Entry point, wires up watcher → attributor → ledger |
| `NookDaemon/Sources/TranscriptParser.swift` | Parse a JSONL line, extract input/output tokens |
| `NookDaemon/Sources/AgentAttributor.swift` | Read `.pixelvillage` in project dir, return agent name |
| `NookDaemon/Sources/Ledger.swift` | Read/write `~/.pixelvillage/ledger.json` atomically |
| `NookDaemon/Sources/ClaudeWatcher.swift` | FSEvents on `~/.claude/projects/`, emit new JSONL lines |
| `NookDaemon/Sources/Models.swift` | Shared value types: `TokenEvent`, `LedgerState`, `AgentRecord` |
| `NookTests/TranscriptParserTests.swift` | Unit tests for JSONL parsing |
| `NookTests/AgentAttributorTests.swift` | Unit tests for .pixelvillage attribution |
| `NookTests/LedgerTests.swift` | Unit tests for ledger read/write/merge |

---

## Task 1: Xcode Project Setup

**Files:**
- Create: `Nook.xcodeproj` (via Xcode)
- Create: `NookDaemon/Sources/main.swift`
- Create: `NookTests/` test target

- [ ] **Step 1: Create Xcode project**

Open Xcode → File → New → Project → macOS → App.
- Product Name: `Nook`
- Bundle ID: `com.yourname.nook`
- Language: Swift
- Uncheck SwiftUI (we'll use AppKit + SpriteKit)
- Save to `/Users/mchau/Desktop/Code/Nook/`

- [ ] **Step 2: Add NookDaemon target**

In Xcode → File → New → Target → macOS → Command Line Tool.
- Product Name: `NookDaemon`
- Language: Swift

This creates `NookDaemon/main.swift`.

- [ ] **Step 3: Add NookTests target**

In Xcode → File → New → Target → macOS → Unit Testing Bundle.
- Product Name: `NookTests`
- Target to test: `NookDaemon`

- [ ] **Step 4: Create Models.swift**

Create `NookDaemon/Sources/Models.swift`:

```swift
import Foundation

struct TokenEvent {
    let projectPath: String
    let inputTokens: Int
    let outputTokens: Int
    let timestamp: Date

    var bits: Double {
        Double(inputTokens) / 1000.0 * 5.0 +
        Double(outputTokens) / 1000.0 * 15.0
    }
}

struct AgentRecord: Codable {
    var name: String
    var totalTokens: Int
    var bond: Int

    mutating func addTokens(_ event: TokenEvent) {
        totalTokens += event.inputTokens + event.outputTokens
        bond = bondLevel(for: totalTokens)
    }

    private func bondLevel(for tokens: Int) -> Int {
        switch tokens {
        case ..<10_000: return 1
        case ..<50_000: return 2
        case ..<200_000: return 3
        case ..<1_000_000: return 4
        default: return 5
        }
    }
}

struct LedgerState: Codable {
    var totalBits: Double
    var pendingBits: Double
    var agents: [String: AgentRecord]
    var lastUpdated: Date

    static var empty: LedgerState {
        LedgerState(
            totalBits: 0,
            pendingBits: 0,
            agents: [:],
            lastUpdated: Date()
        )
    }
}
```

- [ ] **Step 5: Verify build**

Cmd+B — both targets must compile with zero errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/mchau/Desktop/Code/Nook
git init
git add .
git commit -m "feat: initial Xcode project with NookDaemon and NookTests targets"
```

---

## Task 2: TranscriptParser

**Files:**
- Create: `NookDaemon/Sources/TranscriptParser.swift`
- Create: `NookTests/TranscriptParserTests.swift`

- [ ] **Step 1: Write failing tests**

Create `NookTests/TranscriptParserTests.swift`:

```swift
import XCTest
@testable import NookDaemon

final class TranscriptParserTests: XCTestCase {

    func test_parse_assistant_line_with_usage() throws {
        let line = """
        {"type":"assistant","message":{"role":"assistant","content":[]},"usage":{"input_tokens":4821,"output_tokens":312}}
        """
        let result = TranscriptParser.parseLine(line)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.inputTokens, 4821)
        XCTAssertEqual(result?.outputTokens, 312)
    }

    func test_parse_line_without_usage_returns_nil() {
        let line = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        """
        let result = TranscriptParser.parseLine(line)
        XCTAssertNil(result)
    }

    func test_parse_empty_line_returns_nil() {
        XCTAssertNil(TranscriptParser.parseLine(""))
    }

    func test_parse_malformed_json_returns_nil() {
        XCTAssertNil(TranscriptParser.parseLine("{not valid json}"))
    }

    func test_bits_calculation() throws {
        let line = """
        {"type":"assistant","usage":{"input_tokens":1000,"output_tokens":1000}}
        """
        let result = try XCTUnwrap(TranscriptParser.parseLine(line))
        // 1000 input * 5/1000 + 1000 output * 15/1000 = 5 + 15 = 20
        XCTAssertEqual(result.bits, 20.0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

In Xcode: Cmd+U, or:
```bash
xcodebuild test -scheme NookDaemon -destination 'platform=macOS' 2>&1 | grep -E "(PASS|FAIL|error)"
```
Expected: compile error — `TranscriptParser` not found.

- [ ] **Step 3: Implement TranscriptParser**

Create `NookDaemon/Sources/TranscriptParser.swift`:

```swift
import Foundation

enum TranscriptParser {
    private struct RawLine: Decodable {
        let type: String
        let usage: Usage?

        struct Usage: Decodable {
            let input_tokens: Int
            let output_tokens: Int
        }
    }

    static func parseLine(_ line: String) -> TokenEvent? {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawLine.self, from: data),
              let usage = raw.usage
        else { return nil }

        return TokenEvent(
            projectPath: "",
            inputTokens: usage.input_tokens,
            outputTokens: usage.output_tokens,
            timestamp: Date()
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme NookDaemon -destination 'platform=macOS' 2>&1 | grep -E "(PASS|FAIL|error)"
```
Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add NookDaemon/Sources/TranscriptParser.swift NookTests/TranscriptParserTests.swift
git commit -m "feat: TranscriptParser extracts input/output tokens from JSONL lines"
```

---

## Task 3: AgentAttributor

**Files:**
- Create: `NookDaemon/Sources/AgentAttributor.swift`
- Create: `NookTests/AgentAttributorTests.swift`

- [ ] **Step 1: Write failing tests**

Create `NookTests/AgentAttributorTests.swift`:

```swift
import XCTest
@testable import NookDaemon

final class AgentAttributorTests: XCTestCase {

    var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func test_returns_agent_name_when_config_exists() throws {
        let config = tmpDir.appendingPathComponent(".pixelvillage")
        try """
        { "agent": "Radion" }
        """.write(to: config, atomically: true, encoding: .utf8)

        let name = AgentAttributor.agentName(forProjectPath: tmpDir.path)
        XCTAssertEqual(name, "Radion")
    }

    func test_returns_nil_when_no_config_file() {
        let name = AgentAttributor.agentName(forProjectPath: tmpDir.path)
        XCTAssertNil(name)
    }

    func test_returns_nil_when_config_malformed() throws {
        let config = tmpDir.appendingPathComponent(".pixelvillage")
        try "not json".write(to: config, atomically: true, encoding: .utf8)

        let name = AgentAttributor.agentName(forProjectPath: tmpDir.path)
        XCTAssertNil(name)
    }

    func test_returns_nil_when_agent_key_missing() throws {
        let config = tmpDir.appendingPathComponent(".pixelvillage")
        try """
        { "other": "value" }
        """.write(to: config, atomically: true, encoding: .utf8)

        let name = AgentAttributor.agentName(forProjectPath: tmpDir.path)
        XCTAssertNil(name)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme NookDaemon -destination 'platform=macOS' 2>&1 | grep -E "(PASS|FAIL|error)"
```
Expected: compile error — `AgentAttributor` not found.

- [ ] **Step 3: Implement AgentAttributor**

Create `NookDaemon/Sources/AgentAttributor.swift`:

```swift
import Foundation

enum AgentAttributor {
    private struct Config: Decodable {
        let agent: String?
    }

    static func agentName(forProjectPath path: String) -> String? {
        let configURL = URL(fileURLWithPath: path)
            .appendingPathComponent(".pixelvillage")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return nil }
        return config.agent
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme NookDaemon -destination 'platform=macOS' 2>&1 | grep -E "(PASS|FAIL|error)"
```
Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add NookDaemon/Sources/AgentAttributor.swift NookTests/AgentAttributorTests.swift
git commit -m "feat: AgentAttributor reads .pixelvillage config to attribute tokens to NPCs"
```

---

## Task 4: Ledger

**Files:**
- Create: `NookDaemon/Sources/Ledger.swift`
- Create: `NookTests/LedgerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `NookTests/LedgerTests.swift`:

```swift
import XCTest
@testable import NookDaemon

final class LedgerTests: XCTestCase {

    var ledgerURL: URL!
    var ledger: Ledger!

    override func setUp() {
        super.setUp()
        ledgerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("ledger.json")
        ledger = Ledger(url: ledgerURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: ledgerURL.deletingLastPathComponent())
        super.tearDown()
    }

    func test_load_returns_empty_state_when_no_file() {
        let state = ledger.load()
        XCTAssertEqual(state.totalBits, 0)
        XCTAssertEqual(state.pendingBits, 0)
        XCTAssertTrue(state.agents.isEmpty)
    }

    func test_save_and_reload_preserves_state() throws {
        var state = LedgerState.empty
        state.totalBits = 42.5
        state.pendingBits = 10.0
        state.agents["Radion"] = AgentRecord(name: "Radion", totalTokens: 50_000, bond: 3)

        try ledger.save(state)
        let loaded = ledger.load()

        XCTAssertEqual(loaded.totalBits, 42.5, accuracy: 0.001)
        XCTAssertEqual(loaded.pendingBits, 10.0, accuracy: 0.001)
        XCTAssertEqual(loaded.agents["Radion"]?.totalTokens, 50_000)
        XCTAssertEqual(loaded.agents["Radion"]?.bond, 3)
    }

    func test_apply_event_global_pool_increases_bits() throws {
        let event = TokenEvent(
            projectPath: "/some/project",
            inputTokens: 1000,
            outputTokens: 1000,
            timestamp: Date()
        )
        var state = LedgerState.empty
        ledger.apply(event: event, agentName: nil, to: &state)

        // 1000*5/1000 + 1000*15/1000 = 20 Bits
        XCTAssertEqual(state.pendingBits, 20.0, accuracy: 0.001)
        XCTAssertEqual(state.totalBits, 20.0, accuracy: 0.001)
        XCTAssertTrue(state.agents.isEmpty)
    }

    func test_apply_event_with_agent_updates_bond() throws {
        let event = TokenEvent(
            projectPath: "/some/project",
            inputTokens: 10_000,
            outputTokens: 0,
            timestamp: Date()
        )
        var state = LedgerState.empty
        ledger.apply(event: event, agentName: "Radion", to: &state)

        XCTAssertEqual(state.agents["Radion"]?.totalTokens, 10_000)
        XCTAssertEqual(state.agents["Radion"]?.bond, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme NookDaemon -destination 'platform=macOS' 2>&1 | grep -E "(PASS|FAIL|error)"
```
Expected: compile error — `Ledger` not found.

- [ ] **Step 3: Implement Ledger**

Create `NookDaemon/Sources/Ledger.swift`:

```swift
import Foundation

final class Ledger {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(url: URL) {
        self.url = url
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> LedgerState {
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(LedgerState.self, from: data)
        else { return .empty }
        return state
    }

    func save(_ state: LedgerState) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func apply(event: TokenEvent, agentName: String?, to state: inout LedgerState) {
        let bits = event.bits
        state.pendingBits += bits
        state.totalBits += bits
        state.lastUpdated = Date()

        if let name = agentName {
            var record = state.agents[name] ?? AgentRecord(name: name, totalTokens: 0, bond: 1)
            record.addTokens(event)
            state.agents[name] = record
        }
    }
}

extension Ledger {
    static var production: Ledger {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixelvillage/ledger.json")
        return Ledger(url: url)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme NookDaemon -destination 'platform=macOS' 2>&1 | grep -E "(PASS|FAIL|error)"
```
Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add NookDaemon/Sources/Ledger.swift NookTests/LedgerTests.swift
git commit -m "feat: Ledger persists LedgerState to JSON, applies TokenEvents with Bits calculation"
```

---

## Task 5: ClaudeWatcher

**Files:**
- Create: `NookDaemon/Sources/ClaudeWatcher.swift`

Note: FSEvents cannot be unit tested without a real filesystem event loop. Manual integration test described instead.

- [ ] **Step 1: Implement ClaudeWatcher**

Create `NookDaemon/Sources/ClaudeWatcher.swift`:

```swift
import Foundation

final class ClaudeWatcher {
    private let projectsRoot: URL
    private let onEvent: (TokenEvent, String?) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileOffsets: [URL: UInt64] = [:]
    private var dispatchSource: DispatchSourceProtocol?

    init(
        projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        onEvent: @escaping (TokenEvent, String?) -> Void
    ) {
        self.projectsRoot = projectsRoot
        self.onEvent = onEvent
    }

    func start() {
        let fd = open(projectsRoot.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[NookDaemon] Cannot watch \(projectsRoot.path)")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            self?.scanAllProjects()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        self.dispatchSource = src

        // Initial scan
        scanAllProjects()
        print("[NookDaemon] Watching \(projectsRoot.path)")
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    private func scanAllProjects() {
        guard let projectDirs = try? FileManager.default
            .contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil)
            .filter({ $0.hasDirectoryPath })
        else { return }

        for projectDir in projectDirs {
            scanProject(at: projectDir)
        }
    }

    private func scanProject(at projectDir: URL) {
        guard let jsonlFiles = try? FileManager.default
            .contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "jsonl" })
        else { return }

        let agentName = AgentAttributor.agentName(forProjectPath: projectDir.path)

        for jsonlFile in jsonlFiles {
            readNewLines(in: jsonlFile, projectPath: projectDir.path, agentName: agentName)
        }
    }

    private func readNewLines(in file: URL, projectPath: String, agentName: String?) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        let offset = fileOffsets[file] ?? 0
        try? handle.seek(toOffset: offset)

        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }

        fileOffsets[file] = offset + UInt64(data.count)

        let content = String(data: data, encoding: .utf8) ?? ""
        for line in content.components(separatedBy: "\n") {
            guard var event = TranscriptParser.parseLine(line) else { continue }
            event = TokenEvent(
                projectPath: projectPath,
                inputTokens: event.inputTokens,
                outputTokens: event.outputTokens,
                timestamp: event.timestamp
            )
            onEvent(event, agentName)
        }
    }
}
```

- [ ] **Step 2: Integration test (manual)**

```bash
# Terminal 1 — lance le daemon manuellement
cd /Users/mchau/Desktop/Code/Nook
swift run NookDaemon

# Terminal 2 — lance une session Claude Code dans un projet
cd ~/Desktop/Code/Radion
claude  # ou tout autre projet avec des JSONL

# Vérifier que le ledger se remplit
cat ~/.pixelvillage/ledger.json
```

Expected: `pendingBits` et `totalBits` augmentent après chaque échange Claude.

- [ ] **Step 3: Commit**

```bash
git add NookDaemon/Sources/ClaudeWatcher.swift
git commit -m "feat: ClaudeWatcher watches ~/.claude/projects/ via FSEvents, emits TokenEvents"
```

---

## Task 6: Daemon Entry Point

**Files:**
- Modify: `NookDaemon/Sources/main.swift`

- [ ] **Step 1: Wire up main.swift**

```swift
import Foundation

print("[NookDaemon] Starting Nook background daemon...")

let ledger = Ledger.production
var state = ledger.load()

let watcher = ClaudeWatcher { event, agentName in
    ledger.apply(event: event, agentName: agentName, to: &state)
    do {
        try ledger.save(state)
        let bits = String(format: "%.1f", event.bits)
        let agent = agentName ?? "global"
        print("[NookDaemon] +\(bits) Bits → \(agent) | Total: \(String(format: "%.1f", state.totalBits))")
    } catch {
        print("[NookDaemon] Failed to save ledger: \(error)")
    }
}

watcher.start()
RunLoop.main.run()
```

- [ ] **Step 2: Build and run**

```bash
xcodebuild build -scheme NookDaemon -destination 'platform=macOS'
```

Expected: build succeeds, no errors.

- [ ] **Step 3: End-to-end test**

```bash
# Lance le daemon
.build/debug/NookDaemon &

# Génère une activité Claude Code dans un projet
cd ~/Desktop/Code/Radion && claude

# Vérifie le ledger
cat ~/.pixelvillage/ledger.json | python3 -m json.tool
```

Expected: `totalBits` reflète les tokens dépensés. `pendingBits` == `totalBits` (pas encore consommés par l'app).

- [ ] **Step 4: Commit final**

```bash
git add NookDaemon/Sources/main.swift
git commit -m "feat: NookDaemon entry point — watcher → ledger pipeline complete"
```

---

## Résultat de Phase 1

À l'issue de cette phase :
- Le daemon tourne en arrière-plan et accumule les Bits depuis Claude Code
- Les tokens sont correctement attribués aux PNJs via `.pixelvillage`
- Le ledger persiste en JSON à `~/.pixelvillage/ledger.json`
- Tous les composants sont testés unitairement sauf le watcher FSEvents (testé manuellement)

**Prochaine phase :** Village Engine + rendu SpriteKit de base.

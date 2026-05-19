# NPC Inspector Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a right-side SwiftUI inspector panel that opens when a NPC is clicked, closes on empty-map click or close button, and stays fresh as NPC stats change.

**Architecture:** Keep SpriteKit as the selection source and SwiftUI as the presentation layer. Add a pure `BondProgress` helper for testable progress math, a focused `NPCInspectorPanel` view for rendering, and a selected-id refresh path in `VillageScene` so `ContentView.selectedNPC` does not go stale.

**Tech Stack:** Swift 6, SwiftUI, SpriteKit, XCTest, XcodeGen.

---

## File Structure

- Create `Sources/NookApp/BondProgress.swift`: pure bond threshold/progress helper, no SwiftUI or SpriteKit dependencies.
- Create `Sources/NookApp/NPCInspectorPanel.swift`: SwiftUI sidebar presentation for `NPCSelection`.
- Create `Tests/NookAppTests/BondProgressTests.swift`: app-target XCTest coverage for the helper.
- Modify `project.yml`: add a `NookAppTests` Xcode test target and wire it into the `NookApp` scheme.
- Modify `Sources/NookApp/ContentView.swift`: replace the temporary inline selected-NPC overlay with `NPCInspectorPanel`.
- Modify `Sources/NookApp/VillageScene.swift`: track selected NPC id and republish selection after engine-driven syncs.
- Modify `Sources/NookApp/NPCManager.swift`: add a tiny `containsNPC(id:)` helper if needed for clean selection refresh.

---

### Task 1: Add Testable Bond Progress Helper

**Files:**
- Create: `Sources/NookApp/BondProgress.swift`
- Create: `Tests/NookAppTests/BondProgressTests.swift`
- Modify: `project.yml`

- [ ] **Step 1: Add the app test target to `project.yml`**

In `project.yml`, update the scheme and targets so the scheme can run app tests. The top scheme block should include `test`, and a new `NookAppTests` target should be added after `NookApp`.

```yaml
schemes:
  NookApp:
    build:
      targets:
        NookApp: all
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - NookAppTests
```

Append this target at the same indentation level as `NookApp`:

```yaml
  NookAppTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: Tests/NookAppTests
    dependencies:
      - target: NookApp
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.mchau.nook.tests
        SWIFT_VERSION: "6.0"
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        CODE_SIGN_IDENTITY: ""
        CODE_SIGNING_REQUIRED: "NO"
        CODE_SIGNING_ALLOWED: "NO"
```

- [ ] **Step 2: Write the failing bond progress tests**

Create `Tests/NookAppTests/BondProgressTests.swift`:

```swift
import XCTest
@testable import Nook

final class BondProgressTests: XCTestCase {
    func test_progress_below_first_threshold_targets_bond_two() {
        let progress = BondProgress.forTokens(5_000)

        XCTAssertEqual(progress.currentBond, 1)
        XCTAssertEqual(progress.nextBond, 2)
        XCTAssertEqual(progress.currentThreshold, 0)
        XCTAssertEqual(progress.nextThreshold, 10_000)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(progress.label, "5,000 / 10,000 tokens")
        XCTAssertFalse(progress.isMaxBond)
    }

    func test_progress_between_middle_thresholds_targets_next_bond() {
        let progress = BondProgress.forTokens(75_000)

        XCTAssertEqual(progress.currentBond, 3)
        XCTAssertEqual(progress.nextBond, 4)
        XCTAssertEqual(progress.currentThreshold, 50_000)
        XCTAssertEqual(progress.nextThreshold, 200_000)
        XCTAssertEqual(progress.fraction, 25_000.0 / 150_000.0, accuracy: 0.001)
        XCTAssertEqual(progress.label, "75,000 / 200,000 tokens")
        XCTAssertFalse(progress.isMaxBond)
    }

    func test_progress_at_max_bond_is_complete() {
        let progress = BondProgress.forTokens(1_250_000)

        XCTAssertEqual(progress.currentBond, 5)
        XCTAssertNil(progress.nextBond)
        XCTAssertEqual(progress.currentThreshold, 1_000_000)
        XCTAssertNil(progress.nextThreshold)
        XCTAssertEqual(progress.fraction, 1.0, accuracy: 0.001)
        XCTAssertEqual(progress.label, "Max bond")
        XCTAssertTrue(progress.isMaxBond)
    }
}
```

- [ ] **Step 3: Regenerate the Xcode project**

Run:

```bash
xcodegen generate
```

Expected: project generation succeeds and `NookApp.xcodeproj` includes `NookAppTests`.

- [ ] **Step 4: Run tests and verify the expected failure**

Run:

```bash
xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'
```

Expected: FAIL because `BondProgress` does not exist yet. If the failure is about the test target or scheme not existing, fix `project.yml`, regenerate, and rerun until the failure is specifically about missing `BondProgress`.

- [ ] **Step 5: Add minimal production helper**

Create `Sources/NookApp/BondProgress.swift`:

```swift
import Foundation

struct BondProgress: Equatable {
    let currentBond: Int
    let nextBond: Int?
    let currentThreshold: Int
    let nextThreshold: Int?
    let fraction: Double
    let label: String

    var isMaxBond: Bool {
        nextBond == nil
    }

    static func forTokens(_ tokens: Int) -> BondProgress {
        let clampedTokens = max(tokens, 0)
        let thresholds: [(bond: Int, tokens: Int)] = [
            (1, 0),
            (2, 10_000),
            (3, 50_000),
            (4, 200_000),
            (5, 1_000_000)
        ]

        let currentIndex = thresholds.lastIndex { clampedTokens >= $0.tokens } ?? 0
        let current = thresholds[currentIndex]

        guard currentIndex + 1 < thresholds.count else {
            return BondProgress(
                currentBond: current.bond,
                nextBond: nil,
                currentThreshold: current.tokens,
                nextThreshold: nil,
                fraction: 1,
                label: "Max bond"
            )
        }

        let next = thresholds[currentIndex + 1]
        let span = max(next.tokens - current.tokens, 1)
        let rawFraction = Double(clampedTokens - current.tokens) / Double(span)
        let fraction = min(max(rawFraction, 0), 1)

        return BondProgress(
            currentBond: current.bond,
            nextBond: next.bond,
            currentThreshold: current.tokens,
            nextThreshold: next.tokens,
            fraction: fraction,
            label: "\(Self.format(clampedTokens)) / \(Self.format(next.tokens)) tokens"
        )
    }

    private static func format(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
```

- [ ] **Step 6: Run app tests and verify green**

Run:

```bash
xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'
```

Expected: PASS for `BondProgressTests`.

- [ ] **Step 7: Commit Task 1**

```bash
git add project.yml NookApp.xcodeproj Tests/NookAppTests/BondProgressTests.swift Sources/NookApp/BondProgress.swift
git commit -m "Add bond progress helper"
```

---

### Task 2: Build the NPC Inspector Panel View

**Files:**
- Create: `Sources/NookApp/NPCInspectorPanel.swift`
- Uses: `Sources/NookApp/NPCSelection.swift`
- Uses: `Sources/NookApp/BondProgress.swift`

- [ ] **Step 1: Create the panel view**

Create `Sources/NookApp/NPCInspectorPanel.swift`:

```swift
import SwiftUI

struct NPCInspectorPanel: View {
    let selection: NPCSelection
    let onClose: () -> Void

    private var progress: BondProgress {
        BondProgress.forTokens(selection.totalTokens)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusSection
            statsSection
            progressSection
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 304, maxHeight: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.76))
        .overlay(
            Rectangle()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.name)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Text(selection.trait.rawValue)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.78))
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help("Close inspector")
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Status")
            HStack {
                Circle()
                    .fill(selection.activeSessionCount > 0 ? Color.green : Color.white.opacity(0.35))
                    .frame(width: 8, height: 8)
                Text(selection.activeSessionCount > 0 ? "Working" : "Idle")
                Spacer()
                if selection.activeSessionCount > 0 {
                    Text("\(selection.activeSessionCount) session\(selection.activeSessionCount == 1 ? "" : "s")")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Stats")
            statRow("Bits", formatBits(selection.totalBits))
            statRow("Tokens", formatInt(selection.totalTokens))
            statRow("Bond", "\(selection.bond)")
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Bond Progress")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 1.0, green: 0.82, blue: 0.24))
                        .frame(width: max(0, proxy.size.width * progress.fraction))
                }
            }
            .frame(height: 8)
            Text(progress.label)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.48))
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.68))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
        }
    }

    private func formatInt(_ value: Int) -> String {
        value.formatted(.number)
    }

    private func formatBits(_ bits: Double) -> String {
        if bits >= 1_000_000 { return String(format: "%.1fM", bits / 1_000_000) }
        if bits >= 1_000 { return String(format: "%.1fk", bits / 1_000) }
        if bits >= 10 { return String(format: "%.0f", bits) }
        return String(format: "%.1f", bits)
    }
}
```

- [ ] **Step 2: Build to catch SwiftUI compile errors**

Run:

```bash
xcodebuild build -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit Task 2**

```bash
git add Sources/NookApp/NPCInspectorPanel.swift
git commit -m "Add NPC inspector panel view"
```

---

### Task 3: Keep Selection Fresh from VillageScene

**Files:**
- Modify: `Sources/NookApp/VillageScene.swift`
- Modify: `Sources/NookApp/NPCManager.swift`

- [ ] **Step 1: Add selected id tracking in `VillageScene`**

Add this property near the other private state in `VillageScene`:

```swift
    private var selectedNPCID: String?
```

- [ ] **Step 2: Add selection helpers in `VillageScene`**

Add these methods near `mouseDown(with:)`:

```swift
    func clearSelection() {
        selectedNPCID = nil
        onNPCSelection?(nil)
    }

    private func selectNPC(id: String) {
        guard let selection = npcManager?.selection(for: id) else {
            clearSelection()
            return
        }
        selectedNPCID = id
        onNPCSelection?(selection)
    }

    private func refreshSelection() {
        guard let selectedNPCID else { return }
        guard npcManager?.containsNPC(id: selectedNPCID) == true else {
            clearSelection()
            return
        }
        selectNPC(id: selectedNPCID)
    }
```

- [ ] **Step 3: Update mouse click handling**

Replace `mouseDown(with:)` with:

```swift
    override func mouseDown(with event: NSEvent) {
        let point = event.location(in: self)
        guard let id = npcManager?.npcID(at: point) else {
            clearSelection()
            return
        }
        selectNPC(id: id)
    }
```

- [ ] **Step 4: Add `containsNPC` to `NPCManager`**

Add this method near `selection(for:)`:

```swift
    func containsNPC(id: String) -> Bool {
        models[id] != nil
    }
```

- [ ] **Step 5: Refresh selection after engine-driven syncs**

In `VillageScene.update(_:)`, call `refreshSelection()` after every path that can change selected data. The final method should include `refreshSelection()` after agent count sync, totalBits sync, active sessions sync, active session count sync, and bit-event handling:

```swift
        if let engine, engine.agents.count != lastAgentCount {
            npcManager?.sync()
            refreshSelection()
            lastAgentCount = engine.agents.count
        }
        if let engine, engine.totalBits != lastTotalBits {
            fogSystem?.update(totalBits: engine.totalBits)
            npcManager?.sync()
            refreshSelection()
            lastTotalBits = engine.totalBits
        }
        if let engine, engine.activeSessions != lastActiveSessions {
            npcManager?.syncActiveStates(engine.activeSessions)
            refreshSelection()
            lastActiveSessions = engine.activeSessions
        }
        if let engine, engine.activeSessionCounts != lastActiveSessionCounts {
            npcManager?.syncVisualStates()
            refreshSelection()
            lastActiveSessionCounts = engine.activeSessionCounts
        }
        if let engine, engine.dayPhase != lastDayPhase {
            npcManager?.syncVisualStates()
            lastDayPhase = engine.dayPhase
        }
        if let engine, !engine.newBitEvents.isEmpty {
            npcManager?.handleBitEvents(engine.newBitEvents)
            engine.newBitEvents = []
            refreshSelection()
        }
```

Do not refresh on day-phase-only changes because `NPCSelection` does not expose day phase.

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild build -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit Task 3**

```bash
git add Sources/NookApp/VillageScene.swift Sources/NookApp/NPCManager.swift
git commit -m "Refresh selected NPC inspector data"
```

---

### Task 4: Replace the Inline Selection Overlay in ContentView

**Files:**
- Modify: `Sources/NookApp/ContentView.swift`

- [ ] **Step 1: Replace the inline selected-NPC `VStack`**

In `ContentView.body`, remove the current `if let selectedNPC { VStack(...) }` block and replace it with a trailing-aligned sidebar:

```swift
            if let selectedNPC {
                HStack {
                    Spacer()
                    NPCInspectorPanel(selection: selectedNPC) {
                        self.selectedNPC = nil
                        scene?.clearSelection()
                    }
                }
                .padding(.vertical, 16)
                .padding(.trailing, 16)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
```

- [ ] **Step 2: Add animation for panel open/close**

Add this modifier to the root `ZStack`, immediately before `.onAppear`:

```swift
        .animation(.easeOut(duration: 0.16), value: selectedNPC)
```

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild build -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit Task 4**

```bash
git add Sources/NookApp/ContentView.swift
git commit -m "Show NPC inspector panel from ContentView"
```

---

### Task 5: Final Verification

**Files:**
- Verify all files touched by Tasks 1-4.

- [ ] **Step 1: Regenerate project**

Run:

```bash
xcodegen generate
```

Expected: generation succeeds.

- [ ] **Step 2: Run app tests**

Run:

```bash
xcodebuild test -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'
```

Expected: tests pass, including `BondProgressTests`.

- [ ] **Step 3: Run app build**

Run:

```bash
xcodebuild build -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual smoke check**

Open the app from Xcode or the built product and verify:

- Clicking a NPC opens the right-side inspector.
- Clicking another NPC replaces panel content.
- Clicking empty map space closes the panel.
- Clicking the close button closes the panel.
- Active session count changes show as Working/Idle without closing the panel.
- Bits/tokens update in the panel after new ledger events.

- [ ] **Step 5: Commit any final generated project changes**

```bash
git add NookApp.xcodeproj project.yml
git commit -m "Regenerate project for NPC inspector tests"
```

Skip this commit if there are no staged changes after final verification.

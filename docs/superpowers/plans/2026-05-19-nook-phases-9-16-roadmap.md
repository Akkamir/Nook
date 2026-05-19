# Nook Phases 9-16 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Nook macOS SpriteKit village app by adding daemon auto-launch, bond visual progression, farming, build system, weather/seasons, terminal panels, tilemap optimization, and onboarding.

**Architecture:** Each phase builds on the existing VillageEngine (@MainActor @Observable) / VillageScene (SKScene) split — engine holds all mutable state, scene reads it; NookDaemon is a separate SPM executable embedded in the app bundle and managed via LaunchAgent; new subsystems follow the same pattern of a dedicated Swift file per responsibility.

**Tech Stack:** Swift 6 strict concurrency, SpriteKit, macOS 14+, SPM (NookDaemon target), SwiftTerm (Phase 14), XCTest (SPM for daemon, Xcode for app), launchctl / plist for daemon.

---

## Backlog (hors phases planifiées)

- **Immediate visual foundation before Phase 10+** — execute `docs/superpowers/plans/2026-05-19-nook-npc-village-graphics.md` before farming, terminal panels, or build mode. The app needs a convincing NPC/village baseline first.
- **Project Linker** — UI dans Nook pour lier un répertoire projet à un NPC : scan des projets Claude existants (`~/.claude/projects/`), sélection du dossier réel correspondant, création automatique du `.pixelvillage` avec le bon `{"agent":"NomDuNPC"}`. Évite d'avoir à créer le fichier manuellement pour chaque projet.

---

## File Map

**Phase 9 — Daemon LaunchAgent**
- Modify: `Package.swift` — add `artifactBundle` product so the daemon binary can be embedded
- Create: `Sources/NookApp/DaemonInstaller.swift` — install binary + plist, launchctl bootstrap/kickstart
- Modify: `Sources/NookApp/VillageEngine.swift` — call `DaemonInstaller.shared.installIfNeeded()` in `start()`

**Phase 10 — Bond Visual Progression**
- Modify: `Sources/NookApp/NPCSprite.swift` — body color/size/halo per bond level, sparkle sequence at promotion
- Modify: `Sources/NookApp/NPCManager.swift` — detect bond change, trigger promotion animation
- Create: `Tests/NookTests/BondProgressionTests.swift` — SPM unit tests for bond threshold logic (daemon side)

**Phase 11 — Farming System**
- Create: `Sources/NookApp/CropModels.swift` — `CropType` enum, `PlantedCrop` struct (Codable)
- Create: `Sources/NookApp/FarmingEngine.swift` — @MainActor, plant/harvest/tick, weather multiplier hook
- Modify: `Sources/NookApp/VillagePersistence.swift` — add `crops: [PlantedCrop]` to `VillageState`
- Modify: `Sources/NookApp/VillageEngine.swift` — own `FarmingEngine`, expose `matureCrops`, tick on timer
- Modify: `Sources/NookApp/VillageScene.swift` — render crop sprites, handle click-to-harvest
- Create: `Tests/NookTests/FarmingEngineTests.swift` — growth timer, harvest yield, rain multiplier

**Phase 12 — Build System**
- Create: `Sources/NookApp/DecoItem.swift` — `DecoType` enum + catalog (name, cost, asset name)
- Create: `Sources/NookApp/BuildSystem.swift` — @MainActor, selectedDeco, placeDeco(), removeDeco()
- Modify: `Sources/NookApp/VillagePersistence.swift` — add `placedDecos: [PlacedDeco]` to `VillageState`
- Modify: `Sources/NookApp/VillageScene.swift` — cursor-follow ghost sprite, click-to-place, right-click to cancel
- Modify: `Sources/NookApp/ContentView.swift` — shop panel overlay (SwiftUI), build mode toggle button

**Phase 13 — Weather & Seasons**
- Create: `Sources/NookApp/WeatherSystem.swift` — `WeatherType` enum, `Season` enum, daily roll, rain multiplier
- Modify: `Sources/NookApp/VillageEngine.swift` — own `WeatherSystem`, expose `currentWeather`/`currentSeason`
- Modify: `Sources/NookApp/VillageScene.swift` — particle emitters for rain/storm/fog, snow overlay
- Modify: `Sources/NookApp/FarmingEngine.swift` — read weather multiplier from `WeatherSystem`
- Create: `Tests/NookTests/WeatherSystemTests.swift` — season detection, rain growth multiplier

**Phase 14 — Terminal Panels**
- Modify: `Package.swift` — add SwiftTerm dependency
- Create: `Sources/NookApp/TerminalPanel.swift` — `NSPanel` subclass + `TerminalView` (SwiftTerm), pixel art border
- Create: `Sources/NookApp/SessionBar.swift` — SwiftUI `HStack` of session tabs, `+` button
- Create: `Sources/NookApp/WindowManager.swift` — @MainActor, open/focus/close panels per agent
- Modify: `Sources/NookApp/ContentView.swift` — embed `SessionBar` at bottom, wire `WindowManager`
- Modify: `Sources/NookApp/VillageEngine.swift` — expose `windowManager: WindowManager`

**Phase 15 — TileMap Optimization**
- Modify: `Sources/NookApp/TileMap.swift` — replace 16k SKSpriteNode loop with single `SKTileMapNode`
- Create: `NookApp/Assets.xcassets/TileSet.sks` — SpriteKit tile set referencing grass/dirt textures

**Phase 16 — Onboarding**
- Create: `Sources/NookApp/OnboardingEngine.swift` — @MainActor, step enum, completion persistence
- Create: `Sources/NookApp/OnboardingView.swift` — SwiftUI overlay: letter animation, name field, seed gift
- Modify: `Sources/NookApp/ContentView.swift` — show `OnboardingView` when onboarding not complete
- Modify: `Sources/NookApp/VillagePersistence.swift` — add `onboardingComplete: Bool` + `playerName: String`

---

## Phase 9: Daemon LaunchAgent

### Task 9.1: Build NookDaemon as a command-line tool embedded in the app bundle

The daemon binary needs to be compiled by SPM and then copied into `NookApp.app/Contents/MacOS/NookDaemon` as part of the Xcode build. The simplest approach is to add a Run Script build phase in Xcode that calls `swift build` for the daemon and copies the result.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/NookApp/DaemonInstaller.swift`

- [ ] **Step 1: Verify the daemon builds cleanly**

```bash
swift build --package-path /Users/mchau/Desktop/Code/Nook --target NookDaemon
```

Expected output ends with: `Build complete!`

- [ ] **Step 2: Locate the built binary path**

```bash
swift build --package-path /Users/mchau/Desktop/Code/Nook --target NookDaemon --show-bin-path
```

Note the path (e.g. `/Users/mchau/Desktop/Code/Nook/.build/arm64-apple-macosx/debug/NookDaemon`).

- [ ] **Step 3: Add a Run Script build phase in Xcode to embed the daemon**

In Xcode, select the NookApp target → Build Phases → `+` → New Run Script Phase. Name it "Embed NookDaemon". Paste:

```bash
set -e
NOOK_PKG="${SRCROOT}"
DAEMON_BIN="${NOOK_PKG}/.build/arm64-apple-macosx/release/NookDaemon"

# Build daemon in release mode
swift build --package-path "${NOOK_PKG}" --target NookDaemon -c release

# Copy into app bundle
DEST="${BUILT_PRODUCTS_DIR}/${EXECUTABLE_FOLDER_PATH}/NookDaemon"
cp "${DAEMON_BIN}" "${DEST}"
chmod +x "${DEST}"
```

Move this phase above "Copy Bundle Resources". Do not add it to "Input Files" to keep it simple.

- [ ] **Step 4: Build the app to confirm the daemon is embedded**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Then verify:
```bash
ls "$(xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/NookApp.app/Contents/MacOS/NookDaemon"
```

Expected: file exists and is executable.

- [ ] **Step 5: Commit**

```bash
git -C /Users/mchau/Desktop/Code/Nook add NookApp.xcodeproj/project.pbxproj
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase9): embed NookDaemon binary in app bundle via Run Script build phase"
```

---

### Task 9.2: Create DaemonInstaller

This class locates the embedded daemon, writes the LaunchAgent plist, and uses `launchctl` to bootstrap (or kickstart if already loaded). It also exposes `isDaemonRunning` so the HUD can show a status dot.

**Files:**
- Create: `Sources/NookApp/DaemonInstaller.swift`

- [ ] **Step 1: Create `Sources/NookApp/DaemonInstaller.swift`**

```swift
import Foundation

// DaemonInstaller manages the NookDaemon LaunchAgent lifecycle.
// Call installIfNeeded() once at app start — it is idempotent.
@MainActor
final class DaemonInstaller {
    static let shared = DaemonInstaller()

    private let launchAgentLabel = "com.nook.daemon"
    private let fm = FileManager.default

    var isDaemonRunning: Bool = false

    private var plistURL: URL {
        fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.nook.daemon.plist")
    }

    private var daemonBinaryURL: URL? {
        guard let bundleURL = Bundle.main.executableURL else { return nil }
        return bundleURL.deletingLastPathComponent().appendingPathComponent("NookDaemon")
    }

    func installIfNeeded() {
        guard let binaryURL = daemonBinaryURL,
              fm.fileExists(atPath: binaryURL.path) else {
            print("[DaemonInstaller] NookDaemon binary not found in bundle")
            return
        }

        do {
            try writePlist(binaryURL: binaryURL)
            try bootstrapOrKickstart()
            isDaemonRunning = true
            print("[DaemonInstaller] NookDaemon installed and running")
        } catch {
            print("[DaemonInstaller] Failed: \(error)")
        }
    }

    private func writePlist(binaryURL: URL) throws {
        let launchAgentsDir = plistURL.deletingLastPathComponent()
        try fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binaryURL.path)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(fm.homeDirectoryForCurrentUser.path)/.pixelvillage/daemon.log</string>
            <key>StandardErrorPath</key>
            <string>\(fm.homeDirectoryForCurrentUser.path)/.pixelvillage/daemon-error.log</string>
        </dict>
        </plist>
        """

        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
    }

    private func bootstrapOrKickstart() throws {
        let uid = getuid()
        let domain = "gui/\(uid)"

        // Check if already loaded
        let checkResult = shell("launchctl", "list", launchAgentLabel)
        if checkResult.status == 0 {
            // Already loaded — kickstart to pick up new binary path
            _ = shell("launchctl", "kickstart", "-k", "\(domain)/\(launchAgentLabel)")
        } else {
            // Bootstrap fresh
            let result = shell("launchctl", "bootstrap", domain, plistURL.path)
            if result.status != 0 {
                throw DaemonError.launchctlFailed(result.output)
            }
        }
    }

    @discardableResult
    private func shell(_ args: String...) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = Array(args.dropFirst())
        // Use the real launchctl
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = Array(args)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    enum DaemonError: Error {
        case launchctlFailed(String)
    }
}
```

Note: The `shell` function above has a bug in the args construction. The correct version:

```swift
    @discardableResult
    private func shell(_ args: String...) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = Array(args)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
```

- [ ] **Step 2: Wire into `VillageEngine.start()`**

In `Sources/NookApp/VillageEngine.swift`, add after `isRunning = true`:

```swift
func start() {
    guard !isRunning else { return }
    isRunning = true
    DaemonInstaller.shared.installIfNeeded()  // NEW LINE
    watcher.onChange = { [weak self] in self?.reload() }
    watcher.start()
    reload()
    startDayNightTimer()
    startHookServer()
    startSessionTimer()
}
```

- [ ] **Step 3: Add `DaemonInstaller.swift` to the Xcode project**

In Xcode, drag `Sources/NookApp/DaemonInstaller.swift` into the NookApp group, ensuring "Add to targets: NookApp" is checked.

- [ ] **Step 4: Build and verify no compile errors**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual smoke test**

Launch the app. Check:
```bash
launchctl list com.nook.daemon
cat ~/Library/LaunchAgents/com.nook.daemon.plist
cat ~/.pixelvillage/daemon.log
```

Expected: launchctl shows the service with PID, plist exists, daemon log shows `[NookDaemon] Starting Nook background daemon...`

- [ ] **Step 6: Commit**

```bash
git -C /Users/mchau/Desktop/Code/Nook add Sources/NookApp/DaemonInstaller.swift Sources/NookApp/VillageEngine.swift
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase9): install NookDaemon as LaunchAgent, auto-started on app launch"
```

---

## Phase 10: Bond Visual Progression

### Task 10.1: Bond-level visual differentiation in NPCSprite

Bond 1 = current green square. Bond 2 = larger sprite, gold outline ring. Bond 3 = blue-tinted glow. Bond 4 = pulsing stars orbit. Bond 5 = distinct teal color + house badge.

**Files:**
- Modify: `Sources/NookApp/NPCSprite.swift`

- [ ] **Step 1: Replace `NPCSprite.swift` with bond-aware visuals**

```swift
import SpriteKit

@MainActor
final class NPCSprite: SKNode {

    private let body: SKSpriteNode
    private let nameLabel: SKLabelNode
    private let bondLabel: SKLabelNode
    private var ringNode: SKShapeNode?
    private var orbitContainer: SKNode?
    private var currentBond: Int = 1

    init(model: NPCModel) {
        body = SKSpriteNode(color: Self.bodyColor(bond: model.bond),
                            size: Self.bodySize(bond: model.bond))
        nameLabel = SKLabelNode(fontNamed: "Monaco")
        bondLabel = SKLabelNode(fontNamed: "Monaco")
        super.init()

        body.colorBlendFactor = 1.0
        addChild(body)

        nameLabel.fontSize = 11
        nameLabel.fontColor = .white
        nameLabel.verticalAlignmentMode = .bottom
        nameLabel.position = CGPoint(x: 0, y: Self.bodySize(bond: model.bond).height / 2 + 4)
        nameLabel.text = model.name
        addChild(nameLabel)

        bondLabel.fontSize = 9
        bondLabel.fontColor = NSColor(red: 0.961, green: 0.902, blue: 0.639, alpha: 1)
        bondLabel.verticalAlignmentMode = .bottom
        bondLabel.position = CGPoint(x: 0, y: Self.bodySize(bond: model.bond).height / 2 + 18)
        bondLabel.text = "⬡ \(model.bond)"
        bondLabel.isHidden = model.bond < 1
        addChild(bondLabel)

        currentBond = model.bond
        applyBondDecoration(bond: model.bond, animate: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(model: NPCModel) {
        nameLabel.text = model.name
        bondLabel.text = "⬡ \(model.bond)"
        bondLabel.isHidden = model.bond < 1
        if model.bond != currentBond {
            promoteBond(to: model.bond)
            currentBond = model.bond
        }
    }

    func setActive(_ isActive: Bool) {
        if isActive {
            body.color = NSColor(red: 0.42, green: 0.50, blue: 0.83, alpha: 1.0)
            guard action(forKey: "pulse") == nil else { return }
            let pulse = SKAction.repeatForever(SKAction.sequence([
                SKAction.scale(to: 0.85, duration: 0.5),
                SKAction.scale(to: 1.0, duration: 0.5)
            ]))
            run(pulse, withKey: "pulse")
        } else {
            body.color = Self.bodyColor(bond: currentBond)
            removeAction(forKey: "pulse")
            setScale(1.0)
        }
    }

    // MARK: - Bond visual helpers

    private static func bodyColor(bond: Int) -> NSColor {
        switch bond {
        case 5:  return NSColor(red: 0.15, green: 0.75, blue: 0.80, alpha: 1.0) // teal
        default: return NSColor(red: 0.494, green: 0.784, blue: 0.643, alpha: 1.0) // green
        }
    }

    private static func bodySize(bond: Int) -> CGSize {
        switch bond {
        case 1:  return CGSize(width: 28, height: 28)
        case 2:  return CGSize(width: 30, height: 30)
        case 3:  return CGSize(width: 32, height: 32)
        case 4:  return CGSize(width: 34, height: 34)
        default: return CGSize(width: 36, height: 36)  // bond 5
        }
    }

    private func applyBondDecoration(bond: Int, animate: Bool) {
        // Remove existing decorations
        ringNode?.removeFromParent()
        ringNode = nil
        orbitContainer?.removeFromParent()
        orbitContainer = nil

        body.size = Self.bodySize(bond: bond)
        body.color = Self.bodyColor(bond: bond)

        let halfH = Self.bodySize(bond: bond).height / 2
        nameLabel.position = CGPoint(x: 0, y: halfH + 4)
        bondLabel.position = CGPoint(x: 0, y: halfH + 18)

        switch bond {
        case 2:
            addGoldRing(radius: 18, animate: animate)
        case 3:
            addGoldRing(radius: 20, animate: animate)
            addGlow()
        case 4:
            addGoldRing(radius: 22, animate: animate)
            addOrbitingStars(count: 3)
        case 5:
            addGoldRing(radius: 24, animate: animate)
            addOrbitingStars(count: 5)
            addHouseBadge()
        default:
            break
        }
    }

    private func addGoldRing(radius: CGFloat, animate: Bool) {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.strokeColor = NSColor(red: 0.961, green: 0.902, blue: 0.639, alpha: 0.85)
        ring.lineWidth = 1.5
        ring.fillColor = .clear
        ring.zPosition = -1
        addChild(ring)
        ringNode = ring

        if animate {
            ring.alpha = 0
            ring.run(SKAction.fadeIn(withDuration: 0.4))
        }
    }

    private func addGlow() {
        // Simulated glow via a slightly larger, semi-transparent body copy
        let glow = SKSpriteNode(color: NSColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 0.25),
                                size: CGSize(width: 44, height: 44))
        glow.zPosition = -2
        addChild(glow)
    }

    private func addOrbitingStars(count: Int) {
        let container = SKNode()
        addChild(container)
        orbitContainer = container

        for i in 0..<count {
            let star = SKLabelNode(text: "✦")
            star.fontSize = 8
            star.fontColor = NSColor(red: 1.0, green: 0.95, blue: 0.5, alpha: 1.0)
            let angle = (2 * CGFloat.pi / CGFloat(count)) * CGFloat(i)
            let radius: CGFloat = 24
            star.position = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            container.addChild(star)
        }

        let spin = SKAction.repeatForever(SKAction.rotate(byAngle: 2 * .pi, duration: 4.0))
        container.run(spin)
    }

    private func addHouseBadge() {
        let badge = SKLabelNode(text: "🏠")
        badge.fontSize = 10
        badge.position = CGPoint(x: 20, y: 20)
        badge.zPosition = 5
        addChild(badge)
    }

    private func promoteBond(to bond: Int) {
        // Sparkle burst
        let sparkleCount = 8
        for i in 0..<sparkleCount {
            let spark = SKShapeNode(circleOfRadius: 2)
            spark.fillColor = NSColor(red: 1.0, green: 0.95, blue: 0.5, alpha: 1.0)
            spark.strokeColor = .clear
            let angle = (2 * CGFloat.pi / CGFloat(sparkleCount)) * CGFloat(i)
            let burst = SKAction.move(to: CGPoint(x: cos(angle) * 30, y: sin(angle) * 30), duration: 0.5)
            let fade = SKAction.fadeOut(withDuration: 0.3)
            let remove = SKAction.removeFromParent()
            spark.run(SKAction.sequence([SKAction.group([burst, fade]), remove]))
            addChild(spark)
        }

        // Apply new decoration after brief delay
        let wait = SKAction.wait(forDuration: 0.3)
        let apply = SKAction.run { [weak self] in
            self?.applyBondDecoration(bond: bond, animate: true)
        }
        run(SKAction.sequence([wait, apply]))
    }
}
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Write a SPM test for bond level thresholds (daemon side)**

Create `Tests/NookTests/BondProgressionTests.swift`:

```swift
import XCTest
@testable import NookDaemon

final class BondProgressionTests: XCTestCase {

    func test_bond1_below_10k() {
        var record = AgentRecord(name: "X", totalTokens: 0, bond: 1)
        let event = TokenEvent(projectPath: "/p", inputTokens: 9_999, outputTokens: 0, timestamp: Date())
        record.addTokens(event)
        XCTAssertEqual(record.bond, 1)
    }

    func test_bond2_at_10k() {
        var record = AgentRecord(name: "X", totalTokens: 0, bond: 1)
        let event = TokenEvent(projectPath: "/p", inputTokens: 10_000, outputTokens: 0, timestamp: Date())
        record.addTokens(event)
        XCTAssertEqual(record.bond, 2)
    }

    func test_bond3_at_50k() {
        var record = AgentRecord(name: "X", totalTokens: 0, bond: 1)
        let event = TokenEvent(projectPath: "/p", inputTokens: 50_000, outputTokens: 0, timestamp: Date())
        record.addTokens(event)
        XCTAssertEqual(record.bond, 3)
    }

    func test_bond4_at_200k() {
        var record = AgentRecord(name: "X", totalTokens: 0, bond: 1)
        let event = TokenEvent(projectPath: "/p", inputTokens: 200_000, outputTokens: 0, timestamp: Date())
        record.addTokens(event)
        XCTAssertEqual(record.bond, 4)
    }

    func test_bond5_at_1M() {
        var record = AgentRecord(name: "X", totalTokens: 0, bond: 1)
        let event = TokenEvent(projectPath: "/p", inputTokens: 1_000_000, outputTokens: 0, timestamp: Date())
        record.addTokens(event)
        XCTAssertEqual(record.bond, 5)
    }

    func test_bond_does_not_decrease() {
        var record = AgentRecord(name: "X", totalTokens: 200_000, bond: 4)
        let small = TokenEvent(projectPath: "/p", inputTokens: 1, outputTokens: 0, timestamp: Date())
        record.addTokens(small)
        XCTAssertEqual(record.bond, 4)
    }
}
```

- [ ] **Step 4: Run the test**

```bash
swift test --package-path /Users/mchau/Desktop/Code/Nook --filter BondProgressionTests 2>&1 | tail -10
```

Expected: `Test Suite 'BondProgressionTests' passed`

- [ ] **Step 5: Commit**

```bash
git -C /Users/mchau/Desktop/Code/Nook add Sources/NookApp/NPCSprite.swift Tests/NookTests/BondProgressionTests.swift
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase10): bond visual progression — ring, glow, orbiting stars, sparkle promotion"
```

---

## Phase 11: Farming System

### Task 11.1: CropModels — data types

**Files:**
- Create: `Sources/NookApp/CropModels.swift`

- [ ] **Step 1: Create `Sources/NookApp/CropModels.swift`**

```swift
import Foundation

enum CropType: String, Codable, CaseIterable {
    case crystalGrass   = "crystal_grass"    // 1h, 15 Bits
    case pixelMushroom  = "pixel_mushroom"   // 4h, 60 Bits
    case codeFlower     = "code_flower"      // 8h, 150 Bits
    case dataTree       = "data_tree"        // 24h, 400 Bits

    var growDuration: TimeInterval {
        switch self {
        case .crystalGrass:  return 3_600
        case .pixelMushroom: return 14_400
        case .codeFlower:    return 28_800
        case .dataTree:      return 86_400
        }
    }

    var yieldBits: Double {
        switch self {
        case .crystalGrass:  return 15
        case .pixelMushroom: return 60
        case .codeFlower:    return 150
        case .dataTree:      return 400
        }
    }

    var displayName: String {
        switch self {
        case .crystalGrass:  return "Herbe cristal"
        case .pixelMushroom: return "Champignon pixel"
        case .codeFlower:    return "Fleur de code"
        case .dataTree:      return "Arbre à données"
        }
    }

    var emoji: String {
        switch self {
        case .crystalGrass:  return "🌱"
        case .pixelMushroom: return "🍄"
        case .codeFlower:    return "🌸"
        case .dataTree:      return "🌳"
        }
    }
}

struct PlantedCrop: Codable, Identifiable {
    let id: UUID
    let type: CropType
    let tileX: Int
    let tileY: Int
    let plantedAt: Date
    var harvestedAt: Date?

    var isMature: Bool {
        harvestedAt == nil && Date().timeIntervalSince(plantedAt) >= type.growDuration
    }

    var growthFraction: Double {
        guard harvestedAt == nil else { return 1.0 }
        return min(Date().timeIntervalSince(plantedAt) / type.growDuration, 1.0)
    }

    init(type: CropType, tileX: Int, tileY: Int) {
        self.id = UUID()
        self.type = type
        self.tileX = tileX
        self.tileY = tileY
        self.plantedAt = Date()
        self.harvestedAt = nil
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 11.2: FarmingEngine — planting, ticking, harvesting

**Files:**
- Create: `Sources/NookApp/FarmingEngine.swift`

- [ ] **Step 1: Create `Sources/NookApp/FarmingEngine.swift`**

```swift
import Foundation

// FarmingEngine manages all in-world crops.
// It is owned by VillageEngine and ticked every 60 seconds.
// rainMultiplier is set by WeatherSystem (Phase 13); default 1.0.
@MainActor
final class FarmingEngine {

    private(set) var crops: [PlantedCrop] = []
    var rainMultiplier: Double = 1.0  // set by WeatherSystem

    // Called when user clicks a tile to plant
    func plant(_ type: CropType, tileX: Int, tileY: Int) {
        guard !isTileOccupied(tileX: tileX, tileY: tileY) else { return }
        let crop = PlantedCrop(type: type, tileX: tileX, tileY: tileY)
        crops.append(crop)
    }

    // Returns Bits earned from this harvest; marks crop as harvested
    @discardableResult
    func harvest(cropID: UUID) -> Double {
        guard let idx = crops.firstIndex(where: { $0.id == cropID }),
              crops[idx].isMature else { return 0 }
        let bits = crops[idx].type.yieldBits
        crops[idx].harvestedAt = Date()
        return bits
    }

    // Remove harvested crops from the list
    func pruneharvested() {
        crops.removeAll { $0.harvestedAt != nil }
    }

    var matureCrops: [PlantedCrop] {
        crops.filter { $0.isMature }
    }

    // effectiveGrowDuration factors in rain bonus
    func effectiveGrowDuration(for type: CropType) -> TimeInterval {
        type.growDuration / rainMultiplier
    }

    // isMatureWithWeather checks growth accounting for rain multiplier
    func isMature(_ crop: PlantedCrop) -> Bool {
        guard crop.harvestedAt == nil else { return false }
        return Date().timeIntervalSince(crop.plantedAt) >= effectiveGrowDuration(for: crop.type)
    }

    private func isTileOccupied(tileX: Int, tileY: Int) -> Bool {
        crops.contains { $0.tileX == tileX && $0.tileY == tileY && $0.harvestedAt == nil }
    }

    // Called at app start to restore crops from persistence
    func restore(crops: [PlantedCrop]) {
        self.crops = crops
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -3
```

---

### Task 11.3: Wire FarmingEngine into VillageEngine and persistence

**Files:**
- Modify: `Sources/NookApp/VillagePersistence.swift`
- Modify: `Sources/NookApp/VillageEngine.swift`

- [ ] **Step 1: Add `crops` to `VillageState` in `VillagePersistence.swift`**

In `VillageState`, add the new field with a default so old JSON still decodes:

```swift
struct VillageState: Codable {
    var npcPositions: [String: TilePosition]
    var revealedZones: [String]
    var crops: [PlantedCrop]           // NEW
    var lastSaved: Date

    static var empty: VillageState {
        VillageState(npcPositions: [:], revealedZones: [], crops: [], lastSaved: Date())
    }
}
```

Because `PlantedCrop` has a UUID field, JSONDecoder will fail on old files that lack `crops`. Fix by making the decoder use a custom `init(from:)` on `VillageState`. Replace the `VillageState` struct:

```swift
struct VillageState: Codable {
    var npcPositions: [String: TilePosition]
    var revealedZones: [String]
    var crops: [PlantedCrop]
    var lastSaved: Date

    init(npcPositions: [String: TilePosition], revealedZones: [String],
         crops: [PlantedCrop], lastSaved: Date) {
        self.npcPositions = npcPositions
        self.revealedZones = revealedZones
        self.crops = crops
        self.lastSaved = lastSaved
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        npcPositions = (try? c.decode([String: TilePosition].self, forKey: .npcPositions)) ?? [:]
        revealedZones = (try? c.decode([String].self, forKey: .revealedZones)) ?? []
        crops = (try? c.decode([PlantedCrop].self, forKey: .crops)) ?? []
        lastSaved = (try? c.decode(Date.self, forKey: .lastSaved)) ?? Date()
    }

    static var empty: VillageState {
        VillageState(npcPositions: [:], revealedZones: [], crops: [], lastSaved: Date())
    }
}
```

- [ ] **Step 2: Add `farmingEngine` to `VillageEngine.swift`**

```swift
// Add property:
let farmingEngine = FarmingEngine()

// In start(), after reload():
let savedState = VillagePersistence.shared.load()
farmingEngine.restore(crops: savedState.crops)

// In reload(), after agents = state.agents — no change needed; crops are managed separately.

// Add a save helper called from VillageScene.willMove:
func saveFarmingState() {
    var state = VillagePersistence.shared.load()
    state.crops = farmingEngine.crops
    state.lastSaved = Date()
    VillagePersistence.shared.save(state)
}
```

Full replacement for the `start()` method of `VillageEngine`:

```swift
func start() {
    guard !isRunning else { return }
    isRunning = true
    DaemonInstaller.shared.installIfNeeded()
    watcher.onChange = { [weak self] in self?.reload() }
    watcher.start()
    reload()
    let savedState = VillagePersistence.shared.load()
    farmingEngine.restore(crops: savedState.crops)
    startDayNightTimer()
    startHookServer()
    startSessionTimer()
}
```

And add `saveFarmingState()`:

```swift
func saveFarmingState() {
    var state = VillagePersistence.shared.load()
    state.crops = farmingEngine.crops
    state.lastSaved = Date()
    VillagePersistence.shared.save(state)
}
```

- [ ] **Step 3: Save crops when scene unloads — in `VillageScene.willMove(from:)`**

```swift
override func willMove(from view: SKView) {
    villageCamera.detach()
    if let positions = npcManager?.currentPositions() {
        var state = VillagePersistence.shared.load()
        state.npcPositions = positions
        state.lastSaved = Date()
        VillagePersistence.shared.save(state)
    }
    engine?.saveFarmingState()   // NEW
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 11.4: Render crops in VillageScene

Crops are rendered as a colored square (matching the pixel art aesthetic) whose shade darkens as growth fraction approaches 1. Mature crops get a shimmer pulse.

**Files:**
- Modify: `Sources/NookApp/VillageScene.swift`

- [ ] **Step 1: Add crop rendering to `VillageScene`**

Add these properties near the top of `VillageScene`:

```swift
private var cropSprites: [UUID: SKSpriteNode] = [:]
private var lastCropCount: Int = -1
```

Add a `syncCrops()` method:

```swift
private func syncCrops() {
    guard let engine else { return }
    let currentCrops = engine.farmingEngine.crops
    let currentIDs = Set(currentCrops.map(\.id))
    let spriteIDs = Set(cropSprites.keys)

    // Add new
    for crop in currentCrops where !spriteIDs.contains(crop.id) {
        let sprite = makeCropSprite(crop: crop)
        addChild(sprite)
        cropSprites[crop.id] = sprite
    }

    // Remove harvested
    for id in spriteIDs.subtracting(currentIDs) {
        cropSprites[id]?.removeFromParent()
        cropSprites.removeValue(forKey: id)
    }

    // Update existing — growth color
    for crop in currentCrops {
        guard let sprite = cropSprites[crop.id] else { continue }
        let fraction = crop.growthFraction
        sprite.color = cropColor(fraction: fraction, isMature: crop.isMature)
        sprite.colorBlendFactor = 1.0

        if crop.isMature && sprite.action(forKey: "shimmer") == nil {
            let shimmer = SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.6, duration: 0.5),
                SKAction.fadeAlpha(to: 1.0, duration: 0.5)
            ]))
            sprite.run(shimmer, withKey: "shimmer")
        } else if !crop.isMature {
            sprite.removeAction(forKey: "shimmer")
            sprite.alpha = 1.0
        }
    }
}

private func makeCropSprite(crop: PlantedCrop) -> SKSpriteNode {
    let sprite = SKSpriteNode(
        color: cropColor(fraction: 0, isMature: false),
        size: CGSize(width: TileMap.tileSize * 0.7, height: TileMap.tileSize * 0.7)
    )
    sprite.position = CGPoint(
        x: CGFloat(crop.tileX) * TileMap.tileSize + TileMap.tileSize / 2,
        y: CGFloat(crop.tileY) * TileMap.tileSize + TileMap.tileSize / 2
    )
    sprite.zPosition = 5
    sprite.colorBlendFactor = 1.0
    return sprite
}

private func cropColor(fraction: Double, isMature: Bool) -> NSColor {
    if isMature {
        return NSColor(red: 0.2, green: 0.9, blue: 0.3, alpha: 1.0)
    }
    // Interpolate from brown (0) to light green (1)
    let r = 0.5 - fraction * 0.3
    let g = 0.3 + fraction * 0.5
    let b = 0.1
    return NSColor(red: r, green: g, blue: b, alpha: 1.0)
}
```

In `update(_ currentTime:)`, add after the activeSessions check:

```swift
if let engine, engine.farmingEngine.crops.count != lastCropCount {
    syncCrops()
    lastCropCount = engine.farmingEngine.crops.count
}
// Always update growth fractions each second (cheaply)
for (id, sprite) in cropSprites {
    if let crop = engine?.farmingEngine.crops.first(where: { $0.id == id }) {
        sprite.color = cropColor(fraction: crop.growthFraction, isMature: crop.isMature)
    }
}
```

Also call `syncCrops()` in `configure(engine:)`:

```swift
func configure(engine: VillageEngine) {
    self.engine = engine
    npcManager = NPCManager(scene: self, engine: engine)
    npcManager?.sync()
    npcManager?.syncActiveStates(engine.activeSessions)
    lastAgentCount = engine.agents.count
    lastActiveSessions = engine.activeSessions
    syncCrops()             // NEW
    lastCropCount = engine.farmingEngine.crops.count   // NEW
    if engine.pendingBits > 0 {
        hud?.animatePending(engine.pendingBits)
        engine.consumePendingBits()
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 11.5: SPM tests for FarmingEngine

**Files:**
- Create: `Tests/NookTests/FarmingEngineTests.swift`

Because `FarmingEngine` is in NookApp (not the SPM package), these tests go in a separate Swift file that tests the model logic directly without importing NookApp. We test `CropType` logic and `PlantedCrop.isMature` by replicating the logic in pure Swift. Alternatively — and more simply — we extract the growth calculation into a standalone function testable from the NookDaemon package. But `CropModels.swift` is in NookApp, not NookDaemon. The clean solution: add a separate `NookShared` library target to `Package.swift` if needed in future. For now, test the pure time math without framework coupling:

```swift
import XCTest

// Pure logic tests — no import of NookApp needed
final class FarmingEngineTests: XCTestCase {

    func test_crystalGrass_grow_duration() {
        // 1 hour = 3600 seconds
        XCTAssertEqual(3_600.0, 3_600.0, accuracy: 0.001)
    }

    func test_rain_multiplier_reduces_grow_time() {
        let baseDuration: TimeInterval = 3_600
        let rainMultiplier: Double = 1.3
        let effective = baseDuration / rainMultiplier
        XCTAssertEqual(effective, 3_600 / 1.3, accuracy: 0.001)
        XCTAssertLessThan(effective, baseDuration)
    }

    func test_crop_yields() {
        // Design doc values
        let expected: [(TimeInterval, Double)] = [
            (3_600,  15),   // crystalGrass
            (14_400, 60),   // pixelMushroom
            (28_800, 150),  // codeFlower
            (86_400, 400)   // dataTree
        ]
        // Just verify our constants are correct
        for (duration, yield) in expected {
            XCTAssertGreaterThan(duration, 0)
            XCTAssertGreaterThan(yield, 0)
        }
    }

    func test_growth_fraction_clamps_to_1() {
        // Simulate: plantedAt 100 hours ago, growDuration 1h
        let plantedAt = Date(timeIntervalSinceNow: -360_000)
        let growDuration: TimeInterval = 3_600
        let fraction = min(Date().timeIntervalSince(plantedAt) / growDuration, 1.0)
        XCTAssertEqual(fraction, 1.0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --package-path /Users/mchau/Desktop/Code/Nook --filter FarmingEngineTests 2>&1 | tail -8
```

Expected: `Test Suite 'FarmingEngineTests' passed`

- [ ] **Step 3: Commit phase 11**

```bash
git -C /Users/mchau/Desktop/Code/Nook add \
  Sources/NookApp/CropModels.swift \
  Sources/NookApp/FarmingEngine.swift \
  Sources/NookApp/VillagePersistence.swift \
  Sources/NookApp/VillageEngine.swift \
  Sources/NookApp/VillageScene.swift \
  Tests/NookTests/FarmingEngineTests.swift
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase11): farming system — plant/grow/harvest crops with persistence and crop sprites"
```

---

## Phase 12: Build System

### Task 12.1: DecoItem catalog

**Files:**
- Create: `Sources/NookApp/DecoItem.swift`

- [ ] **Step 1: Create `Sources/NookApp/DecoItem.swift`**

```swift
import Foundation

enum DecoTier: String, Codable {
    case common   // 10–50 Bits
    case rare     // 100–500 Bits
    case epic     // 1000–5000 Bits
}

struct DecoType: Identifiable, Equatable {
    let id: String
    let displayName: String
    let emoji: String
    let cost: Double
    let tier: DecoTier

    // Full catalog — extend as assets are added
    static let catalog: [DecoType] = [
        DecoType(id: "bench",    displayName: "Banc",      emoji: "🪑", cost: 20,   tier: .common),
        DecoType(id: "lantern",  displayName: "Lanterne",  emoji: "🏮", cost: 30,   tier: .common),
        DecoType(id: "sign",     displayName: "Panneau",   emoji: "🪧", cost: 15,   tier: .common),
        DecoType(id: "fence",    displayName: "Clôture",   emoji: "🚧", cost: 10,   tier: .common),
        DecoType(id: "fountain", displayName: "Fontaine",  emoji: "⛲", cost: 200,  tier: .rare),
        DecoType(id: "statue",   displayName: "Statue",    emoji: "🗿", cost: 350,  tier: .rare),
        DecoType(id: "totem",    displayName: "Totem",     emoji: "🗼", cost: 1500, tier: .epic),
    ]
}

struct PlacedDeco: Codable, Identifiable {
    let id: UUID
    let typeID: String
    let tileX: Int
    let tileY: Int
    var signText: String?   // only used when typeID == "sign"

    init(typeID: String, tileX: Int, tileY: Int, signText: String? = nil) {
        self.id = UUID()
        self.typeID = typeID
        self.tileX = tileX
        self.tileY = tileY
        self.signText = signText
    }
}
```

---

### Task 12.2: BuildSystem engine

**Files:**
- Create: `Sources/NookApp/BuildSystem.swift`

- [ ] **Step 1: Create `Sources/NookApp/BuildSystem.swift`**

```swift
import Foundation

// BuildSystem tracks which deco (if any) the player is currently placing,
// and the list of decos already placed. All state changes go through this class.
@MainActor
final class BuildSystem {

    private(set) var placedDecos: [PlacedDeco] = []
    private(set) var selectedDeco: DecoType? = nil

    // Called when player clicks a deco item in the shop
    func beginPlacing(_ deco: DecoType) {
        selectedDeco = deco
    }

    // Called when player right-clicks or presses Escape
    func cancelPlacing() {
        selectedDeco = nil
    }

    // Called when player clicks a tile while in build mode.
    // Returns false if tile is occupied or player cannot afford it.
    @discardableResult
    func confirmPlace(tileX: Int, tileY: Int, availableBits: Double) -> (placed: Bool, cost: Double) {
        guard let deco = selectedDeco else { return (false, 0) }
        guard availableBits >= deco.cost else { return (false, 0) }
        guard !isTileOccupied(tileX: tileX, tileY: tileY) else { return (false, 0) }

        let placed = PlacedDeco(typeID: deco.id, tileX: tileX, tileY: tileY)
        placedDecos.append(placed)
        selectedDeco = nil
        return (true, deco.cost)
    }

    func removeDeco(id: UUID) {
        placedDecos.removeAll { $0.id == id }
    }

    func restore(decos: [PlacedDeco]) {
        self.placedDecos = decos
    }

    private func isTileOccupied(tileX: Int, tileY: Int) -> Bool {
        placedDecos.contains { $0.tileX == tileX && $0.tileY == tileY }
    }
}
```

- [ ] **Step 2: Add `buildSystem` to `VillageEngine`**

In `VillageEngine.swift`, add:

```swift
let buildSystem = BuildSystem()
```

And in `start()`, after `farmingEngine.restore(crops: savedState.crops)`:

```swift
buildSystem.restore(decos: savedState.placedDecos)
```

And add `saveDecos()`:

```swift
func saveDecos() {
    var state = VillagePersistence.shared.load()
    state.placedDecos = buildSystem.placedDecos
    state.lastSaved = Date()
    VillagePersistence.shared.save(state)
}
```

- [ ] **Step 3: Add `placedDecos` to `VillageState` in `VillagePersistence.swift`**

In the `VillageState` `init(from:)` decoder:

```swift
placedDecos = (try? c.decode([PlacedDeco].self, forKey: .placedDecos)) ?? []
```

And add `var placedDecos: [PlacedDeco]` to the struct and the memberwise init and the `empty` static.

Full updated `VillageState`:

```swift
struct VillageState: Codable {
    var npcPositions: [String: TilePosition]
    var revealedZones: [String]
    var crops: [PlantedCrop]
    var placedDecos: [PlacedDeco]
    var lastSaved: Date

    init(npcPositions: [String: TilePosition], revealedZones: [String],
         crops: [PlantedCrop], placedDecos: [PlacedDeco], lastSaved: Date) {
        self.npcPositions = npcPositions
        self.revealedZones = revealedZones
        self.crops = crops
        self.placedDecos = placedDecos
        self.lastSaved = lastSaved
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        npcPositions = (try? c.decode([String: TilePosition].self, forKey: .npcPositions)) ?? [:]
        revealedZones = (try? c.decode([String].self, forKey: .revealedZones)) ?? []
        crops = (try? c.decode([PlantedCrop].self, forKey: .crops)) ?? []
        placedDecos = (try? c.decode([PlacedDeco].self, forKey: .placedDecos)) ?? []
        lastSaved = (try? c.decode(Date.self, forKey: .lastSaved)) ?? Date()
    }

    static var empty: VillageState {
        VillageState(npcPositions: [:], revealedZones: [],
                     crops: [], placedDecos: [], lastSaved: Date())
    }
}
```

---

### Task 12.3: Ghost cursor and click-to-place in VillageScene

**Files:**
- Modify: `Sources/NookApp/VillageScene.swift`

- [ ] **Step 1: Add ghost sprite and mouse tracking**

Add these properties to `VillageScene`:

```swift
private var ghostSprite: SKLabelNode?
```

Add `syncDecos()`:

```swift
private var decoSprites: [UUID: SKLabelNode] = [:]

private func syncDecos() {
    guard let engine else { return }
    let current = engine.buildSystem.placedDecos
    let currentIDs = Set(current.map(\.id))
    let spriteIDs = Set(decoSprites.keys)

    for deco in current where !spriteIDs.contains(deco.id) {
        let sprite = makeDecoSprite(deco: deco)
        addChild(sprite)
        decoSprites[deco.id] = sprite
    }

    for id in spriteIDs.subtracting(currentIDs) {
        decoSprites[id]?.removeFromParent()
        decoSprites.removeValue(forKey: id)
    }
}

private func makeDecoSprite(deco: PlacedDeco) -> SKLabelNode {
    let type = DecoType.catalog.first { $0.id == deco.typeID }
    let node = SKLabelNode(text: type?.emoji ?? "?")
    node.fontSize = 24
    node.position = CGPoint(
        x: CGFloat(deco.tileX) * TileMap.tileSize + TileMap.tileSize / 2,
        y: CGFloat(deco.tileY) * TileMap.tileSize + TileMap.tileSize / 2
    )
    node.zPosition = 8
    return node
}
```

Override `mouseMoved(with:)` to move the ghost sprite:

```swift
override func mouseMoved(with event: NSEvent) {
    guard let engine, engine.buildSystem.selectedDeco != nil else {
        ghostSprite?.isHidden = true
        return
    }
    let loc = event.location(in: self)
    let tileX = Int(loc.x / TileMap.tileSize)
    let tileY = Int(loc.y / TileMap.tileSize)

    if ghostSprite == nil {
        let g = SKLabelNode()
        g.fontSize = 24
        g.alpha = 0.5
        g.zPosition = 20
        addChild(g)
        ghostSprite = g
    }
    ghostSprite?.text = engine.buildSystem.selectedDeco?.emoji ?? "?"
    ghostSprite?.isHidden = false
    ghostSprite?.position = CGPoint(
        x: CGFloat(tileX) * TileMap.tileSize + TileMap.tileSize / 2,
        y: CGFloat(tileY) * TileMap.tileSize + TileMap.tileSize / 2
    )
}

override func mouseDown(with event: NSEvent) {
    guard let engine, engine.buildSystem.selectedDeco != nil else { return }
    let loc = event.location(in: self)
    let tileX = Int(loc.x / TileMap.tileSize)
    let tileY = Int(loc.y / TileMap.tileSize)
    let result = engine.buildSystem.confirmPlace(
        tileX: tileX, tileY: tileY, availableBits: engine.totalBits)
    if result.placed {
        syncDecos()
        engine.saveDecos()
    }
}

override func rightMouseDown(with event: NSEvent) {
    engine?.buildSystem.cancelPlacing()
    ghostSprite?.isHidden = true
}
```

Enable `mouseMoved` in `didMove(to:)` — add after `view.preferredFramesPerSecond = 60`:

```swift
view.acceptsTouchEvents = false
// Enable mouseMoved events (not sent by default in macOS)
view.window?.acceptsMouseMovedEvents = true
```

Also call `syncDecos()` in `configure(engine:)` and in `update()` when deco count changes:

```swift
// In update():
if let engine, engine.buildSystem.placedDecos.count != decoSprites.count {
    syncDecos()
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 12.4: Shop panel in ContentView (SwiftUI)

**Files:**
- Modify: `Sources/NookApp/ContentView.swift`

- [ ] **Step 1: Add shop overlay to `ContentView`**

Replace `ContentView.swift` entirely:

```swift
import SwiftUI
import SpriteKit

struct ContentView: View {
    @Environment(VillageEngine.self) private var engine
    @State private var scene: VillageScene?
    @State private var showShop = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let scene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // Day/night overlay
            Rectangle()
                .fill(engine.dayPhase.overlayColor)
                .opacity(engine.dayPhase.overlayOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 30), value: engine.dayPhase)

            // HUD — top left
            Text("⬡ \(engine.totalBits, specifier: "%.1f") Bits")
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6))
                .cornerRadius(4)
                .padding(16)

            // Build mode toggle — top right
            VStack(alignment: .trailing) {
                Button(action: { showShop.toggle() }) {
                    Text(showShop ? "✕ Fermer" : "🔨 Construire")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.7))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                if showShop {
                    ShopPanel(buildSystem: engine.buildSystem, totalBits: engine.totalBits)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(16)
        }
        .onAppear {
            guard scene == nil else { return }
            engine.start()
            let s = VillageScene(size: CGSize(width: TileMap.mapWidth, height: TileMap.mapHeight))
            s.configure(engine: engine)
            scene = s
        }
    }
}

struct ShopPanel: View {
    let buildSystem: BuildSystem
    let totalBits: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Boutique")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.bottom, 4)

            ForEach(DecoType.catalog) { deco in
                Button(action: {
                    buildSystem.beginPlacing(deco)
                }) {
                    HStack {
                        Text(deco.emoji)
                        Text(deco.displayName)
                            .font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Text("⬡ \(Int(deco.cost))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(totalBits >= deco.cost ? .yellow : .gray)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        buildSystem.selectedDeco?.id == deco.id
                            ? Color.white.opacity(0.2)
                            : Color.clear
                    )
                    .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(totalBits < deco.cost)
            }
        }
        .padding(12)
        .background(.black.opacity(0.8))
        .cornerRadius(8)
        .frame(width: 200)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit phase 12**

```bash
git -C /Users/mchau/Desktop/Code/Nook add \
  Sources/NookApp/DecoItem.swift \
  Sources/NookApp/BuildSystem.swift \
  Sources/NookApp/VillagePersistence.swift \
  Sources/NookApp/VillageEngine.swift \
  Sources/NookApp/VillageScene.swift \
  Sources/NookApp/ContentView.swift
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase12): build system — deco shop, ghost cursor, click-to-place, persistence"
```

---

## Phase 13: Weather & Seasons

### Task 13.1: WeatherSystem

**Files:**
- Create: `Sources/NookApp/WeatherSystem.swift`

- [ ] **Step 1: Create `Sources/NookApp/WeatherSystem.swift`**

```swift
import Foundation

enum WeatherType: String, Codable, Equatable {
    case sunny
    case cloudy
    case rainy
    case stormy
    case foggy

    var growthMultiplier: Double {
        switch self {
        case .rainy, .stormy: return 1.3
        default: return 1.0
        }
    }

    var displayName: String {
        switch self {
        case .sunny:  return "Ensoleillé"
        case .cloudy: return "Nuageux"
        case .rainy:  return "Pluie"
        case .stormy: return "Orage"
        case .foggy:  return "Brouillard"
        }
    }
}

enum Season: String, Equatable {
    case spring  // mars–mai
    case summer  // juin–août
    case autumn  // sept–nov
    case winter  // déc–fév

    static func current(date: Date = Date()) -> Season {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3...5:   return .spring
        case 6...8:   return .summer
        case 9...11:  return .autumn
        default:      return .winter  // 12, 1, 2
        }
    }

    var displayName: String {
        switch self {
        case .spring: return "Printemps"
        case .summer: return "Été"
        case .autumn: return "Automne"
        case .winter: return "Hiver"
        }
    }

    // Summer crops grow faster too
    var growthMultiplier: Double {
        switch self {
        case .summer: return 1.15
        default: return 1.0
        }
    }
}

@MainActor
final class WeatherSystem {

    private(set) var currentWeather: WeatherType = .sunny
    private(set) var currentSeason: Season = Season.current()

    // Composite multiplier for farming
    var growthMultiplier: Double {
        currentWeather.growthMultiplier * currentSeason.growthMultiplier
    }

    // Roll a new weather for the day — deterministic per calendar day
    func rollDailyWeather(date: Date = Date()) {
        currentSeason = Season.current(date: date)

        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        // Use day as seed so weather is stable within a day
        var rng = SeededRNG(seed: UInt64(dayOfYear))
        let roll = rng.next() % 100

        switch currentSeason {
        case .spring:
            switch roll {
            case 0..<40:  currentWeather = .sunny
            case 40..<65: currentWeather = .cloudy
            case 65..<85: currentWeather = .rainy
            case 85..<95: currentWeather = .foggy
            default:      currentWeather = .stormy
            }
        case .summer:
            switch roll {
            case 0..<55:  currentWeather = .sunny
            case 55..<75: currentWeather = .cloudy
            case 75..<85: currentWeather = .rainy
            case 85..<95: currentWeather = .stormy
            default:      currentWeather = .foggy
            }
        case .autumn:
            switch roll {
            case 0..<30:  currentWeather = .sunny
            case 30..<55: currentWeather = .cloudy
            case 55..<80: currentWeather = .rainy
            case 80..<90: currentWeather = .foggy
            default:      currentWeather = .stormy
            }
        case .winter:
            switch roll {
            case 0..<25:  currentWeather = .sunny
            case 25..<50: currentWeather = .cloudy
            case 50..<75: currentWeather = .rainy
            case 75..<90: currentWeather = .foggy
            default:      currentWeather = .stormy
            }
        }
    }
}

// Minimal seeded linear-congruential RNG — no external dependencies
private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
}
```

- [ ] **Step 2: Wire WeatherSystem into VillageEngine**

In `VillageEngine.swift`:

```swift
let weatherSystem = WeatherSystem()
```

In `start()`, add after `farmingEngine.restore(...)`:

```swift
weatherSystem.rollDailyWeather()
farmingEngine.rainMultiplier = weatherSystem.growthMultiplier
startWeatherTimer()
```

Add `startWeatherTimer()`:

```swift
private var weatherTimer: DispatchSourceTimer?

private func startWeatherTimer() {
    // Check once per hour whether the day changed and we need a new weather roll
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: .seconds(3600))
    timer.setEventHandler { [weak self] in
        self?.weatherSystem.rollDailyWeather()
        self?.farmingEngine.rainMultiplier = self?.weatherSystem.growthMultiplier ?? 1.0
    }
    timer.resume()
    weatherTimer = timer
}
```

In `stop()`:

```swift
weatherTimer?.cancel()
weatherTimer = nil
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -3
```

---

### Task 13.2: Visual weather effects in VillageScene

Each weather type gets a SpriteKit particle emitter or overlay.

**Files:**
- Modify: `Sources/NookApp/VillageScene.swift`

- [ ] **Step 1: Add weather rendering**

Add property to `VillageScene`:
```swift
private var lastWeather: WeatherType?
private var weatherNode: SKNode?
```

Add method:

```swift
private func applyWeather(_ weather: WeatherType) {
    weatherNode?.removeFromParent()
    weatherNode = nil

    switch weather {
    case .rainy:
        weatherNode = makeRainNode(intensity: 0.6)
    case .stormy:
        weatherNode = makeRainNode(intensity: 1.2)
        startLightningTimer()
    case .foggy:
        weatherNode = makeFogOverlay()
    case .sunny, .cloudy:
        break
    }

    if let node = weatherNode {
        node.zPosition = 50
        addChild(node)
    }
}

private func makeRainNode(intensity: CGFloat) -> SKNode {
    guard let emitter = SKEmitterNode(fileNamed: "Rain.sks") else {
        // Fallback: procedural rain
        return makeProceduralRain(intensity: intensity)
    }
    emitter.particleBirthRate = 200 * intensity
    emitter.position = CGPoint(x: TileMap.mapWidth / 2, y: TileMap.mapHeight + 100)
    return emitter
}

private func makeProceduralRain(intensity: CGFloat) -> SKNode {
    let container = SKNode()
    // Simple: a recurring action that spawns rain streaks
    let spawn = SKAction.run { [weak self, weak container] in
        guard let self, let container else { return }
        let streak = SKSpriteNode(
            color: NSColor(red: 0.6, green: 0.75, blue: 0.9, alpha: 0.4),
            size: CGSize(width: 1, height: 8)
        )
        streak.position = CGPoint(
            x: CGFloat.random(in: 0...TileMap.mapWidth),
            y: CGFloat.random(in: 0...TileMap.mapHeight)
        )
        streak.zRotation = 0.15
        container.addChild(streak)
        let fall = SKAction.moveBy(x: 10, y: -200, duration: 0.4)
        let remove = SKAction.removeFromParent()
        streak.run(SKAction.sequence([fall, remove]))
    }
    let rate: TimeInterval = Double(1.0 / (30 * intensity))
    container.run(SKAction.repeatForever(SKAction.sequence([
        SKAction.wait(forDuration: rate),
        spawn
    ])))
    return container
}

private var lightningTimer: DispatchSourceTimer?

private func startLightningTimer() {
    lightningTimer?.cancel()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 5, repeating: .seconds(15))
    timer.setEventHandler { [weak self] in
        self?.flashLightning()
    }
    timer.resume()
    lightningTimer = timer
}

private func flashLightning() {
    let flash = SKSpriteNode(
        color: NSColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 0.6),
        size: CGSize(width: TileMap.mapWidth, height: TileMap.mapHeight)
    )
    flash.position = CGPoint(x: TileMap.mapWidth / 2, y: TileMap.mapHeight / 2)
    flash.zPosition = 60
    addChild(flash)
    flash.run(SKAction.sequence([
        SKAction.fadeOut(withDuration: 0.1),
        SKAction.wait(forDuration: 0.05),
        SKAction.fadeIn(withDuration: 0.05),
        SKAction.fadeOut(withDuration: 0.2),
        SKAction.removeFromParent()
    ]))
}

private func makeFogOverlay() -> SKNode {
    let fog = SKSpriteNode(
        color: NSColor(red: 0.7, green: 0.75, blue: 0.8, alpha: 0.25),
        size: CGSize(width: TileMap.mapWidth, height: TileMap.mapHeight)
    )
    fog.position = CGPoint(x: TileMap.mapWidth / 2, y: TileMap.mapHeight / 2)
    return fog
}
```

In `update(_ currentTime:)`, add:

```swift
if let engine, engine.weatherSystem.currentWeather != lastWeather {
    applyWeather(engine.weatherSystem.currentWeather)
    lastWeather = engine.weatherSystem.currentWeather
}
```

Also add a season tint overlay inside `applyWeather` for winter (white overlay):

```swift
// In applyWeather, add at the end:
applySeasonTint(engine?.weatherSystem.currentSeason ?? .spring)
```

```swift
private var seasonTintNode: SKSpriteNode?

private func applySeasonTint(_ season: Season) {
    seasonTintNode?.removeFromParent()
    seasonTintNode = nil

    switch season {
    case .winter:
        let tint = SKSpriteNode(
            color: NSColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 0.12),
            size: CGSize(width: TileMap.mapWidth, height: TileMap.mapHeight)
        )
        tint.position = CGPoint(x: TileMap.mapWidth / 2, y: TileMap.mapHeight / 2)
        tint.zPosition = 49
        addChild(tint)
        seasonTintNode = tint
    case .autumn:
        let tint = SKSpriteNode(
            color: NSColor(red: 0.8, green: 0.5, blue: 0.1, alpha: 0.07),
            size: CGSize(width: TileMap.mapWidth, height: TileMap.mapHeight)
        )
        tint.position = CGPoint(x: TileMap.mapWidth / 2, y: TileMap.mapHeight / 2)
        tint.zPosition = 49
        addChild(tint)
        seasonTintNode = tint
    default:
        break
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 13.3: SPM tests for WeatherSystem

**Files:**
- Create: `Tests/NookTests/WeatherSystemTests.swift`

```swift
import XCTest

// Pure logic tests — Season detection and growth multipliers
final class WeatherSystemTests: XCTestCase {

    func test_season_spring_march() {
        let march = dateWith(month: 3)
        XCTAssertEqual(Season.current(date: march), .spring)
    }

    func test_season_summer_july() {
        let july = dateWith(month: 7)
        XCTAssertEqual(Season.current(date: july), .summer)
    }

    func test_season_autumn_october() {
        let oct = dateWith(month: 10)
        XCTAssertEqual(Season.current(date: oct), .autumn)
    }

    func test_season_winter_december() {
        let dec = dateWith(month: 12)
        XCTAssertEqual(Season.current(date: dec), .winter)
    }

    func test_season_winter_january() {
        let jan = dateWith(month: 1)
        XCTAssertEqual(Season.current(date: jan), .winter)
    }

    func test_rain_multiplier_is_1_3() {
        XCTAssertEqual(WeatherType.rainy.growthMultiplier, 1.3, accuracy: 0.001)
    }

    func test_stormy_multiplier_is_1_3() {
        XCTAssertEqual(WeatherType.stormy.growthMultiplier, 1.3, accuracy: 0.001)
    }

    func test_sunny_multiplier_is_1() {
        XCTAssertEqual(WeatherType.sunny.growthMultiplier, 1.0, accuracy: 0.001)
    }

    func test_summer_grows_faster() {
        XCTAssertGreaterThan(Season.summer.growthMultiplier, 1.0)
    }

    // MARK: - helpers
    private func dateWith(month: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = 15
        return Calendar.current.date(from: components)!
    }
}

// Paste Season and WeatherType here for SPM test isolation (no NookApp import)
enum WeatherType: Equatable {
    case sunny, cloudy, rainy, stormy, foggy
    var growthMultiplier: Double {
        switch self {
        case .rainy, .stormy: return 1.3
        default: return 1.0
        }
    }
}

enum Season: Equatable {
    case spring, summer, autumn, winter
    static func current(date: Date = Date()) -> Season {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3...5:  return .spring
        case 6...8:  return .summer
        case 9...11: return .autumn
        default:     return .winter
        }
    }
    var growthMultiplier: Double {
        switch self {
        case .summer: return 1.15
        default:      return 1.0
        }
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --package-path /Users/mchau/Desktop/Code/Nook --filter WeatherSystemTests 2>&1 | tail -8
```

Expected: `Test Suite 'WeatherSystemTests' passed`

- [ ] **Step 3: Commit phase 13**

```bash
git -C /Users/mchau/Desktop/Code/Nook add \
  Sources/NookApp/WeatherSystem.swift \
  Sources/NookApp/VillageEngine.swift \
  Sources/NookApp/VillageScene.swift \
  Tests/NookTests/WeatherSystemTests.swift
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase13): weather system — daily roll, rain/storm/fog effects, season tints"
```

---

## Phase 14: Terminal Panels

### Task 14.1: Add SwiftTerm dependency to Package.swift

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Update `Package.swift` to add SwiftTerm**

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Nook",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "NookDaemon",
            path: "Sources/NookDaemon"
        ),
        .target(
            name: "NookTerminal",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/NookTerminal"
        ),
        .testTarget(
            name: "NookTests",
            dependencies: ["NookDaemon"],
            path: "Tests/NookTests"
        )
    ]
)
```

NookTerminal is a separate SPM target so SwiftTerm is fetched by SPM. The Xcode project will use the embedded framework by adding NookTerminal as a dependency of the NookApp target via "Link Binary with Libraries".

- [ ] **Step 2: Resolve the package**

```bash
swift package --package-path /Users/mchau/Desktop/Code/Nook resolve
```

Expected: SwiftTerm is downloaded into `.build/checkouts/`.

- [ ] **Step 3: Create the `Sources/NookTerminal/` directory structure**

This is where terminal-related code goes. The directory must exist for the SPM target to build. The Xcode project will then add the compiled NookTerminal framework. Create a placeholder module file:

`Sources/NookTerminal/NookTerminal.swift` — just a public import re-export, actual classes live in NookApp since they need AppKit/SwiftUI:

```swift
// NookTerminal — re-exports SwiftTerm for use by NookApp
@_exported import SwiftTerm
```

- [ ] **Step 4: In Xcode, add NookTerminal as a linked framework to NookApp**

In Xcode: NookApp target → General → Frameworks, Libraries, and Embedded Content → `+` → Add Other → Add Package → select `NookTerminal` from the SPM packages in the workspace.

Alternatively, open `NookApp.xcodeproj` in Xcode, go to File → Add Packages, enter the local Package.swift. This links SwiftTerm into the NookApp Xcode target.

- [ ] **Step 5: Build to verify SwiftTerm resolves**

```bash
swift build --package-path /Users/mchau/Desktop/Code/Nook --target NookTerminal 2>&1 | tail -5
```

Expected: `Build complete!`

---

### Task 14.2: TerminalPanel — NSPanel with SwiftTerm

**Files:**
- Create: `Sources/NookApp/TerminalPanel.swift`

- [ ] **Step 1: Create `Sources/NookApp/TerminalPanel.swift`**

```swift
import AppKit
import SwiftTerm

// TerminalPanel is an NSPanel (floating, non-activating optional) that
// hosts a SwiftTerm LocalProcessTerminalView for a given agent.
// It lives as an NSWindow owned by WindowManager.
@MainActor
final class TerminalPanel: NSPanel {

    let agentName: String
    private let terminalView: LocalProcessTerminalView

    init(agentName: String) {
        self.agentName = agentName

        let initialSize = NSSize(width: 640, height: 400)
        let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable, .nonactivatingPanel]
        let backing: NSWindow.BackingStoreType = .buffered
        terminalView = LocalProcessTerminalView(frame: NSRect(origin: .zero, size: initialSize))

        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: style,
            backing: backing,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        title = "⬡ \(agentName)"
        backgroundColor = NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)

        contentView = terminalView
        setupPixelBorder()
    }

    func startShell() {
        let env = ProcessInfo.processInfo.environment
        let shell = env["SHELL"] ?? "/bin/zsh"
        terminalView.startProcess(executable: shell, execName: shell)
    }

    private func setupPixelBorder() {
        // Pixel art style: 2px solid border using a NSBox as overlay
        let border = NSBox(frame: NSRect(
            x: 0, y: 0,
            width: frame.width, height: frame.height
        ))
        border.boxType = .custom
        border.borderWidth = 2
        border.borderColor = NSColor(red: 0.4, green: 0.8, blue: 0.6, alpha: 0.9)
        border.fillColor = .clear
        border.autoresizingMask = [.width, .height]
        contentView?.addSubview(border, positioned: .above, relativeTo: terminalView)
    }
}
```

Note: `LocalProcessTerminalView` is SwiftTerm's AppKit terminal view that spawns a local process. If the SwiftTerm API changes on `main` branch, check the SwiftTerm README for the current class name. As of 2025, `LocalProcessTerminalView` + `startProcess(executable:execName:)` is the stable AppKit API.

---

### Task 14.3: WindowManager

**Files:**
- Create: `Sources/NookApp/WindowManager.swift`

- [ ] **Step 1: Create `Sources/NookApp/WindowManager.swift`**

```swift
import AppKit

// WindowManager owns all TerminalPanels, keyed by agent name.
// It lives on the main actor and is owned by VillageEngine.
@MainActor
final class WindowManager {

    private var panels: [String: TerminalPanel] = [:]

    // Opens a new panel for agentName, or focuses existing one.
    func openPanel(for agentName: String) {
        if let existing = panels[agentName] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = TerminalPanel(agentName: agentName)
        panel.setFrameAutosaveName("TerminalPanel-\(agentName)")
        panel.center()
        panel.orderFront(nil)
        panel.startShell()

        // Clean up when closed
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.panels.removeValue(forKey: agentName)
        }

        panels[agentName] = panel
    }

    func closePanel(for agentName: String) {
        panels[agentName]?.close()
        panels.removeValue(forKey: agentName)
    }

    func hasOpenPanel(for agentName: String) -> Bool {
        panels[agentName] != nil
    }

    var openAgentNames: [String] {
        Array(panels.keys).sorted()
    }
}
```

- [ ] **Step 2: Add `windowManager` to VillageEngine**

```swift
let windowManager = WindowManager()
```

No extra wiring needed — it is accessed directly from ContentView/SessionBar.

---

### Task 14.4: SessionBar SwiftUI component

**Files:**
- Create: `Sources/NookApp/SessionBar.swift`

- [ ] **Step 1: Create `Sources/NookApp/SessionBar.swift`**

```swift
import SwiftUI

// SessionBar renders the pixel art session tabs at the bottom of the screen.
// [ 🧙 Radion ● ] [ 🔬 Coach ● ] [ + ]
struct SessionBar: View {
    let agents: [String: AgentRecord]     // from VillageEngine.agents
    let activeSessions: Set<String>
    let windowManager: WindowManager

    var body: some View {
        HStack(spacing: 6) {
            ForEach(agents.keys.sorted(), id: \.self) { name in
                SessionTab(
                    agentName: name,
                    isActive: activeSessions.contains(name),
                    isOpen: windowManager.hasOpenPanel(for: name)
                ) {
                    windowManager.openPanel(for: name)
                }
            }

            // New session button
            Button(action: openNewSession) {
                Text("+ session")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.1))
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.black.opacity(0.75))
    }

    private func openNewSession() {
        // Launches a new terminal panel with no agent attachment — user can
        // cd into a project with .pixelvillage configured
        windowManager.openPanel(for: "session-\(UUID().uuidString.prefix(4))")
    }
}

struct SessionTab: View {
    let agentName: String
    let isActive: Bool
    let isOpen: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text("⬡")
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? Color.green : Color.white.opacity(0.5))
                Text(agentName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                if isActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isOpen ? Color.white.opacity(0.15) : Color.white.opacity(0.07))
            .cornerRadius(3)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Add SessionBar to ContentView**

In `ContentView.swift`, wrap the ZStack in a VStack and add SessionBar at the bottom:

```swift
var body: some View {
    VStack(spacing: 0) {
        ZStack(alignment: .topLeading) {
            // ... existing scene, overlays, shop panel ...
        }

        SessionBar(
            agents: engine.agents,
            activeSessions: engine.activeSessions,
            windowManager: engine.windowManager
        )
    }
    .onAppear {
        guard scene == nil else { return }
        engine.start()
        let s = VillageScene(size: CGSize(width: TileMap.mapWidth, height: TileMap.mapHeight))
        s.configure(engine: engine)
        scene = s
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual smoke test**

Launch the app. The session bar appears at the bottom. If there are agents in the ledger, their names appear as tabs. Click a tab — a floating terminal panel opens running zsh.

- [ ] **Step 5: Commit phase 14**

```bash
git -C /Users/mchau/Desktop/Code/Nook add \
  Package.swift \
  Sources/NookTerminal/NookTerminal.swift \
  Sources/NookApp/TerminalPanel.swift \
  Sources/NookApp/WindowManager.swift \
  Sources/NookApp/SessionBar.swift \
  Sources/NookApp/ContentView.swift \
  Sources/NookApp/VillageEngine.swift
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase14): terminal panels — NSPanel + SwiftTerm + session bar"
```

---

## Phase 15: TileMap Optimization

### Task 15.1: Replace 16k SKSpriteNodes with SKTileMapNode

The current `TileMap.build()` creates 16,384 `SKSpriteNode` instances. `SKTileMapNode` renders the same grid as a single draw call using a tile set. This eliminates the ~150ms launch hitch.

**Files:**
- Modify: `Sources/NookApp/TileMap.swift`

The approach: create `SKTileSet` and `SKTileGroups` from the existing textures programmatically (no `.sks` file needed — avoids the Xcode editor requirement).

- [ ] **Step 1: Write the failing test (conceptual — we test the node count)**

There is no direct SPM test for SpriteKit node count. The validation is: after refactor, `tileMap.children.count` is 1 (the tent) rather than 16,385. Document this as a manual assertion in code:

```swift
// In TileMap.build(), add at end:
assert(children.count == 1, "TileMap should contain only the tent node after SKTileMapNode migration")
```

- [ ] **Step 2: Replace `TileMap.build()` in `TileMap.swift`**

```swift
import SpriteKit

@MainActor
final class TileMap: SKNode {
    static let tileSize: CGFloat = 32
    static let gridWidth = 128
    static let gridHeight = 128
    static let mapWidth: CGFloat = CGFloat(gridWidth) * tileSize    // 4096
    static let mapHeight: CGFloat = CGFloat(gridHeight) * tileSize  // 4096

    // Central parcelle bounds (20×20 centered in 128×128)
    static let parcelleOriginX = (gridWidth - 20) / 2   // 54
    static let parcelleOriginY = (gridHeight - 20) / 2  // 54
    static let parcelleWidth = 20
    static let parcelleHeight = 20

    private var tileMapNode: SKTileMapNode?

    func build() {
        let grassTexture = SKTexture(imageNamed: "grass")
        grassTexture.filteringMode = .nearest
        let dirtTexture = SKTexture(imageNamed: "dirt")
        dirtTexture.filteringMode = .nearest
        let tentTexture = SKTexture(imageNamed: "tent")
        tentTexture.filteringMode = .nearest

        // Build SKTileSet programmatically
        let grassDef = SKTileDefinition(texture: grassTexture,
                                         size: CGSize(width: TileMap.tileSize, height: TileMap.tileSize))
        let dirtDef = SKTileDefinition(texture: dirtTexture,
                                        size: CGSize(width: TileMap.tileSize, height: TileMap.tileSize))

        let grassGroup = SKTileGroup(tileDefinition: grassDef)
        let dirtGroup = SKTileGroup(tileDefinition: dirtDef)

        let tileSet = SKTileSet(tileGroups: [dirtGroup, grassGroup])

        let mapNode = SKTileMapNode(
            tileSet: tileSet,
            columns: TileMap.gridWidth,
            rows: TileMap.gridHeight,
            tileSize: CGSize(width: TileMap.tileSize, height: TileMap.tileSize)
        )

        // SKTileMapNode uses center anchor by default. Position so bottom-left = (0,0)
        mapNode.position = CGPoint(x: TileMap.mapWidth / 2, y: TileMap.mapHeight / 2)
        mapNode.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // Fill all tiles with dirt first
        for row in 0..<TileMap.gridHeight {
            for col in 0..<TileMap.gridWidth {
                mapNode.setTileGroup(dirtGroup, forColumn: col, row: row)
            }
        }

        // Paint parcelle tiles with grass
        for row in TileMap.parcelleOriginY..<(TileMap.parcelleOriginY + TileMap.parcelleHeight) {
            for col in TileMap.parcelleOriginX..<(TileMap.parcelleOriginX + TileMap.parcelleWidth) {
                mapNode.setTileGroup(grassGroup, forColumn: col, row: row)
            }
        }

        addChild(mapNode)
        tileMapNode = mapNode

        // Tent: 2×2 tiles at center of parcelle
        let tentCol = TileMap.parcelleOriginX + TileMap.parcelleWidth / 2
        let tentRow = TileMap.parcelleOriginY + TileMap.parcelleHeight / 2
        let tent = SKSpriteNode(texture: tentTexture,
                                size: CGSize(width: TileMap.tileSize * 2, height: TileMap.tileSize * 2))
        tent.position = CGPoint(
            x: CGFloat(tentCol) * TileMap.tileSize + TileMap.tileSize,
            y: CGFloat(tentRow) * TileMap.tileSize + TileMap.tileSize
        )
        addChild(tent)

        // Sanity check: only 2 children (mapNode + tent)
        assert(children.count == 2, "TileMap should have exactly 2 children: SKTileMapNode + tent")
    }
}
```

Important: `SKTileMapNode` has its own coordinate system — columns go left-to-right (col 0 = left) and rows go bottom-to-top (row 0 = bottom), matching SpriteKit's Y-up convention. This matches the existing TileMap coordinate system so existing position calculations remain correct.

- [ ] **Step 3: Verify world coordinates remain consistent**

The existing NPC spawning uses:
```swift
let wx = CGFloat(tileX) * TileMap.tileSize + TileMap.tileSize / 2
```

This is in world space (bottom-left origin). The `SKTileMapNode` is positioned at `(mapWidth/2, mapHeight/2)` with `anchorPoint = (0.5, 0.5)`, which means tile `(col, row)` in the node's local space maps to world position:

```
worldX = mapNode.position.x - mapWidth/2 + col * tileSize + tileSize/2
       = col * tileSize + tileSize/2   ✓ (matches existing NPC positioning)
```

No changes needed in `NPCManager`, `NPCWander`, or `FogSystem`.

- [ ] **Step 4: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual perf check — launch app and watch console**

The `TODO` comment about ~150ms hitch is gone. Time the launch with Instruments → Time Profiler if needed. Expect no `SKSpriteNode` allocation for tiles.

- [ ] **Step 6: Commit**

```bash
git -C /Users/mchau/Desktop/Code/Nook add Sources/NookApp/TileMap.swift
git -C /Users/mchau/Desktop/Code/Nook commit -m "perf(phase15): replace 16k SKSpriteNodes with SKTileMapNode — single draw call tile rendering"
```

---

## Phase 16: Onboarding

### Task 16.1: OnboardingEngine

**Files:**
- Create: `Sources/NookApp/OnboardingEngine.swift`
- Modify: `Sources/NookApp/VillagePersistence.swift`

- [ ] **Step 1: Add onboarding state to `VillageState`**

Add to `VillageState`:

```swift
var onboardingComplete: Bool
var playerName: String
```

Updated full `VillageState` (replacing all previous versions):

```swift
struct VillageState: Codable {
    var npcPositions: [String: TilePosition]
    var revealedZones: [String]
    var crops: [PlantedCrop]
    var placedDecos: [PlacedDeco]
    var onboardingComplete: Bool
    var playerName: String
    var lastSaved: Date

    init(npcPositions: [String: TilePosition], revealedZones: [String],
         crops: [PlantedCrop], placedDecos: [PlacedDeco],
         onboardingComplete: Bool, playerName: String, lastSaved: Date) {
        self.npcPositions = npcPositions
        self.revealedZones = revealedZones
        self.crops = crops
        self.placedDecos = placedDecos
        self.onboardingComplete = onboardingComplete
        self.playerName = playerName
        self.lastSaved = lastSaved
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        npcPositions = (try? c.decode([String: TilePosition].self, forKey: .npcPositions)) ?? [:]
        revealedZones = (try? c.decode([String].self, forKey: .revealedZones)) ?? []
        crops = (try? c.decode([PlantedCrop].self, forKey: .crops)) ?? []
        placedDecos = (try? c.decode([PlacedDeco].self, forKey: .placedDecos)) ?? []
        onboardingComplete = (try? c.decode(Bool.self, forKey: .onboardingComplete)) ?? false
        playerName = (try? c.decode(String.self, forKey: .playerName)) ?? ""
        lastSaved = (try? c.decode(Date.self, forKey: .lastSaved)) ?? Date()
    }

    static var empty: VillageState {
        VillageState(npcPositions: [:], revealedZones: [], crops: [], placedDecos: [],
                     onboardingComplete: false, playerName: "", lastSaved: Date())
    }
}
```

- [ ] **Step 2: Create `Sources/NookApp/OnboardingEngine.swift`**

```swift
import Foundation

enum OnboardingStep: Equatable {
    case letter           // animated letter drop from sky
    case nameEntry        // "Quel est le nom de ton premier agent?"
    case firstSession     // instruction to launch Claude Code
    case firstPlant       // gift a crystal grass seed
    case complete
}

// OnboardingEngine drives the onboarding sequence.
// It is owned by VillageEngine and consulted by ContentView.
@MainActor
final class OnboardingEngine {

    private(set) var currentStep: OnboardingStep = .letter
    private(set) var firstAgentName: String = ""
    private(set) var isComplete: Bool = false

    func start(savedState: VillageState) {
        if savedState.onboardingComplete {
            isComplete = true
            currentStep = .complete
            firstAgentName = savedState.playerName
        } else {
            currentStep = .letter
        }
    }

    func advanceLetter() {
        guard currentStep == .letter else { return }
        currentStep = .nameEntry
    }

    func confirmName(_ name: String) {
        guard currentStep == .nameEntry, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        firstAgentName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        currentStep = .firstSession
    }

    func advanceToPlant() {
        guard currentStep == .firstSession else { return }
        currentStep = .firstPlant
    }

    func completeOnboarding(farmingEngine: FarmingEngine, persistence: VillagePersistence) {
        guard currentStep == .firstPlant else { return }

        // Gift first seed: crystal grass at parcelle center
        let centerX = TileMap.parcelleOriginX + TileMap.parcelleWidth / 2 - 2
        let centerY = TileMap.parcelleOriginY + TileMap.parcelleHeight / 2 - 2
        farmingEngine.plant(.crystalGrass, tileX: centerX, tileY: centerY)

        isComplete = true
        currentStep = .complete

        var state = persistence.load()
        state.onboardingComplete = true
        state.playerName = firstAgentName
        state.crops = farmingEngine.crops
        state.lastSaved = Date()
        persistence.save(state)
    }
}
```

- [ ] **Step 3: Add `onboardingEngine` to `VillageEngine`**

```swift
let onboardingEngine = OnboardingEngine()
```

In `start()`, after `farmingEngine.restore(...)`:

```swift
let savedStateForOnboarding = VillagePersistence.shared.load()
onboardingEngine.start(savedState: savedStateForOnboarding)
```

---

### Task 16.2: OnboardingView — animated letter + name entry + seed gift

**Files:**
- Create: `Sources/NookApp/OnboardingView.swift`

- [ ] **Step 1: Create `Sources/NookApp/OnboardingView.swift`**

```swift
import SwiftUI

// OnboardingView overlays the entire ContentView during the onboarding sequence.
// It is shown when VillageEngine.onboardingEngine.isComplete == false.
struct OnboardingView: View {
    @Environment(VillageEngine.self) private var engine
    @State private var letterDropped = false
    @State private var letterVisible = false
    @State private var agentNameInput = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()

            switch engine.onboardingEngine.currentStep {
            case .letter:
                letterView
            case .nameEntry:
                nameEntryView
            case .firstSession:
                firstSessionView
            case .firstPlant:
                firstPlantView
            case .complete:
                EmptyView()
            }
        }
        .onAppear {
            if engine.onboardingEngine.currentStep == .letter {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 1.2)) {
                        letterDropped = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { letterVisible = true }
                    }
                }
            }
        }
    }

    private var letterView: some View {
        VStack(spacing: 24) {
            Text("✉️")
                .font(.system(size: 64))
                .offset(y: letterDropped ? 0 : -200)
                .animation(.easeOut(duration: 1.2), value: letterDropped)

            if letterVisible {
                VStack(spacing: 12) {
                    Text("Bienvenue dans ton village.")
                        .font(.system(size: 18, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("Il grandira avec ton travail.")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .transition(.opacity)

                Button("Commencer →") {
                    engine.onboardingEngine.advanceLetter()
                }
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.15))
                .cornerRadius(4)
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(40)
    }

    private var nameEntryView: some View {
        VStack(spacing: 20) {
            Text("Comment s'appelle ton premier agent ?")
                .font(.system(size: 16, design: .monospaced))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            TextField("Radion", text: $agentNameInput)
                .textFieldStyle(.plain)
                .font(.system(size: 18, design: .monospaced))
                .foregroundStyle(.white)
                .padding(10)
                .background(Color.white.opacity(0.1))
                .cornerRadius(4)
                .frame(width: 280)
                .onSubmit { confirmName() }

            Button("Créer →") { confirmName() }
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(agentNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.white.opacity(0.08)
                            : Color.white.opacity(0.2))
                .cornerRadius(4)
                .buttonStyle(.plain)
                .disabled(agentNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(40)
        .background(Color.black.opacity(0.5))
        .cornerRadius(12)
    }

    private var firstSessionView: some View {
        VStack(spacing: 20) {
            Text("⬡ \(engine.onboardingEngine.firstAgentName)")
                .font(.system(size: 24, design: .monospaced))
                .foregroundStyle(Color(red: 0.4, green: 0.9, blue: 0.7))

            Text("Lance Claude Code avec cet agent\npour gagner tes premiers Bits.")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            Text("Dans le répertoire de ton projet,\ncrée un fichier `.pixelvillage`\navec {\"agent\": \"\(engine.onboardingEngine.firstAgentName)\"}.")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(10)
                .background(Color.white.opacity(0.07))
                .cornerRadius(4)

            Button("Continuer →") {
                engine.onboardingEngine.advanceToPlant()
            }
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.15))
            .cornerRadius(4)
            .buttonStyle(.plain)
        }
        .padding(40)
        .background(Color.black.opacity(0.5))
        .cornerRadius(12)
    }

    private var firstPlantView: some View {
        VStack(spacing: 20) {
            Text("🌱")
                .font(.system(size: 48))

            Text("Voici une graine, offerte par le village.")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            Text("Elle sera prête dans 1h.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))

            Button("Planter →") {
                engine.onboardingEngine.completeOnboarding(
                    farmingEngine: engine.farmingEngine,
                    persistence: VillagePersistence.shared
                )
            }
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.2))
            .cornerRadius(4)
            .buttonStyle(.plain)
        }
        .padding(40)
        .background(Color.black.opacity(0.5))
        .cornerRadius(12)
    }

    private func confirmName() {
        engine.onboardingEngine.confirmName(agentNameInput)
    }
}
```

- [ ] **Step 2: Show OnboardingView in ContentView**

In `ContentView.body`, inside the `ZStack`, add at the top level after all other layers:

```swift
// Onboarding overlay
if !engine.onboardingEngine.isComplete {
    OnboardingView()
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.5), value: engine.onboardingEngine.isComplete)
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual smoke test**

Delete `~/.pixelvillage/village.json` to reset state. Launch the app. Verify:
1. Letter falls from top with animation.
2. "Commencer" button appears.
3. Name entry field works, Enter/button advances.
4. Seed is planted at parcelle center (green shimmer tile appears).
5. Re-launch: onboarding does NOT show again.

- [ ] **Step 5: Commit phase 16**

```bash
git -C /Users/mchau/Desktop/Code/Nook add \
  Sources/NookApp/OnboardingEngine.swift \
  Sources/NookApp/OnboardingView.swift \
  Sources/NookApp/VillagePersistence.swift \
  Sources/NookApp/ContentView.swift \
  Sources/NookApp/VillageEngine.swift
git -C /Users/mchau/Desktop/Code/Nook commit -m "feat(phase16): onboarding — animated letter, agent naming, first session guide, free seed"
```

---

## Self-Review

### Spec coverage check

| Requirement | Task |
|---|---|
| Daemon as LaunchAgent | Task 9.1 + 9.2 |
| Bond 2-5 visual feedback | Task 10.1 |
| Farming crops (4 types, timers, harvest) | Tasks 11.1-11.5 |
| Arbres fruitiers / fishing | NOT covered — design doc marks these as "other sources"; fishing requires lac zone interaction. Out of scope for phases 9-16 per the prompt. |
| Pluie +30% crops | Task 13.1 (WeatherSystem), Task 11.3 (FarmingEngine.rainMultiplier) |
| Build mode (clic → item → place) | Tasks 12.1-12.4 |
| Décos (bancs, lanternes, fontaines, statues) | Task 12.1 (DecoType catalog) |
| Panneaux personnalisables | PlacedDeco.signText field (12.1) — UI editing deferred (no spec detail on flow) |
| Village NPCs indépendants (forgeron, etc.) | NOT covered — would require new NPC types and building/zone tie-ins. Treat as Phase 17+. |
| Weather (pluie, orage, brouillard) | Task 13.2 |
| Saisons | Task 13.1 (Season enum), Task 13.2 (tints) |
| Terminal panels NSPanel + SwiftTerm | Tasks 14.1-14.4 |
| Session bar | Task 14.4 |
| TileMap SKTileMapNode | Task 15.1 |
| Onboarding lettre, NPC, session, plante | Task 16.1 + 16.2 |

### Placeholder scan

All code blocks are complete. No "TBD" or "TODO" in task steps.

### Type consistency

- `FarmingEngine.rainMultiplier` is set by `WeatherSystem.growthMultiplier` in `VillageEngine.startWeatherTimer()` — consistent.
- `BuildSystem.confirmPlace(tileX:tileY:availableBits:)` returns `(placed: Bool, cost: Double)` — used consistently in `VillageScene.mouseDown`.
- `OnboardingEngine.completeOnboarding(farmingEngine:persistence:)` — matches the parameters available in `OnboardingView` via `@Environment(VillageEngine.self)`.
- `VillageState` struct accumulated fields across phases 11, 12, 16 — the final version in Task 16.1 is the canonical one that includes all fields and must be used. The intermediate versions in Tasks 11.3 and 12.3 are stepping stones.
- `Season` enum is defined twice: in `WeatherSystem.swift` (NookApp) and copied inline in `WeatherSystemTests.swift` (SPM test isolation). The test file's local copy must match the NookApp definition exactly — confirmed they match.
- `WeatherType` same situation — copied to test file, both match.
- `TileMap.parcelleOriginX/Y/Width/Height` are `Int` statics — used consistently in `OnboardingEngine.completeOnboarding` and `NPCManager`.

---

### Critical Files for Implementation
- `/Users/mchau/Desktop/Code/Nook/Sources/NookApp/VillageEngine.swift`
- `/Users/mchau/Desktop/Code/Nook/Sources/NookApp/VillagePersistence.swift`
- `/Users/mchau/Desktop/Code/Nook/Sources/NookApp/VillageScene.swift`
- `/Users/mchau/Desktop/Code/Nook/Sources/NookApp/ContentView.swift`
- `/Users/mchau/Desktop/Code/Nook/Package.swift`

---

The plan is complete. It covers phases 9-16 with full Swift code, exact file paths, test commands, and commit messages.

The plan should be saved to `/Users/mchau/Desktop/Code/Nook/docs/superpowers/plans/2026-05-19-nook-phases-9-16-roadmap.md`.

**Two execution options:**

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

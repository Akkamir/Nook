# Nook NPC Village Graphics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current square NPC prototype with a coherent Pixel Agents-style village NPC system: layered pixel characters, visible work states, multi-session load, bond progression, living village props, and a lightweight inspection loop.

**Architecture:** Keep the existing `VillageEngine` / `VillageScene` split. `VillageEngine` owns observed state from the daemon and session hooks; `NPCManager` translates engine state into SpriteKit entities; focused SpriteKit helper types own rendering and behavior. This plan deliberately avoids terminal panels, farming, build mode, and full tilemap optimization.

**Tech Stack:** Swift 6, SpriteKit, SwiftUI overlay, XcodeGen project source discovery, local JSON persistence under `~/.pixelvillage`, existing Claude hook/session detection.

---

## Scope Boundaries

Build now:
- Agent NPC visual states: idle, wandering, active at desk, night idle, overloaded.
- Multi-session count per NPC and visual load tiers: 1, 2, 3+ sessions.
- Bond visual progression from existing `AgentRecord.bond`.
- Pixel Agents-inspired office/village feel using procedural SpriteKit pixel nodes first.
- Village decor layer: desks, paths, trees, lamps, unlocked-zone landmarks.
- Click inspection panel for an NPC.

Defer:
- SwiftTerm terminal windows.
- Farming economy.
- Build/shop placement mode.
- Full `SKTileMapNode` migration.
- Downloaded third-party sprite packs. Procedural sprites keep this public repo clean and unblock iteration.

---

## Current State

Important files already exist:
- `Sources/NookApp/VillageEngine.swift` reads `ledger.json`, tracks total bits, agents, active sessions, day phase, and new bit events.
- `Sources/NookApp/SessionDetector.swift` maps Claude hooks and recent JSONL activity to active agent names.
- `Sources/NookApp/NPCManager.swift` creates one `NPCSprite` per ledger agent, starts/stops `NPCWander`, and routes `BitEvent`s.
- `Sources/NookApp/NPCSprite.swift` is currently a colored square with text labels and a pulse animation.
- `Sources/NookApp/NPCWander.swift` randomly moves inactive NPCs inside the central parcelle.
- `Sources/NookApp/TileMap.swift` renders a 128x128 map with current grass/dirt/tent assets.
- `Sources/NookApp/VillagePersistence.swift` persists NPC positions and revealed zones.
- `Sources/NookApp/ContentView.swift` owns the SwiftUI overlay and instantiates `VillageScene`.

---

## File Map

**Session load**
- Modify: `Sources/NookApp/SessionDetector.swift` — add active session counts while preserving existing `detectActive()`.
- Modify: `Sources/NookApp/VillageEngine.swift` — expose `activeSessionCounts: [String: Int]`.
- Modify: `Sources/NookApp/VillageScene.swift` — sync NPCs when counts change.

**NPC visual model**
- Create: `Sources/NookApp/NPCVisualState.swift` — pure data model for visual state and traits.
- Modify: `Sources/NookApp/NPCModel.swift` — add helper fields only if needed; keep it small.

**NPC rendering**
- Replace: `Sources/NookApp/NPCSprite.swift` — layered pixel-art node with body/head/hair/shadow/accessory/desk/status bubble.
- Create: `Sources/NookApp/PixelNodeFactory.swift` — small helpers for crisp rectangular pixel nodes.

**NPC behavior**
- Create: `Sources/NookApp/NPCBehavior.swift` — active desk behavior, inactive wandering, night behavior, facing.
- Modify: `Sources/NookApp/NPCManager.swift` — use `NPCBehavior`, visual state derivation, session counts, bond promotion detection.
- Leave: `Sources/NookApp/NPCWander.swift` — remove from live path after `NPCBehavior` lands; delete in cleanup task if unused.

**Village graphics**
- Create: `Sources/NookApp/VillageDecorLayer.swift` — paths, desk area, trees, lamps, zone markers.
- Modify: `Sources/NookApp/TileMap.swift` — expose map/parcelle helpers and add visual anchors.
- Modify: `Sources/NookApp/VillageScene.swift` — add decor layer between tiles and NPCs.

**Inspection UI**
- Create: `Sources/NookApp/NPCSelection.swift` — selected NPC data passed to SwiftUI.
- Modify: `Sources/NookApp/VillageScene.swift` — hit-test NPC clicks and publish selection.
- Modify: `Sources/NookApp/ContentView.swift` — compact NPC inspector overlay.

**Verification/docs**
- Modify: `docs/design.md` only if the implementation intentionally narrows behavior.
- Modify: `docs/superpowers/plans/2026-05-19-nook-phases-9-16-roadmap.md` to mark this plan as the immediate pre-farming priority.

---

## Task 1: Expose Active Session Counts

Current code only exposes a set of active agents, so one active session and three active sessions look identical. Add counts without breaking existing callers.

**Files:**
- Modify: `Sources/NookApp/SessionDetector.swift`
- Modify: `Sources/NookApp/VillageEngine.swift`
- Modify: `Sources/NookApp/VillageScene.swift`

- [ ] **Step 1: Add `detectActiveCounts()` to `SessionDetector`**

In `Sources/NookApp/SessionDetector.swift`, add this method below `detectActive()`:

```swift
func detectActiveCounts() -> [String: Int] {
    pruneState()
    let cutoff = now().addingTimeInterval(-300)
    var counts: [String: Int] = [:]

    for session in sessionAgents.values {
        guard recentlyEndedAgents[session.agent] == nil else { continue }
        counts[session.agent, default: 0] += 1
    }

    for agent in hookActiveAgents where recentlyEndedAgents[agent] == nil {
        counts[agent] = max(counts[agent, default: 0], 1)
    }

    guard let entries = try? fm.contentsOfDirectory(
        at: claudeProjectsURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles
    ) else { return counts }

    for entry in entries {
        guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
        if hasRecentJSONL(in: entry, since: cutoff),
           let name = agentName(forProjectDir: entry),
           recentlyEndedAgents[name] == nil {
            counts[name] = max(counts[name, default: 0], 1)
        }
    }

    return counts
}
```

- [ ] **Step 2: Rewrite `detectActive()` to derive from counts**

Replace the body of `detectActive()` with:

```swift
func detectActive() -> Set<String> {
    Set(detectActiveCounts().keys)
}
```

- [ ] **Step 3: Store counts in `VillageEngine`**

In `Sources/NookApp/VillageEngine.swift`, add the property next to `activeSessions`:

```swift
private(set) var activeSessionCounts: [String: Int] = [:]
```

Update the hook event callback:

```swift
if changed {
    self.activeSessionCounts = await self.sessionDetector.detectActiveCounts()
    self.activeSessions = Set(self.activeSessionCounts.keys)
}
```

Update the session timer callback:

```swift
let counts = await self.sessionDetector.detectActiveCounts()
self.activeSessionCounts = counts
self.activeSessions = Set(counts.keys)
```

- [ ] **Step 4: Track count changes in `VillageScene`**

In `Sources/NookApp/VillageScene.swift`, add:

```swift
private var lastActiveSessionCounts: [String: Int] = [:]
```

Set it in `configure(engine:)`:

```swift
lastActiveSessionCounts = engine.activeSessionCounts
```

In `update(_:)`, after active session syncing, add:

```swift
if let engine, engine.activeSessionCounts != lastActiveSessionCounts {
    npcManager?.syncVisualStates()
    lastActiveSessionCounts = engine.activeSessionCounts
}
```

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Sources/NookApp/SessionDetector.swift Sources/NookApp/VillageEngine.swift Sources/NookApp/VillageScene.swift
git commit -m "feat: track active session counts per NPC"
```

---

## Task 2: Add NPC Visual State Model

Create a pure model that centralizes visual decisions. This keeps SpriteKit rendering simple and makes state derivation reviewable.

**Files:**
- Create: `Sources/NookApp/NPCVisualState.swift`

- [ ] **Step 1: Create `NPCVisualState.swift`**

```swift
import Foundation

enum NPCActivityKind: Equatable {
    case wandering
    case working(sessionCount: Int)
    case resting
}

enum NPCWorkTrait: String, Codable, Equatable {
    case newAgent
    case steady
    case deepThinker
    case powerUser
}

struct NPCVisualState: Equatable {
    let id: String
    let name: String
    let bond: Int
    let totalTokens: Int
    let totalBits: Double
    let activity: NPCActivityKind
    let trait: NPCWorkTrait
    let isNight: Bool

    var sessionCount: Int {
        if case let .working(count) = activity { return count }
        return 0
    }

    var isWorking: Bool {
        sessionCount > 0
    }

    var loadTier: Int {
        min(sessionCount, 3)
    }

    static func derive(
        from model: NPCModel,
        activeSessionCount: Int,
        dayPhase: DayPhase
    ) -> NPCVisualState {
        let activity: NPCActivityKind
        if activeSessionCount > 0 {
            activity = .working(sessionCount: activeSessionCount)
        } else if dayPhase == .night {
            activity = .resting
        } else {
            activity = .wandering
        }

        return NPCVisualState(
            id: model.id,
            name: model.name,
            bond: model.bond,
            totalTokens: model.totalTokens,
            totalBits: model.totalBits,
            activity: activity,
            trait: NPCVisualState.trait(for: model),
            isNight: dayPhase == .night
        )
    }

    private static func trait(for model: NPCModel) -> NPCWorkTrait {
        switch model.totalTokens {
        case ..<10_000:
            return .newAgent
        case ..<50_000:
            return .steady
        case ..<200_000:
            return .deepThinker
        default:
            return .powerUser
        }
    }
}
```

- [ ] **Step 2: Add a temporary compile probe**

Create `/tmp/nook_visual_state_probe.swift`:

```swift
import Foundation

enum DayPhase: Equatable { case sunrise, day, sunset, night }
struct NPCModel {
    let id: String
    var name: String
    var bond: Int
    var totalTokens: Int
    var totalBits: Double
    var tileX: Int
    var tileY: Int
}

// Paste the full contents of Sources/NookApp/NPCVisualState.swift below this line.

let model = NPCModel(id: "Coach", name: "Coach", bond: 3, totalTokens: 60_000, totalBits: 800, tileX: 1, tileY: 1)
let visual = NPCVisualState.derive(from: model, activeSessionCount: 2, dayPhase: .night)
precondition(visual.sessionCount == 2)
precondition(visual.loadTier == 2)
precondition(visual.trait == .deepThinker)
precondition(visual.isWorking)
```

Run:

```bash
swift /tmp/nook_visual_state_probe.swift
```

Expected: exits with status `0`.

- [ ] **Step 3: Build app**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Sources/NookApp/NPCVisualState.swift
git commit -m "feat: add NPC visual state model"
```

---

## Task 3: Add Pixel Node Rendering Helpers

Use procedural pixel nodes for now. This gives a real visual upgrade without asset licensing or sprite pack integration.

**Files:**
- Create: `Sources/NookApp/PixelNodeFactory.swift`

- [ ] **Step 1: Create `PixelNodeFactory.swift`**

```swift
import SpriteKit

@MainActor
enum PixelNodeFactory {
    static func rect(
        size: CGSize,
        color: NSColor,
        position: CGPoint = .zero,
        z: CGFloat = 0
    ) -> SKSpriteNode {
        let node = SKSpriteNode(color: color, size: size)
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.position = position
        node.zPosition = z
        node.colorBlendFactor = 1
        return node
    }

    static func label(
        _ text: String,
        size: CGFloat,
        color: NSColor,
        position: CGPoint,
        z: CGFloat = 0
    ) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "Monaco")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = position
        label.zPosition = z
        return label
    }

    static func bubble(text: String, position: CGPoint) -> SKNode {
        let root = SKNode()
        root.position = position
        root.zPosition = 80
        let background = rect(
            size: CGSize(width: 34, height: 20),
            color: NSColor.black.withAlphaComponent(0.78),
            z: 0
        )
        let label = label(text, size: 11, color: .white, position: CGPoint(x: 0, y: 1), z: 1)
        root.addChild(background)
        root.addChild(label)
        return root
    }
}
```

- [ ] **Step 2: Build app**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Sources/NookApp/PixelNodeFactory.swift
git commit -m "feat: add pixel node rendering helpers"
```

---

## Task 4: Replace NPCSprite With Layered Pixel Character

The current NPC is a single square. Replace it with a top-down-ish layered character that reads closer to Pixel Agents: shadow, feet, body, head, hair, accessory, status bubble, desk for active sessions.

**Files:**
- Replace: `Sources/NookApp/NPCSprite.swift`

- [ ] **Step 1: Replace `NPCSprite` storage**

In `NPCSprite.swift`, replace the current private properties with:

```swift
private let shadow: SKSpriteNode
private let leftFoot: SKSpriteNode
private let rightFoot: SKSpriteNode
private let body: SKSpriteNode
private let head: SKSpriteNode
private let hair: SKSpriteNode
private let accessory: SKSpriteNode
private let desk: SKNode
private let statusBubble = SKNode()
private let nameLabel: SKLabelNode
private let bondLabel: SKLabelNode
private var currentVisualState: NPCVisualState?
```

- [ ] **Step 2: Replace initializer**

Use this initializer body:

```swift
init(model: NPCModel) {
    shadow = PixelNodeFactory.rect(
        size: CGSize(width: 34, height: 10),
        color: NSColor.black.withAlphaComponent(0.35),
        position: CGPoint(x: 0, y: -15),
        z: -2
    )
    leftFoot = PixelNodeFactory.rect(size: CGSize(width: 8, height: 8), color: NSColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1), position: CGPoint(x: -7, y: -12), z: 1)
    rightFoot = PixelNodeFactory.rect(size: CGSize(width: 8, height: 8), color: NSColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1), position: CGPoint(x: 7, y: -12), z: 1)
    body = PixelNodeFactory.rect(size: CGSize(width: 22, height: 24), color: NSColor(red: 0.31, green: 0.62, blue: 0.78, alpha: 1), position: CGPoint(x: 0, y: -1), z: 2)
    head = PixelNodeFactory.rect(size: CGSize(width: 20, height: 18), color: NSColor(red: 0.93, green: 0.75, blue: 0.58, alpha: 1), position: CGPoint(x: 0, y: 18), z: 3)
    hair = PixelNodeFactory.rect(size: CGSize(width: 22, height: 7), color: NSColor(red: 0.17, green: 0.10, blue: 0.07, alpha: 1), position: CGPoint(x: 0, y: 27), z: 4)
    accessory = PixelNodeFactory.rect(size: CGSize(width: 24, height: 4), color: NSColor.clear, position: CGPoint(x: 0, y: 18), z: 5)
    desk = SKNode()
    nameLabel = PixelNodeFactory.label(model.name, size: 10, color: .white, position: CGPoint(x: 0, y: 48), z: 20)
    bondLabel = PixelNodeFactory.label("", size: 9, color: NSColor(red: 1.0, green: 0.86, blue: 0.35, alpha: 1), position: CGPoint(x: 0, y: 62), z: 20)
    super.init()

    desk.zPosition = -1
    desk.isHidden = true
    desk.addChild(PixelNodeFactory.rect(size: CGSize(width: 46, height: 18), color: NSColor(red: 0.28, green: 0.18, blue: 0.10, alpha: 1), position: CGPoint(x: 0, y: -28), z: 0))
    desk.addChild(PixelNodeFactory.rect(size: CGSize(width: 16, height: 10), color: NSColor(red: 0.07, green: 0.12, blue: 0.16, alpha: 1), position: CGPoint(x: -11, y: -20), z: 1))

    addChild(shadow)
    addChild(desk)
    addChild(leftFoot)
    addChild(rightFoot)
    addChild(body)
    addChild(head)
    addChild(hair)
    addChild(accessory)
    addChild(nameLabel)
    addChild(bondLabel)
    addChild(statusBubble)

    update(model: model)
}
```

Keep the existing `required init?(coder:)`.

- [ ] **Step 3: Add `apply(visualState:)`**

Add this method:

```swift
func apply(visualState: NPCVisualState) {
    currentVisualState = visualState
    nameLabel.text = visualState.name
    bondLabel.text = "Bond \(visualState.bond)  \(formatBits(visualState.totalBits))"

    let palette = palette(for: visualState)
    body.color = palette.body
    hair.color = palette.hair
    accessory.color = palette.accessory
    accessory.isHidden = visualState.bond < 2
    desk.isHidden = !visualState.isWorking

    statusBubble.removeAllChildren()
    if visualState.isWorking {
        let symbol = visualState.loadTier >= 3 ? "!!!" : String(repeating: ">", count: visualState.loadTier)
        statusBubble.addChild(PixelNodeFactory.bubble(text: symbol, position: CGPoint(x: 0, y: 82)))
        startWorkingAnimation(loadTier: visualState.loadTier)
    } else if visualState.activity == .resting {
        statusBubble.addChild(PixelNodeFactory.bubble(text: "zzz", position: CGPoint(x: 0, y: 82)))
        stopWorkingAnimation()
    } else {
        stopWorkingAnimation()
    }
}
```

- [ ] **Step 4: Update existing `update(model:)`**

Replace `update(model:)` with:

```swift
func update(model: NPCModel) {
    let fallback = NPCVisualState.derive(from: model, activeSessionCount: currentVisualState?.sessionCount ?? 0, dayPhase: currentVisualState?.isNight == true ? .night : .day)
    apply(visualState: fallback)
}
```

- [ ] **Step 5: Add palette and animation helpers**

Add these private methods above `formatBits(_:)`:

```swift
private func palette(for state: NPCVisualState) -> (body: NSColor, hair: NSColor, accessory: NSColor) {
    let bodyColors: [NSColor] = [
        NSColor(red: 0.31, green: 0.62, blue: 0.78, alpha: 1),
        NSColor(red: 0.50, green: 0.70, blue: 0.38, alpha: 1),
        NSColor(red: 0.66, green: 0.48, blue: 0.78, alpha: 1),
        NSColor(red: 0.82, green: 0.58, blue: 0.30, alpha: 1),
        NSColor(red: 0.90, green: 0.74, blue: 0.26, alpha: 1)
    ]
    let index = max(0, min(state.bond - 1, bodyColors.count - 1))
    let accessory: NSColor
    switch state.trait {
    case .newAgent: accessory = .clear
    case .steady: accessory = NSColor(red: 0.95, green: 0.95, blue: 0.78, alpha: 1)
    case .deepThinker: accessory = NSColor(red: 0.10, green: 0.13, blue: 0.18, alpha: 1)
    case .powerUser: accessory = NSColor(red: 0.25, green: 0.95, blue: 0.74, alpha: 1)
    }
    return (
        body: bodyColors[index],
        hair: state.isNight ? NSColor(red: 0.08, green: 0.08, blue: 0.13, alpha: 1) : NSColor(red: 0.17, green: 0.10, blue: 0.07, alpha: 1),
        accessory: accessory
    )
}

private func startWorkingAnimation(loadTier: Int) {
    let duration = max(0.12, 0.34 - Double(loadTier) * 0.06)
    if action(forKey: "workBob") == nil {
        let bob = SKAction.repeatForever(.sequence([
            .moveBy(x: 0, y: 2, duration: duration),
            .moveBy(x: 0, y: -2, duration: duration)
        ]))
        run(bob, withKey: "workBob")
    }
}

private func stopWorkingAnimation() {
    removeAction(forKey: "workBob")
}
```

- [ ] **Step 6: Update `setActive(_:)`**

Replace `setActive(_:)` with:

```swift
func setActive(_ isActive: Bool) {
    if isActive {
        startWorkingAnimation(loadTier: max(currentVisualState?.loadTier ?? 1, 1))
    } else {
        stopWorkingAnimation()
        setScale(1.0)
    }
}
```

- [ ] **Step 7: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add Sources/NookApp/NPCSprite.swift
git commit -m "feat: render layered pixel NPC sprites"
```

---

## Task 5: Replace Wander With NPCBehavior

`NPCWander` only random-walks. Add a behavior controller that understands working at a desk, idle wandering, night resting, and pixel-step movement.

**Files:**
- Create: `Sources/NookApp/NPCBehavior.swift`
- Modify: `Sources/NookApp/NPCManager.swift`

- [ ] **Step 1: Create `NPCBehavior.swift`**

```swift
import SpriteKit

@MainActor
final class NPCBehavior {
    private let sprite: NPCSprite
    private var model: NPCModel
    private let deskTile: TilePosition
    private var currentActivity: NPCActivityKind = .wandering

    init(sprite: NPCSprite, model: NPCModel, deskTile: TilePosition) {
        self.sprite = sprite
        self.model = model
        self.deskTile = deskTile
    }

    func apply(_ visualState: NPCVisualState) {
        guard visualState.activity != currentActivity else { return }
        currentActivity = visualState.activity
        sprite.removeAction(forKey: "behavior")

        switch visualState.activity {
        case .working:
            moveTo(tile: deskTile, speed: 0.18, key: "behavior")
        case .resting:
            startResting()
        case .wandering:
            startWandering()
        }
    }

    func currentTile() -> TilePosition {
        TilePosition(
            tileX: Int(sprite.position.x / TileMap.tileSize),
            tileY: Int(sprite.position.y / TileMap.tileSize)
        )
    }

    private func startWandering() {
        let wait = SKAction.wait(forDuration: 1.8, withRange: 1.2)
        let step = SKAction.run { [weak self] in self?.randomStep() }
        sprite.run(.repeatForever(.sequence([wait, step])), withKey: "behavior")
    }

    private func startResting() {
        let wait = SKAction.wait(forDuration: 3.0, withRange: 2.0)
        let tinyMove = SKAction.run { [weak self] in self?.randomStep(maxOffset: 1) }
        sprite.run(.repeatForever(.sequence([wait, tinyMove])), withKey: "behavior")
    }

    private func randomStep(maxOffset: Int = 2) {
        let offsetX = Int.random(in: -maxOffset...maxOffset)
        let offsetY = Int.random(in: -maxOffset...maxOffset)
        let newTile = TilePosition(
            tileX: (model.tileX + offsetX).clamped(to: TileMap.parcelleOriginX...(TileMap.parcelleOriginX + TileMap.parcelleWidth - 1)),
            tileY: (model.tileY + offsetY).clamped(to: TileMap.parcelleOriginY...(TileMap.parcelleOriginY + TileMap.parcelleHeight - 1))
        )
        guard newTile.tileX != model.tileX || newTile.tileY != model.tileY else { return }
        moveTo(tile: newTile, speed: 0.24, key: nil)
    }

    private func moveTo(tile: TilePosition, speed: Double, key: String?) {
        let point = CGPoint(
            x: CGFloat(tile.tileX) * TileMap.tileSize + TileMap.tileSize / 2,
            y: CGFloat(tile.tileY) * TileMap.tileSize + TileMap.tileSize / 2
        )
        let dx = tile.tileX - model.tileX
        let dy = tile.tileY - model.tileY
        let duration = Double(max(abs(dx), abs(dy))) * speed
        model.tileX = tile.tileX
        model.tileY = tile.tileY
        let action = SKAction.move(to: point, duration: max(duration, 0.1))
        if let key {
            sprite.run(action, withKey: key)
        } else {
            sprite.run(action)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
```

- [ ] **Step 2: Replace manager storage**

In `NPCManager.swift`, replace:

```swift
private var wanders: [String: NPCWander] = [:]
```

with:

```swift
private var behaviors: [String: NPCBehavior] = [:]
private var lastBondByAgent: [String: Int] = [:]
```

- [ ] **Step 3: Add deterministic desk slot helper**

Add to `NPCManager`:

```swift
private func deskTile(for index: Int) -> TilePosition {
    let startX = TileMap.parcelleOriginX + 4
    let startY = TileMap.parcelleOriginY + TileMap.parcelleHeight - 5
    let col = index % 4
    let row = index / 4
    return TilePosition(tileX: startX + col * 4, tileY: startY - row * 3)
}
```

- [ ] **Step 4: Update additions in `sync()`**

Inside the addition loop, before constructing `NPCBehavior`, compute a stable index:

```swift
let sortedIDs = engine.agents.keys.sorted()
let slotIndex = sortedIDs.firstIndex(of: id) ?? sprites.count
let behavior = NPCBehavior(sprite: sprite, model: model, deskTile: deskTile(for: slotIndex))
let visualState = NPCVisualState.derive(
    from: model,
    activeSessionCount: engine.activeSessionCounts[id, default: 0],
    dayPhase: engine.dayPhase
)
sprite.apply(visualState: visualState)
behavior.apply(visualState)
```

Store it:

```swift
behaviors[id] = behavior
lastBondByAgent[id] = record.bond
```

Do not create or start `NPCWander`.

- [ ] **Step 5: Add `syncVisualStates()`**

Add this public method to `NPCManager`:

```swift
func syncVisualStates() {
    for (id, model) in models {
        guard let sprite = sprites[id], let behavior = behaviors[id] else { continue }
        let visualState = NPCVisualState.derive(
            from: model,
            activeSessionCount: engine.activeSessionCounts[id, default: 0],
            dayPhase: engine.dayPhase
        )
        sprite.apply(visualState: visualState)
        behavior.apply(visualState)
    }
}
```

- [ ] **Step 6: Update removals**

In the removal block, replace `wanders` cleanup with:

```swift
behaviors.removeValue(forKey: id)
lastBondByAgent.removeValue(forKey: id)
```

- [ ] **Step 7: Update position persistence**

Replace `currentPositions()` implementation with:

```swift
func currentPositions() -> [String: TilePosition] {
    var result: [String: TilePosition] = [:]
    for (id, behavior) in behaviors {
        result[id] = behavior.currentTile()
    }
    return result
}
```

- [ ] **Step 8: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 9: Commit**

```bash
git add Sources/NookApp/NPCBehavior.swift Sources/NookApp/NPCManager.swift
git commit -m "feat: add NPC behavior states"
```

---

## Task 6: Add Bond Promotion and Visual Sync

Make progression visible when bond changes, and route all state updates through `NPCVisualState`.

**Files:**
- Modify: `Sources/NookApp/NPCSprite.swift`
- Modify: `Sources/NookApp/NPCManager.swift`
- Modify: `Sources/NookApp/VillageScene.swift`

- [ ] **Step 1: Add bond promotion animation**

Add to `NPCSprite.swift`:

```swift
func showBondPromotion(level: Int) {
    let ring = SKShapeNode(circleOfRadius: 28)
    ring.strokeColor = NSColor(red: 1.0, green: 0.88, blue: 0.30, alpha: 1)
    ring.lineWidth = 3
    ring.alpha = 0.95
    ring.zPosition = 70
    addChild(ring)

    let label = PixelNodeFactory.label("Bond \(level)", size: 12, color: NSColor(red: 1.0, green: 0.88, blue: 0.30, alpha: 1), position: CGPoint(x: 0, y: 94), z: 72)
    addChild(label)

    ring.run(.sequence([
        .group([.scale(to: 1.8, duration: 0.55), .fadeOut(withDuration: 0.55)]),
        .removeFromParent()
    ]))
    label.run(.sequence([
        .group([.moveBy(x: 0, y: 24, duration: 0.9), .fadeOut(withDuration: 0.9)]),
        .removeFromParent()
    ]))
}
```

- [ ] **Step 2: Detect bond promotions in `NPCManager.sync()`**

In the updates block, after `sprites[id]?.update(model: updated)`, add:

```swift
if let previousBond = lastBondByAgent[id], record.bond > previousBond {
    sprites[id]?.showBondPromotion(level: record.bond)
}
lastBondByAgent[id] = record.bond
```

Then call:

```swift
syncVisualStates()
```

after the update loop finishes.

- [ ] **Step 3: Sync on day phase changes**

In `VillageScene.swift`, add:

```swift
private var lastDayPhase: DayPhase?
```

Set in `configure(engine:)`:

```swift
lastDayPhase = engine.dayPhase
```

In `update(_:)`, add:

```swift
if let engine, engine.dayPhase != lastDayPhase {
    npcManager?.syncVisualStates()
    lastDayPhase = engine.dayPhase
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Sources/NookApp/NPCSprite.swift Sources/NookApp/NPCManager.swift Sources/NookApp/VillageScene.swift
git commit -m "feat: animate NPC bond progression"
```

---

## Task 7: Add Village Decor Layer

Create a distinct visual layer that makes the village read as a place, not a grid with NPCs.

**Files:**
- Create: `Sources/NookApp/VillageDecorLayer.swift`
- Modify: `Sources/NookApp/VillageScene.swift`

- [ ] **Step 1: Create `VillageDecorLayer.swift`**

```swift
import SpriteKit

@MainActor
final class VillageDecorLayer: SKNode {
    override init() {
        super.init()
        zPosition = 4
        buildPaths()
        buildOfficeArea()
        buildTrees()
        buildLamps()
        buildZoneMarkers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildPaths() {
        let pathColor = NSColor(red: 0.48, green: 0.36, blue: 0.22, alpha: 1)
        addChild(PixelNodeFactory.rect(
            size: CGSize(width: CGFloat(TileMap.parcelleWidth) * TileMap.tileSize, height: 3 * TileMap.tileSize),
            color: pathColor,
            position: world(tileX: TileMap.parcelleOriginX + TileMap.parcelleWidth / 2, tileY: TileMap.parcelleOriginY + TileMap.parcelleHeight / 2),
            z: 0
        ))
        addChild(PixelNodeFactory.rect(
            size: CGSize(width: 3 * TileMap.tileSize, height: CGFloat(TileMap.parcelleHeight) * TileMap.tileSize),
            color: pathColor,
            position: world(tileX: TileMap.parcelleOriginX + TileMap.parcelleWidth / 2, tileY: TileMap.parcelleOriginY + TileMap.parcelleHeight / 2),
            z: 0
        ))
    }

    private func buildOfficeArea() {
        let rug = PixelNodeFactory.rect(
            size: CGSize(width: 18 * TileMap.tileSize, height: 7 * TileMap.tileSize),
            color: NSColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1),
            position: world(tileX: TileMap.parcelleOriginX + 10, tileY: TileMap.parcelleOriginY + 15),
            z: 1
        )
        rug.alpha = 0.75
        addChild(rug)
    }

    private func buildTrees() {
        let positions = [
            TilePosition(tileX: TileMap.parcelleOriginX + 1, tileY: TileMap.parcelleOriginY + 1),
            TilePosition(tileX: TileMap.parcelleOriginX + 18, tileY: TileMap.parcelleOriginY + 2),
            TilePosition(tileX: TileMap.parcelleOriginX + 2, tileY: TileMap.parcelleOriginY + 18),
            TilePosition(tileX: TileMap.parcelleOriginX + 18, tileY: TileMap.parcelleOriginY + 18)
        ]
        for position in positions {
            addChild(tree(at: position))
        }
    }

    private func buildLamps() {
        for position in [
            TilePosition(tileX: TileMap.parcelleOriginX + 5, tileY: TileMap.parcelleOriginY + 14),
            TilePosition(tileX: TileMap.parcelleOriginX + 15, tileY: TileMap.parcelleOriginY + 14)
        ] {
            let lamp = SKNode()
            lamp.position = world(tileX: position.tileX, tileY: position.tileY)
            lamp.addChild(PixelNodeFactory.rect(size: CGSize(width: 6, height: 26), color: NSColor(red: 0.14, green: 0.12, blue: 0.10, alpha: 1), position: CGPoint(x: 0, y: 5), z: 2))
            lamp.addChild(PixelNodeFactory.rect(size: CGSize(width: 18, height: 12), color: NSColor(red: 1.0, green: 0.78, blue: 0.35, alpha: 1), position: CGPoint(x: 0, y: 23), z: 3))
            addChild(lamp)
        }
    }

    private func buildZoneMarkers() {
        let markers: [(String, TilePosition)] = [
            ("FOREST", TilePosition(tileX: TileMap.parcelleOriginX - 4, tileY: TileMap.parcelleOriginY + 10)),
            ("LAKE", TilePosition(tileX: TileMap.parcelleOriginX + 10, tileY: TileMap.parcelleOriginY - 4)),
            ("MARKET", TilePosition(tileX: TileMap.parcelleOriginX + 24, tileY: TileMap.parcelleOriginY + 10)),
            ("MOUNT", TilePosition(tileX: TileMap.parcelleOriginX + 10, tileY: TileMap.parcelleOriginY + 24))
        ]
        for (text, position) in markers {
            let sign = PixelNodeFactory.bubble(text: text, position: world(tileX: position.tileX, tileY: position.tileY))
            sign.setScale(0.75)
            addChild(sign)
        }
    }

    private func tree(at tile: TilePosition) -> SKNode {
        let root = SKNode()
        root.position = world(tileX: tile.tileX, tileY: tile.tileY)
        root.addChild(PixelNodeFactory.rect(size: CGSize(width: 10, height: 20), color: NSColor(red: 0.35, green: 0.20, blue: 0.10, alpha: 1), position: CGPoint(x: 0, y: -2), z: 1))
        root.addChild(PixelNodeFactory.rect(size: CGSize(width: 34, height: 30), color: NSColor(red: 0.16, green: 0.42, blue: 0.22, alpha: 1), position: CGPoint(x: 0, y: 18), z: 2))
        root.addChild(PixelNodeFactory.rect(size: CGSize(width: 24, height: 22), color: NSColor(red: 0.22, green: 0.56, blue: 0.28, alpha: 1), position: CGPoint(x: 0, y: 30), z: 3))
        return root
    }

    private func world(tileX: Int, tileY: Int) -> CGPoint {
        CGPoint(
            x: CGFloat(tileX) * TileMap.tileSize + TileMap.tileSize / 2,
            y: CGFloat(tileY) * TileMap.tileSize + TileMap.tileSize / 2
        )
    }
}
```

- [ ] **Step 2: Add layer to scene**

In `VillageScene.swift`, add:

```swift
private var decorLayer: VillageDecorLayer?
```

After `tileMap.build()` in `didMove(to:)`, add:

```swift
let decor = VillageDecorLayer()
addChild(decor)
decorLayer = decor
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Sources/NookApp/VillageDecorLayer.swift Sources/NookApp/VillageScene.swift
git commit -m "feat: add village decor layer"
```

---

## Task 8: Add NPC Selection and Inspector

Give the user a lightweight interaction loop: click an NPC, see who it is and why it looks the way it does.

**Files:**
- Create: `Sources/NookApp/NPCSelection.swift`
- Modify: `Sources/NookApp/NPCManager.swift`
- Modify: `Sources/NookApp/VillageScene.swift`
- Modify: `Sources/NookApp/ContentView.swift`

- [ ] **Step 1: Create `NPCSelection.swift`**

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
}
```

- [ ] **Step 2: Add selection lookup to `NPCManager`**

Add to `NPCManager.swift`:

```swift
func npcID(at point: CGPoint) -> String? {
    sprites.first { _, sprite in
        sprite.calculateAccumulatedFrame().insetBy(dx: -12, dy: -12).contains(point)
    }?.key
}

func selection(for id: String) -> NPCSelection? {
    guard let model = models[id] else { return nil }
    let visualState = NPCVisualState.derive(
        from: model,
        activeSessionCount: engine.activeSessionCounts[id, default: 0],
        dayPhase: engine.dayPhase
    )
    return NPCSelection(
        id: id,
        name: model.name,
        bond: model.bond,
        totalTokens: model.totalTokens,
        totalBits: model.totalBits,
        activeSessionCount: visualState.sessionCount,
        trait: visualState.trait
    )
}
```

- [ ] **Step 3: Publish selection from `VillageScene`**

In `VillageScene.swift`, add:

```swift
var onNPCSelection: ((NPCSelection?) -> Void)?
```

Add:

```swift
override func mouseDown(with event: NSEvent) {
    let point = event.location(in: self)
    guard let id = npcManager?.npcID(at: point),
          let selection = npcManager?.selection(for: id) else {
        onNPCSelection?(nil)
        return
    }
    onNPCSelection?(selection)
}
```

- [ ] **Step 4: Store selection in `ContentView`**

In `ContentView.swift`, add:

```swift
@State private var selectedNPC: NPCSelection?
```

When creating the scene, before `scene = s`, add:

```swift
s.onNPCSelection = { selection in
    selectedNPC = selection
}
```

Inside the `ZStack`, below the bits HUD, add:

```swift
if let selectedNPC {
    VStack(alignment: .leading, spacing: 6) {
        Text(selectedNPC.name)
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
        Text("Bond \(selectedNPC.bond)")
        Text("\(selectedNPC.totalTokens) tokens")
        Text("\(selectedNPC.totalBits, specifier: "%.1f") Bits")
        Text(selectedNPC.activeSessionCount > 0 ? "\(selectedNPC.activeSessionCount) active session(s)" : "Idle")
        Text(selectedNPC.trait.rawValue)
    }
    .font(.system(size: 12, weight: .regular, design: .monospaced))
    .foregroundStyle(.white)
    .padding(10)
    .background(.black.opacity(0.72))
    .cornerRadius(4)
    .padding(.top, 56)
    .padding(.leading, 16)
}
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add Sources/NookApp/NPCSelection.swift Sources/NookApp/NPCManager.swift Sources/NookApp/VillageScene.swift Sources/NookApp/ContentView.swift
git commit -m "feat: add NPC inspection overlay"
```

---

## Task 9: Clean Up Old NPCWander Path

After `NPCBehavior` is live, remove the old behavior class if no references remain.

**Files:**
- Delete: `Sources/NookApp/NPCWander.swift`

- [ ] **Step 1: Verify no references remain**

Run:

```bash
rg "NPCWander|wanders" /Users/mchau/Desktop/Code/Nook/Sources/NookApp
```

Expected: no output.

- [ ] **Step 2: Delete file**

```bash
rm /Users/mchau/Desktop/Code/Nook/Sources/NookApp/NPCWander.swift
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add -A Sources/NookApp/NPCWander.swift
git commit -m "chore: remove old NPC wander controller"
```

---

## Task 10: Final Verification and Roadmap Update

Verify the full app/daemon surface and record that this plan is the immediate priority before farming/build/terminal work.

**Files:**
- Modify: `docs/superpowers/plans/2026-05-19-nook-phases-9-16-roadmap.md`

- [ ] **Step 1: Run daemon tests**

```bash
swift test --package-path /Users/mchau/Desktop/Code/Nook
```

Expected: all `NookTests` pass with `0 failures`.

- [ ] **Step 2: Run app build**

```bash
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Update roadmap priority**

In `docs/superpowers/plans/2026-05-19-nook-phases-9-16-roadmap.md`, add this note under the backlog section:

```markdown
- **Immediate visual foundation before Phase 10+** — execute `docs/superpowers/plans/2026-05-19-nook-npc-village-graphics.md` before farming, terminal panels, or build mode. The app needs a convincing NPC/village baseline first.
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/plans/2026-05-19-nook-phases-9-16-roadmap.md
git commit -m "docs: prioritize NPC village graphics foundation"
```

- [ ] **Step 5: Push**

```bash
git push
```

Expected: branch `master` pushes to `origin/master`.

---

## Self-Review

Spec coverage:
- NPC lifecycle active/inactive/night is covered by Tasks 1, 2, 5, and 6.
- Multi-session visual load is covered by Tasks 1, 2, and 4.
- Bond progression is covered by Task 6.
- Pixel Agents-style graphics direction is covered by Tasks 3, 4, and 7.
- Village liveliness before farming/build/terminal work is covered by Task 7.
- Basic NPC interaction is covered by Task 8.

Known constraints:
- This plan uses procedural SpriteKit nodes instead of external bitmap sprite packs. That is intentional for the first visual foundation.
- The plan keeps the current `TileMap` architecture and adds a decor layer. Full tilemap optimization stays deferred.
- App-side behavior is verified through Xcode builds because the current repo has SwiftPM tests only for `NookDaemon`.

Placeholder scan:
- The plan contains no placeholder requirements, vague edge-handling steps, or unbounded implementation instructions.

Type consistency:
- `NPCVisualState`, `NPCActivityKind`, `NPCWorkTrait`, `TilePosition`, and `NPCSelection` are introduced before use.
- `activeSessionCounts` is added to `VillageEngine` before `NPCManager` consumes it.

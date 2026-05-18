# Phase 2 — Village Engine + SpriteKit App

**Objectif :** App Mac fonctionnelle avec une scène SpriteKit affichant un village pixel art, un compteur de Bits en temps réel, et une caméra navigable. Le daemon Phase 1 continue de tourner indépendamment ; l'app lit `~/.pixelvillage/ledger.json` en FSEvents.

**Livrable :** `open NookApp.xcodeproj` → une fenêtre s'ouvre avec une parcelle herbeuse 20×20, une tente au centre, un compteur de Bits en HUD, caméra pan/zoom fonctionnelle.

---

## Stack décidée

| Décision | Choix |
|---|---|
| Project format | Xcode project via XcodeGen |
| Entry point | SwiftUI `@main` + `SpriteView` |
| Rendu | SpriteKit, `SKTextureFilteringMode.nearest` |
| Assets | Kenney "Tiny Town" CC0 |
| Partage models | Duplication minimaliste dans `Sources/NookApp/` (pas de refactoring du daemon) |
| État partagé | `@Observable` `VillageEngine` passé via SwiftUI `.environment` |
| Surveillance ledger | `DispatchSource.makeFileSystemObjectSource` sur `~/.pixelvillage/ledger.json` |

---

## Structure cible

```
Nook/
├── Package.swift                    ← inchangé (daemon Phase 1)
├── Sources/
│   ├── NookDaemon/                  ← inchangé
│   └── NookApp/                     ← NOUVEAU
│       ├── NookApp.swift            — @main, SwiftUI App
│       ├── ContentView.swift        — SpriteView wrapper
│       ├── LedgerModels.swift       — LedgerState, AgentRecord (Codable)
│       ├── LedgerWatcher.swift      — FSEvents sur ledger.json
│       ├── VillageEngine.swift      — @Observable, source of truth
│       ├── VillageScene.swift       — SKScene principale
│       ├── TileMap.swift            — grille 128×128, parcelle centrale
│       ├── Camera.swift             — pan + zoom
│       └── HUD.swift                — overlay Bits counter
├── NookApp/
│   ├── Assets.xcassets/             — sprites Kenney
│   └── Info.plist
├── project.yml                      — XcodeGen spec
└── NookApp.xcodeproj/               — généré par XcodeGen
```

---

## Tâches

### Task 1 — Scaffold Xcode project [XcodeGen]

**But :** Avoir un projet Xcode qui compile un "Hello World" SpriteKit.

**Actions :**
1. `brew install xcodegen`
2. Créer `project.yml` à la racine de `Nook/`
3. Créer `NookApp/Info.plist`
4. Créer `Sources/NookApp/NookApp.swift` (entry point minimal)
5. Créer `Sources/NookApp/ContentView.swift` (SpriteView placeholder)
6. `xcodegen generate`
7. `xcodebuild -project NookApp.xcodeproj -scheme NookApp build`

**`project.yml` :**
```yaml
name: NookApp
options:
  bundleIdPrefix: com.mchau
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15"
targets:
  NookApp:
    type: application
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - path: Sources/NookApp
      - path: NookApp
    info:
      path: NookApp/Info.plist
      properties:
        CFBundleName: Nook
        CFBundleIdentifier: com.mchau.nook
        CFBundleVersion: "1"
        CFBundleShortVersionString: "0.1"
        LSMinimumSystemVersion: "13.0"
        NSPrincipalClass: NSApplication
        NSMainNibFile: ""
        NSHighResolutionCapable: true
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: true
        com.apple.security.app-sandbox: false
    settings:
      base:
        PRODUCT_NAME: Nook
        SWIFT_VERSION: "6.0"
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        ENABLE_HARDENED_RUNTIME: false
    entitlements:
      path: NookApp/NookApp.entitlements
      properties:
        com.apple.security.app-sandbox: false
```

**Critère de succès :** `xcodebuild build` passe sans erreur, `swift build` (daemon) toujours vert.

---

### Task 2 — LedgerModels + LedgerWatcher

**But :** L'app peut lire `~/.pixelvillage/ledger.json` et être notifiée de chaque changement.

**`LedgerModels.swift` :** Copie des structs `LedgerState` et `AgentRecord` du daemon (Codable). **Ne pas importer le module daemon** — duplication intentionnelle.

**`LedgerWatcher.swift` :**
```swift
final class LedgerWatcher {
    private let ledgerURL: URL
    private var source: DispatchSourceProtocol?
    var onChange: (() -> Void)?

    init(ledgerURL: URL = FileManager.default.homeDirectoryForCurrentUser
             .appendingPathComponent(".pixelvillage/ledger.json"))

    func start()   // DispatchSource sur le fichier, appelle onChange à chaque write
    func stop()
}
```

**Setup fichier de test :** Créer `~/.pixelvillage/` et un `ledger.json` minimal si absent.

**Critère de succès :** LedgerWatcher appelle `onChange` quand on modifie ledger.json manuellement (`echo '...' >> ~/.pixelvillage/ledger.json`).

---

### Task 3 — VillageEngine

**But :** Source of truth observable de l'état du village, rechargée à chaque tick du watcher.

```swift
@Observable
final class VillageEngine {
    private(set) var totalBits: Double = 0
    private(set) var pendingBits: Double = 0
    private(set) var agents: [String: AgentRecord] = [:]
    
    private let ledgerURL: URL
    private var watcher: LedgerWatcher
    
    init(ledgerURL: URL = ...)
    func start()       // démarre watcher, charge l'état initial
    func stop()
    private func reload()  // lit ledger.json, met à jour @Observable properties
}
```

**SwiftUI wiring :** Passé en `.environment(engine)` dans `NookApp.swift`.

**Critère de succès :** Modifier `ledger.json` → `engine.totalBits` se met à jour sans relancer l'app.

---

### Task 4 — VillageScene + TileMap + Camera

**But :** Scène SpriteKit affichant une grille pixel art navigable.

**`TileMap.swift` :**
- Grille logique 128×128, taille tile 32×32 pixels
- Au départ : parcelle centrale 20×20 (herbe), reste en fog (couleur gris-bleu uniforme)
- Chaque tile = `SKSpriteNode` coloré (placeholder tant qu'il n'y a pas d'assets)
  - Herbe : vert `#5A8F3C`
  - Fog : `#2A3040`
- Tente : node central sur la parcelle, couleur crème `#F5E6C8`, taille 2×2 tiles
- Méthode `updateUnlockedZones(totalBits:)` → révèle des tiles supplémentaires selon les milestones

**`Camera.swift` :**
- `SKCameraNode` attaché à la scène
- Pan : `NSPanGestureRecognizer` (drag souris)
- Zoom : `scrollWheel` event (override dans `SKView` ou `VillageScene`)
- Limites : ne peut pas aller au-delà des bords de la grille
- Zoom min/max : 0.5× – 3×

**`VillageScene.swift` :**
- `SKScene(size: CGSize(width: 128*32, height: 128*32))` = 4096×4096
- `scaleMode = .resizeFill`
- Contient : `TileMap` + `Camera` + `HUD`
- Reçoit `VillageEngine` en init, observe `totalBits` pour `updateUnlockedZones`

**Critère de succès :** La fenêtre s'ouvre, on voit une grille herbeuse 20×20 au centre, du fog autour, une tente, et on peut pan/zoom à la souris.

---

### Task 5 — HUD (Bits counter)

**But :** Overlay fixe qui affiche les Bits en temps réel.

**`HUD.swift` :**
- `SKNode` enfant de la caméra (reste fixe à l'écran)
- Coin supérieur gauche : `⬡ 0.0 Bits` en `SKLabelNode`
- Police : `Monaco` 14pt (monospace, pixel-art feel sans asset custom)
- Fond : rectangle semi-transparent noir arrondi
- Si `pendingBits > 0` au lancement : animation `+XXX Bits` qui monte et disparaît

**Intégration :** `VillageScene` observe `engine.totalBits` via `NotificationCenter` ou polling 1fps dans `update(_ currentTime:)`.

**Critère de succès :** Le compteur affiche les vrais Bits depuis ledger.json, se met à jour sans redémarrage.

---

### Task 6 — Kenney assets (optionnel, ne bloque pas les tâches précédentes)

**But :** Remplacer les placeholders colorés par de vrais sprites pixel art CC0.

**Actions :**
1. Télécharger Kenney Tiny Town depuis kenney.nl (CC0, gratuit)
2. Extraire les PNGs pertinents : herbe, chemin en terre, eau, tente, pierre
3. Créer `NookApp/Assets.xcassets/` avec un image set par tile
4. Dans `TileMap.swift` : remplacer `SKSpriteNode(color:size:)` par `SKSpriteNode(imageNamed:)`
5. Appliquer `SKTextureFilteringMode.nearest` sur chaque texture → rendu pixel perfect

**Critère de succès :** La grille affiche de vraies tiles Kenney, sans blur, pixel perfect.

---

## Ordre d'exécution recommandé

```
Task 1 (scaffold) → Task 2 (ledger) → Task 3 (engine) → Task 4 (scene) → Task 5 (HUD) → Task 6 (assets)
```

Tasks 5 et 6 peuvent se faire en parallèle après Task 4.

---

## Critères de succès globaux Phase 2

- [ ] `swift build` (daemon Phase 1) toujours vert
- [ ] `xcodebuild -project NookApp.xcodeproj -scheme NookApp build` vert
- [ ] Fenêtre s'ouvre avec scène SpriteKit visible
- [ ] Grille 20×20 herbe + fog + tente centrale
- [ ] Camera pan + zoom fonctionnels
- [ ] HUD affiche Bits depuis ledger.json
- [ ] Modifier ledger.json manuellement → HUD se met à jour en live
- [ ] (bonus) Tiles Kenney en rendu pixel perfect

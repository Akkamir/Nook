# Phase 6 — Persistance

**Objectif :** L'état du village survit aux relances. Les positions des NPCs et les zones débloquées sont sauvegardées dans `~/.pixelvillage/village.json`.

**Livrable :** Relancer l'app → les NPCs réapparaissent là où ils étaient, les zones révélées restent révélées.

---

## Ce qui est persisté

| Donnée | Pourquoi |
|---|---|
| Positions NPC (tileX, tileY par agent) | Éviter la respawn aléatoire |
| Zones débloquées (Set de strings) | Éviter de réanimer le fog déjà révélé |

**Hors scope :** position caméra (reset au centre à chaque lancement = UX normale).

---

## Format `~/.pixelvillage/village.json`

```json
{
  "npcPositions": {
    "Radion": { "tileX": 62, "tileY": 58 },
    "Coach":  { "tileX": 55, "tileY": 67 }
  },
  "revealedZones": ["foret", "lac"],
  "lastSaved": "2026-05-18T12:00:00Z"
}
```

---

## Architecture

```
VillagePersistence (singleton @MainActor)
  ├── load() → VillageState
  └── save(VillageState)

FogSystem
  └── init : charge revealedZones, révèle sans animation
  └── reveal() : sauvegarde après chaque déblocage

NPCManager
  └── sync() : utilise position sauvegardée si disponible

VillageScene
  └── willMove(from:) : sauvegarde positions NPC courantes
```

---

## Tâches

### Task 1 — VillagePersistence

**Fichier :** `Sources/NookApp/VillagePersistence.swift`

```swift
import Foundation

struct TilePosition: Codable {
    var tileX: Int
    var tileY: Int
}

struct VillageState: Codable {
    var npcPositions: [String: TilePosition]
    var revealedZones: [String]   // Array pour Codable simple (pas Set)
    var lastSaved: Date

    static var empty: VillageState {
        VillageState(npcPositions: [:], revealedZones: [], lastSaved: Date())
    }
}

@MainActor
final class VillagePersistence {
    static let shared = VillagePersistence()

    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() { ... }   // configure url + encoder/decoder iso8601

    func load() -> VillageState { ... }   // lit le fichier, retourne .empty si absent/invalide
    func save(_ state: VillageState) { ... }  // écrit atomiquement (tempfile + rename)
}
```

**Détails `save` :** écriture atomique — écrire dans un `.tmp`, puis `FileManager.moveItem` pour éviter la corruption.

**Critère de succès :** Sauvegarder puis relire → même état.

---

### Task 2 — FogSystem : persistance des zones

**Modifier :** `Sources/NookApp/FogSystem.swift`

**Changements dans `init()` :**
- Après avoir créé les 4 strips, charger `VillagePersistence.shared.load()`
- Pour chaque zone dans `state.revealedZones` → appeler `revealInstant(strip:id:)` (fade immédiat, alpha=0, sans animation)

**Nouvelle méthode `private func revealInstant(_ strip: SKSpriteNode, id: String)` :**
- `revealed.insert(id)`
- `strip.alpha = 0` (pas d'animation, déjà révélé)

**Modifier `reveal(_:id:threshold:totalBits:)` :** après l'insert, sauvegarder :
```swift
var state = VillagePersistence.shared.load()
state.revealedZones = Array(revealed)
state.lastSaved = Date()
VillagePersistence.shared.save(state)
```

**Critère de succès :** Débloquer une zone, relancer → zone toujours débloquée sans animation.

---

### Task 3 — NPCManager : positions persistées

**Modifier :** `Sources/NookApp/NPCManager.swift`

**Dans `sync()`, section Additions — remplacer `randomSpawnTile()` par :**
```swift
let (tileX, tileY) = savedTile(for: id) ?? randomSpawnTile()
```

**Nouvelle méthode `private func savedTile(for id: String) -> (Int, Int)?` :**
```swift
let state = VillagePersistence.shared.load()
guard let pos = state.npcPositions[id] else { return nil }
return (pos.tileX, pos.tileY)
```

**Nouvelle méthode `func currentPositions() -> [String: TilePosition]` :**
- Pour chaque `(id, sprite)` dans `sprites` :
  - Lire `sprite.position` (world coordinates)
  - Convertir en tile : `tileX = Int(sprite.position.x / TileMap.tileSize)`, idem Y
  - Retourner `[id: TilePosition(tileX:tileY:)]`

**Critère de succès :** Un NPC spawne à la même position après relance.

---

### Task 4 — VillageScene : save au quit

**Modifier :** `Sources/NookApp/VillageScene.swift`

**Dans `willMove(from:)`, après `villageCamera.detach()` :**
```swift
if let positions = npcManager?.currentPositions() {
    var state = VillagePersistence.shared.load()
    state.npcPositions = positions
    state.lastSaved = Date()
    VillagePersistence.shared.save(state)
}
```

**Critère de succès :** Quitter l'app → `village.json` contient les positions actuelles.

---

## Ordre d'exécution

Task 1 → Task 2 → Task 3 → Task 4

## Critères de succès globaux Phase 6

- [ ] Build vert
- [ ] `~/.pixelvillage/village.json` créé au premier lancement
- [ ] Relancer → NPCs aux mêmes positions
- [ ] Relancer → zones déjà débloquées restent révélées (pas d'animation)
- [ ] Pas de régression : fog, cycle jour/nuit, zoom, pan

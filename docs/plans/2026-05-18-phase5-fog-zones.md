# Phase 5 — Fog + Zones

**Objectif :** Tout ce qui dépasse la parcelle est recouvert d'une brume sombre. Les zones se révèlent progressivement selon les Bits accumulés, avec une animation de fondu.

**Livrable :** Au lancement, seule la parcelle 20×20 est visible. Le reste de la carte est recouvert d'un overlay sombre semi-transparent. Quand `totalBits` atteint les seuils, la zone correspondante se révèle (fade-out de 2 secondes).

---

## Approche technique

4 rectangles de brume couvrent les 4 bandes autour de la parcelle :

```
┌─────────────────────────── fogTop ───────────────────────────┐
│ fogLeft │        PARCELLE (visible)          │ fogRight       │
└────────────────────────── fogBottom ─────────────────────────┘
```

Coordonnées monde (tileSize=32, parcelleOriginX=Y=54, parcelleWidth=Height=20) :
- Parcelle world bounds : x∈[1728,2368], y∈[1728,2368]
- fogBottom : size=(4096,1728), position=(2048, 864)
- fogTop    : size=(4096,1728), position=(2048, 3232)
- fogLeft   : size=(1728, 640), position=(864, 2048)
- fogRight  : size=(1728, 640), position=(3232, 2048)

Quand une zone se débloque → fade alpha 0→0 sur le strip correspondant en 2s.

zPosition = 2 (au-dessus des tiles à z=0, en-dessous des NPCs à z=10).

---

## Seuils de déblocage

| Zone | Strip | Seuil Bits |
|---|---|---|
| Forêt (ouest) | fogLeft | 1 000 |
| Lac (sud) | fogBottom | 5 000 |
| Marché (est) | fogRight | 10 000 |
| Montagne (nord) | fogTop | 25 000 |

---

## Tâches

### Task 1 — FogSystem

**Fichier :** `Sources/NookApp/FogSystem.swift`

```swift
import SpriteKit

@MainActor
final class FogSystem: SKNode {
    // 4 fog strips
    private var fogBottom: SKSpriteNode!
    private var fogTop:    SKSpriteNode!
    private var fogLeft:   SKSpriteNode!
    private var fogRight:  SKSpriteNode!

    // Track which zones are already revealed (avoid re-animating)
    private var revealed: Set<String> = []

    override init() { ... }   // build the 4 strips
    required init?(coder: NSCoder) { fatalError() }

    func update(totalBits: Double) { ... }   // check thresholds, reveal zones
}
```

**Détails `init()` :**
- Couleur fog : `NSColor(red: 0.06, green: 0.08, blue: 0.16, alpha: 1.0)` (bleu-nuit profond)
- Alpha des nodes : `0.88`
- Chaque strip = `SKSpriteNode(color: fogColor, size: ...)` positionné selon les coordonnées ci-dessus
- Les 4 strips sont ajoutés comme enfants de `self`

**Détails `update(totalBits:)` :**
- Pour chaque seuil : si `totalBits >= seuil` ET `!revealed.contains(id)` → appeler `reveal(strip:id:)`
- `reveal(strip:id:)` : `revealed.insert(id)` + `strip.run(SKAction.fadeOut(withDuration: 2.0))`
- Seuils : fogLeft @ 1000, fogBottom @ 5000, fogRight @ 10000, fogTop @ 25000

**Critère de succès :** Instancier FogSystem dans la scène → 4 strips de brume visibles autour de la parcelle.

---

### Task 2 — Intégration VillageScene

**Modifier :** `Sources/NookApp/VillageScene.swift`

**Changements :**
1. Ajouter `private var fogSystem: FogSystem?`
2. Ajouter `private var lastTotalBits: Double = -1`
3. Dans `didMove(to:)`, après `tileMap.build()` :
   ```swift
   fogSystem = FogSystem()
   addChild(fogSystem!)
   ```
4. Dans `update(_ currentTime:)`, après la logique NPC :
   ```swift
   if let engine, engine.totalBits != lastTotalBits {
       fogSystem?.update(totalBits: engine.totalBits)
       lastTotalBits = engine.totalBits
   }
   ```

**Ne pas casser :** camera, tileMap, npcManager, lastAgentCount, initialZoomSet.

**Critère de succès :** Build vert, brume visible au lancement, parcelle dégagée.

---

## Ordre d'exécution

Task 1 → Task 2

## Critères de succès globaux Phase 5

- [ ] Build vert
- [ ] Parcelle visible, reste de la carte en brume sombre
- [ ] Tester : modifier `totalBits = 1500` dans ledger.json → fogLeft disparaît en 2s
- [ ] Pas de régression : NPC, HUD, cycle jour/nuit, pan/zoom

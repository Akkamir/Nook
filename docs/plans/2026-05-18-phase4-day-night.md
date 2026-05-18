# Phase 4 — Cycle jour/nuit

**Objectif :** La scène change de teinte en temps réel selon l'heure de la machine. Purement cosmétique, zéro gameplay — mais transforme le village d'un affichage statique en quelque chose qui vit.

**Livrable :** L'app affiche un overlay coloré sur la scène qui varie selon l'heure réelle :
- 6h–9h : lever de soleil (teinte dorée légère)
- 9h–18h : journée (transparent)
- 18h–21h : coucher de soleil (orangé)
- 21h–6h : nuit (bleu sombre, opacité ~50%)

Transitions douces via SwiftUI animation (30 secondes de fondu).

---

## Approche technique

Même logique que le HUD : overlay SwiftUI sur le SpriteView, pas de node SpriteKit.

```
VillageEngine (@Observable)
  └─ dayPhase: DayPhase   ← mis à jour toutes les 60s via DispatchSourceTimer

ContentView (SwiftUI ZStack)
  ├─ SpriteView
  ├─ Rectangle overlay (color + opacity from dayPhase)  ← NOUVEAU
  └─ HUD Bits
```

**Pourquoi SwiftUI et pas SpriteKit ?**
- Les enfants du SKCameraNode ont une taille relative au zoom → overlay qui change avec le zoom
- SwiftUI `Rectangle().allowsHitTesting(false)` est propre, stable, et `withAnimation` donne les fondus gratos

---

## Phases et couleurs

```swift
enum DayPhase {
    case sunrise  // 6h–9h
    case day      // 9h–18h
    case sunset   // 18h–21h
    case night    // 21h–6h
}
```

| Phase | Couleur | Opacité |
|---|---|---|
| sunrise | RGB(1.0, 0.75, 0.2) — ambre | 0.18 |
| day | n/a | 0.0 |
| sunset | RGB(1.0, 0.45, 0.1) — orangé | 0.22 |
| night | RGB(0.08, 0.08, 0.25) — bleu nuit | 0.52 |

---

## Tâches

### Task 1 — DayPhase

**Fichier :** `Sources/NookApp/DayPhase.swift`

```swift
import SwiftUI

enum DayPhase {
    case sunrise, day, sunset, night

    static func current() -> DayPhase {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<9:  return .sunrise
        case 9..<18: return .day
        case 18..<21: return .sunset
        default:     return .night
        }
    }

    var overlayColor: Color { ... }
    var overlayOpacity: Double { ... }
}
```

### Task 2 — VillageEngine : dayPhase + timer

**Modifier :** `Sources/NookApp/VillageEngine.swift`

Ajouter :
- `private(set) var dayPhase: DayPhase = DayPhase.current()`
- `private var dayNightTimer: DispatchSourceTimer?`
- Dans `start()` : lancer un timer DispatchSource qui appelle `updateDayPhase()` toutes les 60s
- `private func updateDayPhase()` : `dayPhase = DayPhase.current()`
- Dans `stop()` : annuler le timer

### Task 3 — ContentView : overlay

**Modifier :** `Sources/NookApp/ContentView.swift`

Dans le ZStack, entre SpriteView et HUD :
```swift
Rectangle()
    .fill(engine.dayPhase.overlayColor)
    .opacity(engine.dayPhase.overlayOpacity)
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .animation(.easeInOut(duration: 30), value: engine.dayPhase)
```

---

## Ordre d'exécution

Task 1 → Task 2 → Task 3

## Critères de succès

- [ ] Build vert
- [ ] Overlay visible selon l'heure réelle au lancement
- [ ] Modifier l'heure système → overlay change (ou tester en forçant une phase dans `current()`)
- [ ] Transition douce (30s) quand la phase change
- [ ] Pan, zoom, NPC, HUD Bits : aucune régression

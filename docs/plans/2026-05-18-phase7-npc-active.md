# Phase 7 — NPC États Actifs

**Objectif :** Détecter les sessions Claude Code actives et changer l'état visuel des NPCs en conséquence. Un NPC dont l'agent a une session ouverte cesse de se balader et pulse sur place (il "travaille").

**Livrable :** Ouvrir une session Claude Code sur un projet avec `.pixelvillage` → le NPC correspondant change de couleur (violet) et pulse. Fermer la session → il reprend sa balade.

---

## Détection des sessions actives

Claude Code écrit dans `~/.claude/projects/<encoded-path>/`. Les JSONL sont modifiés en temps réel.

**Encodage du path :** `/Users/mchau/Radion` → `-Users-mchau-Radion` (premier `/` supprimé, les `/` remplacés par `-`).

**Attribution via `.pixelvillage` :** fichier JSON `{ "agent": "Radion" }` dans le répertoire projet.

**Algorithme de détection :**
1. Lister `~/.claude/projects/`
2. Pour chaque dossier : vérifier si un `.jsonl` a été modifié dans les 5 dernières minutes
3. Si oui : décoder le path → chercher `.pixelvillage` → lire l'agent
4. Retourner `Set<String>` des agents actifs

---

## États visuels NPC

| État | Couleur body | Animation | Wander |
|---|---|---|---|
| idle | `#7EC8A4` (vert-menthe) | aucune | oui |
| working | `#6B7FD4` (violet-bleu) | pulse scale 0.9↔1.0 (0.5s) | non |

---

## Tâches

### Task 1 — SessionDetector

**Fichier :** `Sources/NookApp/SessionDetector.swift`

```swift
import Foundation

@MainActor
final class SessionDetector {
    private let fm = FileManager.default
    private let claudeProjectsURL: URL

    init() {
        claudeProjectsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    func detectActive() -> Set<String> { ... }
    private func hasRecentJSONL(in dir: URL, since cutoff: Date) -> Bool { ... }
    private func agentName(forProjectDir dir: URL) -> String? { ... }
}
```

**`detectActive()` :**
- cutoff = `Date().addingTimeInterval(-300)` (5 min)
- Liste `claudeProjectsURL`, itère chaque entrée
- Si `hasRecentJSONL(in: entry, since: cutoff)` : appelle `agentName(forProjectDir: entry)`
- Retourne le Set des noms non-nil

**`hasRecentJSONL(in:since:)` :**
- Liste le répertoire avec `.contentModificationDateKey`
- Retourne `true` si au moins un fichier `.jsonl` a `modificationDate > cutoff`

**`agentName(forProjectDir:)` :**
- `dirName = dir.lastPathComponent` (ex: `-Users-mchau-Radion`)
- `projectPath = "/" + String(dirName.dropFirst()).replacingOccurrences(of: "-", with: "/")`
- Cherche `<projectPath>/.pixelvillage`
- Lit JSON `{ "agent": "Radion" }` → retourne le nom, nil si absent/invalide

---

### Task 2 — VillageEngine : activeSessions + timer

**Modifier :** `Sources/NookApp/VillageEngine.swift`

Ajouter :
- `private(set) var activeSessions: Set<String> = []`
- `private var sessionTimer: DispatchSourceTimer?`
- `private let sessionDetector = SessionDetector()`

Dans `start()`, après `startDayNightTimer()` :
```swift
startSessionTimer()
```

Nouvelle méthode :
```swift
private func startSessionTimer() {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: .seconds(30))
    timer.setEventHandler { [weak self] in
        self?.activeSessions = self?.sessionDetector.detectActive() ?? []
    }
    timer.resume()
    sessionTimer = timer
}
```

Dans `stop()` :
```swift
sessionTimer?.cancel()
sessionTimer = nil
```

---

### Task 3 — NPCSprite : setActive

**Modifier :** `Sources/NookApp/NPCSprite.swift`

Ajouter une méthode publique :
```swift
func setActive(_ isActive: Bool) {
    if isActive {
        body.color = NSColor(red: 0.42, green: 0.50, blue: 0.83, alpha: 1.0)  // #6B80D4
        guard action(forKey: "pulse") == nil else { return }
        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 0.85, duration: 0.5),
            SKAction.scale(to: 1.0,  duration: 0.5)
        ]))
        run(pulse, withKey: "pulse")
    } else {
        body.color = NSColor(red: 0.494, green: 0.784, blue: 0.643, alpha: 1.0)  // #7EC8A4
        removeAction(forKey: "pulse")
        setScale(1.0)
    }
}
```

---

### Task 4 — NPCManager : syncActiveStates + VillageScene wiring

**Modifier :** `Sources/NookApp/NPCManager.swift`

Ajouter :
```swift
private var activeAgents: Set<String> = []

func syncActiveStates(_ active: Set<String>) {
    guard active != activeAgents else { return }
    activeAgents = active
    for (id, sprite) in sprites {
        let isActive = active.contains(id)
        sprite.setActive(isActive)
        if isActive {
            wanders[id]?.stop()
        } else {
            wanders[id]?.start()
        }
    }
}
```

**Modifier :** `Sources/NookApp/VillageScene.swift`

Ajouter propriété :
```swift
private var lastActiveSessions: Set<String> = []
```

Dans `update(_ currentTime:)`, après la logique fog :
```swift
if let engine, engine.activeSessions != lastActiveSessions {
    npcManager?.syncActiveStates(engine.activeSessions)
    lastActiveSessions = engine.activeSessions
}
```

---

## Ordre d'exécution

Task 1 → Task 2 → Task 3 → Task 4

## Critères de succès globaux Phase 7

- [ ] Build vert
- [ ] Session active détectée dans `detectActive()` (test : modifier un JSONL manuellement)
- [ ] NPC actif : violet + pulse, pas de wander
- [ ] NPC inactif : vert + wander reprend
- [ ] Pas de régression : fog, persistance, zoom/pan

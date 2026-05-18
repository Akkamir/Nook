# Phase 8 — Claude Hooks Live Session Detection

**Objectif :** remplacer la détection "session active" basée uniquement sur l'âge des JSONL par une détection live via Claude Code hooks, tout en gardant le scan JSONL comme fallback.

**Livrable :** ouvrir une session Claude Code dans un projet avec `.pixelvillage` rend le NPC actif dès `SessionStart`; fermer/quitter la session rend le NPC inactif dès `SessionEnd`, sans attendre l'expiration du seuil de 5 minutes.

---

## Motivation

La Phase 7 détecte les sessions actives en scannant `~/.claude/projects/` et en considérant actif tout projet dont un `.jsonl` a été modifié dans les 5 dernières minutes. Cette approche est simple mais ne sait pas distinguer :

- une vraie session Claude encore ouverte ;
- une session terminée récemment ;
- un fichier JSONL modifié par reprise, `/clear`, sous-agent ou outil externe.

Pixel Agents évite ce problème en combinant deux sources :

1. des hooks Claude Code pour les événements de lifecycle (`SessionStart`, `SessionEnd`, `Stop`, `Notification`, etc.) ;
2. un polling JSONL pour le contenu détaillé et le fallback.

Nook doit suivre ce modèle minimalement : hooks pour le lifecycle, JSONL pour le fallback.

---

## Architecture

### Vue d'ensemble

Nook démarre un petit serveur HTTP local écoutant uniquement sur `127.0.0.1`. Au démarrage, il écrit une configuration locale dans :

```text
~/.pixelvillage/hook-server.json
```

Le fichier contient le port et un token aléatoire de session. Nook installe aussi un script hook dans :

```text
~/.pixelvillage/hooks/claude-hook.py
```

Claude Code appelle ce script pour les événements configurés. Le script lit le JSON d'événement sur `stdin`, lit `hook-server.json`, puis POST l'événement au serveur local Nook. Si Nook n'est pas lancé, le script échoue silencieusement pour ne pas perturber Claude Code.

### Flux

```text
Claude Code event
  -> ~/.pixelvillage/hooks/claude-hook.py
  -> POST http://127.0.0.1:<port>/claude-hook
  -> ClaudeHookServer
  -> SessionDetector live state
  -> VillageEngine.activeSessions
  -> NPCManager.syncActiveStates
```

---

## Hooks Claude à installer

Nook installe des entrées dans `~/.claude/settings.json` pour :

- `SessionStart`
- `SessionEnd`
- `Stop`
- `Notification`
- `PreToolUse`
- `PostToolUse`

Les événements strictement nécessaires au lifecycle sont `SessionStart` et `SessionEnd`. Les autres servent à confirmer l'activité récente et à préparer des statuts plus riches plus tard.

Chaque entrée ajoutée par Nook doit être identifiable par le chemin `~/.pixelvillage/hooks/claude-hook.py`. L'installation est idempotente :

- conserver toutes les entrées existantes ;
- supprimer uniquement les anciennes entrées Nook avant d'ajouter les nouvelles ;
- ne jamais supprimer les hooks d'autres outils ou les hooks personnels existants.

Le fichier actuel `~/.claude/settings.json` contient déjà des hooks `SessionStart` et `PreCompact`; ils doivent être préservés.

---

## Composants

### `ClaudeHookServer.swift`

Responsabilités :

- ouvrir un serveur HTTP local sur `127.0.0.1` et un port libre ;
- générer un token de session ;
- écrire `~/.pixelvillage/hook-server.json` avec permissions utilisateur ;
- accepter uniquement `POST /claude-hook` ;
- vérifier le header `Authorization: Bearer <token>` ;
- parser le JSON en `ClaudeHookEvent` ;
- appeler un callback `onEvent`.

Le serveur ne doit pas exposer d'interface réseau externe.

### `ClaudeHookInstaller.swift`

Responsabilités :

- écrire `~/.pixelvillage/hooks/claude-hook.py` ;
- créer les répertoires nécessaires ;
- rendre le script exécutable ;
- lire `~/.claude/settings.json` si présent ;
- fusionner les entrées hooks Nook de façon idempotente ;
- écrire les settings via fichier temporaire puis rename atomique.

Le script hook Python :

- lit `stdin` ;
- parse le JSON ;
- lit `~/.pixelvillage/hook-server.json` ;
- POST vers le serveur local avec timeout court ;
- ignore toutes les erreurs et sort avec code `0`.

### `SessionDetector.swift`

Responsabilités existantes :

- scanner `~/.claude/projects/` ;
- mapper un dossier Claude vers un projet local ;
- lire `<project>/.pixelvillage` pour obtenir le nom d'agent.

Nouvelles responsabilités :

- conserver un état live `hookActiveAgents: Set<String>` ;
- traiter les `ClaudeHookEvent` reçus ;
- mapper `transcript_path` ou `cwd` vers l'agent ;
- donner priorité aux hooks récents ;
- conserver le scan JSONL comme fallback.

Règle de combinaison :

```text
detectActive() = hookActiveAgents union jsonlFallbackActiveAgents
```

Pour éviter qu'une session fermée reste active à cause du fallback JSONL, un `SessionEnd` récent ajoute aussi l'agent à une courte liste `recentlyEndedAgents`. Pendant 5 minutes, ces agents sont exclus du fallback JSONL sauf nouveau `SessionStart`.

### `VillageEngine.swift`

Responsabilités :

- démarrer `ClaudeHookServer` dans `start()` ;
- installer les hooks via `ClaudeHookInstaller` après démarrage serveur ;
- connecter `server.onEvent` à `sessionDetector.handleHookEvent(_:)` ;
- garder le timer actuel pour recalculer `activeSessions` périodiquement ;
- mettre à jour `activeSessions` immédiatement quand un hook modifie l'état ;
- arrêter le serveur dans `stop()`.

---

## Mapping événement -> agent

Ordre de résolution :

1. si l'événement contient `transcript_path`, prendre son dossier parent comme dossier Claude projet ;
2. sinon si l'événement contient `cwd`, encoder ce chemin comme Claude Code encode les dossiers projet ;
3. sinon si `session_id` correspond à un fichier JSONL connu, utiliser ce fichier ;
4. sinon ignorer l'événement.

Le dossier Claude projet est ensuite décodé vers le projet local, puis Nook lit :

```text
<project>/.pixelvillage
```

Format attendu :

```json
{ "agent": "Radion" }
```

Si le fichier manque ou est invalide, l'événement est ignoré.

---

## Gestion d'état

`SessionStart` :

- résoudre l'agent ;
- supprimer l'agent de `recentlyEndedAgents` ;
- ajouter l'agent à `hookActiveAgents` ;
- publier immédiatement `activeSessions`.

`SessionEnd` :

- résoudre l'agent ;
- supprimer l'agent de `hookActiveAgents` ;
- ajouter l'agent à `recentlyEndedAgents` avec timestamp ;
- publier immédiatement `activeSessions`.

`PreToolUse`, `PostToolUse`, `Stop`, `Notification` :

- résoudre l'agent si possible ;
- si l'agent n'est pas récemment terminé, le garder actif ou rafraîchir son timestamp d'activité ;
- ne pas transformer `Stop` seul en inactif, car `Stop` signifie souvent fin de tour et attente utilisateur, pas fermeture de session.

---

## Erreurs et sécurité

- Si `~/.claude/settings.json` est invalide, ne pas écraser le fichier. Logguer et désactiver l'installation hooks.
- Si le port HTTP ne peut pas être ouvert, conserver uniquement le fallback JSONL.
- Si le hook script ne peut pas joindre Nook, il sort quand même avec code `0`.
- Le token dans `hook-server.json` change à chaque lancement de Nook.
- Le serveur bind uniquement `127.0.0.1`.
- Les hooks Nook sont supprimables en retirant les entrées contenant `.pixelvillage/hooks/claude-hook.py`.

---

## Tests et vérification

### Tests ciblés

- `ClaudeHookInstaller` sur settings temporaire :
  - préserve les hooks existants ;
  - ajoute les hooks Nook ;
  - reste idempotent après deux installations.
- `SessionDetector` :
  - `SessionStart` active un agent ;
  - `SessionEnd` désactive un agent ;
  - `recentlyEndedAgents` bloque le fallback JSONL.

### Vérification manuelle

- lancer Nook ;
- vérifier que `~/.pixelvillage/hook-server.json` existe ;
- vérifier que `~/.pixelvillage/hooks/claude-hook.py` existe et est exécutable ;
- ouvrir une session Claude dans un projet avec `.pixelvillage` ;
- observer le NPC devenir actif rapidement ;
- quitter la session Claude ;
- observer le NPC redevenir inactif rapidement.

### Build

```bash
xcodebuild -project NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

---

## Critères de succès

- [ ] Build vert.
- [ ] Hooks installés sans supprimer les hooks existants.
- [ ] Serveur local démarre et refuse les requêtes sans token.
- [ ] `SessionStart` active le bon NPC sans attendre le scan 30s.
- [ ] `SessionEnd` désactive le bon NPC sans attendre 5 minutes.
- [ ] Le fallback JSONL continue de fonctionner si les hooks sont absents.
- [ ] Aucun crash Claude Code si Nook n'est pas lancé.

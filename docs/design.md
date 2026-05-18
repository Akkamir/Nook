# Nook — Design Document

> App Mac standalone, style Stardew Valley / Animal Crossing.
> Les tokens Claude Code sont la currency du village.
> Le village grandit et vit pendant que tes agents tournent.

---

## Stack technique

- **App** : Swift + SpriteKit (natif Mac, léger ~30MB)
- **Data source** : lecture JSONL transcripts `~/.claude/projects/` (observationnel, sans toucher à Claude Code)
- **Persistence** : JSON local
- **Rendu** : grille top-down 32×32px, pixel art, `SKTextureFilteringMode.nearest`

---

## Architecture

```
Claude Watcher  →  Village Engine  →  Village App (SpriteKit)
(JSONL parser)     (état, économie)   (rendu, gameplay)
```

---

## Économie : les Bits

### Source primaire — Claude Code (daemon arrière-plan)
Le daemon tourne en permanence via macOS LaunchAgent, même app fermée.
Il surveille `~/.claude/projects/` via FSEvents et parse les JSONL en temps réel.

| Type de token | Conversion |
|---|---|
| Input tokens | 1 000 = 5 Bits |
| Output tokens | 1 000 = 15 Bits |

Attribution aux PNJs via fichier `.pixelvillage` dans le répertoire du projet :
```json
{ "agent": "Radion" }
```
Sans ce fichier, les tokens vont dans le pool global (Bits oui, bond non).

Ledger local : `~/.pixelvillage/ledger.json`
`pending_bits` = Bits gagnés depuis la dernière ouverture → animation au lancement.

### Source secondaire — Farming in-game (~20% max des revenus quotidiens)
Les récoltes donnent uniquement des Bits, pas de craft.

| Culture | Temps de pousse | Rendement |
|---|---|---|
| Herbe cristal | 1h | 15 Bits |
| Champignon pixel | 4h | 60 Bits |
| Fleur de code | 8h | 150 Bits |
| Arbre à données | 24h | 400 Bits |

Arbres fruitiers : poussent une fois, donnent des récoltes périodiques sans replanter.

Autres sources in-game :
- **Pêche** (lac débloqué) — 1x/heure, 5-50 Bits aléatoires
- **Cueillette** (forêt débloquée) — items aléatoires sur la carte, petits Bits bonus

### Règle d'équilibre
```
Session intense (50k tokens)  →  ~500 Bits
Journée de farming active      →  ~80–120 Bits
```
Claude Code reste toujours la source principale.

---

## Sections à définir

- [x] 1. Monde & zones
- [x] 2. Contenu — bâtiments, décos, tiers
- [x] 3. PNJs
- [x] 4. Courbe de progression
- [x] 5. Économie complète & farming
- [x] 6. Boucle d'interaction & window management
- [x] 7. Ce qui rend le village vivant (météo, cycles, événements)
- [x] 8. Onboarding
- [x] 9. Structure Swift & fichiers

---

## 1. Monde & zones

**Structure générale :**
Grande carte (ex. 128×128 tiles). La majorité est vide/brumée au départ. Les zones se révèlent et se peuplent au fur et à mesure des Bits dépensés.

**Carte des zones :**
```
         [ Montagne ]
              ↑
[ Forêt ] ← [ TA PARCELLE ] → [ Marché ]
              ↓
           [ Lac ]
              ↓
         [ Ruines ]
```

**Déblocages par milestone de Bits dépensés :**
| Milestone | Zone débloquée |
|---|---|
| 0 | Ta parcelle centrale (20×20 tiles) |
| 1 000 Bits | Forêt (ouest) |
| 5 000 Bits | Lac (nord) |
| 10 000 Bits | Marché (est) |
| 25 000 Bits | Montagne (sud) |
| 100 000 Bits | Ruines (zone spéciale) |

**Ta parcelle centrale — upgrades de la maison :**
La maison évolue indépendamment des zones. C'est le cœur émotionnel du jeu.

| Niveau | Nom | Coût | Ce que ça change |
|---|---|---|---|
| 0 | Tente | gratuit | Point de départ |
| 1 | Cabane | 500 Bits | Maison basique, 1 pièce |
| 2 | Maison | 2 000 Bits | 2 pièces, intérieur furnissable |
| 3 | Villa | 10 000 Bits | Grande maison, plusieurs pièces |
| 4 | Manoir | 50 000 Bits | Endgame, toit-terrasse |

**Améliorations de la parcelle (indépendantes de la maison) :**
- Défricher (rochers, herbes sauvages) — coût faible
- Chemins (pierre, bois, brique, terre)
- Parterres de fleurs / jardin
- Clôtures et portails
- Points d'eau (fontaine, mare)
- Éclairage (lanternes, réverbères)

---

## 2. Contenu — bâtiments, décos, nature

### Bâtiments fonctionnels
Présents dès le départ, gratuits — c'est le lien core avec Claude Code.
Les Bits servent uniquement à customiser et décorer, jamais à débloquer des fonctions.

| Bâtiment | Fonction |
|---|---|
| Atelier | Crafter des décos via recettes |
| Bibliothèque | Archive tes sessions (stats, tokens/jour, projets) |
| Tour de guet | Affiche tes agents Claude actifs en temps réel |
| Marché | Achète des items avec des Bits |

### Décos (cosmétiques)
Organisées en tiers de rareté et de coût.

| Tier | Exemples | Coût |
|---|---|---|
| Commun | Bancs, lanternes, panneaux, clôtures | 10–50 Bits |
| Rare | Fontaines, statues, mobilier élaboré | 100–500 Bits |
| Épique | Totems animés, objets avec effets visuels | 1 000–5 000 Bits |
| Légendaire | Items uniques débloqués par milestones | Milestones uniquement |

Les panneaux sont **personnalisables** — tu peux y écrire du texte (nom de projet, citation, etc.).

### Nature
Pousse avec le temps réel entre les sessions.

| Élément | Comportement |
|---|---|
| Arbres | Plantés petits, grandissent sur 3–5 sessions |
| Fleurs | Instantanées, se fanent si non arrosées |
| Cultures | Plantées, récoltées après N sessions (donne des Bits bonus) |
| Buissons | Permanents une fois placés |

---

## 3. PNJs

### Principe central
Les PNJs représentent des **relations de travail durables**, pas des fenêtres terminal.
Pas de PNJ générique par session — pas d'attachement possible.

### Système de slots
Max 6 PNJs simultanés. Les slots se débloquent avec la progression de la maison.

| Niveau maison | Slots |
|---|---|
| Tente | 2 |
| Cabane | 3 |
| Maison | 4 |
| Villa | 5 |
| Manoir | 6 (max) |

Pour inviter un nouveau PNJ quand tous les slots sont pris : retirer un existant (son histoire s'archive dans la Bibliothèque, son plot se libère).

### Personnalité émergente (pas de customisation upfront)
La personnalité n'est pas choisie — elle émerge du travail réel accompli avec le PNJ.
À la création : un seul champ, le nom. Tout le reste arrive tout seul.

| Pattern de travail observé | Trait visuel qui émerge |
|---|---|
| Sessions longues, gros output | "Deep thinker" — posture calme, grosses lunettes |
| Sessions courtes et fréquentes | Énergique — beaucoup de mouvement, multitâche |
| Travail principalement la nuit | "Night owl" — café, lampe de bureau, ambiance sombre |
| Projets de code intensifs | Accessoires dev — clavier mécanique, écrans multiples |
| Mix varié de projets | "Généraliste" — bureau fourni, polyvalent |
| Bond 5 atteint | Transformation majeure — tenue distinctive, propre maison |

**Renommer un PNJ :**
- Coûte 500 Bits (délibéré, pas anodin)
- Ou gratuit au Bond 3 — la relation est assez établie

### Multi-session par PNJ
Un PNJ peut gérer plusieurs sessions Claude Code en parallèle.
Sa charge se voit visuellement :

| Sessions actives | Apparence |
|---|---|
| 1 | Tape tranquillement |
| 2 | Deux écrans, animation plus rapide |
| 3+ | Bureau chargé, indicateur "deep focus" |

### Agents-PNJs (créés par toi)
Tu crées un agent en lui donnant un **nom libre + description**. Ce nom devient un PNJ permanent dans le village, indépendamment des sessions ouvertes.

**Cycle de vie :**
- Agent actif (session Claude Code ouverte) → PNJ animé à son bureau (tape, lit, réfléchit)
- Agent inactif → PNJ qui se balade dans le village

**Histoire accumulée par PNJ :**
- Total de tokens traités avec cet agent spécifiquement
- Durée cumulée des sessions
- Projets sur lesquels il a travaillé (déduit du répertoire Claude Code)

**Bond — jauge de relation basée sur les tokens**
La relation grandit selon les tokens dépensés *avec ce PNJ spécifiquement*, pas le nombre de sessions.

| Bond | Seuil tokens | Ce qui se débloque |
|---|---|---|
| 1 | 0 | État initial |
| 2 | 10 000 tokens | Nouvelles animations, dialogue enrichi |
| 3 | 50 000 tokens | Bureau qui se décore automatiquement |
| 4 | 200 000 tokens | Notifications stylisées ("messages" du PNJ) |
| 5 | 1 000 000 tokens | Sa propre maison dans le village |

Un PNJ peu utilisé reste à Bond 1 et n'évolue pas. L'attachement est proportionnel au travail réel accompli ensemble.

### PNJs du village (indépendants)
Apparaissent quand tu débloques des zones. Donnent vie au monde sans interférer avec tes agents.

| PNJ | Lié à | Rôle |
|---|---|---|
| Le forgeron | Atelier | Propose des recettes de craft |
| La bibliothécaire | Bibliothèque | Montre tes stats de sessions |
| Le marchand | Marché | Passe 1x/jour avec des items rares |
| L'explorateur | Nouvelles zones | Apparaît quand une zone se débloque |

---

## 6. Boucle d'interaction & window management

### Paradigme central
**Le village EST ton desktop.** Pas un fond statique — un monde vivant en permanence.
Les fenêtres terminal flottent dessus comme sur un vrai bureau macOS.
Le village ne se met jamais en pause, ne s'assombrit jamais derrière les fenêtres.

```
┌─────────────────────────────────────────────────────┐
│  🌳    🏠 Village    🌿         🌊                  │
│     ┌──────────────────┐   ┌──────────────┐   🌳   │
│  🧙 │ Radion > claude  │   │ Coach >      │        │
│     │ $ working...     │   │ $ thinking.. │  🦆    │
│  🌿 │                  │   │              │        │
│     └──────────────────┘   └──────────────┘   🌸  │
│  🌳      🏪          🌿        🧑‍💻              🌿  │
└─────────────────────────────────────────────────────┘
```

### Fenêtres terminal
- `NSPanel` flottants avec `SwiftTerm` embarqué
- Draggables, resizables, stackables librement sur le village
- Bordure et barre de titre stylisées pixel art
- Transparence légère optionnelle pour voir le village en dessous
- Le PNJ associé continue de s'animer dans le village pendant que sa fenêtre est ouverte

### Gestion des sessions
**Lancer depuis l'app** — clic sur un PNJ ou bouton `+` → nouvelle session Claude Code spawne, fenêtre terminal s'ouvre immédiatement.

**Sync externe** — si une session Claude Code est lancée dans un terminal externe, l'app détecte via JSONL et propose de l'attacher à un PNJ existant.

### Barre de sessions (pixel art, bas d'écran)
```
[ 🧙 Radion ● ] [ 🔬 Coach ● ] [ + nouvelle session ]
```
- Point vert = session active
- Clic = focus sur la fenêtre de ce PNJ
- Drag = réordonner

### Boucle pendant qu'un agent tourne
1. Animation Bits gagnés au lancement
2. Cultures mûres signalées
3. Actions disponibles en parallèle des terminaux ouverts :
   - Récolter et replanter
   - Placer/déplacer des éléments (mode build — clic item → suit curseur → clic pour poser)
   - Acheter au marché
   - Interagir avec les PNJs (stats, dialogue)
   - Pêche / cueillette dans les zones débloquées

---

## 7. Ce qui rend le village vivant

### Cycle jour/nuit
Synchronisé sur l'heure réelle de la machine.

| Heure | Ambiance |
|---|---|
| 6h–9h | Lever de soleil, lumière dorée, PNJs qui arrivent à leur bureau |
| 9h–18h | Journée, pleine luminosité |
| 18h–21h | Coucher de soleil, teintes orangées |
| 21h–6h | Nuit, lanternes allumées, PNJs rentrent chez eux (sauf si session active) |

Un PNJ avec une session active reste éveillé et à son bureau même la nuit.

### Météo
Aléatoire, change chaque vrai jour. Purement cosmétique sauf effets sur cultures.

| Météo | Effet |
|---|---|
| Ensoleillé | Aucun bonus |
| Nuageux | Aucun bonus |
| Pluie | Cultures poussent 30% plus vite |
| Orage | Animation spéciale sur PNJs actifs, éclairs sur la carte |
| Brouillard | Ambiance rare, visibilité réduite aux bords de carte |

### Saisons
Synchronisées sur les vraies saisons de l'année (hémisphère nord).

| Saison | Palette | Spécificités |
|---|---|---|
| Printemps (mars–mai) | Verts tendres, fleurs roses | Fleurs sauvages apparaissent partout |
| Été (juin–août) | Couleurs vives, ciel bleu | Journées longues, cultures poussent plus vite |
| Automne (sept–nov) | Oranges, rouges, dorés | Feuilles qui tombent, ambiance chaleureuse |
| Hiver (déc–fév) | Blanc, bleu nuit, neige | Neige sur les toits, feux dans les maisons |

### Événements rares
Déclenchés par milestones ou calendrier réel.

| Événement | Déclencheur |
|---|---|
| Fête du village | Premier PNJ atteignant Bond 5 |
| Feu d'artifice | 1 000 000 tokens traités cumulés |
| Marchand spécial | 1x par mois, items introuvables ailleurs |
| Nouvel An pixel | 1er janvier, animation globale du village |
| Anniversaire d'un PNJ | Date de création du PNJ, chaque année |

---

## 8. Onboarding

Objectif : en moins de 3 minutes, le joueur a son premier PNJ, comprend la mécanique, et a gagné ses premiers Bits. Zéro tutorial verbeux.

**Étape 1 — L'arrivée (30s)**
Parcelle vide, herbe fraîche, ciel de printemps. Une lettre animée tombe du ciel :
*"Bienvenue dans ton village. Il grandira avec ton travail."*

**Étape 2 — Premier PNJ (1 min)**
Un seul champ : *"Comment s'appelle ton premier agent ?"*
Pas de choix de personnalité — elle émergera du travail. Le PNJ apparaît, se balade, s'installe à un bureau.

**Étape 3 — Première session (1 min)**
Tooltip discret : *"Lance Claude Code avec cet agent pour gagner tes premiers Bits."*
Bouton direct si Claude Code est installé. Premiers tokens → animation de Bits → mécanique comprise sans explication.

**Étape 4 — Première plante (30s)**
Une graine offerte gratuitement. Clic sur le sol → plantée.
*"Elle sera prête dans 1h."* C'est tout.

---

## 9. Structure Swift & fichiers

```
Nook/
├── App/
│   ├── NookApp.swift                  — entry point, AppDelegate
│   └── WindowManager.swift            — gestion NSPanel terminaux flottants
│
├── Daemon/                            — LaunchAgent séparé (tourne en arrière-plan)
│   ├── ClaudeWatcher.swift            — FSEvents sur ~/.claude/projects/
│   ├── TranscriptParser.swift         — extraction tokens input/output des JSONL
│   ├── AgentAttributor.swift          — lecture .pixelvillage, attribution aux PNJs
│   └── Ledger.swift                   — écriture ~/.pixelvillage/ledger.json
│
├── Engine/
│   ├── VillageEngine.swift            — état global du village, source of truth
│   ├── Economy.swift                  — conversion tokens→Bits, farming, pending_bits
│   ├── PersonalityEngine.swift        — calcul traits émergents depuis patterns d'usage
│   ├── ProgressionEngine.swift        — milestones, déblocages zones, upgrades maison
│   └── Persistence.swift             — save/load JSON local
│
├── Game/
│   ├── VillageScene.swift             — scène SpriteKit principale
│   ├── TileMap.swift                  — grille 128×128, placement, zones
│   ├── BuildSystem.swift              — mode build, place/déplace/supprime
│   ├── Camera.swift                   — pan, zoom
│   ├── WeatherSystem.swift            — météo, saisons, cycle jour/nuit
│   └── EventSystem.swift             — événements rares, fêtes, milestones
│
├── NPCs/
│   ├── NPCManager.swift               — slots, cycle de vie, bond tracking
│   ├── NPCBehavior.swift              — routines, animations selon état (actif/idle/nuit)
│   └── NPCRenderer.swift             — sprite selection selon traits émergents
│
├── Terminal/
│   ├── TerminalPanel.swift            — NSPanel + SwiftTerm, pixel art frame
│   ├── SessionManager.swift           — spawn/attach sessions Claude Code
│   └── SessionBar.swift              — barre de sessions bas d'écran
│
├── Models/
│   ├── VillageState.swift
│   ├── NPCModel.swift                 — nom, bond, tokens cumulés, traits émergents
│   ├── TileType.swift
│   ├── BuildingType.swift
│   └── CropType.swift
│
└── Assets/
    └── Assets.xcassets                — sprites, tiles, pixel art
```

**Dépendance externe :**
- `SwiftTerm` — émulateur terminal Swift open source

**Données persistées :**
- `~/.pixelvillage/ledger.json` — Bits, tokens par PNJ, pending_bits
- `~/.pixelvillage/village.json` — état complet du village (tiles, bâtiments, PNJs, cultures)

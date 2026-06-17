# Économie de Nook

## Vue d'ensemble

Nook est un idle-clicker ancré dans l'utilisation réelle de Claude Code. Les **bits** sont la monnaie unique du jeu — ils naissent des tokens brûlés lors de sessions Claude, s'amplifient via des upgrades achetées dans le shop, et se dépensent pour débloquer de nouvelles mécaniques. L'économie repose sur trois sources de revenus distinctes et un système d'upgrades additif.

---

## 1. Source primaire — Les tokens Claude

### Comment les bits sont générés

Le **daemon** (`NookDaemon`) surveille en continu les sessions Claude Code. À chaque événement de tokens (fin d'un appel API), il calcule les bits correspondants et les écrit dans `~/.pixelvillage/ledger.json`.

#### Formule de conversion

Les tokens sont pondérés selon leur coût relatif (tarification Sonnet 4.6) :

```
tokens_pondérés = input × 1.0 + output × 5.0 + cache_write × 1.25
bits = tokens_pondérés / 1000 × 5
```

| Type de token | Poids | Ratio vs input | Note                                        |
|--------------|-------|----------------|---------------------------------------------|
| Input        | 1.0   | ×1             |                                             |
| Output       | 5.0   | ×5             |                                             |
| Cache write  | 1.25  | ×1.25          | coût actif, non récurrent                   |
| Cache read   | 0.0   | —              | exclu : accumulation quadratique subagents  |

**Exemples de gains par session :**

| Session | Input | Output | Cache R/W | Bits gagnés |
|---------|-------|--------|-----------|-------------|
| Légère  | 5 000 | 2 000  | —         | ~75 bits    |
| Standard| 20 000| 8 000  | 5k/10k    | ~336 bits   |
| Intensive| 50 000| 20 000| 20k/80k  | ~915 bits   |

### Où atterrissent ces bits

Les bits bruts du daemon vont dans `AgentRecord.totalBits` dans le ledger. L'app les lit en lecture seule — **elle n'écrit jamais dans le ledger**. `totalBits` ne diminue jamais : c'est un compteur cumulatif de toute la carrière du NPC.

### Bond — la progression de la relation

En parallèle, les tokens alimentent le **bond** (0–20), une mesure de la relation entre l'utilisateur et le NPC. Le bond utilise les mêmes tokens pondérés :

| Bond | Tokens pondérés nécessaires |
|------|----------------------------|
| 1    | 0                          |
| 2    | 400 000                    |
| 3    | 667 240                    |
| 4    | 1 113 040                  |
| 5    | 1 856 640                  |
| 6    | 3 097 040                  |
| 7    | 5 166 200                  |
| 8    | 8 617 720                  |
| 10   | 23 979 360                 |
| 20   | 4 000 000 000              |

Le bond est utilisé par le **Bond Dividend** (voir section 3) et influence les discours du NPC.

---

## 2. Formule des bits disponibles

```
availableBits = totalBits + bonusAccumulated + trickleBitsAccumulated − spentBits
```

| Composant               | Source              | Varie comment              |
|-------------------------|---------------------|---------------------------|
| `totalBits`             | Daemon / ledger     | Croît avec chaque session |
| `bonusAccumulated`      | Multiplicateurs     | Croît à chaque event daemon|
| `trickleBitsAccumulated`| Bit Trickle         | Croît toutes les 10s      |
| `spentBits`             | Achats dans le shop | Augmente à chaque achat   |

**Le HUD** affiche `totalAvailableBits` = somme des `availableBits` de tous les NPCs.

---

## 3. Les trois upgrades du Shop

### 3.1 Bit Multiplier

Le Bit Multiplier amplifie le bonus que l'on reçoit sur chaque bit gagné via le daemon.

**Mécanique :** Quand le daemon enregistre un événement de `X bits` pour un agent :
```
bonus_crédité = X × (effectiveMultiplier − 1.0)
bonusAccumulated += bonus_crédité
```
Le multiplicateur s'applique aux **nouveaux gains uniquement** — pas rétroactivement au stock de `totalBits` existant (voir section 4 sur le `bonusAccumulated`).

**Niveaux et coûts :**

| Niveau | Coût       | Multiplicateur | Bonus par niveau |
|--------|-----------|----------------|-----------------|
| L1     | 50 bits   | +0.25          | +25%            |
| L2     | 90 bits   | +0.50          | +25%            |
| L3     | 162 bits  | +0.75          | +25%            |
| L4     | 292 bits  | +1.00 (+100%)  | +25%            |
| L5     | 525 bits  | +1.25          | +25%            |
| L6     | 945 bits  | +1.50          | +25%            |
| L7     | 1 701 bits| +1.75          | +25%            |
| Ln     | `50 × 1.8^(n−1)` | `+n × 0.25` | —         |

**Pas de niveau maximum** — le coût croît exponentiellement (×1.8 par niveau).

---

### 3.2 Bond Dividend

Le Bond Dividend est un multiplicateur dont la puissance **scale avec le bond actuel du NPC**. À faible bond, il est moins intéressant que le Bit Multiplier ; à bond élevé, il le surpasse largement.

**Formule de la contribution :**
```
bdBonus = (bond / 10) × factor[level]
```

**Niveaux et facteurs :**

| Niveau | Coût       | Facteur | Bond 3 | Bond 5 | Bond 7 | Bond 10 |
|--------|-----------|---------|--------|--------|--------|---------|
| L0     | —         | 0       | +0%    | +0%    | +0%    | +0%     |
| L1     | 200 bits  | 0.5     | +15%   | +25%   | +35%   | +50%    |
| L2     | 600 bits  | 1.2     | +36%   | +60%   | +84%   | +120%   |
| L3     | 1 800 bits| 3.0     | +90%   | +150%  | +210%  | +300%   |

**3 niveaux maximum** (contrairement au Bit Multiplier illimité).

À bond 5, le L1 du Bond Dividend (+25%) vaut exactement le L1 du Bit Multiplier (+25%) pour un coût 4× plus élevé. L'intérêt du Bond Dividend apparaît à partir de bond 6–7.

---

### 3.3 Bit Trickle — modèle Cookie Clicker

Le Bit Trickle est un revenu passif fixe, indépendant du daemon et des multiplicateurs. Il s'inspire directement du **curseur de Cookie Clicker** : chaque achat ajoute une unité, les unités s'accumulent de manière additive, sans niveau maximum.

**Mécanique :**
- Chaque unité produit **1 bit toutes les 10 secondes**
- Un timer se déclenche toutes les 10s dans l'app
- Les bits trickle s'accumulent dans `trickleBitsAccumulated`
- Une animation flottante apparaît au-dessus du NPC à chaque tick (si gain ≥ 0.5 bit)

**Coûts et payback :**

| Unités achetées | Coût unitaire | Coût cumulé | Taux | Payback |
|-----------------|--------------|-------------|------|---------|
| 1               | 50 bits      | 50 bits     | 1 b/10s | 8.3 min |
| 2               | 57.5 bits    | 107.5 bits  | 2 b/10s | 4.8 min |
| 3               | 66.1 bits    | 173.6 bits  | 3 b/10s | 3.7 min |
| 5               | 87.5 bits    | 337.1 bits  | 5 b/10s | 2.9 min |
| 10              | 175.9 bits   | 1 015 bits  | 10 b/10s | 2.9 min |
| N               | `50 × 1.15^(N−1)` | — | N b/10s | ~3 min |

**Cap offline :** Quand l'app est fermée, le trickle continue de s'accumuler mais est plafonné à **1 heure** de production au redémarrage (évite les dumps massifs après une longue absence).

**Le trickle n'est pas amplifié** par le Bit Multiplier ni par le Bond Dividend — c'est un revenu brut indépendant.

---

## 4. Le multiplicateur effectif combiné

Bit Multiplier et Bond Dividend se combinent de façon **additive** (pas multiplicative) pour former le multiplicateur effectif :

```
effectiveMultiplier = 1.0 + bitMultiplierBonus + bondDividendBonus
                    = 1.0 + (bitMultiplierLevel × 0.25) + ((bond / 10) × bondFactor[bdLevel])
```

**Exemples (bond = 4) :**

| Bit Multiplier | Bond Dividend | Multiplicateur effectif |
|---------------|--------------|------------------------|
| L0            | L0           | 1.00×                  |
| L4 (+100%)    | L0           | 2.00×                  |
| L0            | L3 (+120%)   | 2.20×                  |
| L4 (+100%)    | L3 (+120%)   | 3.20×                  |
| L12 (+300%)   | L3 (+120%)   | 5.20×                  |

**Pourquoi additif ?** L'empilement multiplicatif `bitMult × bdMult` créait des explosions de balance lors de chaque achat (ex. : un achat de Bit Multiplier à L10 avec Bond Dividend L3 actif donnait un saut instantané de `totalBits × 0.35 × bdMult`). L'addition garantit que chaque niveau d'upgrade contribue toujours +0.25 net, quel que soit l'état de l'autre upgrade.

---

## 5. Architecture des accumulateurs (`economy.json`)

Tout l'état économique côté app est persisté dans `~/.pixelvillage/economy.json` par l'`EconomyStore`. Le ledger est en lecture seule pour l'app.

### Structure par agent (`AgentUpgradeState`)

```
bitMultiplierLevel      : Int     — nombre de niveaux achetés
bondDividendLevel       : Int     — niveau actuel (0–3)
trickleLevel            : Int     — nombre d'unités trickle achetées
spentBits               : Double  — total cumulé de bits dépensés en upgrades
bonusAccumulated        : Double  — bonus de multiplicateur crédité sur events daemon
trickleBitsAccumulated  : Double  — bits passifs accumulés par le trickle
lastTrickleAt           : Date?   — dernier tick trickle (pour le calcul offline)
lastPurchasedAt         : Date?   — dernier achat (usage futur)
```

### Flux des bits

```
DAEMON
  │ token event → bits bruts
  ↓
ledger.json (totalBits, recentEvents)
  │
  ├──→ VillageEngine lit totalBits (read-only)
  │
  └──→ VillageEngine.creditMultiplierBonus(for: freshEvents)
         │ bonus = event.bits × (effectiveMultiplier − 1.0)
         ↓
       economy.json → bonusAccumulated

TRICKLE TIMER (toutes les 10s, app ouverte)
  │ gained = trickleRate(count) × elapsed / 10
  ↓
economy.json → trickleBitsAccumulated

ACHAT D'UPGRADE
  │ spentBits += coût
  ↓
economy.json → spentBits
```

### Mécanisme de plancher (`refreshBonusFloor`)

À chaque démarrage de l'app, un plancher est appliqué :
```
bonusAccumulated = max(bonusAccumulated, totalBits × (effectiveMultiplier − 1.0))
```
Cela garantit que `bonusAccumulated` ne soit jamais inférieur à ce que le multiplicateur actuel aurait dû générer sur l'ensemble des bits acquis historiquement. Ce mécanisme préserve la continuité en cas de migration de formule ou de démarrage partiel du ledger.

---

## 6. Effet des bits sur le monde — le Fog System

Le **Fog System** révèle progressivement les zones de la carte en fonction du `totalBits` **brut du ledger global** (non multiplié, non modifié par les upgrades) :

| Zone        | Seuil `totalBits` |
|-------------|-------------------|
| Forêt       | 1 000 bits        |
| Lac         | 5 000 bits        |
| Marché      | 10 000 bits       |
| Montagne    | 25 000 bits       |

Le fog représente la progression "hard" basée sur l'effort réel de coding — il ne peut pas être accéléré par les upgrades du shop.

---

## 7. Résumé des invariants économiques

| Règle | Détail |
|-------|--------|
| `totalBits` ne diminue jamais | C'est le compteur lifetime du daemon |
| `spentBits` ne diminue jamais | Les achats sont permanents |
| `availableBits ≥ 0` | Clampé à 0 si négatif (ne peut pas être en dette) |
| Les multiplicateurs ne s'appliquent qu'aux nouveaux events | Pas de rétroactivité sauvage |
| Le trickle n'est pas boosté par les multiplicateurs | Revenu brut indépendant |
| Le fog utilise `totalBits` brut du ledger global | Résistant aux upgrades, fidèle à l'usage réel |
| Le Bond Dividend scale avec le bond courant | Valeur dynamique — s'améliore naturellement avec l'usage |
| Cap offline trickle = 1h | Évite les récompenses disproportionnées à la réouverture |

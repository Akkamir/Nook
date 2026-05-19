# NPC Inspector Panel Design

## Goal

Add a right-side NPC inspector panel so clicking a character exposes useful agent state without interrupting the map. This is the first real interaction loop on top of the living village: the user can inspect who a NPC represents, whether it is active, and how its progress is changing.

## Current Context

- `VillageScene.mouseDown(with:)` already detects NPC clicks and emits `NPCSelection?` through `onNPCSelection`.
- `ContentView` already stores `selectedNPC` and shows a small temporary overlay.
- `NPCSelection` currently contains `id`, `name`, `bond`, `totalTokens`, `totalBits`, `activeSessionCount`, and `trait`.
- `NPCManager.selection(for:)` is the existing bridge from SpriteKit state to SwiftUI state.
- `VillageEngine` is the source of truth for ledger state and active session counts.

## UX

The selected NPC appears in a fixed sidebar aligned to the trailing edge of the window. The panel should use the same quiet dark, monospaced visual language as the current HUD, but with a more intentional layout.

Content:

- Header with NPC name and a close button.
- Status row: `Working` when `activeSessionCount > 0`, otherwise `Idle`.
- Session count when active.
- Bits, tokens, bond level, and work trait.
- Bond progress bar toward the next known threshold.

Interactions:

- Clicking a NPC opens or replaces the panel.
- Clicking empty map space closes the panel.
- The close button closes the panel.
- The panel should allow hit testing so the close button works.
- The panel should not block normal map interaction outside its bounds.

## Data Flow

The first implementation should keep `NPCSelection` as the DTO consumed by SwiftUI. `ContentView` owns the selected value and passes a close callback into `NPCInspectorPanel`.

To avoid stale panel data, `VillageScene` should remember the selected NPC id. When engine-driven state changes cause `npcManager` to resync, the scene should republish `npcManager.selection(for:)` for the selected id if that NPC still exists. If the NPC disappears, it should emit `nil`.

This keeps a single read path:

`VillageEngine` -> `NPCManager` -> `NPCSelection` -> `ContentView` -> `NPCInspectorPanel`

## Components

### `NPCInspectorPanel`

A SwiftUI view responsible only for presentation. It accepts:

- `selection: NPCSelection`
- `onClose: () -> Void`

It formats numbers locally and uses a small private progress view for bond progress.

### Bond Progress Helper

Add a pure helper for bond thresholds so it can be tested without SpriteKit or SwiftUI. It should mirror the daemon's bond thresholds:

- Bond 1 starts below 10,000 tokens.
- Bond 2 starts at 10,000 tokens.
- Bond 3 starts at 50,000 tokens.
- Bond 4 starts at 200,000 tokens.
- Bond 5 starts at 1,000,000 tokens.

For max bond, the panel should show a complete progress bar and a `Max bond` style label.

## Error Handling

If selected data becomes unavailable, close the panel. Avoid showing partially stale or placeholder data.

If progress data cannot compute a next threshold because the NPC is already maxed, show a complete bar.

## Testing

Add focused unit coverage for the bond progress helper:

- Below first threshold.
- Between each threshold.
- At max bond.

Run the relevant Swift tests if the scheme supports them, then run the app build command used in the project to confirm the SwiftUI and SpriteKit integration compiles.

## Out of Scope

- Recent activity history.
- Editable NPC metadata.
- Personality timeline.
- Session transcript links.
- Build mode or map editing.

# Maygetsu Local Village Redesign

## Goal

Move Nook's visual direction from procedural placeholder sprites toward a cozy top-down village inspired by Animal Crossing, using Maygetsu's Cozy Town assets as the primary visual reference and local asset source. The project remains public for now, so Maygetsu PNGs are not committed to Git.

## Source Asset Policy

Maygetsu's Cozy Town pack is the chosen visual direction. It provides 16x16 top-down town/village tiles, buildings, props, animated characters, animals, and effects. The pack allows use and modification under its listed terms, with commercial usage requiring payment at the stated threshold. It also forbids reuploading or redistributing the assets as standalone graphics or inside another asset pack.

Because Nook is currently public, raw Maygetsu assets must remain local:

- Local source directory: `Assets.local/Maygetsu/`
- Generated local runtime directory: `NookApp/GeneratedAssets.local/Maygetsu/`
- Both directories are ignored by Git.
- The repository includes code, manifests, import scripts, and placeholders only.
- The app compiles and runs without Maygetsu assets, using clear placeholders and a visible missing-assets state.

If Nook later becomes private or gains a commercial distribution path, paying for the Maygetsu commercial license enables use in the app, but does not by itself imply raw PNGs should be published in a public repository.

## Visual Direction

The village should feel like a compact, inspectable community rather than a large empty map. The first viewport should show the heart of the village: a central plaza, paths, benches, lamps, trees, small houses or cabins, and work spots for each agent.

The Pixel Agents influence is structural, not thematic:

- crisp low-resolution bitmap assets;
- dense object placement;
- readable grid-aligned furniture and props;
- NPCs with directional animation states;
- NPCs returning to assigned work spots;
- speech/status bubbles above characters;
- hover or selection outlines;
- depth sorting so characters can pass in front of or behind props.

The Animal Crossing influence is thematic:

- outdoor village instead of office interior;
- houses/cabins instead of cubicles;
- cozy paths and plaza instead of floor plans;
- work spots that look like small outdoor desks, workshops, benches, or tables;
- gentle, toy-like composition with readable silhouettes.

## Scene Composition

The first implementation should replace the current broad 128x128 map feeling with a compact village hub centered on the existing parcelle. The map may still be backed by the current world dimensions, but the rendered village core should be authored as a smaller layout.

Minimum village layout:

- central plaza with path intersections;
- 3-8 agent work spots arranged around the plaza;
- one home/work landmark per visible agent where possible;
- decorative props around edges: trees, bushes, fences, lamps, market stall, benches;
- optional water/fountain/bridge if available in the pack;
- clear walkable lanes so NPC pathing reads naturally.

The current procedural `VillageDecorLayer` becomes a fallback or debug layer. The asset-driven village layer becomes the default when imported Maygetsu assets are available.

## Asset Pipeline

The app should not depend on the exact Maygetsu zip layout at runtime. Instead, an import step normalizes local source assets into a small Nook-specific runtime schema.

Input:

- user downloads/extracts Maygetsu Cozy Town into `Assets.local/Maygetsu/source/`;
- import script scans known PNG sheets and optional Aseprite exports where available.

Output:

- normalized PNGs in `NookApp/GeneratedAssets.local/Maygetsu/`;
- a generated manifest such as `maygetsu-manifest.json`;
- no generated asset file is committed.

The manifest should describe:

- terrain tiles by semantic role: grass, dirt, stone path, water, plaza;
- props by semantic role: tree, bush, lamp, bench, fence, sign, market, fountain;
- building parts or prefab buildings;
- character sprite sheets and animation frame rectangles;
- optional animation frame timings.

The import script should fail with actionable messages when assets are missing, but the app itself should fall back gracefully.

## SpriteKit Architecture

Add a visual asset layer rather than hardwiring Maygetsu directly into scene code.

Core types:

- `PixelAssetCatalog`: loads the normalized manifest and resolves `SKTexture` objects.
- `VillageLayout`: data model for tiles, props, buildings, work spots, and spawn points.
- `AssetTileMap`: renders compact tile layers with nearest-neighbor filtering.
- `VillagePropNode`: renders placed props/buildings with footprint and depth anchor metadata.
- `NPCSpriteAnimator`: replaces the procedural body/head sprite path when character sheets are available.
- `VillageDepthLayer`: owns z-sorted props and NPCs, or provides a consistent z-position policy.

Existing state classes stay useful:

- `VillageEngine` continues to own ledger, active sessions, day phase, and bit events.
- `NPCVisualState` remains the bridge from Claude state to visual state.
- `NPCBehavior` evolves from random step movement into grid/path movement between village waypoints and assigned work spots.
- `NPCSelection` remains the SwiftUI inspection payload.

## NPC Behavior Mapping

Each agent gets a stable village role:

- `homeTile`: where the NPC rests or returns at night;
- `workSpotTile`: where active work is shown;
- `wanderZone`: small nearby set of tiles for idle movement;
- `characterVariant`: deterministic assignment based on agent id.

Visual state mapping:

- inactive day: walk/wander around the plaza or near home;
- active session count 1: walk to work spot, show focused work animation;
- active session count 2: same spot, faster or more energetic work loop;
- active session count 3+: overloaded bubble and more intense animation;
- night: return home/bench and idle/rest;
- reading/search tool, once available from hook status: reading animation;
- editing/bash/tool use: typing/work animation;
- waiting/permission: speech bubble state.

The first pass does not need full pathfinding. It can use short grid paths around the authored plaza, but movement should be tile-centered and directional so sprite animations read correctly.

## Fallback Behavior

When Maygetsu assets are missing:

- the app shows a small non-blocking overlay: "Local village assets missing";
- `TileMap`, `VillageDecorLayer`, and procedural `NPCSprite` remain available;
- import instructions are visible in docs, not inside the main user UI;
- tests and app build still pass on a clean public checkout.

This keeps the public repository useful without leaking premium/local art.

## Non-Goals

This design does not include:

- committing Maygetsu PNGs to Git;
- implementing a build/shop editor;
- supporting arbitrary third-party asset packs;
- converting the whole app to Canvas or React;
- full farming economy;
- terminal panels;
- public commercial packaging.

## Testing And Verification

Verification for this redesign should include:

- clean checkout without `Assets.local`: app builds and runs with fallback visuals;
- local checkout with imported Maygetsu assets: manifest loads, textures render, and nearest-neighbor filtering is applied;
- NPCs remain selectable after the sprite renderer swap;
- active session count changes still update NPC visual state;
- day/night changes still update NPC behavior;
- `swift test --package-path /Users/mchau/Desktop/Code/Nook`;
- `xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build`.

## Open Implementation Choices

The implementation plan should decide:

- whether the import script is Swift, shell, or a small command-line utility;
- whether generated local assets live inside `NookApp/GeneratedAssets.local` or are loaded from `Assets.local`;
- whether the first asset-driven tile renderer uses `SKSpriteNode` batching or `SKTileMapNode`;
- whether character animation uses Maygetsu character assets immediately or ships first with village tiles/props only;
- how much of the existing procedural layer remains visible behind the Maygetsu layout.

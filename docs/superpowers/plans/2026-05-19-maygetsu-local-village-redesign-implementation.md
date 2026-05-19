# Maygetsu Local Village Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local-only Maygetsu asset pipeline and an asset-driven cozy village hub renderer while keeping the public repo buildable without premium assets.

**Architecture:** Generated Maygetsu assets live outside Git and are described by a small manifest loaded at runtime. `VillageScene` chooses between the existing procedural fallback and a new asset-driven village layer based on manifest availability. The first implementation renders terrain and props; NPC sprite-sheet animation remains scoped for the next pass once the local Maygetsu export shape is known.

**Tech Stack:** Swift 6, SpriteKit, XcodeGen, local shell import script, JSON manifests, existing `VillageScene` / `TileMap` / `NPCManager` architecture.

---

## File Map

- Modify `.gitignore` to exclude `Assets.local/` and `NookApp/GeneratedAssets.local/`.
- Create `docs/assets/maygetsu-local-assets.md` with setup and licensing notes.
- Create `tools/import_maygetsu_assets.sh` to normalize local PNGs into `NookApp/GeneratedAssets.local/Maygetsu/`.
- Create `Sources/NookApp/PixelAssetCatalog.swift` for manifest decoding and texture lookup.
- Create `Sources/NookApp/VillageLayout.swift` for authored tile/prop/workspot layout data.
- Create `Sources/NookApp/AssetTileMap.swift` for asset-backed terrain rendering.
- Create `Sources/NookApp/AssetVillageLayer.swift` for asset-backed hub rendering.
- Modify `Sources/NookApp/VillageScene.swift` to choose asset-backed vs fallback layers.
- Modify `Sources/NookApp/ContentView.swift` to show a small local-assets status overlay.

## Task 1: Ignore And Document Local Maygetsu Assets

**Files:**
- Modify: `.gitignore`
- Create: `docs/assets/maygetsu-local-assets.md`

- [ ] **Step 1: Add local asset directories to `.gitignore`**

Add:

```gitignore
Assets.local/
NookApp/GeneratedAssets.local/
```

- [ ] **Step 2: Add setup documentation**

Create `docs/assets/maygetsu-local-assets.md` explaining:

- Maygetsu assets are local-only and not committed.
- Put the extracted pack under `Assets.local/Maygetsu/source/`.
- Run `tools/import_maygetsu_assets.sh`.
- Commit code/manifests/scripts only, never generated PNGs.

- [ ] **Step 3: Commit**

```bash
git add .gitignore docs/assets/maygetsu-local-assets.md
git commit -m "docs: document local Maygetsu asset setup"
```

## Task 2: Add Import Script

**Files:**
- Create: `tools/import_maygetsu_assets.sh`

- [ ] **Step 1: Write script**

The script should:

- read from `Assets.local/Maygetsu/source`;
- write to `NookApp/GeneratedAssets.local/Maygetsu`;
- copy best-effort matching PNGs for roles: grass, path, water, tree, bench, lamp, house, market, fountain;
- emit `maygetsu-manifest.json`;
- fail if no PNGs are found.

- [ ] **Step 2: Run script without assets to verify failure**

```bash
tools/import_maygetsu_assets.sh
```

Expected: non-zero exit with a message telling the user to place assets under `Assets.local/Maygetsu/source`.

- [ ] **Step 3: Commit**

```bash
git add tools/import_maygetsu_assets.sh
git commit -m "chore: add Maygetsu local asset importer"
```

## Task 3: Add Manifest Catalog

**Files:**
- Create: `Sources/NookApp/PixelAssetCatalog.swift`

- [ ] **Step 1: Write a failing probe**

Create `/tmp/nook_catalog_probe.swift` with minimal manifest decoding expectations for terrain and props. Run it before adding production code to verify `PixelAssetCatalog` is missing.

- [ ] **Step 2: Implement catalog**

Add Codable manifest models:

- `PixelAssetManifest`
- `PixelAssetEntry`
- `PixelAssetCatalog`

The catalog should load from:

1. `NOOK_MAYGETSU_ASSET_ROOT` environment variable, if present;
2. bundled `GeneratedAssets.local/Maygetsu` resources, if present;
3. repo-local `NookApp/GeneratedAssets.local/Maygetsu` relative to the current working directory, if present.

- [ ] **Step 3: Run probe again**

Expected: probe passes.

- [ ] **Step 4: Run XcodeGen and build**

```bash
xcodegen generate
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Sources/NookApp/PixelAssetCatalog.swift NookApp.xcodeproj/project.pbxproj
git commit -m "feat: add local pixel asset catalog"
```

## Task 4: Render Asset-Driven Village Hub

**Files:**
- Create: `Sources/NookApp/VillageLayout.swift`
- Create: `Sources/NookApp/AssetTileMap.swift`
- Create: `Sources/NookApp/AssetVillageLayer.swift`
- Modify: `Sources/NookApp/VillageScene.swift`

- [ ] **Step 1: Add layout data**

Create a compact 24x24 hub centered around the existing parcelle. Include terrain roles and prop placements.

- [ ] **Step 2: Add tile and prop rendering**

Render nearest-neighbor `SKSpriteNode`s from `PixelAssetCatalog`. Missing roles should use deterministic colored fallback sprites, not crash.

- [ ] **Step 3: Switch `VillageScene`**

If `PixelAssetCatalog.loadMaygetsu()` succeeds, build `AssetVillageLayer`; otherwise keep existing `TileMap` + `VillageDecorLayer`.

- [ ] **Step 4: Run XcodeGen and build**

```bash
xcodegen generate
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Sources/NookApp/VillageLayout.swift Sources/NookApp/AssetTileMap.swift Sources/NookApp/AssetVillageLayer.swift Sources/NookApp/VillageScene.swift NookApp.xcodeproj/project.pbxproj
git commit -m "feat: render Maygetsu asset village layer"
```

## Task 5: Add Missing Asset Overlay And Final Verification

**Files:**
- Modify: `Sources/NookApp/VillageScene.swift`
- Modify: `Sources/NookApp/ContentView.swift`

- [ ] **Step 1: Publish asset availability**

`VillageScene` should expose `onLocalAssetAvailability: ((Bool) -> Void)?` and call it after deciding the render path.

- [ ] **Step 2: Add SwiftUI overlay**

`ContentView` should show a compact "Local village assets missing" overlay when assets are not available.

- [ ] **Step 3: Run full verification**

```bash
swift test --package-path /Users/mchau/Desktop/Code/Nook
xcodebuild -project /Users/mchau/Desktop/Code/Nook/NookApp.xcodeproj -scheme NookApp -destination 'platform=macOS' build
```

Expected: Swift tests pass with 0 failures and Xcode build succeeds.

- [ ] **Step 4: Commit and push**

```bash
git add Sources/NookApp/VillageScene.swift Sources/NookApp/ContentView.swift
git commit -m "feat: surface local village asset status"
git push
```

## Self-Review

Spec coverage:

- Local-only Maygetsu policy is covered by Tasks 1 and 2.
- Public build fallback is covered by Tasks 3, 4, and 5.
- Asset manifest and loader are covered by Task 3.
- Asset-driven terrain/props are covered by Task 4.
- Missing-asset status is covered by Task 5.

Known deferral:

- Character sprite-sheet animation is intentionally deferred until local Maygetsu files are available and their exact frame layout can be inspected.

Placeholder scan:

- No task requires unspecified files or undefined behavior. The importer is best-effort because the source zip is local and not available in the repo.

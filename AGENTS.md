# Repository Guidelines

## Project Structure & Module Organization

Nook is a macOS Swift project split between a SwiftPM daemon and an XcodeGen app. `Sources/NookDaemon` contains the command-line daemon that watches Claude data and writes the ledger. `Sources/NookApp` contains the SwiftUI/SpriteKit app, village engine, UI panels, and app-side models. `Tests/NookTests` covers daemon logic through SwiftPM; `Tests/NookAppTests` covers the app target through Xcode. `NookApp/` holds app metadata, entitlements, and asset catalogs. `tiled/` contains the Tiled map and tileset JSON. Design notes and implementation plans live under `docs/`.

## Architecture

Nook is a macOS app (style Stardew Valley / Animal Crossing) where Claude Code token usage is the in-game currency. A background daemon turns tokens into "Bits"; a SpriteKit village renders agents (NPCs) that live and grow as your Claude sessions run. See `docs/design.md` for the product vision.

Data flows one direction through a JSON ledger on disk:

```
~/.claude/projects/*.jsonl  →  NookDaemon  →  ~/.pixelvillage/ledger.json  →  VillageEngine  →  VillageScene (SpriteKit)
   (Claude transcripts)        (parse+economy)      (shared file)              (app state)         (rendering)
```

1. **NookDaemon** (`Sources/NookDaemon/`) runs in the background as a macOS LaunchAgent (`com.nook.daemon`), even when the app is closed. `ClaudeWatcher` polls `~/.claude/projects/` every 250ms, tracking per-file byte offsets (`offsets.json`) so it only parses new JSONL lines. `TranscriptParser` extracts token usage; `Ledger` converts tokens to Bits (**input: 5 Bits / 1k tokens, output: 15 Bits / 1k**) and persists `LedgerState`.

2. **Agent attribution** (`AgentAttributor`): tokens are credited to an NPC only if the project directory contains a `.pixelvillage` file (`{"agent": "Radion"}`). Claude encodes project paths as dir names like `-Users-foo-bar`; the attributor decodes these back to the real path to find the config. No file → Bits go to the global pool, no bond progression.

3. **VillageEngine** (`Sources/NookApp/`) is the app's `@MainActor @Observable` core. `LedgerWatcher` watches `ledger.json` for changes and reloads `LedgerState`. The engine drives day/night phases, Bit-gain animations (via `recentEvents` / `eventSeq`), and NPC speech (via `recentActivity` / `activitySeq`). The app **only reads** the ledger — it never writes Bits.

4. **Live session detection** is a *separate* path from the token economy. The app runs its own `ClaudeHookServer` + `ClaudeHookInstaller` (installs Claude Code hooks) and `ClaudeProjectsWatcher`, feeding `SessionDetector` to know which agents are *actively working right now* — this animates NPCs in real time, independent of the daemon's Bit accounting.

5. **Daemon lifecycle**: the app embeds the release `NookDaemon` binary into its bundle at build time (`project.yml` postBuildScript) and `DaemonInstaller` writes/reloads the LaunchAgent plist on launch.

### Critical: the ledger schema is duplicated across both targets

`LedgerState`, `SessionRecord`, `AgentRecord`, `BitEvent`, and `SessionActivityEvent` are defined **twice** — in `Sources/NookDaemon/Models.swift` (writer) and `Sources/NookApp/LedgerModels.swift` (reader). The two targets can't share code, so **any change to the on-disk ledger format must be made in both files**, kept byte-compatible.

Because real users have existing `ledger.json` files, every model uses **hand-written backward-compatible `init(from:)` decoders** that tolerate missing fields (e.g. subject fields on `SessionRecord`, `totalBits` migrated from `totalTokens`). When adding a field, add it as optional/defaulted in the custom decoder in **both** copies, and add a decode test (`LedgerStateDecodeTests` / `LedgerStateAppDecodeTests`).

### Rendering

`VillageScene` is the SpriteKit scene. The village can render from a Tiled map (`tiled/nook-village.tmj`, `TiledVillageLayer`/`TiledMapData`) or procedural/asset layers (`AssetVillageLayer`, `VillageDecorLayer`). Pixel art uses `.nearest` texture filtering. Local-only art lives under `NookApp/GeneratedAssets.local/` and `Assets.local/` (untracked); `project.yml` postBuildScripts copy them into the bundle and patch absolute tileset paths in the `.tsj` files.

## Build, Test, and Development Commands

- `make daemon`: runs `swift build` for the `NookDaemon` package target.
- `swift test`: runs the SwiftPM daemon tests in `Tests/NookTests`.
- `make app`: regenerates `NookApp.xcodeproj` from `project.yml` with XcodeGen, then opens it.
- `xcodebuild test -scheme NookApp -project NookApp.xcodeproj`: runs app unit tests after the project has been generated.

`project.yml` is the source of truth for the Xcode project. Do not hand-edit generated `*.xcodeproj` files.

## Coding Style & Naming Conventions

Use standard Swift formatting: 4-space indentation, braces on the declaration line, and clear type names in `UpperCamelCase`. Methods, properties, and test functions use `lowerCamelCase`; existing tests use descriptive names such as `test_apply_event_with_agent_updates_bond`. Prefer small model types and focused helpers over broad utility classes. Keep comments rare and specific, especially around persistence, attribution, and filesystem behavior.

## Testing Guidelines

Add or update tests with behavior changes. Daemon tests should live in `Tests/NookTests` and import `NookDaemon`; app tests should live in `Tests/NookAppTests` and import `Nook`. Use temporary directories for filesystem tests and clean them in `tearDown`. Keep assertions concrete: verify decoded fields, token counts, dates, and ledger mutations rather than only checking non-nil values.

## Commit & Pull Request Guidelines

Recent history uses Conventional Commit-style messages, for example `feat(app): add ProjectRollup history helper` and `fix(daemon): keep prior session attribution when agent unresolved`. Follow `type(scope): summary`, with scopes like `app`, `daemon`, or `docs`.

Pull requests should describe the user-visible change, list validation commands run, and include screenshots or short recordings for UI changes. Mention any changes to local data formats, ledger compatibility, Tiled assets, or generated project configuration.

## Security & Configuration Tips

Keep local-only assets and runtime state untracked. `.gitignore` already excludes `.pixelvillage`, `Assets.local/`, `NookApp/GeneratedAssets.local/`, build outputs, and generated Xcode projects. Avoid committing machine-specific paths; asset path patching belongs in `project.yml` build scripts.

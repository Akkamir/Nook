# Maygetsu Local Assets

Nook uses Maygetsu's Cozy Town asset pack as the preferred local visual source for the cozy village redesign. The raw PNGs are not committed to this repository while the repo is public.

## Directory Layout

Put the extracted Maygetsu pack here:

```text
Assets.local/Maygetsu/source/
```

Run the local importer from the repo root:

```bash
tools/import_maygetsu_assets.sh
```

The importer writes normalized runtime assets here:

```text
NookApp/GeneratedAssets.local/Maygetsu/
```

Both `Assets.local/` and `NookApp/GeneratedAssets.local/` are ignored by Git.

## License Boundary

Maygetsu's page allows use and modification under its listed terms, with commercial use requiring payment at the stated threshold. It does not allow redistributing the assets as standalone graphics or inside another asset pack.

For this repo:

- commit code, scripts, docs, and generated manifest schemas;
- do not commit Maygetsu PNGs or extracted zip contents;
- keep local generated assets on the development machine;
- use the app fallback visuals on clean public checkouts.

## Current Importer Behavior

The importer is intentionally conservative. It scans local PNG filenames and copies best-effort matches for common village roles such as grass, paths, water, trees, benches, lamps, houses, markets, and fountains. If a role is missing, the app uses a deterministic placeholder for that role instead of crashing.

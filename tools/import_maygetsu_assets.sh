#!/usr/bin/env python3
"""Import Maygetsu Cozy Town local assets into NookApp's generated asset catalog.

Terrain tiles are cropped from tilesets (16px tiles).
Props are copied directly from Individual/ PNGs.
Characters are copied from Spritesheets/Characters/.
"""

import json
import os
import shutil
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow not found. Installing...", file=sys.stderr)
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow", "-q"])
    from PIL import Image

ROOT_DIR = Path(__file__).resolve().parent.parent
PACK_DIR = ROOT_DIR / "Assets.local" / "Maygetsu" / "source" / "CozyTown_AssetPack"
OUT_DIR = ROOT_DIR / "NookApp" / "GeneratedAssets.local" / "Maygetsu"
MANIFEST = OUT_DIR / "maygetsu-manifest.json"


def fail(msg: str) -> None:
    print(msg, file=sys.stderr)
    sys.exit(1)


if not PACK_DIR.exists():
    fail(
        f"Maygetsu source assets not found.\n\n"
        f"Expected extracted assets under:\n  {PACK_DIR}\n\n"
        f"Download/extract the Maygetsu Cozy Town pack locally, then run:\n"
        f"  python3 tools/import_maygetsu_assets.sh"
    )

# Clean and recreate output directories
if OUT_DIR.exists():
    shutil.rmtree(OUT_DIR)
for sub in ("terrain", "props", "characters"):
    (OUT_DIR / sub).mkdir(parents=True, exist_ok=True)

terrain: list[dict] = []
props: list[dict] = []
characters: list[dict] = []


def crop_tile(src: Path, dest: Path, left: int, upper: int, right: int, lower: int) -> None:
    """Crop a region from src PNG and save to dest."""
    img = Image.open(src)
    cropped = img.crop((left, upper, right, lower))
    cropped.save(dest)
    print(f"  cropped {src.name} ({left},{upper},{right},{lower}) -> {dest.name}")


def copy_asset(src: Path, dest: Path) -> None:
    """Copy a PNG asset from src to dest."""
    shutil.copy2(src, dest)
    img = Image.open(src)
    print(f"  copied {src.name} {img.size} -> {dest.name}")


# ─── TERRAIN ──────────────────────────────────────────────────────────────────
# Tiles are 16×16 px. (col, row) are 0-indexed.
# pixel_x = col * 16, pixel_y = row * 16

pavements_src = PACK_DIR / "Tileset" / "Structure" / "cozytown_structure_pavements.png"
terrain_src = PACK_DIR / "Tileset" / "Terrain" / "cozytown_terrain.png"

# path → pavements.png tile (col=1, row=1) → pixels (16,16,32,32)
crop_tile(pavements_src, OUT_DIR / "terrain" / "path.png", 16, 16, 32, 32)
terrain.append({"role": "path", "path": "terrain/path.png", "kind": "terrain", "tileWidth": 16, "tileHeight": 16})

# plaza → pavements.png tile (col=2, row=2) → pixels (32,32,48,48)
crop_tile(pavements_src, OUT_DIR / "terrain" / "plaza.png", 32, 32, 48, 48)
terrain.append({"role": "plaza", "path": "terrain/plaza.png", "kind": "terrain", "tileWidth": 16, "tileHeight": 16})

# water → terrain.png tile (col=2, row=2) → pixels (32,32,48,48)
crop_tile(terrain_src, OUT_DIR / "terrain" / "water.png", 32, 32, 48, 48)
terrain.append({"role": "water", "path": "terrain/water.png", "kind": "terrain", "tileWidth": 16, "tileHeight": 16})

# ground → terrain.png tile (col=1, row=7) → pixels (16,112,32,128)
crop_tile(terrain_src, OUT_DIR / "terrain" / "ground.png", 16, 112, 32, 128)
terrain.append({"role": "ground", "path": "terrain/ground.png", "kind": "terrain", "tileWidth": 16, "tileHeight": 16})

# ─── PROPS ────────────────────────────────────────────────────────────────────
nature_dir = PACK_DIR / "Individual" / "Nature"
props_dir = PACK_DIR / "Individual" / "Props"

prop_copies = [
    # (role, src_path, tileWidth, tileHeight)
    ("tree",      nature_dir / "cozytown_tree.png",                      48, 80),
    ("pinetree",  nature_dir / "cozytown_pinetree.png",                  48, 80),
    ("bush",      nature_dir / "cozytown_bush2x2.png",                   32, 32),
    ("bush_large",nature_dir / "cozytown_bush3x3.png",                   48, 48),
    ("bench",     props_dir  / "cozytown_props_bench_parkF.png",         32, 32),
    ("lamp",      props_dir  / "cozytown_props_biglamp.png",             48, 64),
    ("fountain",  props_dir  / "cozytown_props_fountain01.png",          32, 32),
    ("fountain2", props_dir  / "cozytown_props_fountain02.png",          32, 32),
    ("market",    props_dir  / "cozytown_props_marketstall01.png",       48, 64),
    ("fence",     props_dir  / "cozytown_props_fences.png",              80, 48),
    ("table",     props_dir  / "cozytown_props_table01.png",             48, 32),
    ("flowerbed", props_dir  / "cozytown_props_flowerbed_Horizontal.png",32, 16),
]

for role, src, tw, th in prop_copies:
    dest = OUT_DIR / "props" / f"{role}.png"
    if not src.exists():
        print(f"  WARNING: {src} not found, skipping {role}", file=sys.stderr)
        continue
    copy_asset(src, dest)
    props.append({"role": role, "path": f"props/{role}.png", "kind": "prop", "tileWidth": tw, "tileHeight": th})

# ─── CHARACTERS ───────────────────────────────────────────────────────────────
chars_dir = PACK_DIR / "Spritesheets" / "Characters"

char_copies = [
    ("char_boy_walk",  chars_dir / "cozytown_characters_boy_walking.png",  192, 32),
    ("char_girl_walk", chars_dir / "cozytown_characters_girl_walking.png", 192, 32),
    ("char_boy_idle",  chars_dir / "cozytown_characters_boy_idle.png",      64, 32),
    ("char_girl_idle", chars_dir / "cozytown_characters_girl_idle.png",     64, 32),
]

for role, src, tw, th in char_copies:
    dest = OUT_DIR / "characters" / f"{role}.png"
    if not src.exists():
        print(f"  WARNING: {src} not found, skipping {role}", file=sys.stderr)
        continue
    copy_asset(src, dest)
    characters.append({"role": role, "path": f"characters/{role}.png", "kind": "character", "tileWidth": tw, "tileHeight": th})

# ─── MANIFEST ─────────────────────────────────────────────────────────────────
manifest = {
    "version": 1,
    "pack": "Maygetsu Cozy Town",
    "tileSize": 16,
    "terrain": terrain,
    "props": props,
    "characters": characters,
}
MANIFEST.write_text(json.dumps(manifest, indent=2))

print(f"\nImported Maygetsu local assets:")
print(f"  manifest: {MANIFEST}")
print(f"  terrain roles ({len(terrain)}): {[e['role'] for e in terrain]}")
print(f"  prop roles ({len(props)}): {[e['role'] for e in props]}")
print(f"  character sheets ({len(characters)}): {[e['role'] for e in characters]}")

#!/usr/bin/env python3
"""Import Maygetsu Cozy Town local assets into NookApp's generated asset catalog."""

import json
import os
import re
import shutil
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT_DIR / "Assets.local" / "Maygetsu" / "source"
OUT_DIR = ROOT_DIR / "NookApp" / "GeneratedAssets.local" / "Maygetsu"
MANIFEST = OUT_DIR / "maygetsu-manifest.json"


def fail(msg: str) -> None:
    print(msg, file=sys.stderr)
    sys.exit(1)


if not SOURCE_DIR.exists():
    fail(
        f"Maygetsu source assets not found.\n\n"
        f"Expected extracted assets under:\n  {SOURCE_DIR}\n\n"
        f"Download/extract the Maygetsu Cozy Town pack locally, then run:\n"
        f"  tools/import_maygetsu_assets.sh"
    )

pngs = sorted(
    p for p in SOURCE_DIR.rglob("*.png")
    if "__MACOSX" not in str(p)
)
if not pngs:
    fail(f"No PNG files found under {SOURCE_DIR}")

if OUT_DIR.exists():
    shutil.rmtree(OUT_DIR)
for sub in ("terrain", "props", "characters"):
    (OUT_DIR / sub).mkdir(parents=True, exist_ok=True)


def find_and_copy(section: str, role: str, patterns: list[str], size: tuple[int, int]) -> dict | None:
    """Find first PNG matching any pattern, copy it, return manifest entry."""
    for pattern in patterns:
        for p in pngs:
            if re.search(pattern, p.name, re.IGNORECASE):
                dest = OUT_DIR / section / f"{role}{p.suffix.lower()}"
                shutil.copy2(p, dest)
                w, h = size
                return {
                    "role": role,
                    "path": f"{section}/{role}{p.suffix.lower()}",
                    "kind": section.rstrip("s"),
                    "tileWidth": w,
                    "tileHeight": h,
                }
    return None


terrain: list[dict] = []
props: list[dict] = []
characters: list[dict] = []

# Terrain
for role, patterns, size in [
    ("grass",  ["terrain", "grass", "ground"],            (16, 16)),
    ("path",   ["pavement", "path", "road", "cobble"],    (16, 16)),
    ("water",  ["water", "river", "pond", "bridge"],      (16, 16)),
    ("plaza",  ["pavement", "plaza", "cobble", "floor"],  (16, 16)),
]:
    entry = find_and_copy("terrain", role, patterns, size)
    if entry:
        terrain.append(entry)

# Props
for role, patterns, size in [
    ("tree",      ["cozytown_tree\\.png", "pinetree", "2tree"],       (32, 48)),
    ("bush",      ["bush", "shrub"],                                   (16, 16)),
    ("bench",     ["bench_parkf", "bench_whitef", "bench"],            (16, 16)),
    ("lamp",      ["biglamp", "smalllamp", "lamp", "lantern"],         (16, 32)),
    ("house",     ["buildings_roofs", "buildings_walls", "roof"],      (16, 16)),
    ("market",    ["marketstall01", "marketstall", "market", "stall"], (32, 32)),
    ("fountain",  ["fountain01", "fountain", "well"],                  (32, 32)),
    ("fence",     ["props_fences", "fence", "wall"],                   (16, 16)),
    ("table",     ["props_table01", "table"],                          (16, 16)),
    ("flowerbed", ["flowerbed_horizontal", "flowerbed", "flower"],     (16, 16)),
]:
    entry = find_and_copy("props", role, patterns, size)
    if entry:
        props.append(entry)

# Character spritesheets
for role, patterns in [
    ("char_boy_walk",  ["characters_boy_walking"]),
    ("char_girl_walk", ["characters_girl_walking"]),
    ("char_boy_idle",  ["characters_boy_idle"]),
    ("char_girl_idle", ["characters_girl_idle"]),
]:
    entry = find_and_copy("characters", role, patterns, (16, 16))
    if entry:
        characters.append(entry)

if not terrain and not props and not characters:
    fail("No known Maygetsu roles could be matched from PNG filenames.")

manifest = {
    "version": 1,
    "pack": "Maygetsu Cozy Town",
    "tileSize": 16,
    "terrain": terrain,
    "props": props,
    "characters": characters,
}
MANIFEST.write_text(json.dumps(manifest, indent=2))

print(f"Imported Maygetsu local assets:")
print(f"  {MANIFEST}")
print(f"  terrain roles: {len(terrain)}")
print(f"  prop roles: {len(props)}")
print(f"  character sheets: {len(characters)}")

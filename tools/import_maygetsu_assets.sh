#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${ROOT_DIR}/Assets.local/Maygetsu/source"
OUT_DIR="${ROOT_DIR}/NookApp/GeneratedAssets.local/Maygetsu"
MANIFEST="${OUT_DIR}/maygetsu-manifest.json"

if [[ ! -d "${SOURCE_DIR}" ]]; then
  cat >&2 <<EOF
Maygetsu source assets not found.

Expected extracted assets under:
  ${SOURCE_DIR}

Download/extract the Maygetsu Cozy Town pack locally, then run:
  tools/import_maygetsu_assets.sh
EOF
  exit 1
fi

mapfile -t PNGS < <(find "${SOURCE_DIR}" -type f \( -iname '*.png' -o -iname '*.PNG' \) | sort)
if [[ "${#PNGS[@]}" -eq 0 ]]; then
  echo "No PNG files found under ${SOURCE_DIR}" >&2
  exit 1
fi

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/terrain" "${OUT_DIR}/props"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

find_match() {
  local pattern="$1"
  local fallback="${2:-}"
  local match=""
  for file in "${PNGS[@]}"; do
    local base
    base="$(basename "$file" | tr '[:upper:]' '[:lower:]')"
    if [[ "$base" =~ $pattern ]]; then
      match="$file"
      break
    fi
  done
  if [[ -z "$match" && -n "$fallback" ]]; then
    for file in "${PNGS[@]}"; do
      local base
      base="$(basename "$file" | tr '[:upper:]' '[:lower:]')"
      if [[ "$base" =~ $fallback ]]; then
        match="$file"
        break
      fi
    done
  fi
  printf '%s' "$match"
}

copy_role() {
  local section="$1"
  local role="$2"
  local pattern="$3"
  local fallback="${4:-}"
  local match
  match="$(find_match "$pattern" "$fallback")"
  if [[ -z "$match" ]]; then
    return 1
  fi
  local ext="${match##*.}"
  local rel="${section}/${role}.${ext,,}"
  cp "$match" "${OUT_DIR}/${rel}"
  printf '%s' "$rel"
}

declare -a TERRAIN_ENTRIES=()
declare -a PROP_ENTRIES=()

add_entry() {
  local array_name="$1"
  local role="$2"
  local rel="$3"
  local kind="$4"
  local width="$5"
  local height="$6"
  local entry
  entry="    { \"role\": \"$(json_escape "$role")\", \"path\": \"$(json_escape "$rel")\", \"kind\": \"${kind}\", \"tileWidth\": ${width}, \"tileHeight\": ${height} }"
  eval "$array_name+=(\"\$entry\")"
}

if rel="$(copy_role terrain grass 'grass|terrain|ground' '')"; then add_entry TERRAIN_ENTRIES grass "$rel" terrain 16 16; fi
if rel="$(copy_role terrain path 'path|road|stone|cobble' '')"; then add_entry TERRAIN_ENTRIES path "$rel" terrain 16 16; fi
if rel="$(copy_role terrain water 'water|river|pond' '')"; then add_entry TERRAIN_ENTRIES water "$rel" terrain 16 16; fi
if rel="$(copy_role terrain plaza 'plaza|stone|cobble|floor' 'path|road')"; then add_entry TERRAIN_ENTRIES plaza "$rel" terrain 16 16; fi

if rel="$(copy_role props tree 'tree|oak|pine' '')"; then add_entry PROP_ENTRIES tree "$rel" prop 16 16; fi
if rel="$(copy_role props bush 'bush|shrub' '')"; then add_entry PROP_ENTRIES bush "$rel" prop 16 16; fi
if rel="$(copy_role props bench 'bench|seat' '')"; then add_entry PROP_ENTRIES bench "$rel" prop 16 16; fi
if rel="$(copy_role props lamp 'lamp|light|lantern' '')"; then add_entry PROP_ENTRIES lamp "$rel" prop 16 16; fi
if rel="$(copy_role props house 'house|home|building|roof' '')"; then add_entry PROP_ENTRIES house "$rel" prop 16 16; fi
if rel="$(copy_role props market 'market|stall|shop' '')"; then add_entry PROP_ENTRIES market "$rel" prop 16 16; fi
if rel="$(copy_role props fountain 'fountain|well' '')"; then add_entry PROP_ENTRIES fountain "$rel" prop 16 16; fi
if rel="$(copy_role props fence 'fence|wall' '')"; then add_entry PROP_ENTRIES fence "$rel" prop 16 16; fi

if [[ "${#TERRAIN_ENTRIES[@]}" -eq 0 && "${#PROP_ENTRIES[@]}" -eq 0 ]]; then
  echo "No known Maygetsu roles could be matched from PNG filenames." >&2
  exit 1
fi

write_entries() {
  local -n entries_ref="$1"
  local count="${#entries_ref[@]}"
  for ((i = 0; i < count; i++)); do
    if [[ "$i" -lt $((count - 1)) ]]; then
      printf '%s,\n' "${entries_ref[$i]}"
    else
      printf '%s\n' "${entries_ref[$i]}"
    fi
  done
}

{
  cat <<EOF
{
  "version": 1,
  "pack": "Maygetsu Cozy Town",
  "tileSize": 16,
  "terrain": [
EOF
  write_entries TERRAIN_ENTRIES
  cat <<EOF
  ],
  "props": [
EOF
  write_entries PROP_ENTRIES
  cat <<EOF
  ]
}
EOF
} > "${MANIFEST}"

echo "Imported Maygetsu local assets:"
echo "  ${MANIFEST}"
echo "  terrain roles: ${#TERRAIN_ENTRIES[@]}"
echo "  prop roles: ${#PROP_ENTRIES[@]}"

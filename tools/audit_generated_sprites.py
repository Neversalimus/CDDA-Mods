#!/usr/bin/env python3
"""Check actual PNG pixels and CDDA sprite references, including packaged payloads.

Install tools/sprite-qa-requirements.txt for this developer-only QA command.
The per-cell review ledger is evidence of human/visual review, not an automated
claim that a sharpness score can measure artistic quality or in-game rendering.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "mods/undeadpeople/content"
CONTRACT = ROOT / "mods/undeadpeople/art-review/2026-10-09.json"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical_digest(value):
    return digest(json.dumps(value, sort_keys=True, separators=(",", ":")).encode())


def sprite_refs(value):
    """CDDA supports integers, directional arrays and weighted sprite arrays."""
    if isinstance(value, int) and not isinstance(value, bool):
        yield value
    elif isinstance(value, list):
        for element in value:
            yield from sprite_refs(element)
    elif isinstance(value, dict) and "sprite" in value:
        yield from sprite_refs(value["sprite"])


def tile_entries(tile):
    yield tile
    for child in tile.get("additional_tiles", []):
        yield from tile_entries(child)


def inspect_config(cfg, read_bytes):
    """Resolve global indices using every sheet, including the ASCII sheet."""
    info = cfg["tile_info"][0]
    sheets = []
    offset = 0
    for block in cfg["tiles-new"]:
        name = block["file"]
        with Image.open(io.BytesIO(read_bytes(name))) as image:
            width, height = image.size
            image.verify()
        sw = block.get("sprite_width", info["width"])
        sh = block.get("sprite_height", info["height"])
        if sw <= 0 or sh <= 0 or width % sw or height % sh:
            raise ValueError(f"Invalid sheet geometry: {name}: {width}x{height}, cell {sw}x{sh}")
        count = (width // sw) * (height // sh)
        sheets.append(dict(file=name, start=offset, count=count, width=sw,
                           height=sh, columns=width // sw, block=block))
        offset += count
    refs = 0
    for sheet in sheets:
        for tile in sheet["block"].get("tiles", []):
            for entry in tile_entries(tile):
                for layer in ("fg", "bg"):
                    for index in sprite_refs(entry.get(layer, [])):
                        refs += 1
                        # -1 is CDDA's explicit 'no sprite' sentinel.
                        if not -1 <= index < offset:
                            raise ValueError(f"Invalid sprite reference: {entry.get('id')}: {index}")
    return sheets, refs, offset


def inspect_cell(image):
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    data = image.tobytes()
    opaque = [data[i:i + 3] for i in range(0, len(data), 4) if data[i + 3]]
    return dict(pixel_sha256=digest(image.tobytes()), bounds=list(bounds) if bounds else None,
                colors=len(set(opaque)), opaque_pixels=len(opaque),
                binary_alpha=set(alpha.tobytes()) <= {0, 255})


def verify_cell(image, expected):
    stats = inspect_cell(image)
    label = f"{expected['file']} cell {expected['cell']}"
    if not stats["bounds"]:
        raise ValueError(f"Empty sprite: {label}")
    if not stats["binary_alpha"]:
        raise ValueError(f"Soft alpha: {label}")
    if expected["decision"] == "redrawn":
        x0, y0, x1, y1 = stats["bounds"]
        if x0 < 1 or y0 < 1 or x1 > image.width - 1 or y1 != image.height - 2:
            raise ValueError(f"Sprite margin/baseline violation: {label}: {stats['bounds']}")
        if stats["colors"] > 24:
            raise ValueError(f"Unexpected palette expansion: {label}: {stats['colors']}")
    if stats["pixel_sha256"] != expected["after_sha256"]:
        raise ValueError(f"Unreviewed sprite pixel change: {label}")
    return stats


def audit(read_bytes, contract):
    cfg = json.loads(read_bytes("tile_config.json"))
    # The installer appends Secronom sheets; it must preserve the entire base config.
    base = dict(cfg)
    base["tiles-new"] = cfg["tiles-new"][:contract["base_block_count"]]
    if canonical_digest(base) != contract["base_config_sha256"]:
        raise ValueError("Unreviewed base tileset mapping/geometry change")
    sheets, refs, capacity = inspect_config(cfg, read_bytes)
    by_name = {sheet["file"]: sheet for sheet in sheets}
    generated = set(contract["generated_files"])
    actual_ids = {}
    all_ids = {}
    for sheet in sheets:
        for tile in sheet["block"].get("tiles", []):
            ids = tile["id"] if isinstance(tile["id"], list) else [tile["id"]]
            for tile_id in ids:
                all_ids.setdefault(tile_id, []).append(sheet["file"])
            for entry in tile_entries(tile):
                for layer in ("fg", "bg"):
                    for index in sprite_refs(entry.get(layer, [])):
                        if index < 0:
                            continue
                        owner = next(s for s in sheets if s["start"] <= index < s["start"] + s["count"])
                        if owner["file"] in generated:
                            actual_ids.setdefault((owner["file"], index - owner["start"]), set()).update(ids)
    duplicates = {key: names for key, names in all_ids.items() if len(names) > 1}
    # Secronom already ships overrides and duplicate definitions.
    # Only the exact existing ID + ordered source-sheet pairs are allowed.
    allowed = contract["existing_packaged_overrides"] if len(sheets) > contract["base_block_count"] else {}
    if duplicates != allowed:
        raise ValueError(f"Unreviewed duplicate top-level tile IDs: {duplicates}")
    images = {name: Image.open(io.BytesIO(read_bytes(name))).convert("RGBA") for name in generated}
    seen = set()
    redrawn = 0
    reviewed_ids = set()
    for cell in contract["cells"]:
        key = cell["file"], cell["cell"]
        if key in seen:
            raise ValueError(f"Duplicate review entry: {key}")
        seen.add(key)
        sheet = by_name[cell["file"]]
        if not 0 <= cell["cell"] < sheet["count"]:
            raise ValueError(f"Review cell out of range: {key}")
        ids = actual_ids.get(key, set())
        if ids != set(cell["ids"]):
            raise ValueError(f"Sprite identity mismatch: {key}")
        reviewed_ids.update(ids)
        if cell["decision"] not in {"redrawn", "retained", "unused-retained"}:
            raise ValueError(f"Unknown review decision: {key}")
        if (cell["decision"] == "unused-retained") != (not ids):
            raise ValueError(f"Incorrect unused-cell classification: {key}")
        if cell["decision"] != "redrawn" and cell["before_sha256"] != cell["after_sha256"]:
            raise ValueError(f"Retained cell changed: {key}")
        x = cell["cell"] % sheet["columns"] * sheet["width"]
        y = cell["cell"] // sheet["columns"] * sheet["height"]
        image = images[cell["file"]].crop((x, y, x + sheet["width"], y + sheet["height"]))
        verify_cell(image, cell)
        redrawn += cell["decision"] == "redrawn"
    expected = {(name, i) for name in generated for i in range(by_name[name]["count"])}
    if seen != expected:
        raise ValueError("Incomplete generated-sprite review ledger")
    return dict(sheets=len(sheets), sprite_capacity=capacity, references=refs,
                reviewed_cells=len(seen), reviewed_ids=len(reviewed_ids), redrawn_cells=redrawn)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, help="Audit the actual built undeadpeople ZIP")
    args = parser.parse_args()
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if args.package:
        with zipfile.ZipFile(args.package) as package:
            result = audit(lambda name: package.read("payload/" + name), contract)
    else:
        result = audit(lambda name: (CONTENT / name).read_bytes(), contract)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

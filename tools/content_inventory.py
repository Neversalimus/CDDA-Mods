#!/usr/bin/env python3
"""Inventory repository-owned content covered by the Deep content audit."""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

import modsuite as suite

ROOT = Path(__file__).resolve().parents[1]

ITEM_TYPES = {
    # Current CDDA unified item schema.
    "ITEM",
    # Keep legacy item kinds visible if an imported mod still contains one.
    "AMMO", "ARMOR", "BATTERY", "BIONIC_ITEM", "BOOK", "COMESTIBLE",
    "ENGINE", "GENERIC", "GUN", "GUNMOD", "MAGAZINE", "PET_ARMOR",
    "TOOL", "TOOL_ARMOR", "WHEEL",
}
RECIPE_TYPES = {"recipe", "uncraft", "practice", "nested_category"}
VEHICLE_TYPES = {
    "vehicle", "vehicle_part", "vehicle_group", "vehicle_placement",
    "vehicle_part_category",
}
OVERMAP_TYPES = {
    "overmap_terrain", "overmap_special", "city_building", "mapgen",
}

GROUPS = {
    "items": ITEM_TYPES,
    "recipes": RECIPE_TYPES,
    "vehicles": VEHICLE_TYPES,
    "overmap": OVERMAP_TYPES,
}


def variant_for(mod: dict, target: str) -> dict:
    rows = [v for v in mod["variants"] if target in v["targets"]]
    if len(rows) != 1:
        raise ValueError(
            f"{mod['id']}: expected one variant for {target}, got {len(rows)}"
        )
    return rows[0]


def rows_from_document(doc):
    if isinstance(doc, list):
        return [row for row in doc if isinstance(row, dict)]
    if isinstance(doc, dict):
        return [doc]
    return []


def display_id(row: dict, rel: str, index: int) -> str:
    for key in ("id", "abstract"):
        value = row.get(key)
        if isinstance(value, str) and value:
            return value
    if row.get("type") in RECIPE_TYPES:
        value = row.get("result")
        if isinstance(value, str) and value:
            return value
    return f"{rel}#{index}"


def scan(target: str) -> dict:
    mods, targets = suite.validate()
    if target not in targets:
        raise ValueError(f"Unknown target: {target}")

    entries = {name: [] for name in GROUPS}
    type_counts = Counter()
    per_component = defaultdict(Counter)

    for mid, mod in sorted(mods.items()):
        if mod["kind"] != "json":
            continue
        variants = [v for v in mod["variants"] if target in v["targets"]]
        if not variants:
            continue
        variant = variant_for(mod, target)
        root = ROOT / "mods" / mid / variant["path"]
        for path in sorted(root.rglob("*.json")):
            doc = suite.read(path)
            rel = path.relative_to(ROOT).as_posix()
            for index, row in enumerate(rows_from_document(doc)):
                typ = row.get("type")
                if not isinstance(typ, str):
                    continue
                type_counts[typ] += 1
                for group, accepted in GROUPS.items():
                    if typ not in accepted:
                        continue
                    entry = {
                        "component": mid,
                        "file": rel,
                        "index": index,
                        "type": typ,
                        "id": display_id(row, rel, index),
                    }
                    entries[group].append(entry)
                    per_component[mid][group] += 1
                    break

    counts = {name: len(values) for name, values in entries.items()}
    for name, count in counts.items():
        if count == 0:
            raise ValueError(f"Content audit inventory is empty for {name}")

    return {
        "schema": 1,
        "target": target,
        "counts": counts,
        "entries": entries,
        "per_component": {
            mid: dict(sorted(values.items()))
            for mid, values in sorted(per_component.items())
        },
        "json_type_counts": dict(sorted(type_counts.items())),
    }


def markdown(report: dict) -> str:
    lines = [
        "# Content exhaustive inventory",
        "",
        f"Target: `{report['target']}`",
        "",
        "| Class | Repository objects |",
        "|---|---:|",
    ]
    for name in ("items", "recipes", "vehicles", "overmap"):
        lines.append(f"| {name} | {report['counts'][name]} |")
    lines += [
        "",
        "## By component",
        "",
        "| Component | Items | Recipes | Vehicles | Overmap |",
        "|---|---:|---:|---:|---:|",
    ]
    for mid, counts in report["per_component"].items():
        lines.append(
            f"| {mid} | {counts.get('items', 0)} | "
            f"{counts.get('recipes', 0)} | {counts.get('vehicles', 0)} | "
            f"{counts.get('overmap', 0)} |"
        )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    report = scan(args.target)
    (out / "inventory.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    md = markdown(report)
    (out / "inventory.md").write_text(md, encoding="utf-8")
    print(md, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

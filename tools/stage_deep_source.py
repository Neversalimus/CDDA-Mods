#!/usr/bin/env python3
"""Stage selected repository JSON mods into an exact CDDA source checkout.

This is intentionally destructive only inside <cdda>/data/mods for the selected
MOD_INFO ids. It never touches saves or the user's installed game.
"""
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def manifests():
    return {
        p.parent.name: read_json(p)
        for p in sorted((ROOT / "mods").glob("*/manifest.json"))
    }


def dependency_closure(mods: dict, requested: list[str]) -> list[str]:
    ordered: list[str] = []
    visiting: set[str] = set()

    def visit(mod_id: str):
        if mod_id in ordered:
            return
        if mod_id in visiting:
            raise ValueError(f"dependency cycle at {mod_id}")
        if mod_id not in mods:
            raise ValueError(f"unknown component: {mod_id}")
        visiting.add(mod_id)
        for dep in mods[mod_id].get("dependencies", []):
            visit(dep)
        visiting.remove(mod_id)
        ordered.append(mod_id)

    for mod_id in requested:
        visit(mod_id)
    return ordered


def variant_for_target(manifest: dict, target: str) -> dict:
    matches = [v for v in manifest["variants"] if target in v.get("targets", [])]
    if len(matches) != 1:
        raise ValueError(
            f"{manifest['id']}: expected exactly one variant for {target}, got {len(matches)}"
        )
    return matches[0]


def mod_info_ids(mod_dir: Path) -> set[str]:
    path = mod_dir / "modinfo.json"
    if not path.is_file():
        return set()
    data = read_json(path)
    rows = data if isinstance(data, list) else [data]
    return {
        row["id"]
        for row in rows
        if isinstance(row, dict)
        and row.get("type") == "MOD_INFO"
        and isinstance(row.get("id"), str)
    }


def requested_from_matrix(matrix_path: Path, suite: str) -> tuple[str, list[str]]:
    matrix = read_json(matrix_path)
    target = matrix["target"]
    suites = matrix["source_suites"]
    if suite == "all":
        requested = sorted({m for row in suites for m in row.get("mods", [])})
    else:
        rows = [row for row in suites if row["id"] == suite]
        if len(rows) != 1:
            raise ValueError(f"unknown source suite: {suite}")
        requested = list(rows[0].get("mods", []))
    return target, requested


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdda-root", required=True)
    ap.add_argument("--matrix", required=True)
    ap.add_argument("--suite", default="all")
    args = ap.parse_args()

    cdda = Path(args.cdda_root).resolve()
    matrix_path = Path(args.matrix).resolve()
    if not (cdda / "data" / "mods").is_dir():
        raise ValueError(f"not a CDDA source checkout: {cdda}")

    target, requested = requested_from_matrix(matrix_path, args.suite)
    mods = manifests()
    chosen = dependency_closure(mods, requested)
    chosen = [mid for mid in chosen if mods[mid]["kind"] == "json"]

    game_ids = {
        game_id
        for mid in chosen
        for game_id in mods[mid].get("game_mod_ids", [])
    }

    # Remove any upstream copy with the same MOD_INFO id before staging ours.
    mods_root = cdda / "data" / "mods"
    for child in list(mods_root.iterdir()):
        if not child.is_dir():
            continue
        if mod_info_ids(child) & game_ids:
            shutil.rmtree(child)

    staged = []
    for mid in chosen:
        manifest = mods[mid]
        variant = variant_for_target(manifest, target)
        source = ROOT / "mods" / mid / variant["path"]
        dest = mods_root / manifest["folder"]
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(source, dest)
        staged.append(
            {
                "component": mid,
                "folder": manifest["folder"],
                "game_mod_ids": manifest["game_mod_ids"],
                "variant": variant["id"],
                "version": variant["version"],
                "revision": variant["revision"],
            }
        )

    print(json.dumps({"target": target, "staged": staged}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

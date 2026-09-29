#!/usr/bin/env python3
"""Download the exact official CDDA Windows release bound to a catalog target."""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
API = "https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases/tags/"


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def request_json(url: str, token: str | None):
    headers = {"User-Agent": "CDDA-Mods-deep-runtime"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(
        urllib.request.Request(url, headers=headers), timeout=60
    ) as response:
        return json.load(response)


def choose_asset(assets: list[dict]) -> dict:
    candidates = []
    for asset in assets:
        name = asset.get("name", "")
        low = name.lower()
        if not low.endswith(".zip"):
            continue
        if any(
            marker in low
            for marker in ("symbols", "source", "android", "osx", "linux")
        ):
            continue
        score = 0
        if "windows-with-graphics-x64" in low:
            score += 100
        if "windows" in low:
            score += 20
        if "graphics" in low or "tiles" in low:
            score += 20
        if "x64" in low or "x86_64" in low:
            score += 20
        if "sounds" in low:
            score -= 5
        if score:
            candidates.append((score, name, asset))
    if not candidates:
        names = ", ".join(asset.get("name", "?") for asset in assets)
        raise ValueError(
            "No Windows x64 graphical ZIP found. "
            f"Release assets: {names}"
        )
    candidates.sort(key=lambda row: (-row[0], row[1]))
    return candidates[0][2]


def download(url: str, path: Path, token: str | None):
    headers = {"User-Agent": "CDDA-Mods-deep-runtime"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=120) as src, path.open(
        "wb"
    ) as dst:
        shutil.copyfileobj(src, dst)


def find_root(out: Path) -> Path:
    roots = []
    for version in out.rglob("VERSION.txt"):
        parent = version.parent
        if any(
            (parent / name).is_file()
            for name in (
                "cataclysm-tiles.exe",
                "cataclysm-tiles.vanilla.exe",
                "cataclysm.exe",
            )
        ):
            roots.append(parent)
    if len(roots) != 1:
        raise ValueError(
            f"Expected one extracted game root, found {len(roots)}"
        )
    return roots[0]


def verify_commit(root: Path, expected: str):
    text = (root / "VERSION.txt").read_text(
        encoding="utf-8", errors="replace"
    )
    match = re.search(r"commit sha:\s*([0-9a-f]{40})", text, re.I)
    if not match:
        raise ValueError(
            "VERSION.txt does not contain an exact commit SHA"
        )
    actual = match.group(1).lower()
    if actual != expected.lower():
        raise ValueError(
            f"Release commit mismatch: expected {expected}, got {actual}"
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--token", default=None)
    args = parser.parse_args()

    target_path = (
        ROOT / "catalog" / "targets" / f"{args.target}.json"
    )
    target = read_json(target_path)
    out = Path(args.out).resolve()
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    release = request_json(API + target["tag"], args.token)
    asset = choose_asset(release["assets"])
    archive = out / asset["name"]
    download(asset["browser_download_url"], archive, args.token)

    with zipfile.ZipFile(archive) as bundle:
        bundle.extractall(out / "game")
    archive.unlink()

    root = find_root(out / "game")
    verify_commit(root, target["commit"])

    (out / "game-root.txt").write_text(
        str(root), encoding="utf-8"
    )
    (out / "release.json").write_text(
        json.dumps(
            {
                "target": args.target,
                "tag": target["tag"],
                "commit": target["commit"],
                "asset": asset["name"],
                "game_root": str(root),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(root)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)

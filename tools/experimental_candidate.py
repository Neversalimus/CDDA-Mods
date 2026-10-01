#!/usr/bin/env python3
"""Prepare one CDDA experimental target in a checkout.

Certification jobs use this only in their local checkout.  The same operation
is materialized in main only after every compatibility gate is green.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

TAG_RE = re.compile(
    r"^cdda-experimental-(\d{4})-(\d{2})-(\d{2})-(\d{4})$"
)
COMMIT_RE = re.compile(r"^[0-9a-fA-F]{40}$")


def target_id_from_tag(tag: str) -> str:
    if not TAG_RE.fullmatch(tag):
        raise ValueError(f"Unsupported experimental tag: {tag}")
    return tag.removeprefix("cdda-")


def label_from_tag(tag: str) -> str:
    match = TAG_RE.fullmatch(tag)
    if not match:
        raise ValueError(f"Unsupported experimental tag: {tag}")
    year, month, day, hm = match.groups()
    return f"CDDA experimental {year}-{month}-{day} {hm[:2]}:{hm[2:]}"


def latest_experimental_variant(manifest: dict) -> dict:
    candidates: list[tuple[str, dict]] = []
    for variant in manifest.get("variants", []):
        for target in variant.get("targets", []):
            if isinstance(target, str) and target.startswith("experimental-"):
                candidates.append((target, variant))
    if not candidates:
        raise ValueError(
            f"{manifest.get('id', '<unknown>')}: no experimental variant"
        )
    return max(candidates, key=lambda row: row[0])[1]


def write_json(path: Path, doc: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(doc, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def prepare_candidate(root: Path, tag: str, commit: str) -> dict:
    root = root.resolve()
    target = target_id_from_tag(tag)
    commit = commit.lower()
    if not COMMIT_RE.fullmatch(commit):
        raise ValueError(f"Invalid source commit: {commit}")

    target_path = root / "catalog" / "targets" / f"{target}.json"
    target_doc = {
        "schema": 1,
        "id": target,
        "channel": "experimental",
        "tag": tag,
        "commit": commit,
        "label": label_from_tag(tag),
    }
    if target_path.exists():
        existing = json.loads(target_path.read_text(encoding="utf-8-sig"))
        if existing != target_doc:
            raise ValueError(
                f"Existing target disagrees with candidate: {target_path}"
            )
    else:
        write_json(target_path, target_doc)

    changed: list[str] = []
    manifests = sorted((root / "mods").glob("*/manifest.json"))
    if not manifests:
        raise ValueError("No component manifests found")

    for path in manifests:
        doc = json.loads(path.read_text(encoding="utf-8-sig"))
        variants = doc.get("variants", [])
        if any(target in variant.get("targets", []) for variant in variants):
            continue
        variant = latest_experimental_variant(doc)
        variant.setdefault("targets", []).append(target)
        write_json(path, doc)
        changed.append(path.relative_to(root).as_posix())

    return {
        "schema": 1,
        "target": target,
        "tag": tag,
        "commit": commit,
        "target_path": target_path.relative_to(root).as_posix(),
        "changed_manifests": changed,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        default=str(Path(__file__).resolve().parents[1]),
    )
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--out")
    args = parser.parse_args()

    report = prepare_candidate(Path(args.root), args.tag, args.commit)
    rendered = json.dumps(report, indent=2, ensure_ascii=False)
    print(rendered)
    if args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(rendered + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

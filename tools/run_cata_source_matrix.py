#!/usr/bin/env python3
"""Run CDDA's own cata_test against this repository's staged JSON mods.

Every non-[nogame] cata_test invocation initializes game data, creates a test
world and avatar, loads the map, and tears the world down afterward. This gives
us a real engine/world/character lifecycle rather than a JSON parser check.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

import stage_deep_source as stage


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def variant_for_target(manifest: dict, target: str) -> dict:
    rows = [v for v in manifest["variants"] if target in v.get("targets", [])]
    if len(rows) != 1:
        raise ValueError(
            f"{manifest['id']}: expected exactly one variant for {target}, got {len(rows)}"
        )
    return rows[0]


def game_mod_ids(mods: dict, requested: list[str], target: str) -> list[str]:
    result: list[str] = []
    for mid in stage.dependency_closure(mods, requested):
        manifest = mods[mid]
        if manifest["kind"] != "json":
            continue
        variant_for_target(manifest, target)
        for game_id in manifest.get("game_mod_ids", []):
            if game_id not in result:
                result.append(game_id)
    return result


def run_one(
    exe: Path,
    cdda_root: Path,
    out: Path,
    user_root: Path,
    suite_id: str,
    index: int,
    filt: dict,
    mod_ids: list[str],
) -> dict:
    run_id = f"{suite_id}-{index:02d}"
    log_dir = out / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    user_dir = user_root / run_id
    user_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        str(exe),
        "--error-format",
        "github-action",
        "--rng-seed",
        "424242",
        "--user-dir",
        str(user_dir),
    ]
    if mod_ids:
        cmd.append("--mods=" + ",".join(mod_ids))
    fuzz = int(filt.get("rng_seed_fuzz", 0) or 0)
    if fuzz > 1:
        cmd += ["--rng-seed-fuzz", str(fuzz)]
    cmd.append(filt["expr"])

    stdout_path = log_dir / f"{run_id}.stdout.log"
    stderr_path = log_dir / f"{run_id}.stderr.log"
    timeout = int(filt.get("timeout_seconds", 3600))
    code = 124
    timed_out = False
    with stdout_path.open("w", encoding="utf-8", errors="replace") as stdout, stderr_path.open(
        "w", encoding="utf-8", errors="replace"
    ) as stderr:
        proc = subprocess.Popen(cmd, cwd=cdda_root, stdout=stdout, stderr=stderr)
        try:
            code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            proc.kill()
            proc.wait()
            stderr.write(f"\nDeep runtime timeout after {timeout} seconds.\n")

    return {
        "id": run_id,
        "suite": suite_id,
        "filter": filt["expr"],
        "mods": mod_ids,
        "rng_seed": 424242,
        "rng_seed_fuzz": fuzz,
        "timeout_seconds": timeout,
        "timed_out": timed_out,
        "exit_code": code,
        "stdout": str(stdout_path.relative_to(out)),
        "stderr": str(stderr_path.relative_to(out)),
        "command": cmd,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdda-root", required=True)
    ap.add_argument("--matrix", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--suite", default="all")
    args = ap.parse_args()

    cdda_root = Path(args.cdda_root).resolve()
    matrix_path = Path(args.matrix).resolve()
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    user_root = cdda_root / "deep_test_users"
    user_root.mkdir(parents=True, exist_ok=True)

    exe_candidates = [
        cdda_root / "tests" / "cata_test",
        cdda_root / "cata_test",
        cdda_root / "build" / "tests" / "cata_test",
    ]
    exe = next((p for p in exe_candidates if p.is_file()), None)
    if exe is None:
        raise ValueError("cata_test executable not found")

    matrix = read_json(matrix_path)
    target = matrix["target"]
    mods = stage.manifests()
    suites = matrix["source_suites"]
    if args.suite != "all":
        suites = [row for row in suites if row["id"] == args.suite]
        if not suites:
            raise ValueError(f"unknown source suite: {args.suite}")

    report = {
        "schema": 1,
        "target": target,
        "cdda_root": str(cdda_root),
        "cata_test": str(exe),
        "runs": [],
    }
    failures = []
    try:
        for suite in suites:
            ids = game_mod_ids(mods, list(suite.get("mods", [])), target)
            for index, filt in enumerate(suite["filters"], start=1):
                result = run_one(
                    exe,
                    cdda_root,
                    out,
                    user_root,
                    suite["id"],
                    index,
                    filt,
                    ids,
                )
                report["runs"].append(result)
                (out / "report.json").write_text(
                    json.dumps(report, indent=2) + "\n", encoding="utf-8"
                )
                if result["exit_code"] != 0 or result["timed_out"]:
                    failures.append(result["id"])
    finally:
        (out / "report.json").write_text(
            json.dumps(report, indent=2) + "\n", encoding="utf-8"
        )

    print(
        f"Deep cata_test matrix: {len(report['runs'])} run(s), "
        f"{len(failures)} failure(s)."
    )
    if failures:
        print("Failed:", ", ".join(failures))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

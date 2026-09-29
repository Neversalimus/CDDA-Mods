#!/usr/bin/env python3
"""Run CDDA's own cata_test against this repository's JSON mods.

The game checkout is external and must be pinned to catalog/targets/<target>.json.
This script never mutates the mod repository and stages payloads only inside the
throw-away CDDA checkout used by CI.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_hash(root: Path) -> str:
    rows = []
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        rows.append(path.relative_to(root).as_posix() + "\0" + file_hash(path) + "\n")
    return hashlib.sha256("".join(rows).encode()).hexdigest()


def load_manifests(repo: Path):
    result = {}
    for path in sorted((repo / "mods").glob("*/manifest.json")):
        data = read_json(path)
        result[data["id"]] = data
    return result


def variant_for(manifest: dict, target: str) -> dict:
    matches = [v for v in manifest["variants"] if target in v["targets"]]
    if len(matches) != 1:
        raise ValueError(f"{manifest['id']}: expected one variant for {target}, got {len(matches)}")
    return matches[0]


def resolve(manifests: dict, requested: list[str]) -> list[str]:
    ordered: list[str] = []
    visiting: set[str] = set()

    def visit(mod_id: str) -> None:
        if mod_id in ordered:
            return
        if mod_id in visiting:
            raise ValueError(f"dependency cycle at {mod_id}")
        if mod_id not in manifests:
            raise ValueError(f"unknown component {mod_id}")
        visiting.add(mod_id)
        for dep in manifests[mod_id].get("dependencies", []):
            visit(dep)
        visiting.remove(mod_id)
        ordered.append(mod_id)

    for mod_id in requested:
        visit(mod_id)
    return ordered


def mod_info_ids(path: Path) -> set[str]:
    data = read_json(path)
    records = data if isinstance(data, list) else [data]
    return {
        row["id"]
        for row in records
        if isinstance(row, dict) and row.get("type") == "MOD_INFO" and row.get("id")
    }


def find_existing_mod_ids(game: Path, wanted: set[str]) -> dict[str, list[str]]:
    found = {x: [] for x in wanted}
    for info in (game / "data" / "mods").rglob("modinfo.json"):
        try:
            ids = mod_info_ids(info)
        except (OSError, ValueError, json.JSONDecodeError):
            continue
        for mod_id in ids & wanted:
            found[mod_id].append(str(info))
    return {k: v for k, v in found.items() if v}


def stage(repo: Path, game: Path, target: str, manifests: dict, requested: list[str]) -> tuple[list[str], dict]:
    selected = resolve(manifests, requested)
    for mod_id in selected:
        if manifests[mod_id]["kind"] != "json":
            raise ValueError(f"{mod_id}: real source-runtime harness accepts JSON mods only")

    game_ids = {
        gid
        for mod_id in selected
        for gid in manifests[mod_id].get("game_mod_ids", [])
    }
    duplicates = find_existing_mod_ids(game, game_ids)
    if duplicates:
        raise ValueError("target CDDA already contains colliding mod IDs: " + json.dumps(duplicates))

    evidence = {}
    for mod_id in selected:
        manifest = manifests[mod_id]
        variant = variant_for(manifest, target)
        source = (repo / "mods" / mod_id / variant["path"]).resolve()
        if not source.is_dir():
            raise ValueError(f"{mod_id}: missing payload {source}")
        destination = game / "data" / "mods" / ("zz_neversalimus_" + mod_id)
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(source, destination)
        evidence[mod_id] = {
            "variant": variant["id"],
            "version": variant["version"],
            "revision": variant["revision"],
            "content_sha256": tree_hash(source),
            "game_mod_ids": manifest["game_mod_ids"],
        }

    ordered_game_ids = []
    for mod_id in selected:
        for gid in manifests[mod_id]["game_mod_ids"]:
            if gid not in ordered_game_ids:
                ordered_game_ids.append(gid)
    return ordered_game_ids, evidence


def run_one(exe: Path, game: Path, selector: str, game_ids: list[str], userdir: Path,
            logdir: Path, timeout: int) -> dict:
    userdir.mkdir(parents=True, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", selector).strip("_") or "selector"
    command = [str(exe), selector, f"--user-dir={userdir}"]
    if game_ids:
        command.append("--mods=" + ",".join(game_ids))
    started = time.monotonic()
    try:
        proc = subprocess.run(
            command,
            cwd=game,
            text=True,
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
        code = proc.returncode
        stdout = proc.stdout
        stderr = proc.stderr
        timed_out = False
    except subprocess.TimeoutExpired as exc:
        code = 124
        stdout = exc.stdout.decode(errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode(errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        stderr += f"\nTIMEOUT after {timeout}s\n"
        timed_out = True

    duration = round(time.monotonic() - started, 3)
    logdir.mkdir(parents=True, exist_ok=True)
    (logdir / f"{safe}.stdout.log").write_text(stdout, encoding="utf-8")
    (logdir / f"{safe}.stderr.log").write_text(stderr, encoding="utf-8")
    debug_logs = []
    for debug in userdir.rglob("debug.log"):
        copied = logdir / f"{safe}.{len(debug_logs)}.debug.log"
        shutil.copy2(debug, copied)
        debug_logs.append(str(copied))
    return {
        "selector": selector,
        "command": command,
        "exit_code": code,
        "timed_out": timed_out,
        "duration_seconds": duration,
        "debug_logs": debug_logs,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--game", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--case", required=True, help="baseline, component:<id>, or profile:<name>")
    parser.add_argument("--scope", choices=("smoke", "deep", "exhaustive"), default="deep")
    parser.add_argument("--out", required=True)
    parser.add_argument("--test-exe")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    game = Path(args.game).resolve()
    out = Path(args.out).resolve()
    plan = read_json(repo / "catalog" / "runtime-tests.json")
    target = read_json(repo / "catalog" / "targets" / f"{args.target}.json")
    if args.target != target["id"]:
        raise ValueError("target id/path mismatch")

    game_sha = subprocess.check_output(
        ["git", "-C", str(game), "rev-parse", "HEAD"], text=True
    ).strip().lower()
    if game_sha != target["commit"].lower():
        raise ValueError(f"CDDA checkout mismatch: {game_sha} != {target['commit']}")

    exe = Path(args.test_exe).resolve() if args.test_exe else game / "tests" / "cata_test"
    if not exe.is_file():
        raise ValueError(f"cata_test missing: {exe}")

    manifests = load_manifests(repo)
    requested: list[str] = []
    if args.case == "baseline":
        label = "baseline"
    elif args.case.startswith("component:"):
        mod_id = args.case.split(":", 1)[1]
        configured = plan["source_runtime"]["components"]
        if mod_id not in configured:
            raise ValueError(f"component not enabled for deep runtime: {mod_id}")
        requested = [mod_id]
        label = mod_id
    elif args.case.startswith("profile:"):
        profile = args.case.split(":", 1)[1]
        profiles = plan["source_runtime"]["profiles"]
        if profile not in profiles:
            raise ValueError(f"unknown runtime profile: {profile}")
        requested = list(profiles[profile])
        label = profile
    else:
        raise ValueError(f"invalid case: {args.case}")

    game_ids: list[str] = []
    evidence = {}
    if requested:
        game_ids, evidence = stage(repo, game, args.target, manifests, requested)

    selectors = plan["source_runtime"]["selectors"][args.scope]
    timeout = int(plan["source_runtime"]["per_selector_timeout_seconds"])
    results = []
    for index, selector in enumerate(selectors, 1):
        result = run_one(
            exe,
            game,
            selector,
            game_ids,
            out / "user" / f"{index:02d}",
            out / "logs",
            timeout,
        )
        results.append(result)

    report = {
        "schema": 1,
        "target": args.target,
        "target_commit": target["commit"],
        "observed_game_commit": game_sha,
        "case": args.case,
        "scope": args.scope,
        "requested_components": requested,
        "game_mod_ids": game_ids,
        "content": evidence,
        "results": results,
        "passed": all(r["exit_code"] == 0 for r in results),
    }
    write_json(out / "report.json", report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)

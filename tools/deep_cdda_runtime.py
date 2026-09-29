#!/usr/bin/env python3
"""Deep runtime checks for the JSON/content side of CDDA-Mods.

This intentionally does not test NCMM/native modules. It can:
* stage the repository's JSON mods into an exact CDDA source checkout;
* run the official release executable against each mod/profile/combined stack;
* run CDDA's own cata_test binary with those mods loaded.

Reports are content-hash bound so old evidence cannot silently certify changed payloads.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import modsuite as suite

ROOT = Path(__file__).resolve().parents[1]
ERROR_RE = re.compile(
    r"\(json-error\)|ERROR\s*:|Error loading|Unknown mod:|Missing dependencies:|Fatal:|timed out",
    re.I,
)


def target_variant(mod: dict, target: str) -> dict:
    matches = [v for v in mod["variants"] if target in v["targets"]]
    if len(matches) != 1:
        raise ValueError(
            f"{mod['id']}: expected exactly one variant for {target}, got {len(matches)}"
        )
    return matches[0]


def json_components(target: str) -> dict[str, dict]:
    mods, targets = suite.validate()
    if target not in targets:
        raise ValueError(f"Unknown target: {target}")
    return {
        mid: mod
        for mid, mod in mods.items()
        if mod["kind"] == "json"
        and any(target in v["targets"] for v in mod["variants"])
    }


def closure(mods: dict[str, dict], ids: list[str]) -> list[str]:
    out: list[str] = []

    def visit(mid: str) -> None:
        if mid in out:
            return
        if mid not in mods:
            raise ValueError(
                f"Selected JSON component depends on unavailable component: {mid}"
            )
        for dep in mods[mid]["dependencies"]:
            visit(dep)
        out.append(mid)

    for mid in ids:
        visit(mid)
    return out


def game_ids_for(mods: dict[str, dict], ids: list[str]) -> list[str]:
    ordered = closure(mods, ids)
    result = ["dda"]
    for mid in ordered:
        for game_id in mods[mid]["game_mod_ids"]:
            if game_id not in result:
                result.append(game_id)
    return result


def build_suites(target: str) -> tuple[dict[str, dict], list[dict]]:
    mods = json_components(target)
    rows: list[dict] = []

    for mid in sorted(mods):
        ids = closure(mods, [mid])
        rows.append(
            {
                "name": f"component-{mid}",
                "components": ids,
                "game_mod_ids": game_ids_for(mods, ids),
            }
        )

    profiles = suite.read(ROOT / "catalog/repository.json").get("profiles", {})
    for name, profile_ids in sorted(profiles.items()):
        selected = [mid for mid in profile_ids if mid in mods]
        if not selected:
            continue
        ids = closure(mods, selected)
        row = {
            "name": f"profile-{name}",
            "components": ids,
            "game_mod_ids": game_ids_for(mods, ids),
        }
        if not any(
            existing["game_mod_ids"] == row["game_mod_ids"] for existing in rows
        ):
            rows.append(row)

    all_ids = closure(mods, sorted(mods))
    combined = {
        "name": "combined-all-json",
        "components": all_ids,
        "game_mod_ids": game_ids_for(mods, all_ids),
    }
    if not any(
        existing["game_mod_ids"] == combined["game_mod_ids"] for existing in rows
    ):
        rows.append(combined)

    for row in rows:
        row["content_sha256"] = {
            mid: suite.tree_hash(
                ROOT / "mods" / mid / target_variant(mods[mid], target)["path"]
            )
            for mid in row["components"]
        }
    return mods, rows


def copy_json_mods(target: str, destination_mods: Path) -> dict[str, dict]:
    mods = json_components(target)
    destination_mods.mkdir(parents=True, exist_ok=True)
    for mid, mod in mods.items():
        variant = target_variant(mod, target)
        src = ROOT / "mods" / mid / variant["path"]
        dst = destination_mods / mod["folder"]
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    return mods


def find_game_exe(game: Path) -> Path:
    candidates = (
        "cataclysm-tiles.vanilla.exe",
        "cataclysm-tiles.exe",
        "cataclysm.exe",
        "cataclysm",
        "cataclysm-tiles",
    )
    for name in candidates:
        p = game / name
        if p.is_file():
            return p
    for name in candidates:
        hits = list(game.rglob(name))
        if hits:
            return hits[0]
    raise ValueError("CDDA executable not found")


def exact_commit(game: Path) -> str:
    version = game / "VERSION.txt"
    if not version.is_file():
        hits = list(game.rglob("VERSION.txt"))
        if len(hits) != 1:
            raise ValueError("VERSION.txt missing or ambiguous")
        version = hits[0]
    text = version.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"commit sha:\s*([0-9a-f]{40})", text, re.I)
    if not match:
        raise ValueError("VERSION.txt does not contain an exact commit SHA")
    return match.group(1).lower()


def run_process(args: list[str], cwd: Path, log_dir: Path, timeout: int) -> dict:
    log_dir.mkdir(parents=True, exist_ok=True)
    try:
        proc = subprocess.run(
            args,
            cwd=cwd,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
        )
        code = proc.returncode
        stdout = proc.stdout
        stderr = proc.stderr
    except subprocess.TimeoutExpired as exc:
        code = 124
        stdout = (
            exc.stdout.decode(errors="replace")
            if isinstance(exc.stdout, bytes)
            else (exc.stdout or "")
        )
        stderr = (
            exc.stderr.decode(errors="replace")
            if isinstance(exc.stderr, bytes)
            else (exc.stderr or "")
        )
        stderr += "\nTimed out.\n"
    (log_dir / "stdout.log").write_text(stdout, encoding="utf-8")
    (log_dir / "stderr.log").write_text(stderr, encoding="utf-8")
    return {
        "exit_code": code,
        "errors": [
            line
            for line in (stdout + "\n" + stderr).splitlines()
            if ERROR_RE.search(line)
        ],
        "command": args,
    }


def run_release(game_root: Path, target: str, out: Path, timeout: int) -> dict:
    _, targets = suite.validate()
    if target not in targets:
        raise ValueError(f"Unknown target: {target}")
    target_info = targets[target]
    game_root = game_root.resolve()
    if exact_commit(game_root) != target_info["commit"]:
        raise ValueError(
            "Downloaded CDDA binary does not match catalog target commit"
        )
    exe = find_game_exe(game_root)
    _, rows = build_suites(target)
    out.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="cdda-mods-deep-release-") as temp:
        data = Path(temp) / "data"
        shutil.copytree(
            game_root / "data",
            data,
            ignore=shutil.ignore_patterns("cache", "gfx"),
        )
        if (game_root / "gfx").is_dir():
            shutil.copytree(game_root / "gfx", data / "gfx")
        copy_json_mods(target, data / "mods")

        def check(name: str, game_ids: list[str]) -> dict:
            user = out / name / "user"
            user.mkdir(parents=True, exist_ok=True)
            args = [
                str(exe),
                "--basepath",
                str(game_root) + "/",
                "--datadir",
                str(data) + "/",
                "--userdir",
                str(user) + "/",
                "--seed",
                "CDDA_MODS_DEEP_RUNTIME",
                "--check-mods",
                *game_ids,
            ]
            result = run_process(args, game_root, out / name, timeout)
            debug = "\n".join(
                p.read_text(encoding="utf-8", errors="replace")
                for p in user.rglob("debug.log")
            )
            extra = [line for line in debug.splitlines() if ERROR_RE.search(line)]
            result["errors"] = sorted(set(result["errors"] + extra))
            return result

        baseline = check("baseline-dda", ["dda"])
        results = []
        if baseline["exit_code"] == 0 and not baseline["errors"]:
            for row in rows:
                result = check(row["name"], row["game_mod_ids"])
                results.append({**row, "result": result})

        report = {
            "schema": 2,
            "kind": "release-binary",
            "target": target,
            "commit": target_info["commit"],
            "baseline": baseline,
            "suites": results,
        }
        suite.write(out / "report.json", report)

    failures = []
    if baseline["exit_code"] or baseline["errors"]:
        failures.append("baseline-dda")
    failures.extend(
        row["name"]
        for row in results
        if row["result"]["exit_code"] or row["result"]["errors"]
    )
    if failures:
        raise RuntimeError(
            "Release-binary deep checks failed: " + ", ".join(failures)
        )
    return report


def run_installed(
    game_root: Path,
    target: str,
    game_mod_ids: list[str],
    out: Path,
    timeout: int,
) -> dict:
    """Validate mods that are already installed into a real game tree."""
    _, targets = suite.validate()
    if target not in targets:
        raise ValueError(f"Unknown target: {target}")
    target_info = targets[target]
    game_root = game_root.resolve()
    if exact_commit(game_root) != target_info["commit"]:
        raise ValueError(
            "Installed CDDA binary does not match catalog target commit"
        )
    exe = find_game_exe(game_root)
    user = out / "user"
    user.mkdir(parents=True, exist_ok=True)
    ids = ["dda"] + [
        mid for mid in game_mod_ids if mid and mid != "dda"
    ]
    args = [
        str(exe),
        "--basepath",
        str(game_root) + "/",
        "--datadir",
        str(game_root / "data") + "/",
        "--userdir",
        str(user) + "/",
        "--seed",
        "CDDA_MODS_INSTALL_MATRIX",
        "--check-mods",
        *ids,
    ]
    result = run_process(args, game_root, out, timeout)
    debug = "\n".join(
        p.read_text(encoding="utf-8", errors="replace")
        for p in user.rglob("debug.log")
    )
    result["errors"] = sorted(
        set(
            result["errors"]
            + [
                line
                for line in debug.splitlines()
                if ERROR_RE.search(line)
            ]
        )
    )
    report = {
        "schema": 1,
        "kind": "installed-game-check",
        "target": target,
        "commit": target_info["commit"],
        "mods": ids,
        "result": result,
    }
    suite.write(out / "report.json", report)
    if result["exit_code"] or result["errors"]:
        raise RuntimeError(
            "Installed-game validation failed for: " + ", ".join(ids)
        )
    return report


def stage_source(cdda_root: Path, target: str) -> None:
    data_mods = cdda_root / "data" / "mods"
    if not data_mods.is_dir():
        raise ValueError(f"Not a CDDA source checkout: {cdda_root}")
    copy_json_mods(target, data_mods)


def find_cata_test(cdda_root: Path) -> Path:
    candidates = [
        cdda_root / "tests" / "cata_test",
        cdda_root / "build" / "tests" / "cata_test",
        cdda_root / "tests" / "cata_test.exe",
        cdda_root / "build" / "tests" / "cata_test.exe",
    ]
    for p in candidates:
        if p.is_file():
            return p
    raise ValueError(
        "cata_test not found; build the exact CDDA source first"
    )


def source_specs(depth: str, combined: bool) -> list[str]:
    specs = ["[force_load_game]"]
    if depth in ("full", "exhaustive"):
        specs.append("~[slow] ~[.]")
    if depth == "exhaustive" and combined:
        specs.extend(
            ["[slow] ~crafting_skill_gain", "crafting_skill_gain"]
        )
    return specs


def run_source(
    cdda_root: Path,
    target: str,
    out: Path,
    depth: str,
    timeout: int,
) -> dict:
    _, targets = suite.validate()
    if target not in targets:
        raise ValueError(f"Unknown target: {target}")
    target_info = targets[target]
    cdda_root = cdda_root.resolve()
    stage_source(cdda_root, target)
    test_bin = find_cata_test(cdda_root)
    _, rows = build_suites(target)
    out.mkdir(parents=True, exist_ok=True)

    runs = []
    for row in rows:
        combined = row["name"] == "combined-all-json"
        mod_arg = ",".join(row["game_mod_ids"])
        for index, spec in enumerate(source_specs(depth, combined)):
            safe_spec = (
                re.sub(r"[^A-Za-z0-9_.-]+", "_", spec).strip("_")
                or "spec"
            )
            log_dir = out / row["name"] / f"{index:02d}-{safe_spec}"
            userdir = log_dir / "user"
            args = [
                str(test_bin),
                f"--mods={mod_arg}",
                f"--user-dir={userdir}",
                "--rng-seed",
                "0",
                "--order",
                "lex",
                "--error-format=github-action",
                spec,
            ]
            result = run_process(args, cdda_root, log_dir, timeout)
            runs.append(
                {
                    "suite": row["name"],
                    "components": row["components"],
                    "content_sha256": row["content_sha256"],
                    "mods": row["game_mod_ids"],
                    "spec": spec,
                    "result": result,
                }
            )

    report = {
        "schema": 2,
        "kind": "source-cata-test",
        "depth": depth,
        "target": target,
        "commit": target_info["commit"],
        "runs": runs,
    }
    suite.write(out / "report.json", report)
    failed = [
        f"{r['suite']}::{r['spec']}"
        for r in runs
        if r["result"]["exit_code"]
    ]
    if failed:
        raise RuntimeError(
            "Source runtime tests failed: " + ", ".join(failed)
        )
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    plan = sub.add_parser("plan")
    plan.add_argument("--target", required=True)

    stage = sub.add_parser("stage-source")
    stage.add_argument("--cdda-root", required=True)
    stage.add_argument("--target", required=True)

    release = sub.add_parser("run-release")
    release.add_argument("--game-root", required=True)
    release.add_argument("--target", required=True)
    release.add_argument("--out", required=True)
    release.add_argument("--timeout", type=int, default=600)

    installed = sub.add_parser("run-installed")
    installed.add_argument("--game-root", required=True)
    installed.add_argument("--target", required=True)
    installed.add_argument("--mods", required=True)
    installed.add_argument("--out", required=True)
    installed.add_argument("--timeout", type=int, default=600)

    source = sub.add_parser("run-source")
    source.add_argument("--cdda-root", required=True)
    source.add_argument("--target", required=True)
    source.add_argument("--out", required=True)
    source.add_argument(
        "--depth",
        choices=("load", "full", "exhaustive"),
        default="full",
    )
    source.add_argument("--timeout", type=int, default=7200)

    args = parser.parse_args()
    if args.command == "plan":
        _, rows = build_suites(args.target)
        print(json.dumps(rows, ensure_ascii=False, indent=2))
    elif args.command == "stage-source":
        stage_source(Path(args.cdda_root), args.target)
    elif args.command == "run-release":
        run_release(
            Path(args.game_root),
            args.target,
            Path(args.out),
            args.timeout,
        )
    elif args.command == "run-installed":
        run_installed(
            Path(args.game_root),
            args.target,
            [mid.strip() for mid in args.mods.split(",") if mid.strip()],
            Path(args.out),
            args.timeout,
        )
    elif args.command == "run-source":
        run_source(
            Path(args.cdda_root),
            args.target,
            Path(args.out),
            args.depth,
            args.timeout,
        )


if __name__ == "__main__":
    try:
        main()
    except (
        AssertionError,
        ValueError,
        KeyError,
        OSError,
        RuntimeError,
        subprocess.SubprocessError,
    ) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)

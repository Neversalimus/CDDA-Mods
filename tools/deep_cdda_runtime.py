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
import hashlib
import json
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import unquote

import modsuite as suite

ROOT = Path(__file__).resolve().parents[1]
ERROR_RE = re.compile(
    r"\(json-error\)|ERROR\s*:|Error loading|Unknown mod:|Missing dependencies:|Fatal:|timed out",
    re.I,
)
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
STYLE_ANNOTATION_RE = re.compile(
    r"::error file=([^,]+),line=(\d+),col=(\d+)::(.*)"
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


def declared_game_dependencies(mod: dict, target: str) -> dict[str, list[str]]:
    """Read MOD_INFO dependencies for every game mod ID owned by a component."""
    variant = target_variant(mod, target)
    modinfo = suite.read(
        ROOT / "mods" / mod["id"] / variant["path"] / "modinfo.json"
    )
    rows = modinfo if isinstance(modinfo, list) else [modinfo]
    wanted = set(mod["game_mod_ids"])
    found: dict[str, list[str]] = {}
    for row in rows:
        if not isinstance(row, dict) or row.get("type") != "MOD_INFO":
            continue
        game_id = row.get("id")
        if game_id in wanted:
            found[game_id] = list(row.get("dependencies", []))
    missing = wanted - set(found)
    if missing:
        raise ValueError(
            f"{mod['id']}: MOD_INFO missing declared game ids: {sorted(missing)}"
        )
    return found


def game_ids_for(
    mods: dict[str, dict], ids: list[str], target: str
) -> list[str]:
    """Build dependency-complete game-mod order for check-mods/cata_test.

    Repository manifests describe package dependencies. MOD_INFO can additionally
    depend on game-shipped mods which are deliberately not packages in this repo,
    e.g. Mind Over Matter. Those IDs still have to precede our compatibility mod
    in the explicit runtime selection.
    """
    ordered_components = closure(mods, ids)
    game_to_component = {
        game_id: mid
        for mid, mod in mods.items()
        for game_id in mod["game_mod_ids"]
    }
    deps_by_game: dict[str, list[str]] = {}
    for mid in ordered_components:
        deps_by_game.update(declared_game_dependencies(mods[mid], target))

    result: list[str] = []
    visiting: set[str] = set()

    def add_game(game_id: str) -> None:
        if game_id in result:
            return
        if game_id in visiting:
            raise ValueError(f"Game mod dependency cycle at {game_id}")
        visiting.add(game_id)

        owner = game_to_component.get(game_id)
        if owner is not None and owner not in ordered_components:
            for dep_mid in closure(mods, [owner]):
                if dep_mid not in ordered_components:
                    ordered_components.append(dep_mid)
                    deps_by_game.update(
                        declared_game_dependencies(mods[dep_mid], target)
                    )

        for dep in deps_by_game.get(game_id, []):
            add_game(dep)

        visiting.remove(game_id)
        if game_id not in result:
            result.append(game_id)

    add_game("dda")
    for mid in ordered_components:
        for game_id in mods[mid]["game_mod_ids"]:
            add_game(game_id)
    return result


def direct_game_ids(mods: dict[str, dict], ids: list[str]) -> list[str]:
    """Return only game mod IDs directly owned by the selected components."""
    result: list[str] = []
    for mid in ids:
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
                "game_mod_ids": game_ids_for(mods, ids, target),
                "check_mod_ids": direct_game_ids(mods, [mid]),
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
            "game_mod_ids": game_ids_for(mods, ids, target),
            "check_mod_ids": direct_game_ids(mods, selected),
        }
        if not any(
            existing["game_mod_ids"] == row["game_mod_ids"] for existing in rows
        ):
            rows.append(row)

    all_ids = closure(mods, sorted(mods))
    combined = {
        "name": "combined-all-json",
        "components": all_ids,
        "game_mod_ids": game_ids_for(mods, all_ids, target),
        "check_mod_ids": direct_game_ids(mods, sorted(mods)),
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


def copy_json_mods(
    target: str,
    destination_mods: Path,
    component_ids: list[str] | None = None,
) -> dict[str, dict]:
    mods = json_components(target)
    selected = (
        closure(mods, component_ids)
        if component_ids is not None
        else sorted(mods)
    )
    destination_mods.mkdir(parents=True, exist_ok=True)
    for mid in selected:
        mod = mods[mid]
        variant = target_variant(mod, target)
        src = ROOT / "mods" / mid / variant["path"]
        dst = destination_mods / mod["folder"]
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    return {mid: mods[mid] for mid in selected}


def clear_repository_json_mods(target: str, destination_mods: Path) -> None:
    """Remove only this repository's staged JSON mod folders from a CDDA tree."""
    for mod in json_components(target).values():
        staged = destination_mods / mod["folder"]
        if staged.exists():
            shutil.rmtree(staged)


def classify_debug_errors(debug: str) -> tuple[list[str], list[str]]:
    """Split advisory CDDA text-style diagnostics from real loader errors.

    Prefer the stable GitHub annotation emitted immediately after a text-style
    header. Timestamps in the header are intentionally discarded so warning
    fingerprints remain comparable across otherwise identical runs.
    """
    style: list[str] = []
    fatal: list[str] = []
    lines = debug.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        if "ERROR :" not in line:
            index += 1
            continue
        if "text_style_check_reader.cpp:63" in line:
            normalized = None
            if index + 1 < len(lines):
                annotation = ANSI_RE.sub("", lines[index + 1]).strip()
                match = STYLE_ANNOTATION_RE.search(annotation)
                if match:
                    message = unquote(match.group(4)).splitlines()[0].strip()
                    normalized = (
                        f"{match.group(1)}:{match.group(2)}:{match.group(3)}: "
                        f"{message}"
                    )
            style.append(normalized or "text_style_check_reader.cpp:63")
            index += 1
            continue
        if "(error message will follow backtrace)" in line:
            # debugmsg emits this generic prelude before the source-bearing line.
            index += 1
            continue
        fatal.append(line)
        index += 1
    return sorted(set(style)), sorted(set(fatal))


def game_mod_index(data_root: Path) -> dict[str, dict]:
    """Index game mods in one data tree for validator capability checks."""
    result: dict[str, dict] = {}
    mods_root = data_root / "mods"
    if not mods_root.is_dir():
        return result
    for info in mods_root.rglob("modinfo.json"):
        try:
            doc = json.loads(info.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError):
            continue
        rows = doc if isinstance(doc, list) else [doc]
        for row in rows:
            if not isinstance(row, dict) or row.get("type") != "MOD_INFO":
                continue
            game_id = row.get("id")
            if not isinstance(game_id, str) or not game_id:
                continue
            result[game_id] = {
                "root": info.parent,
                "dependencies": [
                    dep for dep in row.get("dependencies", [])
                    if isinstance(dep, str) and dep
                ],
            }
    return result


def check_mods_interaction_hazards(data_root: Path, root_id: str) -> list[str]:
    """Return interaction-bearing mods reachable from one game-mod root.

    Older CDDA --check-mods implementations can load dependency mod_interactions
    through the generic recursive loader.  Capability probing decides whether
    those graphs must be deferred; this function only identifies the exposure.
    """
    index = game_mod_index(data_root)
    seen: set[str] = set()
    stack = [root_id]
    hazards: list[str] = []
    while stack:
        game_id = stack.pop()
        if game_id in seen:
            continue
        seen.add(game_id)
        meta = index.get(game_id)
        if meta is None:
            continue
        interactions = meta["root"] / "mod_interactions"
        if interactions.is_dir() and any(interactions.rglob("*.json")):
            hazards.append(game_id)
        stack.extend(meta["dependencies"])
    return sorted(set(hazards))


def deferred_check_mods_result(game_id: str, hazards: list[str]) -> dict:
    return {
        "exit_code": 0,
        "raw_exit_code": None,
        "errors": [],
        "style_warnings": [],
        "debug_logs": [],
        "command": None,
        "deferred": True,
        "deferred_to": "exact-source-cata_test",
        "validator_limitation": "upstream-check-mods-mod_interactions",
        "root_mod": game_id,
        "interaction_mods": hazards,
    }

CHECK_MODS_INTERACTION_PROBE_TOKEN = (
    "CDDA_MODS_CHECK_MODS_INTERACTION_PROBE_SENTINEL"
)
CHECK_MODS_INTERACTION_PROBE_DEP = "cdda_mods_probe_interaction_dep"
CHECK_MODS_INTERACTION_PROBE_ROOT = "cdda_mods_probe_interaction_root"


def _write_check_mods_interaction_probe(data_root: Path) -> list[Path]:
    mods_root = data_root / "mods"
    mods_root.mkdir(parents=True, exist_ok=True)
    dep = mods_root / "__cdda_mods_probe_interaction_dep"
    root = mods_root / "__cdda_mods_probe_interaction_root"
    for path in (dep, root):
        if path.exists():
            raise RuntimeError(
                f"Refusing to overwrite validator capability probe path: {path}"
            )

    dep.mkdir(parents=True)
    root.mkdir(parents=True)
    suite.write(
        dep / "modinfo.json",
        {
            "type": "MOD_INFO",
            "id": CHECK_MODS_INTERACTION_PROBE_DEP,
            "name": "CDDA-Mods validator capability dependency",
            "authors": ["CDDA-Mods CI"],
            "description": "Temporary capability probe.",
            "category": "content",
            "dependencies": ["dda"],
        },
    )
    suite.write(
        root / "modinfo.json",
        {
            "type": "MOD_INFO",
            "id": CHECK_MODS_INTERACTION_PROBE_ROOT,
            "name": "CDDA-Mods validator capability root",
            "authors": ["CDDA-Mods CI"],
            "description": "Temporary capability probe.",
            "category": "content",
            "dependencies": ["dda", CHECK_MODS_INTERACTION_PROBE_DEP],
        },
    )
    hidden = dep / "mod_interactions" / "cdda_mods_probe_never_loaded"
    hidden.mkdir(parents=True)
    suite.write(
        hidden / "sentinel.json",
        {
            "type": "snippet",
            "category": "cdda_mods_probe_interaction",
            "text": (
                CHECK_MODS_INTERACTION_PROBE_TOKEN
                + ". single-space sentinel"
            ),
        },
    )
    return [root, dep]


def probe_check_mods_interactions(
    exe: Path,
    game_root: Path,
    data_root: Path,
    out: Path,
    timeout: int = 120,
) -> dict:
    """Detect whether this exact binary handles dependency mod_interactions safely."""
    out = out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    user = out / "user"
    user.mkdir(parents=True, exist_ok=True)
    (user / "config").mkdir(parents=True, exist_ok=True)
    created: list[Path] = []
    try:
        created = _write_check_mods_interaction_probe(data_root)
        args = [
            str(exe),
            "--basepath",
            str(game_root.resolve()) + "/",
            "--datadir",
            str(data_root.resolve()) + "/",
            "--userdir",
            str(user) + "/",
            "--seed",
            "CDDA_MODS_VALIDATOR_CAPABILITY",
            "--check-mods",
            CHECK_MODS_INTERACTION_PROBE_ROOT,
        ]
        result = run_process(args, game_root, out, timeout)
        debug_files = list(user.rglob("debug.log"))
        debug = "\n".join(
            p.read_text(encoding="utf-8", errors="replace")
            for p in debug_files
        )
        (out / "debug.log").write_text(debug, encoding="utf-8")
        stdout = (out / "stdout.log").read_text(
            encoding="utf-8", errors="replace"
        )
        stderr = (out / "stderr.log").read_text(
            encoding="utf-8", errors="replace"
        )
        combined = stdout + "\n" + stderr + "\n" + debug
        style_warnings, fatal_debug = classify_debug_errors(debug)
        result["style_warnings"] = style_warnings
        result["errors"] = sorted(set(result["errors"] + fatal_debug))
        result["debug_logs"] = [str(p) for p in debug_files]

        if CHECK_MODS_INTERACTION_PROBE_TOKEN in combined:
            status = "broken"
            failure_mode = "sentinel-loaded"
        elif result["exit_code"] == 124:
            # A tiny synthetic graph must not hang. Treat timeout as an
            # unusable validator capability and conservatively defer only
            # interaction-bearing dependency graphs to exact-source cata_test.
            status = "broken"
            failure_mode = "timeout"
        elif result["exit_code"] == 0 and not result["errors"]:
            status = "supported"
            failure_mode = None
        else:
            status = "inconclusive"
            failure_mode = "unexpected-result"

        report = {
            "schema": 1,
            "kind": "check-mods-interaction-capability",
            "status": status,
            "supported": status == "supported",
            "probe_token": CHECK_MODS_INTERACTION_PROBE_TOKEN,
            "failure_mode": failure_mode,
            "result": result,
        }
        suite.write(out / "report.json", report)
        return report
    finally:
        for path in created:
            if path.exists():
                shutil.rmtree(path)


def probe_check_mods_for_game(
    game_root: Path,
    target: str,
    out: Path,
    timeout: int,
) -> dict:
    _, targets = suite.validate()
    if target not in targets:
        raise ValueError(f"Unknown target: {target}")
    game_root = game_root.resolve()
    if exact_commit(game_root) != targets[target]["commit"]:
        raise ValueError(
            "Installed CDDA binary does not match catalog target commit"
        )
    return probe_check_mods_interactions(
        find_game_exe(game_root),
        game_root,
        game_root / "data",
        out,
        timeout,
    )


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


def file_sha256(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return None


def git_head(path: Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=path,
            text=True,
            errors="replace",
        ).strip().lower()
    except (OSError, subprocess.SubprocessError):
        return None


def write_environment(
    out: Path,
    target: str,
    target_commit: str,
    runtime: Path | None = None,
    observed_commit: str | None = None,
) -> None:
    """Write diagnostic-only runtime identity without affecting validation logic."""
    data = {
        "schema": 1,
        "kind": "deep-runtime-environment",
        "target": target,
        "target_commit": target_commit,
        "observed_commit": observed_commit,
        "harness_commit": git_head(ROOT),
        "python": platform.python_version(),
        "platform": platform.platform(),
    }
    if runtime is not None:
        data["runtime"] = {
            "name": runtime.name,
            "sha256": file_sha256(runtime),
        }
    try:
        suite.write(out / "environment.json", data)
    except OSError as exc:
        print(f"warning: could not write environment manifest: {exc}", file=sys.stderr)


def run_process(args: list[str], cwd: Path, log_dir: Path, timeout: int) -> dict:
    log_dir.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
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
    duration = round(time.perf_counter() - started, 3)
    (log_dir / "stdout.log").write_text(stdout, encoding="utf-8")
    (log_dir / "stderr.log").write_text(stderr, encoding="utf-8")
    return {
        "exit_code": code,
        "duration_seconds": duration,
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
    out = out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    write_environment(
        out,
        target,
        target_info["commit"],
        runtime=exe,
        observed_commit=exact_commit(game_root),
    )

    with tempfile.TemporaryDirectory(prefix="cdda-mods-deep-release-") as temp:
        data = Path(temp) / "data"
        shutil.copytree(
            game_root / "data",
            data,
            ignore=shutil.ignore_patterns("cache", "gfx"),
        )
        if (game_root / "gfx").is_dir():
            shutil.copytree(game_root / "gfx", data / "gfx")

        def check(
            name: str,
            game_ids: list[str],
            datadir: Path | None,
        ) -> dict:
            user = (out / name / "user").resolve()
            user.mkdir(parents=True, exist_ok=True)
            # CDDA opens config/debug.log before assure_essential_dirs_exist().
            # --check-mods exits before that later directory creation path, so
            # prepare config explicitly or Windows release diagnostics vanish.
            (user / "config").mkdir(parents=True, exist_ok=True)
            args = [
                str(exe),
                "--basepath",
                str(game_root) + "/",
            ]
            if datadir is not None:
                args += ["--datadir", str(datadir.resolve()) + "/"]
            args += [
                "--userdir",
                str(user) + "/",
                "--seed",
                "CDDA_MODS_DEEP_RUNTIME",
                "--check-mods",
                *game_ids,
            ]
            result = run_process(args, game_root, out / name, timeout)
            debug_files = list(user.rglob("debug.log"))
            debug = "\n".join(
                p.read_text(encoding="utf-8", errors="replace")
                for p in debug_files
            )
            (out / name / "debug.log").write_text(debug, encoding="utf-8")
            style_warnings, fatal_debug = classify_debug_errors(debug)
            result["raw_exit_code"] = result["exit_code"]
            result["style_warnings"] = style_warnings
            result["errors"] = sorted(set(result["errors"] + fatal_debug))
            # --check-mods returns 1 for any D_ERROR, including purely advisory
            # cata-text-style diagnostics.  Preserve that raw code in evidence,
            # but do not turn legacy prose formatting into a runtime failure.
            if result["exit_code"] == 1 and style_warnings and not result["errors"]:
                result["exit_code"] = 0
                result["style_only_exit"] = True
            result["debug_logs"] = [str(p) for p in debug_files]
            return result

        # First validate the pristine official release with its own native data tree.
        # Then validate the isolated copy used to stage repository payloads. This
        # distinguishes an upstream/binary problem from a harness staging problem.
        baseline = check("baseline-dda-native", ["dda"], None)
        staged_baseline = None
        capability = None
        results = []
        if baseline["exit_code"] == 0 and not baseline["errors"]:
            staged_baseline = check("baseline-dda-staged", ["dda"], data)
        if (
            baseline["exit_code"] == 0
            and not baseline["errors"]
            and staged_baseline is not None
            and staged_baseline["exit_code"] == 0
            and not staged_baseline["errors"]
        ):
            capability = probe_check_mods_interactions(
                exe,
                game_root,
                data,
                out / "capability-check-mods-interactions",
                min(timeout, 120),
            )
            for row in rows:
                # Mod discovery scans every modinfo.json under data/mods.  Keep
                # component checks isolated so an unrelated repository mod cannot
                # poison another suite before its own content is even loaded.
                clear_repository_json_mods(target, data / "mods")
                copy_json_mods(target, data / "mods", row["components"])
                checks = []
                for game_id in row["check_mod_ids"]:
                    hazards = check_mods_interaction_hazards(data, game_id)
                    if (
                        hazards
                        and capability is not None
                        and capability["status"] == "broken"
                    ):
                        result = deferred_check_mods_result(game_id, hazards)
                    else:
                        result = check(
                            f"{row['name']}/{game_id}",
                            [game_id],
                            data,
                        )
                    checks.append({"mod": game_id, "result": result})
                errors = sorted(
                    {
                        error
                        for item in checks
                        for error in item["result"]["errors"]
                    }
                )
                style_warnings = sorted(
                    {
                        warning
                        for item in checks
                        for warning in item["result"].get("style_warnings", [])
                    }
                )
                aggregate = {
                    "exit_code": 0
                    if all(
                        item["result"]["exit_code"] == 0
                        and not item["result"]["errors"]
                        for item in checks
                    )
                    else 1,
                    "errors": errors,
                    "style_warnings": style_warnings,
                    "deferred_checks": [
                        item["mod"]
                        for item in checks
                        if item["result"].get("deferred")
                    ],
                    "checks": checks,
                }
                results.append({**row, "result": aggregate})

        report = {
            "schema": 3,
            "kind": "release-binary",
            "target": target,
            "commit": target_info["commit"],
            "baseline": baseline,
            "staged_baseline": staged_baseline,
            "check_mods_interaction_capability": capability,
            "suites": results,
        }
        suite.write(out / "report.json", report)

    failures = []
    if capability is not None and capability["status"] == "inconclusive":
        failures.append("capability-check-mods-interactions")
    if baseline["exit_code"] or baseline["errors"]:
        failures.append("baseline-dda-native")
    if staged_baseline is not None and (
        staged_baseline["exit_code"] or staged_baseline["errors"]
    ):
        failures.append("baseline-dda-staged")
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
    check_mods_interactions: str = "auto",
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
    out = out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    write_environment(
        out,
        target,
        target_info["commit"],
        runtime=exe,
        observed_commit=exact_commit(game_root),
    )
    ids = []
    for mid in game_mod_ids:
        if mid and mid != "dda" and mid not in ids:
            ids.append(mid)
    if not ids:
        raise ValueError("No installed game mod IDs supplied")

    if check_mods_interactions == "auto":
        capability = probe_check_mods_interactions(
            exe,
            game_root,
            game_root / "data",
            out / "capability-check-mods-interactions",
            min(timeout, 120),
        )
        if capability["status"] == "inconclusive":
            raise RuntimeError(
                "Could not determine --check-mods mod_interactions capability"
            )
    else:
        capability = {
            "schema": 1,
            "kind": "check-mods-interaction-capability",
            "status": check_mods_interactions,
            "supported": check_mods_interactions == "supported",
            "source": "caller",
        }

    checks = []
    for mid in ids:
        hazards = check_mods_interaction_hazards(game_root / "data", mid)
        if hazards and capability["status"] == "broken":
            checks.append(
                {"mod": mid, "result": deferred_check_mods_result(mid, hazards)}
            )
            continue
        log_dir = out / mid
        user = log_dir / "user"
        user.mkdir(parents=True, exist_ok=True)
        (user / "config").mkdir(parents=True, exist_ok=True)
        args = [
            str(exe),
            "--basepath",
            str(game_root) + "/",
            "--userdir",
            str(user) + "/",
            "--seed",
            "CDDA_MODS_INSTALL_MATRIX",
            "--check-mods",
            mid,
        ]
        result = run_process(args, game_root, log_dir, timeout)
        debug_files = list(user.rglob("debug.log"))
        debug = "\n".join(
            p.read_text(encoding="utf-8", errors="replace")
            for p in debug_files
        )
        (log_dir / "debug.log").write_text(debug, encoding="utf-8")
        style_warnings, fatal_debug = classify_debug_errors(debug)
        result["raw_exit_code"] = result["exit_code"]
        result["style_warnings"] = style_warnings
        result["errors"] = sorted(set(result["errors"] + fatal_debug))
        if result["exit_code"] == 1 and style_warnings and not result["errors"]:
            result["exit_code"] = 0
            result["style_only_exit"] = True
        result["debug_logs"] = [str(p) for p in debug_files]
        checks.append({"mod": mid, "result": result})

    report = {
        "schema": 2,
        "kind": "installed-game-check",
        "target": target,
        "commit": target_info["commit"],
        "mods": ids,
        "check_mods_interaction_capability": capability,
        "checks": checks,
    }
    suite.write(out / "report.json", report)
    failed = [
        item["mod"]
        for item in checks
        if item["result"]["exit_code"] or item["result"]["errors"]
    ]
    if failed:
        raise RuntimeError(
            "Installed-game validation failed for: " + ", ".join(failed)
        )
    return report


def stage_source(
    cdda_root: Path,
    target: str,
    component_ids: list[str] | None = None,
) -> None:
    data_mods = cdda_root / "data" / "mods"
    if not data_mods.is_dir():
        raise ValueError(f"Not a CDDA source checkout: {cdda_root}")
    copy_json_mods(target, data_mods, component_ids)


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


def source_specs(
    depth: str,
    combined: bool,
    suite_name: str | None = None,
) -> list[str]:
    del combined  # retained for compatibility with existing callers/tests
    specs = ["[force_load_game]"]
    if suite_name == "component-axiom_7":
        specs.append("[axiom7_lifecycle]")
    if depth in ("full", "exhaustive"):
        # Match CDDA's own CI partition and explicitly include starting_items,
        # which exercises character/profession construction under loaded mod data.
        # Repository-owned probes are compiled into the shared cata_test binary,
        # so exclude them from generic partitions and run them only in their
        # owning component suite above.
        specs.append(
            '~[slow] ~[.] ~[axiom7_lifecycle] '
            '~"item_new_to_hit_enforcement" '
            '~"uncraft_blacklist_is_pruned",starting_items'
        )
    if depth == "exhaustive":
        # The slow partition cannot select AXIOM lifecycle probes because those
        # probes are not tagged [slow], so preserve CDDA's original filter
        # exactly instead of narrowing upstream coverage.
        specs.append("[slow] ~starting_items")
    return specs


CONTENT_SHARDS = ("items", "recipes", "vehicles", "overmap")


def content_specs(shard: str) -> list[str]:
    """Focused exact-engine selectors for object-level content auditing."""
    if shard == "items":
        return [
            "[cdda_mods_content][content_items]",
            "item_length_sanity_check",
            "item_material_density_sanity_check",
            "uncraft_sanity_check",
        ]
    if shard == "recipes":
        return [
            "[cdda_mods_content][content_recipes]",
            "[recipe]",
        ]
    if shard == "vehicles":
        return [
            "[cdda_mods_content][content_vehicles]",
            "[vehicle][vehicle_parts]",
            "vehicle_turret",
        ]
    if shard == "overmap":
        return [
            "[cdda_mods_content][content_overmap]",
            "[overmap]",
        ]
    raise ValueError(f"Unknown content shard: {shard}")


INHERITED_DEBT_BASELINE = ROOT / ".github" / "deep-inherited-debt.json"


def parse_inherited_debt_failures(stdout: str) -> dict:
    """Extract pinned upstream-debt failure classes from Catch output."""
    lines = stdout.splitlines()
    observed = {
        "density_ids": [],
        "uncraft_ids": [],
        "mutation_ids": [],
        "overmap_failed": False,
        "overmap_missing_ids": [],
        "overmap_missing_count": None,
        "unknown_failures": [],
    }
    failure_re = re.compile(r"\.\./tests/([^:]+):(\d+):\s+FAILED:")
    for index, line in enumerate(lines):
        match = failure_re.search(line)
        if not match:
            continue
        location = f"{match.group(1)}:{match.group(2)}"
        forward = "\n".join(lines[index : index + 20])
        around = "\n".join(lines[max(0, index - 20) : index + 20])
        if location == "item_test.cpp:1037":
            item = re.search(
                r'target\.typeId\(\).*?string_id\( "([^"]+)" \)',
                forward,
            )
            if item:
                observed["density_ids"].append(item.group(1))
            else:
                observed["unknown_failures"].append(location + ":missing-item-id")
        elif location == "item_test.cpp:1375":
            item = re.search(r"Item ([^ ]+) weight", forward)
            if item:
                observed["uncraft_ids"].append(item.group(1))
            else:
                observed["unknown_failures"].append(location + ":missing-item-id")
        elif location == "mutation_test.cpp:614":
            mutation_id = None
            for previous in reversed(lines[max(0, index - 20) : index]):
                mutation = re.search(
                    r"Given: mutation of ID ([^ ]+) is valid and removable",
                    previous,
                )
                if mutation:
                    mutation_id = mutation.group(1)
                    break
            if mutation_id:
                observed["mutation_ids"].append(mutation_id)
            else:
                observed["unknown_failures"].append(
                    location + ":missing-mutation-id"
                )
        elif location == "overmap_test.cpp:798":
            observed["overmap_failed"] = True
        else:
            observed["unknown_failures"].append(location)

    if observed["overmap_failed"]:
        count = re.search(r"num_missing\s*:=\s*(\d+)", stdout)
        missing = re.search(
            r'missing_oter_type_ids\s*:=\s*"(.*?)"',
            stdout,
            re.S,
        )
        if count and missing:
            raw = re.sub(r"\s+", " ", missing.group(1))
            raw = raw.replace(", and ", ", ").replace(" and ", ", ")
            observed["overmap_missing_count"] = int(count.group(1))
            observed["overmap_missing_ids"] = [
                item.strip()
                for item in raw.split(",")
                if item.strip()
            ]
        else:
            observed["unknown_failures"].append(
                "overmap_test.cpp:798:missing-coverage-details"
            )
    return observed

def inherited_debt_expectation(
    target: str,
    commit: str,
    components: list[str],
) -> tuple[str, dict] | None:
    if not INHERITED_DEBT_BASELINE.is_file():
        return None
    baseline = suite.read(INHERITED_DEBT_BASELINE)
    if (
        baseline.get("target") != target
        or str(baseline.get("commit", "")).lower() != commit.lower()
    ):
        return None
    matches = [
        (int(debt.get("priority", 0)), debt_id, debt)
        for debt_id, debt in (baseline.get("debts") or {}).items()
        if debt.get("component") in components
    ]
    if not matches:
        return None
    _, debt_id, debt = max(matches, key=lambda item: item[0])
    return debt_id, debt

def normalize_inherited_debt_result(
    result: dict,
    log_dir: Path,
    target: str,
    commit: str,
    components: list[str],
) -> dict:
    """Accept only pinned, component-specific copies of documented upstream debt."""
    result = dict(result)
    if (
        not result.get("exit_code")
        or result.get("errors")
        or not result.get("catch_failed")
    ):
        return result
    expected = inherited_debt_expectation(target, commit, components)
    if expected is None:
        return result
    debt_id, debt = expected
    stdout_path = log_dir / "stdout.log"
    if not stdout_path.is_file():
        return result
    observed = parse_inherited_debt_failures(
        stdout_path.read_text(encoding="utf-8", errors="replace")
    )

    allow_partial = bool(debt.get("allow_partial_classes"))

    def exact_class(observed_values: list[str], expected_values: list[str]) -> bool:
        if allow_partial and not observed_values:
            return True
        return sorted(observed_values) == sorted(expected_values)

    density_ok = exact_class(
        observed["density_ids"],
        list(debt.get("density_ids") or []),
    )
    uncraft_ok = exact_class(
        observed["uncraft_ids"],
        list(debt.get("uncraft_ids") or []),
    )
    mutation_ok = exact_class(
        observed["mutation_ids"],
        list(debt.get("mutation_ids") or []),
    )

    overmap_ok = True
    if observed["overmap_failed"]:
        allowed_ids = set(debt.get("overmap_allowed_ids") or [])
        allowed_prefixes = tuple(debt.get("overmap_allowed_prefixes") or [])
        missing_ids = observed["overmap_missing_ids"]
        ids_ok = bool(missing_ids) and all(
            item in allowed_ids
            or any(item.startswith(prefix) for prefix in allowed_prefixes)
            for item in missing_ids
        )
        count_range = debt.get("overmap_missing_count_range")
        count = observed["overmap_missing_count"]
        count_ok = (
            isinstance(count_range, list)
            and len(count_range) == 2
            and count is not None
            and int(count_range[0]) <= count <= int(count_range[1])
        )
        overmap_ok = ids_ok and count_ok
    elif not allow_partial and (
        debt.get("overmap_allowed_ids")
        or debt.get("overmap_allowed_prefixes")
    ):
        overmap_ok = False

    recognized = bool(
        observed["density_ids"]
        or observed["uncraft_ids"]
        or observed["mutation_ids"]
        or observed["overmap_failed"]
    )
    exact = (
        recognized
        and not observed["unknown_failures"]
        and density_ok
        and uncraft_ok
        and mutation_ok
        and overmap_ok
    )
    result["inherited_debt_check"] = {
        "debt_id": debt_id,
        "matched": exact,
        "density_count": len(observed["density_ids"]),
        "uncraft_count": len(observed["uncraft_ids"]),
        "mutation_count": len(observed["mutation_ids"]),
        "overmap_missing_count": observed["overmap_missing_count"],
        "unknown_failures": observed["unknown_failures"],
    }
    if exact:
        result["exit_code"] = 0
        result["inherited_debt_only"] = True
        result["inherited_debt"] = {
            "debt_id": debt_id,
            "density_ids": sorted(observed["density_ids"]),
            "uncraft_ids": sorted(observed["uncraft_ids"]),
            "mutation_ids": sorted(observed["mutation_ids"]),
            "overmap_missing_ids": sorted(observed["overmap_missing_ids"]),
            "overmap_missing_count": observed["overmap_missing_count"],
        }
    return result

def normalize_cata_test_result(result: dict, log_dir: Path) -> dict:
    """Keep real Catch failures fatal while downgrading pure text-style noise."""
    result = dict(result)
    raw_exit = result["exit_code"]
    stdout_path = log_dir / "stdout.log"
    stderr_path = log_dir / "stderr.log"
    stdout = (
        stdout_path.read_text(encoding="utf-8", errors="replace")
        if stdout_path.is_file()
        else ""
    )
    stderr = (
        stderr_path.read_text(encoding="utf-8", errors="replace")
        if stderr_path.is_file()
        else ""
    )
    style_warnings, fatal_debug = classify_debug_errors(stderr)
    result["raw_exit_code"] = raw_exit
    result["style_warnings"] = style_warnings
    result["errors"] = sorted(set(fatal_debug))

    catch_failed = bool(
        re.search(
            r"(?mi)^\s*test cases:.*\|\s*\d+\s+failed\b",
            stdout,
        )
    )
    catch_passed = bool(
        re.search(
            r"(?mi)^\s*All tests passed\s*\([^\n]*\btest cases?\)\s*$",
            stdout,
        )
        or re.search(
            r"(?mi)^\s*test cases:\s*\d+\s*\|\s*\d+\s+passed\s*$",
            stdout,
        )
        or re.search(
            r"(?mi)^\s*test cases:\s*\d+\s*\|\s*\d+\s+passed\s*\|",
            stdout,
        )
    )

    # cata_test returns 1 when initialization logged D_ERROR, including advisory
    # text-style diagnostics. Normalize only when Catch itself demonstrably
    # passed and there is no non-style diagnostic. Never mask timeouts/crashes.
    if (
        raw_exit == 1
        and style_warnings
        and not result["errors"]
        and catch_passed
        and not catch_failed
    ):
        result["exit_code"] = 0
        result["style_only_exit"] = True
    result["catch_failed"] = catch_failed
    result["catch_passed"] = catch_passed
    return result


def run_source(
    cdda_root: Path,
    target: str,
    out: Path,
    depth: str,
    timeout: int,
    suite_name: str | None = None,
) -> dict:
    _, targets = suite.validate()
    if target not in targets:
        raise ValueError(f"Unknown target: {target}")
    target_info = targets[target]
    cdda_root = cdda_root.resolve()
    try:
        actual_commit = subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=cdda_root,
            text=True,
            errors="replace",
        ).strip().lower()
    except (OSError, subprocess.SubprocessError) as exc:
        raise ValueError(
            "Cannot verify exact CDDA source commit"
        ) from exc
    if actual_commit != target_info["commit"].lower():
        raise ValueError(
            f"CDDA source commit mismatch: expected {target_info['commit']}, "
            f"got {actual_commit}"
        )
    test_bin = find_cata_test(cdda_root)
    _, rows = build_suites(target)
    if suite_name is not None:
        rows = [row for row in rows if row["name"] == suite_name]
        if len(rows) != 1:
            raise ValueError(f"Unknown source-runtime suite: {suite_name}")
    selected_components = sorted(
        {mid for row in rows for mid in row["components"]}
    )
    stage_source(cdda_root, target, selected_components)
    out = out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    write_environment(
        out,
        target,
        target_info["commit"],
        runtime=test_bin,
        observed_commit=actual_commit,
    )

    runs = []
    for row in rows:
        combined = row["name"] == "combined-all-json"
        mod_arg = ",".join(row["game_mod_ids"])
        for index, spec in enumerate(
            source_specs(depth, combined, row["name"])
        ):
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
            result = normalize_cata_test_result(result, log_dir)
            result = normalize_inherited_debt_result(
                result,
                log_dir,
                target,
                target_info["commit"],
                row["components"],
            )
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
        "observed_source_commit": actual_commit,
        "suite_filter": suite_name,
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



def run_content_shard(
    cdda_root: Path,
    target: str,
    out: Path,
    shard: str,
    timeout: int,
) -> dict:
    """Run focused object-level content checks on the full JSON stack."""
    if shard not in CONTENT_SHARDS:
        raise ValueError(f"Unknown content shard: {shard}")
    _, targets = suite.validate()
    if target not in targets:
        raise ValueError(f"Unknown target: {target}")
    target_info = targets[target]
    cdda_root = cdda_root.resolve()
    try:
        actual_commit = subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=cdda_root,
            text=True,
            errors="replace",
        ).strip().lower()
    except (OSError, subprocess.SubprocessError) as exc:
        raise ValueError("Cannot verify exact CDDA source commit") from exc
    if actual_commit != target_info["commit"].lower():
        raise ValueError(
            f"CDDA source commit mismatch: expected {target_info['commit']}, "
            f"got {actual_commit}"
        )

    test_bin = find_cata_test(cdda_root)
    _, rows = build_suites(target)
    combined_rows = [row for row in rows if row["name"] == "combined-all-json"]
    if len(combined_rows) != 1:
        raise ValueError("combined-all-json suite missing or ambiguous")
    row = combined_rows[0]

    stage_source(cdda_root, target, row["components"])
    out = out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    write_environment(
        out,
        target,
        target_info["commit"],
        runtime=test_bin,
        observed_commit=actual_commit,
    )

    runs = []
    mod_arg = ",".join(row["game_mod_ids"])
    for index, spec in enumerate(content_specs(shard)):
        safe_spec = (
            re.sub(r"[^A-Za-z0-9_.-]+", "_", spec).strip("_")
            or "spec"
        )
        log_dir = out / f"{index:02d}-{safe_spec}"
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
        result = normalize_cata_test_result(result, log_dir)
        result = normalize_inherited_debt_result(
            result,
            log_dir,
            target,
            target_info["commit"],
            row["components"],
        )
        runs.append(
            {
                "suite": f"content-{shard}",
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
        "depth": f"content-{shard}",
        "target": target,
        "commit": target_info["commit"],
        "observed_source_commit": actual_commit,
        "suite_filter": f"content-{shard}",
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
            "Content runtime tests failed: " + ", ".join(failed)
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
    installed.add_argument(
        "--check-mods-interactions",
        choices=("auto", "supported", "broken"),
        default="auto",
    )

    capability = sub.add_parser("probe-check-mods")
    capability.add_argument("--game-root", required=True)
    capability.add_argument("--target", required=True)
    capability.add_argument("--out", required=True)
    capability.add_argument("--timeout", type=int, default=120)

    source = sub.add_parser("run-source")
    source.add_argument("--cdda-root", required=True)
    source.add_argument("--target", required=True)
    source.add_argument("--out", required=True)
    source.add_argument(
        "--depth",
        choices=("load", "full", "exhaustive"),
        default="full",
    )
    source.add_argument("--timeout", type=int, default=10800)
    source.add_argument(
        "--suite",
        default=None,
        help="Run only one suite name from the plan (used by CI matrix jobs)",
    )

    content = sub.add_parser("run-content")
    content.add_argument("--cdda-root", required=True)
    content.add_argument("--target", required=True)
    content.add_argument("--out", required=True)
    content.add_argument("--shard", choices=CONTENT_SHARDS, required=True)
    content.add_argument("--timeout", type=int, default=5400)

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
            args.check_mods_interactions,
        )
    elif args.command == "probe-check-mods":
        report = probe_check_mods_for_game(
            Path(args.game_root),
            args.target,
            Path(args.out),
            args.timeout,
        )
        print(json.dumps(report, ensure_ascii=False, indent=2))
        if report["status"] == "inconclusive":
            raise RuntimeError(
                "Could not determine --check-mods mod_interactions capability"
            )
    elif args.command == "run-source":
        run_source(
            Path(args.cdda_root),
            args.target,
            Path(args.out),
            args.depth,
            args.timeout,
            args.suite,
        )
    elif args.command == "run-content":
        run_content_shard(
            Path(args.cdda_root),
            args.target,
            Path(args.out),
            args.shard,
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

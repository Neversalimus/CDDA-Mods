#!/usr/bin/env python3
"""Read-only aggregation for deep CDDA evidence.

The summarizer never changes the authoritative test verdict. It converts the
JSON evidence produced by the release, source and installer jobs into a compact
machine-readable report and a GitHub step summary, while comparing source text
style diagnostics with an informational baseline.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        return {"_parse_error": str(exc)}


def result_status(result: dict) -> str:
    if result.get("deferred"):
        return "DEFER"
    if result.get("exit_code") or result.get("errors"):
        return "FAIL"
    if result.get("inherited_debt_only"):
        return "DEBT"
    return "PASS"


def add_row(rows: list[dict], layer: str, case: str, status: str, result=None, note=""):
    result = result or {}
    rows.append(
        {
            "layer": layer,
            "case": case,
            "status": status,
            "duration_seconds": result.get("duration_seconds"),
            "style_warnings": len(result.get("style_warnings", []) or []),
            "note": note,
        }
    )


def scan_report(path: Path, doc: dict, rows: list[dict], source_warnings: dict[str, set[str]]):
    if "_parse_error" in doc:
        add_row(rows, "summary", str(path), "WARN", note=doc["_parse_error"])
        return

    kind = doc.get("kind")
    if kind == "release-binary":
        baseline = doc.get("baseline") or {}
        add_row(rows, "release", "baseline-dda-native", result_status(baseline), baseline)
        staged = doc.get("staged_baseline")
        if staged is not None:
            add_row(rows, "release", "baseline-dda-staged", result_status(staged), staged)
        capability = doc.get("check_mods_interaction_capability") or {}
        if capability:
            cap_status = capability.get("status", "unknown")
            shown = "PASS" if cap_status == "supported" else ("DEFER" if cap_status == "broken" else "WARN")
            add_row(
                rows,
                "capability",
                "release --check-mods",
                shown,
                capability.get("result") or {},
                "dependency mod_interactions " + cap_status,
            )
        for suite in doc.get("suites", []):
            result = suite.get("result") or {}
            deferred = result.get("deferred_checks") or []
            note = "deferred to exact-source: " + ", ".join(deferred) if deferred else ""
            add_row(rows, "release", suite.get("name", "?"), result_status(result), result, note)
        return

    if kind == "source-cata-test":
        for run in doc.get("runs", []):
            result = run.get("result") or {}
            suite = run.get("suite", "?")
            spec = run.get("spec", "?")
            debt = result.get("inherited_debt") or {}
            note = ""
            if debt:
                note = (
                    "strict inherited upstream debt: "
                    f"{len(debt.get('density_ids', []))} density, "
                    f"{len(debt.get('uncraft_ids', []))} uncraft"
                )
            add_row(
                rows,
                "source",
                f"{suite}::{spec}",
                result_status(result),
                result,
                note,
            )
            source_warnings.setdefault(suite, set()).update(result.get("style_warnings", []) or [])
        return

    if kind == "installed-game-check":
        for item in doc.get("checks", []):
            result = item.get("result") or {}
            note = ""
            if result.get("deferred"):
                note = "deferred to " + str(result.get("deferred_to", "exact-source"))
            add_row(rows, "installed", item.get("mod", "?"), result_status(result), result, note)
        return

    if kind == "check-mods-interaction-capability":
        status = doc.get("status", "unknown")
        shown = "PASS" if status == "supported" else ("DEFER" if status == "broken" else "WARN")
        add_row(
            rows,
            "capability",
            str(path.parent.name),
            shown,
            doc.get("result") or {},
            doc.get("failure_mode") or status,
        )


def scan_matrix(path: Path, doc: dict, rows: list[dict]):
    if "_parse_error" in doc:
        add_row(rows, "summary", str(path), "WARN", note=doc["_parse_error"])
        return
    add_row(
        rows,
        "installer",
        "matrix-total",
        "PASS" if doc.get("passed") else "FAIL",
        {"duration_seconds": doc.get("duration_seconds")},
    )
    for case in doc.get("cases", []):
        add_row(
            rows,
            "installer",
            case.get("case", "?"),
            "PASS" if case.get("passed") else "FAIL",
            case,
        )


def warning_fingerprint(values: set[str]) -> dict:
    ordered = sorted(values)
    payload = "\n".join(ordered).encode("utf-8")
    return {"count": len(ordered), "sha256": hashlib.sha256(payload).hexdigest()}


def compare_baseline(observed: dict, baseline: dict) -> dict:
    expected = (baseline or {}).get("suites", {})
    result = {}
    empty = {"count": 0, "sha256": hashlib.sha256(b"").hexdigest()}
    for suite in sorted(set(expected) | set(observed)):
        cur = observed.get(suite, empty)
        exp = expected.get(suite)
        if exp is None:
            state = "unbaselined" if cur["count"] else "clean"
        elif cur.get("count") == exp.get("count") and cur.get("sha256") == exp.get("sha256"):
            state = "baseline"
        elif cur.get("count", 0) > exp.get("count", 0):
            state = "warning-count-increased"
        elif cur.get("count", 0) < exp.get("count", 0):
            state = "warning-count-decreased"
        else:
            state = "warning-set-changed"
        result[suite] = {"state": state, "expected": exp, "observed": cur}
    return result


def markdown(report: dict) -> str:
    lines = [
        "# Deep runtime summary",
        "",
        "This summary is read-only: authoritative failures remain in their original jobs.",
        "",
        "| Layer | Case | Status | Time (s) | Style | Note |",
        "|---|---|---:|---:|---:|---|",
    ]
    for row in report["rows"]:
        duration = "" if row.get("duration_seconds") is None else f"{row['duration_seconds']:.3f}"
        note = str(row.get("note") or "").replace("|", "\\|")
        case = str(row.get("case") or "").replace("|", "\\|")
        lines.append(
            f"| {row['layer']} | {case} | {row['status']} | {duration} | {row.get('style_warnings', 0)} | {note} |"
        )
    lines += [
        "",
        "## Text-style baseline",
        "",
        "| Suite | State | Expected | Observed |",
        "|---|---:|---:|---:|",
    ]
    for suite, item in report["warning_baseline"].items():
        expected = item.get("expected") or {}
        observed = item.get("observed") or {}
        lines.append(
            f"| {suite} | {item['state']} | {expected.get('count', '—')} | {observed.get('count', 0)} |"
        )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--baseline")
    parser.add_argument("--job-result", action="append", default=[])
    args = parser.parse_args()

    root = Path(args.root)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    source_warnings: dict[str, set[str]] = {}

    if root.exists():
        for path in sorted(root.rglob("report.json")):
            scan_report(path, read_json(path), rows, source_warnings)
        for path in sorted(root.rglob("matrix-summary.json")):
            scan_matrix(path, read_json(path), rows)

    for value in args.job_result:
        name, _, status = value.partition("=")
        add_row(rows, "job", name or "?", (status or "unknown").upper())

    observed = {
        suite: warning_fingerprint(values)
        for suite, values in sorted(source_warnings.items())
    }
    baseline = (
        read_json(Path(args.baseline))
        if args.baseline and Path(args.baseline).is_file()
        else {}
    )
    report = {
        "schema": 1,
        "rows": rows,
        "source_style_warnings": observed,
        "warning_baseline": compare_baseline(observed, baseline),
    }
    (out / "summary.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    md = markdown(report)
    (out / "summary.md").write_text(md, encoding="utf-8")
    step = os.environ.get("GITHUB_STEP_SUMMARY")
    if step:
        with open(step, "a", encoding="utf-8") as handle:
            handle.write(md)
    print(md, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

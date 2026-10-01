#!/usr/bin/env python3
"""Discover and dispatch compatibility checks for new CDDA experimentals."""

from __future__ import annotations

import argparse
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

TAG_RE = re.compile(
    r"^cdda-experimental-(\d{4})-(\d{2})-(\d{2})-(\d{4})$"
)
SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")


def tag_time(tag: str) -> datetime | None:
    match = TAG_RE.fullmatch(tag)
    if not match:
        return None
    year, month, day, hm = match.groups()
    return datetime(
        int(year),
        int(month),
        int(day),
        int(hm[:2]),
        int(hm[2:]),
        tzinfo=timezone.utc,
    )


def known_targets(root: Path) -> dict[str, dict]:
    result: dict[str, dict] = {}
    for path in sorted((root / "catalog" / "targets").glob("*.json")):
        doc = json.loads(path.read_text(encoding="utf-8-sig"))
        if doc.get("channel") != "experimental":
            continue
        tag = doc.get("tag")
        if isinstance(tag, str) and tag_time(tag) is not None:
            result[tag] = doc
    if not result:
        raise ValueError("No experimental targets are registered")
    return result


def discover_candidates(
    releases: list[dict],
    known: dict[str, dict],
    seen_titles: set[str],
) -> list[dict]:
    latest_known = max(known, key=lambda tag: tag_time(tag) or datetime.min.replace(tzinfo=timezone.utc))
    latest_time = tag_time(latest_known)
    assert latest_time is not None
    candidates = []
    for release in releases:
        tag = release.get("tag_name")
        if not isinstance(tag, str) or release.get("draft"):
            continue
        timestamp = tag_time(tag)
        if timestamp is None or timestamp <= latest_time:
            continue
        if tag in known:
            continue
        if f"CDDA Mods certify / {tag}" in seen_titles:
            continue
        candidates.append(release)
    candidates.sort(key=lambda row: tag_time(str(row["tag_name"])))
    return candidates


class GitHub:
    def __init__(self, token: str):
        if not token:
            raise ValueError("GitHub token is required")
        self.token = token

    def request(self, method: str, url: str, payload: dict | None = None):
        data = None
        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {self.token}",
            "User-Agent": "CDDA-Mods-Experimental-Watcher",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            url,
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                if not raw:
                    return None
                return json.loads(raw.decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"GitHub API {method} {url} failed: {exc.code}: {body}"
            ) from exc

    def get(self, url: str):
        return self.request("GET", url)

    def post(self, url: str, payload: dict):
        return self.request("POST", url, payload)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--repo", default="Neversalimus/CDDA-Mods")
    parser.add_argument("--workflow", default="experimental-certify.yml")
    parser.add_argument("--token", default=os.environ.get("GH_TOKEN", ""))
    parser.add_argument("--release-limit", type=int, default=30)
    args = parser.parse_args()

    root = Path(args.root)
    known = known_targets(root)
    latest_known = max(known, key=lambda tag: tag_time(tag))
    client = GitHub(args.token)

    releases = client.get(
        "https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases"
        f"?per_page={args.release_limit}"
    )
    workflow = urllib.parse.quote(args.workflow, safe="")
    runs_doc = client.get(
        f"https://api.github.com/repos/{args.repo}/actions/workflows/"
        f"{workflow}/runs?per_page=100"
    )
    seen_titles = {
        str(run.get("display_title"))
        for run in (runs_doc or {}).get("workflow_runs", [])
        if run.get("display_title")
    }

    candidates = discover_candidates(releases or [], known, seen_titles)
    dispatched = 0
    for release in candidates:
        tag = str(release["tag_name"])
        commit = str(release.get("target_commitish") or "")
        if not SHA_RE.fullmatch(commit):
            resolved = client.get(
                "https://api.github.com/repos/CleverRaven/Cataclysm-DDA/"
                f"commits/{urllib.parse.quote(tag, safe='')}"
            )
            commit = str(resolved["sha"])
        if not SHA_RE.fullmatch(commit):
            raise ValueError(f"Could not resolve exact source commit for {tag}")

        print(f"Dispatching compatibility certification for {tag} ({commit})")
        client.post(
            f"https://api.github.com/repos/{args.repo}/actions/workflows/"
            f"{workflow}/dispatches",
            {
                "ref": "main",
                "inputs": {"tag": tag, "commit": commit.lower()},
            },
        )
        dispatched += 1

    print(f"Latest supported target: {latest_known}")
    print(f"New certification requests: {dispatched}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

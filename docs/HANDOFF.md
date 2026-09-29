# Handoff — 2026-09-30

## Safe CI observability / targeted style cleanup

Branch: `infra/safe-observability-pass`. Base: `f83595d4a1b084c263645aa99aa660b912964d61`. Code validation point: `8a57afbd8c6ee4d6766b927421a86568dd26621b`. Exact CDDA target remains `experimental-2026-09-23-0546` / `e262adb299a7613b4aedc5f12c08fe0413c56a84`.

Changes are deliberately non-invasive: `deep_cdda_runtime.py` records elapsed seconds and diagnostic environment/runtime hashes and normalizes text-style annotations into timestamp-free fingerprints; `deep_install_matrix.ps1` records per-case and total timing plus installer/catalog hashes; `deep_summary.py` and the final deep workflow job aggregate existing evidence into a compact report. The summary job and warning baseline are non-gating and do not alter PASS/FAIL authority.

Targeted Secronom cleanup changed exactly 29 known text-style locations: 28 `...` strings to `…` and one trailing space. The 985 sentence-spacing warnings were not auto-fixed. Expected post-cleanup Secronom warning count is 985; dependent Secronom+ is expected at 1443, and combined/profile suites at 1795. These counts are derived from run 36637757803 and must be confirmed by the next exact-source deep run.

Normal CI run `36644399331` passed all three jobs on code commit `8a57afbd8c6ee4d6766b927421a86568dd26621b`: verify/package + PS 5.1/7 + Python tests, Survivor native compile, and Advanced World Settings native compile. No deep run has yet executed this branch. Next step: merge only after the final branch CI remains green, then run/inspect the exact-game deep workflow and confirm the informational baseline rather than promoting compatibility from normal CI alone.

# Handoff — 2026-09-29

## AXIOM-7 exact-engine lifecycle gate

Active task branch: `mod/axiom_7/deep-lifecycle`. Pull request: #10. Base was updated with `main` commit `47e851d36220ad33cfac9233b68b82096efbbc8a` before review. Exact target remains `experimental-2026-09-23-0546` / `e262adb299a7613b4aedc5f12c08fe0413c56a84`.

Implemented:
- repository-owned `tools/runtime_probes/axiom7_lifecycle_test.cpp`;
- source-build injects that file only into the temporary exact CDDA checkout before compiling `tests/cata_test`;
- `deep_cdda_runtime.py` adds `[axiom7_lifecycle]` only to `component-axiom_7`;
- the probe covers representative AXIOM surface/basement/roof generation, Lena/Rhea/Nadia, AXIOM sentry/turret spawn points, dormant KX-91, the full update-mapgen KX vehicle swap chain, clearance mission end-effects/cards, and security alarm EOC behavior;
- normal Python tests cover probe wiring so ordinary CI detects accidental removal.

Normal PR CI run `36596427480` passed all jobs and 26 Python tests, including the two lifecycle probe wiring tests. Validation rule: do not promote AXIOM beyond `static` until an actual deep workflow run on the exact game commit succeeds. The probe is designed to produce stronger evidence, not to predeclare it.

---

# Handoff — 2026-09-29

## AXIOM-7 0.8.2.8 Integrity

Active task branch: `mod/axiom_7/integrity-0.8.2.8`. Pull request: #9. Base at task start: `main` commit `30590a14654f2b8061c07b9d1ccf51c6262396d8`. Exact game target remains `experimental-2026-09-23-0546` / `e262adb299a7613b4aedc5f12c08fe0413c56a84`.

Implemented:
- fixed two surface patrol waypoints that resolved onto walls;
- fixed two rooftop patrol routes that incorrectly used 72x48 composite coordinates instead of CDDA patrol coordinates relative to the monster's local 24x24 OMT;
- added `tests/test_axiom7_integrity.py` covering composite dimensions, spawn bounds, patrol resolution, cardreader/lock proximity, stair alignment, KX-91 footprints and all six vehicle swaps, KX state transitions, mission-offer wiring, and security EOC coverage;
- bumped AXIOM to 0.8.2.8 without changing existing IDs or save variables.

Validation: PR #9 workflow run `36592734678` passed all normal CI jobs: verify, package build, PowerShell 5.1/7 installer tests, Python tests (24 total, including all 13 AXIOM integrity tests), Survivor native build, and AWS native build. AXIOM is marked `static`, not `load-tested` or `runtime-tested`.

Still required before a stronger compatibility claim: run the exact-game real-CDDA/deep gate for 0546, generate/load AXIOM in a fresh world, exercise clearance and KX-91 restoration/custody in gameplay, and specifically verify NPC/turret/patrol IFF after aircraft interaction. Do not promote beyond `static` from this handoff alone.

---

The private Neversalimus/CDDA-Mods repository is populated; initial import 14bafb0, CI setup d4c2ac5. Read AGENTS.md and STATUS.md, then refresh remote HEAD and latest Actions before editing. Repository access can differ between chats, so verify it instead of assuming an old access state. Never overwrite another chat's changes.

This update imports module-only Survivor 0.9.15 cumulative v8.7.3, archives 0.9.10, and fixes PS 5.1 root-array handling during duplicate mod detection. Provenance is in catalog/provenance.json. SDK recipe is header-only and hash-bound; external NCMM host remains excluded. SOURCE_SHA256.json describes the initial import, not later git commits.

Windows CI [36319464027](https://github.com/Neversalimus/CDDA-Mods/actions/runs/36319464027) passed on source commit `2d10f4708e0e3e0178999a1397a342ad73e48c52`, including PS 5.1/7 tests, Python tests and both current native DLL builds. The release workflow independently retests the release commit.

Deep-runtime infrastructure now lives in `.github/workflows/deep-runtime.yml`, `tools/deep_cdda_runtime.py`, `tools/deep_install_matrix.ps1` and `tools/fetch_cdda_release.py`. It has no push/PR trigger. Weekly runs are on by default; set repository variable `CDDA_DEEP_TESTS_ENABLED=false` to disable them during active development. Manual modes are load/full/exhaustive. Windows deep CI also exercises the shipped installer through install/repeat/update/rollback plus negative lifecycle cases on the exact official game. Artifacts retain engine logs and hash-bound reports. Native NCMM modules remain outside this vanilla runtime gate.

Next: verify the v0.1.0 PREVIEW release in GitHub Releases, then download its bundle after signing into GitHub. Test exact Windows game baseline + selected individual mods + combined stack with tools/verify_game.py or the new deep workflow. Compare Secronom reconstruction with the user's working pair. Promote only matching successful reports. Verify Survivor API 1.8/gameplay hooks, UI and save migration against external NCMM before allowing DLL installation. Prepare new targets for named mods only, preserving prior variants. Do not recreate repository or rerun initial importer.

Native refresh: AWS 0.6.1 and Survivor 0.9.15 revision 1 from v8.7.3 are source-only. Old AWS 0.5.0 DLL is history-only; both current native installs are blocked pending compatible external API 1.8 host. Module source audits and g++ checks passed. No host/game installer ran.

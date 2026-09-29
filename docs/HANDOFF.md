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

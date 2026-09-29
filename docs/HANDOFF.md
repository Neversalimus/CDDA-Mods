# Handoff — 2026-09-27

The private Neversalimus/CDDA-Mods repository is populated; initial import 14bafb0, CI setup d4c2ac5. Read AGENTS.md and STATUS.md, then refresh remote HEAD and latest Actions before editing. The connector currently lacks private-repository access; owner authorized browser uploads. Never overwrite another chat's changes.

This update imports module-only Survivor 0.9.15 cumulative v8.7.3, archives 0.9.10, and fixes PS 5.1 root-array handling during duplicate mod detection. Provenance is in catalog/provenance.json. SDK recipe is header-only and hash-bound; external NCMM host remains excluded. SOURCE_SHA256.json describes the initial import, not later git commits.

Windows CI [36319464027](https://github.com/Neversalimus/CDDA-Mods/actions/runs/36319464027) passed on source commit `2d10f4708e0e3e0178999a1397a342ad73e48c52`, including PS 5.1/7 tests, Python tests and both current native DLL builds. The release workflow independently retests the release commit.

Deep-runtime infrastructure now lives in `.github/workflows/deep-runtime.yml`, `tools/deep_cdda_runtime.py`, `tools/fetch_cdda_release.py`, `tools/run_deep_install_matrix.ps1` and `tests/deep_runtime_matrix.json`. It has no push/PR trigger; scheduled runs require `CDDA_DEEP_TESTS_ENABLED=true`. Manual modes are load/full/exhaustive and artifacts retain engine logs plus hash-bound reports. The official Windows job also runs the release installer through clean install, idempotent reinstall, receipt update, rollback and reinstall-after-rollback on pristine copies. Native NCMM modules remain outside this vanilla runtime gate.

Next: verify the v0.1.0 PREVIEW release in GitHub Releases, then download its bundle after signing into GitHub. Test exact Windows game baseline + selected individual mods + combined stack with tools/verify_game.py or the new deep workflow. Compare Secronom reconstruction with the user's working pair. Promote only matching successful reports. Verify Survivor API 1.8/gameplay hooks, UI and save migration against external NCMM before allowing DLL installation. Prepare new targets for named mods only, preserving prior variants. Do not recreate repository or rerun initial importer.

Native refresh: AWS 0.6.1 and Survivor 0.9.15 revision 1 from v8.7.3 are source-only. Old AWS 0.5.0 DLL is history-only; both current native installs are blocked pending compatible external API 1.8 host. Module source audits and g++ checks passed. No host/game installer ran.

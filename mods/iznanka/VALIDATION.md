# Candidate validation

Target: `cdda-experimental-2026-10-06-1807`
Source: `074aa98bd5be3de4c35f154082db32a0e63bb0f1`

- Official Linux release `--check-mods iznanka`: passed, exit 0, clean debug log.
- Repository manifest validation and package build: passed.
- Existing Python tests: 76 passed; two new sprite/layout contract tests passed.
- Exact-source lifecycle and combined stack: running after blocked-landing hardening.
- Earlier lifecycle probe reached 58 assertions before a harness-only reload bug;
  it now calls the normal Save-and-Quit cleanup before loading.
- SDL software renderer loads the Hybrid atlas; full scene review is pending.
- Windows installer (PowerShell 5.1/7), Python and native snapshot gates:
  passed on initial candidate 5e6cdc496b6b7c4a0dae92f72576a0638081b9eb
  (Actions 37968254773). Final head must be rerun.

This is a candidate until the remaining gates pass. No compatibility claim is
made for other experimental tags.

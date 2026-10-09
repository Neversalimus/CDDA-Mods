# Candidate validation

Target: `cdda-experimental-2026-10-06-1807`
Source: `074aa98bd5be3de4c35f154082db32a0e63bb0f1`

- Official Linux release `--check-mods iznanka`: passed, exit 0, clean debug log.
- Repository manifest validation and package build: passed.
- Existing Python tests: 76 passed; two new sprite/layout contract tests passed.
- Exact-source lifecycle, combined stack and graphical smoke: running.
- Windows installer and native snapshot gates: CI pending.

This is a candidate until the remaining gates pass. No compatibility claim is
made for other experimental tags.

# AXIOM-7

## 0.8.2.8 — Integrity

- Corrected two surface patrol routes whose waypoints resolved onto blocked terrain.
- Corrected two rooftop patrol routes that used composite-map coordinates where CDDA expects coordinates relative to the monster's local 24x24 OMT.
- Added AXIOM-specific semantic regression tests for composite map dimensions, static spawn bounds, patrol resolution, access-reader locks, vertical stairs, KX-91 airframe footprints and state swaps, mission offer wiring, and security EOC coverage.
- Preserved all existing AXIOM IDs and save variables. No save migration is required by this pass.
- Exact-game runtime validation is still pending; this version is not promoted beyond static validation until CI and the real-CDDA gate succeed.

## Initial repository import

Version 0.8.2.7. Imported separately from NCMM.
See catalog/provenance.json and docs/STATUS.md for evidence and pending checks.

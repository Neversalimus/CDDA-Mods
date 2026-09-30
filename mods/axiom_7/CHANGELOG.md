# AXIOM-7

## 0.8.2.8-r2 — Exhaustive invariant cleanup

- Raised the three AXIOM access-card volumes from 5 ml to 6 ml so their 6 g plastic mass no longer exceeds CDDA's material-density invariant.
- Removed legacy `to_hit` fields from the three access cards.
- Removed one-way hostility toward `fungus` and `triffid` from the AXIOM security monster faction; zombie, aquatic-zombie and nether hostility remains.
- Added regression tests for these exact exhaustive-test findings.
- No IDs, mission state, access flags, spawn data, combat stats, or save variables changed.

## 0.8.2.8 — Integrity

- Corrected two surface patrol routes whose waypoints resolved onto blocked terrain.
- Corrected two rooftop patrol routes that used composite-map coordinates where CDDA expects coordinates relative to the monster's local 24x24 OMT.
- Added AXIOM-specific semantic regression tests for composite map dimensions, static spawn bounds, patrol resolution, access-reader locks, vertical stairs, KX-91 airframe footprints and state swaps, mission offer wiring, and security EOC coverage.
- Preserved all existing AXIOM IDs and save variables. No save migration is required by this pass.
- Added an exact-engine AXIOM lifecycle probe for the deep CDDA workflow. It exercises generated surface/basement/roof tiles, key NPC/security spawns, clearance mission end-effects, KX-91 vehicle swaps, and the security alarm EOC inside the pinned CDDA `cata_test` runtime.\n- Exact-game runtime validation is still pending until that deep workflow actually completes; this version remains `static` meanwhile.

## Initial repository import

Version 0.8.2.7. Imported separately from NCMM.
See catalog/provenance.json and docs/STATUS.md for evidence and pending checks.

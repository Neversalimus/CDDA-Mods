# UndeadPeople Hybrid v3 + all patches

## 2026-10-04 — Sprite clarity candidate (3.1.1-r4)

Baseline: `74b6a739d4280f936f26c15b0d89a5614cdb855b`.
The screenshot's `mon_zombie_dwarf` resolved to Ultica foreground 39281 plus
shadow 39490, not the additional monster atlas. A new isolated 32x32 sprite
replaces that mapping; existing atlas dimensions/indices remain unchanged.
The additional atlas contains 280 cells referenced by 294 IDs. Its alpha is
already binary, so alpha cleanup alone cannot solve its noisy detail/style.
A whole-sheet image-generation attempt was rejected because it moved cell
boundaries. That output is not shipped. The remaining 294-ID atlas is unchanged
and still requires individual artistic review; this is a partial visual fix.
Validation: modsuite validate/build passed (8 packages), six targeted tests passed;
only the dwarf mapping changed, the 32x32 image has binary alpha and a ground
margin. No new game compatibility claim. In-game verification and CI pending.


## 3.1.1-r2 — Documentation sync

- README/report/source-note sync only; tileset graphics/mappings unchanged.

## Initial repository import

Version 3.1.1. Imported separately from NCMM.
See catalog/provenance.json and docs/STATUS.md for evidence and pending checks.

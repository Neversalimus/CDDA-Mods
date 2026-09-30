# Aftershock Prime

## 0.1.14a-r2 — Safe exhaustive invariant cleanup

- Removed 18 legacy numeric `to_hit` fields from non-melee utility items, wrecks, mounted weapons and robot items identified by the exact-source test.
- Raised the inherited ETC firmware physical length from 1 cm to 25 mm so its 50 ml volume satisfies the current geometry invariant.
- Added explicit valid broken-item targets for the UICA Irradiant, UICA Regulator and floating lantern variants.
- Raised six 6 g plastic access cards from 5 ml to 6 ml to satisfy the current material-density invariant.
- Converted legacy core `zombie`, `human`, `herbivore` and `wolf` faction copies to `extend` semantics so Aftershock no longer erases vanilla relations; added reciprocal custom machine/reaver relations where the exact-source test exposed one-way attitudes.
- No weapon damage, armor, monster combat stats, spawn weights or crafting quantities changed.

## Initial repository import

Version 0.1.14a. Imported separately from NCMM.
See catalog/provenance.json and docs/STATUS.md for evidence and pending checks.

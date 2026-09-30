# Aftershock Prime

## 0.1.14a-r4 — Calorie sanity and inherited WIP metadata

- Preserved the authored calories of nutriment and Spite Soda while raising their physical mass to remain below the engine's maximum plausible calorie density; nutriment volume is now 50 ml.
- Marked the inherited short COMBAT_BRUTE pre-threshold tree as `wip`. In this pinned engine revision, `wip` is consumed only by mutation tests and does not alter mutation gameplay or availability.
- No mutation points, combat bonuses, calories, addiction effects or post-threshold traits changed.

## 0.1.14a-r3 — Mutation tree restoration

- Restored 46 pinned upstream self-copy mutation overlays that the generic collision pruner incorrectly treated as disposable duplicates.
- Restored MIGO, MASTODON and COMBAT_BRUTE membership and inherited mutation links without duplicating vanilla trait bodies.
- Added a hidden HUMAN baseline mutation that gives the current purifier system an explicit reverse path for 16 reversible Aftershock-only mutations.
- Updated the recovery builder so future Prime rebuilds preserve semantic mutation overlays automatically instead of pruning them as ID collisions.

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

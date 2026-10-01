# Secronom Revival

## 1.5.1-r4 — Documentation sync

- README support/provenance sync only; gameplay payload unchanged.

## 1.5.1-r3 — Exact runtime compatibility

- Removed the invalid relation to the nonexistent pinned-CDDA `blob` monster faction, eliminating the loader circular-dependency error.
- Migrated KAC ChainSAW, XM556 and XM8 magazine wells to explicit `firing_requirements`, matching current multimag vehicle-turret semantics.
- Normalized the two remaining base Secronom flesh-density violations by preserving weight and using physically valid volumes.
- The intentional `zombie_weaver` targeting relationship is left unchanged for a dedicated semantic pass.

## 1.5.1-r2 — Broken robot corpse integrity

- Added explicit broken robot wreck items for the reinforcer, shocker, rifle walker and launcher.
- Wired the four BROKEN-death monsters to those valid item IDs instead of relying on invalid auto-derived IDs.
- Preserved monster stats, attacks, factions, spawn data and existing death-drop groups.
- Reworked legacy `human`, `animal` and `insect` monster-faction overrides into `copy-from + extend`, preserving vanilla relations while keeping Secronom's intended fleshweaver/security relationships.
- Added reciprocal root-faction relations for fleshweaver, saddler, carrion and AXIOM-style security-bot interactions without changing monster stats or spawns.

## 1.5.1 complete text-style cleanup

Resolved the remaining 985 exact-source text-style diagnostics reported by CDDA's
`text_style_check_reader`. Each fix follows the engine's own punctuation rule:
sentence-ending punctuation now has the expected spacing only at checker-reported
locations. No IDs, mechanics, spawn data, effects, balance values, or JSON
structure changed.

## 1.5.1 text-style cleanup

Normalized only diagnostics identified by the exact-source text-style checker:
28 legacy three-dot ellipses were replaced with the preferred ellipsis character,
and one trailing space was removed. No IDs, mechanics, spawn data, effects, or
balance values changed.

## Initial repository import

Version 1.5.1. Imported separately from NCMM.
See catalog/provenance.json and docs/STATUS.md for evidence and pending checks.

# Blazemod Revival

## 0.5.5-r4 — Exact material-density normalization

- Corrected the physical volume of all 72 items reported by the pinned exact-source material-density invariant.
- Each new volume is the smallest practical rounded value above the current material-density limit, with a small safety margin.
- Ammo stack/count semantics were preserved: per-charge physical volume was corrected and then converted back to the JSON stack volume.
- Weight, damage, armor penetration, ammunition counts, vehicle capacity and crafting recipes are unchanged.
- No synthetic high-density blob material was introduced; legacy flesh/blob items continue to use their authored materials.

## 0.5.5-r3 — Modular turret compatibility

- Removed three legacy vehicle turret definitions that mounted CDDA modular receivers (`modular_m4_carbine`, `modular_ar15`, `modular_ump`) as if they were complete guns.
- Those pinned-CDDA receiver items explicitly use `ammo: NULL` and `NO_TURRET`; retaining manual turret parts produced unfireable vehicle weapons.
- No functional Blazemod gun, projectile, damage value or ammunition definition changed.

## 0.5.5-r2 — Vehicle-part metadata cleanup

- Added current CDDA vehicle-part categories to all 76 parts identified by the exact-source exhaustive invariant.
- Added the required `DOOR` flag to six blob hatches that were already `OPENABLE` and `BOARDABLE`.
- Categories follow actual function: movement, hull, warfare, passengers, cargo, lighting, operations or energy.
- No part durability, damage, mass, volume, fuel, weapon or recipe values changed.

## Initial repository import

Version 0.5.5. Imported separately from NCMM.
See catalog/provenance.json and docs/STATUS.md for evidence and pending checks.

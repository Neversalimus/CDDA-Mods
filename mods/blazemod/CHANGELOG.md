# Blazemod Revival

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

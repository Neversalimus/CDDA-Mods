# Blazemod Revival

## 0.5.5-r7 — Blob projectile-effect registry cleanup

- Migrated the legacy acid-puffer ammo effect from `ACID_BOMB` to the current pinned-CDDA `ACIDBOMB` registry ID.
- Removed `CUSTOM_EXPLOSION` from the fuel puffer and gel spouter ammo-effect lists.  In the pinned engine that token is no longer a registered ammo effect; its remaining hardcoded path only copies explosion data from the loaded ammunition, while gasoline and water define no such explosion, so removal preserves current projectile behavior and eliminates runtime D_ERRORs.
- Preserved `JET`, `WIDE`, `BEANBAG`, `BLINDS_EYES`, `ACT_ON_RANGED_HIT` and `NO_EMBED` behavior unchanged.

## 0.5.5-r6 — Legacy ammo-effect migration

- Removed obsolete `NEVER_MISFIRES` ammo-effect references; mounted guns already use the current `NEVER_JAMS` item flag, while ammunition no longer has a current engine-side equivalent for that retired pseudo effect.
- Restored `MININUKE_MOD` as a current JSON ammo effect instead of dropping the authored nuclear projectile behavior.
- The modernized effect keeps the legacy 24-tile nuclear-gas field and a 3000-power impact explosion.
- No ordinary projectile damage, magazine capacity, gun dispersion or crafting recipes changed.

## 0.5.5-r5 — Uncraft mass conservation

- Updated the legacy lead-ball recipe from 100 to 80 lead units so its reversible craft returns the same 400 g mass.
- Raised the coilgun pipe count to match the finished weapon mass without changing weapon stats.
- Modernized the handmade .308 carbine recipe to use a small gun-sized spring and short plank, preserving its pipe-and-wood construction while removing obsolete multi-kilogram components.
- Preserved all seven authored adult-blob → two-grow-form splits; grow-form masses now equal half their adult form instead of creating extra mass on uncraft.
- Converted four old 200-charge water assumptions to current charge semantics for blob wheel/hull recipes.
- No gun damage, blob abilities, transform timers or adult blob weights changed.

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

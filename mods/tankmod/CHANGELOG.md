# Tankmod Revived

## 2026.9.23.4-r3 — Exact-derived physical data repair

- Corrected the broken Mini-Tank UAFV wreck from 45,000 kg / 900 L to 4,500 kg / 1,000 L.  The new mass is within 5% of its exact-source salvage component mass (4,732.212 kg) and satisfies the steel/plastic density invariant.
- Aligned the reversible electric tank primer and artillery primer masses with their exact recipe component masses: 45 g and 51 g.
- No ammunition damage, penetration, weapon stats, crafting components or salvage quantities changed.

## 2026.9.23.4-r2 — Exhaustive schema cleanup

- Removed the 15 legacy numeric `to_hit` fields reported by the exact-source item invariant.
- Added the current `movement` vehicle-part category to the three tread parts.
- No weapon damage, dispersion, ammo, vehicle durability or crafting quantities changed.

## Initial repository import

Version 2026.9.23.4. Imported separately from NCMM.
See catalog/provenance.json and docs/STATUS.md for evidence and pending checks.

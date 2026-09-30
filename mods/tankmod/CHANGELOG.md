# Tankmod Revived

## 2026.9.23.4-r6 — Custom explosion compatibility

- Registered the hardcoded `CUSTOM_EXPLOSION` projectile marker as a no-op ammo effect for current CDDA.
- Tank shells keep their existing per-item `explosion` power and distance settings; the registration only prevents the current ammo-effect factory from treating the hardcoded marker as an invalid ID.
- No ammunition damage, blast power, shrapnel, recoil or range values changed.

## 2026.9.23.4-r5 — Shell salvage mass restoration

- Restored missing inert metal mass in eight legacy 25/105/120/155 mm uncraft recipes using standard steel salvage components.
- Each dismantling recipe now returns 90–100% of the shell's mass, satisfying the exact-source uncraft invariant while retaining a small disassembly loss.
- AP/APDS recipes deliberately do not return radioactive uranium: the original Tankmod explicitly avoided that hazard, so the recovered penetrator/sabot mass remains abstracted as steel.
- Ammunition damage, penetration, recoil, casing IDs and explosive components are unchanged.

## 2026.9.23.4-r4 — Legacy volume normalization

- Normalized legacy volume semantics for the two 25 mm ammo stacks and nine heavy-gun items so exact runtime density no longer exceeds their material limits.
- Mass, damage, penetration, recoil and magazine capacity remain unchanged.

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

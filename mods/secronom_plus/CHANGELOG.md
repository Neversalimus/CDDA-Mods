# Secronom+ Revival

## 0.3.4-r4

- Removed the obsolete `NEVER_MISFIRES` token from bone-needle ammo effects. Current CDDA has no ammo effect by that ID; `NOGIB` and `NON_FOULING` remain valid and unchanged.
- This fixes the exact-runtime initialization error without changing projectile damage, dispersion, count, material or valid ammo effects.

## 0.3.4-r3

- Encode artificial flesh density as 1.6 to match authored equipment without altering item mass or capacity.
- Correct legacy physical dimensions for Secronom+ bio-organic tools, DNA samples, ID cards, power-armor modules, flesh-mech wrecks and the integrated spike launcher.
- Use reinforced flesh for dense bio-organic hardware where the description and existing material system already imply reinforced tissue.
- These changes address exact-engine material-density invariants only; combat stats, crafting outputs and spawn data are unchanged.

## 0.3.4-r2

- Preserve the legacy sinew recipe output explicitly with `charges: 10`, removing the exact-engine recipe warning without changing gameplay output.

## Initial repository import

Version 0.3.4. Imported separately from NCMM.
See catalog/provenance.json and docs/STATUS.md for evidence and pending checks.

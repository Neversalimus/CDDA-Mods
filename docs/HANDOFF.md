# Handoff — 2026-10-01

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


Repository: `Neversalimus/CDDA-Mods`.

Code baseline before this documentation sync:
`8ec3ac49f625448793f59a106a82bcba02f90e73`.

## Current working state

Supported game targets:

- `experimental-2026-09-23-0546` /
  `e262adb299a7613b4aedc5f12c08fe0413c56a84`;
- `experimental-2026-10-01-1040` /
  `3f7fb352bf492ba521bd9408a0c9f6ce239e8d83`.

Normal CI `36868930324` is GREEN, including Windows PowerShell 5.1/7 installer
tests and both native snapshot build jobs.

A real CatLauncher `1040` installation of `profile:all-content` succeeded after
two installer hardening fixes:

- delayed PackageRoot resolution for PowerShell 5.1;
- short `%TEMP%\CDM-*` extraction/validation scratch root to avoid MAX_PATH.

Durable rollback remains under `<game>/_CDDA-Mods/transactions`.

## Aftershock Prime

Prime is now `0.1.14a-r5`. Wraitheon Gryphon is selectively imported from
upstream Aftershock commit `d65c89e0`, without Salus/UICA mapgen. It spawns only
via additive weight-1 entries in `mil_helicopters_small` and
`crashed_helicopters`. Targeted exact-`1040` Prime vehicle/parts runtime passed.

## Mod tileset compatibility

The repository-wide mod asset audit found mod-specific tilesets only in
Blazemod (base + Blaze Industries), Secronom and Tankmod. All four
`mod_tileset.json` compatibility lists now explicitly include
`UndeadPeople_0J_Hybrid_v3`. Secronom+ has no separate tile sheet and continues
to use Secronom's graphics. No tile IDs, sprite indices or gameplay data changed.

Current affected package revisions are Blazemod `0.5.5-r9`, Secronom
`1.5.1-r5` and Tankmod `2026.9.23.4-r7`.

## Experimental automation

`experimental-watch.yml` automatically discovers new experimental releases.
`experimental-certify.yml` gates them through official release, exact source,
combined stack and items/recipes/vehicles/overmap before promotion.

Candidate `2026-10-01-1124` / `cb7701da...` passed every runtime/content gate.
Its promotion was rejected because `main` moved during the long run; that run
started before the stale-main auto-requeue fix existed. It is therefore tested but
not yet registered as supported.

## Native note

Do not revive the old assumption that AWS 0.6.1 / Survivor 0.9.15 here are the
current player modules. They are installer-disabled source snapshots. Current
native delivery belongs to `Neversalimus/NCMM`.

## Next step

Re-run/promote `1124` on current main, then return to actual mod development.
Do not create new exhaustive infrastructure unless a real test gap is found.

Historical handoffs remain available in git history; this file intentionally
describes only the current state.

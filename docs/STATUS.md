# Current status — 2026-10-09

## Изнанка 0.2.0 — town / UDP art verified

0.1.0 merged as PR #19 (`a2c86378299095ff137f4c7a14941a797e5d4b45`); all
its CI passed. New independent town branch, technical/combat solutions, three
threats, suppressor and UDP-style replacement art. Exact target remains 1807 /
`074aa98bd5be3de4c35f154082db32a0e63bb0f1`. Validation and outstanding work:
[mods/iznanka/VALIDATION.md](../mods/iznanka/VALIDATION.md).
PR #20 carries the continuation. Official loader and 78 Python tests pass;
grove terrain was verified in the official graphical client after fixing opaque
ground behind trees. Discovery rejects a cached non-town position. Full current
standalone/combined lifecycle passed 146/146 and 146/146 assertions in run
37997534838 on `cc19b2d52ee031cfde6f07f00c80f52c1790dafa`; normal CI
37997534832 also passed. Manifest is runtime-tested. The first combined run's
incorrect last-entry expectation was fixed in the probe; its failed evidence and
old 0.1.0 evidence remain archived. PR #20 is ready for review, not merged.
Only evidence/docs/validation metadata changed after the tested payload.


## Изнанка 0.1.0 — first playable expedition

Added a separate `iznanka` installer profile (mod + UndeadPeople Hybrid), limited
to exact CDDA `2026-10-06-1807` / `074aa98bd5be3de4c35f154082db32a0e63bb0f1`.
Forest portal, persistent dimension, refuge/woods/marsh expedition, five enemies,
six items, one progression node and 20 sprites. Full design expansion is pending.
Official Linux loader passed. Exact-source standalone and combined lifecycle each
passed 70 assertions, including save/reload and blocked return. The official graphical
release loaded the saved active pump. All 78 Python tests and package checks passed.
Windows CI evidence and limits: [Iznanka validation](../mods/iznanka/VALIDATION.md).
Existing all-content selection and native modules are unchanged.


## 2026-10-09 — Complete generated-art review (UndeadPeople 3.1.1-r5)

Baseline: `f8debb4f8b8177f59fa65bf5602765f776d34e8b`.
Reviewed 282 cells across all three generated PNGs: 281 used cells, 296 tile IDs.
Redrew 178 sprites affecting 186 IDs; preserved all other cells, source mappings,
atlas geometry/indices and upstream donor art. Fixed noisy native-size detail,
weak silhouettes, dwarf/ravenfolk readability and fungal construct size progression.

Source and packaged sprite audits passed (72/75 PNG sheets, 46,008/48,925 sprite
references). Eight installable packages built; all 76 Python tests passed locally.
Normal Windows CI is the installer/native gate; no new gameplay or compatibility
claim is made. Interactive in-game display/zoom verification remains outstanding.

Full per-cell review, hashes, before/after panels and verification instructions:
[`mods/undeadpeople/art-review`](../mods/undeadpeople/art-review/README.md).
The 2026-10-04 partial-artwork status below is superseded by this complete review.

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


## Repository baseline

Current code baseline before this documentation sync:
`8ec3ac49f625448793f59a106a82bcba02f90e73`.

Normal CI run `36868930324` is fully GREEN:

- verify/package;
- Windows PowerShell 5.1 installer tests;
- PowerShell 7 installer tests;
- Python maintenance tests;
- Survivor Progression native snapshot build;
- Advanced World Settings native snapshot build.

## Supported CDDA targets

| Target | Exact commit | Repository support |
|---|---|---|
| experimental-2026-09-23-0546 | `e262adb299a7613b4aedc5f12c08fe0413c56a84` | registered/supported |
| experimental-2026-10-01-1040 | `3f7fb352bf492ba521bd9408a0c9f6ce239e8d83` | registered/supported |

For `1040`, official release loader and exact-source build succeeded. Recipes and
vehicles passed the temporary content recheck. The old items/overmap recheck was
run before portable inherited-debt normalization and must not be interpreted as a
new mod regression. The items failure was explicitly the already-known
Aftershock Prime + MoM inherited signature (104 density + 80 uncraft diagnostics).

The newer `1124` candidate
(`cb7701daa21338fffbbeb4b8c03bd3e26b2a0cb5`) passed:

- exact candidate cata_test build;
- official release loader;
- exact-source full combined-all-json;
- items;
- recipes;
- vehicles;
- overmap.

Its first promotion job failed only because `main` had changed from the SHA being
tested. That run used the pre-requeue workflow revision, so `1124` is not yet
published in `catalog/targets`. Future runs use the updated stale-main requeue
logic.

## Installer

Two Windows-specific defects discovered during a real CatLauncher installation
were fixed:

1. PowerShell 5.1 could bind default `PackageRoot=$PSScriptRoot` as an empty
   string inside the param block. PackageRoot is now resolved after script
   initialization.
2. Staging under a long CatLauncher game path could exceed legacy Win32 MAX_PATH
   for deep Secronom files. Extraction/validation now use short
   `%TEMP%\CDM-*` scratch paths; durable backup/journal remains beside the game.

After both fixes, a real CatLauncher installation of `profile:all-content` on
`2026-10-01-1040` completed isolated validation and installation with
`Exit code: 0`. No saves are modified.

## Aftershock Prime

Current package revision: `0.1.14a-r6` (Gryphon gameplay import was introduced in r5; r6 only synchronizes documentation/provenance).

Base curated snapshot remains CDDA/Aftershock at `e262adb`. A selective upstream
addition imports Wraitheon Gryphon from Aftershock commit `d65c89e0`:

- `wraitheon_aerodyne`;
- `aerodyne_engine`;
- `engine_turbine_large`;
- `afs_aerodyne_engine`;
- `afs_aerodyne_powerplant`.

Gryphon is added only to `mil_helicopters_small` and `crashed_helicopters`
with weight 1. UICA/Salus mapgen, factions and world replacement are not imported.
Exact `1040` Prime vehicle registry/parts test passed.

## Mod tileset compatibility audit

All current mod directories were checked for mod-specific sprite sheets and
`mod_tileset` definitions. Only Blazemod, Secronom and Tankmod ship their own
mod tilesets; Secronom+ has no separate sprite sheet and relies on base Secronom.
Their compatibility arrays now explicitly include the current tileset ID
`UndeadPeople_0J_Hybrid_v3`. Other current mods have no mod-tileset payload to
gate on the base tileset ID.

## Current component versions

- AXIOM-7 0.8.2.8-r2;
- Blazemod 0.5.5-r9;
- Secronom 1.5.1-r5;
- Secronom+ 0.3.4-r5;
- Aftershock Prime 0.1.14a-r6 (r5 introduced Gryphon; r6 is documentation-only);
- Aftershock Prime / MoM 0.1.14a-r2;
- Tankmod 2026.9.23.4-r7;
- UndeadPeople 3.1.1-r5;
- AWS 0.6.1-r3 source snapshot, installer-disabled;
- Survivor Progression 0.9.15-r2 source snapshot, installer-disabled.

Manifest validation fields still include historical `pending/static` values. They
are not automatically rewritten by the deep candidate workflow and should not be
confused with absence of runtime evidence.

## Native ownership

The current NCMM host and current Survivor/AWS runtime modules are maintained in
`Neversalimus/NCMM`. The native trees here are preserved source snapshots and are
not what players should install for current NCMM.

## Next practical work

1. Re-certify/promote `2026-10-01-1124` against current `main`.
2. Let the watcher handle later experimentals; investigate only real red candidates.
3. Avoid adding more broad CI infrastructure unless a concrete blind spot appears.
4. Continue mod content work with the compatibility infrastructure treated as
   stable unless tests expose a defect.

# Current status — 2026-10-01

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

Current version: `0.1.14a-r5`.

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

## Current component versions

- AXIOM-7 0.8.2.8-r2;
- Blazemod 0.5.5-r7;
- Secronom 1.5.1-r3;
- Secronom+ 0.3.4-r5;
- Aftershock Prime 0.1.14a-r5;
- Aftershock Prime / MoM 0.1.14a-r1;
- Tankmod 2026.9.23.4-r6;
- UndeadPeople 3.1.1-r1;
- AWS 0.6.1-r2 source snapshot, installer-disabled;
- Survivor Progression 0.9.15-r1 source snapshot, installer-disabled.

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

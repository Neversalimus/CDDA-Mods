# Current development notes — 2026-10-01

The repository is now beyond the original `v0.1.0` PREVIEW snapshot. The immutable
old release/tag remains historical; current `main` contains newer compatibility,
runtime-test and installer fixes.

## CDDA 2026-10-01-1040

Registered exact target:

- tag: `cdda-experimental-2026-10-01-1040`;
- commit: `3f7fb352bf492ba521bd9408a0c9f6ce239e8d83`.

Official release loading and exact-source build passed. Current content has also
been exercised by the newer generic candidate harness on `1124`, where combined
source + items/recipes/vehicles/overmap are all GREEN.

## Installer hardening

Windows installer now supports long CatLauncher roots safely:

- PackageRoot is resolved after PowerShell script initialization;
- extraction and isolated validation use short `%TEMP%\CDM-*` paths;
- transaction journal and backups remain durable under
  `<game>/_CDDA-Mods/transactions`;
- PowerShell 5.1 and PowerShell 7 tests are both GREEN.

A real CatLauncher installation on `1040` using `profile:all-content` completed
successfully with `Exit code: 0`.

## Aftershock Prime 0.1.14a-r6

Gryphon was introduced in r5; r6 is documentation/provenance-only. Current selective import:

- new aerodyne vehicle + two new vehicle parts + two backing part-items;
- weight 1 in `mil_helicopters_small`;
- weight 1 in `crashed_helicopters`;
- no Salus IV/UICA world/mapgen import.

Exact-`1040` Prime vehicle and vehicle-parts runtime passed.

## Automatic experimental compatibility

The repository now watches official CDDA experimental releases hourly. Every
unseen release is tested before promotion through:

- official release loader;
- exact source;
- full combined JSON stack;
- items;
- recipes;
- vehicles;
- overmap.

Known inherited upstream debt is accepted only by strict signature matching.

## Native modules

AWS 0.6.1 and Survivor Progression 0.9.15 in this repository remain
installer-disabled source snapshots. Current NCMM host/module releases are owned
by the separate NCMM repository.

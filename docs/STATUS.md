# Current status — 2026-09-26

## Version refresh

Latest archives were searched again after the user's explicit warning that work
continued in other chats. Current selected versions: AXIOM 0.8.2.7; Prime
Hotfix14a/installer 1.1.1; Survivor 0.9.10 clean v13. Blazemod 0.5.5, Secronom
builder 2.0, Tankmod Fix4 and UDP FULL remained the latest matching artifacts.
Previous imported versions live under history/ and are not installation defaults.

## Implemented

- Ten independently described components; complete current JSON/tileset payloads.
- Native AWS 0.5.0 source + original binary; latest Survivor 0.9.10 source.
- Windows PowerShell installer: discovery, selection, dependencies, exact game
  commit matching, package/file hashes, pre-install engine validation, backups,
  transaction journal, group rollback, explicit rollback with local-edit guard.
- Offline full bundle and separate mod ZIPs. Online per-mod updates after release.
- Stable/experimental target preparation and immutable old variants.
- Native CI compilation against external pinned NCMM SDKs; runtime excluded.
- Chat/worktree workflow, handoff templates, provenance and maintenance CLI.

## Verification actually completed

- Catalog and 630 current payload JSON files parse; descriptors, IDs, dependency
  graph and tileset image references checked.
- Blazemod recovery's semantic assertions and vanilla collision audit passed.
- Prime Hotfix14a recovery's static completeness and collision gates passed.
- All 30 installer transaction/security/dependency assertions passed under
  PowerShell 7/Linux, including interrupted rollback and receipt restoration.
- Four Python maintenance tests passed. CLI PlanOnly successfully identified
  the exact game commit and planned AXIOM 0.8.2.7 without changing game files.
- Both native module sources passed g++ C++17 syntax checking against their pinned
  external SDK headers. This is not a Windows DLL build or gameplay test.

## Not yet completed / do not claim otherwise

- The private GitHub repository Neversalimus/CDDA-Mods was created on September
  26. Source import and Windows CI are being completed. The GitHub connector
  cannot currently access it; the owner authorized browser upload.
- Windows PowerShell 5.1/Windows filesystem testing runs in the supplied CI after
  push; has not run in this Linux environment.
- Exact target is experimental-2026-09-23-0546 / e262adb299a7613b4aedc5f12c08fe0413c56a84.
  Attempted Linux engine baseline checks did not complete within the timeout;
  after correcting missing gfx in the terminal distribution no clean baseline
  result was obtained. No package is falsely labelled load-tested.
- Secronom payload is a reconstruction, not an export of the user's final working
  tandem; validator-directed text fixes may still differ. Native validation is
  required. The installable snapshot remains pending.
- Survivor 0.9.10 DLL/required host are not silently replaced with 0.9.0. It is
  source-only until Windows native CI and compatible host checks are complete.
  Host changes from CLEAN_v13 belong to NCMM and were not imported here.
- Other stable/experimental versions have no compatibility claim yet.

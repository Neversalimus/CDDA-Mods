# Current status — 2026-09-27

Source import is complete in private Neversalimus/CDDA-Mods (14bafb0); CI enabled in d4c2ac5. NCMM remains external.

Current versions: AXIOM 0.8.2.7; Blazemod 0.5.5; Secronom 1.5.1 + expansion 0.3.4 reconstructed; Prime Hotfix14a / installer 1.1.1; Tankmod Fix4; UDP v3 FULL; AWS 0.6.1; Survivor 0.9.15 cumulative v8.7.3. Refresh cutoff: 2026-09-27 12:27 UTC (15:27 Moscow); latest available archive v8.7.3, v8.7.4 not available in search. Prior Survivor 0.9.10 is preserved in history.

Implemented: independent packages and checksums; Windows installer with selection/dependencies, exact game binding, pre-install validation, backup and transactional group rollback; target preparation for stable/experimental builds; chat/worktree handoffs. Private repository releases require an authenticated manual download; use UPDATE.cmd from the new bundle for selected installed components. No credentials belong in the installer.

Evidence: 630 payload JSON files and catalog validated, four Python tests and 30 PowerShell 7/Linux assertions passed before publication. Windows CI run 36280934305 successfully built AWS 0.5.0 and Survivor 0.9.10 DLL candidates. That run found a PS 5.1 JSON-array enumeration bug in duplicate-mod detection; fixed in the subsequent update. Consult latest CI for Windows verification of the updated tree. Survivor 0.9.15 cumulative upstream source audit and g++ C++17 syntax check passed. CI builds it with an explicit header-only API 1.8 recipe against pinned external SDK, without building host/runtime.

Unresolved: exact game target experimental-2026-09-23-0546 / e262adb299a7613b4aedc5f12c08fe0413c56a84 has no completed clean engine baseline. Linux attempts timed out; no component is marked load-tested. Secronom reconstruction may differ from the final working user tandem. Survivor 0.9.15 remains source-only and unavailable to installer pending matching external NCMM host/gameplay/save migration tests. No automatic compatibility is claimed for other stable or experimental builds. Infrastructure releases remain PREVIEW.

Native refresh: AWS 0.6.1 and Survivor 0.9.15 revision 1 from v8.7.3 are source-only. Old AWS 0.5.0 DLL is history-only; both current native installs are blocked pending compatible external API 1.8 host. Module source audits and g++ checks passed. No host/game installer ran.

Survivor current state schema: 8. Host integration and save migration require separate validation. Source import of v8.6.5 succeeded in Actions run 36303157617; subsequent v8.7.3 refresh preserves that state in history.

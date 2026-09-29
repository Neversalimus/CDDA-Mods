# Current status — 2026-09-29

Source import is complete in private Neversalimus/CDDA-Mods. Latest source commit: `2d10f4708e0e3e0178999a1397a342ad73e48c52` (v8.7.3 refresh). NCMM remains external. The v0.1.0 PREVIEW publication workflow rebuilds and retests its exact release commit before creating an immutable tag and assets.

Current versions: AXIOM 0.8.2.7; Blazemod 0.5.5; Secronom 1.5.1 + expansion 0.3.4 reconstructed; Prime Hotfix14a / installer 1.1.1; Tankmod Fix4; UDP v3 FULL; AWS 0.6.1; Survivor 0.9.15 cumulative v8.7.3. Refresh cutoff: 2026-09-27 12:27 UTC (15:27 Moscow); latest available archive v8.7.3, v8.7.4 not available in search. Prior Survivor 0.9.10 is preserved in history.

Implemented: independent packages and checksums; Windows installer with selection/dependencies, exact game binding, pre-install validation, backup and transactional group rollback; target preparation for stable/experimental builds; chat/worktree handoffs. Private repository releases require an authenticated manual download; use UPDATE.cmd from the new bundle for selected installed components. No credentials belong in the installer.

Evidence: Windows CI run [36319464027](https://github.com/Neversalimus/CDDA-Mods/actions/runs/36319464027) PASSED on source commit `2d10f4708e0e3e0178999a1397a342ad73e48c52`: catalog/build, Windows PowerShell 5.1 and PowerShell 7 installer tests, four Python tests, AWS 0.6.1 and Survivor 0.9.15 Windows DLL candidate builds. The PS 5.1 duplicate-mod JSON-array bug is fixed and covered by passing tests. Earlier local checks validated 630 payload JSON files and 30 PowerShell assertions. Survivor cumulative upstream source audits and both g++ C++17 syntax checks passed. Native CI uses a hash-bound API 1.8 header recipe against the pinned external SDK; host/runtime are not built or shipped.

Unresolved: exact game target experimental-2026-09-23-0546 / e262adb299a7613b4aedc5f12c08fe0413c56a84 has no completed clean engine baseline. Linux attempts timed out; no component is marked load-tested. Secronom reconstruction may differ from the final working user tandem. Survivor 0.9.15 remains source-only and unavailable to installer pending matching external NCMM host/gameplay/save migration tests. No automatic compatibility is claimed for other stable or experimental builds. Infrastructure releases remain PREVIEW.

Native refresh: AWS 0.6.1 and Survivor 0.9.15 revision 1 from v8.7.3 are source-only. Old AWS 0.5.0 DLL is history-only; both current native installs are blocked pending compatible external API 1.8 host. Module source audits and g++ checks passed. No host/game installer ran.

Survivor current state schema: 8. Host integration and save migration require separate validation. Source import of v8.6.5 succeeded in Actions run 36303157617; subsequent v8.7.3 refresh preserves that state in history.

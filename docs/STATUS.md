# Current status — 2026-09-30

Secronom full text-style cleanup is validated on branch `mod/secronom/text-style-cleanup` at code commit `8a4394b3918ba5fc8a73ea0882f951302b7ebf2b`. Normal CI run `36646308606` passed repository/package validation, Windows PowerShell 5.1 and PowerShell 7 installer tests, Python tests, Survivor native build, and Advanced World Settings native build.

The cleanup resolves the remaining 985 exact-source `text_style_check_reader` spacing diagnostics from deep run `36637757803`. Changes are text-style only: exactly one ASCII space was inserted at each checker-reported sentence-boundary location. The earlier 28 ellipsis replacements and one trailing-space removal remain unchanged. No IDs, mechanics, spawn data, effects, balance values, or JSON structure changed.

The informational deep baseline now expects Secronom itself at 0 style warnings. Dependent expected fingerprints were recomputed from archived exact-source evidence by removing the complete Secronom warning set: Secronom+ 458 warnings, profile-all-content 810, combined-all-json 810. A fresh deep run is still required to confirm these fingerprints against the exact CDDA runtime before treating the warning cleanup as runtime-certified.

# Current status — 2026-09-30

Safe observability pass is validated on branch `infra/safe-observability-pass` at code commit `8a57afbd8c6ee4d6766b927421a86568dd26621b`. Normal CI run 36644399331 passed repository/package validation, Windows PowerShell 5.1 and PowerShell 7 installer tests, Python tests, Survivor native build, and Advanced World Settings native build.

The pass does not change runtime verdict rules. It adds per-process and installer-case timing evidence, diagnostic environment/runtime hashes, a read-only final deep summary, and an informational text-style warning baseline. The final summary job is explicitly non-gating; release/source/installer jobs remain authoritative. Source style diagnostics are normalized without timestamps so warning fingerprints are comparable across runs.

Secronom 1.5.1 received a targeted text-only cleanup of exactly 29 previously observed diagnostics: 28 three-dot ellipses were replaced with the preferred ellipsis character and one trailing space was removed. The remaining 985 Secronom sentence-spacing diagnostics were intentionally left unchanged pending a separate reviewed cleanup. No IDs, mechanics, spawn data, effects, or balance values were changed.

The warning baseline is derived from exact-source deep run 36637757803 and adjusted only for those 29 targeted diagnostics. It is informational and cannot turn a runtime failure into a pass. A fresh deep run is still required to confirm the new compact summary and post-cleanup warning fingerprints on the exact game.

# Current status — 2026-09-29

Source import is complete in private Neversalimus/CDDA-Mods. NCMM remains external. The v0.1.0 PREVIEW publication workflow rebuilds and retests its exact release commit before creating an immutable tag and assets.

Current versions: AXIOM 0.8.2.8 (static; runtime pending); Blazemod 0.5.5; Secronom 1.5.1 + expansion 0.3.4-r2 reconstructed; Prime Hotfix14a / installer 1.1.1; Tankmod Fix4; UDP v3 FULL; AWS 0.6.1; Survivor 0.9.15 cumulative v8.7.3. Refresh cutoff: 2026-09-27 12:27 UTC (15:27 Moscow); latest available archive v8.7.3, v8.7.4 not available in search. Prior Survivor 0.9.10 is preserved in history.

AXIOM 0.8.2.8 fixes four patrol-route defects (two blocked surface waypoints and two rooftop routes using composite instead of local-OMT patrol coordinates) and adds AXIOM-specific semantic regression coverage for mapgen, access control, KX-91 state/vehicle swaps, mission offer wiring, and security EOCs. PR #9 CI run 36592734678 passed the normal Windows gate, including catalog validation/build, PowerShell 5.1/7 installer tests, the AXIOM integrity suite, and both native candidate builds. The AXIOM manifest is therefore promoted to `static`; exact-game load/runtime validation is still pending.

Implemented: independent packages and checksums; Windows installer with selection/dependencies, exact game binding, pre-install validation, backup and transactional group rollback; target preparation for stable/experimental builds; chat/worktree handoffs; deep real-CDDA workflow with verified official release-binary matrix, real shipped-installer lifecycle matrix, and parallel exact-source `cata_test` runtime passes. Heavy tests are isolated from push/PR CI. Weekly deep runs are enabled by default and can be disabled without code changes by setting `CDDA_DEEP_TESTS_ENABLED=false`. Private repository releases require an authenticated manual download; use UPDATE.cmd from the new bundle for selected installed components. No credentials belong in the installer.

Evidence: Windows CI run [36319464027](https://github.com/Neversalimus/CDDA-Mods/actions/runs/36319464027) PASSED on source commit `2d10f4708e0e3e0178999a1397a342ad73e48c52`: catalog/build, Windows PowerShell 5.1 and PowerShell 7 installer tests, four Python tests, AWS 0.6.1 and Survivor 0.9.15 Windows DLL candidate builds. The PS 5.1 duplicate-mod JSON-array bug is fixed and covered by passing tests. Earlier local checks validated 630 payload JSON files and 30 PowerShell assertions. Survivor cumulative upstream source audits and both g++ C++17 syntax checks passed. Native CI uses a hash-bound API 1.8 header recipe against the pinned external SDK; host/runtime are not built or shipped.


AXIOM deep-runtime infrastructure now includes an exact-engine lifecycle probe compiled into the pinned CDDA `cata_test` only for `component-axiom_7`. It covers representative multi-level mapgen, key NPC/security spawns, clearance mission end-effects, KX-91 update-mapgen progression, and the security alarm EOC. This is infrastructure only until a deep run produces evidence; AXIOM remains `static`. PR #10 normal CI run `36596427480` passed repository validation, packaging, PowerShell 5.1/7, both native candidate builds, and 26 Python tests including the lifecycle wiring checks. This normal CI result does not substitute for the deep exact-engine run.

Deep-runtime evidence: run 36598744438 proved both the pristine official Windows release baseline and the isolated staged-data baseline for experimental-2026-09-23-0546 / e262adb299a7613b4aedc5f12c08fe0413c56a84 with exit code 0. The same run then exposed two real AXIOM plural-definition errors and one Secronom+ charged-result recipe warning; those content defects are fixed on main. It also exposed two harness defects: cross-component mod discovery contamination in release checks and protected map access in the AXIOM exact-engine probe. Both harness defects are fixed on main and require a fresh deep run for certification. No component is promoted to load-tested/runtime-tested from the failed run.

Unresolved: Secronom reconstruction may differ from the final working user tandem. Survivor 0.9.15 remains source-only and unavailable to installer pending matching external NCMM host/gameplay/save migration tests. No automatic compatibility is claimed for other stable or experimental builds. Infrastructure releases remain PREVIEW.

Native refresh: AWS 0.6.1 and Survivor 0.9.15 revision 1 from v8.7.3 are source-only. Old AWS 0.5.0 DLL is history-only; both current native installs are blocked pending compatible external API 1.8 host. Module source audits and g++ checks passed. No host/game installer ran.

Survivor current state schema: 8. Host integration and save migration require separate validation. Source import of v8.6.5 succeeded in Actions run 36303157617; subsequent v8.7.3 refresh preserves that state in history.

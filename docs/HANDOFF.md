# Handoff — 2026-09-27

The private Neversalimus/CDDA-Mods repository is populated; initial import 14bafb0, CI setup d4c2ac5. Read AGENTS.md and STATUS.md, then refresh remote HEAD and latest Actions before editing. The connector currently lacks private-repository access; owner authorized browser uploads. Never overwrite another chat's changes.

This update imports module-only Survivor 0.9.14 cumulative v8.6.5, archives 0.9.10, and fixes PS 5.1 root-array handling during duplicate mod detection. Provenance is in catalog/provenance.json. SDK recipe is header-only and hash-bound; external NCMM host remains excluded. SOURCE_SHA256.json describes the initial import, not later git commits.

Next: examine latest Windows CI; download the PREVIEW release bundle after signing into GitHub. Test exact Windows game baseline + selected individual mods + combined stack with tools/verify_game.py. Compare Secronom reconstruction with the user's working pair. Promote only matching successful reports. Verify Survivor API 1.7/gameplay hooks, UI and save migration against external NCMM before allowing DLL installation. Prepare new targets for named mods only, preserving prior variants. Do not recreate repository or rerun initial importer.

Native refresh: AWS 0.6.1 and Survivor 0.9.14 revision 2 from v8.6.5 are source-only. Old AWS 0.5.0 DLL is history-only; both current native installs are blocked pending compatible external API 1.7 host. Module source audits and g++ checks passed. Upstream installer parser defect was corrected only in disposable recovery staging; no host/game installer ran.

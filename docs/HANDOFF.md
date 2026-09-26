# Handoff

Task: establish Neversalimus/CDDA-Mods, excluding NCMM, with shared installer and
independent mod/target updates. User required rechecking latest versions on Sep 26.

Read STATUS.md and AGENTS.md. The private GitHub repository exists with initial commit
a247f12b62a379d4ebadf061d917288bf9236125. Browser-based source import is in progress;
verify remote main and Actions before treating the upload as complete.

Next actions:
1. Create/push new repository under Neversalimus; run Windows CI.
2. Run tools/verify_game.py on exact working Windows game baseline. For Secronom,
   compare reconstruction to an export of the user's working core + expansion.
3. Promote only hash-matched successful reports, retaining pending for others.
4. Build Survivor 0.9.10 DLL through native CI. Verify its API 1.4/tree UI/metrics
   requirements against the separate NCMM clean-v13 host before promoting a
   binary package. Do not update NCMM from this repository.
5. Tag a reviewed suite release; use separate per-mod ZIPs and the full bundle.

Version source files and SHA256 are recorded in catalog/provenance.json.
SOURCE_SHA256.json is the reviewed initial source snapshot inventory; modifying
sources intentionally requires revalidating and regenerating it before the initial
publisher will accept them. After normal git adoption use commit history/CI.

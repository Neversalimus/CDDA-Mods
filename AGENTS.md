# Working agreement for every chat / coding agent

This repository owns CDDA JSON/content mods, the custom tileset, installer and
compatibility infrastructure. **NCMM runtime/bootstrap/host and the current native
module delivery live in Neversalimus/NCMM and must not be replaced from here.**

## Before editing

1. Read `README.md`, `docs/STATUS.md`, `docs/CHAT_WORKFLOW_RU.md` and the
   selected `mods/<id>/manifest.json`. Refresh remote `main` and current Actions.
2. Use exact CDDA tag + 40-character source commit. Never infer compatibility from
   date/version ordering.
3. Normal new experimental releases are handled by
   `.github/workflows/experimental-watch.yml` and
   `.github/workflows/experimental-certify.yml`. Do not pre-add support merely
   because a newer build exists.
4. Preserve unrelated changes. For parallel chats prefer separate branches/worktrees.
   Never force-push shared work.
5. Never copy personal paths, saves, tokens or private user data into git.

## Change rules

- Edit selected mods only unless the task explicitly covers shared infrastructure.
- Preserve IDs/save variables/state schemas unless an explicit migration is designed
  and tested.
- Keep dependencies explicit. Secronom+ depends on Secronom; MoM compatibility
  depends on Prime and Mind Over Matter.
- Historical `history/*` and original third-party provenance are immutable evidence,
  not current development sources.
- `tools/recovery` is reconstruction tooling, never a player-side updater.
- Native source snapshots in this repository are installer-disabled. Current NCMM
  host/modules are certified and shipped from the NCMM repository.

## Validation hierarchy

Ordinary CI must pass:

- `python tools/modsuite.py validate`;
- package build/checksums;
- installer tests on Windows PowerShell 5.1 and PowerShell 7;
- Python regression tests;
- native snapshot compilation checks where configured.

Game compatibility requires exact-game evidence:

- official release loader / native validator;
- exact-source `cata_test`;
- combined stack;
- object-level content probes for items/recipes/vehicles/overmap;
- targeted gameplay/lifecycle probes where a mod needs them.

Known inherited upstream debt may be normalized only by an exact, pinned signature.
Unknown/new failures remain fatal.

The heavy `.github/workflows/deep-runtime.yml` is for compatibility/release and
diagnostic passes, not a required every-push gate.

## Documentation/handoff

After meaningful changes update the active mod changelog when applicable and keep
`docs/STATUS.md`, `docs/HANDOFF.md`, compatibility docs and installer guide in
sync. State exact commits, what passed, what remains pending and which evidence is
obsolete/superseded.

Do not promote a candidate from stale evidence if `main` moved after it was tested.

# Working agreement for every chat / coding agent

This repository owns CDDA content mods, two independently versioned code mods,
and the custom tileset. **NCMM runtime, bootstrap, host patches and the CDDA
engine are external. Never migrate, replace or publish them from this repo.**

Before editing:
1. Read README.md, docs/STATUS.md, docs/CHAT_WORKFLOW_RU.md and the selected
   mods/<id>/manifest.json. Check `git status`, current branch and remote HEAD.
2. Refresh current releases/source archives when the user says versions changed.
   Library archive dates and a main branch are not interchangeable: newest work
   can be a pinned patch outside main. Record provenance and hashes.
3. Select the exact game tag AND commit in catalog/targets. Never treat newer
   experimental or stable releases as automatically compatible.
4. Make one task branch `mod/<id>/<task>` or `compat/<target>/<scope>`. Work in a
   separate git worktree when another chat is active. Do not overwrite local edits.

Changes:
- Edit selected mods only. Keep JSON IDs, save variables and native state schemas
  compatible, or document and test an explicit migration. Never reset user saves.
- Each mod has its own version/revision, source variant and target mapping.
  Preserve old target variants. `prepare-target` copies only named components.
- Keep dependencies explicit. Secronom+ depends on Secronom; MoM compatibility
  depends on Prime and the game's MindOverMatter mod. A shared dependency change
  requires testing its consumers and the combined stack.
- `tools/recovery` is historical, staging-only reconstruction. It is NOT the
  development source of truth and must never be run on a player's live game.
- Native mods use external pinned NCMM SDKs. Building a DLL is not proof that the
  target host supports its capabilities. Keep source-only releases unavailable.
- Don't copy machine paths, user logs, tokens, saves or personal context into git.

Before handoff:
- `python tools/modsuite.py validate`; `python tools/modsuite.py build`;
  installer tests under Windows PowerShell 5.1 and pwsh (CI); Python tests.
- For game compatibility run tools/verify_game.py on the exact binary, examine
  baseline + individual + combined logs. Syntax checks are not runtime checks.
- Deep real-CDDA CI is intentionally opt-in: `.github/workflows/deep-runtime.yml`
  has no push/PR trigger. Use it for compatibility/release gates; weekly scheduled
  runs are enabled unless repository variable `CDDA_DEEP_TESTS_ENABLED=false`.
  Set that kill switch during active development and never make this workflow a
  required per-commit check.
- Only `record-validation` can promote verified content to load-tested. A gameplay
  smoke test/save migration is additional evidence, never implied by --check-mods.
- Update docs/STATUS.md, the selected mod changelog, target status and handoff.
  State what was tested, what was not, exact source commit, pending work.
- Never force-push shared branches. Rebase before PR; do not overwrite other chats.

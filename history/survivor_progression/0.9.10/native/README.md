# Survivor Progression v0.9.0 — State Migration & API Stabilization Pass

This replaces the 0.1 technical vertical slice with the first complete playable progression system.

## Core
- 30 Survivor levels.
- 1 normal perk point per level gained.
- 1 Major Point at levels 5, 10, 15, 20, 25 and 30.
- Persistent per-character state through `character_state.v1`.
- F1 opens the progression interface; the binding remains remappable through CDDA.
- Level-up no longer forcibly opens a menu during sleep/wait/activity; it posts a notification instead.
- Full respec with exact refund of spent normal and Major Points.
- 0.1.x Fast Learner ownership is migrated into the new Mastery tree.

## Six branches / 60 perks
Each branch contains 8 normal perks, 1 Major perk and 1 capstone:
- Combat
- Survival
- Mobility
- Crafting
- Scavenging
- Mastery

Each branch has two prerequisite lanes which merge into its Major perk, then a level-30 capstone.
The full character can earn 29 normal perk points and 6 Major Points, so the system is intentionally
choice-driven rather than allowing every perk in one run.

## Real gameplay effects
Perks use NCMM `character.modifiers.v1`, not fake UI-only bonuses. Supported effects in this pass include:
- STR / DEX / PER / INT
- movement speed and movement cost
- maximum stamina
- carrying capacity
- dodge and melee accuracy
- natural healing
- reading speed
- crafting speed
- Survivor XP rate

## Balance state
This is feature-complete enough for live play, but remains v0.8 rather than 1.0 until the 60-perk balance
and long-save migration have been tested in real CDDA sessions.

## 0.8.1 safe polish
- Overview now shows purchased normal/Major counts and aggregated active gameplay effects.
- Locked perk labels distinguish level gates from missing prerequisites.
- Respec confirmation shows the exact refund before applying it.
- Respec smoke coverage now verifies point refund and modifier cleanup.
- No perk values or progression thresholds were rebalanced in this pass.

## 0.9.0 migration pass
- First production consumer of NCMM semantic API 1.1 and `state.migration.v1`.
- Persistent state schema is now 3; schemas 0–2 migrate through the host-owned migration lifecycle.
- Migration normalizes invalid negative XP/point counters and fractional XP while preserving owned perks.
- A newer/unsupported save schema is suspended by the host instead of being guessed or overwritten.
- Level-up text no longer hardcodes F1 because the action is remappable in CDDA.
- Perk values, level thresholds and the 60-perk layout are intentionally unchanged in this pass.

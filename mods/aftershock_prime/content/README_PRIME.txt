Aftershock: Prime Integration
=============================

Current repository version : 0.1.14a (revision: see manifest/package descriptor)
Mod ID                     : aftershock_prime
Hard dependency            : dda only

Supported repository targets
----------------------------
- cdda_experimental_2026_09_23_0546
  e262adb299a7613b4aedc5f12c08fe0413c56a84
- cdda_experimental_2026_10_01_1040
  3f7fb352bf492ba521bd9408a0c9f6ce239e8d83

Upstream provenance
-------------------
The curated base snapshot was recovered from the 0546-era Aftershock source at
e262adb299a7613b4aedc5f12c08fe0413c56a84.

Prime is no longer a pure one-commit snapshot. Gameplay revision r5 selectively imports the
Wraitheon Gryphon vehicle block from upstream Aftershock commit d65c89e0:
- wraitheon_aerodyne
- aerodyne_engine
- engine_turbine_large
- afs_aerodyne_engine
- afs_aerodyne_powerplant

Gryphon is integrated additively at weight 1 into:
- mil_helicopters_small
- crashed_helicopters

UICA shuttle-base mapgen, Salus IV world conversion, factions and missions were
not imported. The exact-1040 Prime vehicle registry/vehicle-parts runtime test
passed.

Scope
-----
Included:
- modular exosuits and modules
- Aftershock CBMs and bionic support
- energy shields
- laser/electrolaser/flechette/advanced ballistic/plasma/rail weapons
- grenades and high-tech utility devices
- robotics, inactive robots, robot crafting and attacks
- genetech / Human+ / Project Sobek
- functional Mercurial Resequencer
- optional separate Mind Over Matter compatibility layer
- selected advanced vehicles and vehicle parts
- hacking, cryosuit, translocation and non-Esper support EOCs/spells
- conservative integration into vanilla science/military/bionic/robot pools

Deliberately excluded:
- Salus IV dimensions, climate and world replacement
- scenarios and start locations
- Aftershock NPC factions, planetary economy and missions
- Aftershock Esper system
- global game options and broad balance overrides
- vanilla map weight suppression/blacklists
- vanilla APC/vehicle overrides
- vanilla bionic installation-data overrides
- global recipe/price overrides

BUILD_REPORT.txt records the original recovery/base-pruning audit. It predates
post-import fixes and the r5 Gryphon selective addition; use this README and git
history for current provenance.

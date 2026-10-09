# Sprite provenance

The atlas was generated for Iznanka with the built-in imagegen tool on 2026-10-09.
`iznanka-source.png` is the unchanged generated output (1122×1402 RGBA).
`../content/iznanka.png` is the game atlas, resampled with Pillow NEAREST to
128×160, four columns by five rows, 32×32 per tile. No smoothing or donor sprites.
The full mapping is in `../content/tileset.json`; every new local visible ID is covered.

Prompt: one transparent horror roguelike pixel-art atlas, exactly four columns
and five rows, no gaps, labels or grid. Restrained grey/olive/bone/black palette,
cyan and rusty-red accents, sharp pixel clusters, readable silhouettes.
Rows: listener / hollow deer / root crawler / drowned;
pump warden / forest portal / return portal / dead tree;
resonance detector / stitched return seal / glassbone / black resin;
sinew thread / quiet-node heart / broken pump / restored pump;
ashed earth / dark shallow marsh / expedition locker / bone cairn.
Terrain cells fill their tiles; foreground objects have transparent backgrounds.

The generated high-resolution source is retained for provenance, not used by the
runtime. Visual review at native size remains separate from schema validation.

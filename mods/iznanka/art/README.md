# Sprite provenance

Current runtime art is the [0.2.0 UDP-style pass](v02/README.md), packed by
`tools/pack_iznanka_art.py` into three sheets. The source described below is
retained as the original 0.1.0 artwork; its former runtime atlas is superseded.

## Original 0.1.0 source

The atlas was generated for Iznanka with the built-in imagegen tool on 2026-10-09.
`iznanka-source.png` is the unchanged generated output (1122×1402 RGBA).
The former `content/iznanka.png` game atlas was resampled with Pillow NEAREST to
128×160, four columns by five rows, 32×32 per tile. No smoothing or donor sprites.
Its historical mapping is retained in the 0.1.0 git history. The current mapping
in `../content/tileset.json` uses the new sheets and covers every local visible ID.

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

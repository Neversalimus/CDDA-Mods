# UDP art pass, 0.2.0

Generated with the built-in imagegen tool on 2026-10-09. The reference was a
contact sheet of actual UndeadPeople Hybrid sprites: soil 13637/13641/13642,
mud 13759, water 14757/14758, grass 13850/13851, monsters 8347/8438/8661,
and terminal 12480. These donor images were visual references, not pasted into
the new atlas. The old Iznanka atlas was a subject reference for existing IDs.

## Production prompts

Monsters: style-transfer, one transparent 4×2 atlas; native 32×32 pixel game art,
nearest-neighbor enlarged; match UDP/MSX chunky clusters, thick dark outlines,
restrained three-tone shading and readable anatomy. Row 1: blind listener with
large ears, hollow deer, low root crawler with skull, bloated drowned humanoid.
Row 2: pump warden, stitched walker in burgundy clothes, crooked white-masked
orderly, stationary three-mouthed voice organ. Keep whole silhouettes in their
cells, feet on the same baseline, two-pixel margin. No ground, glow, gradients,
thin scratchy detail, labels or borders.

Terrain: opaque 4×2 atlas, continuous top-down surfaces with uniform edge-to-edge
density. Four grey-brown ash soil variants, four olive-grey shallow marsh variants.
Reference the low-contrast granular UDP dirt/mud. Logical 32×32 cells, hard square
pixel clusters, shared material midtones. No paving, cobbles, large circles,
cell frames, black edges, bevels, perimeter highlights, vignette, relief or objects.

Objects: transparent 4×5 atlas, compact UDP/MSX pixel clusters and black outlines,
restrained shading, no ground squares or realistic microdetail. Row 1: forest
rift, return rift, dead tree, detector. Row 2: return seal, glassbones, black resin,
sinew. Row 3: heart, broken pump, working pump, locker. Row 4: cairn, inactive
radio rack, active rack, inactive tuning console. Row 5: active console,
suppressor, field manual, conducting coil. Cyan marks active equipment only;
related inactive/active forms retain the same shape.

## Packing and review

Source PNGs are unchanged generated output. `tools/pack_iznanka_art.py` crops
objects at transparent row gaps and per-object alpha bounds, keeps their aspect
ratio, aligns their feet, and uses nearest-neighbor resampling. Packing is not
an artistic repaint. This avoids cutting the taller first row of the generated
object sheet. Terrain is opaque and has four equally weighted variants per ID.

Runtime sheets: `iznanka-monsters.png` (8 cells), `iznanka-objects.png` (20),
`iznanka-terrain.png` (8); all native cells are 32×32. The six console IDs share
two intentional state sprites. Tile IDs and their cumulative indices are in
`content/tileset.json`.

`terrain-repeat-preview.png` is a deterministic 16×8-tile composition at exact
2× zoom, including all eight monsters. It is an atlas repetition check, **not an
in-game screenshot**. Native sheets were also reviewed at 1×. Ground has no
transparent pixels and the former black cell border is gone. Full in-game
lighting/zoom review of every new scene is still pending.

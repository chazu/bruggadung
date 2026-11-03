# Tessera

The visual engine of bruggadung: scenes of tile worlds with z-levels, for
anything that draws them. The design is [TESSERA.md](../TESSERA.md).

This is slice 1: the scene core, the Odin package `tessera` (this
directory). Nothing draws yet.

- **Scenes** (`scene.odin`): an extent of tiles over levels; a cell for
  each (terrain, when seen, light, fluid, flags); marks (the things drawn,
  by entity or referent ID, held ones by their holder); overlays (scalar
  fields, in name order); annotations (lines, arrows, paths, callouts).
  Each scene has a view, truth or knowledge, and overlays and annotations
  may be tagged `.Developer_Only`, which `strip_developer` takes out for a
  player. A scene's fields are for reading; cells change in place, the rest
  through its procedures. Everything it holds is in its allocator.
- **Appearance keys** are small integers a scene names (`look`), made in
  order and kept as made, so a scene copied for the next frame keeps its
  keys.
- **Frames and diffs** (`codec.odin`: `encode_frame`, `encode_diff`,
  `decode`): a compact binary form with varints, runs of equal cells and
  overlay values, and spans of changed cells. A diff names the frame it
  follows, and falls back to a frame when it can't say the change (another
  extent, view or viewer, or keys not extending the last frame's).
  Decoding checks every length, so truncated or corrupted input fails with
  a `Decode_Error` and never reads out of bounds.
- **Text** (`text.odin`: `scene_text`): the scene a line per thing, in a
  fixed order, so two scenes print alike exactly when they are alike.

```odin
import tess "tessera"

meta := tess.Meta{.Knowledge, 1, now_ms, content_hash, viewer_entity}
s := tess.scene_new(meta, tess.Extent{x0, y0, 32, 24, 0, 2, 0})   // 32 x 24 tiles, levels 0..2, looking at 0
defer tess.scene_free(s)
c := tess.cell_at(s, x, y, 0)
c.terrain = tess.look(s, "floor")
c.seen = now_ms
tess.mark_put(s, tess.Mark{id = 4, x = x, y = y, look = tess.look(s, "#Agent"), flags = {.Actor}})

data, is_frame, _ := tess.encode_diff(last, s)               // a frame, if last is nil
```

## Building

```sh
make test       # the tests, with Odin's leak tracking
make check      # the package, vetted
```

Odin's release is pinned in `../lab/ci/odin` (Dockerfile, install-odin.sh).

The core was C11 until 2026-11. The port kept the binary format, format 1,
byte for byte: `tests/golden` holds what the C encoder made of the tests'
room, and the tests check the Odin encoder makes the same.

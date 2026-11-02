# Tessera

The visual engine of bruggadung: scenes of tile worlds with z-levels, for
anything that draws them. The design is [TESSERA.md](../TESSERA.md).

This is slice 1: the scene core. Nothing draws yet.

- **Scenes** (`include/tessera.h`): an extent of tiles over levels; a cell
  for each (terrain, when seen, light, fluid, flags); marks (the things
  drawn, by entity or referent ID, held ones by their holder); overlays
  (scalar fields, in name order); notes (lines, arrows, paths, callouts).
  Each scene has a view, truth or knowledge, and overlays and notes may be
  tagged `TESS_DEVELOPER`, which `tess_strip_developer` takes out for a
  player.
- **Appearance keys** are small integers a scene names (`tess_look`), made
  in order and kept as made, so a scene copied for the next frame keeps its
  keys.
- **Frames and diffs** (`tess_encode_frame`, `tess_encode_diff`,
  `tess_decode`): a compact binary form with varints, runs of equal cells
  and overlay values, and spans of changed cells. A diff names the frame it
  follows, and falls back to a frame when it can't say the change (another
  extent, view or viewer, or keys not extending the last frame's).
  Decoding checks every length, so truncated or corrupted input fails with
  a reason and never reads out of bounds.
- **Text** (`tess_scene_text`): the scene a line per thing, in a fixed
  order, so two scenes print alike exactly when they are alike.

```c
tess_meta   meta = { TESS_KNOWLEDGE, 1, now_ms, content_hash, viewer_entity };
tess_extent ext  = { x0, y0, 32, 24, 0, 2, 0 };          /* 32 x 24 tiles, levels 0..2, looking at 0 */
tess_scene *s    = tess_scene_new(meta, ext);
tess_cell  *c    = tess_cell_at(s, x, y, 0);
c->terrain = tess_look(s, "floor");
c->seen    = now_ms;
tess_mark me = { .id = 4, .x = x, .y = y, .z = 0, .look = tess_look(s, "#Agent"), .flags = TESS_MARK_ACTOR };
tess_mark_put(s, &me);

tess_bytes out;
tess_encode_diff(last, s, &out, NULL);                    /* a frame, if last is NULL */
```

## Building

```sh
make            # build/libtessera.a and the tests
make test       # 73 checks
make ubsan      # the tests under UBSan
make leaks      # the tests under macOS leaks
```

C11, no dependencies. On this machine, as for triangle, link with
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.

# Tessera

## Status and scope

Tessera is bruggadung's visual engine: everything that shows a tile-based
world with z-levels, from a text map in a terminal to a hardware-accelerated
window. It is an engine, not a game. It knows tiles, levels, layers,
appearances, cameras and views. It does not know pumps, agents or water.
Whatever it shows, it is told about in a **scene**.

This document is a draft. Slice 1, the scene core, is built in
[tessera/](tessera/README.md): the Odin package `tessera`. Nothing draws
yet.

Two things in the repository shape it:

- **ARCHITECTURE.md's "Two views, and no leaks".** The developer view shows
  the truth. The player view is built only from perception and the
  character's knowledge store. A visualizer that reads world state directly
  would break this the first time it drew a player's map.
- **The lab runs on three platforms.** It builds with Apple's Foundation on
  the Mac and GNUstep's on Linux and Windows (STACK.md), so a frontend
  linking Metal or AppKit would be the Mac's alone. A hardware-accelerated
  frontend has to draw through a cross-platform layer, or be another
  process. SDL, GLFW and wgpu come with Odin's vendor packages, and sokol
  has Odin bindings of its own.

## Decisions so far

1. **Tessera draws scenes, never worlds.** A scene is plain data: what to
   show for a region of tiles and a range of levels. A **producer** builds
   it (the lab, or anything else) and a **backend** draws it. No backend
   reads simulation state, and no producer draws.
2. **There are two kinds of scene, for the two views.**
   - A **truth scene** (developer view) is built from world state: entities
     where they are, fields as they are.
   - A **knowledge scene** (player view) is built only from one character's
     knowledge store: the tiles it has seen and when, referents where it
     believes them, and their appearance as it believes it.

   A scene records which view built it. Its marks name entity IDs in a
   truth scene and referent IDs in a knowledge scene, never both. Developer
   information shown over a player's map (a causal trace, the truth beside
   a belief) goes in an overlay or annotation tagged as developer-only. A
   backend in player mode refuses those.
3. **Tessera is Odin, apart from the simulation.** The core is an Odin
   package that needs only Odin's core library. Backends are separate
   packages over it. Nothing in Tessera imports the lab, so another
   simulation, or a tool, can produce scenes too. The lab's producers come
   with the lab's own port to Odin: until then it is Objective-C, which
   can't fill an Odin scene. The core was C11 until 2026-11; the port kept
   its binary format byte for byte (tessera/tests/golden).
4. **Scenes are frames and diffs, and serialisable.** A frame is complete.
   A diff lists what changed since an earlier frame, named by sequence
   number. The same data serves in-process use, a pipe or socket to a viewer
   in another process, and a recording file to replay. The first version is
   in-process, but the format is fixed from the start so splitting later
   costs nothing.
5. **The simulation never waits for rendering.** The simulation advances
   by events (scheduler boundaries), not frames. A producer publishes a
   scene at a boundary, or when asked, and a viewer takes the latest at its
   own frame rate. A viewer that falls behind skips to the latest frame. It
   may interpolate motion between scenes, but that is presentation only.
6. **Appearance is content.** How a kind looks is declared in Triangle
   content beside its blueprint: a glyph, an atlas cell, a tint, a layer, a
   stacking order. It resolves through the type hierarchy, so the most
   specific kind with a look wins. Producers put an **appearance key** on
   each mark, and a backend's **theme** maps keys to what it can draw (a
   glyph set, a sprite atlas). Nothing hard-codes a kind's look, as
   BGPlay's glyph table does today.
7. **Glyphs come first.** The first GPU backend draws glyph tiles from a
   font atlas. It is the same pipeline that sprites will use (instanced
   textured quads), without the art.
8. **The first GPU backend uses sokol.** sokol_app and sokol_gfx are C and
   single-header, and drive Metal, OpenGL, D3D11 and WebGPU, including wasm
   for a viewer in a browser.
   - raylib was considered: quicker to start, but shaped like a game.
   - wgpu-native was considered: modern but heavier.
9. **Input goes through actions.** A viewer that controls a character
   sends it commands: the verbs BGPlay takes (a menu entry, walk, ask,
   tell). It never edits the world, and what follows comes back as
   perception, as in BGPlay. Watching comes first. Control comes after.

## Terms

| Term | Meaning |
| --- | --- |
| Scene | What to show: an extent, cells, marks, overlays, annotations, and where it came from. |
| Frame / diff | A complete scene, or the changes since an earlier frame (by sequence number). |
| View | `truth` (developer) or `knowledge` (one character's). Every scene has one. |
| Extent | A rectangle of tiles over a range of levels, and the focus level. |
| Cell | A tile at one level: its terrain, whether and when it was seen, its light, its fluid. |
| Mark | A thing drawn on a cell: an entity, or a referent, with an appearance key. |
| Appearance key | A kind's look as named in content. A theme gives each key its glyph or sprite. |
| Theme | A backend's mapping from appearance keys to glyphs, atlas cells and tints. |
| Overlay | A scalar field over cells, such as heat, CO₂, light, sound, knowledge age or water depth, with a range and a palette. |
| Annotation | A line, arrow, path or callout: a causal chain, line of sight, a route. |
| Producer | What builds scenes from a simulation (the lab's `BGScene`). |
| Backend | What draws scenes: the terminal, a sokol window, a recorder. |

## The scene model

The core structures, as built (tessera/scene.odin).

```odin
View :: enum u8 { Truth, Knowledge }

Extent :: struct {
	x0, y0, w, h: i32,     // tiles
	z0, z1:       i32,     // levels, inclusive
	focus:        i32,     // the level being looked at
}

Cell :: struct {
	seen:    i64,          // ms it was last seen; -1 never (truth: the scene's time)
	fluid:   u32,          // water depth, mL per tile
	terrain: u16,          // appearance key of what the cell is: floor, wall, open air, ...
	flags:   Cell_Flags,   // in sight now, open, door
	light:   u8,           // 0 dark .. 255 full daylight
}

Mark :: struct {
	id, holder: u64,       // entity ID (truth) or referent ID (knowledge); what holds it
	seen:       i64,       // knowledge: when last seen
	x, y, z:    i32,
	look:       u16,       // appearance key
	stack:      i16,       // order among marks on one cell
	flags:      Mark_Flags,   // the actor, believed gone, in sight now
	label:      string,    // optional: "R7", a name
}

Scene :: struct {
	meta:        Meta,     // view, seq, simulation ms, content hash, viewer
	extent:      Extent,
	cells:       []Cell,   // w * h * (z1 - z0 + 1)
	looks:       [dynamic]string,   // the appearance key table
	marks:       [dynamic]Mark,
	overlays:    [dynamic]Overlay,
	annotations: [dynamic]Annotation,
	allocator:   runtime.Allocator,
}
```

- **Appearance keys are small integers.** A scene carries the table from
  key to name (`"#Pump"`, `"wall.stone"`), so a recording keeps its meaning
  after content changes, and a theme matches keys by name. Keys are made in
  order and kept: a producer copies the last scene to build the next, and a
  diff carries only the keys added. Keys made in another order make a frame.
- **Marks are kept by id, overlays by name.** A scene's order never depends
  on the order it was built in, so two scenes that show the same thing are
  the same, and print the same (`scene_text`).
- **Things held or inside** are marks with no cell of their own: in a
  frame they hang off their holder's mark. A backend lists them (in an
  inspector, a tooltip), and the map shows the holder.
- **A knowledge scene has no other source.** Its cells' `seen` comes from
  the store's tile memory (`tileSeenAtX:y:`). Its marks come from referents
  and their believed places, with `seen` and the believed-gone flag. Light
  and fluid come from what the character perceived, not from the world.
  BGPlay's `look` reads the world's water on tiles in sight today. The
  knowledge producer takes it from perception instead (see open
  questions).

## Drawing a scene

A backend draws in this order:

1. Terrain.
2. Fluids.
3. Marks, by stack order.
4. Light and memory. In a knowledge scene, a tile never seen is black, and
   one seen before is dimmed by its age. Tiles in sight now are drawn at
   their light.
5. Overlays.
6. Annotations.
7. The backend's own interface.

**Levels.** The focus level is drawn in full. A level below shows, dimmed,
through cells of the focus level that have no floor (open air, a stairwell,
a hole). Levels above are hidden. Moving the focus up or down is the
viewer's own business and changes nothing in the simulation. The model
assumes no projection: a backend may draw top-down (the first one) or
isometric later.

## Backends

- **tess-term**: the terminal. It is BGPlay's text map re-based on a
  knowledge scene, with optional ANSI colour, and the first backend built,
  because it needs no graphics work to prove the model.
- **tess-sokol**: a window with a camera that pans and zooms, the focus
  level up and down, overlay toggles, and a developer panel. Selecting a
  mark in a truth scene names its entity, which the lab's inspector can
  show. Developer panels may use Dear ImGui (sokol_imgui).
- **Later:** a browser viewer (sokol on wasm, reading scenes over a socket),
  and a recording player.

## How the lab uses it

- **`BGScene`**, a lab class, is the producer:
  - `truthOf:world extent:` builds a truth scene;
  - `knowledgeOf:store extent:` builds a knowledge scene;
  - each frame is diffed against the last one published.
- **BGPlay's `look`** becomes a knowledge scene drawn by tess-term. Its
  output stays the same, which is the test that the model carries what the
  text map needs.
- **A watcher** runs a lab scenario (the cistern, the tempting purse) and
  publishes scenes at boundaries to a tess-sokol window, in the same process
  first.

## The plan, in slices

1. **Core** (built). `tessera/`: the scene structures, a builder API,
   frame and diff encoding (a compact binary form, plus a text form for
   tests), and tests, including truncated and corrupted input.
2. **Producers in the lab.** `BGScene` for both views, and BGPlay's `look`
   drawn through tess-term, with the same output.
3. **Appearance in content.** A look declared beside blueprints, keys
   resolved by type, and a theme for tess-term. BGPlay's glyph table goes.
4. **The first window.** tess-sokol watching a lab scenario: glyph atlas,
   camera, focus level.
5. **Overlays and the developer panel.** Fields from domains (heat, air,
   light, sound), knowledge age, causal traces.
6. **Control.** A character played from the window, through the action
   path.

## Open questions

- **Terrain** (settled: TERRAIN.md). The world has a terrain kind per
  cell, with a `look` for Tessera; rooms are found from it. A knowledge
  scene's cells come from what the character believes of the terrain
  (`believedTerrainAtX:y:level:`).
- **Perceived fields.** For a knowledge scene to show light and water
  without reading the world, the knowledge store has to keep what was
  perceived of a tile, not only when it was seen. How much (water seen,
  dark, smell of smoke), and for how long?
- **Large worlds.** Chunking scenes and diffs for maps much larger than a
  workshop.
- **Motion between boundaries.** An activity has progress, so a walking
  agent could be drawn partway across a tile. Should scenes carry activity
  progress, or should backends only interpolate between positions?
- **Where themes live.** In content, beside the looks, or as assets (atlas
  images, glyph sets) a backend loads.

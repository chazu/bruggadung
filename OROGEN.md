# Orogen

## Status and scope

Orogen is bruggadung's terrain generator: a library that says, from a seed
and a tile's position, what the ground is there and how high it stands. It
makes a small map or a whole planet with the same code, and makes only
what is asked of it, so a planet costs what is explored of it. It places
terrain only. Biomes, plants, animals and settlements come later, and are
not designed here.

This document is a proposal. Nothing is built. The name is provisional.

Three things in the repository shape it:

- **TERRAIN.md decision 5.** The world asks a terrain source what a cell
  is, and stores only the chunks something has changed. A generator is the
  third source it names. Orogen is what that source calls.
- **TERRAIN.md step 4 (levels) is not built.** A world has levels, but
  nothing walks between them and sight stays on one. Relief in the first
  version (decision 6) needs part of that step built in the lab.
- **Tessera draws scenes, never worlds** (TESSERA.md decision 1). Orogen
  gives Tessera nothing. The lab's terrain reads Orogen, and the lab's
  scenes show the terrain, as they do an authored map.

## Decisions so far

1. **Orogen is an Odin package apart from the lab**, in `orogen/`, as
   Tessera is. It needs only Odin's core library and imports nothing of
   the lab, Triangle or Tessera, so a tool can make and print a map with
   no world. The lab imports it for its generated terrain source.
2. **It answers for a column, from the seed and the position alone.** For
   a tile's x and y it gives the ground's **elevation** (the level of the
   tile one stands in there) and its **ground class**. The same seed,
   parameters and position give the same answer whenever asked, in any
   order, so chunks are made as they are explored and never kept for
   their own sake.
   - A cell is read off its column: below the elevation, the class's
     underground (earth, rock); at it, the ground class; above it, air.
   - It computes in integers. Floating point differs between platforms
     and compilers, and a chunk that came out differently on a second
     asking would move the world under what stands on it. This is not
     determinism of the simulation (CLAUDE.md, scenario hashes), which
     stays no goal. It is that unexplored ground is nowhere stored, so the
     generator is its only record.
3. **Ground classes are Orogen's; terrain kinds are content's.** Orogen
   names a small set of classes (`air`, `earth`, `rock`, `grass`, `sand`,
   `water`, `ice`, more as it grows). A generated map in content has a
   legend from class to terrain kind, as a drawn map has one from
   character to kind (TERRAIN.md decision 4). Orogen never names a
   terrain kind, and content never reaches into Orogen's arithmetic.
   - A generated map is declared beside the drawn ones
     (`lab/content/terrain/terrain.tri`): which generator, its width and
     height in tiles, whether it wraps, its levels, its parameters and its
     legend. Its seed is the world seed unless it gives one.
4. **The world is a cylinder.** Tiles are one square grid. With wrapping
   on, x is taken modulo the world's width: walking east returns from the
   west. North and south end at the poles, in ice or sea nothing crosses.
   - A cube of six faces would be nearer a globe, and every grid algorithm
     in the lab would have to learn its seams. A torus wraps both ways,
     but walking north returns from the south and there is no latitude.
     On a cylinder a row is a latitude, so climate, winds and rain
     shadows read as on a globe, and the only seam is one rule.
   - A small map is the same generator with a small width and wrapping
     off. Width and height are parameters, so "a planet" is a size, not
     another mode.
   - Generated terrain wraps by itself: the chunk at x and the chunk a
     world's width east are one chunk. That the world is one across the
     seam (a house west of it seen from east of it) is the lab's to do:
     positions brought into range where they are committed, and the
     difference of two x's taken the short way round (slice 4).
5. **A planet is two tiers.** Noise can be asked of one tile. Plates,
   erosion, rivers and rain shadows can't: a river's course depends on
   everything upstream.
   - **The planet model** is computed whole, once, from the seed: a grid
     of **planet cells**, each some kilometres across, its x wrapping,
     holding plates and their motion, elevation, temperature, rainfall
     and prevailing wind, and rivers as a graph over the cells. It is a
     few megabytes and seconds of work. A save doesn't keep it: the seed
     makes it again.
   - **The refiner** answers for a tile's column from the seed, the
     position and the planet cells around it: their elevation smoothed
     between them, seeded detail added by how rugged they are, a river
     carved where the graph runs. Only the refiner runs as the world is
     explored.
   - A small map has no planet model: the refiner works from seeded noise
     alone (slice 1). The planet model, when built, takes the noise's
     place as the refiner's large-scale input and changes nothing above
     it.
   - **Climate is the generator's; weather is the simulation's.** The
     planet model says how warm and wet a place is over a year. What the
     sky does on a day is a domain in the lab, not designed here.
6. **Relief is in levels, from the first version.** Elevation counts
   levels (TERRAIN.md decision 1; a level is a storey). The ground at a
   tile is the cell at its elevation: floored and not solid, with solid
   earth or rock in every cell below and open air in every cell above.
   No new kind of cell is needed, and digging, building and falling meet
   generated ground as they would a drawn map's.
   - **A step up or down** is between tiles side by side whose ground
     differs by one level. It is read from terrain as it is: the cell
     beside the walker is solid and the cell above that is ground (up),
     or the cell beside is open air and the cell below that is ground
     (down). There is no ramp or stair kind for a hillside. Stairs and
     ladders indoors stay TERRAIN.md step 4's.
   - **A cliff** is a difference of two levels or more. Nothing walks it.
     Nothing falls from it yet either: a walker doesn't step into open
     air with no ground a level below.
   - **Hills hide what is behind them.** Earth and rock are opaque, and
     sight is a straight line through cells in three dimensions.
   - **Water is a ground class** in the first version: a tile below **sea
     level** is water, which nothing walks into. Seas and lakes are
     terrain, not the fluid domain's tile stocks, which would be a stock
     for every tile of an ocean. Where the two meet is open (below).
   - **The view needs nothing new.** Tessera draws the focus level, and
     lower levels dimmed through cells with no floor (TESSERA.md,
     "Levels"). Ground at the focus level is drawn, lower ground shows
     dimmed, and higher ground is the earth it is made of.
7. **Generated chunks are cached, not stored.** Sight and pathfinding ask
   for cells far more often than chunks change. The lab's generated
   source keeps the columns of the chunks last asked for, up to a bound,
   and drops the oldest. The cache is no part of a save or the state
   hash. A chunk is stored, as now, only once something changes in it.
8. **A save names what made its terrain.** The generator, its version, the
   seed and the parameters go in the save with the changed chunks. A
   changed generator would move every unchanged chunk of an old save, so
   a save whose generator version isn't the build's is refused, until
   there is a reason to do better.

## Slices

The first three are the first version: a small generated map with relief
that villagers walk and see across.

1. **The library.** `orogen/`: seeded integer noise, elevation from it,
   ground classes from elevation (water below sea level, sand beside it,
   grass, rock high up), width, height and wrapping. Tests: the same
   answer in any order of asking; a wrapped map's east edge meets its
   west. A small tool prints a map's classes and elevations as text.
2. **A generated terrain source in the lab.** The generated map in
   content with its legend; the source and its cache; the world's extent
   and levels from it; saving and the state hash. The watcher shows it.
3. **Walking and seeing relief.** Steps up and down in pathfinding and in
   the walk; sight through cells in three dimensions; an agent's terrain
   memory across levels. A scenario: a walk over a hill, and something
   behind the hill not seen until its crest.
4. **Wrapping in the lab.** Positions brought into range; differences
   taken the short way; the spatial index, sight, sound and pathfinding
   across the seam. A scenario on a world a few chunks round.
5. **The planet model.** Plates, elevation, climate and rivers on the
   grid of planet cells, shown as a map in the watcher (a scene with a
   tile to a planet cell).
6. **The refiner reads the planet model.** A planet walked from the
   ground.

## Open questions

- **How much the lab subtracts coordinates directly.** Slice 4's size
  isn't known until that is surveyed.
- **How tall a world is.** A level is a storey, so a mountain is hundreds
  of levels. Chunks are per level and unexplored ones cost nothing, but
  sight, the reality bubble's `up` and `down`, and a scene's range of
  levels were sized for buildings. The first version keeps relief within
  64 levels.
- **A surface view.** On a steep slope the focus level shows a thin band
  of ground. A view that follows the ground (each tile drawn at its own
  elevation, shaded by height) may read better outdoors, and is a
  backend's choice (TESSERA.md, "Levels").
- **Water as terrain and water as stock.** Where a sea meets a bucket, a
  ditch dug to the shore, or rain. Rivers that flow.
- **Long journeys.** Pathfinding is bounded (TERRAIN.md, "what lets
  terrain scale"). Crossing a planet wants the coarser graph that doc
  already asks for; the planet model may be it.
- **Underground.** Caves, ore, strata: what the cells below the ground
  are, beyond earth and rock.
- **Generators in content.** How much of a generator's rules (where sand
  ends, what counts as high) is parameters in content, and whether a
  generator could be written in Triangle at all (TERRAIN.md's open
  question, still open).
- **A changed generator and an old save.** Decision 8 refuses. Keeping
  old generator versions, or storing every chunk once seen, are the
  alternatives.

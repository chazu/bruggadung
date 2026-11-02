# Terrain

## Status and scope

The world's physical layout: what each tile at each level is (floor, wall,
open air), so that walking, sight, sound, light, air, water and Tessera
all read one structure instead of each assuming its own. Today the world
has none:
- an agent walks anywhere, even off the 32 x 32 grid;
- it sees every lit tile within four, through walls;
- rooms are rectangles of air written by hand, and "a different room" is
  how light, sound and air guess at walls;
- the fluid domain is a grid with nothing to stop water.

This document is a draft. Steps 1 and 2 are built (lab/src/core/BGTerrain,
lab/content/terrain.tri; sight and memory in lab/src/know/BGKnowledge).

The world is meant to grow to large roguelike and simulation games, with
maps generated as they are explored. Every decision here keeps that open,
and costs nothing per tile that serves no purpose.

## Decisions so far

1. **A wall fills its tile.** Terrain is per cell: a tile at one level,
   which is one terrain kind. There are no thin walls on tile edges, which
   would complicate every grid algorithm (movement, sight, fluids, finding
   rooms) for a nicer look.
2. **Terrain kinds are content.** A kind is a Triangle instance in the
   `terrain` family. It says:
   - whether it is solid (nothing walks into it);
   - whether it is opaque (sight stops at it);
   - whether it is floored (something to stand on; without a floor the
     level below shows, and things fall);
   - its material;
   - its look (its appearance key for Tessera).

   A cell holds a small number, the kind's index in the world's table (0:
   no tile, outside the world). Properties are cached per kind, so asking
   whether a cell is solid is an array lookup.
3. **A cell is not an entity until it needs to be.** COMPONENTS.md: a thing
   gains identity when something needs to tell it apart. A plain wall is a
   number in a grid. A section of wall that something tells apart (cracked,
   marked, a brick loose) becomes an entity there. Doors are entities
   already (they have state), and stand in doorway cells.
4. **Maps are drawn in characters, embedded; their legend is Triangle.** A
   map's levels are text files brought in with `@embed` (CONTENT_LANGUAGE.md
   §2). The legend, which says what kind each character is, and the fill
   for cells the drawing leaves out, stay in Triangle beside the kinds.
5. **Terrain comes from a source, and only what changes is stored.** The
   world asks its terrain source what a cell is:
   - an authored map (step 1);
   - a plain fill, for a world with no map;
   - later, a generator, seeded from the world's seed and the chunk.

   Terrain is chunked, 32 x 32 tiles of one level per chunk. A chunk is
   stored only once something changes in it, as a copy of what the source
   gave with the change made. A save keeps the source's name and the
   changed chunks, so a world generated as it is explored saves no more
   than what happened in it.
6. **Terrain is world state, changed by commitment.** A change is a
   proposal like any other (`setTerrain`), journaled so a rejected group
   leaves it as it was, emitted as an event, saved, and part of the state
   hash. No operation changes terrain yet (digging, building, a wall
   knocked down come with their scenarios); the path is there so they need
   nothing new.
7. **An agent's memory of terrain is a bit per tile, not a copy.** Terrain
   seldom changes, so what an agent believes a tile it has seen to be is
   almost always what it is.
   - **A bit per tile seen:** an agent keeps, per chunk it has seen any of,
     a bit per tile (128 bytes a chunk), and when it last saw the chunk,
     which is coarse but enough to dim memory by age.
   - **Exceptions for changes:** when terrain changes, an agent that has
     seen the tile and doesn't see the change keeps an exception, the kind
     it last saw there, until it sees the tile again.

   That is exact, and costs a world of thousands of agents a few bits per
   tile each saw, instead of a copy of the map each. It replaces the 8 KB
   grid of times each agent keeps today, whose precision nothing reads:
   "seen ever" (exploring) and "seen now" (the map) are all that is asked
   (step 2).

## Steps

Each keeps every existing scenario as it is. A world with no map is open
floor.

1. **Kinds, maps, the chunked store, changes.**
   - Terrain kinds and maps in content (`@embed` for the drawing).
   - The chunked store with its sources.
   - The world's extent from its map.
   - The `setTerrain` proposal.
   - Saving and the state hash.
   - Walking blocked by solid terrain and by the world's edge.
2. **Sight and memory** (built). Line of sight through cells that aren't
   opaque, and agents' terrain memory (decision 7), replacing the grid of
   times.
   - **Sight:** a tile is in sight when nothing opaque stands on a straight
     line to it, either way, so sight is mutual. A wall itself is seen.
   - **Memory:** a terrain change emits an event, and an agent that doesn't
     see the changed tile, but had seen it, recalls the kind it saw.
3. **Rooms from terrain.**
   - Air regions found by flood fill, bounded by solid cells and closed
     doors, instead of rectangles written by hand; light, sound and air read
     them.
   - The existing scenarios drawn as maps, giving the results they give now.
4. **Levels.** Floors, open air, stairs or ladders; water falling through
   what has no floor.

## Open questions

- **The world's extent past 32 x 32.** The fluid domain, the explorer and
  the tile memory loop over a 32 x 32 grid. Step 1 sizes the world from its
  map; maps larger than that work for terrain and walking, but water there
  waits for the fluid domain to be generalised.
- **Generators.** What a generator is in content (rules, rooms and
  corridors, noise), and how determinism by seed and chunk meets content
  that changes.
- **Pathfinding.** Agents walk greedily toward a goal, so a wall stops
  them. Paths over terrain, and over the terrain an agent remembers rather
  than the true one, come with step 2 or soon after.

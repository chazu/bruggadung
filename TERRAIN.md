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

This document is a draft. Steps 1 to 3 are built (lab/src/core/BGTerrain,
lab/content/terrain/terrain.tri; sight and memory in lab/src/know/BGKnowledge;
rooms in BGTerrain and `-[BGWorld airRegionAt:]`; links from doorways in
`-[BGWorld airOpeningsOf:]`; air following terrain in BGCommitter).

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
   - a generator, seeded from the world's seed (OROGEN.md; built for
     open country).

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
3. **Rooms from terrain** (built).
   - **What a room is:** the cells of a level joined side by side that are
     neither solid nor `divides` (a doorway: it belongs to neither room it
     joins), and are enclosed: at most `BG_ROOM_MAX` (4096) of them, none
     at the world's edge. Ground that isn't enclosed is open: in no room. A
     world with no map, open floor to its edges, has no rooms.
   - **Found from a cell out, and kept per chunk.** A room is flooded from
     the cell asked, when first asked, and its cells labelled in their
     chunk (a label table per chunk, kept only once something in it was
     asked of). A flood stops at the edge, past `BG_ROOM_MAX`, or on ground
     already known open, and labels what it reached open. Nothing is ever
     found over the whole world, so a world generated as it is explored
     costs only what is asked of it.
   - **A change finds again only what is beside it.** A cell changing
     whether it is solid or divides lets go of the rooms of it and its four
     neighbours (each at most `BG_ROOM_MAX` cells), found again when next
     asked. A wall that parts open ground floods each side, as far as
     `BG_ROOM_MAX`, for one it has enclosed.
   - **The air over a tile** is the region (a GasStore) whose tile (`atX`,
     `atY`, `atLevel`) is in the tile's room; a tile in a room with no air
     of its own is outdoors. The world keeps each room's air by room
     number, made again when the regions or the rooms change. Light, sound
     and the atmosphere read it, and the rectangles written by hand are
     gone.
   - **Links from doorways.** A region opens through each doorway at its
     room's side (a room keeps its doorways, found by its flood) to the
     region beyond, or the outdoors (open ground, a room with no air, the
     world's edge). A door standing in the doorway passes its `wide` while
     ajar and nothing while shut; with no door, the doorway's kind passes
     its `draught` (a terrain property; a doorway, 200 mmol a second). A
     region's `gap` is now its leak to the outdoors, through walls and
     windows. `opensTo` and `door` are gone. The atmosphere keeps a list
     of links, each measured from its smaller side, found again each time
     it reads the world and keeping its carries by its two sides and
     doorway. Light's "shut in" and sound's "through an open door" read the
     same openings.
   - **Air follows terrain**, in the commit that changes it, journaled with
     it:
     - **A wall knocked through** joining rooms with air of their own
       joins their air into the first's (the least id), every stock and
       total summed; the others end with it as their successor.
     - **A wall built across** a room's air parts it: each side cut off
       gets air of its own (`parted_air`), each stock and total shared by
       the sides' tiles; the air keeps the rest, and the side its tile is
       on (the largest, if the wall is on its tile).
     - **A room opened to the outdoors** leaves its air in no room: the
       atmosphere links it to the outdoors at a hundredth of its total a
       second, and it airs out. If the room is closed again, the air is
       its room's again.
     The atmosphere's ledger balances through each: a join or a part moves
     stock between regions, and airing out is inflow.
   - **The scenarios:** every air scenario draws `rooms_map`, the room and
     back room where they were, a wall row with their doorways below, and
     the corridor a row lower, walled at its ends. They give the results
     they gave, the corridor's listener a tile further from the clatter.
4. **Levels.** Floors, open air, stairs or ladders; water falling through
   what has no floor. Built of it, for relief (OROGEN.md decision 6): a
   step up or down a slope, in the walk and in pathfinding; sight, terrain
   memory and reach across levels.

### Built besides: what lets terrain scale

- **Pathfinding** (lab/src/core/BGPath): a bounded search over tiles,
  expanding at most `BG_PATH_BUDGET` (4096) of them, so it costs the same
  in any world. Toward a target it is A* to the target's reach; looking
  for something it is breadth-first. Agents walk over the ground as they
  believe it (decision 7): a tile they saw solid stops them, a tile never
  seen they guess open. Where the straight way is as short as any, they
  take the longer axis first, as before, so open-ground walks are
  unchanged. Exploring is the same search, for the nearest tile never
  seen, in place of a scan of the whole map; out of a search's reach of
  anything unseen, the explorer stops.
- **The spatial index** (lab/src/core/BGIndex, BGWorld): what stands on the
  ground, filed by chunk; what is in, on, held by or part of a thing,
  filed by the thing; traces on the floor by chunk, and traces borne by
  their bearer. Each list is in entity order, so a query reads the same
  however the index was built; kept with every change of location or
  trace, with every change a refused group undoes, and built again by a
  save restored. Sight reads only what is within `BG_SIGHT` and all it
  holds; hearing only the traces within `BG_SOUND_REACH` (no sound carries
  further); a step only its tile's traces; a doorway's door only its
  tile.
- **Tile stocks are sparse.** Water lies in chunks kept once a tile in
  them is wet; saves write the wet tiles, the state hash reads them.
  The fluid domain works from the wet tiles and their neighbours on any
  map, as many as there are (its holders grow as needed), and water
  stops at walls.

## Open questions

- **Rooms larger than `BG_ROOM_MAX`** are open ground: a great hall wants
  the bound raised, or the outdoors told apart another way (with levels,
  open to the sky).
- **Doorways one tile thick.** A link is found across one doorway cell; two
  doorway cells in a row join nothing.
- **Paths past a search's reach.** A target further than the budget's
  reach is walked toward by the nearest point found, which a long wall can
  mislead; long journeys want a coarser graph (rooms and doorways, or
  chunks) to plan over first.
- **Generators.** OROGEN.md proposes the generator for open country
  (elevation and ground class by seed and position) and how a generated
  map is declared. Still open: what a generator is in content (rules,
  rooms and corridors), and how a generator meets content that changes.

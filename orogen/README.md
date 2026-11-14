# Orogen

The terrain generator of bruggadung: from a seed and a tile's position,
how high the ground stands there and what it is. The design is
[OROGEN.md](../OROGEN.md).

This is slice 1, the library: the Odin package `orogen` (this directory).
It needs only Odin's core library. The lab's generated terrain source
reads it (`../lab/src/core_terrain.odin`).

- **A map** (`orogen.odin`: `Map`, `map_make`, `map_fault`): a seed, a
  width and height in tiles, its levels, whether it wraps, and what shapes
  its ground: the lowest and highest elevation, sea level, how far across
  its largest rises are, how rough it is, how deep its soil, and where
  bare stone begins.
- **Columns** (`column`, `elevation`, `columns`): a tile's elevation (the
  level of the cell one stands in there, or of the seabed) and its ground
  class. The same map and position give the same column whenever asked,
  in any order. `columns` fills a block at once.
- **Cells** (`cell`, `cell_of`, `top`): rock and earth beneath the
  ground, the ground at its elevation, air over it; over a seabed, water
  up to sea level.
- **Ground classes** (`Class`): `air`, `earth`, `rock`, `water`, `grass`,
  `sand`, `stone`, and `none` outside the world. Sand is ground at sea
  level; stone is ground high up, or beside a cliff (a neighbour two
  levels or more above or below).
- **Wrapping:** on a map that wraps, x is taken modulo its width, and the
  ground runs unbroken across the seam. Such a map is a whole number of
  spans wide. North and south never wrap.
- **Text** (`text.odin`: `map_text`): a character to a tile, its ground
  class or the level of its top.

Everything is computed in integers, so a map is the same on every
platform: `tests/golden/` holds one, and the tests compare. A change that
moves a map changes `VERSION` and writes the golden files again (`make
golden`).

```odin
import "orogen"

m := orogen.map_make(seed, 256, 256)
assert(orogen.map_fault(m) == "")
c, ok := orogen.column(m, x, y)     // c.elevation, c.class
k := orogen.cell(m, x, y, z)        // .Earth, .Grass, .Air, ...
```

## The tool

```sh
make                              # build/orogen
build/orogen --seed 7             # 96 by 40 tiles, a character to a tile
build/orogen --seed 7 --elevations
build/orogen --wide 1024 --high 512 --wraps --at 1000,0 --size 80,24
```

`~` water, `:` sand, `.` grass, `^` stone. With `--elevations`, each
tile's top level: 0 to 9, then a to z.

## Building

```sh
make test     # the tests
make check    # the package and the tool, checked with -vet -strict-style
```

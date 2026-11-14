package orogen

// Orogen (OROGEN.md): what the ground is at a tile and how high it stands,
// from a seed and the tile's position alone. The same map and position give
// the same column whenever asked, in any order, so ground is made as it is
// asked for and kept nowhere. Every sum here is in integers: floating point
// differs between platforms, and unexplored ground has no other record.

// Changed whenever a map would come out differently: a save names it
// (OROGEN.md decision 8).
VERSION :: 1

// What Orogen says a cell is. A generated map's legend turns each into a
// terrain kind (OROGEN.md decision 3).
Class :: enum u8 {
	None,  // outside the world
	Air,   // above the ground
	Earth, // beneath the ground, near it
	Rock,  // beneath the ground, deeper, and beneath bare stone
	Water, // from a seabed up to sea level
	Grass, // ground
	Sand,  // ground at the water's edge
	Stone, // ground: bare rock, high up or at a cliff
}

@(rodata)
CLASS_NAMES := [Class]string {
	.None  = "none",
	.Air   = "air",
	.Earth = "earth",
	.Rock  = "rock",
	.Water = "water",
	.Grass = "grass",
	.Sand  = "sand",
	.Stone = "stone",
}

class_name :: proc(c: Class) -> string {
	return CLASS_NAMES[c]
}

class_named :: proc(name: string) -> (Class, bool) {
	for n, c in CLASS_NAMES do if n == name do return c, true
	return .None, false
}

// A map: its seed, its size, and what shapes its ground. Sizes are in
// tiles and levels.
Map :: struct {
	seed:      u64,
	wide:      i32,  // tiles east to west
	high:      i32,  // tiles north to south
	levels:    i32,  // levels, from 0
	wraps:     bool, // x is taken modulo `wide`: east meets west
	lowest:    i32,  // the lowest elevation: the deepest seabed
	sea:       i32,  // sea level: ground below it is under water
	highest:   i32,  // the highest elevation
	span:      i32,  // tiles across the largest rises and hollows: a power of two
	octaves:   i32,  // how many sizes of rise are summed, each half the last across
	roughness: i32,  // of 256: each size's share of the one before
	soil:      i32,  // levels of earth over the rock
	bare:      i32,  // the elevation at and above which ground is bare stone
}

// A map of rolling ground with a little sea, `wide` by `high` tiles.
map_make :: proc(seed: u64, wide, high: i32, wraps := false) -> Map {
	return Map {
		seed = seed,
		wide = wide,
		high = high,
		levels = 32,
		wraps = wraps,
		lowest = 2,
		sea = 8,
		highest = 26,
		span = 32,
		octaves = 4,
		roughness = 128,
		soil = 3,
		bare = 21,
	}
}

// Why a map can't be made, or "" if it can.
map_fault :: proc(m: Map) -> string {
	switch {
	case m.wide < 1 || m.high < 1:
		return "a map is at least one tile each way"
	case m.levels < 2:
		return "a map has at least two levels: ground and the air over it"
	case m.lowest < 0 || m.lowest > m.sea || m.sea > m.highest:
		return "lowest, sea and highest go up in that order, from 0"
	case m.highest > m.levels - 2:
		return "the highest ground leaves a level of air over it"
	case m.span < 2 || m.span & (m.span - 1) != 0:
		return "span is a power of two, at least 2"
	case m.octaves < 1 || m.span >> uint(m.octaves - 1) < 2:
		return "the smallest size of rise is at least two tiles across"
	case m.roughness < 0 || m.roughness > 256:
		return "roughness is of 256"
	case m.soil < 0:
		return "soil is not negative"
	case m.wraps && m.wide % m.span != 0:
		return "a map that wraps is a whole number of spans wide"
	}
	return ""
}

// A tile's column: the ground's elevation (the level of the cell one stands
// in there, or of the seabed) and what the ground is. Under water the class
// is `.Water`.
Column :: struct {
	elevation: i32,
	class:     Class,
}

// The column at a tile, and whether the tile is in the world.
column :: proc(m: Map, x, y: i32) -> (c: Column, ok: bool) {
	px := place(m, x, y) or_return
	e := rise(m, px, y)
	return Column{e, ground(m, e, steep(m, px, y, e))}, true
}

// The ground's elevation at a tile, and whether the tile is in the world.
elevation :: proc(m: Map, x, y: i32) -> (e: i32, ok: bool) {
	px := place(m, x, y) or_return
	return rise(m, px, y), true
}

// The columns of `w` by `h` tiles from (x0, y0), a row after a row, into
// `out`; a tile outside the world gets class `.None`. As `column` gives,
// with each elevation worked out once.
columns :: proc(m: Map, x0, y0, w, h: i32, out: []Column) {
	assert(w >= 0 && h >= 0 && len(out) >= int(w) * int(h))
	if w == 0 || h == 0 do return
	W, H := int(w) + 2, int(h) + 2
	rises := make([]i32, W * H, context.temp_allocator)
	OUT :: min(i32)
	for j in 0 ..< H do for i in 0 ..< W {
		x, ok := place(m, x0 + i32(i) - 1, y0 + i32(j) - 1)
		rises[j * W + i] = rise(m, x, y0 + i32(j) - 1) if ok else OUT
	}
	for j in 1 ..< H - 1 do for i in 1 ..< W - 1 {
		e := rises[j * W + i]
		c := &out[(j - 1) * int(w) + i - 1]
		if e == OUT {
			c^ = Column{0, .None}
			continue
		}
		cliff := false
		for n in ([4]i32{rises[j * W + i - 1], rises[j * W + i + 1], rises[(j - 1) * W + i], rises[(j + 1) * W + i]}) {
			if n != OUT && abs(n - e) >= 2 do cliff = true
		}
		c^ = Column{e, ground(m, e, cliff)}
	}
}

// What a cell of a column is: rock and earth beneath the ground, the
// ground at its elevation, air over it; over a seabed, water up to sea
// level. `.None` outside the map's levels.
cell_of :: proc(m: Map, c: Column, z: i32) -> Class {
	if z < 0 || z >= m.levels || c.class == .None do return .None
	switch {
	case z > c.elevation:
		return .Water if c.class == .Water && z < m.sea else .Air
	case z == c.elevation:
		return c.class
	}
	return .Rock if c.class == .Stone || c.elevation - z > m.soil else .Earth
}

// What the cell at a tile and level is.
cell :: proc(m: Map, x, y, z: i32) -> Class {
	c, ok := column(m, x, y)
	return cell_of(m, c, z) if ok else .None
}

// The level of a column's topmost cell that isn't air: the ground, or the
// water's surface.
surface :: proc(m: Map, c: Column) -> i32 {
	return m.sea - 1 if c.class == .Water else c.elevation
}

// x brought into the world (round the seam, if the map wraps), and whether
// the tile is in it.
@(private)
place :: proc(m: Map, x, y: i32) -> (i32, bool) {
	if y < 0 || y >= m.high do return 0, false
	if m.wraps do return ((x % m.wide) + m.wide) % m.wide, true
	return x, x >= 0 && x < m.wide
}

// What the ground is at an elevation; `cliff`: a neighbour stands two
// levels or more above or below.
@(private)
ground :: proc(m: Map, e: i32, cliff: bool) -> Class {
	switch {
	case e < m.sea:
		return .Water
	case cliff || e >= m.bare:
		return .Stone
	case e == m.sea:
		return .Sand
	}
	return .Grass
}

@(private)
steep :: proc(m: Map, x, y, e: i32) -> bool {
	for d in ([4][2]i32{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
		nx, ok := place(m, x + d.x, y + d.y)
		if ok && abs(rise(m, nx, y + d.y) - e) >= 2 do return true
	}
	return false
}

// The elevation at a tile in the world: the sizes of rise summed, each
// its share of the one before, spread from `lowest` to `highest`.
@(private)
rise :: proc(m: Map, x, y: i32) -> i32 {
	ONE :: 1 << 16
	total, weights: i64
	weight: i64 = ONE
	for o in 0 ..< m.octaves {
		total += noise(m, o, x, y) * weight
		weights += weight
		weight = weight * i64(m.roughness) / 256
		if weight == 0 do break
	}
	n := total / weights // 0 ..< ONE, mostly near the middle
	n = clamp(ONE / 2 + (n - ONE / 2) * 2, 0, ONE - 1)
	return m.lowest + i32(n * i64(m.highest - m.lowest + 1) >> 16)
}

// One size of rise at a tile, 0 ..< 1 << 16: values at the corners of a
// grid `span >> octave` tiles across, eased between them.
@(private)
noise :: proc(m: Map, octave, x, y: i32) -> i64 {
	ONE :: 1 << 16
	size := m.span >> uint(octave)
	ix, iy := x / size, y / size
	tx, ty := ease(i64(x - ix * size) * ONE / i64(size)), ease(i64(y - iy * size) * ONE / i64(size))
	a, b := corner(m, octave, size, ix, iy), corner(m, octave, size, ix + 1, iy)
	c, d := corner(m, octave, size, ix, iy + 1), corner(m, octave, size, ix + 1, iy + 1)
	top := a + (b - a) * tx / ONE
	bottom := c + (d - c) * tx / ONE
	return top + (bottom - top) * ty / ONE
}

// 3t^2 - 2t^3, of 1 << 16.
@(private)
ease :: proc(t: i64) -> i64 {
	ONE :: 1 << 16
	return t * t / ONE * (3 * ONE - 2 * t) / ONE
}

// The value at a grid corner, 0 ..< 1 << 16. On a map that wraps, the
// corners a world's width apart are one corner.
@(private)
corner :: proc(m: Map, octave, size, ix, iy: i32) -> i64 {
	ix := ix
	if m.wraps do ix %= m.wide / size
	h := mix(m.seed ~ (u64(u32(octave)) + 1) * 0x9e3779b97f4a7c15)
	h = mix(h ~ u64(u32(ix)))
	h = mix(h ~ u64(u32(iy)) << 32)
	return i64(h >> 48)
}

@(private)
mix :: proc(v: u64) -> u64 {
	v := v
	v ~= v >> 30
	v *= 0xbf58476d1ce4e5b9
	v ~= v >> 27
	v *= 0x94d049bb133111eb
	v ~= v >> 31
	return v
}

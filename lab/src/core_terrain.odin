package lab

/*
 * BGTerrain — what each tile at each level is (TERRAIN.md): a terrain kind
 * per cell, from a source (an authored map, or a plain fill), with only the
 * chunks that have changed stored. Plain C, for the loops that ask it of
 * many cells (walking, and later sight, rooms and fluids).
 */

/*
 * BGTerrain (TERRAIN.md): a kind per cell. The source is a drawing (an
 * authored map, as dense as it is drawn) or a plain fill; a chunk is stored,
 * in a small open-addressed table, only once a cell in it changes, and a
 * world with nothing changed reads straight from the source.
 */

import "core:c"
import "core:fmt"
import "core:mem"
import "core:slice"
import "../../orogen"
import tri "../../triangle/odin/triangle"

BG_CHUNK :: 32               /* a chunk is BG_CHUNK x BG_CHUNK tiles of one level */
BG_MAX_TERRAIN :: 1024       /* kinds in content, at most */
BG_ROOM_MAX :: 4096          /* a room's cells, at most: past it, ground is open */

Terrain_Kind :: u16          /* a kind's index in the world's table; 0: no tile */

Terrain_Info :: struct {
	name:    cstring,          /* its content instance: "stone_wall" */
	look:    cstring,          /* its appearance key */
	solid:   bool,             /* nothing walks into it */
	opaque:  bool,             /* sight stops at it */
	floored: bool,             /* something to stand on */
	divides: bool,             /* a room ends here without a wall: a doorway */
	draught: i64,              /* air it passes with no door shut in it, mmol a second each way */
	exposed: bool,             /* in the open: nowhere to hide, one hiding on it is seen as anyone is */
}

@(private = "file")
BG_MAX_TERRAIN_CELLS :: 16 * 1024 * 1024    /* a drawing, at most */

@(private = "file")
Chunk :: struct {
	cx:    i32,
	cy:    i32,
	z:     i32,
	cells: [^]Terrain_Kind,         /* NULL: an empty slot */
}

/* A chunk's room labels, kept once a room or open ground in it is found:
 * per cell 0 (not known), BG_OPEN, or a room's number. */
@(private = "file")
Labels :: struct {
	cx:    i32,
	cy:    i32,
	z:     i32,
	cells: [^]u32,                  /* NULL: an empty slot */
}

@(private = "file")
BG_OPEN :: u32(0xFFFFFFFF)      /* open ground: in no room */
@(private = "file")
BG_VISITING :: u32(0xFFFFFFFE)  /* being flooded */

@(private = "file")
Room :: struct {
	size:   u32,                    /* cells; 0: a free slot */
	x:      i32,                    /* its first cell */
	y:      i32,
	z:      i32,
	ndoors: u32,                    /* the doorways at its side, by y then x */
	doors:  [^][3]i32,
}

@(private = "file")
Flood_Cell :: struct {
	x:   i32,
	y:   i32,
	was: u32,                       /* its label before */
}

/* A generated map's source (OROGEN.md): Orogen's map, the terrain kind of
 * each ground class, and the columns of the chunks last asked for. The
 * columns are kept for speed alone: no part of a save or the state hash. */
@(private = "file")
BG_GENERATED_SLOTS :: 256       /* a power of two */

@(private = "file")
Generated_Chunk :: struct {
	cx:      i32,
	cy:      i32,
	columns: ^[BG_CHUNK * BG_CHUNK]orogen.Column,       /* nil: an empty slot */
}

@(private = "file")
Generated :: struct {
	plan:  orogen.Map,
	kinds: [orogen.Class]Terrain_Kind,
	slots: [BG_GENERATED_SLOTS]Generated_Chunk,
}

Terrain :: struct {
	generated: ^Generated,          /* or nil: drawn, or the fill */
	kinds:    [^]Terrain_Info,      /* kinds[ 0] is none */
	nkinds:   uint,
	map_:     cstring,
	wide:     i32,
	high:     i32,
	levels:   i32,
	fill:     Terrain_Kind,
	drawn:    [^]Terrain_Kind,      /* wide * high * levels, or NULL: the fill everywhere */
	chunks:   [^]Chunk,
	nchunks:  uint,
	cap_:     uint,                 /* a power of two, or 0 */
	labels:   [^]Labels,
	nlabels:  uint,
	labelcap: uint,                 /* a power of two, or 0 */
	rooms:    [^]Room,              /* room n is rooms[ n - 1] */
	nrooms:   u32,
	roomcap:  u32,
	free_:    [^]u32,               /* room numbers to use again */
	nfree:    u32,
	dropped:  u64,
	flood:    [^]Flood_Cell,        /* BG_ROOM_MAX + 1 cells */
}

// realloc: the block resized, in the context allocator.
@(private = "file")
realloc :: proc(p: rawptr, old_size, new_size: uint) -> rawptr {
	q, _ := mem.resize(p, int(old_size), int(new_size))
	return q
}

@(private = "file")
dup_string :: proc(s: cstring) -> cstring {
	n: uint
	d: [^]u8

	n = uint(len(s)) + 1
	d = make([^]u8, n)
	mem.copy(d, rawptr(s), int(n))
	return cstring(d)
}

/* A text field of a content node, malloc'd, or NULL. */
@(private = "file")
text_of :: proc(content: ^tri.Content, node: ^tri.Node, path: cstring) -> cstring {
	v: ^tri.Node
	n: c.size_t
	s: [^]u8

	v = tri.at(content, node, path) if node != nil else nil
	if v == nil do return nil
	n = tri.text(content, v, nil, 0)
	if n == max(c.size_t) do return nil
	s = make([^]u8, n + 1)
	tri.text(content, v, s, n + 1)
	return cstring(s)
}

@(private = "file")
is_true :: proc(content: ^tri.Content, node: ^tri.Node, path: cstring) -> bool {
	v: ^tri.Node

	v = tri.at(content, node, path) if node != nil else nil
	return v != nil && tri.node_type(v) == tri.type_named(content, "true")
}

// The reason a build failed, for an error out-parameter: snprintf into the
// caller's buffer, before. (The world's buffer held 255 bytes; no reason
// here comes near it.)
@(private = "file")
set_error :: proc(error: ^string, format: string, args: ..any) {
	if error != nil do error^ = fmt.tprintf(format, ..args)
}

/* The kinds content declares, in the `terrain` family's order. */
@(private = "file")
load_kinds :: proc(t: ^Terrain, content: ^tri.Content, error: ^string) -> bool {
	family: ^tri.Index
	kind: ^tri.Node
	tag: cstring
	i: uint
	n: uint
	look: cstring
	lo: i64
	hi: i64

	family = tri.family_index(content, "terrain")
	n = tri.index_count(family) if family != nil else 0
	if n == 0 || n >= BG_MAX_TERRAIN {
		set_error(error, "too many terrain kinds" if n != 0 else "content has no terrain kinds (the terrain family)")
		return false
	}
	t.kinds = make([^]Terrain_Info, n + 1)
	t.nkinds = n
	for i = 0; i < n; i += 1 {
		tag = cstring(tri.index_tag(family, i))
		kind = tri.spec(content, tag)           /* its defaults applied: floored unless said */
		if kind == nil do kind = tri.pattern(content, tag)
		look = text_of(content, kind, "look")
		t.kinds[i + 1].name = dup_string(tag)
		t.kinds[i + 1].look = look if look != nil else dup_string(tag)
		t.kinds[i + 1].solid = is_true(content, kind, "solid")
		t.kinds[i + 1].opaque = is_true(content, kind, "opaque")
		t.kinds[i + 1].floored = is_true(content, kind, "floored")
		t.kinds[i + 1].divides = is_true(content, kind, "divides")
		t.kinds[i + 1].exposed = is_true(content, kind, "exposed")
		if kind != nil && tri.node_interval(tri.at(content, kind, "draught"), &lo, &hi) != 0 && lo == hi && lo >= 0 {
			t.kinds[i + 1].draught = lo
		}
	}
	return true
}

/* 0 if none */
terrain_kind_named :: proc(t: ^Terrain, name: cstring) -> Terrain_Kind {
	i: uint

	for i = 1; name != nil && i <= t.nkinds; i += 1 {
		if string(t.kinds[i].name) == string(name) do return Terrain_Kind(i)
	}
	return 0
}

// The .m's static terrain_new, renamed: BGTerrainNew has its name here.
@(private = "file")
new_terrain :: proc(content: ^tri.Content, error: ^string) -> ^Terrain {
	t: ^Terrain

	t = new(Terrain)
	if !load_kinds(t, content, error) {
		terrain_free(t)
		return nil
	}
	return t
}

/* Terrain from content's kinds (the `terrain` family) over an extent, every
 * cell the fill kind (by name; NULL: "open_floor", or else the first kind).
 * NULL, with the reason, if content has no kinds or the fill names none.
 * (The reason was snprintf'd into a buffer: it is set in *error, in the
 * temporary allocator, when error isn't nil.) */
terrain_new :: proc(content: ^tri.Content, wide: i32, high: i32, levels: i32, fill: cstring, error: ^string) -> ^Terrain {
	t: ^Terrain

	if wide <= 0 || high <= 0 || levels <= 0 {
		set_error(error, "an empty extent")
		return nil
	}
	t = new_terrain(content, error)
	if t == nil do return nil
	t.wide = wide
	t.high = high
	t.levels = levels
	t.fill = terrain_kind_named(t, fill) if fill != nil else terrain_kind_named(t, "open_floor")
	if t.fill == 0 && fill == nil do t.fill = 1
	if t.fill == 0 {
		set_error(error, "no terrain kind named %s", fill)
		terrain_free(t)
		return nil
	}
	return t
}

/* --- a map ---------------------------------------------------------------------------- */

@(private = "file")
Drawn_Level :: struct {
	z:    i32,
	rows: cstring,
}

/* A whole number a map gives, or `otherwise`. */
@(private = "file")
number_of :: proc(content: ^tri.Content, node: ^tri.Node, path: cstring, otherwise: i64) -> i64 {
	lo: i64
	hi: i64

	if tri.node_interval(tri.at(content, node, path), &lo, &hi) == 0 || lo != hi do return otherwise
	return lo
}

/* Terrain made by a generated map in content (a #Generated instance,
 * OROGEN.md): its extent and what shapes its ground are the map's, its seed
 * the map's or else `seed`, and each ground class the kind its legend
 * gives. NULL, with the reason, if the map is malformed. */
@(private = "file")
terrain_generated :: proc(content: ^tri.Content, node: ^tri.Node, map_: cstring, seed: u64, error: ^string) -> ^Terrain {
	t: ^Terrain
	g: ^Generated
	list: ^tri.Node
	item: ^tri.Node
	class: cstring
	kind: cstring
	own: i64
	ok: bool

	t = new_terrain(content, error)
	if t == nil do return nil
	t.map_ = dup_string(map_)
	g = new(Generated)
	t.generated = g
	own = number_of(content, node, "seed", 0)
	g.plan = orogen.Map {
		seed      = u64(own) if own != 0 else seed,
		wide      = i32(number_of(content, node, "width", 0)),
		high      = i32(number_of(content, node, "height", 0)),
		levels    = i32(number_of(content, node, "tall", 0)),
		wraps     = is_true(content, node, "wraps"),
		lowest    = i32(number_of(content, node, "lowest", -1)),
		sea       = i32(number_of(content, node, "sea", -1)),
		highest   = i32(number_of(content, node, "highest", -1)),
		span      = i32(number_of(content, node, "span", 0)),
		octaves   = i32(number_of(content, node, "octaves", 0)),
		roughness = i32(number_of(content, node, "roughness", -1)),
		soil      = i32(number_of(content, node, "soil", -1)),
		bare      = i32(number_of(content, node, "bare", 0)),
	}
	ok = true
	if fault := orogen.map_fault(g.plan); fault != "" {
		set_error(error, "%s: %s", map_, fault)
		ok = false
	}
	for list = tri.at(content, node, "legend"); ok && list != nil; list = tri.at(content, list, "rest") {
		item = tri.at(content, list, "first")
		if item == nil do break
		class = text_of(content, item, "class")
		kind = text_of(content, item, "terrain")
		c, known := orogen.class_named(string(class))
		if !known || c == .None {
			set_error(error, "%s: no ground class named %s", map_, class if class != nil else "")
			ok = false
		} else {
			g.kinds[c] = terrain_kind_named(t, kind)
			if g.kinds[c] == 0 {
				set_error(error, "%s: no terrain kind named %s, for %s", map_, kind if kind != nil else "", class)
				ok = false
			}
		}
		delete(class)
		delete(kind)
	}
	for c in orogen.Class {
		if ok && c != .None && g.kinds[c] == 0 {
			set_error(error, "%s: its legend has no terrain kind for %s", map_, orogen.class_name(c))
			ok = false
		}
	}
	if !ok {
		terrain_free(t)
		return nil
	}
	t.wide = g.plan.wide
	t.high = g.plan.high
	t.levels = g.plan.levels
	t.fill = g.kinds[.Air]
	return t
}

/* The generator of a generated map's terrain: its seed, and the version of
 * Orogen that makes it; false if the terrain isn't generated. */
terrain_generator :: proc(t: ^Terrain) -> (seed: u64, version: int, ok: bool) {
	if t == nil || t.generated == nil do return 0, 0, false
	return t.generated.plan.seed, orogen.VERSION, true
}

/* The level one stands at on a tile: of its highest cell that has a floor
 * and isn't solid; false if it has none, or is outside the extent. */
terrain_ground_level :: proc(t: ^Terrain, x: i32, y: i32) -> (z: i32, ok: bool) {
	k: Terrain_Kind

	for z = t.levels - 1; z >= 0; z -= 1 {
		k = terrain_at(t, x, y, z)
		if k != 0 && t.kinds[k].floored && !t.kinds[k].solid do return z, true
	}
	return 0, false
}

/* Terrain drawn by a map in content (a #Map instance): its extent is the
 * drawing's. NULL, with the reason, if the map is malformed. */
terrain_from_map :: proc(content: ^tri.Content, map_: cstring, seed: u64, error: ^string) -> ^Terrain {
	node: ^tri.Node
	list: ^tri.Node
	item: ^tri.Node
	t: ^Terrain
	legend: [256]Terrain_Kind
	drawn: [64]Drawn_Level
	cells: [^]Terrain_Kind
	s: [^]u8
	glyph: cstring
	kind: cstring
	fill: cstring
	lo: i64
	hi: i64
	ncells: i64
	nlevels: i32
	i: i32
	x: i32
	y: i32
	wide: i32
	high: i32
	levels: i32
	ok: bool

	node = tri.spec(content, map_)
	if node == nil do node = tri.pattern(content, map_)
	if node != nil && tri.at(content, node, "generator") != nil do return terrain_generated(content, node, map_, seed, error)
	if node == nil || tri.at(content, node, "levels") == nil {
		set_error(error, "no map named %s", map_)
		return nil
	}
	t = new_terrain(content, error)
	if t == nil do return nil
	t.map_ = dup_string(map_)
	ok = true

	/* the legend, by byte; and the fill */
	legend = {}
	for list = tri.at(content, node, "legend"); ok && list != nil; list = tri.at(content, list, "rest") {
		item = tri.at(content, list, "first")
		if item == nil do break
		glyph = text_of(content, item, "glyph")
		kind = text_of(content, item, "terrain")
		if glyph == nil || len(glyph) != 1 {
			set_error(error, "%s: a legend's glyph is one character: \"%s\"", map_, glyph if glyph != nil else "")
			ok = false
		} else {
			legend[([^]u8)(glyph)[0]] = terrain_kind_named(t, kind)
			if legend[([^]u8)(glyph)[0]] == 0 {
				set_error(error, "%s: no terrain kind named %s, for '%s'", map_, kind if kind != nil else "", glyph)
				ok = false
			}
		}
		delete(glyph)
		delete(kind)
	}
	fill = text_of(content, node, "fill")
	if ok {
		t.fill = terrain_kind_named(t, fill if fill != nil else "open_floor")
		if t.fill == 0 {
			set_error(error, "%s: no terrain kind named %s, for its fill", map_, fill if fill != nil else "open_floor")
			ok = false
		}
	}
	delete(fill)
	if legend[' '] == 0 do legend[' '] = t.fill

	/* the levels drawn, and the extent they make */
	nlevels = 0
	wide = 0
	high = 0
	levels = 0
	for list = tri.at(content, node, "levels"); ok && list != nil; list = tri.at(content, list, "rest") {
		item = tri.at(content, list, "first")
		if item == nil do break
		if nlevels == 64 || tri.node_interval(tri.at(content, item, "z"), &lo, &hi) == 0 || lo != hi || lo < 0 || lo > 63 {
			set_error(error, "%s: a level's z is 0 to 63, one per level", map_)
			ok = false
			break
		}
		for i = 0; i < nlevels; i += 1 {
			if drawn[i].z == i32(lo) {
				set_error(error, "%s: level %d is drawn twice", map_, lo)
				ok = false
			}
		}
		drawn[nlevels].z = i32(lo)
		drawn[nlevels].rows = text_of(content, item, "rows")
		if drawn[nlevels].rows == nil do drawn[nlevels].rows = dup_string("")
		nlevels += 1
		if levels < i32(lo) + 1 do levels = i32(lo) + 1
		x = 0
		y = 0
		for s = ([^]u8)(drawn[nlevels - 1].rows); s[0] != 0; s = s[1:] {
			if s[0] == '\n' {
				y += 1
				x = 0
				continue
			}
			if s[0] != '\r' {
				x += 1
				if x > wide do wide = x
			}
		}
		if x != 0 do y += 1          /* a last row without its newline */
		if y > high do high = y
	}
	if tri.node_interval(tri.at(content, node, "width"), &lo, &hi) != 0 && lo == hi && lo > i64(wide) && lo <= 4096 {
		wide = i32(lo)
	}
	if tri.node_interval(tri.at(content, node, "height"), &lo, &hi) != 0 && lo == hi && lo > i64(high) && lo <= 4096 {
		high = i32(lo)
	}
	ncells = i64(wide) * i64(high) * i64(levels)
	if ok && (nlevels == 0 || wide == 0 || high == 0) {
		set_error(error, "%s: nothing is drawn", map_)
		ok = false
	}
	if ok && ncells > BG_MAX_TERRAIN_CELLS {
		set_error(error, "%s: too large to draw (%d cells; %d at most)", map_, ncells, BG_MAX_TERRAIN_CELLS)
		ok = false
	}

	/* the cells */
	cells = nil
	if ok {
		cells = make([^]Terrain_Kind, uint(ncells))
		for i = 0; i64(i) < ncells; i += 1 do cells[i] = t.fill
		for i = 0; ok && i < nlevels; i += 1 {
			x = 0
			y = 0
			for s = ([^]u8)(drawn[i].rows); ok && s[0] != 0; s = s[1:] {
				if s[0] == '\n' {
					y += 1
					x = 0
					continue
				}
				if s[0] == '\r' do continue
				if legend[s[0]] == 0 {
					set_error(error, "%s: level %d, row %d, column %d: '%c' is in no legend", map_, drawn[i].z,
					          y + 1, x + 1, rune(s[0]))
					ok = false
					break
				}
				cells[(uint(drawn[i].z) * uint(high) + uint(y)) * uint(wide) + uint(x)] = legend[s[0]]
				x += 1
			}
		}
	}
	for i = 0; i < nlevels; i += 1 do delete(drawn[i].rows)
	if !ok {
		free(cells)
		terrain_free(t)
		return nil
	}
	t.wide = wide
	t.high = high
	t.levels = levels
	t.drawn = cells
	return t
}

terrain_free :: proc(t: ^Terrain) {
	i: uint

	if t == nil do return
	for i = 1; t.kinds != nil && i <= t.nkinds; i += 1 {
		delete(t.kinds[i].name)
		delete(t.kinds[i].look)
	}
	free(t.kinds)
	for i = 0; i < t.cap_; i += 1 do free(t.chunks[i].cells)
	free(t.chunks)
	free(t.drawn)
	for i = 0; i < t.labelcap; i += 1 do free(t.labels[i].cells)
	free(t.labels)
	for i = 0; i < uint(t.nrooms); i += 1 do free(t.rooms[i].doors)
	free(t.rooms)
	free(t.free_)
	free(t.flood)
	if t.generated != nil {
		for &slot in t.generated.slots do free(slot.columns)
		free(t.generated)
	}
	delete(t.map_)
	free(t)
}

/* The map it came from, or NULL; its extent. */
terrain_map :: proc(t: ^Terrain) -> cstring { return t.map_ }
terrain_wide :: proc(t: ^Terrain) -> i32 { return t.wide }
terrain_high :: proc(t: ^Terrain) -> i32 { return t.high }
terrain_levels :: proc(t: ^Terrain) -> i32 { return t.levels }
/* kinds are 1 .. count */
terrain_kind_count :: proc(t: ^Terrain) -> uint { return t.nkinds }

/* NULL for 0 or none */
terrain_kind_info :: proc(t: ^Terrain, k: Terrain_Kind) -> ^Terrain_Info {
	return &t.kinds[k] if k != 0 && uint(k) <= t.nkinds else nil
}

/* nil for 0 or none */
terrain_kind_name :: proc(t: ^Terrain, k: Terrain_Kind) -> cstring {
	info := terrain_kind_info(t, k)
	return info.name if info != nil else nil
}

/* --- cells ------------------------------------------------------------------------------ */

@(private = "file")
inside :: #force_inline proc(t: ^Terrain, x: i32, y: i32, z: i32) -> bool {
	return x >= 0 && y >= 0 && z >= 0 && x < t.wide && y < t.high && z < t.levels
}

/* What the source gives a cell, whatever has changed. */
terrain_source :: proc(t: ^Terrain, x: i32, y: i32, z: i32) -> Terrain_Kind {
	if !inside(t, x, y, z) do return 0
	if t.generated != nil {
		g := t.generated
		cx, cy := x / BG_CHUNK, y / BG_CHUNK
		slot := &g.slots[uint(mix((u64(u32(cx)) << 32) ~ u64(u32(cy)))) & (BG_GENERATED_SLOTS - 1)]
		if slot.columns == nil || slot.cx != cx || slot.cy != cy {
			if slot.columns == nil do slot.columns = new([BG_CHUNK * BG_CHUNK]orogen.Column)
			slot.cx, slot.cy = cx, cy
			orogen.columns(g.plan, cx * BG_CHUNK, cy * BG_CHUNK, BG_CHUNK, BG_CHUNK, slot.columns[:])
		}
		return g.kinds[orogen.cell_of(g.plan, slot.columns[(y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK], z)]
	}
	if t.drawn == nil do return t.fill
	return t.drawn[(uint(z) * uint(t.high) + uint(y)) * uint(t.wide) + uint(x)]
}

@(private = "file")
slot_of :: proc(cx: i32, cy: i32, z: i32, cap_: uint) -> uint {
	return uint(mix((u64(u32(cx)) << 32) ~ (u64(u32(cy)) << 8) ~ u64(z))) & (cap_ - 1)
}

@(private = "file")
chunk_find :: proc(t: ^Terrain, cx: i32, cy: i32, z: i32) -> ^Chunk {
	i: uint
	c: ^Chunk

	if t.nchunks == 0 do return nil
	for i = slot_of(cx, cy, z, t.cap_);; i = (i + 1) & (t.cap_ - 1) {
		c = &t.chunks[i]
		if c.cells == nil do return nil
		if c.cx == cx && c.cy == cy && c.z == z do return c
	}
}

/* The kind of a cell: 0 outside the extent. */
terrain_at :: proc(t: ^Terrain, x: i32, y: i32, z: i32) -> Terrain_Kind {
	c: ^Chunk

	if !inside(t, x, y, z) do return 0
	if t.nchunks != 0 {
		c = chunk_find(t, x / BG_CHUNK, y / BG_CHUNK, z)
		if c != nil do return c.cells[(y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK]
	}
	return terrain_source(t, x, y, z)
}

/* A kind's properties at a cell: outside the extent, solid and opaque, and
 * no floor. */
terrain_solid :: proc(t: ^Terrain, x: i32, y: i32, z: i32) -> bool {
	k: Terrain_Kind

	k = terrain_at(t, x, y, z)
	return k == 0 || t.kinds[k].solid
}

terrain_opaque :: proc(t: ^Terrain, x: i32, y: i32, z: i32) -> bool {
	k: Terrain_Kind

	k = terrain_at(t, x, y, z)
	return k == 0 || t.kinds[k].opaque
}

terrain_floored :: proc(t: ^Terrain, x: i32, y: i32, z: i32) -> bool {
	k: Terrain_Kind

	k = terrain_at(t, x, y, z)
	return k != 0 && t.kinds[k].floored
}

/* A chunk's cells (BG_CHUNK * BG_CHUNK, row by row; cells past the extent 0). */
terrain_chunk_cells :: proc(t: ^Terrain, x0: i32, y0: i32, z: i32, cells: [^]Terrain_Kind) {
	x: i32
	y: i32

	for y = 0; y < BG_CHUNK; y += 1 {
		for x = 0; x < BG_CHUNK; x += 1 do cells[y * BG_CHUNK + x] = terrain_at(t, x0 + x, y0 + y, z)
	}
}

@(private = "file")
grow :: proc(t: ^Terrain) {
	old: [^]Chunk
	oldcap: uint
	i: uint
	j: uint

	old = t.chunks
	oldcap = t.cap_
	t.cap_ = oldcap * 2 if oldcap != 0 else 16
	t.chunks = make([^]Chunk, t.cap_)
	for i = 0; i < oldcap; i += 1 {
		if old[i].cells != nil {
			for j = slot_of(old[i].cx, old[i].cy, old[i].z, t.cap_); t.chunks[j].cells != nil; j = (j + 1) & (t.cap_ - 1) {
			}
			t.chunks[j] = old[i]
		}
	}
	free(old)
}

/* Sets a cell, storing its chunk if it wasn't; the kind it was, or 0 if the
 * cell is outside the extent or the kind is none. */
terrain_set :: proc(t: ^Terrain, x: i32, y: i32, z: i32, k: Terrain_Kind) -> Terrain_Kind {
	c: ^Chunk
	was: Terrain_Kind
	i: uint
	cx: i32
	cy: i32

	if !inside(t, x, y, z) || k == 0 || uint(k) > t.nkinds do return 0
	cx = x / BG_CHUNK
	cy = y / BG_CHUNK
	c = chunk_find(t, cx, cy, z)
	if c == nil {
		cells: [^]Terrain_Kind
		u: i32
		v: i32

		cells = make([^]Terrain_Kind, BG_CHUNK * BG_CHUNK)       /* as the source has it */
		for v = 0; v < BG_CHUNK; v += 1 {
			for u = 0; u < BG_CHUNK; u += 1 do cells[v * BG_CHUNK + u] = terrain_source(t, cx * BG_CHUNK + u, cy * BG_CHUNK + v, z)
		}
		if (t.nchunks + 1) * 2 > t.cap_ do grow(t)
		for i = slot_of(cx, cy, z, t.cap_); t.chunks[i].cells != nil; i = (i + 1) & (t.cap_ - 1) {
		}
		c = &t.chunks[i]
		c.cx = cx
		c.cy = cy
		c.z = z
		c.cells = cells
		t.nchunks += 1
	}
	was = c.cells[(y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK]
	c.cells[(y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK] = k
	if was != 0 && (t.kinds[was].solid != t.kinds[k].solid || t.kinds[was].divides != t.kinds[k].divides) {
		rooms_changed(t, x, y, z, !t.kinds[was].solid && !t.kinds[was].divides)
	}
	return was
}

// cmp_corner < 0: level, row, column. Corners are distinct chunks: no ties.
@(private = "file")
corner_before :: proc(p: [3]i32, q: [3]i32) -> bool {
	k: i32

	for k = 2; k >= 0; k -= 1 {
		if p[k] != q[k] do return p[k] < q[k]
	}
	return false
}

/* Whether a stored chunk differs from its source. */
@(private = "file")
differs :: proc(t: ^Terrain, c: ^Chunk) -> bool {
	x: i32
	y: i32

	for y = 0; y < BG_CHUNK; y += 1 {
		for x = 0; x < BG_CHUNK; x += 1 {
			if c.cells[y * BG_CHUNK + x] != terrain_source(t, c.cx * BG_CHUNK + x, c.cy * BG_CHUNK + y, c.z) do return true
		}
	}
	return false
}

/* The chunks that differ from the source, for saving: each one's corner,
 * and its cells (terrain_chunk_cells). Returns how many; fills up to max
 * (corners may be nil). */
terrain_changed :: proc(t: ^Terrain, corners: [^][3]i32, max_: uint) -> uint {
	all: [^][3]i32
	n: uint
	i: uint

	all = make([^][3]i32, t.nchunks if t.nchunks != 0 else 1)
	n = 0
	for i = 0; i < t.cap_; i += 1 {
		if t.chunks[i].cells != nil && differs(t, &t.chunks[i]) {
			all[n][0] = t.chunks[i].cx * BG_CHUNK
			all[n][1] = t.chunks[i].cy * BG_CHUNK
			all[n][2] = t.chunks[i].z
			n += 1
		}
	}
	slice.sort_by(all[:n], corner_before)      /* level, row, column: the same every time */
	if corners != nil do mem.copy(corners, all, int((n if n < max_ else max_) * size_of([3]i32)))
	free(all)
	return n
}

/* A hash of the terrain: its source and what has changed. */
terrain_hash :: proc(t: ^Terrain) -> u64 {
	cells: [BG_CHUNK * BG_CHUNK]Terrain_Kind
	corners: [^][3]i32
	h: u64
	n: uint
	i: uint
	k: uint

	h = mix_string(0x7465727261696e, t.map_ if t.map_ != nil else "")
	/* kinds by name: content renumbers them */
	h = mix(h ~ u64(t.wide) ~ (u64(t.high) << 20) ~ (u64(t.levels) << 40))
	h = mix_string(h, terrain_kind_name(t, t.fill))
	if t.generated != nil {      /* what makes the ground: the generator, and all that shapes it */
		p := t.generated.plan
		h = mix(h ~ u64(orogen.VERSION))
		h = mix(h ~ p.seed)
		for v in ([]i32{i32(p.wraps), p.lowest, p.sea, p.highest, p.span, p.octaves, p.roughness, p.soil, p.bare}) {
			h = mix(h ~ u64(u32(v)))
		}
		for c in orogen.Class do if c != .None do h = mix_string(h, terrain_kind_name(t, t.generated.kinds[c]))
	}
	n = terrain_changed(t, nil, 0)
	if n == 0 do return h
	corners = make([^][3]i32, n)
	terrain_changed(t, corners, n)
	for i = 0; i < n; i += 1 {
		terrain_chunk_cells(t, corners[i][0], corners[i][1], corners[i][2], &cells[0])
		h = mix(h ~ u64(corners[i][0]) ~ (u64(corners[i][1]) << 21) ~ (u64(corners[i][2]) << 42))
		for k = 0; k < BG_CHUNK * BG_CHUNK; k += 1 {
			if cells[k] != terrain_source(t, corners[i][0] + i32(k % BG_CHUNK), corners[i][1] + i32(k / BG_CHUNK),
			                              corners[i][2]) {
				h = mix_string(mix(h ~ u64(k)), terrain_kind_name(t, cells[k]))
			}
		}
	}
	free(corners)
	return h
}

/* --- rooms (TERRAIN.md step 3) ------------------------------------------------------ */

/* Rooms are found from a cell out, when first asked, and labelled per chunk:
 * nothing is kept for ground no one has asked of, and nothing is ever found
 * over the whole world. A flood stops at the world's edge, or past
 * BG_ROOM_MAX cells, or on meeting ground already known to be open: the
 * cells it reached are open. A change lets go of the rooms beside it, which
 * are found again when next asked; a wall that parts open ground floods each
 * side, as far as BG_ROOM_MAX, for one it has enclosed. */

@(private = "file")
dx := [4]i32{1, -1, 0, 0}
@(private = "file")
dy := [4]i32{0, 0, 1, -1}

/* Whether a cell is roomy: neither solid nor dividing, so part of a room or
 * of open ground. */
terrain_roomy :: proc(t: ^Terrain, x: i32, y: i32, z: i32) -> bool {
	k: Terrain_Kind

	k = terrain_at(t, x, y, z)
	return k != 0 && !t.kinds[k].solid && !t.kinds[k].divides
}

@(private = "file")
labels_find :: proc(t: ^Terrain, cx: i32, cy: i32, z: i32) -> ^Labels {
	i: uint
	l: ^Labels

	if t.nlabels == 0 do return nil
	for i = slot_of(cx, cy, z, t.labelcap);; i = (i + 1) & (t.labelcap - 1) {
		l = &t.labels[i]
		if l.cells == nil do return nil
		if l.cx == cx && l.cy == cy && l.z == z do return l
	}
}

@(private = "file")
labels_grow :: proc(t: ^Terrain) {
	old: [^]Labels
	oldcap: uint
	i: uint
	j: uint

	old = t.labels
	oldcap = t.labelcap
	t.labelcap = oldcap * 2 if oldcap != 0 else 16
	t.labels = make([^]Labels, t.labelcap)
	for i = 0; i < oldcap; i += 1 {
		if old[i].cells != nil {
			for j = slot_of(old[i].cx, old[i].cy, old[i].z, t.labelcap); t.labels[j].cells != nil;
			    j = (j + 1) & (t.labelcap - 1) {
			}
			t.labels[j] = old[i]
		}
	}
	free(old)
}

/* A cell's label (inside the extent): 0 if none is kept. */
@(private = "file")
label_at :: proc(t: ^Terrain, x: i32, y: i32, z: i32) -> u32 {
	l: ^Labels

	l = labels_find(t, x / BG_CHUNK, y / BG_CHUNK, z)
	return l.cells[(y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK] if l != nil else 0
}

@(private = "file")
label_set :: proc(t: ^Terrain, x: i32, y: i32, z: i32, label: u32) {
	l: ^Labels
	i: uint
	cx: i32
	cy: i32

	cx = x / BG_CHUNK
	cy = y / BG_CHUNK
	l = labels_find(t, cx, cy, z)
	if l == nil {
		if label == 0 do return
		if (t.nlabels + 1) * 2 > t.labelcap do labels_grow(t)
		for i = slot_of(cx, cy, z, t.labelcap); t.labels[i].cells != nil; i = (i + 1) & (t.labelcap - 1) {
		}
		l = &t.labels[i]
		l.cx = cx
		l.cy = cy
		l.z = z
		l.cells = make([^]u32, BG_CHUNK * BG_CHUNK)
		t.nlabels += 1
	}
	l.cells[(y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK] = label
}

@(private = "file")
room_new :: proc(t: ^Terrain) -> u32 {
	n: u32

	if t.nfree != 0 {
		t.nfree -= 1
		n = t.free_[t.nfree]
	} else {
		if t.nrooms == t.roomcap {
			old := uint(t.roomcap)
			t.roomcap = t.roomcap * 2 if t.roomcap != 0 else 16
			t.rooms = ([^]Room)(realloc(t.rooms, old * size_of(Room), uint(t.roomcap) * size_of(Room)))
			t.free_ = ([^]u32)(realloc(t.free_, old * size_of(u32), uint(t.roomcap) * size_of(u32)))
		}
		t.nrooms += 1
		n = t.nrooms
	}
	t.rooms[n - 1] = {}
	return n
}

@(private = "file")
room_of :: proc(t: ^Terrain, n: u32) -> ^Room {
	return &t.rooms[n - 1] if n != 0 && n <= t.nrooms && t.rooms[n - 1].size != 0 else nil
}

@(private = "file")
add_door :: proc(room: ^Room, x: i32, y: i32, z: i32, cap_: ^u32) {
	i: u32

	for i = 0; i < room.ndoors; i += 1 {
		if room.doors[i][0] == x && room.doors[i][1] == y do return
	}
	if room.ndoors == cap_^ {
		old := uint(cap_^)
		cap_^ = cap_^ * 2 if cap_^ != 0 else 4
		room.doors = ([^][3]i32)(realloc(room.doors, old * size_of([3]i32), uint(cap_^) * size_of([3]i32)))
	}
	room.doors[room.ndoors][0] = x
	room.doors[room.ndoors][1] = y
	room.doors[room.ndoors][2] = z
	room.ndoors += 1
}

// cmp_door < 0: by y, then x. A room's doorways are distinct cells: no ties.
@(private = "file")
door_before :: proc(p: [3]i32, q: [3]i32) -> bool {
	if p[1] != q[1] do return p[1] < q[1]
	return p[0] < q[0]
}

/* Floods the roomy cells joined side by side to (x, y, z), marking them
 * visiting, into t->flood with their labels before: returns how many. *open
 * when it met the world's edge, more than BG_ROOM_MAX cells, or, unless
 * `throughOpen`, ground known to be open; it stops there. The doorways at
 * its side go to `room`, if given. */
@(private = "file")
flood :: proc(t: ^Terrain, x: i32, y: i32, z: i32, throughOpen: bool, open: ^bool, room: ^Room) -> u32 {
	k: Terrain_Kind
	n: u32
	head: u32
	label: u32
	cap_: u32
	u: i32
	v: i32
	d: i32

	if t.flood == nil do t.flood = make([^]Flood_Cell, BG_ROOM_MAX + 1)
	open^ = false
	cap_ = 0
	t.flood[0].x = x
	t.flood[0].y = y
	t.flood[0].was = label_at(t, x, y, z)
	n = 1
	label_set(t, x, y, z, BG_VISITING)
	for head = 0; head < n && !open^; head += 1 {
		for d = 0; d < 4; d += 1 {
			u = t.flood[head].x + dx[d]
			v = t.flood[head].y + dy[d]
			if !inside(t, u, v, z) {
				open^ = true
				break
			}
			k = terrain_at(t, u, v, z)
			if t.kinds[k].solid do continue
			if t.kinds[k].divides {
				if room != nil do add_door(room, u, v, z, &cap_)
				continue
			}
			label = label_at(t, u, v, z)
			if label == BG_VISITING do continue
			if (label == BG_OPEN && !throughOpen) || n == BG_ROOM_MAX {
				open^ = true
				break
			}
			t.flood[n].x = u
			t.flood[n].y = v
			t.flood[n].was = label
			n += 1
			label_set(t, u, v, z, BG_VISITING)
		}
	}
	return n
}

/* The room of a roomy cell not yet labelled, or BG_OPEN: found, and every
 * cell reached labelled so. */
@(private = "file")
find_room :: proc(t: ^Terrain, x: i32, y: i32, z: i32) -> u32 {
	room: Room
	label: u32
	n: u32
	i: u32
	open: bool

	room = {}
	n = flood(t, x, y, z, false, &open, &room)
	if open {
		free(room.doors)
		label = BG_OPEN
	} else {
		label = room_new(t)
		room.size = n
		room.x = t.flood[0].x
		room.y = t.flood[0].y
		room.z = z
		for i = 1; i < n; i += 1 {
			if t.flood[i].y < room.y || (t.flood[i].y == room.y && t.flood[i].x < room.x) {
				room.x = t.flood[i].x
				room.y = t.flood[i].y
			}
		}
		if room.ndoors > 1 do slice.sort_by(room.doors[:room.ndoors], door_before)
		t.rooms[label - 1] = room
	}
	for i = 0; i < n; i += 1 do label_set(t, t.flood[i].x, t.flood[i].y, z, label)
	return label
}

/* Lets a room go: its cells' labels, from one of them, and its number. */
@(private = "file")
drop_room :: proc(t: ^Terrain, n: u32, x: i32, y: i32, z: i32) {
	x := x
	y := y
	top: u32
	u: i32
	v: i32
	d: i32

	if t.flood == nil do t.flood = make([^]Flood_Cell, BG_ROOM_MAX + 1)
	label_set(t, x, y, z, 0)
	t.flood[0].x = x
	t.flood[0].y = y
	top = 1
	for top != 0 {
		top -= 1
		x = t.flood[top].x
		y = t.flood[top].y
		for d = 0; d < 4; d += 1 {
			u = x + dx[d]
			v = y + dy[d]
			if inside(t, u, v, z) && label_at(t, u, v, z) == n && top <= BG_ROOM_MAX {
				label_set(t, u, v, z, 0)
				t.flood[top].x = u
				t.flood[top].y = v
				top += 1
			}
		}
	}
	if room_of(t, n) != nil {
		free(t.rooms[n - 1].doors)
		t.rooms[n - 1] = {}
		t.free_[t.nfree] = n
		t.nfree += 1
	}
	t.dropped += 1
}

/* A cell's kind changed whether it is solid or divides: the rooms beside it
 * are let go; and where it parted open ground, a side it enclosed is
 * forgotten as open, to be found a room. */
@(private = "file")
rooms_changed :: proc(t: ^Terrain, x: i32, y: i32, z: i32, wasRoomy: bool) {
	label: u32
	n: u32
	i: u32
	u: i32
	v: i32
	d: i32
	open: bool

	if t.nlabels == 0 do return
	for d = -1; d < 4; d += 1 {
		if d < 0 {
			u = x
			v = y
		} else {
			u = x + dx[d]
			v = y + dy[d]
		}
		if !inside(t, u, v, z) do continue
		label = label_at(t, u, v, z)
		if label != 0 && label != BG_OPEN && label != BG_VISITING do drop_room(t, label, u, v, z)
	}
	label_set(t, x, y, z, 0)
	if !wasRoomy || terrain_roomy(t, x, y, z) do return
	for d = 0; d < 4; d += 1 {
		u = x + dx[d]
		v = y + dy[d]
		if !inside(t, u, v, z) || label_at(t, u, v, z) != BG_OPEN do continue
		n = flood(t, u, v, z, true, &open, nil)
		for i = 0; i < n; i += 1 do label_set(t, t.flood[i].x, t.flood[i].y, z, t.flood[i].was if open else 0)
	}
}

/* Rooms (TERRAIN.md step 3): a cell's room, the roomy cells of its level
 * joined side by side, when they are enclosed: no more than BG_ROOM_MAX of
 * them, none at the world's edge. 0 for a cell in none: a wall, a doorway,
 * open ground, outside the extent. A room is found from the cell asked out,
 * when first asked, and kept; a change finds again only the rooms beside it.
 * A number means nothing across a change. */
terrain_room_at :: proc(t: ^Terrain, x: i32, y: i32, z: i32) -> u32 {
	label: u32

	if !inside(t, x, y, z) || !terrain_roomy(t, x, y, z) do return 0
	label = label_at(t, x, y, z)
	if label == 0 do label = find_room(t, x, y, z)
	return 0 if label == BG_OPEN else label
}

/* A room's size in cells, and its first cell (the least y, then x); 0 and
 * nothing for no room. */
terrain_room_size :: proc(t: ^Terrain, room: u32) -> u32 {
	r: ^Room

	r = room_of(t, room)
	return r.size if r != nil else 0
}

terrain_room_corner :: proc(t: ^Terrain, room: u32, x: ^i32, y: ^i32, z: ^i32) -> bool {
	r: ^Room

	r = room_of(t, room)
	if r == nil do return false
	x^ = r.x
	y^ = r.y
	z^ = r.z
	return true
}

/* The doorways at a room's side, in the order found; returns how many, and
 * fills up to max. */
terrain_room_doorways :: proc(t: ^Terrain, room: u32, cells: [^][3]i32, max_: uint) -> uint {
	r: ^Room
	i: uint

	r = room_of(t, room)
	if r == nil do return 0
	for i = 0; i < uint(r.ndoors) && i < max_; i += 1 {
		cells[i][0] = r.doors[i][0]
		cells[i][1] = r.doors[i][1]
		cells[i][2] = r.doors[i][2]
	}
	return uint(r.ndoors)
}

/* Counts rooms let go, after changes: what is cached by room number is good
 * while this is as it was. */
terrain_rooms_dropped :: proc(t: ^Terrain) -> u64 {
	return t.dropped
}

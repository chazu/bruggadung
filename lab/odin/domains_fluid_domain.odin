package lab

// BGFluidDomain — water flowing out of stores through open taps
// (DOMAIN_SIMULATION.md §3–9, Scenario 3). While any open tap can draw, the
// domain forms a structure: it checks out the water of the stores it draws
// from and delivers into (buckets, and the tiles water spills onto), and its
// values are authoritative until it checks them back in.
//
// Flows are a tap's rate, in whole millilitres; the fraction of a millilitre
// is a carry on the tap, never stock. When a store can't meet the step's
// requests, it is shared pro rata, and the millilitres left over go one each
// in tap-ID order, rotated by the boundary index. The horizon's next event is
// the first step at which a store runs dry, so the scheduler puts a boundary
// exactly there, and every tap on that store reports "exhausted" in it.
//
// While a store is checked out, its record mirrors the domain's value after
// each step, for readers; commitment still refuses to change it, and the
// conservation sum counts it once, through the domain.
//
// The floor around wet tiles (and below every tap) is part of the structure:
// water spreads across it (BG_SPREAD_TAU), and when nothing flows or spreads
// the whole region sleeps: everything is checked in and the horizon is
// infinite.
//
// Watches are activities' (DOMAIN_SIMULATION.md §5, ACTIONS.md §5): a running
// activity with a watchHolder is told, by a "watched" event, in the step its
// holder's water reaches watchAtLeast; that step is part of the horizon too.
//
// (domains/BGFluidDomain.h and .m)

import "core:fmt"
import "core:mem"
import "core:slice"
import tri "../../triangle/odin/triangle"


BG_FLUID_MAX :: 64

// Water on the floor spreads between adjacent tiles: across each pair, in a
// step of dt, (difference × dt) / (8 τ) whole millilitres, from step-start
// values; the safe step is τ, so no pair moves more than an eighth of its
// difference and the scheme stays stable. A fraction of a millilitre doesn't
// move, so a puddle settles once neighbours differ by less than 8 mL.
BG_SPREAD_TAU :: 10000         // ms

Fluid_Holder :: struct {
	entity: Entity_ID,      // a WaterStore; NO_ENTITY for a tile
	x:      i32,
	y:      i32,
	level:  i32,
	water:  i64,
}

Fluid_Outlet :: struct {
	tap:         Entity_ID,
	source:      i32,       // holder indices
	destination: i32,
	rate:        i64,       // mL per minute
	carry:       i64,       // in 1/60000 mL
	exhausted:   bool,
}


Fluid_Domain :: struct {
	using object: Object,
	world:        ^World,
	active:       bool,
	reversed:     bool,
	signature:    u64,
	holders:      [^]Fluid_Holder,     // stores and tiles, as many as the structure takes
	nholders:     i32,
	holdercap:    i32,
	firstTile:    i32,                 // holders before it: the outlets'
	outlets:      [BG_FLUID_MAX]Fluid_Outlet,
	noutlets:     i32,
	log:          [dynamic]string,     // each cloned, freed in dealloc
	predicted:    Time,

	// watches that have fired, until their activities stop watching
	fired:        [BG_FLUID_MAX]Entity_ID,
	nfired:       i32,

	// carries of open taps, kept across check-in and forming again
	carryTaps:    [BG_FLUID_MAX]Entity_ID,
	carries:      [BG_FLUID_MAX]i64,
	ncarries:     i32,
}


@(private = "file")
BG_MS_PER_MINUTE :: 60000


// An open tap as the world has it now: what forming a structure would use.
@(private = "file")
Tap_View :: struct {
	tap:         Entity_ID,
	source:      Entity_ID,
	destination: Entity_ID,     // NO_ENTITY: the tile below
	x:           i32,
	y:           i32,
	level:       i32,
	rate:        i64,
}


@(private = "file")
ground_tile :: proc(world: ^World, e: Entity_ID, tile: ^Location) -> bool {
	loc:   Location
	guard: uint
	e     := e

	for guard = 0; guard < 64; guard += 1 {
		loc = world_location_of(world, e)
		if loc.form == .On_Tile {
			tile^ = loc
			return true
		}
		if loc.form == .None || loc.place == 0 {
			return false
		}
		e = loc.place
	}
	return false
}


fluid_domain_init_with_world :: proc(world: ^World) -> ^Fluid_Domain {
	self := object_new(Fluid_Domain, fluid_domain_dealloc)
	self.world     = retain(world)
	self.log       = make([dynamic]string)
	self.predicted = TIME_NEVER
	return self
}


fluid_domain_dealloc :: proc(self: ^Fluid_Domain) {
	free(self.holders)
	release(self.world)
	for line in self.log {
		delete(line)
	}
	delete(self.log)
}


fluid_domain_name :: proc(self: ^Fluid_Domain) -> string {
	return "fluid"
}


fluid_domain_is_active :: proc(self: ^Fluid_Domain) -> bool {
	return true        // it decides at each horizon whether it has anything to do
}


// Variant 3d: the same participants, held in the reverse order inside.
fluid_domain_set_reversed_order :: proc(self: ^Fluid_Domain, flag: bool) {
	self.reversed = flag
}


// Requested and granted amounts per tap per step, for the developer.
// Settled: the log as it is now (NAMES.md's guess: []T).
fluid_domain_log :: proc(self: ^Fluid_Domain) -> []string {
	return self.log[:]
}


// The exhaustion it last predicted, as a time.
fluid_domain_predicted_exhaustion :: proc(self: ^Fluid_Domain) -> Time {
	return self.predicted
}


// --- participants --------------------------------------------------------------

// The open taps, in ID order, with where each draws from and delivers to.
@(private = "file")
fluid_domain_scan :: proc(self: ^Fluid_Domain, views: [^]Tap_View) -> i32 {
	tap:    ^Tap
	taps:   ^Store
	inside: [4]Entity_ID
	at:     Location
	tile:   Location
	kstore: uint
	i:      uint
	j:      uint
	m:      uint
	n:      i32

	taps   = world_store_for_kind(self.world, world_kind_named(self.world, "Tap"))
	kstore = world_kind_named(self.world, "WaterStore")
	n      = 0
	for i = 0; i < store_count(taps) && n < BG_FLUID_MAX; i += 1 {
		tap = (^Tap)(store_record_at_index(taps, i))
		if !tap.open {
			continue
		}
		views[n].tap = store_entity_at_index(taps, i)
		at           = world_location_of(self.world, views[n].tap)
		// a tap draws from the store it is installed in
		if at.form != .Part_Of || world_record(self.world, kstore, at.place) == nil {
			continue
		}
		views[n].source      = at.place
		views[n].rate        = tap.rate
		views[n].destination = NO_ENTITY
		// into what sits in it, or onto the tile below
		m = world_entities_at(self.world, views[n].tap, .In, &inside[0], 4)
		for j = 0; j < m && j < 4; j += 1 {
			if world_record(self.world, kstore, inside[j]) != nil {
				views[n].destination = inside[j]
				break
			}
		}
		if views[n].destination == 0 {
			if !ground_tile(self.world, views[n].tap, &tile) {
				continue
			}
			views[n].x     = tile.x
			views[n].y     = tile.y
			views[n].level = tile.level
		}
		n += 1
	}
	return n
}


@(private = "file")
cmp_floor :: proc(p: [3]i32, q: [3]i32) -> int {
	k: int

	for k = 2; k >= 0; k -= 1 {
		if p[k] != q[k] {
			return -1 if p[k] < q[k] else 1
		}
	}
	return 0
}


// Whether water can lie on a tile: one of the map, not solid.
@(private = "file")
fluid_domain_floor_x :: proc(self: ^Fluid_Domain, x: i32, y: i32, level: i32) -> bool {
	return world_is_tile_x(self.world, x, y, level) &&
	       !(world_terrain(self.world) != nil && terrain_solid(world_terrain(self.world), x, y, level))
}


// The floor the domain works on: wet tiles and their neighbours (not
// walls), and the tiles below the taps, in (level, y, x) order; read from
// what is wet, not the map.
@(private = "file")
fluid_domain_region :: proc(self: ^Fluid_Domain, result: ^[^][3]i32, views: [^]Tap_View, nviews: i32) -> i32 {
	@(static, rodata) dx := [5]i32{0, 1, -1, 0, 0}
	@(static, rodata) dy := [5]i32{0, 0, 0, 1, -1}
	tiles: [^][3]i32
	wet:   [^][3]i32
	all:   [^][3]i32
	nwet:  uint
	nall:  uint
	i:     uint
	d:     int
	n:     i32

	nwet = world_wet_tiles(self.world, nil, 0)
	wet  = make([^][3]i32, nwet if nwet != 0 else 1)
	world_wet_tiles(self.world, wet, nwet)
	all  = make([^][3]i32, nwet * 5 + uint(nviews) + 1)
	nall = 0
	for i = 0; i < nwet; i += 1 {
		for d = 0; d < 5; d += 1 {
			if fluid_domain_floor_x(self, wet[i][0] + dx[d], wet[i][1] + dy[d], wet[i][2]) {
				all[nall][0] = wet[i][0] + dx[d]
				all[nall][1] = wet[i][1] + dy[d]
				all[nall][2] = wet[i][2]
				nall += 1
			}
		}
	}
	for i = 0; i < uint(nviews); i += 1 {
		if views[i].destination == 0 && world_is_tile_x(self.world, views[i].x, views[i].y, views[i].level) {
			all[nall][0] = views[i].x
			all[nall][1] = views[i].y
			all[nall][2] = views[i].level
			nall += 1
		}
	}
	// qsort: equal entries are the same tile, so the order is total
	slice.sort_by(all[:nall], proc(a, b: [3]i32) -> bool {return cmp_floor(a, b) < 0})
	tiles = make([^][3]i32, nall if nall != 0 else 1)
	n     = 0
	for i = 0; i < nall; i += 1 {
		if i == 0 || cmp_floor(all[i], all[i - 1]) != 0 {
			tiles[n][0] = all[i][0]
			tiles[n][1] = all[i][1]
			tiles[n][2] = all[i][2]
			n += 1
		}
	}
	free(all)
	free(wet)
	result^ = tiles
	return n
}


@(private = "file")
signature :: proc(views: [^]Tap_View, n: i32, tiles: [^][3]i32, ntiles: i32) -> u64 {
	h: u64
	i: i32

	h = mix(u64(n) ~ (u64(ntiles) << 32))
	for i = 0; i < ntiles; i += 1 {
		h = mix(h ~ u64(u32(tiles[i][0])) ~ (u64(u32(tiles[i][1])) << 16))
	}
	for i = 0; i < n; i += 1 {
		h = mix(h ~ views[i].tap ~ (views[i].source << 20) ~ (views[i].destination << 40))
		h = mix(h ~ u64(views[i].rate) ~ (u64(u32(views[i].x)) << 24) ~
		        (u64(u32(views[i].y)) << 44))
	}
	return h
}


// --- the structure -------------------------------------------------------------

@(private = "file")
fluid_domain_holder_for :: proc(self: ^Fluid_Domain, entity: Entity_ID, x: i32, y: i32, level: i32) -> i32 {
	i:     i32
	water: i64

	// a tile of the region, after the outlets': only the outlets' to look
	// through, for a tap's tile; the region has each tile once
	for i = 0; i < (self.nholders if entity != 0 || self.firstTile < 0 else self.firstTile); i += 1 {
		same: bool
		if entity != 0 {
			same = self.holders[i].entity == entity
		} else {
			same = self.holders[i].entity == 0 && self.holders[i].x == x && self.holders[i].y == y && self.holders[i].level == level
		}
		if same {
			return i
		}
	}
	if self.nholders == self.holdercap {
		old := self.holdercap
		self.holdercap = self.holdercap * 2 if self.holdercap != 0 else 64
		q, _ := mem.resize(rawptr(self.holders), int(old) * size_of(Fluid_Holder), int(self.holdercap) * size_of(Fluid_Holder))
		self.holders = ([^]Fluid_Holder)(q)
	}
	if entity != 0 {
		world_get_field(self.world, "WaterStore.water", entity, &water)
		world_set_checked_out(self.world, true, entity)
	} else {
		water = world_water_at_x(self.world, x, y, level)
		world_set_tile_checked_out(self.world, true, x, y, level)
	}
	self.holders[self.nholders].entity = entity
	self.holders[self.nholders].x      = x
	self.holders[self.nholders].y      = y
	self.holders[self.nholders].level  = level
	self.holders[self.nholders].water  = water
	self.nholders += 1
	return self.nholders - 1
}


// Checks out the stores the open taps join, and starts flowing.
@(private = "file")
fluid_domain_form_from :: proc(self: ^Fluid_Domain, views: [^]Tap_View, n: i32, tiles: [^][3]i32, ntiles: i32) {
	o: ^Fluid_Outlet
	i: i32
	k: i32
	m: i32

	self.nholders  = 0
	self.noutlets  = 0
	self.firstTile = -1
	for k = 0; k < n; k += 1 {
		i       = n - 1 - k if self.reversed else k
		o       = &self.outlets[self.noutlets]
		o.tap   = views[i].tap
		o.rate  = views[i].rate
		o.carry = 0
		for m = 0; m < self.ncarries; m += 1 {
			if self.carryTaps[m] == o.tap {
				o.carry = self.carries[m]
			}
		}
		o.source      = fluid_domain_holder_for(self, views[i].source, 0, 0, 0)
		o.destination = fluid_domain_holder_for(self, views[i].destination, views[i].x, views[i].y, views[i].level)
		if o.source < 0 || o.destination < 0 {
			continue
		}
		o.exhausted = self.holders[o.source].water == 0
		self.noutlets += 1
	}
	self.firstTile = self.nholders
	for k = 0; k < ntiles; k += 1 {
		i = ntiles - 1 - k if self.reversed else k
		fluid_domain_holder_for(self, NO_ENTITY, tiles[i][0], tiles[i][1], tiles[i][2])
	}
	self.firstTile = -1
	self.active    = true
}


// The tile holders, by (level, y, x), to find a tile's neighbours.
@(private = "file")
Floor_Tile :: struct {
	x:      i32,
	y:      i32,
	level:  i32,
	holder: i32,
}

@(private = "file")
cmp_floor_tile :: proc(p: ^Floor_Tile, q: ^Floor_Tile) -> int {
	if p.level != q.level {
		return -1 if p.level < q.level else 1
	}
	if p.y != q.y {
		return -1 if p.y < q.y else 1
	}
	return -1 if p.x < q.x else int(p.x > q.x)
}


@(private = "file")
fluid_domain_tile_index :: proc(self: ^Fluid_Domain, at: [^]Floor_Tile) -> i32 {
	i: i32
	n: i32

	n = 0
	for i = 0; i < self.nholders; i += 1 {
		if self.holders[i].entity == 0 {
			at[n].x      = self.holders[i].x
			at[n].y      = self.holders[i].y
			at[n].level  = self.holders[i].level
			at[n].holder = i
			n += 1
		}
	}
	// qsort: each tile is once, so the order is total
	slice.sort_by(at[:n], proc(a, b: Floor_Tile) -> bool {
		a, b := a, b
		return cmp_floor_tile(&a, &b) < 0
	})
	return n
}


// The holder of the tile east (d 0) or south (d 1) of one, or -1.
@(private = "file")
neighbour :: proc(at: [^]Floor_Tile, n: i32, t: ^Floor_Tile, d: i32) -> i32 {
	key:   Floor_Tile
	found: ^Floor_Tile
	lo:    i32
	hi:    i32

	key    = t^
	key.x += 0 if d != 0 else 1
	key.y += 1 if d != 0 else 0
	// bsearch: the tiles are each once, so any match is the match
	found = nil
	lo    = 0
	hi    = n
	for lo < hi {
		mid := lo + (hi - lo) / 2
		c := cmp_floor_tile(&key, &at[mid])
		if c == 0 {
			found = &at[mid]
			break
		}
		if c < 0 {
			hi = mid
		} else {
			lo = mid + 1
		}
	}
	return found.holder if found != nil else -1
}


// Whether some pair of adjacent tiles differs by enough to move water.
@(private = "file")
fluid_domain_spreading :: proc(self: ^Fluid_Domain) -> bool {
	at:    [^]Floor_Tile
	diff:  i64
	moves: bool
	n:     i32
	k:     i32
	i:     i32
	j:     i32
	d:     i32

	at    = make([^]Floor_Tile, int(self.nholders if self.nholders != 0 else 1))
	n     = fluid_domain_tile_index(self, at)
	moves = false
	for k = 0; k < n && !moves; k += 1 {
		for d = 0; d < 2; d += 1 {
			i = at[k].holder
			j = neighbour(at, n, &at[k], d)
			if j >= 0 {
				diff = self.holders[i].water - self.holders[j].water
				if diff >= 8 || diff <= -8 {
					moves = true
				}
			}
		}
	}
	free(at)
	return moves
}


// The water it has checked out (0 at rest): the conservation identity's
// "Σ structures" term.
fluid_domain_checked_out_water :: proc(self: ^Fluid_Domain) -> i64 {
	sum: i64
	i:   i32

	if !self.active {
		return 0
	}
	sum = 0
	for i = 0; i < self.nholders; i += 1 {
		sum += self.holders[i].water
	}
	return sum
}


fluid_domain_check_in_all :: proc(self: ^Fluid_Domain) {
	i: i32

	if !self.active {
		return
	}
	// the carries of the taps flowing now; a closed tap's carry is dropped, which moves nothing
	self.ncarries = 0
	for i = 0; i < self.noutlets; i += 1 {
		if self.outlets[i].carry != 0 {
			self.carryTaps[self.ncarries] = self.outlets[i].tap
			self.carries[self.ncarries]   = self.outlets[i].carry
			self.ncarries += 1
		}
	}
	for i = 0; i < self.nholders; i += 1 {
		if self.holders[i].entity != 0 {
			world_set_checked_out(self.world, false, self.holders[i].entity)
			world_set_field_of_value(self.world, "WaterStore.water", self.holders[i].entity, self.holders[i].water)
		} else {
			world_set_tile_checked_out(self.world, false, self.holders[i].x, self.holders[i].y, self.holders[i].level)
			world_set_water(self.world, self.holders[i].water, self.holders[i].x, self.holders[i].y, self.holders[i].level)
		}
	}
	self.active   = false
	self.nholders = 0
	self.noutlets = 0
}


@(private = "file")
fluid_domain_flowing :: proc(self: ^Fluid_Domain) -> bool {
	i: i32

	for i = 0; i < self.noutlets; i += 1 {
		if !self.outlets[i].exhausted && self.outlets[i].rate > 0 {
			return true
		}
	}
	return fluid_domain_spreading(self)
}


fluid_domain_saved_state :: proc(self: ^Fluid_Domain) -> []string {
	lines: [dynamic]string
	i:     i32

	fluid_domain_check_in_all(self)
	lines = make([dynamic]string, context.temp_allocator)
	for i = 0; i < self.ncarries; i += 1 {
		append(&lines, fmt.tprintf("carry %d %d", u64(self.carryTaps[i]), self.carries[i]))
	}
	return lines[:]
}


fluid_domain_restore_saved_state :: proc(self: ^Fluid_Domain, lines: []string) {
	tap:   i64
	carry: i64
	i:     int

	self.ncarries = 0
	for i = 0; i < len(lines) && self.ncarries < BG_FLUID_MAX; i += 1 {
		if sscanf(lines[i], "carry %llu %lld", &tap, &carry) == 2 {
			self.carryTaps[self.ncarries] = Entity_ID(u64(tap))
			self.carries[self.ncarries]   = carry
			self.ncarries += 1
		}
	}
}


// --- horizons ----------------------------------------------------------------

@(private = "file")
delivered :: proc(o: ^Fluid_Outlet, dt: i64) -> i64 {
	return (o.rate * dt + o.carry) / BG_MS_PER_MINUTE
}


// The first time at which the outlets on a store would ask for all of it:
// exactly the step in which it runs dry. Never later than the true time.
@(private = "file")
fluid_domain_exhaustion_of :: proc(self: ^Fluid_Domain, source: i32, t: Time) -> Time {
	hi:    i64
	lo:    i64
	mid:   i64
	rate:  i64
	sum:   i64
	water: i64
	i:     i32
	n:     i64

	rate  = 0
	n     = 0
	water = self.holders[source].water
	for i = 0; i < self.noutlets; i += 1 {
		if self.outlets[i].source == source && !self.outlets[i].exhausted {
			rate += self.outlets[i].rate
			n += 1
		}
	}
	// a holder nothing draws from never runs dry
	if n == 0 || rate == 0 {
		return TIME_NEVER
	}
	if water == 0 {
		return t
	}
	lo = 1
	hi = ((water + n) * BG_MS_PER_MINUTE + rate - 1) / rate
	for lo < hi {
		mid = (lo + hi) / 2
		sum = 0
		for i = 0; i < self.noutlets; i += 1 {
			if self.outlets[i].source == source && !self.outlets[i].exhausted {
				sum += delivered(&self.outlets[i], mid)
			}
		}
		if sum >= water {
			hi = mid
		} else {
			lo = mid + 1
		}
	}
	return time_make(t.ms + lo)
}


// --- watches -----------------------------------------------------------------

@(private = "file")
Fluid_Watch :: struct {
	activity: Entity_ID,
	holder:   i32,
	atLeast:  i64,
}


// The watches of running activities on holders in the structure.
@(private = "file")
fluid_domain_watches :: proc(self: ^Fluid_Domain, out: [^]Fluid_Watch) -> i32 {
	record:   ^Activity
	watching: [^]Entity_ID
	count:    uint
	running:  tri.Type
	i:        uint
	h:        i32
	n:        i32

	watching = world_copy_watching_activities(self.world, &count)      // the world's index of watches
	running  = tri.type_named(world_tri(self.world), "\"running\"")
	n        = 0
	for i = 0; i < count && n < BG_FLUID_MAX; i += 1 {
		record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), watching[i]))
		if record == nil || (record.watchHolder == 0 && record.watchFloor == 0) || record.status != u32(running) {
			continue
		}
		// a watch on a holder, or on a tile of the floor
		for h = 0; h < self.nholders; h += 1 {
			on: bool
			if record.watchFloor != 0 {
				on = self.holders[h].entity == NO_ENTITY && i64(self.holders[h].x) == record.watchX &&
				     i64(self.holders[h].y) == record.watchY && i64(self.holders[h].level) == record.watchLevel
			} else {
				on = self.holders[h].entity == Entity_ID(record.watchHolder)
			}
			if on {
				out[n].activity = watching[i]
				out[n].holder   = h
				out[n].atLeast  = record.watchFloor if record.watchFloor != 0 else record.watchAtLeast
				n += 1
				break
			}
		}
	}
	free(watching)
	return n
}


@(private = "file")
fluid_domain_has_fired :: proc(self: ^Fluid_Domain, activity: Entity_ID) -> bool {
	i: i32

	for i = 0; i < self.nfired; i += 1 {
		if self.fired[i] == activity {
			return true
		}
	}
	return false
}


// Forget fired watches whose activities no longer watch.
@(private = "file")
fluid_domain_prune_fired :: proc(self: ^Fluid_Domain, watches: [^]Fluid_Watch, n: i32) {
	i:    i32
	j:    i32
	k:    i32
	live: bool

	k = 0
	for i = 0; i < self.nfired; i += 1 {
		live = false
		for j = 0; j < n && !live; j += 1 {
			live = watches[j].activity == self.fired[i]
		}
		if live {
			self.fired[k] = self.fired[i]
			k += 1
		}
	}
	self.nfired = k
}


// The first step at which the inflow brings a holder to the threshold. Never
// later than the true time: a source running dry first only delays it.
@(private = "file")
fluid_domain_crossing_of :: proc(self: ^Fluid_Domain, w: ^Fluid_Watch, t: Time) -> Time {
	hi:   i64
	lo:   i64
	mid:  i64
	need: i64
	rate: i64
	sum:  i64
	i:    i32
	n:    i64

	need = w.atLeast - self.holders[w.holder].water
	if need <= 0 {
		return t
	}
	rate = 0
	n    = 0
	for i = 0; i < self.noutlets; i += 1 {
		if self.outlets[i].destination == w.holder && !self.outlets[i].exhausted {
			rate += self.outlets[i].rate
			n += 1
		}
	}
	if rate == 0 {
		return TIME_NEVER
	}
	lo = 1
	hi = ((need + n) * BG_MS_PER_MINUTE + rate - 1) / rate
	for lo < hi {
		mid = (lo + hi) / 2
		sum = 0
		for i = 0; i < self.noutlets; i += 1 {
			if self.outlets[i].destination == w.holder && !self.outlets[i].exhausted {
				sum += delivered(&self.outlets[i], mid)
			}
		}
		if sum >= need {
			hi = mid
		} else {
			lo = mid + 1
		}
	}
	return time_make(t.ms + lo)
}


fluid_domain_horizon_at :: proc(self: ^Fluid_Domain, t: Time) -> Horizon {
	watches: [BG_FLUID_MAX]Fluid_Watch
	// PORT: the C left this uninitialized on the stack, so a view whose tap
	// delivers into a store had x and y of whatever was there, which the
	// signature read; here they are zero.
	views:   [BG_FLUID_MAX]Tap_View
	tiles:   [^][3]i32
	ntiles:  i32
	h:       Horizon
	next_:   Time
	sig:     u64
	i:       i32
	n:       i32

	h.safeStep  = TIME_NEVER      // constant rates: any step is exact
	h.nextEvent = TIME_NEVER
	n      = fluid_domain_scan(self, &views[0])
	ntiles = fluid_domain_region(self, &tiles, &views[0], n)
	sig    = signature(&views[0], n, tiles, ntiles)
	// a tap opened or closed, or a bucket moved: check in and form again
	if self.active && sig != self.signature {
		fluid_domain_check_in_all(self)
	}
	if !self.active {
		self.signature = sig
		fluid_domain_form_from(self, &views[0], n, tiles, ntiles)
		free(tiles)
		tiles = nil
		if !fluid_domain_flowing(self) {
			fluid_domain_check_in_all(self)
			return h
		}
	}
	free(tiles)
	for i = 0; i < self.nholders; i += 1 {
		next_ = fluid_domain_exhaustion_of(self, i, t)
		if next_.ms < h.nextEvent.ms {
			h.nextEvent = next_
		}
	}
	if h.nextEvent.ms != TIME_NEVER.ms {
		self.predicted = h.nextEvent
	}
	if fluid_domain_spreading(self) {
		h.safeStep = time_make(BG_SPREAD_TAU)
	}
	// the activities' watches
	n = fluid_domain_watches(self, &watches[0])
	fluid_domain_prune_fired(self, &watches[0], n)
	for i = 0; i < n; i += 1 {
		if fluid_domain_has_fired(self, watches[i].activity) {
			continue
		}
		next_ = fluid_domain_crossing_of(self, &watches[i], t)
		if next_.ms < h.nextEvent.ms {
			h.nextEvent = next_
		}
	}
	return h
}


// --- a step --------------------------------------------------------------------

@(private = "file")
cmp_tap :: proc(a: ^i32, b: ^i32, ctx: rawptr) -> int {
	outlets: [^]Fluid_Outlet
	x:       Entity_ID
	y:       Entity_ID

	outlets = ([^]Fluid_Outlet)(ctx)
	x       = outlets[a^].tap
	y       = outlets[b^].tap
	return -1 if x < y else int(x > y)
}


@(private = "file")
sort_by_tap :: proc(order: [^]i32, n: i32, outlets: [^]Fluid_Outlet) {
	i: i32
	j: i32
	t: i32

	for i = 1; i < n; i += 1 {
		for j = i; j > 0 && cmp_tap(&order[j - 1], &order[j], outlets) > 0; j -= 1 {
			t            = order[j]
			order[j]     = order[j - 1]
			order[j - 1] = t
		}
	}
}


fluid_domain_advance_from :: proc(self: ^Fluid_Domain, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	group:     ^Proposal_Group
	granted:   [BG_FLUID_MAX]i64
	requested: [BG_FLUID_MAX]i64
	carry:     [BG_FLUID_MAX]i64
	order:     [BG_FLUID_MAX]i32
	demand:    i64
	dt:        i64
	left:      i64
	supply:    i64
	total:     i64
	step:      u64
	i:         i32
	k:         i32
	n:         i32
	s:         i32

	dt = t1.ms - t0.ms
	if !self.active || dt <= 0 {
		return
	}
	step = world_boundary(world) + 1
	for s = 0; s < self.nholders; s += 1 {
		// the outlets on this store, in tap-ID order whatever the inside order
		n = 0
		for i = 0; i < self.noutlets; i += 1 {
			if self.outlets[i].source == s && !self.outlets[i].exhausted {
				order[n] = i
				n += 1
			}
		}
		if n == 0 {
			continue
		}
		sort_by_tap(&order[0], n, &self.outlets[0])
		demand = 0
		for k = 0; k < n; k += 1 {
			i            = order[k]
			requested[i] = delivered(&self.outlets[i], dt)
			carry[i]     = (self.outlets[i].rate * dt + self.outlets[i].carry) % BG_MS_PER_MINUTE
			demand      += requested[i]
		}
		supply = self.holders[s].water
		if demand <= supply {
			for k = 0; k < n; k += 1 {
				i                      = order[k]
				granted[i]             = requested[i]
				self.outlets[i].carry  = carry[i]
			}
		} else {
			// pro rata; what's left goes one each in tap order, rotated by the step
			left = supply
			for k = 0; k < n; k += 1 {
				i                     = order[k]
				granted[i]            = i64(i128(supply) * i128(requested[i]) / i128(demand))
				left                 -= granted[i]
				self.outlets[i].carry = 0
			}
			for k = 0; left > 0; k += 1 {
				i = order[int((step + u64(k)) % u64(n))]
				if granted[i] < requested[i] {
					granted[i] += 1
					left -= 1
				}
			}
		}
		total = 0
		for k = 0; k < n; k += 1 {
			i      = order[k]
			total += granted[i]
			self.holders[self.outlets[i].destination].water += granted[i]
			append(&self.log, fmt.aprintf("t=%d: tap %d requested %dmL, granted %dmL",
			                              t1.ms, u64(self.outlets[i].tap), requested[i], granted[i]))
		}
		self.holders[s].water -= total
		assert(self.holders[s].water >= 0)       // no step drives a stock negative

		// run dry: every tap on it says so, in this step
		if self.holders[s].water == 0 {
			group = proposal_group_group_with_phase(.Process, fmt.tprintf("fluid: %d ran dry", u64(self.holders[s].entity)))
			for k = 0; k < n; k += 1 {
				i                         = order[k]
				self.outlets[i].exhausted = true
				proposal_group_emit_subject_other(group, "exhausted", whole(self.outlets[i].tap), whole(self.holders[s].entity))
			}
			committer_submit(committer, group)
		}
	}
	fluid_domain_spread_for(self, dt)
	// readers (the inspector, perception) see the domain's values; the
	// records stay checked out, so nothing else may change them
	fluid_domain_mirror(self)
	// watches the step brought to their threshold
	fluid_domain_report_watches_to(self, committer)
	if !fluid_domain_flowing(self) {
		fluid_domain_check_in_all(self)
	}
}


// Water levelling out across the floor: every adjacent pair from step-start
// values, then all applied, so no order can matter.
@(private = "file")
fluid_domain_spread_for :: proc(self: ^Fluid_Domain, dt: i64) {
	at:    [^]Floor_Tile
	delta: [^]i64
	diff:  i64
	q:     i64
	n:     i32
	k:     i32
	i:     i32
	j:     i32
	d:     i32
	dt    := dt

	if dt > BG_SPREAD_TAU {
		dt = BG_SPREAD_TAU
	}
	at    = make([^]Floor_Tile, int(self.nholders if self.nholders != 0 else 1))
	delta = make([^]i64, int(self.nholders if self.nholders != 0 else 1))
	n     = fluid_domain_tile_index(self, at)
	for k = 0; k < n; k += 1 {
		for d = 0; d < 2; d += 1 {          // each pair once: east, south
			i = at[k].holder
			j = neighbour(at, n, &at[k], d)
			if j < 0 {
				continue
			}
			diff = self.holders[i].water - self.holders[j].water
			q    = (-diff if diff < 0 else diff) * dt / (8 * BG_SPREAD_TAU)
			if q == 0 {
				continue
			}
			if diff > 0 {
				delta[i] -= q
				delta[j] += q
			} else {
				delta[i] += q
				delta[j] -= q
			}
		}
	}
	for i = 0; i < self.nholders; i += 1 {
		self.holders[i].water += delta[i]
		assert(self.holders[i].water >= 0)
	}
	free(delta)
	free(at)
}


@(private = "file")
fluid_domain_mirror :: proc(self: ^Fluid_Domain) {
	i: i32

	for i = 0; i < self.nholders; i += 1 {
		if self.holders[i].entity != 0 {
			world_set_field_of_value(self.world, "WaterStore.water", self.holders[i].entity, self.holders[i].water)
		} else {
			world_set_water(self.world, self.holders[i].water, self.holders[i].x, self.holders[i].y, self.holders[i].level)
		}
	}
}


@(private = "file")
fluid_domain_report_watches_to :: proc(self: ^Fluid_Domain, committer: ^Committer) {
	watches: [BG_FLUID_MAX]Fluid_Watch
	group:   ^Proposal_Group
	i:       i32
	n:       i32

	n     = fluid_domain_watches(self, &watches[0])
	group = nil
	for i = 0; i < n; i += 1 {
		if fluid_domain_has_fired(self, watches[i].activity) || self.holders[watches[i].holder].water < watches[i].atLeast {
			continue
		}
		if group == nil {
			group = proposal_group_group_with_phase(.Process, "fluid: watches reached")
		}
		proposal_group_emit_subject_other(group, "watched", whole(watches[i].activity), whole(self.holders[watches[i].holder].entity))
		if self.nfired < BG_FLUID_MAX {
			self.fired[self.nfired] = watches[i].activity
			self.nfired += 1
		}
	}
	if group != nil {
		committer_submit(committer, group)
	}
}


// sscanf for the formats the saves use: literal text, white space (any run
// of it, none too), and integer conversions (%d, %lld, %llu: an optional
// sign, then digits, an unsigned one wrapping as strtoull does), each stored
// as 64 bits for the caller to narrow as C stored it. The number of
// conversions made before the first failure.
@(private = "file")
sscanf :: proc(text: string, format: string, out: ..^i64) -> int {
	is_space :: proc(c: u8) -> bool {
		return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f'
	}
	i, f, n := 0, 0, 0
	for f < len(format) {
		c := format[f]
		if is_space(c) {
			for f < len(format) && is_space(format[f]) do f += 1
			for i < len(text) && is_space(text[i]) do i += 1
			continue
		}
		if c == '%' {
			f += 1
			for f < len(format) && (format[f] == 'l' || format[f] == 'h') do f += 1
			f += 1         // d or u
			for i < len(text) && is_space(text[i]) do i += 1
			j := i
			neg := false
			if j < len(text) && (text[j] == '+' || text[j] == '-') {
				neg = text[j] == '-'
				j += 1
			}
			if j >= len(text) || text[j] < '0' || text[j] > '9' do return n
			v: u64 = 0
			for j < len(text) && text[j] >= '0' && text[j] <= '9' {
				v = v * 10 + u64(text[j] - '0')
				j += 1
			}
			i = j
			out[n]^ = i64(-v if neg else v)
			n += 1
			continue
		}
		if i >= len(text) || text[i] != c do return n
		i += 1
		f += 1
	}
	return n
}


fluid_domain_as_domain :: proc(self: ^Fluid_Domain) -> Domain {
	return Domain{
		data                = self,
		name                = proc(data: rawptr) -> string {return fluid_domain_name((^Fluid_Domain)(data))},
		check_in_all        = proc(data: rawptr) {fluid_domain_check_in_all((^Fluid_Domain)(data))},
		saved_state         = proc(data: rawptr) -> []string {return fluid_domain_saved_state((^Fluid_Domain)(data))},
		restore_saved_state = proc(data: rawptr, lines: []string) {fluid_domain_restore_saved_state((^Fluid_Domain)(data), lines)},
		is_active           = proc(data: rawptr) -> bool {return fluid_domain_is_active((^Fluid_Domain)(data))},
		horizon_at          = proc(data: rawptr, t: Time) -> Horizon {return fluid_domain_horizon_at((^Fluid_Domain)(data), t)},
		advance_from        = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
			fluid_domain_advance_from((^Fluid_Domain)(data), t0, t1, world, committer)
		},
	}
}

package lab

/*
 * BGWorld — authoritative world state: the entity table and ID counter, one
 * store per component kind, locations, edges, tombstones, and the history of
 * committed events. Every mutation is journaled while a group is open, so
 * change commitment can apply a group and roll it back whole.
 *
 * Only change commitment mutates a world. Everything else reads it.
 *
 * (ported from the Objective-C lab's core/BGWorld.m)
 */

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import tri "../../triangle/odin/triangle"


/* What the entity table records for each live entity. */
Entity_Info :: struct {
	blueprint: cstring,     /* interned */
	seed:      u64,
}

/* What remains of an entity that was destroyed, merged, or consumed. */
Tombstone :: struct {
	blueprint: cstring,
	successor: Entity_ID,   /* merged into, or NO_ENTITY */
	cause:     u64,         /* the event that ended it */
	reason:    [24]u8,
}

/* Binary relations other than location. */
Edge_Kind :: enum i32 {
	Split_From = 0,         /* new → source; many-to-one */
	Claimant,               /* claim → agent; many-to-one */
	Claim_Subject,          /* claim → entity; many-to-many */
	Derived_From,           /* content → the content it was altered from; many-to-one */
	Authorizes,             /* authorization → the content that states it */
	Lists,                  /* a register's content → content it lists */
	Kind_Count,
}

Edge :: struct {
	kind: Edge_Kind,
	from: Entity_ID,
	to:   Entity_ID,
}

/* A committed event: history, and what reactions respond to. */
Event :: struct {
	index:    u64,
	boundary: u64,
	round:    u32,
	kind:     cstring,      /* a static string: "created", "moved", "split", ... */
	subject:  Entity_ID,
	other:    Entity_ID,
	actor:    Entity_ID,    /* who did it: the agent whose action the group is, or none */
	location: Location,     /* for "moved" and "created": where to */
	amount:   i64,
	detail:   cstring,      /* interned: a field path, an edge kind, a reason; or nil */
	cause:    u64,          /* the event this one follows from, or 0 */
	group:    u64,          /* the commit position of its group */
	diagnostic: bool,       /* a step along the way, not history: kept a while, then digested
	                           (KNOWLEDGE.md decision 21) */
}

// BGEdgeKindNames, by edge kind (Kind_Count has none).
EDGE_KIND_NAMES := #partial [Edge_Kind]cstring {
	.Split_From    = "splitFrom",
	.Claimant      = "claimant",
	.Claim_Subject = "claimSubject",
	.Derived_From  = "derivedFrom",
	.Authorizes    = "authorizes",
	.Lists         = "lists",
}


/* A way a region of air opens: a doorway at its room's side, the region
 * beyond (none: the outdoors), the door standing in it, if any, and the air
 * it passes now, mmol a second each way: the door's width while it is ajar,
 * nothing while it is shut, the doorway's draught with no door. */
Air_Opening :: struct {
	at:     Location,
	beyond: Entity_ID,
	door:   Entity_ID,
	flow:   i64,
	open:   bool,           /* no door, or its door ajar */
}


World :: struct {
	using object:     Object,
	content:          ^tri.Content,     /* not owned: whoever loaded it frees it */
	seed:             u64,
	time:             Time,
	boundary:         u64,
	nextID:           Entity_ID,

	nkinds:           uint,
	kinds:            [^]^Store,        /* one per generated component kind */
	kindTypes:        [^]tri.Type,
	trueType:         tri.Type,
	entities:         ^Store,           /* Entity_Info */
	locations:        ^Store,           /* Location */
	tombstones:       ^Store,           /* Tombstone */

	edges:            [dynamic]Edge,    /* sorted by kind, from, to */

	/* history (KNOWLEDGE.md decision 21): what is kept, in index order. From
	 * `whole` on, every event is (dense: at windowAt + its index - whole);
	 * before it, only history, diagnostic events digested. Indices are never
	 * reused or renumbered */
	events:           [dynamic]Event,
	nextEvent:        u64,              /* the next event's index */
	whole:            u64,              /* every event from this index on is kept */
	windowAt:         int,              /* where the event with index `whole` is, or would be */
	compactDue:       u64,              /* events before this are compacted next time */
	historyWindow:    i64,              /* ms a diagnostic event is kept at least; 0, for good */
	compactAt:        i64,              /* ms: when history is next compacted */
	digests:          [dynamic]Digest,  /* what was compacted, counted */
	debugHistory:     bool,             /* debug fields' changes logged too (KNOWLEDGE.md decision 21) */

	strings:          [dynamic]cstring, /* interned, sorted */

	journal:          [dynamic]Journal_Entry,
	open:             bool,

	arena:            ^tri.Arena,

	tilesWide:        i32,
	tilesHigh:        i32,
	levels:           i32,
	stocks:           ^Tile_Stocks,     /* tile stocks (water, mL), by chunk, only where ever wet */
	terrain:          ^Terrain,         /* what each tile is (TERRAIN.md); nil: content has no kinds, all open */
	roomAir:          [^]Entity_ID,     /* each room's air, by room number; a cache */
	nroomAir:         u32,
	roomAirChanges:   u64,              /* the GasStore store's members and anchors moved, when it was made */
	airAnchors:       u64,              /* GasStore tiles set, or undone */
	roomAirDropped:   u64,              /* the terrain's rooms dropped, then */
	roomAirKnown:     bool,

	onGround:         ^Index,           /* what stands on a tile, by its chunk; derived from the locations */
	inPlace:          ^Index,           /* what is in, on, held by or part of a thing, by the thing */
	tracesOnGround:   ^Index,           /* traces on the floor, by chunk */
	tracesBorne:      ^Index,           /* traces on a thing, by the thing */
	activitiesOf:     ^Index,           /* activities, by actor */
	watching:         ^Index,           /* activities with a watch, under one key */
	touching:         ^Index,           /* activities, by actor, item and destination */
	creations:        ^Index,           /* the "created" events' indices, by what they created */
	reality:          ^Reality,         /* anchors, levels of detail, leases (REALITY.md) */
	weakness:         Weakness_Table,   /* hunger's curves, from content (domains_bodies.odin) */
	looks:            Looks,            /* what things look like, from content (looks.odin) */
	seen:             [dynamic]Seen_Kind, /* the kinds seen at a glance, from content (act_view.odin) */
	seenAs:           map[Entity_ID]Seen_As, /* each entity's kind as seen, worked out once (act_view.odin) */
	recalled:         map[string]string, /* features as recalled, by kind, steps and features (know_knowledge_store.odin) */
	matched:          map[string]Matched, /* matches of described things, by what was matched (world_matched) */
	settled:          ^Anchors_Kept,    /* the anchors as last settled, to tell what rose */
	risen:            [^]Entity_ID,     /* what rose from frozen since it was last taken */
	nrisen:           uint,
	risencap:         uint,
	activityObserver: Record_Observer,  /* not retained */
	touched:          [^]Entity_ID,     /* entities changed since the mark, unsorted, maybe twice */
	vacated:          [^]Location,      /* ground tiles left since the mark */
	nvacated:         uint,
	vacatedcap:       uint,
	ntouched:         uint,
	touchedcap:       uint,
	kindCache:        [64]struct {
		name: cstring,
		kind: uint,
	},                                  /* kindNamed's, by the name's address */
	kindTrace:        uint,
	kindGas:          uint,
	kindActivity:     uint,
	kindAgent:        uint,
	checkedOut:       [dynamic]Entity_ID, /* sorted; not saved: saves check everything in */
}


/* --- the journal ----------------------------------------------------------- */

@(private = "file")
Journal_Op :: enum {
	Record,
	Edge_Add,
	Edge_Remove,
	Next_ID,
	Events,
	Terrain,
}

@(private = "file")
Journal_Entry :: struct {
	op:     Journal_Op,
	store:  ^Store,
	kind:   uint,           /* a component kind, or one of the codes below */
	entity: Entity_ID,
	had:    bool,
	old:    rawptr,
	edge:   Edge,
	value:  u64,            /* terrain: the kind it was */
	tile:   Location,       /* terrain: the cell */
}

/* kind codes for the stores that aren't component kinds */
@(private = "file") KIND_ENTITIES :: uint(1000001)
@(private = "file") KIND_LOCATIONS :: uint(1000002)
@(private = "file") KIND_TOMBSTONES :: uint(1000003)


// C's realloc of an array of T, from old_cap elements to new_cap (Odin's
// heap, so callers free what is handed out with free(), as before).
@(private = "file")
grow :: proc(p: [^]$T, old_cap, new_cap: uint) -> [^]T {
	q, _ := mem.resize(rawptr(p), int(old_cap * size_of(T)), int(new_cap * size_of(T)))
	return ([^]T)(q)
}


/* --- tile stocks --------------------------------------------------------- */

/* Water per tile, a chunk of BG_CHUNK x BG_CHUNK cells of a level at a
 * time, kept once a tile in it is wet or checked out: a world costs what has
 * ever been wet, not its extent. */
@(private = "file")
Stock_Chunk :: struct {
	cx:    i32,
	cy:    i32,
	z:     i32,
	water: [^]i64,          /* nil: an empty slot */
	out:   [^]u8,
}

@(private = "file")
Tile_Stocks :: struct {
	chunks: [^]Stock_Chunk,
	n:      uint,
	cap:    uint,           /* a power of two, or 0 */
}


@(private = "file")
stocks_new :: proc() -> ^Tile_Stocks {
	return new(Tile_Stocks)
}


@(private = "file")
stocks_free :: proc(s: ^Tile_Stocks) {
	for i: uint = 0; i < s.cap; i += 1 {
		free(s.chunks[i].water)
		free(s.chunks[i].out)
	}
	free(s.chunks)
	free(s)
}


@(private = "file")
stock_slot :: proc(cx, cy, z: i32, cap: uint) -> uint {
	return uint(mix((u64(u32(cx)) << 32) ~ (u64(u32(cy)) << 8) ~ u64(u32(z)))) & (cap - 1)
}


@(private = "file")
stocks_chunk :: proc(s: ^Tile_Stocks, x, y, z: i32, make_: bool) -> ^Stock_Chunk {
	cx := x / BG_CHUNK
	cy := y / BG_CHUNK
	for i := stock_slot(cx, cy, z, s.cap) if s.cap != 0 else 0; s.cap != 0 && s.chunks[i].water != nil; i = (i + 1) & (s.cap - 1) {
		if s.chunks[i].cx == cx && s.chunks[i].cy == cy && s.chunks[i].z == z {
			return &s.chunks[i]
		}
	}
	if !make_ {
		return nil
	}
	if (s.n + 1) * 2 > s.cap {
		old := s.chunks
		oldcap := s.cap
		s.cap = oldcap * 2 if oldcap != 0 else 8
		s.chunks = make([^]Stock_Chunk, s.cap)
		for i: uint = 0; i < oldcap; i += 1 {
			if old[i].water != nil {
				j := stock_slot(old[i].cx, old[i].cy, old[i].z, s.cap)
				for ; s.chunks[j].water != nil; j = (j + 1) & (s.cap - 1) {
				}
				s.chunks[j] = old[i]
			}
		}
		free(old)
	}
	i := stock_slot(cx, cy, z, s.cap)
	for ; s.chunks[i].water != nil; i = (i + 1) & (s.cap - 1) {
	}
	s.chunks[i].cx = cx
	s.chunks[i].cy = cy
	s.chunks[i].z = z
	s.chunks[i].water = make([^]i64, BG_CHUNK * BG_CHUNK)
	s.chunks[i].out = make([^]u8, BG_CHUNK * BG_CHUNK)
	s.n += 1
	return &s.chunks[i]
}


@(private = "file")
stocks_cell :: proc(s: ^Tile_Stocks, x, y, z: i32, make_: bool) -> ^i64 {
	c := stocks_chunk(s, x, y, z, make_)
	return &c.water[(y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK] if c != nil else nil
}


@(private = "file")
stocks_out :: proc(s: ^Tile_Stocks, x, y, z: i32, make_: bool) -> ^u8 {
	c := stocks_chunk(s, x, y, z, make_)
	return &c.out[(y % BG_CHUNK) * BG_CHUNK + x % BG_CHUNK] if c != nil else nil
}


@(private = "file")
stocks_any :: proc(s: ^Tile_Stocks) -> bool {
	for i: uint = 0; i < s.cap; i += 1 {
		for k := 0; s.chunks[i].water != nil && k < BG_CHUNK * BG_CHUNK; k += 1 {
			if s.chunks[i].water[k] != 0 || s.chunks[i].out[k] != 0 {
				return true
			}
		}
	}
	return false
}


@(private = "file")
stocks_total :: proc(s: ^Tile_Stocks) -> i64 {
	sum: i64 = 0
	for i: uint = 0; i < s.cap; i += 1 {
		for k := 0; s.chunks[i].water != nil && k < BG_CHUNK * BG_CHUNK; k += 1 {
			if s.chunks[i].out[k] == 0 {
				sum += s.chunks[i].water[k]
			}
		}
	}
	return sum
}


// cmp_tile, as a less: by level, row, column (it orders every two tiles).
@(private = "file")
cmp_tile :: proc(p, q: [3]i32) -> bool {
	for k := 2; k >= 0; k -= 1 {
		if p[k] != q[k] {
			return p[k] < q[k]
		}
	}
	return false
}


/* The wet tiles, by level, row, column; how many, filling up to max. */
@(private = "file")
stocks_wet :: proc(s: ^Tile_Stocks, out: [^][3]i32, max_: uint) -> uint {
	n: uint = 0
	for i: uint = 0; i < s.cap; i += 1 {
		for k := 0; s.chunks[i].water != nil && k < BG_CHUNK * BG_CHUNK; k += 1 {
			if s.chunks[i].water[k] != 0 {
				if n < max_ {
					out[n][0] = s.chunks[i].cx * BG_CHUNK + i32(k % BG_CHUNK)
					out[n][1] = s.chunks[i].cy * BG_CHUNK + i32(k / BG_CHUNK)
					out[n][2] = s.chunks[i].z
				}
				n += 1
			}
		}
	}
	if out != nil && max_ != 0 {
		slice.sort_by(out[:n if n < max_ else max_], cmp_tile)
	}
	return n
}


/* --- the world ------------------------------------------------------------ */

/* nil, with the reason, if the content's hash differs from the generated
 * header's, an operation in it does nothing (act_declared.odin), or a
 * progression names what isn't there (domains_progressions.odin) */
world_with_content :: proc(content: ^tri.Content, seed: u64, error: ^string) -> ^World {
	if tri.content_hash(content) != CONTENT_HASH {
		if error != nil {
			error^ = fmt.tprintf("the content (%016x) is not what src/components.odin " +
			                     "was generated from (%016x): run make gen",
			                     tri.content_hash(content), u64(CONTENT_HASH))
		}
		return nil
	}
	if reason := declared_check(content); reason != "" {
		if error != nil do error^ = reason
		return nil
	}
	if reason := progressions_check(content); reason != "" {
		if error != nil do error^ = reason
		return nil
	}
	world := world_init_with_content(content, seed)
	return autorelease(world)
}


@(private = "file")
world_init_with_content :: proc(content: ^tri.Content, seed: u64) -> ^World {
	self := object_new(World, world_dealloc)

	self.content = content
	self.seed = seed
	self.debugHistory = debug_history
	self.nextEvent = 1
	self.whole = 1
	self.compactDue = 1
	self.nextID = 1
	self.nkinds = COMPONENT_COUNT
	self.kinds = make([^]^Store, self.nkinds if self.nkinds != 0 else 1)
	self.kindTypes = make([^]tri.Type, self.nkinds if self.nkinds != 0 else 1)
	for k: uint = 0; k < self.nkinds; k += 1 {
		self.kinds[k] = store_init_with_record_size(COMPONENTS[k].size)
		self.kindTypes[k] = tri.type_named(content, COMPONENTS[k].type)
	}
	self.trueType = tri.type_named(content, "true")
	self.kindTrace = world_kind_named(self, "Trace")
	self.kindGas = world_kind_named(self, "GasStore")
	self.kindActivity = world_kind_named(self, "Activity")
	self.kindAgent = world_kind_named(self, "Agent")
	self.entities = store_init_with_record_size(size_of(Entity_Info))
	self.locations = store_init_with_record_size(size_of(Location))
	self.tombstones = store_init_with_record_size(size_of(Tombstone))
	self.onGround = index_new()
	self.inPlace = index_new()
	self.tracesOnGround = index_new()
	self.tracesBorne = index_new()
	self.activitiesOf = index_new()
	self.watching = index_new()
	self.touching = index_new()
	self.creations = index_new()
	self.reality = reality_new(content)
	self.weakness = weakness_load(content)
	self.looks = looks_load(content)
	self.seen  = seen_kinds_load(content)
	self.arena = tri.arena_new()
	self.tilesWide = 32
	self.tilesHigh = 32
	self.levels = 1
	self.stocks = stocks_new()
	{
		why: string

		self.terrain = terrain_new(content, self.tilesWide, self.tilesHigh, self.levels, nil, &why)
	}
	return self
}


world_dealloc :: proc(self: ^World) {
	world_commit_group(self)
	for i: uint = 0; i < self.nkinds; i += 1 {
		release(self.kinds[i])
	}
	free(self.kinds)
	free(self.kindTypes)
	release(self.entities)
	release(self.locations)
	release(self.tombstones)
	delete(self.edges)
	delete(self.events)
	delete(self.digests)
	for s in self.strings {
		delete(s)
	}
	delete(self.strings)
	delete(self.journal)
	stocks_free(self.stocks)
	terrain_free(self.terrain)
	free(self.roomAir)
	free(self.touched)
	free(self.vacated)
	index_free(self.onGround)
	index_free(self.inPlace)
	index_free(self.tracesOnGround)
	index_free(self.tracesBorne)
	index_free(self.activitiesOf)
	index_free(self.watching)
	index_free(self.touching)
	index_free(self.creations)
	reality_free(self.reality)
	looks_free(&self.looks)
	delete(self.seen)
	for _, v in self.seenAs do delete(v.kind)
	delete(self.seenAs)
	world_forget_recalled(self)
	delete(self.recalled)
	world_forget_matched(self)
	delete(self.matched)
	free(self.settled)
	free(self.risen)
	delete(self.checkedOut)
	tri.arena_free(self.arena)
	/* the content isn't the world's: whoever loaded it frees it */
}


world_content_build :: proc(self: ^World) -> ^tri.Content {
	return self.content
}


world_tri :: proc(self: ^World) -> ^tri.Content {
	return self.content
}


world_seed :: proc(self: ^World) -> u64 {
	return self.seed
}


world_time :: proc(self: ^World) -> Time {
	return self.time
}


world_set_time :: proc(self: ^World, time: Time) {
	self.time = time
}


world_boundary :: proc(self: ^World) -> u64 {
	return self.boundary
}


world_set_boundary :: proc(self: ^World, boundary: u64) {
	self.boundary = boundary
}


world_next_id :: proc(self: ^World) -> Entity_ID {
	return self.nextID
}


/* for restoring a save: the counter, and tombstones as they were */
world_set_next_id :: proc(self: ^World, nextID: Entity_ID) {
	self.nextID = nextID
}


world_restore_tombstone :: proc(self: ^World, stone: Tombstone, entity: Entity_ID) {
	stone := stone
	stone.blueprint = world_intern(self, stone.blueprint)
	store_set_record(self.tombstones, &stone, entity)
}


world_entities :: proc(self: ^World) -> ^Store {
	return self.entities
}


world_tombstones :: proc(self: ^World) -> ^Store {
	return self.tombstones
}


world_edge_count :: proc(self: ^World) -> uint {
	return uint(len(self.edges))
}


world_edge_at :: proc(self: ^World, i: uint) -> ^Edge {
	return &self.edges[i] if i < uint(len(self.edges)) else nil
}


/* --- journal --------------------------------------------------------------- */

@(private = "file")
journal_push :: proc(self: ^World) -> ^Journal_Entry {
	append(&self.journal, Journal_Entry{})
	return &self.journal[len(self.journal) - 1]
}


@(private = "file")
journal_record :: proc(self: ^World, store: ^Store, kind: uint, entity: Entity_ID) {
	if !self.open {
		return
	}
	j := journal_push(self)
	j.op = .Record
	j.store = store
	j.kind = kind
	j.entity = entity
	current := store_record_for(store, entity)
	j.had = current != nil
	if current != nil {
		j.old, _ = mem.alloc(int(store_record_size(store)))
		mem.copy(j.old, current, int(store_record_size(store)))
	}
}


world_begin_group :: proc(self: ^World) {
	world_commit_group(self)
	self.open = true
}


world_commit_group :: proc(self: ^World) {
	for i := 0; i < len(self.journal); i += 1 {
		free(self.journal[i].old)
	}
	clear(&self.journal)
	self.open = false
}


world_rollback_group :: proc(self: ^World) {
	for i := len(self.journal) - 1; i >= 0; i -= 1 {
		j := &self.journal[i]
		switch j.op {
		case .Record:
			if self.kindGas < self.nkinds && j.store == self.kinds[self.kindGas] {
				self.airAnchors += 1
			}
			if j.store == self.locations {
				file_location(self, j.entity, (^Location)(store_record_for(self.locations, j.entity)), false)
			}
			if j.kind < self.nkinds && j.store == self.kinds[j.kind] {
				file_record(self, j.kind, j.entity, false)
			}
			if j.had {
				store_set_record(j.store, j.old, j.entity)
			} else {
				store_remove_record_for(j.store, j.entity)
			}
			if j.store == self.locations {
				file_location(self, j.entity, (^Location)(store_record_for(self.locations, j.entity)), true)
			}
			if j.kind < self.nkinds && j.store == self.kinds[j.kind] {
				file_record(self, j.kind, j.entity, true)
			}

		case .Edge_Add:
			edge_remove_raw(self, j.edge)

		case .Edge_Remove:
			edge_insert_raw(self, j.edge)

		case .Next_ID:
			self.nextID = Entity_ID(j.value)

		case .Events:
			/* the events from that index on go, and it is the next again */
			for len(self.events) != 0 && self.events[len(self.events) - 1].index >= j.value do pop(&self.events)
			self.nextEvent = j.value

		case .Terrain:
			terrain_set(self.terrain, j.tile.x, j.tile.y, j.tile.level, Terrain_Kind(j.value))
		}
	}
	world_commit_group(self)
}


/* While a group is open: the entities it has touched, in ID order, and the
 * record a kind had for an entity before the group began. */
world_touched :: proc(self: ^World, out: [^]Entity_ID, max_: uint) -> uint {
	njournal := uint(len(self.journal))
	all := make([]Entity_ID, njournal if njournal != 0 else 1)
	n: uint = 0
	for i: uint = 0; i < njournal; i += 1 {
		if self.journal[i].op == .Record {
			all[n] = self.journal[i].entity
			n += 1
		}
	}
	slice.sort(all[:n])
	u: uint = 0
	for i: uint = 0; i < n; i += 1 {
		if i == 0 || all[i] != all[i - 1] {
			if u < max_ {
				out[u] = all[i]
			}
			u += 1
		}
	}
	delete(all)
	return u
}


world_record_before_group :: proc(self: ^World, kind: uint, entity: Entity_ID, existed: ^bool) -> rawptr {
	for i := 0; i < len(self.journal); i += 1 {
		if self.journal[i].op == .Record && self.journal[i].kind == kind && self.journal[i].entity == entity {
			existed^ = self.journal[i].had
			return self.journal[i].old
		}
	}
	current := store_record_for(self.kinds[kind], entity)
	existed^ = current != nil
	return current
}


world_info_before_group :: proc(self: ^World, entity: Entity_ID) -> ^Entity_Info {
	for i := 0; i < len(self.journal); i += 1 {
		if self.journal[i].op == .Record && self.journal[i].kind == KIND_ENTITIES && self.journal[i].entity == entity {
			return (^Entity_Info)(self.journal[i].old) if self.journal[i].had else nil
		}
	}
	return (^Entity_Info)(store_record_for(self.entities, entity))
}


/* --- component kinds and fields -------------------------------------------- */

world_kind_count :: proc(self: ^World) -> uint {
	return self.nkinds
}


/* NOT_FOUND if none */
world_kind_named :: proc(self: ^World, name: cstring) -> uint {
	/* most names asked are literals, the same address each time: kept by
	 * it, and checked, as a buffer may hold another name at that address */
	slot := (uint(uintptr(rawptr(name))) >> 3) & 63
	if rawptr(self.kindCache[slot].name) == rawptr(name) && self.kindCache[slot].kind < self.nkinds &&
	   string(COMPONENTS[self.kindCache[slot].kind].name) == string(name) {
		return self.kindCache[slot].kind
	}
	for k: uint = 0; k < self.nkinds; k += 1 {
		if string(COMPONENTS[k].name) == string(name) {
			self.kindCache[slot].name = name
			self.kindCache[slot].kind = k
			return k
		}
	}
	return NOT_FOUND
}


world_kind_info :: proc(self: ^World, kind: uint) -> ^Component_Info {
	return &COMPONENTS[kind]
}


world_store_for_kind :: proc(self: ^World, kind: uint) -> ^Store {
	return self.kinds[kind]
}


world_record :: proc(self: ^World, kind: uint, entity: Entity_ID) -> rawptr {
	if kind >= self.nkinds {
		return nil
	}
	return store_record_for(self.kinds[kind], entity)
}


/* Files or unfiles a trace where it is: on what bears it, or its tile. */
@(private = "file")
file_trace :: proc(self: ^World, entity: Entity_ID, trace: ^Trace, add: bool) {
	index: ^Index
	key: u64

	if trace == nil {
		return
	}
	if trace.bearer != 0 {
		index = self.tracesBorne
		key = trace.bearer
	} else {
		index = self.tracesOnGround
		key = ground_key(i32(trace.tileX), i32(trace.tileY), i32(trace.tileLevel))
	}
	if add {
		index_add(index, key, entity)
	} else {
		index_remove(index, key, entity)
	}
}


/* Files or unfiles an activity: under its actor, and, with a watch, among
 * those watching. */
@(private = "file")
file_activity :: proc(self: ^World, entity: Entity_ID, activity: ^Activity, add: bool) {
	if activity == nil {
		return
	}
	if add {
		index_add(self.activitiesOf, activity.actorRef, entity)
		if activity.actorRef != 0 {
			index_add(self.touching, activity.actorRef, entity)
		}
		if activity.itemRef != 0 {
			index_add(self.touching, activity.itemRef, entity)
		}
		if activity.destinationRef != 0 {
			index_add(self.touching, activity.destinationRef, entity)
		}
		if activity.watchHolder != 0 || activity.watchFloor != 0 || activity.watchDioxide != 0 || activity.watchCool != 0 ||
		   activity.watchWarm != 0 {
			index_add(self.watching, 0, entity)
		}
	} else {
		index_remove(self.activitiesOf, activity.actorRef, entity)
		index_remove(self.touching, activity.actorRef, entity)
		index_remove(self.touching, activity.itemRef, entity)
		index_remove(self.touching, activity.destinationRef, entity)
		index_remove(self.watching, 0, entity)
	}
}


/* A thing is leaving where it was: the ground tile under it, noted. */
@(private = "file")
vacate :: proc(self: ^World, was: ^Location) {
	if was == nil {
		return
	}
	at := was^
	for guard := 0; at.form != .On_Tile && at.form != .None && at.place != 0 && guard < 64; guard += 1 {
		at = world_location_of(self, at.place)
	}
	if at.form != .On_Tile {
		return
	}
	if self.nvacated == self.vacatedcap {
		old := self.vacatedcap
		self.vacatedcap = self.vacatedcap * 2 if self.vacatedcap != 0 else 64
		self.vacated = grow(self.vacated, old, self.vacatedcap)
	}
	self.vacated[self.nvacated] = at
	self.nvacated += 1
}


/* An entity changed: noted for those who work when something happens. */
@(private = "file")
touch :: proc(self: ^World, entity: Entity_ID) {
	if self.ntouched != 0 && self.touched[self.ntouched - 1] == entity {
		return
	}
	if self.ntouched == self.touchedcap {
		old := self.touchedcap
		self.touchedcap = self.touchedcap * 2 if self.touchedcap != 0 else 256
		self.touched = grow(self.touched, old, self.touchedcap)
	}
	self.touched[self.ntouched] = entity
	self.ntouched += 1
}


/* Files or unfiles a record in what the world indexes of its kind. */
@(private = "file")
file_record :: proc(self: ^World, kind: uint, entity: Entity_ID, add: bool) {
	if add {
		touch(self, entity)
	}
	if add && kind == self.kindActivity && self.activityObserver.data != nil {
		self.activityObserver.changed_record(self.activityObserver.data, self, entity, kind)
	}
	if kind == self.kindTrace {
		file_trace(self, entity, (^Trace)(store_record_for(self.kinds[kind], entity)), add)
	} else if kind == self.kindActivity {
		file_activity(self, entity, (^Activity)(store_record_for(self.kinds[kind], entity)), add)
	}
}


world_set_record :: proc(self: ^World, record: rawptr, kind: uint, entity: Entity_ID) {
	if store_record_for(self.kinds[kind], entity) == nil do world_forget_seen_as(self, entity)     /* a component it hadn't */
	journal_record(self, self.kinds[kind], kind, entity)
	file_record(self, kind, entity, false)
	store_set_record(self.kinds[kind], record, entity)
	file_record(self, kind, entity, true)
}


world_remove_record :: proc(self: ^World, kind: uint, entity: Entity_ID) {
	if store_record_for(self.kinds[kind], entity) == nil {
		return
	}
	world_forget_seen_as(self, entity)
	journal_record(self, self.kinds[kind], kind, entity)
	file_record(self, kind, entity, false)
	store_remove_record_for(self.kinds[kind], entity)
	touch(self, entity)
}


/* An entity's kind as seen (act_view.odin's kind_of_entity), worked out
 * from its blueprint and its components, which change only as it is made
 * or ended: kept, with the blueprint it was worked out for. */
Seen_As :: struct {
	blueprint: cstring,
	kind:      string,
}


/* A match worked out from text (a pattern and a description, PERFORMANCE.md
 * decision 7): a function of the content alone, so kept, by the text and
 * whatever names the pattern, up to BG_MATCHED of them, then let go. */
Matched :: struct {
	match:  tri.Match,
	result: tri.Match_Result,
}

BG_MATCHED :: 4096


world_matched :: proc(self: ^World, key: string) -> (Matched, bool) {
	return self.matched[key]
}


world_remember_match :: proc(self: ^World, key: string, m: Matched) {
	if len(self.matched) >= BG_MATCHED do world_forget_matched(self)
	self.matched[strings.clone(key)] = m
}


world_forget_matched :: proc(self: ^World) {
	for k in self.matched do delete(k)
	clear(&self.matched)
}


/* Let go of what was recalled (a cache of a pure function of content). */
world_forget_recalled :: proc(self: ^World) {
	for k, v in self.recalled {
		delete(k)
		delete(v)
	}
	clear(&self.recalled)
}


world_forget_seen_as :: proc(self: ^World, entity: Entity_ID) {
	if v, ok := self.seenAs[entity]; ok {
		delete(v.kind)
		delete_key(&self.seenAs, entity)
	}
}


/* Fields by "Kind.field", such as "Body.mass". Numbers, type IDs, booleans
 * and referents read and write as i64. */
world_lookup_field :: proc(self: ^World, path: cstring, kind: ^uint, field: ^^Field_Info) -> bool {
	name: [64]u8

	p := string(path)
	dot := strings.index_byte(p, '.')
	if dot < 0 || dot >= len(name) {
		return false
	}
	mem.copy(&name[0], raw_data(p), dot)
	name[dot] = 0
	k := world_kind_named(self, cstring(&name[0]))
	if k == NOT_FOUND {
		return false
	}
	for i: uint = 0; i < COMPONENTS[k].nfields; i += 1 {
		if string(COMPONENTS[k].fields[i].name) == p[dot + 1:] {
			kind^ = k
			field^ = &COMPONENTS[k].fields[i]
			return true
		}
	}
	return false
}


// What a "changed" event set a field that holds a type to ("Activity.status"),
// that type's name; nil for any other event. Traces, saves and the state
// hash write it so: content renumbers type IDs.
world_event_type_name :: proc(self: ^World, ev: ^Event) -> cstring {
	if ev.kind != "changed" || ev.amount == 0 || !world_field_holds_type(self, ev.detail) do return nil
	return tri.type_name(world_tri(self), tri.Type(ev.amount))
}


// Whether a field ("Plot.stands") holds a type: a union of strings, say.
world_field_holds_type :: proc(self: ^World, path: cstring) -> bool {
	kind: uint
	f:    ^Field_Info

	return path != nil && world_lookup_field(self, path, &kind, &f) && f.value == VALUE_TYPE
}


field_get :: proc(f: ^Field_Info, record: rawptr) -> i64 {
	p := rawptr(uintptr(record) + f.offset)
	switch f.value {
	case VALUE_QUANTITY:
		return (^i64)(p)^
	case VALUE_TYPE:
		return i64((^u32)(p)^)
	case VALUE_BOOL:
		return 1 if (^bool)(p)^ else 0
	case VALUE_REF:
		return i64((^u64)(p)^)
	case:
		return 0
	}
}


@(private = "file")
field_set :: proc(f: ^Field_Info, record: rawptr, value: i64) -> bool {
	p := rawptr(uintptr(record) + f.offset)
	switch f.value {
	case VALUE_QUANTITY:
		(^i64)(p)^ = value
		return true
	case VALUE_TYPE:
		(^u32)(p)^ = u32(value)
		return true
	case VALUE_BOOL:
		(^bool)(p)^ = value != 0
		return true
	case VALUE_REF:
		(^u64)(p)^ = u64(value)
		return true
	case:
		return false
	}
}


world_get_field :: proc(self: ^World, path: cstring, entity: Entity_ID, value: ^i64) -> bool {
	f: ^Field_Info
	k: uint

	if !world_lookup_field(self, path, &k, &f) {
		return false
	}
	record := store_record_for(self.kinds[k], entity)
	if record == nil {
		return false
	}
	value^ = field_get(f, record)
	return true
}


world_set_field_of_value :: proc(self: ^World, path: cstring, entity: Entity_ID, value: i64) -> bool {
	f: ^Field_Info
	k: uint
	copy_: [512]u8

	if !world_lookup_field(self, path, &k, &f) {
		return false
	}
	record := store_record_for(self.kinds[k], entity)
	if record == nil || COMPONENTS[k].size > len(copy_) {
		return false
	}
	mem.copy(&copy_[0], record, int(COMPONENTS[k].size))
	if !field_set(f, &copy_[0], value) {
		return false
	}
	name := string(f.name)
	if k == self.kindGas && len(name) >= 2 && name[0] == 'a' && name[1] == 't' {
		self.airAnchors += 1          /* atX, atY, atLevel: the air's room may move */
	}
	world_set_record(self, &copy_[0], k, entity)
	return true
}


/* a text field; the text is interned */
world_set_field_of_text :: proc(self: ^World, path: cstring, entity: Entity_ID, text: cstring) -> bool {
	f: ^Field_Info
	k: uint
	copy_: [512]u8

	if !world_lookup_field(self, path, &k, &f) || f.value != VALUE_TEXT {
		return false
	}
	record := store_record_for(self.kinds[k], entity)
	if record == nil || COMPONENTS[k].size > len(copy_) {
		return false
	}
	mem.copy(&copy_[0], record, int(COMPONENTS[k].size))
	(^cstring)(&copy_[f.offset])^ = world_intern(self, text) if text != nil else nil
	world_set_record(self, &copy_[0], k, entity)
	return true
}


world_text_field :: proc(self: ^World, path: cstring, entity: Entity_ID) -> cstring {
	f: ^Field_Info
	k: uint

	if !world_lookup_field(self, path, &k, &f) || f.value != VALUE_TEXT {
		return nil
	}
	record := store_record_for(self.kinds[k], entity)
	return (^cstring)(uintptr(record) + f.offset)^ if record != nil else nil
}


/* --- entities -------------------------------------------------------------- */

world_allocate_id :: proc(self: ^World) -> Entity_ID {
	if self.open {
		j := journal_push(self)
		j.op = .Next_ID
		j.value = self.nextID
	}
	id := self.nextID
	self.nextID += 1
	return id
}


world_is_live :: proc(self: ^World, entity: Entity_ID) -> bool {
	return store_record_for(self.entities, entity) != nil
}


world_info :: proc(self: ^World, entity: Entity_ID) -> ^Entity_Info {
	return (^Entity_Info)(store_record_for(self.entities, entity))
}


world_add_entity :: proc(self: ^World, entity: Entity_ID, blueprint: cstring, seed: u64) {
	info: Entity_Info

	info.blueprint = world_intern(self, blueprint)
	info.seed = seed
	journal_record(self, self.entities, KIND_ENTITIES, entity)
	store_set_record(self.entities, &info, entity)
}


/* Builds the entity's components from its blueprint, drawn from its seed.
 * false, with the reason, if the blueprint is unknown or can't be built. */
world_construct :: proc(self: ^World, entity: Entity_ID, error: ^string) -> bool {
	text: [256]u8
	hi: i64
	lo: i64

	info := world_info(self, entity)
	if info == nil {
		return false
	}
	t := world_tri(self)
	mark := tri.arena_mark(self.arena)
	node := tri.construct(t, info.blueprint, info.seed, self.arena)
	if node == nil {
		if error != nil {
			error^ = fmt.tprintf("blueprint %s cannot be built", info.blueprint)
		}
		tri.arena_release(self.arena, mark)
		return false
	}
	type := tri.node_type(node)
	ok := true
	for k: uint = 0; k < self.nkinds && ok; k += 1 {
		if self.kindTypes[k] == tri.BOTTOM || tri.subtype(t, type, self.kindTypes[k]) == 0 {
			continue
		}
		record := make([^]u8, COMPONENTS[k].size)
		for i: uint = 0; i < COMPONENTS[k].nfields && ok; i += 1 {
			f := &COMPONENTS[k].fields[i]
			v := tri.at(t, node, f.name)
			if v == nil {
				continue
			}
			switch f.value {
			case VALUE_REF:
				/* a referent is bound at runtime: left open in a blueprint, it is none */
				if tri.node_interval(v, &lo, &hi) != 0 && lo == hi {
					field_set(f, record, lo)
				}

			case VALUE_QUANTITY:
				if tri.node_interval(v, &lo, &hi) == 0 || lo != hi {
					if error != nil {
						error^ = fmt.tprintf("%s.%s of %s is not concrete",
						                     COMPONENTS[k].name, f.name, info.blueprint)
					}
					ok = false
					break
				}
				field_set(f, record, lo)

			case VALUE_TYPE:
				field_set(f, record, i64(tri.node_type(v)))

			case VALUE_BOOL:
				field_set(f, record, 1 if tri.node_type(v) == self.trueType else 0)

			case VALUE_TEXT:
				n := tri.print(t, v, &text[0], len(text))
				if n >= 2 && n < len(text) && text[0] == '"' {
					text[n - 1] = 0
					(^cstring)(&record[f.offset])^ = world_intern(self, cstring(&text[1]))
				}

			case:
				break      /* structures are not stored yet */
			}
		}
		if ok {
			world_set_record(self, record, k, entity)
		}
		free(record)
	}
	tri.arena_release(self.arena, mark)
	return ok
}


/* Removes every record and the location, and leaves a tombstone. */
world_destroy :: proc(self: ^World, entity: Entity_ID, successor: Entity_ID, cause: u64, reason: cstring) {
	stone: Tombstone

	stone.blueprint = world_info(self, entity).blueprint if world_info(self, entity) != nil else ""
	stone.successor = successor
	stone.cause = cause
	/* strncpy( stone.reason, reason, sizeof( stone.reason) - 1) */
	if reason != nil {
		r := ([^]u8)(reason)
		for i := 0; i < len(stone.reason) - 1 && r[i] != 0; i += 1 {
			stone.reason[i] = r[i]
		}
	}
	for k: uint = 0; k < self.nkinds; k += 1 {
		world_remove_record(self, k, entity)
	}
	world_set_location(self, location_make_none(), entity)
	journal_record(self, self.entities, KIND_ENTITIES, entity)
	store_remove_record_for(self.entities, entity)
	journal_record(self, self.tombstones, KIND_TOMBSTONES, entity)
	store_set_record(self.tombstones, &stone, entity)
}


world_tombstone :: proc(self: ^World, entity: Entity_ID) -> ^Tombstone {
	return (^Tombstone)(store_record_for(self.tombstones, entity))
}


/* The live entity a reference stands for now: itself, or the end of its
 * tombstones' successors. NO_ENTITY if it ended with no successor. */
world_resolve :: proc(self: ^World, entity: Entity_ID) -> Entity_ID {
	entity := entity
	for guard := 0; guard < 1000; guard += 1 {
		if world_is_live(self, entity) {
			return entity
		}
		stone := world_tombstone(self, entity)
		if stone == nil {
			return NO_ENTITY
		}
		entity = stone.successor
	}
	return NO_ENTITY
}


/* Physical entities have a Body. A stack's units are its count, and its unit
 * is its unit blueprint; an individual is one unit of its own blueprint. */
world_is_physical :: proc(self: ^World, entity: Entity_ID) -> bool {
	return world_record(self, world_kind_named(self, "Body"), entity) != nil
}


world_is_stack :: proc(self: ^World, entity: Entity_ID) -> bool {
	return world_record(self, world_kind_named(self, "Stack"), entity) != nil
}


world_unit_of :: proc(self: ^World, entity: Entity_ID) -> cstring {
	stack := (^Stack)(world_record(self, world_kind_named(self, "Stack"), entity))
	if stack != nil {
		return stack.unit
	}
	info := world_info(self, entity)
	return world_unit_of_blueprint(self, info.blueprint) if info != nil else nil
}


/* The unit an individual of a blueprint is one of: the blueprint's name,
 * or, for the instance a unit names, spaces as underscores
 * (unit_blueprint), the unit it says: "hare_meat" is one of "hare meat". */
world_unit_of_blueprint :: proc(self: ^World, blueprint: cstring) -> cstring {
	buf: [256]u8

	if blueprint == nil || !strings.contains_rune(string(blueprint), '_') do return blueprint
	tc      := world_tri(self)
	pattern := tri.pattern(tc, blueprint) if tc != nil else nil
	v       := tri.at(tc, pattern, "unit") if pattern != nil else nil
	if v == nil do return blueprint
	tri.print(tc, v, raw_data(buf[:]), size_of(buf))
	t := string(cstring(raw_data(buf[:])))
	if len(t) < 2 || t[0] != '"' || t[len(t) - 1] != '"' do return blueprint
	return world_intern(self, ns_utf8(t[1:len(t) - 1]))
}


world_units_of :: proc(self: ^World, entity: Entity_ID) -> i64 {
	stack := (^Stack)(world_record(self, world_kind_named(self, "Stack"), entity))
	if stack != nil {
		return stack.count
	}
	return 1 if world_is_live(self, entity) else 0
}


world_mass_of :: proc(self: ^World, entity: Entity_ID) -> i64 {
	body := (^Body)(world_record(self, world_kind_named(self, "Body"), entity))
	return body.mass if body != nil else 0
}


/* --- locations ------------------------------------------------------------- */

world_location_of :: proc(self: ^World, entity: Entity_ID) -> Location {
	loc := (^Location)(store_record_for(self.locations, entity))
	return loc^ if loc != nil else location_make_none()
}


/* The chunk a tile is filed under. */
@(private = "file")
ground_key :: proc(x, y, level: i32) -> u64 {
	return (u64(u32(x >> 5)) << 32) ~ (u64(u32(y >> 5)) << 8) ~ u64(u32(level))
}


/* Files or unfiles an entity where it is (Index). */
@(private = "file")
file_location :: proc(self: ^World, entity: Entity_ID, loc: ^Location, add: bool) {
	index: ^Index
	key: u64

	if loc == nil || loc.form == .None {
		return
	}
	if loc.form == .On_Tile {
		index = self.onGround
		key = ground_key(loc.x, loc.y, loc.level)
	} else {
		index = self.inPlace
		key = loc.place
	}
	if add {
		index_add(index, key, entity)
	} else {
		index_remove(index, key, entity)
	}
}


/* Location_Form.None removes it. */
world_set_location :: proc(self: ^World, location: Location, entity: Entity_ID) {
	location := location
	if location.form == .None && store_record_for(self.locations, entity) == nil {
		return
	}
	journal_record(self, self.locations, KIND_LOCATIONS, entity)
	file_location(self, entity, (^Location)(store_record_for(self.locations, entity)), false)
	vacate(self, (^Location)(store_record_for(self.locations, entity)))
	/* what held it, and what holds it now, have changed too: their contents */
	if store_record_for(self.locations, entity) != nil && (^Location)(store_record_for(self.locations, entity)).form != .On_Tile {
		touch(self, (^Location)(store_record_for(self.locations, entity)).place)
	}
	if location.form != .On_Tile && location.form != .None {
		touch(self, location.place)
	}
	if location.form == .None {
		store_remove_record_for(self.locations, entity)
	} else {
		store_set_record(self.locations, &location, entity)
	}
	file_location(self, entity, (^Location)(store_record_for(self.locations, entity)), true)
	touch(self, entity)
}


/* --- the reality bubble ----------------------------------------------------------- */

/* The bubble's anchors, levels, and leases. */
world_reality :: proc(self: ^World) -> ^Reality {
	return self.reality
}


/* Where a thing stands on the ground, through what holds it. */
@(private = "file")
standing :: proc(self: ^World, e: Entity_ID, tile: ^Location) -> bool {
	e := e
	for guard := 0; e != 0 && guard < 64; guard += 1 {
		at := world_location_of(self, e)
		if at.form == .On_Tile {
			tile^ = at
			return true
		}
		if at.form == .None || at.place == 0 {
			return false
		}
		e = at.place
	}
	return false
}


/* An entity anchors the bubble, of a kind from content (the `anchors`
 * family); false if there is none of that name. Its centre is where it stands
 * at the next boundary (settleAnchors). */
world_set_anchor :: proc(self: ^World, entity: Entity_ID, kind: cstring) -> bool {
	return reality_set_anchor(self.reality, entity, reality_kind_named(self.reality, kind))
}


world_remove_anchor :: proc(self: ^World, entity: Entity_ID) {
	reality_remove_anchor(self.reality, entity)
}


/* Something rose from frozen (REALITY.md step 4): noted, with what it
 * holds, and its activities' timers told to look again. */
@(private = "file")
rise :: proc(self: ^World, e: Entity_ID, depth: uint) {
	n: uint

	if e == 0 || depth > 64 {
		return
	}
	if self.nrisen == self.risencap {
		old := self.risencap
		self.risencap = self.risencap * 2 if self.risencap != 0 else 64
		self.risen = grow(self.risen, old, self.risencap)
	}
	self.risen[self.nrisen] = e
	self.nrisen += 1
	if self.activityObserver.data != nil && world_record(self, self.kindAgent, e) != nil {
		mine := world_copy_activities_of(self, e, &n)
		for i: uint = 0; i < n; i += 1 {
			self.activityObserver.changed_record(self.activityObserver.data, self, mine[i], self.kindActivity)
		}
		free(mine)
	}
	n = world_entities_in(self, e, nil, 0)
	inside := make([^]Entity_ID, n + 1)
	world_entities_in(self, e, inside, n)
	for i: uint = 0; i < n; i += 1 {
		rise(self, inside[i], depth + 1)
	}
	free(inside)
}


/* What rose from frozen as the anchors went from as they were to as they
 * are: over the chunks the moved anchors' reach covered, before or now,
 * each that was frozen and isn't, all that stands there. */
@(private = "file")
rise_from :: proc(self: ^World, before: ^Anchors_Kept) {
	e: Entity_ID
	count: uint
	lo: [3]i32
	hi: [3]i32
	same: bool

	if reality_kept_count(before) == 0 {
		return                                   /* all was full */
	}
	if reality_anchor_count(self.reality) == 0 {
		/* no anchors now: all is full; whatever was frozen rose */
		for i: uint = 0; i < store_count(self.locations); i += 1 {
			loc := (^Location)(store_record_at_index(self.locations, i))
			if loc.form == .On_Tile &&
			   reality_detail_kept(self.reality, before, loc.x, loc.y, loc.level) == .Frozen {
				rise(self, store_entity_at_index(self.locations, i), 0)
			}
		}
		return
	}
	for pass := 0; pass < 2; pass += 1 {
		for k: uint = 0; k < (reality_anchor_count(self.reality) if pass != 0 else reality_kept_count(before)); k += 1 {
			if !reality_kept_box(self.reality, nil if pass != 0 else before, k, &e, &lo, &hi, &same) {
				continue
			}
			if pass != 0 {
				same = reality_kept_same(self.reality, before, k)
			}
			if same {
				continue
			}
			for z := 0 if lo[2] < 0 else lo[2]; z <= hi[2] && z < self.levels; z += 1 {
				for cy := lo[1]; cy <= hi[1]; cy += 1 {
					for cx := lo[0]; cx <= hi[0]; cx += 1 {
						if cx < 0 || cy < 0 || cx * 32 >= self.tilesWide || cy * 32 >= self.tilesHigh ||
						   reality_detail_kept(self.reality, before, cx * 32, cy * 32, z) != .Frozen ||
						   reality_detail_at(self.reality, cx * 32, cy * 32, z) == .Frozen {
							continue
						}
						ids := index_get(self.onGround, ground_key(cx * 32, cy * 32, z), &count)
						for i: uint = 0; i < count; i += 1 {
							rise(self, ids[i], 0)
						}
					}
				}
			}
		}
	}
}


/* Each anchor's centre moved to where it stands, past its margin; leases
 * ended let go. Once a boundary. */
world_settle_anchors :: proc(self: ^World) {
	tile: Location

	for i: uint = 0; i < reality_anchor_count(self.reality); i += 1 {
		e := reality_anchor_at(self.reality, i, nil, nil, nil, nil, nil)
		if standing(self, e, &tile) {
			reality_centre(self.reality, e, tile.x, tile.y, tile.level)
		}
	}
	reality_prune(self.reality, self.time.ms)
	rise_from(self, self.settled)
	free(self.settled)
	self.settled = reality_keep_anchors(self.reality)
}


/* The anchors as they are, taken as settled: a save restored. */
world_mark_anchors_settled :: proc(self: ^World) {
	free(self.settled)
	self.settled = reality_keep_anchors(self.reality)
}


/* What rose from frozen since the last call (the anchors moved, a lease
 * began), and what it holds: malloc'd, in entity order, each once. Its
 * activities have been told (the activity observer). The caller frees it. */
world_take_risen :: proc(self: ^World, n: ^uint) -> [^]Entity_ID {
	list := self.risen if self.risen != nil else make([^]Entity_ID, 1)
	slice.sort(list[:self.nrisen])
	k: uint = 0
	for i: uint = 0; i < self.nrisen; i += 1 {
		if k == 0 || list[k - 1] != list[i] {
			list[k] = list[i]
			k += 1
		}
	}
	n^ = k
	self.risen = nil
	self.nrisen = 0
	self.risencap = 0
	return list
}


/* The level of detail (a Detail) at a tile; of an entity, where it
 * stands, or full while a lease runs, or with no place on the ground. */
world_detail_at :: proc(self: ^World, tile: Location) -> i32 {
	if tile.form != .On_Tile {
		return i32(Detail.Full)
	}
	return i32(reality_detail_at(self.reality, tile.x, tile.y, tile.level))
}


world_detail_of :: proc(self: ^World, entity: Entity_ID) -> i32 {
	tile: Location

	if reality_anchor_count(self.reality) == 0 || reality_lease_of(self.reality, entity) > self.time.ms ||
	   !standing(self, entity, &tile) {
		return i32(Detail.Full)
	}
	return i32(reality_detail_at(self.reality, tile.x, tile.y, tile.level))
}


/* Contact (content's `contact`): each event from `first` between something
 * at full detail and something not leases the other to full. */
world_lease_contacts_from :: proc(self: ^World, first: uint) {
	party: [3]Entity_ID
	detail: [3]i32

	if reality_anchor_count(self.reality) == 0 {
		return
	}
	until := self.time.ms + reality_contact_lease(self.reality)
	for i := first; i < uint(len(self.events)); i += 1 {
		ev := &self.events[i]
		if !reality_is_contact(self.reality, ev.kind) {
			continue
		}
		party[0] = ev.actor
		party[1] = ev.subject
		party[2] = ev.other
		for k := 0; k < 3; k += 1 {
			detail[k] = world_detail_of(self, party[k]) if party[k] != 0 else i32(Detail.Frozen)
		}
		/* one at full detail: the others, raised; from frozen, risen */
		for k := 0; k < 3; k += 1 {
			if party[k] != 0 && detail[k] == i32(Detail.Full) {
				for j := 0; j < 3; j += 1 {
					if party[j] != 0 && detail[j] != i32(Detail.Full) {
						reality_lease(self.reality, party[j], until)
						if detail[j] == i32(Detail.Frozen) {
							rise(self, party[j], 0)
						}
						detail[j] = i32(Detail.Full)
					}
				}
			}
		}
	}
}


/* One observer of the Activity records, told of every change (activities'
 * timers); not retained, so it unsets itself as it goes. */
world_set_activity_observer :: proc(self: ^World, observer: Record_Observer) {
	self.activityObserver = observer
}


world_activity_observer :: proc(self: ^World) -> Record_Observer {
	return self.activityObserver
}


/* The ground tiles things left since the last call (moved off, or out of
 * what stood there), each as often as left: malloc'd, n^ of them; the caller
 * frees it. */
world_take_vacated :: proc(self: ^World, n: ^uint) -> [^]Location {
	list := self.vacated if self.vacated != nil else make([^]Location, 1)
	n^ = self.nvacated
	self.vacated = nil
	self.nvacated = 0
	self.vacatedcap = 0
	return list
}


/* The entities whose records or location changed since the last call, in
 * entity order, each once (REALITY.md decision 7: work when something
 * happens): malloc'd, n^ of them; the record starts again. The caller frees
 * it. */
world_take_touched :: proc(self: ^World, n: ^uint) -> [^]Entity_ID {
	list := self.touched
	if self.ntouched != 0 {
		slice.sort(list[:self.ntouched])
	}
	k: uint = 0
	for i: uint = 0; i < self.ntouched; i += 1 {
		if k == 0 || list[k - 1] != list[i] {
			list[k] = list[i]
			k += 1
		}
	}
	n^ = k
	self.touched = nil
	self.ntouched = 0
	self.touchedcap = 0
	return list if list != nil else make([^]Entity_ID, 1)
}


/* Entities located at `place` in the given form, in ID order. */
world_entities_at :: proc(self: ^World, place: Entity_ID, form: Location_Form, out: [^]Entity_ID, max_: uint) -> uint {
	count: uint

	ids := index_get(self.inPlace, place, &count)
	n: uint = 0
	for i: uint = 0; i < count; i += 1 {
		loc := (^Location)(store_record_for(self.locations, ids[i]))
		if loc == nil || loc.form != form || loc.place != place {
			continue
		}
		if n < max_ {
			out[n] = ids[i]
		}
		n += 1
	}
	return n
}


/* What is within `radius` of a tile, all of it: on the ground there, and
 * what is in, on, held by or part of that, all the way down. Malloc'd into
 * out^, in no set order; returns how many. The caller frees it. */
world_things_near :: proc(self: ^World, tile: Location, radius: i32, out: ^[^]Entity_ID) -> uint {
	n := world_entities_near(self, tile, radius, nil, 0)
	cap := n + 16
	list := make([^]Entity_ID, cap)
	n = world_entities_near(self, tile, radius, list, cap)
	for i: uint = 0; i < n; i += 1 {
		m := world_entities_in(self, list[i], nil, 0)
		if n + m > cap {
			old := cap
			cap = (n + m) * 2
			list = grow(list, old, cap)
		}
		n += world_entities_in(self, list[i], list[n:], m)
	}
	out^ = list
	return n
}


/* The traces within `radius` of a tile: on the floor there, or borne by
 * what is there (thingsNear). Malloc'd into out^, in entity order. The
 * caller frees it. */
world_traces_near :: proc(self: ^World, tile: Location, radius: i32, out: ^[^]Entity_ID) -> uint {
	things: [^]Entity_ID
	count: uint

	cap: uint = 64
	list := make([^]Entity_ID, cap)
	n: uint = 0
	if tile.form == .On_Tile && radius >= 0 && self.kindTrace < self.nkinds {
		for cy := (tile.y - radius) >> 5; cy <= (tile.y + radius) >> 5; cy += 1 {
			for cx := (tile.x - radius) >> 5; cx <= (tile.x + radius) >> 5; cx += 1 {
				ids := index_get(self.tracesOnGround, ground_key(cx * BG_CHUNK, cy * BG_CHUNK, tile.level), &count)
				for i: uint = 0; i < count; i += 1 {
					trace := (^Trace)(store_record_for(self.kinds[self.kindTrace], ids[i]))
					if trace == nil || trace.bearer != 0 || trace.tileLevel != i64(tile.level) ||
					   abs(trace.tileX - i64(tile.x)) > i64(radius) || abs(trace.tileY - i64(tile.y)) > i64(radius) {
						continue
					}
					if n == cap {
						list = grow(list, cap, cap * 2)
						cap *= 2
					}
					list[n] = ids[i]
					n += 1
				}
			}
		}
		nthings := world_things_near(self, tile, radius, &things)
		for k: uint = 0; k < nthings; k += 1 {
			ids := index_get(self.tracesBorne, things[k], &count)
			for i: uint = 0; i < count; i += 1 {
				if n == cap {
					list = grow(list, cap, cap * 2)
					cap *= 2
				}
				list[n] = ids[i]
				n += 1
			}
		}
		free(things)
	}
	slice.sort(list[:n])
	out^ = list
	return n
}


@(private = "file")
index_list :: proc(index: ^Index, key: u64, out: [^]Entity_ID, max_: uint) -> uint {
	count: uint

	ids := index_get(index, key, &count)
	for i: uint = 0; i < count && i < max_; i += 1 {
		out[i] = ids[i]
	}
	return count
}


/* An actor's activities, of every status, in entity order: returns how
 * many, filling up to max. */
world_activities_of :: proc(self: ^World, actor: Entity_ID, out: [^]Entity_ID, max_: uint) -> uint {
	return index_list(self.activitiesOf, actor, out, max_)
}


/* The activities with a watch (a holder's stock, a tile, the air), of
 * every status, in entity order. */
world_watching_activities :: proc(self: ^World, out: [^]Entity_ID, max_: uint) -> uint {
	return index_list(self.watching, 0, out, max_)
}


@(private = "file")
index_copy :: proc(index: ^Index, key: u64, n: ^uint) -> [^]Entity_ID {
	n^ = index_list(index, key, nil, 0)
	list := make([^]Entity_ID, n^ if n^ != 0 else 1)
	index_list(index, key, list, n^)
	return list
}


/* The same, malloc'd: n^ of them; the caller frees it. */
world_copy_activities_of :: proc(self: ^World, actor: Entity_ID, n: ^uint) -> [^]Entity_ID {
	return index_copy(self.activitiesOf, actor, n)
}


/* The activities an entity takes part in, as actor, item or destination,
 * in entity order, malloc'd: n^ of them. */
world_copy_activities_touching :: proc(self: ^World, entity: Entity_ID, n: ^uint) -> [^]Entity_ID {
	return index_copy(self.touching, entity, n)
}


world_copy_watching_activities :: proc(self: ^World, n: ^uint) -> [^]Entity_ID {
	return index_copy(self.watching, 0, n)
}


/* What is in, on, held by or part of a thing, any way, in entity order. */
world_entities_in :: proc(self: ^World, place: Entity_ID, out: [^]Entity_ID, max_: uint) -> uint {
	count: uint

	ids := index_get(self.inPlace, place, &count)
	for i: uint = 0; i < count && i < max_; i += 1 {
		out[i] = ids[i]
	}
	return count
}


/* What stands on the ground at a tile, in entity order: returns how many,
 * filling up to max. */
world_entities_on_tile :: proc(self: ^World, tile: Location, out: [^]Entity_ID, max_: uint) -> uint {
	return world_entities_near(self, tile, 0, out, max_)
}


/* What stands on the ground within `radius` tiles of a tile (corners too),
 * on its level, in entity order. A spatial query: it reads the chunks the
 * square touches, nothing else. */
world_entities_near :: proc(self: ^World, tile: Location, radius: i32, out: [^]Entity_ID, max_: uint) -> uint {
	count: uint

	if tile.form != .On_Tile || radius < 0 {
		return 0
	}
	n: uint = 0
	sorted := true
	for cy := (tile.y - radius) >> 5; cy <= (tile.y + radius) >> 5; cy += 1 {
		for cx := (tile.x - radius) >> 5; cx <= (tile.x + radius) >> 5; cx += 1 {
			ids := index_get(self.onGround, ground_key(cx * BG_CHUNK, cy * BG_CHUNK, tile.level), &count)
			for i: uint = 0; i < count; i += 1 {
				loc := (^Location)(store_record_for(self.locations, ids[i]))
				if loc == nil || loc.form != .On_Tile || loc.level != tile.level ||
				   abs(loc.x - tile.x) > radius || abs(loc.y - tile.y) > radius {
					continue
				}
				if n < max_ {
					if n != 0 && out[n - 1] > ids[i] {
						sorted = false
					}
					out[n] = ids[i]
				}
				n += 1
			}
		}
	}
	/* an area whose corner is farther, but some of whose tiles are within
	 * it (content/things.tri's #Area) */
	areas := world_store_for_kind(self, world_kind_named(self, "Area"))
	for i: uint = 0; areas != nil && i < store_count(areas); i += 1 {
		e   := store_entity_at_index(areas, i)
		a   := (^Area)(store_record_at_index(areas, i))
		loc := (^Location)(store_record_for(self.locations, e))
		if loc == nil || loc.form != .On_Tile || loc.level != tile.level ||
		   (abs(loc.x - tile.x) <= radius && abs(loc.y - tile.y) <= radius) {
			continue       /* not on the ground, or counted already */
		}
		near := area_nearest(loc^, i32(a.east), i32(a.south), tile)
		if abs(near.x - tile.x) > radius || abs(near.y - tile.y) > radius do continue
		if n < max_ {
			if n != 0 && out[n - 1] > e do sorted = false
			out[n] = e
		}
		n += 1
	}
	if !sorted {
		slice.sort(out[:n if n < max_ else max_])
	}
	return n
}


/* An #Area's extent (content/things.tri): tiles east and south from the
 * tile it is placed on; 1 by 1 for anything else. */
world_area_extent :: proc(self: ^World, e: Entity_ID) -> (east: i32, south: i32) {
	a := (^Area)(world_record(self, world_kind_named(self, "Area"), e))
	if a == nil do return 1, 1
	return i32(a.east), i32(a.south)
}


/* The tile of an area, placed at `corner`, nearest a tile. */
area_nearest :: proc(corner: Location, east: i32, south: i32, to: Location) -> Location {
	t  := corner
	t.x = clamp(to.x, corner.x, corner.x + max(east, 1) - 1)
	t.y = clamp(to.y, corner.y, corner.y + max(south, 1) - 1)
	return t
}


world_locations :: proc(self: ^World) -> ^Store {
	return self.locations
}


/* --- edges ----------------------------------------------------------------- */

@(private = "file")
cmp_edge :: proc(a, b: Edge) -> int {
	if a.kind != b.kind {
		return -1 if a.kind < b.kind else 1
	}
	if a.from != b.from {
		return -1 if a.from < b.from else 1
	}
	if a.to != b.to {
		return -1 if a.to < b.to else 1
	}
	return 0
}


@(private = "file")
edge_position :: proc(self: ^World, e: Edge, found: ^bool) -> uint {
	lo: uint = 0
	hi := uint(len(self.edges))
	for lo < hi {
		mid := (lo + hi) / 2
		if cmp_edge(self.edges[mid], e) < 0 {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	found^ = lo < uint(len(self.edges)) && cmp_edge(self.edges[lo], e) == 0
	return lo
}


@(private = "file")
edge_insert_raw :: proc(self: ^World, e: Edge) {
	found: bool

	i := edge_position(self, e, &found)
	if found {
		return
	}
	inject_at(&self.edges, int(i), e)
}


@(private = "file")
edge_remove_raw :: proc(self: ^World, e: Edge) {
	found: bool

	i := edge_position(self, e, &found)
	if !found {
		return
	}
	ordered_remove(&self.edges, int(i))
}


world_has_edge :: proc(self: ^World, kind: Edge_Kind, from: Entity_ID, to: Entity_ID) -> bool {
	found: bool

	edge_position(self, Edge{kind, from, to}, &found)
	return found
}


world_add_edge :: proc(self: ^World, kind: Edge_Kind, from: Entity_ID, to: Entity_ID) {
	if world_has_edge(self, kind, from, to) {
		return
	}
	e := Edge{kind, from, to}
	if self.open {
		j := journal_push(self)
		j.op = .Edge_Add
		j.edge = e
	}
	edge_insert_raw(self, e)
}


world_remove_edge :: proc(self: ^World, kind: Edge_Kind, from: Entity_ID, to: Entity_ID) {
	if !world_has_edge(self, kind, from, to) {
		return
	}
	e := Edge{kind, from, to}
	if self.open {
		j := journal_push(self)
		j.op = .Edge_Remove
		j.edge = e
	}
	edge_remove_raw(self, e)
}


/* in ID order */
world_edges_from :: proc(self: ^World, kind: Edge_Kind, from: Entity_ID, out: [^]Entity_ID, max_: uint) -> uint {
	n: uint = 0
	for i := 0; i < len(self.edges); i += 1 {
		if self.edges[i].kind == kind && self.edges[i].from == from {
			if n < max_ {
				out[n] = self.edges[i].to
			}
			n += 1
		}
	}
	return n
}


world_edges_to :: proc(self: ^World, kind: Edge_Kind, to: Entity_ID, out: [^]Entity_ID, max_: uint) -> uint {
	n: uint = 0
	for i := 0; i < len(self.edges); i += 1 {
		if self.edges[i].kind == kind && self.edges[i].to == to {
			if n < max_ {
				out[n] = self.edges[i].from
			}
			n += 1
		}
	}
	return n
}


/* --- tiles ----------------------------------------------------------------- */

/* --- terrain --------------------------------------------------------------- */

/* What each tile is: open floor, unless a map was set. nil if content
 * declares no terrain kinds. */
world_terrain :: proc(self: ^World) -> ^Terrain {
	return self.terrain
}


world_tiles_wide :: proc(self: ^World) -> i32 {return self.tilesWide}
world_tiles_high :: proc(self: ^World) -> i32 {return self.tilesHigh}
world_levels :: proc(self: ^World) -> i32 {return self.levels}


/* Draws the world from a map in content: its terrain, and the world's extent
 * from the drawing. Only before any tile holds a stock (at setup, or
 * restoring); false with the reason otherwise, or if the map is malformed. */
world_set_terrain_map :: proc(self: ^World, map_: cstring, error: ^string) -> bool {
	why: string

	if stocks_any(self.stocks) {
		if error != nil {
			error^ = "a map is drawn before any tile holds a stock"
		}
		return false
	}
	t := terrain_from_map(self.content, map_, self.seed, &why)
	if t == nil {
		if error != nil {
			error^ = why
		}
		return false
	}
	terrain_free(self.terrain)
	self.terrain = t
	self.roomAirKnown = false
	self.tilesWide = terrain_wide(t)
	self.tilesHigh = terrain_high(t)
	self.levels = terrain_levels(t)
	return true
}


/* The level one stands at on a tile (its highest cell with a floor that
 * isn't solid), or 0 if there is nowhere to stand on it. */
world_ground_level :: proc(self: ^World, x: i32, y: i32) -> i32 {
	if self.terrain == nil do return 0
	z, _ := terrain_ground_level(self.terrain, x, y)
	return z
}


/* The region of air over a tile (content/air/air.tri, TERRAIN.md step 3):
 * the GasStore whose tile is in the tile's room; none outdoors, or on a wall
 * or doorway. */
world_air_region_at :: proc(self: ^World, tile: Location) -> Entity_ID {
	if (tile.form != .On_Tile && tile.form != .None) || self.terrain == nil {
		return NO_ENTITY
	}
	return world_air_of_room(self, terrain_room_at(self.terrain, tile.x, tile.y, tile.level))
}


/* Each room's air, kept while no region of air has come or gone or had its
 * tile set, and no room was let go: its stocks change every step, and
 * leave it be. A region's room is found again, and any other has none. */
/* A room's air, by its number (terrain_room_at); none if it has none. */
world_air_of_room :: proc(self: ^World, room: u32) -> Entity_ID {
	if room == 0 || self.terrain == nil {
		return NO_ENTITY
	}
	stores := world_store_for_kind(self, world_kind_named(self, "GasStore"))
	if !self.roomAirKnown || self.roomAirChanges != store_members(stores) + self.airAnchors ||
	   self.roomAirDropped != terrain_rooms_dropped(self.terrain) {
		if self.nroomAir != 0 {
			mem.zero(self.roomAir, int(self.nroomAir) * size_of(Entity_ID))
		}
		for i: uint = 0; i < store_count(stores); i += 1 {
			gas := (^Gas_Store)(store_record_at_index(stores, i))
			r := terrain_room_at(self.terrain, i32(gas.atX), i32(gas.atY), i32(gas.atLevel))
			if r == 0 {
				continue
			}
			if r > self.nroomAir {
				self.roomAir = grow(self.roomAir, uint(self.nroomAir), uint(r))
				mem.zero(&self.roomAir[self.nroomAir], int(r - self.nroomAir) * size_of(Entity_ID))
				self.nroomAir = r
			}
			if self.roomAir[r - 1] == 0 {
				self.roomAir[r - 1] = store_entity_at_index(stores, i)
			}
		}
		self.roomAirChanges = store_members(stores) + self.airAnchors
		self.roomAirDropped = terrain_rooms_dropped(self.terrain)
		self.roomAirKnown = true
	}
	return self.roomAir[room - 1] if room <= self.nroomAir else NO_ENTITY
}


/* The room a region of air fills: its tile's; 0 if that is in none (a
 * room opened to the outdoors). */
world_room_of_air :: proc(self: ^World, region: Entity_ID) -> u32 {
	gas := (^Gas_Store)(world_record(self, world_kind_named(self, "GasStore"), region))
	if gas == nil || self.terrain == nil {
		return 0
	}
	return terrain_room_at(self.terrain, i32(gas.atX), i32(gas.atY), i32(gas.atLevel))
}


/* The door standing on a tile, or none. */
@(private = "file")
world_door_on_tile :: proc(self: ^World, tile: Location) -> Entity_ID {
	here: [32]Entity_ID

	n := world_entities_on_tile(self, tile, &here[0], 32)
	for i: uint = 0; i < n && i < 32; i += 1 {
		if world_record(self, world_kind_named(self, "Door"), here[i]) != nil {
			return here[i]
		}
	}
	return NO_ENTITY
}


/* The ways a region of air opens (TERRAIN.md step 3): one for each doorway
 * at its room's side and each room beyond it. Returns how many; fills up to
 * max. */
world_air_openings_of :: proc(self: ^World, region: Entity_ID, out: [^]Air_Opening, max_: uint) -> uint {
	@(static, rodata) dx := [4]i32{1, -1, 0, 0}
	@(static, rodata) dy := [4]i32{0, 0, 1, -1}
	o: Air_Opening

	room := world_room_of_air(self, region)
	if room == 0 {
		return 0
	}
	ndoors := terrain_room_doorways(self.terrain, room, nil, 0)
	cells := make([^][3]i32, ndoors if ndoors != 0 else 1)
	terrain_room_doorways(self.terrain, room, cells, ndoors)
	n: uint = 0
	for i: uint = 0; i < ndoors; i += 1 {
		o = {}
		o.at = on_tile(cells[i][0], cells[i][1], cells[i][2])
		o.door = world_door_on_tile(self, o.at)
		kind := terrain_kind_info(self.terrain, terrain_at(self.terrain, o.at.x, o.at.y, o.at.level))
		door := (^Door)(world_record(self, world_kind_named(self, "Door"), o.door)) if o.door != 0 else nil
		o.open = door == nil || door.ajar
		o.flow = (door.wide if door.ajar else 0) if door != nil else (kind.draught if kind != nil else 0)
		first := n
		for d := 0; d < 4; d += 1 {
			u := o.at.x + dx[d]
			v := o.at.y + dy[d]
			if u >= 0 && v >= 0 && u < self.tilesWide && v < self.tilesHigh && !terrain_roomy(self.terrain, u, v, o.at.level) {
				continue
			}
			side := terrain_room_at(self.terrain, u, v, o.at.level)
			if side == room {
				continue
			}
			o.beyond = world_air_of_room(self, side)
			j := first
			for ; j < n && j < max_ && out[j].beyond != o.beyond; j += 1 {
			}
			if j < n && j < max_ {
				continue
			}
			if n < max_ {
				out[n] = o
			}
			n += 1
		}
	}
	free(cells)
	return n
}


/* Whether a region of air is shut in: none of its doorways open (no door,
 * or the door ajar). */
world_air_is_shut_in :: proc(self: ^World, region: Entity_ID) -> bool {
	n := world_air_openings_of(self, region, nil, 0)
	openings := make([^]Air_Opening, n if n != 0 else 1)
	world_air_openings_of(self, region, openings, n)
	shut := true
	for i: uint = 0; i < n && shut; i += 1 {
		shut = !openings[i].open
	}
	free(openings)
	return shut
}


/* Whether one region (none: the outdoors) opens to the other through a
 * doorway standing open. (-airRegion:opensOpenTo:) */
world_air_region :: proc(self: ^World, a: Entity_ID, b: Entity_ID) -> bool {
	from := a if a != 0 else b
	to := b if a != 0 else a
	n := world_air_openings_of(self, from, nil, 0)
	openings := make([^]Air_Opening, n if n != 0 else 1)
	world_air_openings_of(self, from, openings, n)
	open := false
	for i: uint = 0; i < n && !open; i += 1 {
		open = openings[i].beyond == to && openings[i].open
	}
	free(openings)
	return open
}


/* A cell's kind by name, journaled like any change while a group is open:
 * change commitment's, or a save restoring. false for an unknown kind or a
 * cell outside the map. */
world_set_terrain :: proc(self: ^World, kind: cstring, x: i32, y: i32, level: i32) -> bool {
	k: Terrain_Kind

	if self.terrain == nil {
		return false
	}
	k = terrain_kind_named(self.terrain, kind)
	if k == 0 || !world_is_tile_x(self, x, y, level) {
		return false
	}
	was := terrain_set(self.terrain, x, y, level, k)
	if self.open && was != k {
		j := journal_push(self)
		j.op = .Terrain
		j.value = u64(was)
		j.tile = on_tile(x, y, level)
	}
	return true
}


/* The map: 32 × 32 tiles on one level, unless a terrain map says otherwise.
 * Tiles hold stocks; water is the first, kept per chunk only where a tile
 * was ever wet. A tile outside the map holds nothing and takes nothing. */
world_is_tile_x :: proc(self: ^World, x: i32, y: i32, level: i32) -> bool {
	return x >= 0 && x < self.tilesWide && y >= 0 && y < self.tilesHigh && level >= 0 && level < self.levels
}


world_water_at_x :: proc(self: ^World, x: i32, y: i32, level: i32) -> i64 {
	if !world_is_tile_x(self, x, y, level) {
		return 0
	}
	return stocks_cell(self.stocks, x, y, level, false)^ if stocks_cell(self.stocks, x, y, level, false) != nil else 0
}


/* Only a domain checking in, or a save being restored, writes a tile stock
 * directly; at rest, stocks change through commitment. */
world_set_water :: proc(self: ^World, water: i64, x: i32, y: i32, level: i32) {
	if world_is_tile_x(self, x, y, level) {
		cell := stocks_cell(self.stocks, x, y, level, water != 0)
		if cell != nil {
			cell^ = water
		}
	}
}


/* the water in tiles whose stock is at rest */
world_total_tile_water :: proc(self: ^World) -> i64 {
	return stocks_total(self.stocks)
}


world_is_tile_checked_out_x :: proc(self: ^World, x: i32, y: i32, level: i32) -> bool {
	if !world_is_tile_x(self, x, y, level) {
		return false
	}
	out := stocks_out(self.stocks, x, y, level, false)
	return out != nil && out^ != 0
}


world_set_tile_checked_out :: proc(self: ^World, flag: bool, x: i32, y: i32, level: i32) {
	if world_is_tile_x(self, x, y, level) {
		out := stocks_out(self.stocks, x, y, level, flag)
		if out != nil {
			out^ = 1 if flag else 0
		}
	}
}


/* The tiles holding water, by level, then row, then column: returns how
 * many, filling up to max. Costs what is wet, not the map. */
world_wet_tiles :: proc(self: ^World, out: [^][3]i32, max_: uint) -> uint {
	return stocks_wet(self.stocks, out, max_)
}


/* --- checkout -------------------------------------------------------------- */

/* A holder whose stock a domain has checked out: the domain's value is
 * authoritative, and commitment refuses to change the holder's. */
world_is_checked_out :: proc(self: ^World, entity: Entity_ID) -> bool {
	for i := 0; i < len(self.checkedOut); i += 1 {
		if self.checkedOut[i] == entity {
			return true
		}
	}
	return false
}


world_set_checked_out :: proc(self: ^World, flag: bool, entity: Entity_ID) {
	i := 0
	for ; i < len(self.checkedOut) && self.checkedOut[i] < entity; i += 1 {
	}
	if flag {
		if i < len(self.checkedOut) && self.checkedOut[i] == entity {
			return
		}
		inject_at(&self.checkedOut, i, entity)
		return
	}
	if i < len(self.checkedOut) && self.checkedOut[i] == entity {
		ordered_remove(&self.checkedOut, i)
	}
}


/* --- claims ---------------------------------------------------------------- */

/* The sum of the quantities of the claims on an entity. */
world_claimed_units_of :: proc(self: ^World, entity: Entity_ID) -> i64 {
	claims: [64]Entity_ID

	n := world_edges_to(self, .Claim_Subject, entity, &claims[0], 64)
	sum: i64 = 0
	for i: uint = 0; i < n && i < 64; i += 1 {
		claim := (^Claim)(world_record(self, world_kind_named(self, "Claim"), claims[i]))
		if claim != nil {
			sum += claim.quantity
		}
	}
	return sum
}


/* Whether it is settled which units a claim covers: it has one subject, or
 * it is the only claim on its subjects and its quantity covers all their
 * units. After a split of mixed goods it is not, and that stays explicit
 * until an institution decides (§6). */
world_claim_allocation_resolved :: proc(self: ^World, claim: Entity_ID) -> bool {
	others: [64]Entity_ID
	subjects: [64]Entity_ID

	record := (^Claim)(world_record(self, world_kind_named(self, "Claim"), claim))
	if record == nil {
		return false
	}
	n := world_edges_from(self, .Claim_Subject, claim, &subjects[0], 64)
	if n <= 1 {
		return true
	}
	units: i64 = 0
	for i: uint = 0; i < n && i < 64; i += 1 {
		m := world_edges_to(self, .Claim_Subject, subjects[i], &others[0], 64)
		for j: uint = 0; j < m && j < 64; j += 1 {
			if others[j] != claim {
				return false
			}
		}
		units += world_units_of(self, subjects[i])
	}
	return units == record.quantity
}


/* --- history --------------------------------------------------------------- */

/* Whether worlds made from now on log their debug fields' changes in history
 * (`lab --debug-history`): debug-level information, otherwise not kept
 * (KNOWLEDGE.md decision 21). */
debug_history: bool


/* Whether a field's changes are logged in history: a debug field's are not,
 * unless the world asks for them. */
world_logs_field :: proc(self: ^World, f: ^Field_Info) -> bool {
	return self.debugHistory || f.flags == nil || !strings.contains(string(f.flags), "debug")
}


/* Appends the event, giving it the next index, which it returns. */
world_emit :: proc(self: ^World, event: Event) -> u64 {
	event := event
	if self.open {
		j := journal_push(self)
		j.op = .Events
		j.value = self.nextEvent
	}
	event.index = self.nextEvent
	self.nextEvent += 1
	append(&self.events, event)
	if event.subject != 0 && event.kind != nil && string(event.kind) == "created" {
		index_add(self.creations, event.subject, Entity_ID(event.index))
	}
	return event.index
}


/* The index of the event that created an entity, or 0: found without
 * reading the history. */
world_creation_of :: proc(self: ^World, entity: Entity_ID) -> u64 {
	n: uint

	/* the latest noted that is still so (a group rolled back takes its
	 * events with it, and later ones take their places) */
	known := index_get(self.creations, entity, &n)
	for i := n; i > 0; {
		i -= 1
		ev := world_event_at(self, uint(known[i]) - 1)
		if ev != nil && ev.subject == entity && string(ev.kind) == "created" {
			return ev.index
		}
	}
	/* not noted (a save restored): read the history, once, and note it */
	for i := len(self.events) - 1; i >= 0; i -= 1 {
		if self.events[i].subject == entity && string(self.events[i].kind) == "created" {
			index_add(self.creations, entity, Entity_ID(self.events[i].index))
			return self.events[i].index
		}
	}
	return 0
}


/* How many events there have ever been: the last one's index. Some of the
 * older may be compacted (world_event_at says nil). */
world_event_count :: proc(self: ^World) -> uint {
	return uint(self.nextEvent - 1)
}


/* The events kept, in index order: for reading all of history. */
world_history :: proc(self: ^World) -> []Event {
	return self.events[:]
}


/* The event with index i + 1, or nil: none yet, or compacted. */
world_event_at :: proc(self: ^World, i: uint) -> ^Event {
	index := u64(i) + 1
	if index >= self.nextEvent do return nil
	if index >= self.whole {
		at := self.windowAt + int(index - self.whole)
		return &self.events[at] if at < len(self.events) else nil
	}
	/* older: history, found by its index; a diagnostic one is gone */
	lo, hi := 0, self.windowAt
	for lo < hi {
		mid := (lo + hi) / 2
		if self.events[mid].index < index do lo = mid + 1
		else do hi = mid
	}
	return &self.events[lo] if lo < self.windowAt && self.events[lo].index == index else nil
}


/* --- compacting history (KNOWLEDGE.md decision 21) -------------------------- */

/* A diagnostic event's count, once it is compacted: how many of a kind,
 * by an actor, in a chunk, over a window of time. */
Digest :: struct {
	from:   i64,            /* ms: the window it was emitted in */
	until:  i64,
	placed: bool,           /* on the ground: in the chunk at (cx, cy, level) */
	cx:     i32,
	cy:     i32,
	level:  i32,
	kind:   cstring,        /* interned */
	detail: cstring,        /* interned, or nil */
	actor:  Entity_ID,
	count:  u64,
	first:  u64,            /* the first and last event's index */
	last:   u64,
}


/* Diagnostic events are kept `window` ms at least, then compacted: from then
 * on, at each multiple of the window. 0: kept for good (the default). */
world_set_history_window :: proc(self: ^World, window: i64) {
	self.historyWindow = window
	self.compactAt     = (self.time.ms / window + 1) * window if window > 0 else 0
}


world_history_window :: proc(self: ^World) -> i64 {
	return self.historyWindow
}


/* Where history stands, for a save: its window, when it is next
 * compacted, the first index kept whole, the first compacted next time, and
 * the next index. */
world_history_place :: proc(self: ^World) -> (window: i64, compactAt: i64, whole: u64, due: u64, next: u64) {
	return self.historyWindow, self.compactAt, self.whole, self.compactDue, self.nextEvent
}


world_digests :: proc(self: ^World) -> []Digest {
	return self.digests[:]
}


/* At a boundary: compacted, if it is time. The events before the last
 * compaction are compacted now: what is diagnostic goes, counted into
 * digests; history stays, with its index. So a diagnostic event is kept a
 * window at least, and two at most. */
world_compact_history_if_due :: proc(self: ^World) {
	if self.historyWindow <= 0 || self.time.ms < self.compactAt do return
	from := self.compactAt - 2 * self.historyWindow
	until := self.compactAt - self.historyWindow
	for self.compactAt <= self.time.ms do self.compactAt += self.historyWindow
	if self.compactDue > self.whole do world_compact_before(self, self.compactDue, from, until)
	self.compactDue = self.nextEvent
}


@(private = "file")
Digest_Key :: struct {
	placed: bool,
	cx:     i32,
	cy:     i32,
	level:  i32,
	kind:   cstring,
	detail: cstring,
	actor:  Entity_ID,
}


@(private = "file")
world_compact_before :: proc(self: ^World, before: u64, from: i64, until: i64) {
	counted := make(map[Digest_Key]int, context.temp_allocator)    /* to its digest, in `found` */
	found   := make([dynamic]Digest, context.temp_allocator)
	kept    := self.windowAt
	n       := self.windowAt + int(before - self.whole)
	for at := self.windowAt; at < n && at < len(self.events); at += 1 {
		ev := self.events[at]
		if !ev.diagnostic {
			self.events[kept] = ev
			kept += 1
			continue
		}
		key := Digest_Key{kind = ev.kind, detail = ev.detail, actor = ev.actor, placed = ev.location.form == .On_Tile}
		if key.placed {
			key.cx, key.cy, key.level = ev.location.x / BG_CHUNK, ev.location.y / BG_CHUNK, ev.location.level
		}
		d, ok := counted[key]
		if !ok {
			d = len(found)
			counted[key] = d
			append(&found, Digest{from = from, until = until, placed = key.placed, cx = key.cx, cy = key.cy,
			                      level = key.level, kind = ev.kind, detail = ev.detail, actor = ev.actor,
			                      first = ev.index})
		}
		found[d].count += 1
		found[d].last   = ev.index
	}
	/* the window after it, moved down */
	copy(self.events[kept:], self.events[n:])
	resize(&self.events, kept + len(self.events) - n)
	self.windowAt = kept
	self.whole    = before
	/* digests in the order of their first event: the same every time */
	slice.sort_by(found[:], proc(a, b: Digest) -> bool {return a.first < b.first})
	append(&self.digests, ..found[:])
}


/* A saved history, put back: each kept event, in index order, with its own
 * index (world_emit gives the next). */
world_restore_event :: proc(self: ^World, event: Event) -> bool {
	if len(self.events) != 0 && event.index <= self.events[len(self.events) - 1].index do return false
	if event.index < self.whole do self.windowAt += 1      /* compacted history, before the whole */
	append(&self.events, event)
	if event.index >= self.nextEvent do self.nextEvent = event.index + 1
	if event.subject != 0 && event.kind != nil && string(event.kind) == "created" {
		index_add(self.creations, event.subject, Entity_ID(event.index))
	}
	return true
}


/* A saved history's place, put back, before its events. */
world_restore_history :: proc(self: ^World, window: i64, compactAt: i64, whole: u64, due: u64, next: u64) {
	self.historyWindow = window
	self.compactAt     = compactAt
	self.whole         = whole
	self.compactDue    = due
	self.nextEvent     = next
	self.windowAt      = 0
}


world_restore_digest :: proc(self: ^World, d: Digest) {
	append(&self.digests, d)
}


/* --- the rest -------------------------------------------------------------- */

world_intern :: proc(self: ^World, string_: cstring) -> cstring {
	s := string(string_)
	lo: uint = 0
	hi := uint(len(self.strings))
	for lo < hi {
		mid := (lo + hi) / 2
		r := strings.compare(string(self.strings[mid]), s)
		if r == 0 {
			return self.strings[mid]
		}
		if r < 0 {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	inject_at(&self.strings, int(lo), strings.clone_to_cstring(s))
	return self.strings[lo]
}


// A record's fields, a type by its name: content renumbers type IDs.
@(private = "file")
hash_record :: proc(self: ^World, h: u64, info: ^Component_Info, record: rawptr) -> u64 {
	h := h
	for i: uint = 0; i < info.nfields; i += 1 {
		f := &info.fields[i]
		if f.value == VALUE_TEXT {
			text := (^cstring)(uintptr(record) + f.offset)^
			h = mix_string(h, text if text != nil else "")
		} else if f.value == VALUE_TYPE {
			h = mix_string(h, tri.type_name(world_tri(self), tri.Type(field_get(f, record))))
		} else {
			h = mix(h ~ u64(field_get(f, record)))
		}
	}
	return h
}


/* A hash of all authoritative state, in ID order: replays compare it. */
world_state_hash :: proc(self: ^World) -> u64 {
	h := mix(self.seed ~ self.nextID)
	for i: uint = 0; i < store_count(self.entities); i += 1 {
		info := (^Entity_Info)(store_record_at_index(self.entities, i))
		h = mix(h ~ store_entity_at_index(self.entities, i))
		h = mix_string(h, info.blueprint)
		h = mix(h ~ info.seed)
	}
	/* the components by name, those no entity has passed over: content
	 * renumbers them, and adds some */
	kinds := make([]uint, self.nkinds, context.temp_allocator)
	for k: uint = 0; k < self.nkinds; k += 1 do kinds[k] = k
	slice.sort_by(kinds, proc(a, b: uint) -> bool {return string(COMPONENTS[a].name) < string(COMPONENTS[b].name)})
	for k in kinds {
		if store_count(self.kinds[k]) == 0 do continue
		h = mix_string(h, COMPONENTS[k].name)
		for i: uint = 0; i < store_count(self.kinds[k]); i += 1 {
			h = mix(h ~ store_entity_at_index(self.kinds[k], i))
			h = hash_record(self, h, &COMPONENTS[k], store_record_at_index(self.kinds[k], i))
		}
	}
	for i: uint = 0; i < store_count(self.locations); i += 1 {
		loc := (^Location)(store_record_at_index(self.locations, i))
		h = mix(h ~ store_entity_at_index(self.locations, i))
		h = mix(h ~ u64(loc.form) ~ (loc.place << 4))
		h = mix(h ~ u64(u32(loc.x)) ~ (u64(u32(loc.y)) << 32))
		h = mix(h ~ u64(u32(loc.level)) ~ (u64(u32(loc.slot)) << 32))
		h = mix_string(h, location_role_c(loc))
	}
	for i: uint = 0; i < store_count(self.tombstones); i += 1 {
		stone := (^Tombstone)(store_record_at_index(self.tombstones, i))
		h = mix(h ~ store_entity_at_index(self.tombstones, i))
		h = mix_string(h, stone.blueprint)
		h = mix(h ~ stone.successor ~ (stone.cause << 20))
		h = mix_string(h, cstring(&stone.reason[0]))
	}
	for i := 0; i < len(self.edges); i += 1 {
		h = mix(h ~ u64(self.edges[i].kind) ~ (self.edges[i].from << 8) ~ (self.edges[i].to << 36))
	}
	{
		nwet := stocks_wet(self.stocks, nil, 0)
		wet := make([^][3]i32, nwet if nwet != 0 else 1)
		stocks_wet(self.stocks, wet, nwet)
		for w: uint = 0; w < nwet; w += 1 {
			cell := (u64(wet[w][2]) * u64(self.tilesHigh) + u64(wet[w][1])) * u64(self.tilesWide) +
			        u64(wet[w][0])
			h = mix(h ~ cell ~ (u64(world_water_at_x(self, wet[w][0], wet[w][1], wet[w][2])) << 20))
		}
		free(wet)
	}
	if self.terrain != nil {
		h = mix(h ~ terrain_hash(self.terrain))
	}
	h = reality_hash(self.reality, h)
	for i := 0; i < len(self.events); i += 1 {
		ev := &self.events[i]
		h = mix_string(h, ev.kind)
		h = mix_string(h, ev.detail if ev.detail != nil else "")
		amount := ev.amount
		if name := world_event_type_name(self, ev); name != nil {
			h, amount = mix_string(h, name), 0
		}
		h = mix(h ~ ev.subject ~ (ev.other << 24) ~ (u64(amount) << 48))
		h = mix(h ~ ev.cause ~ (ev.group << 32) ~ ev.boundary)
		h = mix(h ~ ev.actor)
	}
	return h
}


// What snprintf into a buffer of `size` bytes keeps of a string: size - 1
// bytes of it.
@(private = "file")
clip :: proc(s: string, size: int) -> string {
	return s[:min(len(s), size - 1)]
}


/* "Body.mass=3g Stack.count=5 ..." for traces and the inspector */
world_describe_entity :: proc(self: ^World, entity: Entity_ID) -> string {
	buf: [128]u8
	value: string

	info := world_info(self, entity)
	if info == nil {
		stone := world_tombstone(self, entity)
		if stone == nil {
			return fmt.tprintf("%d: unknown", entity)
		}
		return fmt.tprintf("%d: tombstone of %s, %s, successor %d",
		                   entity, stone.blueprint, cstring(&stone.reason[0]),
		                   stone.successor)
	}
	s := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&s, "%d %s:", entity, info.blueprint)
	for k: uint = 0; k < self.nkinds; k += 1 {
		record := store_record_for(self.kinds[k], entity)
		if record == nil {
			continue
		}
		for i: uint = 0; i < COMPONENTS[k].nfields; i += 1 {
			f := &COMPONENTS[k].fields[i]
			switch f.value {
			case VALUE_QUANTITY:
				tri.format_quantity(f.kind, field_get(f, record), &buf[0], len(buf))
				value = string(cstring(&buf[0]))
			case VALUE_TYPE:
				name := tri.type_name(world_tri(self), tri.Type(field_get(f, record)))
				value = clip(string(name) if name != nil else "(null)", len(buf))
			case VALUE_BOOL:
				value = "true" if field_get(f, record) != 0 else "false"
			case VALUE_REF:
				value = fmt.tprintf("ref(%d)", field_get(f, record))
			case VALUE_TEXT:
				text := (^cstring)(uintptr(record) + f.offset)^
				value = clip(fmt.tprintf("\"%s\"", text if text != nil else ""), len(buf))
			case:
				value = "_"
			}
			fmt.sbprintf(&s, " %s.%s=%s", COMPONENTS[k].name, f.name, value)
		}
	}
	fmt.sbprintf(&s, " at %s", clip(location_format(world_location_of(self, entity)), len(buf)))
	return strings.to_string(s)
}

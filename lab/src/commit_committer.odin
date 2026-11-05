package lab

// BGCommitter — change commitment (ACTIONS.md §8–11), the only writer of
// world state. At each boundary it orders the submitted groups by phase and
// a seeded permutation, rewrites each for automatic individuation, applies it
// against the state the earlier groups left, validates the result, and keeps
// it or rolls it back with a reason. Applied groups allocate IDs in order and
// emit committed events; components react to those, and their groups form
// the next round, up to a bound. What is left is deferred to the next
// boundary.
//
// (ported from the Objective-C lab's commit/BGCommitter.m. Its protocols, BGReactor and
// BGRoundListener, are in protocols.odin.)
//
// A reason a proposal or a group fails is a string, "" for none (nil in
// Objective-C).

import "core:fmt"
import "core:mem"
import "core:strings"

// _reactors' pairs: kind index, reactor.
@(private = "file")
Reactor_Pair :: struct {
	kind:    uint,
	reactor: Reactor,
}

Committer :: struct {
	using object: Object,
	untraced:  bool,                      // no trace kept: a large world's
	world:     ^World,
	submitted: [dynamic]^Proposal_Group,  // each retained
	deferred:  [dynamic]^Proposal_Group,  // each retained
	reactors:  [dynamic]Reactor_Pair,     // pairs: kind index, reactor (its data retained)
	listeners: [dynamic]Round_Listener,   // each one's data retained
	sources:   map[u64]string,            // commit position → the group's source
	trace:     [dynamic]string,
	rounds:    uint,
	position:  u64,
	round:     u32,
}


// What a group declares it creates or destroys: the only changes to total
// mass and to each unit's count that conservation allows.
@(private = "file")
BG_MAX_UNITS :: 64

@(private = "file")
Unit_Tally :: struct {
	unit:     cstring,
	before:   i64,
	after:    i64,
	declared: i64,
}

@(private = "file")
Tally :: struct {
	mass:   i64,
	units:  [BG_MAX_UNITS]Unit_Tally,
	nunits: uint,
}

@(private = "file")
tally_unit :: proc(t: ^Tally, unit: cstring) -> ^Unit_Tally {
	for i: uint = 0; i < t.nunits; i += 1 {
		if string(t.units[i].unit) == string(unit) do return &t.units[i]
	}
	if t.nunits == BG_MAX_UNITS do return nil
	t.units[t.nunits] = {}
	t.units[t.nunits].unit = unit
	t.nunits += 1
	return &t.units[t.nunits - 1]
}


// Whether the group relates the new entity `splitFrom` something: divided
// from an individual (COMPONENTS.md Scenario 3), its mass is carved from
// that, which the group lowers as much, so none is created.
@(private = "file")
carved_from_source :: proc(g: ^Proposal_Group, handle: Entity_ID) -> bool {
	p: [^]Proposal

	p = proposal_group_proposals(g)
	for i: uint = 0; i < proposal_group_count(g); i += 1 {
		if p[i].kind == .Add_Edge && p[i].edge == .Split_From && p[i].target.entity == handle do return true
	}
	return false
}


@(private = "file")
declare :: proc(t: ^Tally, unit: cstring, units: i64, mass: i64) {
	u: ^Unit_Tally

	t.mass += mass
	u = tally_unit(t, unit) if unit != nil else nil
	if u != nil do u.declared += units
}


// A new committer, its count 1.
committer_init_with_world :: proc(world: ^World) -> ^Committer {
	self := object_new(Committer, committer_dealloc)
	self.world     = retain(world)
	self.submitted = make([dynamic]^Proposal_Group)
	self.deferred  = make([dynamic]^Proposal_Group)
	self.reactors  = make([dynamic]Reactor_Pair)
	self.listeners = make([dynamic]Round_Listener)
	self.sources   = make(map[u64]string)
	self.trace     = make([dynamic]string)
	self.rounds    = 4
	return self
}


committer_dealloc :: proc(self: ^Committer) {
	release(self.world)
	for i := 0; i < len(self.submitted); i += 1 do release(self.submitted[i])
	delete(self.submitted)
	for i := 0; i < len(self.deferred); i += 1 do release(self.deferred[i])
	delete(self.deferred)
	for i := 0; i < len(self.reactors); i += 1 do object_release(self.reactors[i].reactor.data)
	delete(self.reactors)
	for i := 0; i < len(self.listeners); i += 1 do object_release(self.listeners[i].data)
	delete(self.listeners)
	for _, source in self.sources do delete(source)        // freeing: the order can't matter
	delete(self.sources)
	for i := 0; i < len(self.trace); i += 1 do delete(self.trace[i])
	delete(self.trace)
}


committer_world :: proc(self: ^Committer) -> ^World {
	return self.world
}


// R; 4 by default
committer_set_rounds :: proc(self: ^Committer, rounds: uint) {
	self.rounds = rounds
}


committer_add_reactor :: proc(self: ^Committer, reactor: Reactor, kind: cstring) {
	k: uint

	k = world_kind_named(self.world, kind)
	if k == NOT_FOUND do return
	object_retain(reactor.data)
	append(&self.reactors, Reactor_Pair{k, reactor})
}


// retained: a listener must not retain the committer
committer_add_listener :: proc(self: ^Committer, listener: Round_Listener) {
	object_retain(listener.data)
	append(&self.listeners, listener)
}


committer_submit :: proc(self: ^Committer, group: ^Proposal_Group) {
	append(&self.submitted, retain(group))
}


committer_has_pending :: proc(self: ^Committer) -> bool {
	return len(self.submitted) != 0 || len(self.deferred) != 0
}


// The source of the group committed at a position, if this committer did it.
// (source, ok) #optional_ok; "" and false where the Objective-C
// returned nil.
committer_source_of_position :: proc(self: ^Committer, position: u64) -> (string, bool) #optional_ok {
	return self.sources[position]
}


committer_position :: proc(self: ^Committer) -> u64 {
	return self.position
}


committer_set_position :: proc(self: ^Committer, position: u64) {
	self.position = position
}


// Saved state: the groups waiting for the next boundary: those deferred to
// it, then those submitted since (a decision phase's actions, a player's
// command), the order it commits them in. Settled: []^Proposal_Group, in
// the temporary allocator.
committer_deferred_groups :: proc(self: ^Committer) -> []^Proposal_Group {
	groups := make([dynamic]^Proposal_Group, 0, len(self.deferred) + len(self.submitted), context.temp_allocator)
	append(&groups, ..self.deferred[:])
	append(&groups, ..self.submitted[:])
	return groups[:]
}


// Restored, they are all deferred. Settled: groups []^Proposal_Group.
committer_restore_deferred :: proc(self: ^Committer, groups: []^Proposal_Group) {
	// the new ones retained before the old are let go, which may be them
	for i := 0; i < len(groups); i += 1 do retain(groups[i])
	for i := 0; i < len(self.deferred); i += 1 do release(self.deferred[i])
	clear(&self.deferred)
	append(&self.deferred, ..groups)
}


// One line per group, rejection, event, and deferral, for the developer.
// []string, the trace itself (valid until the next line is noted).
committer_trace :: proc(self: ^Committer) -> []string {
	return self.trace[:]
}


committer_note :: proc(self: ^Committer, line: string) {
	if !self.untraced do append(&self.trace, strings.clone(line))
}


// Whether the trace is kept (by default it is): a line a group and an
// event, which a large world running long can do without.
committer_set_tracing :: proc(self: ^Committer, flag: bool) {
	self.untraced = !flag
}


// --- ordering --------------------------------------------------------------

// What weights a group in the permutation (ACTIONS.md §8, decision 13): in
// the action phase, what its operation declares weights its contests (its
// actor's quickness, for taking); 10 for one that declares nothing. Process
// and system phases are never weighted.
@(private = "file")
committer_order_weight_of :: proc(self: ^Committer, g: ^Proposal_Group) -> u64 {
	if proposal_group_phase(g) == .Action && proposal_group_weight(g) > 0 do return proposal_group_weight(g)
	return 10
}


// By phase, then a permutation seeded by the world seed, the boundary, and
// the round: nobody wins by being older, lower in ID, or submitted first.
// Weighted, when the groups' weights differ: drawn one at a time, each in
// proportion to its weight, from the same seeded stream, in integers.
// (The groups are kept alive by the caller's array: not retained here.)
@(private = "file")
committer_order :: proc(self: ^Committer, groups: []^Proposal_Group) -> []^Proposal_Group {
	ordered: [dynamic]^Proposal_Group
	phase:   [dynamic]^Proposal_Group
	g:       ^Proposal_Group
	i:       uint
	j:       uint
	state:   u64

	ordered = make([dynamic]^Proposal_Group, context.temp_allocator)
	for p: uint = 0; p < uint(Phase.Count); p += 1 {
		phase = make([dynamic]^Proposal_Group, context.temp_allocator)
		for i = 0; i < uint(len(groups)); i += 1 {
			g = groups[i]
			if proposal_group_phase(g) == Phase(p) do append(&phase, g)
		}
		state = mix(world_seed(self.world) ~ mix(world_boundary(self.world) * 0x100 + u64(self.round)) ~ (u64(p) << 56))
		for i = 1; i < uint(len(phase)) && committer_order_weight_of(self, phase[i]) == committer_order_weight_of(self, phase[0]); i += 1 {
		}
		if i < uint(len(phase)) {
			// weighted: successive sampling without replacement
			for len(phase) > 0 {
				total: u64
				r:     u64

				total = 0
				for i = 0; i < uint(len(phase)); i += 1 do total += committer_order_weight_of(self, phase[i])
				r = next(&state) % total
				for i = 0; i + 1 < uint(len(phase)) && r >= committer_order_weight_of(self, phase[i]); i += 1 {
					r -= committer_order_weight_of(self, phase[i])
				}
				append(&ordered, phase[i])
				ordered_remove(&phase, int(i))
			}
			continue
		}
		for i = uint(len(phase)); i > 1; i -= 1 {
			j = uint(next(&state) % u64(i))
			phase[i - 1], phase[j] = phase[j], phase[i - 1]
		}
		append(&ordered, ..phase[:])
	}
	return ordered[:]
}


// --- automatic individuation -----------------------------------------------

@(private = "file")
Unit_Pair :: struct {
	entity: Entity_ID,
	unit:   u32,
	handle: Entity_ID,        // the split-off unit, or NO_ENTITY for the whole entity
}

@(private = "file")
rewrite_ref :: proc(r: ^Ref, pairs: []Unit_Pair, n: uint) {
	if r.unit == 0 do return
	for i: uint = 0; i < n; i += 1 {
		if pairs[i].entity == r.entity && pairs[i].unit == r.unit {
			if pairs[i].handle != NO_ENTITY do r.entity = pairs[i].handle
			r.unit = 0
			return
		}
	}
}


@(private = "file")
BG_TRACED_UNIT :: u32(0xffffffff)      // the unit a trace on a stack marks


// Proposals that address one unit of a stack get that unit split off first,
// whether or not the proposer asked: the group's copy is rewritten so that
// every proposal naming {stack, n} names the split-off unit. The copy is
// made (malloc'd in Objective-C) for the caller to delete; its first
// `count` are used.
@(private = "file")
committer_individuate :: proc(self: ^Committer, group: ^Proposal_Group, count: ^uint) -> []Proposal {
	in_:    [^]Proposal
	out:    []Proposal
	split:  Proposal
	refs:   [2]^Ref
	pairs:  []Unit_Pair
	i:      uint
	j:      uint
	k:      uint
	n:      uint
	npairs: uint
	q:      uint
	found:  bool

	in_    = proposal_group_proposals(group)
	n      = proposal_group_count(group)
	out    = make([]Proposal, 4 * n + 1)
	pairs  = make([]Unit_Pair, 3 * n + 1)
	npairs = 0
	k      = 0
	for i = 0; i < n; i += 1 {
		r: [2]Ref

		r[0] = in_[i].target
		r[1] = in_[i].other
		for j = 0; j < 2; j += 1 {
			if r[j].unit == 0 do continue
			found = false
			for q = 0; q < npairs && !found; q += 1 {
				found = pairs[q].entity == r[j].entity && pairs[q].unit == r[j].unit
			}
			if found do continue
			pairs[npairs].entity = r[j].entity
			pairs[npairs].unit   = r[j].unit
			pairs[npairs].handle = NO_ENTITY
			// units of a stack this group creates can't be split off yet: the whole entity is meant
			if !is_handle(r[j].entity) && world_is_stack(self.world, r[j].entity) && world_units_of(self.world, r[j].entity) > 1 {
				split                = {}
				split.kind           = .Split
				split.target         = whole(r[j].entity)
				split.value          = 1
				split.handle         = proposal_group_new_handle(group)
				pairs[npairs].handle = split.handle
				out[k]               = split
				k += 1
				committer_note(self, fmt.tprintf("    individuate: unit %d of %d is split off first",
				                                 r[j].unit, r[j].entity))
			}
			npairs += 1
		}
	}
	// a trace put on a stack of several marks one unit (KNOWLEDGE.md §3): it
	// is split off, the same one for every trace the group puts on that stack
	for i = 0; i < n; i += 1 {
		if in_[i].kind != .Set_Field || in_[i].name == nil || string(in_[i].name) != "Trace.bearer" ||
		   is_handle(Entity_ID(in_[i].value)) || !world_is_stack(self.world, Entity_ID(in_[i].value)) ||
		   world_units_of(self.world, Entity_ID(in_[i].value)) < 2 {
			continue
		}
		found = false
		for q = 0; q < npairs && !found; q += 1 {
			found = pairs[q].entity == Entity_ID(in_[i].value) && pairs[q].unit == BG_TRACED_UNIT
		}
		if found do continue
		split                 = {}
		split.kind            = .Split
		split.target          = whole(Entity_ID(in_[i].value))
		split.value           = 1
		split.handle          = proposal_group_new_handle(group)
		pairs[npairs].entity  = Entity_ID(in_[i].value)
		pairs[npairs].unit    = BG_TRACED_UNIT
		pairs[npairs].handle  = split.handle
		npairs += 1
		out[k] = split
		k += 1
		committer_note(self, fmt.tprintf("    individuate: a unit of %d, traced, is split off first",
		                                 in_[i].value))
	}
	for i = 0; i < n; i += 1 {
		out[k]  = in_[i]
		refs[0] = &out[k].target
		refs[1] = &out[k].other
		rewrite_ref(refs[0], pairs, npairs)
		rewrite_ref(refs[1], pairs, npairs)
		if out[k].kind == .Set_Field && out[k].name != nil && string(out[k].name) == "Trace.bearer" {
			for q = 0; q < npairs; q += 1 {
				if pairs[q].unit == BG_TRACED_UNIT && pairs[q].entity == Entity_ID(out[k].value) {
					out[k].value = i64(pairs[q].handle)
				}
			}
		}
		k += 1
	}
	delete(pairs)
	count^ = k
	return out
}


// --- applying proposals ----------------------------------------------------

@(private = "file")
resolve_ref :: proc(g: ^Proposal_Group, r: Ref) -> Entity_ID {
	return proposal_group_id_for(g, r.entity)
}


@(private = "file")
resolve_location :: proc(g: ^Proposal_Group, loc: Location) -> Location {
	loc := loc

	if is_handle(loc.place) do loc.place = proposal_group_id_for(g, loc.place)
	return loc
}


@(private = "file")
committer_emit :: proc(self: ^Committer, kind: cstring, subject: Entity_ID, other: Entity_ID, amount: i64,
                       detail: cstring, location: Location, group: ^Proposal_Group) -> u64 {
	ev: Event

	ev.boundary = world_boundary(self.world)
	ev.round    = self.round
	ev.kind     = kind
	ev.subject  = subject
	ev.other    = other
	ev.amount   = amount
	ev.detail   = world_intern(self.world, detail) if detail != nil else nil
	ev.location = location
	ev.cause    = proposal_group_cause(group)
	ev.actor    = proposal_group_actor(group)
	ev.group    = self.position
	ev.diagnostic = proposal_group_diagnostic(group)
	return world_emit(self.world, ev)
}


@(private = "file")
live_check :: proc(w: ^World, e: Entity_ID, role: string) -> string {
	if e == NO_ENTITY do return fmt.tprintf("the %s is not known", role)
	if world_tombstone(w, e) != nil do return fmt.tprintf("the %s %d is a tombstone", role, e)
	if !world_is_live(w, e) do return fmt.tprintf("the %s %d does not exist", role, e)
	return ""
}


// Whether a trace that hasn't run out is on the entity.
@(private = "file")
bears_trace :: proc(world: ^World, e: Entity_ID) -> bool {
	trace:  ^Trace
	traces: ^Store

	traces = world_store_for_kind(world, world_kind_named(world, "Trace"))
	for i: uint = 0; i < store_count(traces); i += 1 {
		trace = (^Trace)(store_record_at_index(traces, i))
		if trace.bearer == e && trace.expires > world_time(world).ms do return true
	}
	return false
}


// Why `a` cannot merge into `b`, or "".
@(private = "file")
committer_merge_obstacle :: proc(self: ^Committer, a: Entity_ID, b: Entity_ID) -> string {
	ba:       ^Body
	bb:       ^Body
	ua:       cstring
	ub:       cstring
	claims:   [8]Entity_ID
	subjects: [2]Entity_ID
	body:     uint
	n:        uint

	if a == b do return "an entity cannot merge into itself"
	if !world_is_physical(self.world, a) || !world_is_physical(self.world, b) do return "only physical units merge"
	if !world_is_stack(self.world, b) do return fmt.tprintf("%d is not a stack", b)
	ua = world_unit_of(self.world, a)
	ub = world_unit_of(self.world, b)
	if ua == nil || ub == nil || string(ua) != string(ub) {
		return fmt.tprintf("different units (%s, %s)", ua if ua != nil else "?", ub if ub != nil else "?")
	}
	body = world_kind_named(self.world, "Body")
	ba   = (^Body)(world_record(self.world, body, a))
	bb   = (^Body)(world_record(self.world, body, b))
	if ba.bent || bb.bent do return "units differ physically: one is bent"
	if ba.toolMarks != 0 || bb.toolMarks != 0 do return "units differ physically: one has tool marks"
	if bears_trace(self.world, a) || bears_trace(self.world, b) do return "units differ physically: one bears a trace"
	if !location_equal(world_location_of(self.world, a), world_location_of(self.world, b)) do return "they are not in the same place"
	// a quantity claim over several entities follows the units; a claim on this one unit alone pins it
	if !world_is_stack(self.world, a) {
		n = world_edges_to(self.world, .Claim_Subject, a, &claims[0], 8)
		for i: uint = 0; i < n && i < 8; i += 1 {
			if world_edges_from(self.world, .Claim_Subject, claims[i], &subjects[0], 2) == 1 do return "a claim is on this unit alone"
		}
	}
	return ""
}


// --- air follows terrain (TERRAIN.md step 3) -------------------------------

// What a terrain change may part or join: the cell's room's air, and the
// air of the rooms beside it, before.
@(private = "file")
Air_Before :: struct {
	roomy:  bool,
	air:    Entity_ID,
	beside: [4]Entity_ID,
}

@(private = "file")
side_dx := [4]i32{1, -1, 0, 0}
@(private = "file")
side_dy := [4]i32{0, 0, 1, -1}

@(private = "file")
air_fields := [5]cstring{"GasStore.oxygen", "GasStore.dioxide", "GasStore.gasHeat", "GasStore.total",
                         "GasStore.gap"}


@(private = "file")
air_before :: proc(world: ^World, at: Location, before: ^Air_Before) {
	before^ = {}
	before.roomy = terrain_roomy(world_terrain(world), at.x, at.y, at.level)
	before.air   = world_air_region_at(world, at)
	for d := 0; d < 4; d += 1 {
		before.beside[d] = world_air_region_at(world, on_tile(at.x + side_dx[d], at.y + side_dy[d], at.level))
	}
}


// A wall built across a room's air parts it: each side it cut off gets air
// of its own (parted_air), as much of each stock as its share of the
// sides' tiles; the air keeps the rest, and the side its tile is on, or,
// the wall on its tile, the largest side.
@(private = "file")
committer_part_air :: proc(self: ^Committer, air: Entity_ID, at: Location, g: ^Proposal_Group) -> string {
	t:      ^Terrain
	error:  string
	e:      Entity_ID
	parts:  [4]u32
	keep:   u32
	room:   u32
	stock:  [5]i64
	share:  i64
	left:   [5]i64
	sum:    i64
	x:      i32
	y:      i32
	z:      i32
	nparts: int
	i:      int

	t      = world_terrain(self.world)
	nparts = 0
	for d := 0; d < 4; d += 1 {
		room = terrain_room_at(t, at.x + side_dx[d], at.y + side_dy[d], at.level)
		for i = 0; i < nparts && parts[i] != room; i += 1 {
		}
		if room != 0 && i == nparts && (world_air_of_room(self.world, room) == NO_ENTITY || world_air_of_room(self.world, room) == air) {
			parts[nparts] = room
			nparts += 1
		}
	}
	if nparts == 0 do return ""                      // the room was this one tile: its air is in no room now
	keep = world_room_of_air(self.world, air)
	for i = 0; i < nparts && parts[i] != keep; i += 1 {
	}
	if i == nparts {
		// its tile walled: it moves to the largest side
		if keep != 0 do return ""
		for keep, i = parts[0], 1; i < nparts; i += 1 {
			if terrain_room_size(t, parts[i]) > terrain_room_size(t, keep) do keep = parts[i]
		}
		terrain_room_corner(t, keep, &x, &y, &z)
		world_set_field_of_value(self.world, "GasStore.atX", air, i64(x))
		world_set_field_of_value(self.world, "GasStore.atY", air, i64(y))
		world_set_field_of_value(self.world, "GasStore.atLevel", air, i64(z))
	}
	if nparts == 1 do return ""
	sum = 0
	for i = 0; i < nparts; i += 1 do sum += i64(terrain_room_size(t, parts[i]))
	for q := 0; q < 5; q += 1 {
		world_get_field(self.world, air_fields[q], air, &stock[q])
		left[q] = stock[q]
	}
	for i = 0; i < nparts; i += 1 {
		if parts[i] == keep do continue
		e = world_allocate_id(self.world)
		world_add_entity(self.world, e, "parted_air", mix(mix(world_seed(self.world) ~ 0x7061727465640000) ~ u64(e)))
		error = ""
		if !world_construct(self.world, e, &error) do return error if error != "" else "cannot build parted_air"
		terrain_room_corner(t, parts[i], &x, &y, &z)
		world_set_field_of_value(self.world, "GasStore.atX", e, i64(x))
		world_set_field_of_value(self.world, "GasStore.atY", e, i64(y))
		world_set_field_of_value(self.world, "GasStore.atLevel", e, i64(z))
		for q := 0; q < 5; q += 1 {
			share = stock[q] * i64(terrain_room_size(t, parts[i])) / sum
			if q == 3 && share < 1 do share = 1                 // a total is at least a millimole
			if q == 3 && left[q] - share < 1 do return "too little air to part"
			world_set_field_of_value(self.world, air_fields[q], e, share)
			left[q] -= share
		}
		committer_emit(self, "created", e, air, 0, "parted_air", location_make_none(), g)
	}
	for q := 0; q < 5; q += 1 do world_set_field_of_value(self.world, air_fields[q], air, left[q])
	return ""
}


// A wall knocked through joins rooms: the air of each that had it is one,
// the first's, holding all of each stock; the others end in it. Joined to
// open ground, the rooms are none, and their air airs out.
@(private = "file")
committer_join_air_at :: proc(self: ^Committer, at: Location, before: ^Air_Before, g: ^Proposal_Group) -> string {
	airs: [4]Entity_ID
	keep: Entity_ID
	ev:   u64
	room: u32
	sum:  [5]i64
	v:    i64
	n:    int
	i:    int

	room = terrain_room_at(world_terrain(self.world), at.x, at.y, at.level)
	if room == 0 do return ""
	n = 0
	for d := 0; d < 4; d += 1 {
		for i = 0; i < n && airs[i] != before.beside[d]; i += 1 {
		}
		if before.beside[d] != NO_ENTITY && i == n && world_room_of_air(self.world, before.beside[d]) == room {
			airs[n] = before.beside[d]
			n += 1
		}
	}
	if n < 2 do return ""
	for keep, i = airs[0], 1; i < n; i += 1 {
		if airs[i] < keep do keep = airs[i]
	}
	sum = {}
	for i = 0; i < n; i += 1 {
		for q := 0; q < 5; q += 1 {
			if world_get_field(self.world, air_fields[q], airs[i], &v) do sum[q] += v
		}
	}
	for q := 0; q < 5; q += 1 {
		if !world_set_field_of_value(self.world, air_fields[q], keep, sum[q]) do return "too much air to join"
	}
	for i = 0; i < n; i += 1 {
		if airs[i] == keep do continue
		ev = committer_emit(self, "destroyed", airs[i], keep, 0, "joined", location_make_none(), g)
		world_destroy(self.world, airs[i], keep, ev, "joined")
	}
	return ""
}


@(private = "file")
committer_air_follows_terrain_at :: proc(self: ^Committer, at: Location, before: ^Air_Before, g: ^Proposal_Group) -> string {
	roomy: bool

	roomy = terrain_roomy(world_terrain(self.world), at.x, at.y, at.level)
	if before.roomy && !roomy && before.air != NO_ENTITY do return committer_part_air(self, before.air, at, g)
	if !before.roomy && roomy do return committer_join_air_at(self, at, before, g)
	return ""
}


@(private = "file")
committer_apply :: proc(self: ^Committer, p: ^Proposal, g: ^Proposal_Group, tally: ^Tally) -> string {
	stack:  Stack
	body:   Body
	sp:     ^Stack
	loc:    Location
	a:      Entity_ID
	b:      Entity_ID
	claims: [64]Entity_ID
	e:      Entity_ID
	reason: string
	error:  string
	kbody:  uint
	kstack: uint
	n:      uint
	ev:     u64
	seed:   u64
	f:      ^Field_Info
	info:   ^Entity_Info
	k:      uint
	value:  i64

	kbody  = world_kind_named(self.world, "Body")
	kstack = world_kind_named(self.world, "Stack")
	switch p.kind {
	case .Create:
		e = world_allocate_id(self.world)
		proposal_group_set_id(g, e, p.handle)
		seed = mix_string(mix(world_seed(self.world) ~ 0x637265617465), p.key if p.key != nil else p.name)
		world_add_entity(self.world, e, p.name, seed)
		error = ""
		if !world_construct(self.world, e, &error) do return error if error != "" else fmt.tprintf("cannot build %s", p.name)
		loc = resolve_location(g, p.location)
		if world_is_physical(self.world, e) {
			if loc.form == .None do return fmt.tprintf("%s is physical and needs a location", p.name)
			world_set_location(self.world, loc, e)
		} else {
			if loc.form != .None do return fmt.tprintf("%s is informational and has no location", p.name)
		}
		// a part revealed in a latent assembly (COMPONENTS.md §7): its mass
		// is carved out of the assembly's, which the group lowers as much, so
		// none is created
		declare(tally, world_unit_of(self.world, e) if world_is_physical(self.world, e) else nil, world_units_of(self.world, e),
		        0 if (loc.form == .Part_Of && world_record(self.world, world_kind_named(self.world, "Latent"), loc.place) != nil) ||
		             carved_from_source(g, p.handle) else world_mass_of(self.world, e))
		committer_emit(self, "created", e, NO_ENTITY, 0, p.name, loc, g)
		return ""

	case .Destroy:
		e = resolve_ref(g, p.target)
		reason = live_check(self.world, e, "target")
		if reason != "" do return reason
		if world_is_physical(self.world, e) {
			declare(tally, world_unit_of(self.world, e), -world_units_of(self.world, e), -world_mass_of(self.world, e))
		}
		/* where it was: a witness knows the thing that ended there (KNOWLEDGE.md decision 19) */
		ev = committer_emit(self, "destroyed", e, NO_ENTITY, 0, p.name, world_location_of(self.world, e), g)
		world_destroy(self.world, e, NO_ENTITY, ev, p.name if p.name != nil else "destroyed")
		return ""

	case .Set_Field:
		e = resolve_ref(g, p.target)
		reason = live_check(self.world, e, "target")
		if reason != "" do return reason
		if !world_lookup_field(self.world, p.name, &k, &f) do return fmt.tprintf("no field %s", p.name)
		if !strings.contains(string(f.flags), "proposable") do return fmt.tprintf("%s is not proposable", p.name)
		if world_is_checked_out(self.world, e) && string(world_kind_info(self.world, k).name) == "WaterStore" {
			return fmt.tprintf("%d's water is checked out by its domain; contribute to the domain instead", e)
		}
		if world_record(self.world, k, e) == nil {
			return fmt.tprintf("%d has no %s component", e, world_kind_info(self.world, k).name)
		}
		if p.expects {
			now: i64
			if !world_get_field(self.world, p.name, e, &now) || now != i64(u64(p.other.entity)) {
				return fmt.tprintf("%d's %s is no longer %d", e, p.name, i64(u64(p.other.entity)))
			}
		}
		// a reference to something the group creates: its ID now
		value = i64(proposal_group_id_for(g, Entity_ID(p.value))) if f.value == VALUE_REF && is_handle(Entity_ID(p.value)) else p.value
		set: bool
		if f.value == VALUE_TEXT {
			set = world_set_field_of_text(self.world, p.name, e, p.key)
		} else {
			set = world_set_field_of_value(self.world, p.name, e, value)
		}
		if !set do return fmt.tprintf("%s cannot be set", p.name)
		if world_logs_field(self.world, f) {
			committer_emit(self, "changed", e, NO_ENTITY, p.value, p.name, location_make_none(), g)
		}
		return ""

	case .Move:
		e = resolve_ref(g, p.target)
		reason = live_check(self.world, e, "target")
		if reason != "" do return reason
		if !world_is_physical(self.world, e) do return fmt.tprintf("%d is informational and has no location", e)
		loc = resolve_location(g, p.location)
		if loc.form == .None do return "a physical entity cannot be moved nowhere"
		if p.expects {
			now: Location
			was: Location

			now = world_location_of(self.world, e)
			was = resolve_location(g, p.expected)
			if now.form != was.form || now.place != was.place || now.slot != was.slot ||
			   (now.form == .On_Tile && (now.x != was.x || now.y != was.y || now.level != was.level)) {
				return fmt.tprintf("%d is no longer where it was taken from", e)
			}
		}
		world_set_location(self.world, loc, e)
		committer_emit(self, "moved", e, loc.place, 0, nil, loc, g)
		return ""

	case .Split:
		a = resolve_ref(g, p.target)
		reason = live_check(self.world, a, "stack")
		if reason != "" do return reason
		sp = (^Stack)(world_record(self.world, kstack, a))
		if sp == nil do return fmt.tprintf("%d is not a stack", a)
		if p.value < 1 || p.value >= sp.count do return fmt.tprintf("cannot split %d of %d", p.value, sp.count)
		// copies: adding the new entity's records may move the store's
		stack = sp^
		sp    = nil
		body  = (^Body)(world_record(self.world, kbody, a))^
		info  = world_info(self.world, a)
		e     = world_allocate_id(self.world)
		proposal_group_set_id(g, e, p.handle)
		seed  = mix(info.seed ~ (u64(stack.count) * 0x9e3779b97f4a7c15))
		loc   = world_location_of(self.world, a) if p.location.form == .None else resolve_location(g, p.location)
		// the new entity: an individual of the unit, or a smaller stack
		if p.value == 1 {
			world_add_entity(self.world, e, stack.unit, seed)
			body.mass = stack.unitMass
			world_set_record(self.world, &body, kbody, e)
		} else {
			world_add_entity(self.world, e, info.blueprint, seed)
			body.mass   = stack.unitMass * p.value
			stack.count = p.value
			world_set_record(self.world, &body, kbody, e)
			world_set_record(self.world, &stack, kstack, e)
			stack = (^Stack)(world_record(self.world, kstack, a))^
		}
		// the units are alike: what else the stack is (its food, say), so is
		// what was split off
		for kind: uint = 0; kind < world_kind_count(self.world); kind += 1 {
			if kind == kbody || kind == kstack do continue
			from := world_record(self.world, kind, a)
			if from == nil do continue
			buf := make([]u8, world_kind_info(self.world, kind).size, context.temp_allocator)
			mem.copy(raw_data(buf), from, len(buf))
			world_set_record(self.world, raw_data(buf), kind, e)
		}
		// what remains
		stack.count -= p.value
		body         = (^Body)(world_record(self.world, kbody, a))^
		body.mass   -= stack.unitMass * p.value
		world_set_record(self.world, &stack, kstack, a)
		world_set_record(self.world, &body, kbody, a)
		world_set_location(self.world, loc, e)
		world_add_edge(self.world, .Split_From, e, a)
		// every claim on the stack extends to what was split off; which units it covers is not assigned
		n = world_edges_to(self.world, .Claim_Subject, a, &claims[0], 64)
		for i: uint = 0; i < n && i < 64; i += 1 do world_add_edge(self.world, .Claim_Subject, claims[i], e)
		committer_emit(self, "split", e, a, p.value, nil, loc, g)
		return ""

	case .Merge:
		a = resolve_ref(g, p.target)
		b = resolve_ref(g, p.other)
		reason = live_check(self.world, a, "unit")
		if reason == "" do reason = live_check(self.world, b, "stack")
		if reason != "" do return reason
		reason = committer_merge_obstacle(self, a, b)
		if reason != "" do return fmt.tprintf("cannot merge %d into %d: %s", a, b, reason)
		stack        = (^Stack)(world_record(self.world, kstack, b))^
		body         = (^Body)(world_record(self.world, kbody, b))^
		stack.count += world_units_of(self.world, a)
		body.mass   += world_mass_of(self.world, a)
		world_set_record(self.world, &stack, kstack, b)
		world_set_record(self.world, &body, kbody, b)
		// quantity claims follow the units; each keeps its quantity
		n = world_edges_to(self.world, .Claim_Subject, a, &claims[0], 64)
		for i: uint = 0; i < n && i < 64; i += 1 {
			world_remove_edge(self.world, .Claim_Subject, claims[i], a)
			world_add_edge(self.world, .Claim_Subject, claims[i], b)
		}
		ev = committer_emit(self, "merged", a, b, world_units_of(self.world, a), nil, world_location_of(self.world, b), g)
		world_destroy(self.world, a, b, ev, "merged")
		return ""

	case .Add_Edge, .Remove_Edge:
		a = resolve_ref(g, p.target)
		b = resolve_ref(g, p.other)
		reason = live_check(self.world, a, "source")
		if reason == "" do reason = live_check(self.world, b, "target")
		if reason != "" do return reason
		if p.kind == .Remove_Edge {
			if !world_has_edge(self.world, p.edge, a, b) {
				return fmt.tprintf("no %s edge from %d to %d", EDGE_KIND_NAMES[p.edge], a, b)
			}
			world_remove_edge(self.world, p.edge, a, b)
			committer_emit(self, "unrelated", a, b, 0, EDGE_KIND_NAMES[p.edge], location_make_none(), g)
			return ""
		}
		// splitFrom and claimant are many-to-one
		if p.edge != .Claim_Subject && world_edges_from(self.world, p.edge, a, &claims[0], 1) != 0 {
			return fmt.tprintf("%d already has a %s", a, EDGE_KIND_NAMES[p.edge])
		}
		world_add_edge(self.world, p.edge, a, b)
		committer_emit(self, "related", a, b, 0, EDGE_KIND_NAMES[p.edge], location_make_none(), g)
		return ""

	case .Set_Terrain:
		before: Air_Before

		loc = p.location
		if world_terrain(self.world) == nil || terrain_kind_named(world_terrain(self.world), p.name) == 0 {
			return fmt.tprintf("no terrain kind named %s", p.name if p.name != nil else "")
		}
		if loc.form != .On_Tile || !world_is_tile_x(self.world, loc.x, loc.y, loc.level) do return "terrain is set on a tile of the map"
		value = i64(terrain_at(world_terrain(self.world), loc.x, loc.y, loc.level))
		air_before(self.world, loc, &before)
		world_set_terrain(self.world, p.name, loc.x, loc.y, loc.level)
		committer_emit(self, "terrain", NO_ENTITY, NO_ENTITY, value, p.name, loc, g)
		return committer_air_follows_terrain_at(self, loc, &before, g)

	case .Event:
		a = resolve_ref(g, p.target)
		b = resolve_ref(g, p.other)
		committer_emit(self, world_intern(self.world, p.name), a, b, p.value,
		               world_intern(self.world, p.key) if p.key != nil else nil,
		               location_make_none(), g)
		return ""
	}
	return "unknown proposal"
}


// --- validation ------------------------------------------------------------

// Why the place a physical entity is in can't hold it, or "".
@(private = "file")
committer_place_obstacle :: proc(self: ^Committer, e: Entity_ID, loc: Location) -> string {
	loc := loc
	agent:     ^Agent
	container: ^Container
	assembly:  ^Assembly
	others:    [256]Entity_ID
	up:        Entity_ID
	other:     Location
	guard:     uint
	n:         uint

	if loc.form == .On_Tile {
		if !world_is_tile_x(self.world, loc.x, loc.y, loc.level) do return fmt.tprintf("(%d, %d) is off the map", loc.x, loc.y)
		// terrain that fills its tile takes nothing in (TERRAIN.md)
		if world_terrain(self.world) != nil && terrain_solid(world_terrain(self.world), loc.x, loc.y, loc.level) {
			return fmt.tprintf("(%d, %d) is %s, solid", loc.x, loc.y,
			                   terrain_kind_info(world_terrain(self.world),
			                                     terrain_at(world_terrain(self.world), loc.x, loc.y, loc.level)).name)
		}
		return ""
	}
	if !world_is_live(self.world, loc.place) do return fmt.tprintf("%d is in %d, which does not exist", e, loc.place)
	// nothing is inside itself, however deep
	up = loc.place
	for guard = 0; up != NO_ENTITY && guard < 64; guard += 1 {
		if up == e do return fmt.tprintf("%d would be inside itself", e)
		up = world_location_of(self.world, up).place
	}
	n = world_entities_at(self.world, loc.place, loc.form, &others[0], 256)
	#partial switch loc.form {
	case .Held_By:
		agent = (^Agent)(world_record(self.world, world_kind_named(self.world, "Agent"), loc.place))
		if agent == nil do return fmt.tprintf("%d has no hands", loc.place)
		if loc.slot < 0 || i64(loc.slot) >= agent.hands do return fmt.tprintf("%d has no hand %d", loc.place, loc.slot)
		for i: uint = 0; i < n && i < 256; i += 1 {
			other = world_location_of(self.world, others[i])
			if others[i] != e && other.slot == loc.slot {
				return fmt.tprintf("hand %d of %d already holds %d", loc.slot, loc.place, others[i])
			}
		}
		return ""

	case .In:
		container = (^Container)(world_record(self.world, world_kind_named(self.world, "Container"), loc.place))
		if container == nil do return fmt.tprintf("%d is not a container", loc.place)
		if i64(n) > container.capacity do return fmt.tprintf("%d is full (%d)", loc.place, container.capacity)
		return ""

	case .Part_Of:
		assembly = (^Assembly)(world_record(self.world, world_kind_named(self.world, "Assembly"), loc.place))
		if assembly == nil do return fmt.tprintf("%d is not an assembly", loc.place)
		if loc.slot < 0 || i64(loc.slot) >= assembly.slots do return fmt.tprintf("%d has no slot %d", loc.place, loc.slot)
		for i: uint = 0; i < n && i < 256; i += 1 {
			other = world_location_of(self.world, others[i])
			if others[i] != e && other.slot == loc.slot && location_role(&other) == location_role(&loc) {
				return fmt.tprintf("%s %d of %d is taken", location_role(&loc), loc.slot, loc.place)
			}
		}
		return ""

	case:
		return ""
	}
}


@(private = "file")
committer_validate :: proc(self: ^Committer, tally: ^Tally) -> string {
	body:     ^Body
	stack:    ^Stack
	info:     ^Entity_Info
	u:        ^Unit_Tally
	touched:  [^]Entity_ID
	loc:      Location
	reason:   string
	kbody:    uint
	kstack:   uint
	n:        uint
	after:    i64
	before:   i64
	hadBody:  bool
	hadStack: bool

	kbody   = world_kind_named(self.world, "Body")
	kstack  = world_kind_named(self.world, "Stack")
	n       = world_touched(self.world, nil, 0)
	touched = make([^]Entity_ID, n if n != 0 else 1)
	world_touched(self.world, touched, n)
	reason = ""
	before = 0
	after  = 0
	for i: uint = 0; i < n && reason == ""; i += 1 {
		// location: every physical entity has exactly one, in a place that can hold it
		if world_is_live(self.world, touched[i]) {
			loc = world_location_of(self.world, touched[i])
			if world_is_physical(self.world, touched[i]) {
				if loc.form == .None {
					reason = fmt.tprintf("%d has no location", touched[i])
				} else {
					reason = committer_place_obstacle(self, touched[i], loc)
				}
			} else {
				if loc.form != .None do reason = fmt.tprintf("%d is informational but has a location", touched[i])
			}
		}

		// conservation: mass, and each unit's count
		body = (^Body)(world_record_before_group(self.world, kbody, touched[i], &hadBody))
		if hadBody {
			before += body.mass
			stack   = (^Stack)(world_record_before_group(self.world, kstack, touched[i], &hadStack))
			info    = world_info_before_group(self.world, touched[i])
			unit_name: cstring
			if hadStack {
				unit_name = stack.unit
			} else {
				unit_name = info.blueprint if info != nil else "?"
			}
			u = tally_unit(tally, unit_name)
			if u != nil {
				if hadStack do u.before += stack.count
				else do u.before += 1
			}
		}
		if world_is_physical(self.world, touched[i]) {
			after += world_mass_of(self.world, touched[i])
			u      = tally_unit(tally, world_unit_of(self.world, touched[i]))
			if u != nil do u.after += world_units_of(self.world, touched[i])
		}
	}
	free(touched)
	if reason != "" do return reason
	if after - before != tally.mass {
		return fmt.tprintf("mass is not conserved: %dg before, %dg after, %dg declared", before, after, tally.mass)
	}
	for i: uint = 0; i < tally.nunits; i += 1 {
		u = &tally.units[i]
		if u.after - u.before != u.declared {
			return fmt.tprintf("the count of %s is not conserved: %d before, %d after, %d declared",
			                   u.unit, u.before, u.after, u.declared)
		}
	}
	return ""
}


// --- one group -------------------------------------------------------------

@(private = "file")
committer_describe_event :: proc(self: ^Committer, ev: ^Event) -> string {
	where_: string

	where_ = location_format(ev.location)
	amount := ""
	if name := world_event_type_name(self.world, ev); name != nil {
		amount = fmt.tprintf(", %s", name)
	} else if ev.amount != 0 {
		amount = fmt.tprintf(", %d", ev.amount)
	}
	return fmt.tprintf("    event %d %s: %d%s%s%s%s%s%s",
	                   ev.index, ev.kind, ev.subject,
	                   ", other " if ev.other != NO_ENTITY else "",
	                   fmt.tprintf("%d", ev.other) if ev.other != NO_ENTITY else "",
	                   amount,
	                   fmt.tprintf(", %s", ev.detail) if ev.detail != nil else "",
	                   ", to " if ev.location.form != .None else "",
	                   where_ if ev.location.form != .None else "")
}


@(private = "file")
committer_commit_group :: proc(self: ^Committer, group: ^Proposal_Group) {
	proposals: []Proposal
	tally:     Tally
	reason:    string
	first:     uint
	n:         uint

	self.position += 1
	if old, ok := self.sources[self.position]; ok do delete(old)
	self.sources[self.position] = strings.clone(proposal_group_source(group))
	committer_note(self, fmt.tprintf("b%d r%d #%d %s %s", world_boundary(self.world), self.round,
	                                 self.position, PHASE_NAMES[proposal_group_phase(group)], proposal_group_source(group)))
	tally = {}
	world_begin_group(self.world)
	first     = world_event_count(self.world)
	proposals = committer_individuate(self, group, &n)
	reason    = ""
	for i: uint = 0; i < n && reason == ""; i += 1 do reason = committer_apply(self, &proposals[i], group, &tally)
	if reason == "" do reason = committer_validate(self, &tally)
	delete(proposals)
	if reason != "" {
		world_rollback_group(self.world)
		proposal_group_set_applied(group, false, reason, self.position)
		committer_note(self, fmt.tprintf("    rejected: %s", reason))
		return
	}
	world_commit_group(self.world)
	proposal_group_set_applied(group, true, "", self.position)
	for i := first; !self.untraced && i < world_event_count(self.world); i += 1 {
		committer_note(self, committer_describe_event(self, world_event_at(self.world, i)))
	}
	// contact raises what is touched to full detail (REALITY.md decision 10)
	world_lease_contacts_from(self.world, first)
}


// --- a boundary ------------------------------------------------------------

@(private = "file")
committer_react_to_events_from :: proc(self: ^Committer, first: uint) {
	ev:      ^Event
	reactor: Reactor
	kind:    uint
	last:    uint

	last = world_event_count(self.world)
	// engine machinery that follows each round, such as activities
	for k := 0; k < len(self.listeners); k += 1 {
		self.listeners[k].did_commit_round(self.listeners[k].data, self, self.round, first, last)
	}
	for i := first; i < last; i += 1 {
		ev = world_event_at(self.world, i)
		for k := 0; k < len(self.reactors); k += 1 {
			kind    = self.reactors[k].kind
			reactor = self.reactors[k].reactor
			if world_record(self.world, kind, ev.subject) != nil do reactor.react_to_event(reactor.data, self, ev, self.world)
		}
	}
}


// Commits everything submitted for the world's current boundary. Returns the
// groups processed, in order, each marked applied or rejected. Settled:
// []^Proposal_Group, in the temporary allocator, each group autoreleased
// once more (the autoreleased array held them).
committer_commit_boundary :: proc(self: ^Committer) -> []^Proposal_Group {
	current:   [dynamic]^Proposal_Group      // each retained, as the NSMutableArray held them
	processed: [dynamic]^Proposal_Group
	ordered:   []^Proposal_Group
	first:     uint

	processed = make([dynamic]^Proposal_Group, context.temp_allocator)
	current   = make([dynamic]^Proposal_Group, context.temp_allocator)
	for g in self.deferred do append(&current, retain(g))
	for g in self.submitted do append(&current, retain(g))
	for g in self.deferred do release(g)
	clear(&self.deferred)
	for g in self.submitted do release(g)
	clear(&self.submitted)
	for self.round = 0; len(current) != 0 && uint(self.round) < self.rounds; self.round += 1 {
		ordered = committer_order(self, current[:])
		first   = world_event_count(self.world)
		for i := 0; i < len(ordered); i += 1 {
			committer_commit_group(self, ordered[i])
			append(&processed, autorelease(retain(ordered[i])))
		}
		committer_react_to_events_from(self, first)
		for g in current do release(g)
		clear(&current)
		for g in self.submitted do append(&current, retain(g))
		for g in self.submitted do release(g)
		clear(&self.submitted)
	}
	if len(current) != 0 {
		committer_note(self, fmt.tprintf("b%d: %d groups deferred to the next boundary",
		                                 world_boundary(self.world), len(current)))
		for g in current do append(&self.deferred, retain(g))
	}
	for g in current do release(g)        // the array's own hold, let go
	return processed[:]
}

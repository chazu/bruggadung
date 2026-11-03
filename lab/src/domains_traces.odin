package lab

// BGTraces — the trace system (KNOWLEDGE.md §3). Traces are component state
// on informational entities (content/traces/traces.tri), made and removed
// only by the operations that declare them, in their effects' groups. Aging is
// analytic: a trace's strength is computed from its age when it is read,
// fading evenly from its magnitude to nothing at its `expires`. This domain
// costs nothing between: its horizon's next event is the earliest moment a
// trace is gone (below its kind's floor, or expired), and at that boundary
// it removes what is gone.
//
// (ported from the Objective-C lab's domains/BGTraces.m)

import tri "../../triangle/odin/triangle"


// Sound (KNOWLEDGE.md decision 14): how loud a sound of `strength` made at
// `from` is at `to`: less BG_SOUND_FALLOFF a tile, and, from another room
// (air region), BG_SOUND_DOOR through a doorway open between them (no
// door, or its door ajar), or BG_SOUND_WALL through a wall or a shut door.
// Another level: silent.
BG_SOUND_FALLOFF :: 3
BG_SOUND_DOOR :: 10
BG_SOUND_WALL :: 30
// How far any sound carries, at most: a trace's magnitude is at most 100
// (content/traces/traces.tri), less BG_SOUND_FALLOFF a tile. Hearing looks no
// further (the spatial index).
BG_SOUND_REACH :: (100 / BG_SOUND_FALLOFF + 1)
BG_SOUND_MASK :: 20     // a sound this much quieter than the loudest heard is masked


// How strong the trace is at `t`: its magnitude, faded evenly to 0 at its
// expiry.
trace_strength :: proc(trace: ^Trace, t: i64) -> i64 {
	life: i64

	if t >= trace.expires {
		return 0
	}
	life = trace.expires - trace.created
	if life <= 0 || t <= trace.created {
		return trace.magnitude
	}
	return trace.magnitude * (trace.expires - t) / life
}


// When it is gone (KNOWLEDGE.md §3): the first moment its strength is below
// its kind's floor (traces/traces.tri), or its expiry.
trace_gone :: proc(world: ^World, trace: ^Trace) -> i64 {
	v:     ^tri.Node
	floor: i64
	lo:    i64
	hi:    i64
	life:  i64
	t:     i64

	v     = tri.at(world_tri(world), tri.pattern(world_tri(world), trace.traceKind), "floor") if trace.traceKind != nil else nil
	floor = lo if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi else 0
	life  = trace.expires - trace.created
	if floor <= 0 || life <= 0 {
		return trace.expires
	}
	if trace.magnitude < floor {
		return trace.created
	}
	// strength(t) = magnitude * (expires - t) / life, below floor from about
	// expires - floor * life / magnitude; settled to the first such moment
	t = trace.expires - floor * life / trace.magnitude
	for t > trace.created && trace_strength(trace, t - 1) < floor {
		t -= 1
	}
	for t < trace.expires && trace_strength(trace, t) >= floor {
		t += 1
	}
	return t
}


// The air region over a tile, or none.
@(private = "file")
region_at :: proc(world: ^World, tile: Location) -> Entity_ID {
	return world_air_region_at(world, tile)
}


// Whether one region opens to the other (none: the outdoors) through a
// doorway standing open: no door in it, or its door ajar.
@(private = "file")
open_between :: proc(world: ^World, a: Entity_ID, b: Entity_ID) -> bool {
	return world_air_region(world, a, b)
}


loudness :: proc(world: ^World, strength: i64, from: Location, to: Location) -> i64 {
	a:        Entity_ID
	b:        Entity_ID
	d:        i64
	strength := strength

	if from.level != to.level {
		return 0
	}
	d         = i64(abs(from.x - to.x) if abs(from.x - to.x) > abs(from.y - to.y) else abs(from.y - to.y))
	strength -= BG_SOUND_FALLOFF * d
	a         = region_at(world, from)
	b         = region_at(world, to)
	if a != b {
		strength -= BG_SOUND_DOOR if open_between(world, a, b) else BG_SOUND_WALL
	}
	return strength if strength > 0 else 0
}


Traces :: struct {
	using object: Object,
	world:        ^World,
}


traces_init_with_world :: proc(world: ^World) -> ^Traces {
	self := object_new(Traces, traces_dealloc)
	self.world = retain(world)
	return self
}


traces_dealloc :: proc(self: ^Traces) {
	release(self.world)
}


traces_name :: proc(self: ^Traces) -> string {
	return "traces"
}


@(private = "file")
traces_traces :: proc(self: ^Traces) -> ^Store {
	return world_store_for_kind(self.world, world_kind_named(self.world, "Trace"))
}


traces_is_active :: proc(self: ^Traces) -> bool {
	return store_count(traces_traces(self)) > 0
}


// Nothing continuous: only the next trace gone.
traces_horizon_at :: proc(self: ^Traces, t: Time) -> Horizon {
	record: ^Trace
	traces: ^Store
	h:      Horizon
	i:      uint
	gone:   i64

	h.safeStep  = TIME_NEVER
	h.nextEvent = TIME_NEVER
	traces      = traces_traces(self)
	for i = 0; i < store_count(traces); i += 1 {
		record = (^Trace)(store_record_at_index(traces, i))
		gone   = trace_gone(self.world, record)
		if gone > t.ms && gone < h.nextEvent.ms {
			h.nextEvent = time_make(gone)
		}
	}
	return h
}


// What is gone by t1 is removed at t1, in trace order.
traces_advance_from :: proc(self: ^Traces, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	record: ^Trace
	group:  ^Proposal_Group
	traces: ^Store
	i:      uint

	traces = traces_traces(self)
	group  = nil
	for i = 0; i < store_count(traces); i += 1 {
		record = (^Trace)(store_record_at_index(traces, i))
		if trace_gone(world, record) > t1.ms {
			continue
		}
		if group == nil {
			group = proposal_group_group_with_phase(.Process, "traces: run out")
		}
		proposal_group_destroy(group, whole(store_entity_at_index(traces, i)), "run out")
	}
	if group != nil {
		committer_submit(committer, group)
	}
}


traces_check_in_all :: proc(self: ^Traces) {
}


traces_saved_state :: proc(self: ^Traces) -> []string {
	return make([]string, 0, context.temp_allocator)
}


traces_restore_saved_state :: proc(self: ^Traces, lines: []string) {
}


traces_as_domain :: proc(self: ^Traces) -> Domain {
	return Domain{
		data                = self,
		name                = proc(data: rawptr) -> string {return traces_name((^Traces)(data))},
		check_in_all        = proc(data: rawptr) {traces_check_in_all((^Traces)(data))},
		saved_state         = proc(data: rawptr) -> []string {return traces_saved_state((^Traces)(data))},
		restore_saved_state = proc(data: rawptr, lines: []string) {traces_restore_saved_state((^Traces)(data), lines)},
		is_active           = proc(data: rawptr) -> bool {return traces_is_active((^Traces)(data))},
		horizon_at          = proc(data: rawptr, t: Time) -> Horizon {return traces_horizon_at((^Traces)(data), t)},
		advance_from        = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
			traces_advance_from((^Traces)(data), t0, t1, world, committer)
		},
	}
}

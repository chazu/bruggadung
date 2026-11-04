package lab

/*
 * BGCistern — DOMAIN_SIMULATION.md Scenario 3, "Two draws on a dwindling
 * stock": a cistern with 15 L, two taps at 5 L/min with a bucket under each,
 * and a crack leaking 0.5 L/min onto the floor. Agents A and B open their
 * taps; the cistern runs dry; the water ends up in the buckets and on the
 * floor, exactly.
 *
 *   base: A and B open their taps at the same time
 *   3b:   A opens a minute earlier, and gets more
 *   3d:   the domain holds its participants in the reverse order inside;
 *         the run must be bit-identical to the base
 *   3e:   A fills only 3 L: a watch on the bucket ends A's activity, which
 *         closes the tap, and B gets the rest
 *
 * The agents fill their buckets as activities (fill_bucket), which end when
 * their watch fires or their tap reports the cistern dry.
 *
 * (ported from the Objective-C lab's scenario/BGCistern.m)
 */

import "core:fmt"
import tri "../../triangle/odin/triangle"


Cistern_Variant :: enum i32 {
	Base,
	Earlier,                 /* 3b */
	Reversed,                /* 3d */
	Stops_Early,             /* 3e */
}


// <BGInputSource, BGSchedulerObserver>: cistern_as_input_source,
// cistern_as_scheduler_observer.
Cistern :: struct {
	using object:  Object,
	variant:       Cistern_Variant,
	world:         ^World,
	committer:     ^Committer,
	scheduler:     ^Scheduler,
	fluid:         ^Fluid_Domain,
	activities:    ^Activities,
	results:       [dynamic]string,     // each cloned
	groups:        [dynamic]^Proposal_Group,
	times:         [256]i64,            /* boundary → time */
	next:          uint,
	conserved:     bool,
	neverNegative: bool,
	firstProblem:  string,              // cloned; "" for none

	cistern:       Entity_ID,
	tapA:          Entity_ID,
	tapB:          Entity_ID,
	crack:         Entity_ID,
	bucketA:       Entity_ID,
	bucketB:       Entity_ID,
	agentA:        Entity_ID,
	agentB:        Entity_ID,
	setup:         ^Proposal_Group,
}


cistern_name_of :: proc(variant: Cistern_Variant) -> string {
	switch variant {
	case .Base:
		return "cistern"
	case .Earlier:
		return "cistern-b"
	case .Reversed:
		return "cistern-d"
	case .Stops_Early:
		return "cistern-e"
	}
	return "?"
}


// returns the new scenario, its count 1.
cistern_init_with_world :: proc(world: ^World, committer: ^Committer, variant: Cistern_Variant) -> ^Cistern {
	self := object_new(Cistern, cistern_dealloc)
	self.variant       = variant
	self.world         = retain(world)
	self.committer     = retain(committer)
	self.scheduler     = scheduler_init_with_world(world, committer)
	self.fluid         = fluid_domain_init_with_world(world)
	self.results       = make([dynamic]string)
	self.groups        = make([dynamic]^Proposal_Group)
	self.conserved     = true
	self.neverNegative = true
	fluid_domain_set_reversed_order(self.fluid, variant == .Reversed)
	self.activities = retain(activities_with_world(world, committer))
	scheduler_add_domain(self.scheduler, fluid_domain_as_domain(self.fluid))
	scheduler_set_activities(self.scheduler, activities_as_activity_clock(self.activities))
	scheduler_set_inputs(self.scheduler, cistern_as_input_source(self))
	scheduler_set_observer(self.scheduler, cistern_as_scheduler_observer(self))
	return self
}


cistern_dealloc :: proc(self: ^Cistern) {
	release(self.world)
	release(self.committer)
	release(self.scheduler)
	release(self.fluid)
	release(self.activities)
	for i := 0; i < len(self.results); i += 1 do delete(self.results[i])
	delete(self.results)
	for i := 0; i < len(self.groups); i += 1 do release(self.groups[i])
	delete(self.groups)
	delete(self.firstProblem)
	release(self.setup)
}


cistern_as_input_source :: proc(self: ^Cistern) -> Input_Source {
	return Input_Source {
		data              = self,
		next_input_time   = proc(data: rawptr) -> Time {
			return cistern_next_input_time((^Cistern)(data))
		},
		deliver_inputs_at = proc(data: rawptr, t: Time, world: ^World, committer: ^Committer) {
			cistern_deliver_inputs_at((^Cistern)(data), t, world, committer)
		},
	}
}


cistern_as_scheduler_observer :: proc(self: ^Cistern) -> Scheduler_Observer {
	return Scheduler_Observer {
		data                = self,
		did_commit_boundary = proc(data: rawptr, scheduler: ^Scheduler, boundary: u64, groups: []^Proposal_Group) {
			cistern_did_commit_boundary((^Cistern)(data), scheduler, boundary, groups)
		},
	}
}


cistern_world :: proc(self: ^Cistern) -> ^World {
	return self.world
}


cistern_committer :: proc(self: ^Cistern) -> ^Committer {
	return self.committer
}


cistern_fluid :: proc(self: ^Cistern) -> ^Fluid_Domain {
	return self.fluid
}


// []string, the scenario's own (valid while it lives).
cistern_results :: proc(self: ^Cistern) -> []string {
	return self.results[:]
}


cistern_failure_count :: proc(self: ^Cistern) -> uint {
	n: uint

	n = 0
	for i := 0; i < len(self.results); i += 1 {
		if ns_has_prefix(self.results[i], "FAIL") do n += 1
	}
	return n
}


// why: "" for nil.
@(private = "file")
cistern_check :: proc(self: ^Cistern, ok: bool, name: string, why: string) {
	if ok {
		append(&self.results, fmt.aprintf("ok   %s", name))
	} else {
		append(&self.results, fmt.aprintf("FAIL %s: %s", name, why if why != "" else "no"))
	}
}


/* --- inputs --------------------------------------------------------------------- */

@(private = "file")
cistern_open_time_b :: proc(self: ^Cistern) -> i64 {
	return 61000 if self.variant == .Earlier else 1000
}


@(private = "file")
cistern_next_input_time :: proc(self: ^Cistern) -> Time {
	switch self.next {
	case 0:
		return time_make(0)
	case 1:
		return time_make(1000)
	case 2:
		return time_make(cistern_open_time_b(self)) if cistern_open_time_b(self) > 1000 else TIME_NEVER
	case:
		return TIME_NEVER
	}
}


/* The agent starts filling the bucket under the tap, to `amount` mL. */
@(private = "file")
cistern_fill :: proc(self: ^Cistern, bucket: Entity_ID, tap: Entity_ID, agent: Entity_ID, amount: i64) {
	error: string
	g:     ^Proposal_Group

	error = ""
	g     = perform(self.world, self.committer, action_make(world_intern(self.world, "fill_bucket"), agent, tap, bucket),
	                amount, &error)
	if g == nil {
		cistern_check(self, false, fmt.tprintf("agent %d can fill from tap %d", agent, tap), error)
	}
}


@(private = "file")
cistern_deliver_inputs_at :: proc(self: ^Cistern, t: Time, world: ^World, committer: ^Committer) {
	g: ^Proposal_Group
	h: [8]Entity_ID

	for cistern_next_input_time(self).ms <= t.ms {
		switch self.next {
		case 0:
			g = cistern_setup(&h)
			committer_submit(committer, g)
			self.setup   = retain(g)
			self.cistern = h[0]
			self.tapA    = h[1]
			self.tapB    = h[2]
			self.crack   = h[3]
			self.bucketA = h[4]
			self.bucketB = h[5]
			self.agentA  = h[6]
			self.agentB  = h[7]

		case 1:
			cistern_fill(self, self.bucketA, self.tapA, self.agentA, 3000 if self.variant == .Stops_Early else 10000)
			if cistern_open_time_b(self) == 1000 do cistern_fill(self, self.bucketB, self.tapB, self.agentB, 10000)

		case 2:
			cistern_fill(self, self.bucketB, self.tapB, self.agentB, 10000)
		}
		self.next += 1
	}
}


/* --- each boundary --------------------------------------------------------------- */

/* the total water: at rest in stores and tiles, plus what the domain has out */
cistern_total_water :: proc(self: ^Cistern) -> i64 {
	stores: ^Store
	e:      Entity_ID
	sum:    i64
	w:      i64

	stores = world_store_for_kind(self.world, world_kind_named(self.world, "WaterStore"))
	sum    = world_total_tile_water(self.world) + fluid_domain_checked_out_water(self.fluid)
	for i: uint = 0; i < store_count(stores); i += 1 {
		e = store_entity_at_index(stores, i)
		if world_is_checked_out(self.world, e) do continue
		world_get_field(self.world, "WaterStore.water", e, &w)
		sum += w
		if w < 0 do self.neverNegative = false
	}
	return sum
}


@(private = "file")
cistern_did_commit_boundary :: proc(self: ^Cistern, scheduler: ^Scheduler, boundary: u64, groups: []^Proposal_Group) {
	total: i64

	if boundary < 256 do self.times[boundary] = world_time(self.world).ms
	if is_handle(self.cistern) && proposal_group_applied(self.setup) {
		self.cistern = proposal_group_id_for(self.setup, self.cistern)
		self.tapA    = proposal_group_id_for(self.setup, self.tapA)
		self.tapB    = proposal_group_id_for(self.setup, self.tapB)
		self.crack   = proposal_group_id_for(self.setup, self.crack)
		self.bucketA = proposal_group_id_for(self.setup, self.bucketA)
		self.bucketB = proposal_group_id_for(self.setup, self.bucketB)
		self.agentA  = proposal_group_id_for(self.setup, self.agentA)
		self.agentB  = proposal_group_id_for(self.setup, self.agentB)
	}
	total = cistern_total_water(self)
	if total != 15000 && self.conserved {
		self.conserved    = false
		self.firstProblem = fmt.aprintf("boundary %d: %d mL", boundary, total)
	}
}


/* --- the run --------------------------------------------------------------------- */

@(private = "file")
cistern_water_of :: proc(self: ^Cistern, e: Entity_ID) -> i64 {
	w: i64

	w = 0
	world_get_field(self.world, "WaterStore.water", e, &w)
	return w
}


/* The boundary of the "exhausted" event for a tap, or 0. */
@(private = "file")
cistern_exhausted_boundary_of :: proc(self: ^Cistern, tap: Entity_ID) -> u64 {
	ev: ^Event

	for &kept in world_history(self.world) {
		ev = &kept
		if string(ev.kind) == "exhausted" && ev.subject == tap do return ev.boundary
	}
	return 0
}


/* An agent's fill activity: its status, and the boundary its status last changed. */
@(private = "file")
cistern_activity_of :: proc(self: ^Cistern, agent: Entity_ID, boundary: ^u64) -> cstring {
	record: ^Activity
	ev:     ^Event
	mine:   [^]Entity_ID
	a:      Entity_ID
	n:      uint

	mine = world_copy_activities_of(self.world, agent, &n)
	a    = mine[n - 1] if n != 0 else NO_ENTITY          /* its latest */
	free(mine)
	boundary^ = 0
	if a == 0 do return "none"
	for &kept in world_history(self.world) {
		ev = &kept
		if string(ev.kind) == "changed" && ev.subject == a && ev.detail != nil && string(ev.detail) == "Activity.status" {
			boundary^ = ev.boundary
		}
	}
	record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), a))
	return tri.type_name(world_tri(self.world), record.status)
}


/* only the boundaries up to a time, without the final checks */
cistern_run_until :: proc(self: ^Cistern, t: Time) {
	scheduler_run_until(self.scheduler, t)
}


/* carry on in a world restored from a save of this one, with a fresh fluid
 * domain given the save's domain state; then finish and check */
// the state as []string.
cistern_resume_with_world :: proc(self: ^Cistern, world: ^World, committer: ^Committer, state: []string) {
	autorelease(self.world)
	self.world = retain(world)
	autorelease(self.committer)
	self.committer = retain(committer)
	autorelease(self.fluid)
	self.fluid = fluid_domain_init_with_world(world)
	fluid_domain_set_reversed_order(self.fluid, self.variant == .Reversed)
	{
		d := fluid_domain_as_domain(self.fluid)
		d.restore_saved_state(d.data, state)
	}
	autorelease(self.activities)
	self.activities = retain(activities_with_world(world, committer))
	autorelease(self.scheduler)
	self.scheduler = scheduler_init_with_world(world, committer)
	scheduler_add_domain(self.scheduler, fluid_domain_as_domain(self.fluid))
	scheduler_set_activities(self.scheduler, activities_as_activity_clock(self.activities))
	scheduler_set_inputs(self.scheduler, cistern_as_input_source(self))
	scheduler_set_observer(self.scheduler, cistern_as_scheduler_observer(self))
}


cistern_run :: proc(self: ^Cistern) {
	cistern_finish(self)
}


cistern_finish :: proc(self: ^Cistern) {
	a:      i64
	b:      i64
	puddle: i64
	ba:     u64
	bb:     u64
	bc:     u64

	scheduler_run_until(self.scheduler, time_make(300000))
	{
		d := fluid_domain_as_domain(self.fluid)
		d.check_in_all(d.data)
	}

	a      = cistern_water_of(self, self.bucketA)
	b      = cistern_water_of(self, self.bucketB)
	puddle = world_total_tile_water(self.world)
	cistern_check(self, self.conserved && cistern_total_water(self) == 15000,
	              "1. exact conservation: buckets + floor + cistern = 15 L at every boundary",
	              self.firstProblem)
	cistern_check(self, self.neverNegative,
	              "4. no stock ever goes negative",
	              "")
	if self.variant == .Earlier || self.variant == .Stops_Early {
		cistern_check(self, a > b if self.variant == .Earlier else b > a,
		              ("3b. A, who started a minute earlier, got more" if self.variant == .Earlier
		                                                               else "3e. B, who kept filling, got more"),
		              fmt.tprintf("A %d, B %d", a, b))
	} else {
		cistern_check(self, abs(a - b) <= 1,
		              "3. fairness: equal requests differ by at most one millilitre",
		              fmt.tprintf("A %d, B %d", a, b))
	}
	ba = cistern_exhausted_boundary_of(self, self.tapA)
	bb = cistern_exhausted_boundary_of(self, self.tapB)
	bc = cistern_exhausted_boundary_of(self, self.crack)
	/* in 3e both taps close by their watches before the cistern runs dry */
	if self.variant != .Stops_Early {
		cistern_check(self, ba != 0 && ba == bb && bb == bc && ba < 256 &&
		                    self.times[ba] == fluid_domain_predicted_exhaustion(self.fluid).ms &&
		                    cistern_water_of(self, self.cistern) == 0,
		              "5. every tap hears \"exhausted\" in the same step, at the boundary the horizon predicted",
		              fmt.tprintf("boundaries %d %d %d, at %dms, predicted %dms",
		                          ba, bb, bc,
		                          self.times[ba] if ba < 256 else -1,
		                          fluid_domain_predicted_exhaustion(self.fluid).ms))
	}
	activity: {
		sa: cstring
		sb: cstring
		ea: u64
		eb: u64

		sa = cistern_activity_of(self, self.agentA, &ea)
		sb = cistern_activity_of(self, self.agentB, &eb)
		if self.variant == .Stops_Early {
			cistern_check(self, string(sa) == "\"completed\"" && a == 3000 && string(sb) == "\"completed\"" && b == 10000,
			              "3e. each watch ended its activity at its amount: A at 3 L, B at 10 L; the crack drained the rest",
			              fmt.tprintf("A %s with %d mL, B %s with %d mL", sa, a, sb, b))
		} else {
			cistern_check(self, string(sa) == "\"exhausted\"" && string(sb) == "\"exhausted\"" && ea == eb && ea == ba,
			              "5. both fill activities end, exhausted, in the step the cistern ran dry",
			              fmt.tprintf("A %s at %d, B %s at %d, dry at %d", sa, ea, sb, eb, ba))
		}
	}
	append(&self.results, fmt.aprintf("     bucket A %d mL, bucket B %d mL, floor %d mL, " +
	                                  "dry at %dms", a, b, puddle,
	                                  fluid_domain_predicted_exhaustion(self.fluid).ms))
}

package lab

/*
 * BGMarkedNail — COMPONENTS.md Scenario 1, "The marked nail", run headless
 * from a scripted input log, with its acceptance checks.
 *
 *   base: the worker takes 5 nails, hammers one into a lock (marking it),
 *         pulls it out, and drops all 5 back: 4 merge, the bent one can't
 *   A:    the same with an unmarked nail, which merges back too
 *   B:    mixed goods: the worker pours their own 10 nails into the smith's
 *         bin, then takes 5; the two quantity claims sum, then can't be
 *         allocated
 *
 * (ported from the Objective-C lab's scenario/BGMarkedNail.m)
 */

import "core:fmt"


Marked_Nail_Variant :: enum i32 {
	Base,
	Unmarked,                    /* variant A */
	Mixed_Goods,                 /* variant B */
}


// <BGInputSource, BGSchedulerObserver>: marked_nail_as_input_source,
// marked_nail_as_scheduler_observer.
Marked_Nail :: struct {
	using object:   Object,
	variant:        Marked_Nail_Variant,
	world:          ^World,
	committer:      ^Committer,
	scheduler:      ^Scheduler,
	activities:     ^Activities,
	next:           uint,
	results:        [dynamic]string,            // each cloned
	groups:         [dynamic]^Proposal_Group,   /* every group processed, in order */
	mass:           i64,                        /* totals after setup */
	nails:          i64,
	invariantsHeld: bool,

	bin:            Entity_ID,
	stack:          Entity_ID,
	lock:           Entity_ID,
	worker:         Entity_ID,
	smith:          Entity_ID,
	claim:          Entity_ID,
	workerStack:    Entity_ID,
	workerClaim:    Entity_ID,
	handful:        Entity_ID,
	nail:           Entity_ID,
	explicitMerge:  ^Proposal_Group,

	/* names waiting for their group to apply: the group, and the name's ivar */
	pendingGroups:  [16]^Proposal_Group,
	pendingNames:   [16]^Entity_ID,
	npending:       uint,
}


/* The input log: what happens, and when (simulation milliseconds). */
// BGStep: Script_Step here, as core_path.odin has the package's Step.
@(private = "file")
Script_Step :: enum i32 {
	Setup,
	Pour,              /* B: the worker's own nails go into the bin */
	Take,              /* the worker takes 5 */
	Hammer,            /* one nail is hammered into the lock */
	Pull_Out,
	Drop_Back,         /* all 5 go back into the bin */
	Merge_Bent,        /* a merge of the bent nail is proposed outright */
	End,
}

@(private = "file")
Script_Line :: struct {
	ms:   i64,
	step: Script_Step,
}

@(private = "file", rodata)
base_script := [?]Script_Line {
	{    0, .Setup},
	{ 1000, .Take},
	{ 5000, .Hammer},
	{60000, .Pull_Out},
	{61000, .Drop_Back},
	{62000, .Merge_Bent},
	{   -1, .End},
}

@(private = "file", rodata)
unmarked_script := [?]Script_Line {
	{    0, .Setup},
	{ 1000, .Take},
	{ 5000, .Hammer},       /* A: one nail goes into the other hand, unmarked */
	{61000, .Drop_Back},
	{   -1, .End},
}

@(private = "file", rodata)
mixed_script := [?]Script_Line {
	{    0, .Setup},
	{  500, .Pour},
	{ 1000, .Take},
	{   -1, .End},
}


marked_nail_name_of :: proc(variant: Marked_Nail_Variant) -> string {
	switch variant {
	case .Base:
		return "marked-nail"
	case .Unmarked:
		return "marked-nail-a"
	case .Mixed_Goods:
		return "marked-nail-b"
	}
	return "?"
}


// returns the new scenario, its count 1.
marked_nail_init_with_world :: proc(world: ^World, committer: ^Committer, variant: Marked_Nail_Variant) -> ^Marked_Nail {
	self := object_new(Marked_Nail, marked_nail_dealloc)
	self.variant        = variant
	self.world          = retain(world)
	self.committer      = retain(committer)
	self.scheduler      = scheduler_init_with_world(world, committer)
	self.results        = make([dynamic]string)
	self.groups         = make([dynamic]^Proposal_Group)
	self.invariantsHeld = true
	self.activities     = retain(activities_with_world(world, committer))
	scheduler_set_activities(self.scheduler, activities_as_activity_clock(self.activities))
	scheduler_set_inputs(self.scheduler, marked_nail_as_input_source(self))
	scheduler_set_observer(self.scheduler, marked_nail_as_scheduler_observer(self))
	return self
}


marked_nail_dealloc :: proc(self: ^Marked_Nail) {
	release(self.world)
	release(self.committer)
	release(self.scheduler)
	release(self.activities)
	for i := 0; i < len(self.results); i += 1 do delete(self.results[i])
	delete(self.results)
	for i := 0; i < len(self.groups); i += 1 do release(self.groups[i])
	delete(self.groups)
	release(self.explicitMerge)
}


marked_nail_as_input_source :: proc(self: ^Marked_Nail) -> Input_Source {
	return Input_Source {
		data              = self,
		next_input_time   = proc(data: rawptr) -> Time {
			return marked_nail_next_input_time((^Marked_Nail)(data))
		},
		deliver_inputs_at = proc(data: rawptr, t: Time, world: ^World, committer: ^Committer) {
			marked_nail_deliver_inputs_at((^Marked_Nail)(data), t, world, committer)
		},
	}
}


marked_nail_as_scheduler_observer :: proc(self: ^Marked_Nail) -> Scheduler_Observer {
	return Scheduler_Observer {
		data                = self,
		did_commit_boundary = proc(data: rawptr, scheduler: ^Scheduler, boundary: u64, groups: []^Proposal_Group) {
			marked_nail_did_commit_boundary((^Marked_Nail)(data), scheduler, boundary, groups)
		},
	}
}


marked_nail_world :: proc(self: ^Marked_Nail) -> ^World {
	return self.world
}


marked_nail_committer :: proc(self: ^Marked_Nail) -> ^Committer {
	return self.committer
}


/* "ok <check>" or "FAIL <check>: <why>", in the order they were made */
// []string, the scenario's own (valid while it lives).
marked_nail_results :: proc(self: ^Marked_Nail) -> []string {
	return self.results[:]
}


marked_nail_failure_count :: proc(self: ^Marked_Nail) -> uint {
	n: uint

	n = 0
	for i := 0; i < len(self.results); i += 1 {
		if ns_has_prefix(self.results[i], "FAIL") do n += 1
	}
	return n
}


// why: "" for nil.
@(private = "file")
marked_nail_check :: proc(self: ^Marked_Nail, ok: bool, name: string, why: string) {
	if ok {
		append(&self.results, fmt.aprintf("ok   %s", name))
	} else {
		append(&self.results, fmt.aprintf("FAIL %s: %s", name, why if why != "" else "no"))
	}
}


@(private = "file")
marked_nail_script :: proc(self: ^Marked_Nail) -> []Script_Line {
	switch self.variant {
	case .Base:
		return base_script[:]
	case .Unmarked:
		return unmarked_script[:]
	case .Mixed_Goods:
		return mixed_script[:]
	}
	return base_script[:]
}


/* --- the input log --------------------------------------------------------- */

@(private = "file")
marked_nail_next_input_time :: proc(self: ^Marked_Nail) -> Time {
	line: ^Script_Line

	line = &marked_nail_script(self)[self.next]
	return TIME_NEVER if line.step == .End else time_make(line.ms)
}


/* A command: the worker performs an operation from content, through the
 * menu. A command that isn't on the menu is a failed check. */
@(private = "file")
marked_nail_perform_item_destination_amount :: proc(self: ^Marked_Nail, operation: cstring, item: Entity_ID,
                                                    destination: Entity_ID, amount: i64) -> ^Proposal_Group {
	group: ^Proposal_Group
	error: string

	error = ""
	group = perform(self.world, self.committer,
	                action_make(world_intern(self.world, operation), self.worker, item, destination), amount, &error)
	if group == nil {
		marked_nail_check(self, false, fmt.tprintf("the worker can %s", operation), error)
		return nil
	}
	append(&self.groups, retain(group))
	return group
}


@(private = "file")
marked_nail_deliver_inputs_at :: proc(self: ^Marked_Nail, t: Time, world: ^World, committer: ^Committer) {
	line: ^Script_Line

	for line = &marked_nail_script(self)[self.next]; line.step != .End && line.ms <= t.ms; {
		marked_nail_perform(self, line.step)
		self.next += 1
		line = &marked_nail_script(self)[self.next]
	}
}


@(private = "file")
marked_nail_perform :: proc(self: ^Marked_Nail, step: Script_Step) {
	g: ^Proposal_Group
	h: [8]Entity_ID

	switch step {
	case .Setup:
		g = workshop_setup(self.variant == .Mixed_Goods, &h)
		committer_submit(self.committer, g)
		append(&self.groups, retain(g))
		self.bin    = h[0]
		self.stack  = h[1]
		self.lock   = h[2]
		self.worker = h[3]
		self.smith  = h[4]
		self.claim  = h[5]
		marked_nail_name(self, &self.bin, g)
		marked_nail_name(self, &self.stack, g)
		marked_nail_name(self, &self.lock, g)
		marked_nail_name(self, &self.worker, g)
		marked_nail_name(self, &self.smith, g)
		marked_nail_name(self, &self.claim, g)
		if self.variant == .Mixed_Goods {
			self.workerStack = h[6]
			self.workerClaim = h[7]
			marked_nail_name(self, &self.workerStack, g)
			marked_nail_name(self, &self.workerClaim, g)
		}

	case .Pour:
		marked_nail_perform_item_destination_amount(self, "put_in", self.workerStack, self.bin, 0)

	case .Take:
		g = marked_nail_perform_item_destination_amount(self, "take_some", self.stack, NO_ENTITY, 5)
		if g != nil {
			self.handful = proposal_group_proposals(g)[0].handle
			marked_nail_name(self, &self.handful, g)
		}

	case .Hammer:
		/* drive names one nail of the five; commitment splits it off */
		if self.variant == .Base {
			marked_nail_perform_item_destination_amount(self, "drive", self.handful, self.lock, 0)
		} else {
			marked_nail_perform_item_destination_amount(self, "take_some", self.handful, NO_ENTITY, 1)
		}

	case .Pull_Out:
		marked_nail_perform_item_destination_amount(self, "take", self.nail, NO_ENTITY, 0)

	case .Drop_Back:
		marked_nail_perform_item_destination_amount(self, "put_in", self.handful, self.bin, 0)
		marked_nail_perform_item_destination_amount(self, "put_in", self.nail, self.bin, 0)

	case .Merge_Bent:
		/* not an operation: a merge proposed outright, to see commitment refuse it */
		g = proposal_group_group_with_phase(.System, "someone proposes merging the bent nail")
		proposal_group_merge(g, whole(self.nail), whole(self.stack))
		committer_submit(self.committer, g)
		append(&self.groups, retain(g))
		self.explicitMerge = retain(g)

	case .End:
	}
}


/* --- after each boundary --------------------------------------------------- */

/* A name is a handle until the group that made it applies; then it is the
 * ID that group gave it. Handles are numbered per group. */
@(private = "file")
marked_nail_name :: proc(self: ^Marked_Nail, name: ^Entity_ID, group: ^Proposal_Group) {
	self.pendingGroups[self.npending] = group
	self.pendingNames[self.npending]  = name
	self.npending += 1
}


@(private = "file")
marked_nail_learn_ids :: proc(self: ^Marked_Nail) {
	parts: [4]Entity_ID
	n:     uint

	for i: uint = 0; i < self.npending; i += 1 {
		if proposal_group_applied(self.pendingGroups[i]) {
			self.pendingNames[i]^ = proposal_group_id_for(self.pendingGroups[i], self.pendingNames[i]^)
		}
	}
	self.npending = 0
	/* the hammered nail is whatever is now wedged in the lock; in A, the single nail in the other hand */
	if self.nail == 0 && self.lock != 0 && world_entities_at(self.world, self.lock, .Part_Of, raw_data(parts[:]), 4) != 0 {
		self.nail = parts[0]
	}
	if self.nail == 0 && self.variant == .Unmarked && self.worker != 0 {
		n = world_entities_at(self.world, self.worker, .Held_By, raw_data(parts[:]), 4)
		if n != 0 {
			for i: uint = 0; i < n && i < 4; i += 1 {
				if !world_is_stack(self.world, parts[i]) do self.nail = parts[i]
			}
		}
	}
}


/* Totals over every live physical entity: mass, and iron nails. */
@(private = "file")
marked_nail_totals_mass :: proc(self: ^Marked_Nail, mass: ^i64, nails: ^i64) {
	bodies: ^Store
	e:      Entity_ID
	unit:   cstring

	bodies = world_store_for_kind(self.world, world_kind_named(self.world, "Body"))
	mass^  = 0
	nails^ = 0
	for i: uint = 0; i < store_count(bodies); i += 1 {
		e      = store_entity_at_index(bodies, i)
		mass^ += world_mass_of(self.world, e)
		unit   = world_unit_of(self.world, e)
		if unit != nil && string(unit) == "iron_nail" do nails^ += world_units_of(self.world, e)
	}
}


/* Every live physical entity has exactly one location, and no two share a
 * hand or an assembly slot. */
// "" for none (nil).
@(private = "file")
marked_nail_location_problem :: proc(self: ^Marked_Nail) -> string {
	bodies:    ^Store
	locations: ^Store
	a:         ^Location
	b:         ^Location

	bodies = world_store_for_kind(self.world, world_kind_named(self.world, "Body"))
	for i: uint = 0; i < store_count(bodies); i += 1 {
		if world_location_of(self.world, store_entity_at_index(bodies, i)).form == .None {
			return fmt.tprintf("%d has no location", store_entity_at_index(bodies, i))
		}
	}
	locations = world_locations(self.world)
	for i: uint = 0; i < store_count(locations); i += 1 {
		a = (^Location)(store_record_at_index(locations, i))
		if a.form != .Held_By && a.form != .Part_Of do continue
		for j := i + 1; j < store_count(locations); j += 1 {
			b = (^Location)(store_record_at_index(locations, j))
			if a.form == b.form && a.place == b.place && a.slot == b.slot && location_role(a) == location_role(b) {
				return fmt.tprintf("%d and %d share a place",
				                   store_entity_at_index(locations, i),
				                   store_entity_at_index(locations, j))
			}
		}
	}
	return ""
}


@(private = "file")
marked_nail_did_commit_boundary :: proc(self: ^Marked_Nail, scheduler: ^Scheduler, boundary: u64,
                                        groups: []^Proposal_Group) {
	problem: string
	mass:    i64
	nails:   i64

	marked_nail_learn_ids(self)
	marked_nail_totals_mass(self, &mass, &nails)
	if boundary == 1 {
		self.mass  = mass
		self.nails = nails
		return
	}
	problem = marked_nail_location_problem(self)
	if mass != self.mass || nails != self.nails || problem != "" {
		if self.invariantsHeld {
			append(&self.results, fmt.aprintf("FAIL invariants at boundary %d: mass %d (was %d), " +
			                                  "nails %d (was %d)%s%s",
			                                  boundary, mass,
			                                  self.mass, nails, self.nails,
			                                  ", " if problem != "" else "", problem))
		}
		self.invariantsHeld = false
	}
}


/* --- the run and its checks ------------------------------------------------ */

@(private = "file")
marked_nail_trace_contains :: proc(self: ^Marked_Nail, text: string) -> bool {
	trace: []string

	trace = committer_trace(self.committer)
	for i := 0; i < len(trace); i += 1 {
		if ns_contains(trace[i], text) do return true
	}
	return false
}


/* From history, which saves keep: the unit was split off in the same group
 * that marked it, though the group proposed no split. */
@(private = "file")
marked_nail_split_in_group_that_marked :: proc(self: ^Marked_Nail, unit: Entity_ID) -> bool {
	ev:    ^Event
	split: ^Event

	split = nil
	for i: uint = 0; i < world_event_count(self.world); i += 1 {
		ev = world_event_at(self.world, i)
		if string(ev.kind) == "split" && ev.subject == unit && ev.other == self.handful && ev.amount == 1 do split = ev
		if split != nil && string(ev.kind) == "changed" && ev.subject == unit && ev.group == split.group &&
		   ev.detail != nil && string(ev.detail) == "Body.bent" {
			return true
		}
	}
	return false
}


/* The same in parts: run boundaries up to a time; carry on in another world
 * (restored from a save of this one); finish and check. */
marked_nail_run_until :: proc(self: ^Marked_Nail, t: Time) {
	scheduler_run_until(self.scheduler, t)
}


marked_nail_resume_with_world :: proc(self: ^Marked_Nail, world: ^World, committer: ^Committer) {
	autorelease(self.world)
	self.world = retain(world)
	autorelease(self.committer)
	self.committer = retain(committer)
	autorelease(self.activities)
	self.activities = retain(activities_with_world(world, committer))
	autorelease(self.scheduler)
	self.scheduler = scheduler_init_with_world(world, committer)
	scheduler_set_activities(self.scheduler, activities_as_activity_clock(self.activities))
	scheduler_set_inputs(self.scheduler, marked_nail_as_input_source(self))
	scheduler_set_observer(self.scheduler, marked_nail_as_scheduler_observer(self))
}


/* Runs the input log to its end, then the final checks. */
marked_nail_run :: proc(self: ^Marked_Nail) {
	marked_nail_run_until(self, time_make(120000))
	marked_nail_finish(self)
}


marked_nail_finish :: proc(self: ^Marked_Nail) {
	stone: ^Tombstone
	body:  ^Body
	kbody: uint

	scheduler_run_until(self.scheduler, time_make(120000))
	kbody = world_kind_named(self.world, "Body")

	marked_nail_check(self, self.invariantsHeld,
	                  "1. count and mass are conserved exactly",
	                  "see the invariants failure above")
	marked_nail_check(self, self.invariantsHeld,
	                  "2. location is exclusive at every boundary",
	                  "see the invariants failure above")

	switch self.variant {
	case .Base:
		body = (^Body)(world_record(self.world, kbody, self.nail)) if self.nail != 0 else nil
		marked_nail_check(self, self.nail != 0 && !world_is_stack(self.world, self.nail) && body != nil && body.bent &&
		                        body.toolMarks == 3 && marked_nail_split_in_group_that_marked(self, self.nail),
		                  "3. marking one nail in a stack split it off first, unasked",
		                  fmt.tprintf("nail %d", self.nail))
		marked_nail_check(self, world_is_live(self.world, self.nail) && world_location_of(self.world, self.nail).form == .In &&
		                        world_location_of(self.world, self.nail).place == self.bin &&
		                        marked_nail_trace_contains(self, "units differ physically: one is bent"),
		                  "4a. the bent nail's merge reaction was rejected, with the reason",
		                  "no rejection naming the bend")
		marked_nail_check(self, self.explicitMerge != nil && !proposal_group_applied(self.explicitMerge) &&
		                        ns_contains(proposal_group_rejection(self.explicitMerge), "bent"),
		                  "4b. a merge proposed outright is rejected, with the reason",
		                  proposal_group_rejection(self.explicitMerge) if self.explicitMerge != nil else "")
		stone = world_tombstone(self.world, self.handful)
		marked_nail_check(self, stone != nil && stone.successor == self.stack && world_resolve(self.world, self.handful) == self.stack,
		                  "5. the merged handful resolves through its tombstone to the bin stack",
		                  world_describe_entity(self.world, self.handful))
		marked_nail_check(self, world_units_of(self.world, self.stack) == 29 && world_mass_of(self.world, self.stack) == 87,
		                  "the bin stack holds 29 nails, 87g",
		                  world_describe_entity(self.world, self.stack))
		marked_nail_check(self, world_claimed_units_of(self.world, self.stack) == 30 &&
		                        world_claim_allocation_resolved(self.world, self.claim),
		                  "6. the smith's claim covers the bin stack and the bent nail, resolved",
		                  world_describe_entity(self.world, self.claim))

	case .Unmarked:
		marked_nail_check(self, self.nail != 0 && world_tombstone(self.world, self.nail) != nil &&
		                        world_resolve(self.world, self.nail) == self.stack,
		                  "A. the unmarked nail merged back; a reference to it resolves to the bin stack",
		                  world_describe_entity(self.world, self.nail))
		marked_nail_check(self, world_units_of(self.world, self.stack) == 30,
		                  "A. the bin stack holds all 30 again",
		                  world_describe_entity(self.world, self.stack))
		marked_nail_check(self, world_claim_allocation_resolved(self.world, self.claim),
		                  "A. the smith's claim is resolved",
		                  world_describe_entity(self.world, self.claim))

	case .Mixed_Goods:
		marked_nail_check(self, world_resolve(self.world, self.workerStack) == self.stack &&
		                        world_units_of(self.world, self.stack) == 35,
		                  "B. the worker's nails merged into the bin; 5 were then taken",
		                  world_describe_entity(self.world, self.stack))
		marked_nail_check(self, world_claimed_units_of(self.world, self.stack) == 40,
		                  "6a. the quantity claims summed on merge (30 + 10)",
		                  fmt.tprintf("%d", world_claimed_units_of(self.world, self.stack)))
		marked_nail_check(self, !world_claim_allocation_resolved(self.world, self.claim) &&
		                        !world_claim_allocation_resolved(self.world, self.workerClaim) &&
		                        world_claimed_units_of(self.world, self.handful) == 40,
		                  "6b. after the split, whose nails were taken is explicitly unresolved",
		                  fmt.tprintf("%s / %s", world_describe_entity(self.world, self.claim),
		                              world_describe_entity(self.world, self.workerClaim)))
	}
}

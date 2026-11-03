package lab

// The lab's tests, part 1 of 3: test/BGTests.m, lines 1–3846 (stores and the
// registry, commitment, the scheduler, the marked nail, the action menu,
// activities, the command interface, knowledge, agency, the rumour,
// salience, traces, and the pump's wear up to pump_work). The test table,
// TESTS, is in part 3.
//
// The split file's rules: every static helper, static variable and helper
// class is package-level, so the other parts can call it; a helper whose
// name doesn't start with test_ takes the prefix (commit_create →
// test_commit_create); a helper class is a type by the usual rule
// (BGPingReactor → Ping_Reactor). Two helpers, prefixed, would meet the
// tests they serve: missing_nails and rumour take a trailing underscore
// (test_missing_nails_, test_rumour_), as a name meeting a keyword does.

import "core:fmt"
import "core:slice"
import "core:strings"
import tri "../../triangle/odin/triangle"


/* --- stores and the registry ------------------------------------------------ */

test_store :: proc() {
	store: ^Store
	v:     i64

	store = autorelease(store_init_with_record_size(size_of(i64)))
	v = 30
	store_set_record(store, &v, 30)
	v = 10
	store_set_record(store, &v, 10)
	v = 20
	store_set_record(store, &v, 20)
	bg_check(store_count(store) == 3)
	bg_check(store_entity_at_index(store, 0) == 10 && store_entity_at_index(store, 1) == 20 && store_entity_at_index(store, 2) == 30)
	v = 21
	store_set_record(store, &v, 20)
	bg_check(store_count(store) == 3 && (^i64)(store_record_for(store, 20))^ == 21)
	store_remove_record_for(store, 10)
	bg_check(store_count(store) == 2 && store_record_for(store, 10) == nil && store_entity_at_index(store, 0) == 20)
}


test_commit_create :: proc(committer: ^Committer, blueprint: cstring, at: Location) -> Entity_ID {
	g: ^Proposal_Group
	h: Entity_ID

	g = proposal_group_group_with_phase(.System, "create")
	h = proposal_group_create(g, blueprint, blueprint, at)
	committer_submit(committer, g)
	committer_commit_boundary(committer)
	return proposal_group_id_for(g, h) if proposal_group_applied(g) else NO_ENTITY
}


test_registry_and_construction :: proc() {
	w:     ^World
	c:     ^Committer
	bin:   Entity_ID
	nails: Entity_ID
	v:     i64
	stack: ^Stack

	w = test_world(1)
	c = test_committer(w)
	bg_check(world_kind_count(w) == 40)
	bg_check(world_kind_named(w, "Body") != NOT_FOUND && world_kind_named(w, "Nonesuch") == NOT_FOUND)
	bin   = test_commit_create(c, "bin", on_tile(0, 0, 0))
	nails = test_commit_create(c, "nails_30", in_(bin))
	bg_check(bin == 1 && nails == 2)
	bg_check(world_get_field(w, "Body.mass", bin, &v) && v == 4000)
	bg_check(world_get_field(w, "Container.capacity", bin, &v) && v == 50)
	/* the stack's mass comes from Triangle arithmetic: 30 × 3 g */
	bg_check(world_get_field(w, "Body.mass", nails, &v) && v == 90)
	stack = (^Stack)(world_record(w, world_kind_named(w, "Stack"), nails))
	bg_check(stack != nil && stack.count == 30 && string(stack.unit) == "iron_nail")
	bg_check(world_is_physical(w, nails) && world_is_stack(w, nails) && !world_is_stack(w, bin))
	bg_check(ns_contains(world_describe_entity(w, nails), "Body.mass=90g"))
	bg_check(!world_get_field(w, "Body.nonesuch", bin, &v))
}


test_rollback :: proc() {
	w:      ^World
	c:      ^Committer
	bin:    Entity_ID
	e:      Entity_ID
	ev:     Event
	before: u64

	w      = test_world(1)
	c      = test_committer(w)
	bin    = test_commit_create(c, "bin", on_tile(0, 0, 0))
	before = world_state_hash(w)
	world_begin_group(w)
	e = world_allocate_id(w)
	world_add_entity(w, e, "nails_30", 5)
	bg_check(world_construct(w, e, nil))
	world_set_location(w, in_(bin), e)
	world_add_edge(w, .Split_From, e, bin)
	world_set_field_of_value(w, "Body.mass", bin, 1)
	ev = {}
	ev.kind = "test"
	world_emit(w, ev)
	bg_check(world_state_hash(w) != before)
	world_rollback_group(w)
	bg_check(world_state_hash(w) == before)
	bg_check(!world_is_live(w, e) && world_next_id(w) == e && !world_has_edge(w, .Split_From, e, bin))
}


/* --- commitment ------------------------------------------------------------- */

test_validation :: proc() {
	w:      ^World
	c:      ^Committer
	g:      ^Proposal_Group
	bin:    Entity_ID
	nails:  Entity_ID
	worker: Entity_ID
	claim:  Entity_ID
	before: u64

	w      = test_world(1)
	c      = test_committer(w)
	bin    = test_commit_create(c, "bin", on_tile(0, 0, 0))
	nails  = test_commit_create(c, "nails_30", in_(bin))
	worker = test_commit_create(c, "worker", on_tile(1, 0, 0))
	claim  = test_commit_create(c, "ownership", location_make_none())
	bg_check(claim != NO_ENTITY && !world_is_physical(w, claim))
	bg_check(test_commit_create(c, "bin", location_make_none()) == NO_ENTITY)      /* physical needs a location */
	bg_check(test_commit_create(c, "nonesuch", on_tile(0, 0, 0)) == NO_ENTITY)
	before = world_state_hash(w)

	/* mass can't change without a declared process */
	g = proposal_group_group_with_phase(.System, "t")
	proposal_group_set_of_to(g, "Body.mass", whole(nails), 91)
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "mass is not conserved"))

	/* only proposable fields */
	g = proposal_group_group_with_phase(.System, "t")
	proposal_group_set_of_to(g, "Body.material", whole(nails), 1)
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "not proposable"))

	/* informational entities have no location */
	g = proposal_group_group_with_phase(.System, "t")
	proposal_group_move_to(g, whole(claim), on_tile(0, 0, 0))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(!proposal_group_applied(g))

	/* one hand holds one thing; one bad proposal rejects the whole group */
	g = proposal_group_group_with_phase(.System, "t")
	proposal_group_split(g, whole(nails), 2, held_by(worker, 0))
	proposal_group_split(g, whole(nails), 3, held_by(worker, 0))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "already holds"))
	g = proposal_group_group_with_phase(.System, "t")
	proposal_group_split(g, whole(nails), 2, held_by(worker, 2))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "no hand 2"))

	/* nothing goes inside itself */
	g = proposal_group_group_with_phase(.System, "t")
	proposal_group_move_to(g, whole(bin), in_(bin))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(!proposal_group_applied(g))

	/* tombstones and unknown entities are refused */
	g = proposal_group_group_with_phase(.System, "t")
	proposal_group_move_to(g, whole(999), in_(bin))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "does not exist"))

	bg_check(world_state_hash(w) == before)
}


test_individuation_and_merge_rules :: proc() {
	w:     ^World
	c:     ^Committer
	g:     ^Proposal_Group
	bin:   Entity_ID
	nails: Entity_ID
	other: Entity_ID
	parts: [4]Entity_ID
	lock:  Entity_ID

	w     = test_world(1)
	c     = test_committer(w)
	bin   = test_commit_create(c, "bin", on_tile(0, 0, 0))
	nails = test_commit_create(c, "nails_30", in_(bin))
	lock  = test_commit_create(c, "lock", on_tile(2, 0, 0))

	/* addressing one unit splits it off: the stack keeps 29, the unit is an individual */
	g = proposal_group_group_with_phase(.System, "t")
	proposal_group_set_of_to(g, "Body.toolMarks", unit(nails, 1), 2)
	proposal_group_move_to(g, unit(nails, 1), part_of(lock, "pin", 0))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(proposal_group_applied(g))
	if !proposal_group_applied(g) do fmt.eprintf("DEBUG %s\n", proposal_group_rejection(g))
	bg_check(world_units_of(w, nails) == 29 && world_mass_of(w, nails) == 87)
	bg_check(world_entities_at(w, lock, .Part_Of, &parts[0], 4) == 1)
	bg_check(!world_is_stack(w, parts[0]) && world_mass_of(w, parts[0]) == 3)
	bg_check(world_has_edge(w, .Split_From, parts[0], nails))
	bg_check(string(world_unit_of(w, parts[0])) == "iron_nail")

	/* merging needs the same place, the same unit, and no marks */
	other = test_commit_create(c, "nails_10", on_tile(0, 0, 0))
	g = proposal_group_group_with_phase(.System, "t")
	proposal_group_merge(g, whole(other), whole(nails))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "not in the same place"))
	g = proposal_group_group_with_phase(.System, "t")
	proposal_group_merge(g, whole(lock), whole(nails))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "different units"))
	g = proposal_group_group_with_phase(.System, "t")
	proposal_group_move_to(g, whole(parts[0]), on_tile(0, 0, 0))
	proposal_group_merge(g, whole(parts[0]), whole(other))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "tool marks"))

	/* the Body reaction merges a clean stack put into the bin */
	g = proposal_group_group_with_phase(.Action, "t")
	proposal_group_move_to(g, whole(other), in_(bin))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(world_units_of(w, nails) == 39 && world_resolve(w, other) == nails)
	bg_check(world_tombstone(w, other) != nil && string(cstring(&world_tombstone(w, other).reason[0])) == "merged")

	/* a claim on one unit alone pins it; a quantity claim over several entities follows the units */
	{
		claim: Entity_ID
		unit_: Entity_ID
		h:     Entity_ID

		claim = test_commit_create(c, "ownership", location_make_none())
		g     = proposal_group_group_with_phase(.System, "t")
		h     = proposal_group_split(g, whole(nails), 1, in_(bin))
		proposal_group_relate(g, .Claim_Subject, whole(claim), whole(h))
		committer_submit(c, g)
		committer_commit_boundary(c)
		unit_ = proposal_group_id_for(g, h)
		bg_check(proposal_group_applied(g) && !world_is_stack(w, unit_))
		g = proposal_group_group_with_phase(.System, "t")
		proposal_group_merge(g, whole(unit_), whole(nails))
		committer_submit(c, g)
		committer_commit_boundary(c)
		bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "claim is on this unit alone"))
		g = proposal_group_group_with_phase(.System, "t")
		proposal_group_relate(g, .Claim_Subject, whole(claim), whole(nails))
		proposal_group_merge(g, whole(unit_), whole(nails))
		committer_submit(c, g)
		committer_commit_boundary(c)
		bg_check(proposal_group_applied(g) && world_resolve(w, unit_) == nails && world_has_edge(w, .Claim_Subject, claim, nails))
	}
}


/* Two groups want the same hand: the seeded order decides, the same way for
 * the same seed, and over many seeds neither wins every time. */
test_winner :: proc(seed: u64) -> Entity_ID {
	w:      ^World
	c:      ^Committer
	a:      ^Proposal_Group
	b:      ^Proposal_Group
	bin:    Entity_ID
	nails:  Entity_ID
	worker: Entity_ID

	w      = test_world(seed)
	c      = test_committer(w)
	bin    = test_commit_create(c, "bin", on_tile(0, 0, 0))
	nails  = test_commit_create(c, "nails_30", in_(bin))
	worker = test_commit_create(c, "worker", on_tile(1, 0, 0))
	world_set_boundary(w, 7)
	a = proposal_group_group_with_phase(.Action, "a")
	proposal_group_split(a, whole(nails), 2, held_by(worker, 0))
	b = proposal_group_group_with_phase(.Action, "b")
	proposal_group_split(b, whole(nails), 3, held_by(worker, 0))
	committer_submit(c, a)
	committer_submit(c, b)
	committer_commit_boundary(c)
	if proposal_group_applied(a) == proposal_group_applied(b) do return 0
	return 2 if proposal_group_applied(a) else 3
}


test_seeded_order :: proc() {
	seed:   u64
	twos:   i32
	threes: i32
	w:      Entity_ID

	twos   = 0
	threes = 0
	for seed = 1; seed <= 24; seed += 1 {
		w = test_winner(seed)
		bg_check(w != 0)
		bg_check(test_winner(seed) == w)
		if w == 2 do twos += 1
		if w == 3 do threes += 1
	}
	/* over many seeds, neither group wins every time */
	bg_check(twos > 0 && threes > 0)
}


/* A reactor that answers every ping with another: the rounds bound cuts it
 * off, and the rest is deferred to the next boundary. */
Ping_Reactor :: struct {
	using object: Object,
}

// [BGPingReactor new]
ping_reactor_new :: proc() -> ^Ping_Reactor {
	return object_new(Ping_Reactor, nil)
}

ping_reactor_react_to_event :: proc(self: ^Ping_Reactor, committer: ^Committer, event: ^Event, world: ^World) {
	g: ^Proposal_Group

	if string(event.kind) != "ping" do return
	g = proposal_group_group_with_phase(.System, "pong")
	proposal_group_set_cause(g, event.index)
	proposal_group_emit_subject_other(g, "ping", whole(event.subject), whole(NO_ENTITY))
	committer_submit(committer, g)
}

ping_reactor_as_reactor :: proc(self: ^Ping_Reactor) -> Reactor {
	return Reactor{
		data = self,
		react_to_event = proc(data: rawptr, committer: ^Committer, event: ^Event, world: ^World) {
			ping_reactor_react_to_event((^Ping_Reactor)(data), committer, event, world)
		},
	}
}


test_reaction_rounds :: proc() {
	w:      ^World
	c:      ^Committer
	g:      ^Proposal_Group
	claim:  Entity_ID
	groups: []^Proposal_Group
	trace:  []string

	w     = test_world(1)
	c     = test_committer(w)
	committer_add_reactor(c, ping_reactor_as_reactor(autorelease(ping_reactor_new())), "Claim")
	claim = test_commit_create(c, "ownership", location_make_none())
	committer_set_rounds(c, 3)
	g = proposal_group_group_with_phase(.System, "ping")
	proposal_group_emit_subject_other(g, "ping", whole(claim), whole(NO_ENTITY))
	committer_submit(c, g)
	groups = committer_commit_boundary(c)
	bg_check(len(groups) == 3)
	bg_check(committer_has_pending(c))
	/* an empty trace's lastObject is nil, and [nil rangeOfString:] is at 0, found */
	trace = committer_trace(c)
	bg_check(len(trace) == 0 || ns_contains(trace[len(trace) - 1], "deferred to the next boundary"))
	/* each reaction's event names its cause */
	bg_check(world_event_at(w, world_event_count(w) - 1).cause == world_event_at(w, world_event_count(w) - 2).index)
}


/* --- the scheduler ---------------------------------------------------------- */

Test_Domain :: struct {
	using object: Object,
	steps:  [16][2]i64,
	nsteps: i32,
}

// [BGTestDomain new]
test_domain_new :: proc() -> ^Test_Domain {
	return object_new(Test_Domain, nil)
}

test_domain_name :: proc(self: ^Test_Domain) -> string {
	return "test"
}

test_domain_is_active :: proc(self: ^Test_Domain) -> bool {
	return true
}

test_domain_horizon_at :: proc(self: ^Test_Domain, t: Time) -> Horizon {
	h: Horizon

	h.safeStep  = time_make(1000)
	h.nextEvent = time_make(300) if t.ms < 300 else time_make(700) if t.ms < 700 else TIME_NEVER
	return h
}

test_domain_check_in_all :: proc(self: ^Test_Domain) {
}

test_domain_saved_state :: proc(self: ^Test_Domain) -> []string {
	return make([]string, 0, context.temp_allocator)
}

test_domain_restore_saved_state :: proc(self: ^Test_Domain, lines: []string) {
}

test_domain_advance_from :: proc(self: ^Test_Domain, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	if self.nsteps < 16 {
		self.steps[self.nsteps][0] = t0.ms
		self.steps[self.nsteps][1] = t1.ms
		self.nsteps += 1
	}
}

test_domain_as_domain :: proc(self: ^Test_Domain) -> Domain {
	return Domain{
		data                = self,
		name                = proc(data: rawptr) -> string {return test_domain_name((^Test_Domain)(data))},
		check_in_all        = proc(data: rawptr) {test_domain_check_in_all((^Test_Domain)(data))},
		saved_state         = proc(data: rawptr) -> []string {return test_domain_saved_state((^Test_Domain)(data))},
		restore_saved_state = proc(data: rawptr, lines: []string) {test_domain_restore_saved_state((^Test_Domain)(data), lines)},
		is_active           = proc(data: rawptr) -> bool {return test_domain_is_active((^Test_Domain)(data))},
		horizon_at          = proc(data: rawptr, t: Time) -> Horizon {return test_domain_horizon_at((^Test_Domain)(data), t)},
		advance_from        = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
			test_domain_advance_from((^Test_Domain)(data), t0, t1, world, committer)
		},
	}
}


test_scheduler_horizons :: proc() {
	w: ^World
	c: ^Committer
	s: ^Scheduler
	d: ^Test_Domain
	n: uint

	w = test_world(1)
	c = test_committer(w)
	s = autorelease(scheduler_init_with_world(w, c))
	d = autorelease(test_domain_new())
	scheduler_add_domain(s, test_domain_as_domain(d))
	n = scheduler_run_until(s, time_make(2000))
	/* events bound the first steps; the safe step bounds the next; the stop is a boundary too */
	bg_check(n == 4)
	bg_check(d.nsteps == 4)
	bg_check(d.steps[0][1] == 300 && d.steps[1][1] == 700 && d.steps[2][1] == 1700)
	bg_check(d.steps[3][0] == 1700 && d.steps[3][1] == 2000)
	bg_check(world_time(w).ms == 2000 && world_boundary(w) == 4)
}


/* --- the marked nail -------------------------------------------------------- */

test_run_marked_nail :: proc(variant: Marked_Nail_Variant, seed: u64) -> ^Marked_Nail {
	w:        ^World
	scenario: ^Marked_Nail

	w        = test_world(seed)
	scenario = autorelease(marked_nail_init_with_world(w, test_committer(w), variant))
	marked_nail_run(scenario)
	return scenario
}


test_check_scenario :: proc(scenario: ^Marked_Nail) {
	results: []string
	i:       uint

	results = marked_nail_results(scenario)
	for i = 0; i < uint(len(results)); i += 1 {
		if ns_has_prefix(results[i], "FAIL") do fmt.eprintf("    %s\n", results[i])
	}
	bg_check(len(results) > 0)
	bg_check(marked_nail_failure_count(scenario) == 0)
}


test_marked_nail :: proc() {
	test_check_scenario(test_run_marked_nail(.Base, 42))
}


test_marked_nail_a :: proc() {
	test_check_scenario(test_run_marked_nail(.Unmarked, 42))
}


test_marked_nail_b :: proc() {
	test_check_scenario(test_run_marked_nail(.Mixed_Goods, 42))
}


/* Acceptance check 7: a replay is bit-identical, IDs and state and trace. */
test_marked_nail_replay :: proc() {
	a:     ^Marked_Nail
	b:     ^Marked_Nail
	other: ^Marked_Nail

	a     = test_run_marked_nail(.Base, 42)
	b     = test_run_marked_nail(.Base, 42)
	other = test_run_marked_nail(.Base, 43)
	bg_check(world_state_hash(marked_nail_world(a)) == world_state_hash(marked_nail_world(b)))
	bg_check(world_next_id(marked_nail_world(a)) == world_next_id(marked_nail_world(b)))
	bg_check(slice.equal(committer_trace(marked_nail_committer(a)), committer_trace(marked_nail_committer(b))))
	/* another world seed draws other seeds, but the story comes out the same */
	bg_check(marked_nail_failure_count(other) == 0)
	bg_check(world_state_hash(marked_nail_world(other)) != world_state_hash(marked_nail_world(a)))
}


/* --- the action menu ------------------------------------------------------- */

test_menu_text :: proc(w: ^World, actor: Entity_ID) -> string {
	menu:  ^Menu
	lines: [dynamic]string
	i:     uint

	menu  = menu_for_world(actor, w)
	lines = make([dynamic]string, context.temp_allocator)
	for i = 0; i < menu_count(menu); i += 1 do append(&lines, menu_describe_at(menu, i))
	return strings.join(lines[:], "; ", context.temp_allocator)
}


test_menu :: proc() {
	w:        ^World
	c:        ^Committer
	scenario: ^Marked_Nail
	g:        ^Proposal_Group
	arena:    ^tri.Arena
	r:        tri.Match_Result
	error:    string
	text:     string
	seen:     ^tri.Node
	wants:    ^tri.Node

	/* the workshop: bin 1 holding nails 2, lock 3, worker 4, smith 5 (out of reach) */
	w        = test_world(42)
	c        = test_committer(w)
	scenario = autorelease(marked_nail_init_with_world(w, c, .Base))
	marked_nail_run_until(scenario, time_make(0))
	text = test_menu_text(w, 4)
	bg_check(text == "look_in item 1: entailed; take item 1: entailed; take item 2: entailed; " +
	                 "take item 3: entailed; take_some item 2: entailed; take_up item 1: entailed; " +
	                 "take_up item 2: entailed; take_up item 3: entailed; test_scratch item 1: entailed; " +
	                 "test_scratch item 3: entailed; touch_up item 3: entailed; " +
	                 "walk_east: entailed; walk_north: entailed; walk_south: entailed; walk_west: entailed; " +
	                 "wash_floor: entailed; watch_closely: entailed; while_away: entailed")
	if !ns_contains(text, "watch_closely: entailed; while_away: entailed") do fmt.eprintf("    menu: %s\n", text)

	/* a description carries perceivable fields only: the stack's count is hidden */
	text = view_describe_entity(view_of(4, w), 2)
	bg_check(ns_has_prefix(text, "#Stack & { id: ref(2), place: #Inside & { container: ref(1) }"))
	bg_check(ns_contains(text, "unit: \"iron_nail\""))
	bg_check(!ns_contains(text, "count"))
	/* so a pattern on the count is unknown, never incompatible, and says what to find out */
	arena = tri.arena_new()
	seen  = tri.value(world_tri(w), ns_utf8(text), arena, nil, 0)
	wants = tri.value(world_tri(w), "#Stack & { count: >=5 }", arena, nil, 0)
	bg_check(seen != nil && wants != nil && tri.match(world_tri(w), wants, seen, &r) == .Unknown)
	bg_check(r.nresidual == 1 && string(cstring(&r.residual[0][0])) == "count")
	tri.arena_free(arena)

	/* what isn't on the menu can't be performed */
	error = ""
	bg_check(perform(w, c, action_make("put_in", 4, 2, 1), 0, &error) == nil)
	bg_check(ns_contains(error, "ruled out at roles.item.place"))
	bg_check(perform(w, c, action_make("take", 4, 5, NO_ENTITY), 0, &error) == nil)
	bg_check(ns_contains(error, "not in the actor's reach"))
	bg_check(perform(w, c, action_make("fly", 4, NO_ENTITY, NO_ENTITY), 0, &error) == nil)
	bg_check(perform(w, c, action_make("take_some", 4, 2, NO_ENTITY), 0, &error) == nil)
	bg_check(ns_contains(error, "how many"))

	/* take five: then they can be put back, driven, or split between hands */
	g = perform(w, c, action_make("take_some", 4, 2, NO_ENTITY), 5, &error)
	bg_check(g != nil)
	world_set_boundary(w, world_boundary(w) + 1)
	committer_commit_boundary(c)
	bg_check(proposal_group_applied(g) && proposal_group_id_for(g, proposal_group_proposals(g)[0].handle) == 7)      /* the claim is 6 */
	text = test_menu_text(w, 4)
	bg_check(ns_contains(text, "put_in item 7 destination 1: entailed"))
	bg_check(ns_contains(text, "drive item 7 destination 3: entailed"))
	bg_check(ns_contains(text, "take_some item 7: entailed"))
	/* the bin is no assembly, and the lock no container */
	bg_check(!ns_contains(text, "drive item 7 destination 1"))
	bg_check(!ns_contains(text, "put_in item 7 destination 3"))
}


/* --- activities ------------------------------------------------------------ */

test_status_of :: proc(w: ^World, a: Entity_ID) -> cstring {
	record: ^Activity

	record = (^Activity)(world_record(w, world_kind_named(w, "Activity"), a))
	return tri.type_name(world_tri(w), tri.Type(record.status)) if record != nil else "none"
}


/* A timed activity whose item merges away before it is due: the recheck
 * suspends it (a hard interruption), and it can't be resumed. */
test_activity_interrupted :: proc() {
	w:          ^World
	c:          ^Committer
	s:          ^Scheduler
	activities: ^Activities
	g:          ^Proposal_Group
	bin:        Entity_ID
	nails:      Entity_ID
	lock:       Entity_ID
	worker:     Entity_ID
	handful:    Entity_ID
	a:          Entity_ID
	error:      string

	w          = test_world(5)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	s          = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	bin    = test_commit_create(c, "bin", on_tile(0, 0, 0))
	nails  = test_commit_create(c, "nails_30", in_(bin))
	lock   = test_commit_create(c, "lock", on_tile(2, 0, 0))
	worker = test_commit_create(c, "worker", on_tile(1, 0, 0))

	g = perform(w, c, action_make("take_some", worker, nails, NO_ENTITY), 5, &error)
	scheduler_run_until(s, time_make(10))
	handful = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	bg_check(world_units_of(w, handful) == 5)

	g = perform(w, c, action_make("drive", worker, handful, lock), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(s, time_make(20))
	a = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	bg_check(string(test_status_of(w, a)) == "\"running\"")
	bg_check(activities_next_completion(activities).ms == 10 + 4000)      /* from the command, at 10ms */
	bg_check(world_units_of(w, handful) == 5)                           /* nothing happens until it is due */

	/* the nails go back in the bin and merge away before the drive is due */
	perform(w, c, action_make("put_in", worker, handful, bin), 0, &error)
	scheduler_run_until(s, time_make(30))
	bg_check(world_resolve(w, handful) == nails)
	bg_check(string(test_status_of(w, a)) == "\"suspended\"")
	bg_check(activities_resume(activities, a, &error) == nil && ns_contains(error, "is gone"))
	scheduler_run_until(s, time_make(6000))
	bg_check(activities_next_completion(activities).ms == TIME_NEVER.ms)
	bg_check(world_units_of(w, nails) == 30)
}


/* A completion commitment rejects fails its activity: the lock has four
 * slots, and the fifth nail has nowhere to go. */
test_activity_fails :: proc() {
	w:          ^World
	c:          ^Committer
	s:          ^Scheduler
	activities: ^Activities
	g:          ^Proposal_Group
	bin:        Entity_ID
	nails:      Entity_ID
	lock:       Entity_ID
	worker:     Entity_ID
	handful:    Entity_ID
	a:          Entity_ID
	parts:      [8]Entity_ID
	error:      string
	i:          i32

	w          = test_world(5)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	s          = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	bin    = test_commit_create(c, "bin", on_tile(0, 0, 0))
	nails  = test_commit_create(c, "nails_30", in_(bin))
	lock   = test_commit_create(c, "lock", on_tile(2, 0, 0))
	worker = test_commit_create(c, "worker", on_tile(1, 0, 0))
	g = perform(w, c, action_make("take_some", worker, nails, NO_ENTITY), 10, &error)
	scheduler_run_until(s, time_make(10))
	handful = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	a       = NO_ENTITY
	for i = 0; i < 5; i += 1 {
		g = perform(w, c, action_make("drive", worker, handful, lock), 0, &error)
		scheduler_run_until(s, time_make(world_time(w).ms + 5000))
		a = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	}
	bg_check(world_entities_at(w, lock, .Part_Of, &parts[0], 8) == 4)
	bg_check(string(test_status_of(w, a)) == "\"failed\"")
	bg_check(world_units_of(w, handful) == 6)
}


/* Two stages, walked away from and come back to: progress is kept across a
 * suspension, and resuming runs only what is left. */
/* ACTIONS.md §2: costs, wear and traces among them, are "committed per
 * stage". Prying a nail out of the lock: its loosening stage (3 s) leaves a
 * scratch on the nail with its own effect, two seconds before the pulling
 * stage completes the activity. */
test_bears_kind :: proc(w: ^World, bearer: Entity_ID, kind: cstring) -> bool {
	traces: ^Store
	i:      uint
	text:   cstring

	traces = world_store_for_kind(w, world_kind_named(w, "Trace"))
	for i = 0; i < store_count(traces); i += 1 {
		text = world_text_field(w, "Trace.traceKind", store_entity_at_index(traces, i))
		if text != nil && string(text) == string(kind) &&
		   Entity_ID((^Trace)(store_record_at_index(traces, i)).bearer) == bearer {
			return true
		}
	}
	return false
}


test_stage_traces :: proc() {
	w:      ^World
	c:      ^Committer
	s:      ^Scheduler
	g:      ^Proposal_Group
	lock:   Entity_ID
	worker: Entity_ID
	nail:   Entity_ID
	a:      Entity_ID
	error:  string

	w      = test_world(5)
	c      = test_committer(w)
	s      = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities_with_world(w, c)))
	lock   = test_commit_create(c, "lock", on_tile(2, 0, 0))
	worker = test_commit_create(c, "worker", on_tile(1, 0, 0))
	nail   = test_commit_create(c, "iron_nail", part_of(lock, "wedge", 0))
	error  = ""
	g      = perform(w, c, action_make("pry_out", worker, nail, NO_ENTITY), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(s, time_make(2000))
	a = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	bg_check(!test_bears_kind(w, nail, "scratch"))
	scheduler_run_until(s, time_make(3500))
	bg_check(string(test_status_of(w, a)) == "\"running\"" && test_bears_kind(w, nail, "scratch"))
	scheduler_run_until(s, time_make(6000))
	bg_check(string(test_status_of(w, a)) == "\"completed\"" && world_location_of(w, nail).place == worker)
}


test_stages_and_suspension :: proc() {
	w:          ^World
	c:          ^Committer
	s:          ^Scheduler
	activities: ^Activities
	g:          ^Proposal_Group
	lock:       Entity_ID
	worker:     Entity_ID
	nail:       Entity_ID
	a:          Entity_ID
	error:      string
	v:          i64
	record:     ^Activity

	w          = test_world(5)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	s          = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	lock   = test_commit_create(c, "lock", on_tile(2, 0, 0))
	worker = test_commit_create(c, "worker", on_tile(1, 0, 0))
	nail   = test_commit_create(c, "iron_nail", part_of(lock, "wedge", 0))

	/* pry it out: 3 s loosening, 2 s pulling */
	g = perform(w, c, action_make("pry_out", worker, nail, NO_ENTITY), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(s, time_make(1000))
	a = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	bg_check(string(test_status_of(w, a)) == "\"running\"")

	/* a second in, the worker walks away: the prying goes on while it walks
	 * (hands and legs), and is suspended when it arrives out of reach, with
	 * the two seconds kept */
	bg_check(perform(w, c, action_make("walk_west", worker, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(1999))
	bg_check(string(test_status_of(w, a)) == "\"running\"" && world_location_of(w, worker).x == 1)
	/* one walk at a time: its legs are busy */
	bg_check(perform(w, c, action_make("walk_east", worker, NO_ENTITY, NO_ENTITY), 0, &error) == nil &&
	         ns_contains(error, "its legs are busy with activity"))
	scheduler_run_until(s, time_make(2000))
	record = (^Activity)(world_record(w, world_kind_named(w, "Activity"), a))
	bg_check(world_location_of(w, worker).x == 0)
	bg_check(string(test_status_of(w, a)) == "\"suspended\"" && record.progress == 2000 && record.stage == 0)
	bg_check(activities_resume(activities, a, &error) == nil && ns_contains(error, "out of reach"))
	scheduler_run_until(s, time_make(10000))
	bg_check(world_get_field(w, "Body.toolMarks", nail, &v) && v == 0)      /* nothing happened meanwhile */

	/* back, and resumed at 11 s: what is left of the loosening, then 2 s of pulling */
	perform(w, c, action_make("walk_east", worker, NO_ENTITY, NO_ENTITY), 0, &error)
	scheduler_run_until(s, time_make(11000))
	bg_check(activities_resume(activities, a, &error) != nil)
	scheduler_run_until(s, time_make(11001))
	record = (^Activity)(world_record(w, world_kind_named(w, "Activity"), a))
	bg_check(record.due == 11000 + 1000)
	scheduler_run_until(s, time_make(12000))
	bg_check(world_get_field(w, "Body.toolMarks", nail, &v) && v == 1)      /* loosened */
	record = (^Activity)(world_record(w, world_kind_named(w, "Activity"), a))
	bg_check(record.stage == 1 && record.due == 12000 + 2000)
	scheduler_run_until(s, time_make(14001))
	bg_check(string(test_status_of(w, a)) == "\"completed\"")
	bg_check(world_location_of(w, nail).form == .Held_By && world_location_of(w, nail).place == worker)

	/* and suspended by choice, then resumed: the same accounting */
	g = perform(w, c, action_make("drive", worker, nail, lock), 0, &error)
	scheduler_run_until(s, time_make(15001))
	a = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	bg_check(activities_suspend(activities, a, "a break", &error) != nil)
	scheduler_run_until(s, time_make(20000))
	bg_check(activities_resume(activities, a, &error) != nil)
	scheduler_run_until(s, time_make(20001))
	record = (^Activity)(world_record(w, world_kind_named(w, "Activity"), a))
	bg_check(record.progress == 1000 && record.due == 20000 + 3000)
}


/* --- the command interface ------------------------------------------------- */

test_session :: proc(world: string, commands: []string, hash: ^u64) -> string {
	play: ^Play
	out:  strings.Builder
	i:    uint

	play = play_world(world, 42, nil)
	out  = strings.builder_make(context.temp_allocator)
	strings.write_string(&out, play_take_output(play))
	for i = 0; i < uint(len(commands)); i += 1 {
		play_command(play, commands[i])
		strings.write_string(&out, play_take_output(play))
	}
	hash^ = world_state_hash(play_world(play))
	return strings.to_string(out)
}


/* A session in the workshop: look, take five nails, walk, drive one into the
 * lock, inspect it, and ask why. The same commands give the same world. */
test_play :: proc() {
	commands: []string
	out:      string
	again:    string
	h1:       u64
	h2:       u64

	commands = []string{"look", "menu", "do 1", "menu", "do 5 5", "walk w", "walk e", "menu",
	                    "do 1", "idle", "inspect 11", "why 11", "knows", "walk n", "walk n",
	                    "walk n", "walk n", "walk n", "look", "knows", "hash"}
	out   = test_session("workshop", commands, &h1)
	again = test_session("workshop", commands, &h2)
	bg_check(h1 == h2)
	bg_check(out == again)
	/* the map, from what the worker knows: the smith (A), the bin (u), itself (@), the lock (m) */
	bg_check(ns_contains(out, "Au@m"))
	/* the menu comes from the knowledge view: the nails only once it has looked into the bin */
	bg_check(ns_contains(out, " 1. look_in item R2 (#Container)"))
	bg_check(ns_contains(out, "you notice: R5: #Stack, at (3, 4)"))
	bg_check(ns_contains(out, " 5. take_some item R5 (#Stack)"))
	bg_check(ns_contains(out, "you notice: R6: #Stack, at (4, 4)"))
	bg_check(ns_contains(out, " 1. drive item R6 (#Stack) destination R3 (#Assembly)"))
	/* the drive completes as an activity, and the nail it split off is in the lock, bent */
	bg_check(ns_contains(out, "activity 10: drive completes"))
	bg_check(ns_contains(out, "Body.bent=true"))
	bg_check(ns_contains(out, "at partOf(3, wedge, 0)"))
	bg_check(ns_contains(out, "R7 #Body, seen at 6000ms, truth 11"))
	/* why: the move into the lock, in the drive's completion, because the worker started the drive */
	bg_check(ns_contains(out, "moved 11 to partOf(3, wedge, 0) at boundary 10, in \"activity 10: drive completes\"\n" +
	                          "because:\n  created 10 activity at boundary 9, in \"4: drive item 7 destination 3\""))
	/* walks are activities of a second each: two of them, so the drive is activity 10, and done at 6 s */
	bg_check(ns_contains(out, "activity 9: walk_east completes"))
	/* KNOWLEDGE.md Scenario 3's check 1: the map renders from the knowledge
	 * store, and what is remembered carries its age, never refreshed: the
	 * nails in the bin, last seen when it looked in, at the start */
	bg_check(ns_contains(out, "R5 #Stack in R2, as you saw it 11s ago"))
	bg_check(ns_contains(out, "R5 #Stack, seen at 0ms, truth 2"))
	/* the map's edge: the step off it fails when it would arrive */
	bg_check(ns_contains(out, "is off the map"))
	if !ns_contains(out, "is off the map") do fmt.eprintf("%s\n", out)
}


/* Talking in a session: the worker looks into the bin, steps over by the
 * smith, tells the smith where the nails are, asks where they are and who
 * said so, then takes them and says they are still in the bin: a lie. The
 * smith answers through agency. */
test_play_talk :: proc() {
	commands: []string
	take:     int
	out:      string
	again:    string
	h1:       u64
	h2:       u64

	/* taking the nails: whichever its menu number is, as operations come and go */
	commands = []string{"do 1", "walk w", "tell R4 R5", "ask R4 where R5", "ask R4 who R5", "menu"}
	out      = test_session("workshop", commands, &h1)
	take     = strings.last_index(out, ". take item R5 (#Stack)")      // -rangeOfString:options:NSBackwardsSearch, -1 for none
	bg_check(take >= 0 && take >= 2)
	if take < 0 || take < 2 do return
	commands = []string{"do 1", "walk w", "tell R4 R5", "ask R4 where R5", "ask R4 who R5",
	                    "menu",
	                    fmt.tprintf("do %d", ns_int_value(out[take - 2:][:2])),
	                    "tell R4 R5 in R2", "knows", "knows 5", "tell R4",
	                    "ask R4 where R99", "help"}
	out   = test_session("workshop", commands, &h1)
	again = test_session("workshop", commands, &h2)
	bg_check(h1 == h2)
	bg_check(out == again)
	/* told, from what the worker saw */
	bg_check(ns_contains(out, "said: 4, other 5, #IsIn & { what: #Stack"))
	bg_check(ns_contains(out, "attribution: #Saw & { sure: 30 } }"))
	/* asked, the smith answers, naming the worker by its coat */
	bg_check(ns_contains(out, "said: 4, other 5, #WhereIs"))
	bg_check(ns_contains(out, "you notice: R4 says to R1: #IsIn"))
	bg_check(ns_contains(out, "#Heard & { from: #Agent & {"))
	bg_check(ns_contains(out, "coat: \"blue\""))
	bg_check(ns_contains(out, "said: 4, other 5, #WhoToldYou"))
	/* the lie: the worker knows it didn't believe it, and the developer sees it made up */
	bg_check(ns_contains(out, "(not believed)"))
	bg_check(ns_contains(out, "truly made up by 4"))
	/* what it can't say */
	bg_check(ns_contains(out, "Tell whom what?"))
	bg_check(ns_contains(out, "Ask whom, where or who, of what?"))
	bg_check(ns_contains(out, "ask <R> where|who <R>, tell <R> <R> [in <R>]"))
}


/* --- knowledge ------------------------------------------------------------- */

test_referent_of :: proc(store: ^Knowledge_Store, truth: Entity_ID) -> u32 {
	i: uint

	for i = 0; i < knowledge_store_count(store); i += 1 {
		if knowledge_store_referent_at(store, i).truth == truth do return knowledge_store_referent_at(store, i).id
	}
	return 0
}


test_believed_menu_has :: proc(w: ^World, store: ^Knowledge_Store, entry: string) -> bool {
	menu: ^Menu
	i:    uint

	menu = menu_for_world_believed(store, w, true)
	for i = 0; i < menu_count(menu); i += 1 {
		if ns_has_prefix(menu_describe_at(menu, i), entry) do return true
	}
	return false
}


/* KNOWLEDGE.md Scenario 3, in the workshop: the worker looks into the bin,
 * walks away; the smith takes the nails out of sight; back by the bin, the
 * worker still believes them there, the menu offers them, and the attempt
 * corrects the belief. */
test_stale_belief :: proc() {
	w:          ^World
	w2:         ^World
	c:          ^Committer
	s:          ^Scheduler
	activities: ^Activities
	knowledge:  ^Knowledge
	restored:   ^Knowledge
	store:      ^Knowledge_Store
	g:          ^Proposal_Group
	nails:      ^Referent
	h:          [8]Entity_ID
	error:      string
	text:       string
	deferred:   []^Proposal_Group
	rbin:       u32
	rnails:     u32
	position:   u64
	i:          i32

	w          = test_world(11)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	knowledge  = autorelease(knowledge_init_with_world(w))
	s          = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	committer_submit(c, workshop_setup(false, &h))
	scheduler_run_until(s, time_make(1))
	store = knowledge_store_of(knowledge, 4)

	/* the worker sees the bin, the lock, and the smith; not what is in the bin */
	rbin = test_referent_of(store, 1)
	bg_check(rbin != 0 && test_referent_of(store, 3) != 0 && test_referent_of(store, 5) != 0 && test_referent_of(store, 2) == 0)
	bg_check(knowledge_store_referent(store, knowledge_store_self_referent(store)).truth == 4)
	bg_check((test_believed_menu_has(w, store, fmt.tprintf("look_in item R%d", rbin))))

	/* it looks in, and knows the nails are there */
	g = perform_believed(w, c, store, action_make("look_in", Entity_ID(knowledge_store_self_referent(store)), Entity_ID(rbin), NO_ENTITY), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(s, time_make(2))
	rnails = test_referent_of(store, 2)
	bg_check(rnails != 0 && knowledge_store_referent(store, rnails).form == .In && knowledge_store_referent(store, rnails).container == rbin)

	/* it walks away, out of sight */
	for i = 0; i < 6; i += 1 {
		perform(w, c, action_make("walk_east", 4, NO_ENTITY, NO_ENTITY), 0, &error)
		scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	}
	/* the smith takes the nails and walks off */
	bg_check(perform(w, c, action_make("take", 5, 2, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	for i = 0; i < 5; i += 1 {
		perform(w, c, action_make("walk_south", 5, NO_ENTITY, NO_ENTITY), 0, &error)
		scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	}
	nails = knowledge_store_referent(store, rnails)
	bg_check(nails.present && nails.form == .In)                         /* it saw none of that */
	bg_check(abs(world_location_of(w, 4).x - 3) > BG_SIGHT)              /* nor the bin's tile, since: out of sight */

	/* back by the bin: it sees the bin, not into it */
	for i = 0; i < 6; i += 1 {
		perform(w, c, action_make("walk_west", 4, NO_ENTITY, NO_ENTITY), 0, &error)
		scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	}
	bg_check(knowledge_store_referent(store, rnails).present)
	/* the menu comes from the knowledge view: it offers the nails it remembers */
	bg_check((test_believed_menu_has(w, store, fmt.tprintf("take_some item R%d", rnails))))
	bg_check(menu_count(menu_for_world(4, w)) == 0 ||
	         !ns_contains(menu_describe_at(menu_for_world(4, w), 0), "item 2"))

	/* the attempt: it reaches into the bin, and now knows they are gone */
	g = perform_believed(w, c, store, action_make("take_some", Entity_ID(knowledge_store_self_referent(store)), Entity_ID(rnails), NO_ENTITY), 5, &error)
	bg_check(g != nil && ns_contains(proposal_group_source(g), "an attempt"))
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	bg_check(!knowledge_store_referent(store, rnails).present)
	bg_check((slice.contains(knowledge_store_news(store), fmt.tprintf("R%d is not where it was", rnails))))
	bg_check((!test_believed_menu_has(w, store, fmt.tprintf("take_some item R%d", rnails))))
	/* the world is as it was: the smith has the nails */
	bg_check(world_location_of(w, 2).form == .Held_By && world_location_of(w, 2).place == 5)

	/* knowledge is saved, and restored the same */
	text = save(w, c, []Saved_System{knowledge_as_saved_system(knowledge)})
	w2   = restore(text, world_content_build(w), &deferred, &position, &error)
	bg_check(w2 != nil)
	restored = autorelease(knowledge_init_with_world(w2))
	knowledge_restore_saved_state(restored, saved_domain_state(text, "knowledge"))
	bg_check(knowledge_dump(restored, 4) == knowledge_dump(knowledge, 4))
	bg_check(knowledge_dump(restored, 5) == knowledge_dump(knowledge, 5))
}


/* --- agency ---------------------------------------------------------------- */

Nails_Run :: struct {
	world:      ^World,
	agency:     ^Agency,
	knowledge:  ^Knowledge,
	apprentice: Entity_ID,
	text:       string,         /* a save at the end, agency and knowledge included */
}


/* Whether there is an apprentice, and what it does: sees the smith put the
 * nails in the chest, or is too far off to; it answers when asked, unless it
 * is silent (agency doesn't control it). */
Apprentice :: enum i32 {
	No_Apprentice = 0,
	Apprentice_Saw,
	Apprentice_Missed,
	Apprentice_Silent,
	Apprentice_Surly,               /* it saw, and won't help */
	Stranger_Glimpsed,              /* no apprentice; a stranger glimpsed nails in the sack, and says so */
}


BG_EIGHT :: i64(8 * 3600000)        /* 8:00, the shift's start */


/* AGENCY.md Scenario 1, as "the missing nails". The worker looks into the bin
 * and walks off past the crate; the smith takes the nails away (with an
 * apprentice, into the chest, at the bottom of the map, and the apprentice
 * then comes over by the crate); then agency takes the worker over,
 * committed to wedging the lock. `saveAt`, if not 0, is when to save,
 * restore into a fresh world, with fresh knowledge and agency from the
 * save, and carry on there. */
/* `curious`: the worker's curiosity, with spare nails in a sack in the far
 * corner, which the worker has seen; -1, no sack. */
test_missing_nails_ :: proc(spares: bool, omniscient: bool, apprentice: Apprentice, saveAt: i64,
                            shiftUntil: i64, curious: i32) -> Nails_Run {
	w:          ^World
	c:          ^Committer
	s:          ^Scheduler
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	h:          [8]Entity_ID
	crate:      Entity_ID
	ch:         Entity_ID
	chest:      Entity_ID
	helper:     Entity_ID
	sack:       Entity_ID
	sacked:     Entity_ID
	error:      string
	text:       string
	run:        Nails_Run
	i:          i32

	w          = test_world(13)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	knowledge  = autorelease(knowledge_init_with_world(w))
	agency     = autorelease(agency_init_with_world(w, c, knowledge))
	s          = autorelease(scheduler_init_with_world(w, c))
	knowledge_set_omniscient(knowledge, omniscient)
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))
	committer_submit(c, workshop_setup(false, &h))
	g  = proposal_group_group_with_phase(.System, "setup: the crate")
	ch = proposal_group_create(g, "crate", "crate", on_tile(8, 7, 0))
	if spares do proposal_group_create(g, "nails_4", "spare nails", in_(ch))
	sacked = NO_ENTITY
	if curious >= 0 {
		sack   = proposal_group_create(g, "sack", "sack", on_tile(13, 8, 0))
		sacked = proposal_group_create(g, "nails_4", "spare nails", in_(sack))
		proposal_group_set_of_to(g, "Agent.curious", whole(4), i64(curious))
	}
	if shiftUntil > BG_EIGHT {
		/* breakfast at 7:30, before the shift */
		proposal_group_set_of_to(g, "Hungry.satiety", whole(4), 100)
		proposal_group_set_of_to(g, "Hungry.fedAt", whole(4), BG_EIGHT - 1800000)
	}
	chest  = NO_ENTITY
	helper = NO_ENTITY
	if apprentice == .Stranger_Glimpsed {
		helper = proposal_group_create(g, "stranger", "stranger", on_tile(13, 9, 0))
	} else if apprentice != .No_Apprentice {
		chest  = proposal_group_create(g, "chest", "chest", on_tile(2, 12, 0))
		helper = proposal_group_create(g, "apprentice", "apprentice",
		                               on_tile(12, 13, 0) if apprentice == .Apprentice_Missed else on_tile(3, 13, 0))
		if apprentice == .Apprentice_Surly do proposal_group_set_of_to(g, "Agent.helpful", whole(helper), -25)
	}
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	crate  = proposal_group_id_for(g, ch)
	chest  = proposal_group_id_for(g, chest)
	helper = proposal_group_id_for(g, helper)
	sacked = proposal_group_id_for(g, sacked) if sacked != NO_ENTITY else NO_ENTITY
	_ = crate
	if apprentice != .No_Apprentice && apprentice != .Apprentice_Silent && apprentice != .Stranger_Glimpsed {
		agency_control(agency, helper)
	}

	/* the worker looks into the bin, then walks off east */
	perform(w, c, action_make("look_in", 4, 1, NO_ENTITY), 0, &error)
	scheduler_run_until(s, time_make(2))
	for i = 0; i < 6; i += 1 {
		perform(w, c, action_make("walk_east", 4, NO_ENTITY, NO_ENTITY), 0, &error)
		scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	}
	/* the smith takes the nails and walks off south */
	perform(w, c, action_make("take", 5, 2, NO_ENTITY), 0, &error)
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	for i = 0; i < 5; i += 1 {
		perform(w, c, action_make("walk_south", 5, NO_ENTITY, NO_ENTITY), 0, &error)
		scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	}
	if apprentice == .Stranger_Glimpsed {
		/* the stranger looks into the sack, comes over, and tells the worker
		 * nails are there; it only glimpsed them, and says so (sure: 5), so
		 * the worker doesn't believe it */
		seen:  ^Knowledge_Store
		claim:   string
		claimed: bool
		say:     Action

		bg_check(perform(w, c, action_make("look_in", helper, proposal_group_id_for(g, sack), NO_ENTITY), 0, &error) != nil)
		scheduler_run_until(s, time_make(world_time(w).ms + 1000))
		g = proposal_group_group_with_phase(.System, "setup: the stranger comes over")
		proposal_group_move_to(g, whole(helper), on_tile(11, 4, 0))
		committer_submit(c, g)
		scheduler_run_until(s, time_make(world_time(w).ms + 1000))
		seen  = knowledge_store_of(knowledge, helper)
		claim, claimed = knowledge_store_claim_about(seen, test_referent_of(seen, sacked))
		claim = ns_replace(claim, "sure: 30", "sure: 5")
		bg_check(claimed)      // claim != nil
		say         = action_make("say", helper, 4, NO_ENTITY)
		say.content = world_intern(w, ns_utf8(claim))
		bg_check(perform(w, c, say, 0, &error) != nil)
		scheduler_run_until(s, time_make(world_time(w).ms + 3000))
	} else if apprentice != .No_Apprentice {
		/* on into the chest, where the apprentice may see it */
		for i = 0; i < 2; i += 1 {
			perform(w, c, action_make("walk_south", 5, NO_ENTITY, NO_ENTITY), 0, &error)
			scheduler_run_until(s, time_make(world_time(w).ms + 1000))
		}
		bg_check(perform(w, c, action_make("put_in", 5, 2, chest), 0, &error) != nil)
		scheduler_run_until(s, time_make(world_time(w).ms + 1000))
		/* the apprentice comes over, by the crate */
		g = proposal_group_group_with_phase(.System, "setup: the apprentice comes over")
		proposal_group_move_to(g, whole(helper), on_tile(10, 8, 0))
		committer_submit(c, g)
		scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	}

	/* the shift: agency has the worker now; or, from 8:00, the worker's
	 * employment does (the routine generator) */
	if shiftUntil != 0 {
		bg_check(agency_undertake_goal_from_until_source(agency, 4, "wedge_lock", BG_EIGHT if shiftUntil > BG_EIGHT else 0, shiftUntil,
		                                                 "employment"))
	} else {
		bg_check(agency_commit(agency, 4, "wedge_lock"))
	}
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	if saveAt != 0 {
		scheduler_run_until(s, time_make(saveAt))
		text  = save(w, c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
		error = ""
		w     = test_restore(text, world_content_build(w), &c, &error)
		bg_check(w != nil)
		activities = activities_with_world(w, c)
		knowledge  = autorelease(knowledge_init_with_world(w))
		agency     = autorelease(agency_init_with_world(w, c, knowledge))
		s          = autorelease(scheduler_init_with_world(w, c))
		knowledge_set_omniscient(knowledge, omniscient)
		knowledge_restore_saved_state(knowledge, saved_domain_state(text, "knowledge"))
		agency_restore_saved_state(agency, saved_domain_state(text, "agency"))
		scheduler_set_activities(s, activities_as_activity_clock(activities))
		scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
		scheduler_set_decision(s, agency_as_decision_phase(agency))
		bg_check(save(w, c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)}) == text)
	}
	scheduler_run_until(s, time_make(BG_EIGHT + 120000 if shiftUntil > BG_EIGHT else 120000))
	run.world      = w
	run.agency     = agency
	run.knowledge  = knowledge
	run.apprentice = helper
	run.text   = save(w, c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	return run
}


test_happened :: proc(w: ^World, kind: cstring, actor: Entity_ID, other: Entity_ID) -> bool {
	ev: ^Event
	i:  uint

	for i = 0; i < world_event_count(w); i += 1 {
		ev = world_event_at(w, i)
		if string(ev.kind) == string(kind) && ev.actor == actor && ev.other == other do return true
	}
	return false
}


test_first_at :: proc(w: ^World, kind: cstring, actor: Entity_ID, other: Entity_ID) -> u64 {
	ev: ^Event
	i:  uint

	for i = 0; i < world_event_count(w); i += 1 {
		ev = world_event_at(w, i)
		if string(ev.kind) == string(kind) && ev.actor == actor && ev.other == other do return ev.index
	}
	return 0
}


test_wedged :: proc(w: ^World) -> bool {
	parts: [4]Entity_ID

	return world_entities_at(w, 3, .Part_Of, &parts[0], 4) > 0
}


test_logged :: proc(agency: ^Agency, text: string) -> bool {
	log: []string
	i:   uint

	log = agency_log_of(agency, 4)
	for i = 0; i < uint(len(log)); i += 1 {
		if ns_contains(log[i], text) do return true
	}
	return false
}


/* the referent of the agent's that tracks the entity, present or not; developer-only */
test_tracks :: proc(run: Nails_Run, agent: Entity_ID, truth: Entity_ID) -> u32 {
	store: ^Knowledge_Store
	i:     uint

	store = knowledge_store_of(run.knowledge, agent)
	for i = 0; i < knowledge_store_count(store); i += 1 {
		if knowledge_store_referent_at(store, i).truth == truth do return knowledge_store_referent_at(store, i).id
	}
	return 0
}


test_missing_nails :: proc() {
	base:      Nails_Run
	again:     Nails_Run
	spares:    Nails_Run
	seer:      Nails_Run
	resumed:   Nails_Run
	incurious: Nails_Run
	curious:   Nails_Run
	glimpsed:  Nails_Run
	crate:     Entity_ID
	full:      []string
	rest:      []string

	crate = 7           /* after the workshop's six */

	/* base: the bin first (believed), then the crate; nowhere left: dropped, with why */
	base = test_missing_nails_(false, false, .No_Apprentice, 0, 0, -1)

	bg_check(test_happened(base.world, "attempted", 4, 1))
	bg_check(test_happened(base.world, "looked", 4, crate))
	bg_check(test_first_at(base.world, "attempted", 4, 1) < test_first_at(base.world, "looked", 4, crate))
	bg_check(test_logged(base.agency, "[wedge the lock] drive a nail in: have nails first"))
	bg_check(test_logged(base.agency, "[have nails] fetch nails: take_some"))
	bg_check(test_logged(base.agency, "[have nails] fetch nails no longer holds"))
	bg_check(test_logged(base.agency, "[have nails] search for nails: look_in"))
	bg_check(test_logged(base.agency, "[have nails] nothing I know of will do: impossible for now"))
	bg_check(test_logged(base.agency, "[wedge the lock] drive a nail in has failed: it needed have nails"))
	bg_check(test_logged(base.agency, "[wedge the lock] nothing I know of will do: impossible for now"))
	bg_check(!test_wedged(base.world) && agency_mind_of(base.agency, 4).nintentions == 0)

	/* the same run is the same, decisions and all */
	again = test_missing_nails_(false, false, .No_Apprentice, 0, 0, -1)
	bg_check(world_state_hash(again.world) == world_state_hash(base.world))
	bg_check(slice.equal(agency_log_of(again.agency, 4), agency_log_of(base.agency, 4)))
	bg_check(again.text == base.text)

	/* A: spare nails in the crate: found, taken, and the lock wedged; wedging was the intention throughout */
	spares = test_missing_nails_(true, false, .No_Apprentice, 0, 0, -1)
	bg_check(test_happened(spares.world, "attempted", 4, 1))
	bg_check(test_logged(spares.agency, "[wedge the lock] back to it: have nails is done"))
	bg_check(test_logged(spares.agency, "[wedge the lock] drive a nail in: drive"))
	bg_check(test_logged(spares.agency, "[wedge the lock] done"))
	/* the spare nails are a thing of their own, not the bin's missing ones found again: they look different */
	bg_check(test_tracks(spares, 4, 2) != 0 && test_tracks(spares, 4, 8) != 0 && test_tracks(spares, 4, 2) != test_tracks(spares, 4, 8))
	bg_check(test_wedged(spares.world))

	/* B: the omniscient stub knows better, and the behaviour shows it: straight to the crate */
	seer = test_missing_nails_(true, true, .No_Apprentice, 0, 0, -1)
	bg_check(!test_happened(seer.world, "attempted", 4, 1))
	bg_check(!test_logged(seer.agency, "search for nails"))
	bg_check(test_wedged(seer.world))
	bg_check(len(agency_log_of(seer.agency, 4)) < len(agency_log_of(spares.agency, 4)))

	/* A (AGENCY.md's): spares in a sack in the far corner, which the worker has
	 * seen. The search looks into two places, the bin and the crate, and
	 * gives up; a curious worker's goes on, to the sack, and finds them */
	incurious = test_missing_nails_(false, false, .No_Apprentice, 0, 0, 0)
	bg_check(test_happened(incurious.world, "looked", 4, crate))
	bg_check(!test_happened(incurious.world, "looked", 4, crate + 1))
	bg_check(test_logged(incurious.agency, "[have nails] nothing I know of will do: impossible for now"))
	bg_check(!test_wedged(incurious.world))
	/* AGENCY.md §5, the places to look ordered by the belief that the thing
	 * is there: a stranger, barely sure, says nails are in the far sack; the
	 * worker doesn't believe it (it doesn't go to fetch them from there),
	 * but when the bin it believed held nails is empty, its search goes to
	 * the sack first, before the nearer crate, and finds them */
	glimpsed = test_missing_nails_(false, false, .Stranger_Glimpsed, 0, 0, 0)
	bg_check(test_log_index(glimpsed.agency, 4, "search for nails: ") != NOT_FOUND &&
	         test_log_index(glimpsed.agency, 4, "search for nails: ") ==
	         test_log_index(glimpsed.agency, 4, "search for nails: walk_east, toward R7 at (13, 8)"))
	bg_check(test_log_index(glimpsed.agency, 4, "fetch nails: walk_east, toward R7") == NOT_FOUND)
	bg_check(test_happened(glimpsed.world, "looked", 4, crate + 1))
	bg_check(!test_happened(glimpsed.world, "looked", 4, crate) ||
	         test_first_at(glimpsed.world, "looked", 4, crate + 1) < test_first_at(glimpsed.world, "looked", 4, crate))
	bg_check(test_wedged(glimpsed.world))

	curious = test_missing_nails_(false, false, .No_Apprentice, 0, 0, 50)
	bg_check(test_happened(curious.world, "looked", 4, crate))
	bg_check(test_happened(curious.world, "looked", 4, crate + 1))
	bg_check(test_first_at(curious.world, "looked", 4, crate) < test_first_at(curious.world, "looked", 4, crate + 1))
	bg_check(test_wedged(curious.world))

	/* saved mid-search, mid-stride (a boundary the run has anyway: the walk
	 * toward the crate just committed), the commitment and the subgoal stacked,
	 * fetching passed over: restored, the agent carries on exactly as it would
	 * have */
	resumed = test_missing_nails_(true, false, .No_Apprentice, 20005, 0, -1)
	bg_check(world_state_hash(resumed.world) == world_state_hash(spares.world))
	bg_check(resumed.text == spares.text)
	full = agency_log_of(spares.agency, 4)
	rest = agency_log_of(resumed.agency, 4)
	bg_check(len(rest) > 0 && len(rest) < len(full))
	bg_check(len(rest) <= len(full) &&
	         slice.equal(rest, full[len(full) - len(rest):][:len(rest)]))
}


test_logged_by :: proc(agency: ^Agency, agent: Entity_ID, text: string) -> bool {
	log: []string
	i:   uint

	log = agency_log_of(agency, agent)
	for i = 0; i < uint(len(log)); i += 1 {
		if ns_contains(log[i], text) do return true
	}
	return false
}


test_believed :: proc(run: Nails_Run, agent: Entity_ID, truth: Entity_ID) -> ^Referent {
	store: ^Knowledge_Store
	i:     uint

	store = knowledge_store_of(run.knowledge, agent)
	for i = 0; i < knowledge_store_count(store); i += 1 {
		if knowledge_store_referent_at(store, i).truth == truth && knowledge_store_referent_at(store, i).present {
			return knowledge_store_referent_at(store, i)
		}
	}
	return nil
}


/* AGENCY.md Scenario 1's "ask a coworker", with KNOWLEDGE.md's event
 * perception and claims: the search fails, and the worker asks the
 * apprentice, who may have seen the smith put the nails in the chest. */
test_asking :: proc() {
	saw:     Nails_Run
	again:   Nails_Run
	missed:  Nails_Run
	silent:  Nails_Run
	resumed: Nails_Run
	seer:    Nails_Run
	surly:   Nails_Run
	nails:   ^Referent
	chest:   ^Referent
	store:   ^Knowledge_Store
	full:    []string
	rest:    []string
	c:       Entity_ID

	/* it saw: told where, the worker goes to a chest it has never seen, and wedges the lock */
	saw = test_missing_nails_(false, false, .Apprentice_Saw, 0, 0, -1)
	c   = 8                 /* the crate is 7 */
	bg_check(test_logged(saw.agency, "[have nails] ask where nails are: say R"))
	bg_check(test_logged(saw.agency, ": #WhereIs"))
	bg_check(test_logged(saw.agency, "answered: #IsIn"))
	bg_check(test_logged_by(saw.agency, saw.apprentice, "answering: say R"))
	bg_check(test_happened(saw.world, "said", 4, saw.apprentice) && test_happened(saw.world, "said", saw.apprentice, 4))
	bg_check(test_first_at(saw.world, "looked", 4, 7) < test_first_at(saw.world, "said", 4, saw.apprentice))
	bg_check(!test_happened(saw.world, "looked", 4, c))
	bg_check(test_wedged(saw.world))
	/* the apprentice saw the nails go in: believed in the chest, not told */
	nails = test_believed(saw, saw.apprentice, 2)
	chest = test_believed(saw, saw.apprentice, c)
	bg_check(nails != nil && chest != nil && nails.form == .In && nails.container == chest.id && nails.toldBy == 0)
	/* the worker was told of the chest, then saw it: what it was told is seen
	 * true, and it trusts the apprentice more */
	chest = test_believed(saw, 4, c)
	store = knowledge_store_of(saw.knowledge, 4)
	bg_check(chest != nil && chest.toldBy == 0 && knowledge_store_testimony_count(store) == 1)
	bg_check(knowledge_store_testimony_at(store, 0).container == chest.id && knowledge_store_testimony_at(store, 0).settled == 1 &&
	         knowledge_store_testimony_at(store, 0).attribution == .Saw)
	bg_check(knowledge_store_trust_in(store, knowledge_store_testimony_at(store, 0).source) == BG_TRUST + BG_CONFIRMED)
	bg_check(ns_contains(knowledge_dump(saw.knowledge, 4), "seen true; truly seen by"))
	bg_check(ns_contains(knowledge_dump(saw.knowledge, 4), "said R"))

	again = test_missing_nails_(false, false, .Apprentice_Saw, 0, 0, -1)
	bg_check(world_state_hash(again.world) == world_state_hash(saw.world))
	bg_check(again.text == saw.text)
	bg_check(slice.equal(agency_log_of(again.agency, 4), agency_log_of(saw.agency, 4)))

	/* it didn't see: it says so, and the goal is dropped */
	missed = test_missing_nails_(false, false, .Apprentice_Missed, 0, 0, -1)
	bg_check(test_logged(missed.agency, "answered: #DontKnow"))
	bg_check(test_logged(missed.agency, "[wedge the lock] nothing I know of will do: impossible for now"))
	bg_check(!test_wedged(missed.world))
	bg_check(test_believed(missed, missed.apprentice, 2) == nil)

	/* nobody answers: the worker waits a while, then gives up on it */
	silent = test_missing_nails_(false, false, .Apprentice_Silent, 0, 0, -1)
	bg_check(test_logged(silent.agency, "did not answer"))
	bg_check(!test_happened(silent.world, "said", silent.apprentice, 4) && !test_wedged(silent.world))

	/* saved while it waits, the wait goes on in the restored world, and ends as it would have */
	resumed = test_missing_nails_(false, false, .Apprentice_Silent, 30006, 0, -1)
	bg_check(world_state_hash(resumed.world) == world_state_hash(silent.world))
	bg_check(resumed.text == silent.text)
	full = agency_log_of(silent.agency, 4)
	rest = agency_log_of(resumed.agency, 4)
	bg_check(len(rest) > 0 && len(rest) < len(full) &&
	         slice.equal(rest, full[len(full) - len(rest):][:len(rest)]))
	bg_check(len(rest) != 0 && ns_contains(rest[0], "t=35005ms") &&
	         ns_contains(rest[0], "did not answer"))

	/* asked, a surly apprentice weighs answering at less than nothing, and says it won't: the goal is dropped */
	surly = test_missing_nails_(false, false, .Apprentice_Surly, 0, 0, -1)
	bg_check(test_logged_by(surly.agency, surly.apprentice, "asked by R"))
	bg_check(test_logged_by(surly.agency, surly.apprentice, "worth -5, refusing"))
	bg_check(test_logged_by(surly.agency, surly.apprentice, "refusing: say R"))
	bg_check(test_logged(surly.agency, "answered: #WontSay"))
	bg_check(test_logged(surly.agency, "[wedge the lock] nothing I know of will do: impossible for now"))
	bg_check(!test_wedged(surly.world))
	/* a helpful one weighed it at the trust in the asker */
	bg_check(test_logged_by(saw.agency, saw.apprentice, "worth +20, answering"))

	/* the omniscient stub needs no one: straight to the chest */
	seer = test_missing_nails_(false, true, .Apprentice_Saw, 0, 0, -1)
	bg_check(!test_happened(seer.world, "said", 4, seer.apprentice))
	bg_check(!test_happened(seer.world, "attempted", 4, 1) && test_wedged(seer.world))
}


/* AGENCY.md Scenario 1 as written: the worker's shift (an employment
 * commitment from 8:00) is what puts wedging the lock in its mind: the
 * routine generator, at 8:00, nothing else to weigh it against. */
test_routine :: proc() {
	shift:     Nails_Run
	fruitless: Nails_Run
	closing:   Nails_Run
	hurried:   Nails_Run
	resumed:   Nails_Run
	log:       []string
	full:      []string
	rest:      []string

	/* the shift, 8:00 to 16:00: at 8:00, and not before, the worker takes up
	 * wedging the lock, worth its duty; no urgency yet */
	shift = test_missing_nails_(true, false, .No_Apprentice, 0, BG_EIGHT + 8 * 3600000, -1)
	log   = agency_log_of(shift.agency, 4)
	bg_check(len(log) != 0 && ns_contains(log[0], "t=28800000ms [-] weighing wedge the lock: +20 " +
	                                              "(employment, duty +20, urgency +0) against nothing: " +
	                                              "switching"))
	bg_check(test_logged_by(shift.agency, 4, "t=28800000ms [wedge the lock] drive a nail in: have nails first"))
	bg_check(test_wedged(shift.world))
	/* done, it is settled for the shift: not taken up again */
	bg_check(test_log_count(shift.agency, 4, "switching") == 1)

	/* without spares, impossible, and settled too: not taken up again and again */
	fruitless = test_missing_nails_(false, false, .No_Apprentice, 0, BG_EIGHT + 8 * 3600000, -1)
	bg_check(test_logged_by(fruitless.agency, 4, "[wedge the lock] nothing I know of will do: impossible for now"))
	bg_check(test_log_count(fruitless.agency, 4, "switching") == 1 && !test_wedged(fruitless.world))

	/* a shift of five seconds closes mid-search: the commitment is over, and
	 * what it needed with it */
	closing = test_missing_nails_(true, false, .No_Apprentice, 0, BG_EIGHT + 5000, -1)
	bg_check(test_logged_by(closing.agency, 4, "t=28805000ms [have nails] wedge the lock is over: its window has closed"))
	bg_check(!test_wedged(closing.world) && agency_mind_of(closing.agency, 4).nintentions == 0)

	/* urgency rises toward the deadline: a window from 0 to 40 s, taken up
	 * at 12 s, three tenths of the way: 6 of 20 */
	hurried = test_missing_nails_(true, false, .No_Apprentice, 0, 40000, -1)
	bg_check(test_logged_by(hurried.agency, 4, "t=12003ms [-] weighing wedge the lock: +26 (employment, duty +20, urgency +6)"))

	/* saved mid-shift, restored, the same end */
	resumed = test_missing_nails_(true, false, .No_Apprentice, BG_EIGHT + 6001, BG_EIGHT + 8 * 3600000, -1)
	bg_check(world_state_hash(resumed.world) == world_state_hash(shift.world))
	bg_check(resumed.text == shift.text)
	full = agency_log_of(shift.agency, 4)
	rest = agency_log_of(resumed.agency, 4)
	bg_check(len(rest) > 0 && len(rest) < len(full) &&
	         slice.equal(rest, full[len(full) - len(rest):][:len(rest)]))
}


/* AGENCY.md §6: the worker, holding nails of its own and its supper, by the
 * lock. `fed` is how fed it is at 0; `drive`, whether it is driving a nail
 * when agency takes it over; it runs to `until`. */
Hunger_Run :: struct {
	world:       ^World,
	knowledge:   ^Knowledge,
	agency:      ^Agency,
	supper:      Entity_ID,
	feltDriving: i32,            /* what it felt while driving */
	boundaries:  uint,
	text:        string,
}


test_hunger_run :: proc(fed: i64, drive: bool, until: i64) -> Hunger_Run {
	w:          ^World
	c:          ^Committer
	s:          ^Scheduler
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	h:          [8]Entity_ID
	supper:     Entity_ID
	error:      string
	run:        Hunger_Run

	run = {}
	w          = test_world(47)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	knowledge  = autorelease(knowledge_init_with_world(w))
	agency     = autorelease(agency_init_with_world(w, c, knowledge))
	s          = autorelease(scheduler_init_with_world(w, c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))
	scheduler_add_domain(s, bodies_as_domain(autorelease(bodies_init_with_world(w))))
	committer_submit(c, workshop_setup(true, &h))
	scheduler_run_until(s, time_make(1))
	g      = proposal_group_group_with_phase(.System, "setup: supper, and how fed the worker is")
	supper = proposal_group_create(g, "supper", "supper", held_by(4, 1))
	proposal_group_set_of_to(g, "Hungry.satiety", whole(4), fed)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(2))
	run.supper = proposal_group_id_for(g, supper)

	if drive {
		error = ""
		bg_check(perform(w, c, action_make("drive", 4, 7, 3), 0, &error) != nil)
		scheduler_run_until(s, time_make(1000))
	}
	agency_control(agency, 4)
	if drive {
		scheduler_run_until(s, time_make(2000))
		run.feltDriving = knowledge_store_feels(knowledge_store_of(knowledge, 4), "hunger")
	}
	run.boundaries = scheduler_run_until(s, time_make(until))
	run.world      = w
	run.knowledge  = knowledge
	run.agency     = agency
	run.text       = save(w, c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	return run
}


/* AGENCY.md decision 17: going without food harms the body, slowly. The
 * worker, nearly starved, with nothing to eat and left to itself: a point of
 * harm every ten minutes, fatigue up to 50, then injury. */
test_going_without :: proc() {
	w:       ^World
	c:       ^Committer
	s:       ^Scheduler
	g:       ^Proposal_Group
	h:       [8]Entity_ID
	fatigue: i64
	injury:  i64

	/* hunger in closed form (content/hunger/body.tri's defaults): the
	 * stomach empties a point every 4.8 min (8 h), reserves refill a point
	 * every 1.68 h (7 d) until it is empty, then fall a point every 5.04 h
	 * (21 d) */
	{
		hu := Hungry{satiety = 50, reserves = 60, fedAt = 1000, emptiesIn = 8 * 3600000,
		             lastsFor = 21 * BG_DAY, refillsIn = 7 * BG_DAY, harmsEvery = 2 * 3600000}
		empty := i64(1000 + 50 * 288000)
		bg_check(satiety(&hu, 1000 + 10 * 288000) == 40 && satiety(&hu, empty - 1) == 1 && satiety(&hu, empty) == 0)
		bg_check(hunger_empties_at(&hu) == empty)
		bg_check(reserves(&hu, 1000 + 6048000) == 61 && reserves(&hu, empty) == 62)
		bg_check(reserves(&hu, empty + 12 * 18144000) == 50)
		bg_check(hunger_exhausted_at(&hu) == empty + 62 * 18144000)    /* 13 days on */
		bg_check(reserves(&hu, hunger_exhausted_at(&hu) - 1) == 1 && reserves(&hu, hunger_exhausted_at(&hu)) == 0)
		bg_check(reserves(&hu, 100 * BG_DAY) == 0)
		/* what doesn't get hungry is always full */
		bg_check(satiety(nil, 5000) == 100 && reserves(nil, 5000) == 100)
	}

	/* the body domain: an empty stomach doesn't harm; reserves gone, a point
	 * of injury every 2 h, and none of fatigue (a rest doesn't cure it) */
	for gone := 0; gone < 2; gone += 1 {
		w = test_world(49)
		c = test_committer(w)
		s = autorelease(scheduler_init_with_world(w, c))
		scheduler_add_domain(s, bodies_as_domain(autorelease(bodies_init_with_world(w))))
		committer_submit(c, workshop_setup(true, &h))
		scheduler_run_until(s, time_make(1))
		g = proposal_group_group_with_phase(.System, "setup: how fed and tired the worker is")
		proposal_group_set_of_to(g, "Hungry.satiety", whole(4), 0)
		proposal_group_set_of_to(g, "Hungry.reserves", whole(4), 1 if gone == 1 else 50)
		proposal_group_set_of_to(g, "Hungry.fedAt", whole(4), 1)
		proposal_group_set_of_to(g, "Agent.fatigue", whole(4), 49)
		committer_submit(c, g)
		/* reserves of 1 run out at 18,144,001 ms; harm at 21.6, 28.8 and 36 Ms */
		scheduler_run_until(s, time_make(18000000))
		world_get_field(w, "Agent.injury", 4, &injury)
		bg_check(injury == 0)
		scheduler_run_until(s, time_make(36000001))
		fatigue = 0
		injury  = 0
		world_get_field(w, "Agent.fatigue", 4, &fatigue)
		world_get_field(w, "Agent.injury", 4, &injury)
		if gone == 1 {
			bg_check(fatigue == 49 && injury == 3)
		} else {
			bg_check(fatigue == 49 && injury == 0)
		}
	}

	/* weakness, by content/hunger/weakness.tri's curves, at reserves of 20:
	 * attention 38% lost, the pace of work 40%, perception 67%, grip 25% */
	w = test_world(49)
	c = test_committer(w)
	s = autorelease(scheduler_init_with_world(w, c))
	committer_submit(c, workshop_setup(true, &h))
	scheduler_run_until(s, time_make(1))
	bg_check(work_rate(w, 4, "saw_through", 0) == 100)
	g = proposal_group_group_with_phase(.System, "setup: weeks without")
	proposal_group_set_of_to(g, "Hungry.satiety", whole(4), 0)
	proposal_group_set_of_to(g, "Hungry.reserves", whole(4), 20)
	proposal_group_set_of_to(g, "Hungry.fedAt", whole(4), 1)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(2))
	bg_check(weakness(w, 4, .Attention, 2) == 38 && weakness(w, 4, .Pace, 2) == 40)
	bg_check(weakness(w, 4, .Perception, 2) == 67 && weakness(w, 4, .Grip, 2) == 25)
	bg_check(work_rate(w, 4, "saw_through", 0) == 60)
	/* fed well, nothing lost; and what isn't hungry (the bin) never weakens */
	bg_check(weakness(w, 4, .Pace, -1) == 40 && weakness(w, 1, .Pace, 2) == 0)
}


/* VILLAGE.md decision 2: a worker weeks without food sees as if worn out
 * (perception lost by half or more): the smith's brown coat only as dark. */
test_starving_sight :: proc() {
	st:        Stage
	knowledge: ^Knowledge
	store:     ^Knowledge_Store
	g:         ^Proposal_Group
	worker:    Entity_ID
	smith:     Entity_ID
	r:         u32

	st.w      = test_world(157)
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	g      = proposal_group_group_with_phase(.System, "setup: a starving worker")
	worker = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	smith  = proposal_group_create(g, "smith", "smith", on_tile(7, 5, 0))
	proposal_group_set_of_to(g, "Hungry.satiety", whole(worker), 0)
	proposal_group_set_of_to(g, "Hungry.reserves", whole(worker), 15)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1000))
	worker = proposal_group_id_for(g, worker)
	smith  = proposal_group_id_for(g, smith)
	store  = knowledge_store_of(knowledge, worker)
	r      = test_referent_of(store, smith)
	bg_check(r != 0 && ns_contains(knowledge_store_describe_referent(store, r), "coat: \"dark\""))
	g = proposal_group_group_with_phase(.System, "setup: fed back to health")
	proposal_group_set_of_to(g, "Hungry.reserves", whole(worker), 100)
	proposal_group_set_of_to(g, "Hungry.fedAt", whole(worker), 1000)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(2000))
	bg_check(knowledge_store_hypotheses_of(store, r) == 0 && ns_contains(knowledge_store_describe_referent(store, r), "coat: \"brown\""))
}


test_needs :: proc() {
	hungry:   Hunger_Run
	busy:     Hunger_Run
	later:    Hunger_Run
	again:    Hunger_Run
	w2:       ^World
	restored: ^Knowledge
	deferred: []^Proposal_Group
	error:    string
	position: u64

	/* hungry (70), idle: the needs generator raises eating, worth what it
	 * feels, and it eats its supper */
	hungry = test_hunger_run(30, false, 120000)
	bg_check(test_logged_by(hungry.agency, 4, "weighing eat something: +35 (hunger +35) against nothing: switching"))
	bg_check(test_logged_by(hungry.agency, 4, "[eat something] eat what I have: eat R"))
	bg_check(test_logged_by(hungry.agency, 4, "[eat something] done"))
	bg_check(!world_is_live(hungry.world, hungry.supper))
	/* AGENCY.md decision 16: its supper is worth 10 to it, and more the
	 * hungrier it is, half a point a point of hunger it feels */
	{
		early: Hunger_Run
		store: ^Knowledge_Store
		felt:  i32

		early = test_hunger_run(30, true, 2500)
		store = knowledge_store_of(early.knowledge, 4)
		felt  = knowledge_store_feels(store, "hunger")
		bg_check(felt > 0 && agency_worth_of(early.agency, test_referent_of(store, early.supper), 4) == 10 + felt / 2)
		early = test_hunger_run(100, true, 2500)
		store = knowledge_store_of(early.knowledge, 4)
		bg_check(knowledge_store_feels(store, "hunger") == 0 && agency_worth_of(early.agency, test_referent_of(store, early.supper), 4) == 10)
	}
	fed := hungry_of(hungry.world, 4)
	bg_check(fed != nil && fed.satiety == 80)
	bg_check(knowledge_store_feels(knowledge_store_of(hungry.knowledge, 4), "hunger") == 20)

	/* driving a nail, its hunger (50) dulled by the attention the drive
	 * demands: it feels 30, and eats only once the drive is done */
	busy = test_hunger_run(50, true, 120000)
	bg_check(busy.feltDriving == 30)
	bg_check(test_logged_by(busy.agency, 4, "t=4002ms [-] weighing eat something: +25 (hunger +25)"))
	bg_check(test_log_count(busy.agency, 4, "weighing") == 1)
	bg_check(!world_is_live(busy.world, busy.supper))

	/* fed (80), it grows hungry as time passes, a point every 4.8 minutes
	 * (its stomach empties in 8 h), computed when read: the body domain
	 * wakes it at each band, and at 144 minutes it feels 50 and eats;
	 * nothing is computed between */
	later = test_hunger_run(80, false, 3 * 3600000)
	bg_check(test_logged_by(later.agency, 4, "t=8640000ms [-] weighing eat something: +25 (hunger +25)"))
	bg_check(later.boundaries < 12)
	bg_check(!world_is_live(later.world, later.supper))

	/* the same on replay; what it feels is saved */
	again = test_hunger_run(80, false, 3 * 3600000)
	bg_check(again.text == later.text)
	w2 = restore(later.text, world_content_build(later.world), &deferred, &position, &error)
	bg_check(w2 != nil)
	restored = autorelease(knowledge_init_with_world(w2))
	knowledge_restore_saved_state(restored, saved_domain_state(later.text, "knowledge"))
	bg_check(knowledge_dump(restored, 4) == knowledge_dump(later.knowledge, 4))
}


/* AGENCY.md §8: each morning the worker is handed nails, and puts them away.
 * Days 1 to 3 (if `practised`) it knows only the crate, two tiles off, and
 * puts them there, watched by a curious apprentice. On day 4 a bin stands
 * right beside it. On day 45 it puts them away again. */
Habit_Run :: struct {
	world:      ^World,
	knowledge:  ^Knowledge,
	agency:     ^Agency,
	crate:      Entity_ID,
	bin:        Entity_ID,
	apprentice: Entity_ID,
	text:       string,
}


BG_DAY :: i64(86400000)

/* Everyone who gets hungry fed full at t: for tests that run for days
 * about something else, in which nobody should weaken from going without. */
test_breakfast :: proc(w: ^World, g: ^Proposal_Group, t: i64) {
	hungry := world_store_for_kind(w, world_kind_named(w, "Hungry"))
	for i: uint = 0; i < store_count(hungry); i += 1 {
		e := store_entity_at_index(hungry, i)
		proposal_group_set_of_to(g, "Hungry.satiety", whole(e), 100)
		proposal_group_set_of_to(g, "Hungry.reserves", whole(e), 100)
		proposal_group_set_of_to(g, "Hungry.fedAt", whole(e), t)
	}
}

test_hand_nails :: proc(w: ^World, c: ^Committer, s: ^Scheduler, agency: ^Agency, day: i64) {
	g: ^Proposal_Group

	scheduler_run_until(s, time_make(day * BG_DAY))
	g = proposal_group_group_with_phase(.System, "setup: in at the door, with nails for the day")
	test_breakfast(w, g, day * BG_DAY)
	proposal_group_move_to(g, whole(4), on_tile(5, 5, 0))
	proposal_group_create(g, "nails_10", ns_utf8(fmt.tprintf("nails of day %d", day)), held_by(4, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(day * BG_DAY + 1))
	bg_check(agency_commit(agency, 4, "put_away"))
	scheduler_run_until(s, time_make(day * BG_DAY + 10000))
}


test_habits_run :: proc(practised: bool, binDays: i32) -> Habit_Run {
	w:          ^World
	c:          ^Committer
	s:          ^Scheduler
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	crate:      Entity_ID
	apprentice: Entity_ID
	bin:        Entity_ID
	run:        Habit_Run
	day:        i32

	run = {}
	w          = test_world(53)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	knowledge  = autorelease(knowledge_init_with_world(w))
	agency     = autorelease(agency_init_with_world(w, c, knowledge))
	s          = autorelease(scheduler_init_with_world(w, c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))
	g          = proposal_group_group_with_phase(.System, "setup: the workshop")
	proposal_group_create(g, "lock", "lock", on_tile(20, 20, 0))
	proposal_group_create(g, "lock", "lock 2", on_tile(21, 20, 0))
	proposal_group_create(g, "smith", "smith", on_tile(22, 20, 0))
	proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	crate      = proposal_group_create(g, "crate", "crate", on_tile(5, 7, 0))
	apprentice = proposal_group_create(g, "apprentice", "apprentice", on_tile(7, 4, 0))
	proposal_group_set_of_to(g, "Agent.curious", whole(apprentice), 100)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	bg_check(proposal_group_id_for(g, handle(4)) == 4)
	run.crate      = proposal_group_id_for(g, crate)
	run.apprentice = proposal_group_id_for(g, apprentice)
	agency_control(agency, 4)

	for day = 1; practised && day <= 3; day += 1 do test_hand_nails(w, c, s, agency, i64(day))

	/* day 4: a bin beside the worker */
	scheduler_run_until(s, time_make(4 * BG_DAY - 1000))
	g   = proposal_group_group_with_phase(.System, "setup: a bin, right beside")
	bin = proposal_group_create(g, "bin", "bin", on_tile(4, 5, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(4 * BG_DAY - 500))
	run.bin = proposal_group_id_for(g, bin)
	test_hand_nails(w, c, s, agency, 4)
	if practised do test_hand_nails(w, c, s, agency, 45)
	/* and on, the bin every day now */
	for day = 46; day < 46 + binDays; day += 1 do test_hand_nails(w, c, s, agency, i64(day))

	run.world     = w
	run.knowledge = knowledge
	run.agency    = agency
	run.text      = save(w, c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	return run
}


/* how many nails lie in the container */
test_nails_in :: proc(w: ^World, container: Entity_ID) -> i64 {
	inside: [16]Entity_ID
	n:      uint
	i:      uint
	units:  i64

	n     = world_entities_at(w, container, .In, &inside[0], 16)
	units = 0
	for i = 0; i < n; i += 1 do units += world_units_of(w, inside[i])
	return units
}


test_habits :: proc() {
	practised: Habit_Run
	fresh:     Habit_Run
	again:     Habit_Run
	moved:     Habit_Run
	store:     ^Knowledge_Store
	f:         ^Finding

	practised = test_habits_run(true, 0)
	fresh     = test_habits_run(false, 0)

	/* a method default: three days of the crate, and on day 4 the worker
	 * walks past the bin beside it to the crate; with no habit, the bin */
	bg_check(test_nails_in(fresh.world, fresh.bin) == 10 && test_nails_in(fresh.world, fresh.crate) == 0)
	bg_check(test_nails_in(practised.world, practised.crate) == 40)
	/* the method, habitual too: 10 a day, less a point for each day between: 27 by day 4 */
	bg_check(test_logged_by(practised.agency, 4, "scoring put them in a box +2 (habit +2)"))
	bg_check(test_log_count(practised.agency, 4, "put them in a box: put_in R") == 5)
	/* on day 45 the habit has faded, and the bin beside it wins */
	bg_check(test_nails_in(practised.world, practised.bin) == 10)

	/* the apprentice, who watched, believes the worker usually puts things in the crate */
	store = knowledge_store_of(practised.knowledge, practised.apprentice)
	f     = knowledge_store_finding(store, "#Habit", test_referent_of(store, 4))
	bg_check(f != nil && f.choice == test_referent_of(store, practised.crate) && string(f.rule) == "usually_puts")
	/* and its breaking it on day 45 is salient: an anomaly */
	bg_check(ns_contains(knowledge_dump(practised.knowledge, practised.apprentice), "salience 25"))

	/* the same on replay */
	again = test_habits_run(true, 0)
	bg_check(again.text == practised.text)

	/* KNOWLEDGE.md §9, retracted with its premise: the worker goes on using
	 * the bin, day after day, until it has used it more than the crate; the
	 * apprentice's belief about where it usually puts things is retracted
	 * and drawn again: the bin */
	moved = test_habits_run(true, 4)
	bg_check(test_nails_in(moved.world, moved.bin) == 50)
	store = knowledge_store_of(moved.knowledge, moved.apprentice)
	f     = knowledge_store_finding(store, "#Habit", test_referent_of(store, 4))
	bg_check(f != nil && f.choice == test_referent_of(store, moved.bin))
	/* three days on the bin, not yet more than the crate: still the crate */
	moved = test_habits_run(true, 3)
	store = knowledge_store_of(moved.knowledge, moved.apprentice)
	f     = knowledge_store_finding(store, "#Habit", test_referent_of(store, 4))
	bg_check(f != nil && f.choice == test_referent_of(store, moved.crate))
}


/* --- the rumour ------------------------------------------------------------ */

/* KNOWLEDGE.md Scenario 1, "the witness and the rumour", in the workshop: the
 * apprentice (Marius) and the neighbour (Nadia) see the smith put the nails
 * in the chest. Day 1: the apprentice tells the carter (Teodor) and the
 * porter (Ulla). Day 2: the carter tells the foreman (Ines), naming the
 * apprentice; the porter tells the foreman, naming no one; the foreman asks
 * the porter who told it. Day 3: the neighbour tells the foreman what it saw.
 * Days are seconds here, and people are brought together by system moves.
 * Questions are the test's; answers are agency's. Single: only the carter
 * tells the foreman. Lie (variant A): the smith keeps the nails, and the
 * apprentice, who saw nothing go in, says it did; the foreman looks in the
 * chest. Decay (variant B): the apprentice walks off, and the foreman asks
 * it on day 10, and again on day 20. */
Rumour_Variant :: enum i32 {
	Full = 0,
	Single,
	Lie,
	Decay,
}


Rumour :: struct {
	world:          ^World,
	knowledge:      ^Knowledge,
	smith:          Entity_ID,
	apprentice:     Entity_ID,
	carter:         Entity_ID,
	porter:         Entity_ID,
	neighbour:      Entity_ID,
	foreman:        Entity_ID,
	told:           i32,         /* the foreman's credence after the carter */
	rumoured:       i32,         /* ... and the porter: step 5 */
	questioned:     i32,         /* ... and the porter's answer: step 6 */
	corroborated:   i32,         /* ... and the neighbour: step 7 */
	rumouredDump:   string,
	questionedDump: string,
	freshDump:      string,      /* decay: the apprentice's store, just after */
	dayOneDump:     string,      /* ... and a day later */
	text:           string,      /* a save at the end */
}


Stage :: struct {
	w: ^World,
	c: ^Committer,
	s: ^Scheduler,
}


test_stage_move :: proc(st: ^Stage, e: Entity_ID, x: i32, y: i32) {
	g: ^Proposal_Group

	g = proposal_group_group_with_phase(.System, "setup: someone comes over")
	proposal_group_move_to(g, whole(e), on_tile(x, y, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
}


test_stage_say :: proc(st: ^Stage, speaker: Entity_ID, hearer: Entity_ID, content: string) {
	error:  string
	action: Action

	error          = ""
	action         = action_make("say", speaker, hearer, NO_ENTITY)
	action.content = world_intern(st.w, ns_utf8(content))
	bg_check(perform(st.w, st.c, action, 0, &error) != nil)
	/* a second to say it, and time for a second's answer */
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 3000))
}


test_last_said :: proc(w: ^World, actor: Entity_ID, other: Entity_ID) -> u64 {
	ev: ^Event
	i:  uint

	for i = world_event_count(w); i > 0; i -= 1 {
		ev = world_event_at(w, i - 1)
		if string(ev.kind) == "said" && ev.actor == actor && ev.other == other do return ev.index
	}
	return 0
}


/* the foreman's credence in the first claim it heard */
test_credence_of :: proc(knowledge: ^Knowledge, agent: Entity_ID) -> i32 {
	store: ^Knowledge_Store

	store = knowledge_store_of(knowledge, agent)
	if knowledge_store_testimony_count(store) == 0 do return BG_PRIOR
	return knowledge_store_credence_that(store, knowledge_store_testimony_at(store, 0).thing, knowledge_store_testimony_at(store, 0).container)
}


// A format: its %s (the Objective-C's %@) is the attribution. Odin's fmt
// reads `{` as the start of an argument, so each is written `{{`.
test_nails_in_chest :: "#IsIn & {{ what: #Stack & {{ unit: \"iron_nail\" }, " +
                       "within: #Container & {{ material: \"oak\", capacity: 40, " +
                       "place: #OnTile & {{ x: 2, y: 20, level: 0 } }, attribution: %s }"


test_rumour_ :: proc(variant: Rumour_Variant) -> Rumour {
	st:         Stage
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	h:          [8]Entity_ID
	error:      string
	where_:     string
	run:        Rumour

	run = {}
	st.w       = test_world(17)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))

	g    = proposal_group_group_with_phase(.System, "setup: the rumour of the nails")
	h[0] = proposal_group_create(g, "chest", "chest", on_tile(2, 20, 0))
	h[1] = proposal_group_create(g, "smith", "smith", on_tile(3, 20, 0))
	h[2] = proposal_group_create(g, "nails_30", "nails", held_by(h[1], 0))
	h[3] = proposal_group_create(g, "apprentice", "apprentice", on_tile(5, 21, 0))
	h[4] = proposal_group_create(g, "neighbour", "neighbour", on_tile(4, 23, 0))
	h[5] = proposal_group_create(g, "carter", "carter", on_tile(20, 4, 0))
	h[6] = proposal_group_create(g, "porter", "porter", on_tile(26, 4, 0))
	h[7] = proposal_group_create(g, "foreman", "foreman", on_tile(20, 28, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	run.world      = st.w
	run.knowledge  = knowledge
	run.smith      = proposal_group_id_for(g, h[1])
	run.apprentice = proposal_group_id_for(g, h[3])
	run.neighbour  = proposal_group_id_for(g, h[4])
	run.carter     = proposal_group_id_for(g, h[5])
	run.porter     = proposal_group_id_for(g, h[6])
	run.foreman    = proposal_group_id_for(g, h[7])
	agency_control(agency, run.apprentice)
	agency_control(agency, run.neighbour)
	agency_control(agency, run.carter)
	agency_control(agency, run.porter)
	where_ = "#WhereIs & { what: #Stack & { unit: \"iron_nail\" } }"

	// the Objective-C's `goto done` is a break out of this block
	done: {
		/* night: the smith puts the nails in the chest, in sight of the apprentice and the neighbour */
		if variant != .Lie {
			error = ""
			bg_check(perform(st.w, st.c, action_make("put_in", run.smith, proposal_group_id_for(g, h[2]), proposal_group_id_for(g, h[0])), 0,
			                 &error) != nil)
		}
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))

		if variant == .Decay {
			/* the apprentice goes off, out of sight of it all; asked on day 10, it
			 * remembers less, and less surely; on day 20, nothing */
			run.freshDump = knowledge_dump(knowledge, run.apprentice)
			test_stage_move(&st, run.apprentice, 12, 12)
			scheduler_run_until(st.s, time_make(BG_MEMORY_STEP + 3000))
			run.dayOneDump = knowledge_dump(knowledge, run.apprentice)
			scheduler_run_until(st.s, time_make(10 * BG_MEMORY_STEP + 3000))
			test_stage_move(&st, run.foreman, 13, 12)
			test_stage_say(&st, run.foreman, run.apprentice, where_)
			run.told = test_credence_of(knowledge, run.foreman)
			scheduler_run_until(st.s, time_make(20 * BG_MEMORY_STEP + 3000))
			test_stage_say(&st, run.foreman, run.apprentice, where_)
			break done
		}

		/* day 1: the apprentice tells the carter, then the porter; lying, it says it saw */
		test_stage_move(&st, run.apprentice, 20, 5)
		if variant == .Lie {
			test_stage_say(&st, run.apprentice, run.carter, fmt.tprintf(test_nails_in_chest, "#Saw"))
		} else {
			test_stage_say(&st, run.carter, run.apprentice, where_)
		}
		test_stage_move(&st, run.apprentice, 26, 5)
		if variant == .Lie {
			test_stage_say(&st, run.apprentice, run.porter, fmt.tprintf(test_nails_in_chest, "#Saw"))
		} else {
			test_stage_say(&st, run.porter, run.apprentice, where_)
		}
		test_stage_move(&st, run.apprentice, 5, 21)

		/* day 2: the carter tells the foreman, naming the apprentice */
		test_stage_move(&st, run.carter, 20, 27)
		test_stage_say(&st, run.foreman, run.carter, where_)
		test_stage_move(&st, run.carter, 20, 4)
		run.told = test_credence_of(knowledge, run.foreman)
		if variant == .Single do break done
		if variant == .Lie {
			/* the foreman goes to look for itself, and finds the chest empty */
			test_stage_move(&st, run.foreman, 3, 21)
			error = ""
			bg_check(perform(st.w, st.c, action_make("look_in", run.foreman, proposal_group_id_for(g, h[0]), NO_ENTITY), 0,
			                 &error) != nil)
			scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
			break done
		}

		/* the porter tells the foreman, naming no one: step 5 */
		test_stage_move(&st, run.porter, 21, 27)
		test_stage_say(&st, run.porter, run.foreman, fmt.tprintf(test_nails_in_chest, "#Heard"))
		run.rumoured     = test_credence_of(knowledge, run.foreman)
		run.rumouredDump = knowledge_dump(knowledge, run.foreman)

		/* the foreman asks the porter who told it: step 6 */
		test_stage_say(&st, run.foreman, run.porter,
		               "#WhoToldYou & { what: #Stack & { unit: \"iron_nail\" }, " +
		               "within: #Container & { place: #OnTile & { x: 2, y: 20, level: 0 } } }")
		test_stage_move(&st, run.porter, 26, 4)
		run.questioned     = test_credence_of(knowledge, run.foreman)
		run.questionedDump = knowledge_dump(knowledge, run.foreman)

		/* day 3: the neighbour tells the foreman what it saw: step 7 */
		test_stage_move(&st, run.neighbour, 19, 27)
		test_stage_say(&st, run.foreman, run.neighbour, where_)
		run.corroborated = test_credence_of(knowledge, run.foreman)
	}

	run.text = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	return run
}


test_rumour :: proc() {
	full:       Rumour
	again:      Rumour
	single:     Rumour
	lie:        Rumour
	store:      ^Knowledge_Store
	restored:   ^Knowledge
	a:          ^Ancestry
	ev:         ^Event
	w2:         ^World
	deferred:   []^Proposal_Group
	error:      string
	position:   u64
	apprentice: u32
	carter:     u32
	i:          uint

	full   = test_rumour_(.Full)
	single = test_rumour_(.Single)

	/* the claims were said, and answered, as the scenario has it */
	bg_check(test_last_said(full.world, full.apprentice, full.carter) != 0 && test_last_said(full.world, full.apprentice, full.porter) != 0)
	bg_check(test_last_said(full.world, full.carter, full.foreman) != 0 && test_last_said(full.world, full.neighbour, full.foreman) != 0)

	/* 1: no IDs in what agents say: content describes, it never names */
	for i = 0; i < world_event_count(full.world); i += 1 {
		ev = world_event_at(full.world, i)
		if string(ev.kind) == "said" {
			bg_check(ev.detail != nil && !strings.contains(string(ev.detail), "ref(") && !strings.contains(string(ev.detail), "id:"))
		}
	}

	/* the carter names the apprentice; the foreman knows the apprentice only by that */
	store = knowledge_store_of(full.knowledge, full.foreman)
	bg_check(knowledge_store_testimony_count(store) == 3)
	bg_check(knowledge_store_testimony_at(store, 0).attribution == .Heard_From)
	apprentice = knowledge_store_testimony_at(store, 0).root
	bg_check(apprentice != 0 && !knowledge_store_referent(store, apprentice).present && knowledge_store_referent(store, apprentice).truth == 0)

	/* 2: credence follows perceived ancestry: the porter's rumour, its root
	 * unknown, counts again (step 5); asked, the porter names the apprentice,
	 * the groups merge, and credence is the single source's (step 6) */
	bg_check(full.told == BG_PRIOR + BG_TRUST - BG_HEARSAY)
	bg_check(full.rumoured == full.told + BG_TRUST - BG_RUMOUR)
	bg_check(full.rumoured > full.questioned)
	bg_check(full.questioned == single.told)
	bg_check(knowledge_store_testimony_at(store, 1).attribution == .Heard_From && knowledge_store_testimony_at(store, 1).root == apprentice)

	/* 3: the neighbour saw it: an independent root, and credence rises above the single source's */
	bg_check(full.corroborated > full.questioned)
	bg_check(full.corroborated == full.questioned + BG_TRUST)
	bg_check(knowledge_store_testimony_at(store, 2).attribution == .Saw)

	/* 4: true ancestry: the carter's word comes from the apprentice's, which
	 * the apprentice saw; the neighbour's is its own; the inspector flags step
	 * 5's false corroboration, and not step 6's merged group */
	a = knowledge_ancestry_of(full.knowledge, test_last_said(full.world, full.carter, full.foreman))
	bg_check(a != nil && a.relayed && a.parent == test_last_said(full.world, full.apprentice, full.carter))
	a = knowledge_root_of(full.knowledge, test_last_said(full.world, full.carter, full.foreman))
	bg_check(a != nil && !a.relayed && !a.fabricated && a.speaker == full.apprentice && a.origin == full.apprentice)
	a = knowledge_ancestry_of(full.knowledge, test_last_said(full.world, full.porter, full.foreman))
	bg_check(a != nil && a.relayed && a.origin == full.apprentice)
	a = knowledge_ancestry_of(full.knowledge, test_last_said(full.world, full.neighbour, full.foreman))
	bg_check(a != nil && !a.relayed && !a.fabricated && a.origin == full.neighbour)
	bg_check(ns_contains(full.rumouredDump, "false corroboration"))
	bg_check(!ns_contains(full.questionedDump, "false corroboration"))

	/* the same run is the same */
	again = test_rumour_(.Full)
	bg_check(world_state_hash(again.world) == world_state_hash(full.world))
	bg_check(again.text == full.text)

	/* knowledge, testimony, and ancestry are saved, and restored the same */
	w2 = restore(full.text, world_content_build(full.world), &deferred, &position, &error)
	bg_check(w2 != nil)
	restored = autorelease(knowledge_init_with_world(w2))
	knowledge_restore_saved_state(restored, saved_domain_state(full.text, "knowledge"))
	bg_check(knowledge_dump(restored, full.foreman) == knowledge_dump(full.knowledge, full.foreman))
	bg_check(knowledge_dump(restored, full.porter) == knowledge_dump(full.knowledge, full.porter))
	bg_check(knowledge_root_of(restored, test_last_said(full.world, full.carter, full.foreman)).origin == full.apprentice)

	/* 5: variant A: the apprentice made it up. History records a fabrication
	 * root, and the apprentice's store marks it as not believed; the carter
	 * relays it in good faith */
	lie = test_rumour_(.Lie)
	a   = knowledge_ancestry_of(lie.knowledge, test_last_said(lie.world, lie.apprentice, lie.carter))
	bg_check(a != nil && a.fabricated && !a.relayed && a.origin == lie.apprentice)
	a = knowledge_ancestry_of(lie.knowledge, test_last_said(lie.world, lie.carter, lie.foreman))
	bg_check(a != nil && a.fabricated && a.relayed && a.origin == lie.apprentice)
	bg_check(ns_contains(knowledge_dump(lie.knowledge, lie.apprentice), "(not believed)"))
	bg_check(!ns_contains(knowledge_dump(lie.knowledge, lie.carter), "(not believed)"))
	bg_check(ns_contains(knowledge_dump(lie.knowledge, lie.foreman), "truly made up by"))

	/* the foreman looks, finds the chest empty, and sees the nails in the
	 * smith's hand: the claim is found false, and it trusts the carter and the
	 * apprentice less */
	store      = knowledge_store_of(lie.knowledge, lie.foreman)
	carter     = knowledge_store_testimony_at(store, 0).source
	apprentice = knowledge_store_testimony_at(store, 0).root
	bg_check(knowledge_store_testimony_at(store, 0).settled == -1)
	bg_check(knowledge_store_referent(store, knowledge_store_testimony_at(store, 0).thing).form == .Held_By)
	bg_check(knowledge_store_trust_in(store, carter) == BG_TRUST - BG_REFUTED && knowledge_store_trust_in(store, apprentice) == BG_TRUST - BG_REFUTED)
	/* what they say next weighs less than it did */
	bg_check(knowledge_store_weight_of(store, knowledge_store_testimony_at(store, 0)) < BG_TRUST - BG_HEARSAY)
}


/* KNOWLEDGE.md Scenario 1's variant B, and §12: memory decays along the
 * feature hierarchy, the strength of a belief fades, and what fades too far
 * is forgotten; deterministic, and the same on replay. */
test_memory_decay :: proc() {
	decay:  Rumour
	again:  Rumour
	store:  ^Knowledge_Store
	first:  ^Event
	second: ^Event
	i:      uint
	asked:  u64

	decay = test_rumour_(.Decay)

	/* just after, the apprentice remembers the oak chest, the smith's brown
	 * coat, and iron nails; a day later, a wooden chest, a dark coat, and
	 * nails of some metal it can't say */
	bg_check(ns_contains(decay.freshDump, "material: \"oak\""))
	bg_check(ns_contains(decay.freshDump, "coat: \"brown\""))
	bg_check(!ns_contains(decay.dayOneDump, "material: \"oak\""))
	bg_check(ns_contains(decay.dayOneDump, "material: \"wood\""))
	bg_check(ns_contains(decay.dayOneDump, "material: \"metal\""))
	bg_check(ns_contains(decay.dayOneDump, "coat: \"dark\""))
	bg_check(!ns_contains(decay.dayOneDump, "coat: \"brown\""))
	/* its own coat it sees */
	bg_check(ns_contains(decay.dayOneDump, "coat: \"navy\""))

	/* day 10: it still says where, though its description has lost its
	 * detail, and it says how sure it is: its memory's strength */
	first  = nil
	second = nil
	for i = 0; i < world_event_count(decay.world); i += 1 {
		if string(world_event_at(decay.world, i).kind) == "said" && world_event_at(decay.world, i).actor == decay.apprentice {
			if first == nil {
				first = world_event_at(decay.world, i)
			} else {
				second = world_event_at(decay.world, i)
			}
		}
	}
	bg_check(first != nil && strings.contains(string(first.detail), "#IsIn") && strings.contains(string(first.detail), "sure: 10 "))
	bg_check(first != nil && !strings.contains(string(first.detail), "oak") && !strings.contains(string(first.detail), "wood") &&
	         !strings.contains(string(first.detail), "iron"))
	/* the foreman believes it less than a fresh account: it weighs no more than the apprentice is sure */
	bg_check(decay.told == BG_PRIOR + BG_SEEN - 10 * BG_FADE)
	bg_check(decay.told < BG_PRIOR + BG_TRUST)
	asked = first.index if first != nil else 0
	bg_check(knowledge_ancestry_of(decay.knowledge, asked) != nil && knowledge_ancestry_of(decay.knowledge, asked).origin == decay.apprentice &&
	         !knowledge_ancestry_of(decay.knowledge, asked).fabricated)

	/* day 20: it has forgotten, and says so */
	bg_check(second != nil && strings.contains(string(second.detail), "#DontKnow"))
	store = knowledge_store_of(decay.knowledge, decay.apprentice)
	for i = 0; i < knowledge_store_count(store); i += 1 {
		if knowledge_store_referent_at(store, i).truth == decay.smith do bg_check(!knowledge_store_referent_at(store, i).present)
	}
	bg_check(ns_contains(knowledge_dump(decay.knowledge, decay.apprentice), "not there any more"))

	/* the same on replay */
	again = test_rumour_(.Decay)
	bg_check(world_state_hash(again.world) == world_state_hash(decay.world))
	bg_check(again.text == decay.text)
	bg_check(again.dayOneDump == decay.dayOneDump)
}


/* --- salience ------------------------------------------------------------- */

Salience_Run :: struct {
	world:     ^World,
	knowledge: ^Knowledge,
	agency:    ^Agency,
	gossip:    Entity_ID,
	idle:      uint,            /* the worker's observations of the smith, with nothing in mind */
	concerned: uint,            /* ... once the nails concern it */
	busy:      uint,            /* ... while it drives a nail */
	text:      string,
}


test_observed_by :: proc(store: ^Knowledge_Store, actor: u32, kind: cstring) -> uint {
	i: uint
	n: uint

	n = 0
	for i = 0; i < knowledge_store_observation_count(store); i += 1 {
		if knowledge_store_observation_at(store, i).actor == actor && string(knowledge_store_observation_at(store, i).kind) == string(kind) do n += 1
	}
	return n
}


/* The workshop, with the worker holding nails of its own. At rest, with
 * nothing in mind, the worker sees the smith take the smith's nails; then,
 * committed to wedging the lock, which the nails concern, sees the smith put
 * them back; then, driving a nail, sees the smith take them again, and the
 * gossip asks it something. The gossip, who keeps four observations, asks
 * the smith something too, and is told five things. */
test_salience_run :: proc() -> Salience_Run {
	w:          ^World
	c:          ^Committer
	s:          ^Scheduler
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	copy_:      ^Agency
	store:      ^Knowledge_Store
	g:          ^Proposal_Group
	h:          [8]Entity_ID
	gossip:     Entity_ID
	error:      string
	where_:     string
	action:     Action
	run:        Salience_Run
	smith:      u32
	i:          i32

	w          = test_world(19)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	knowledge  = autorelease(knowledge_init_with_world(w))
	agency     = autorelease(agency_init_with_world(w, c, knowledge))
	s          = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))
	committer_submit(c, workshop_setup(true, &h))
	g      = proposal_group_group_with_phase(.System, "setup: the gossip")
	gossip = proposal_group_create(g, "gossip", "gossip", on_tile(3, 5, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	gossip = proposal_group_id_for(g, gossip)
	agency_control(agency, 4)
	store  = knowledge_store_of(knowledge, 4)
	smith  = test_referent_of(store, 5)
	where_ = "#WhereIs & { what: #Stack & { unit: \"iron_nail\" } }"

	/* at rest, nothing in mind: routine */
	bg_check(perform(w, c, action_make("take", 5, 2, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	run.idle = test_observed_by(store, smith, "moved")
	bg_check(knowledge_store_referent(store, test_referent_of(store, 2)).form == .Held_By)   /* seen all the same */

	/* the nails concern it now; it sets to driving one of its own into the lock */
	bg_check(agency_commit(agency, 4, "wedge_lock"))
	bg_check(perform(w, c, action_make("put_in", 5, 2, 1), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	run.concerned = test_observed_by(store, smith, "moved")

	/* driving, it misses what concerns it, but not being spoken to */
	bg_check(perform(w, c, action_make("take", 5, 2, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	run.busy = test_observed_by(store, smith, "moved")
	action         = action_make("say", gossip, 4, NO_ENTITY)
	action.content = world_intern(w, ns_utf8(where_))
	bg_check(perform(w, c, action, 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	/* the question put off is part of the worker's mind, and saved with it */
	copy_ = autorelease(agency_init_with_world(w, c, knowledge))
	agency_restore_saved_state(copy_, agency_saved_state(agency))
	knowledge_set_concerns(knowledge, agency_as_concerns(agency))
	bg_check(slice.equal(agency_saved_state(copy_), agency_saved_state(agency)))
	bg_check(agency_mind_of(agency, 4).nquestions == 1 && ns_contains(strings.join(agency_saved_state(agency), "\n", context.temp_allocator),
	                                                                   "question 4 "))

	/* the gossip asks the smith, and is told five things */
	action         = action_make("say", gossip, 5, NO_ENTITY)
	action.content = world_intern(w, ns_utf8(where_))
	bg_check(perform(w, c, action, 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	for i = 0; i < 5; i += 1 {
		action         = action_make("say", 5, gossip, NO_ENTITY)
		action.content = world_intern(w, ns_utf8(fmt.tprintf("#WhereIs & {{ what: #Stack & {{ count: %d } }", i + 1)))
		bg_check(perform(w, c, action, 0, &error) != nil)
		scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	}
	scheduler_run_until(s, time_make(30000))

	run.world     = w
	run.knowledge = knowledge
	run.agency    = agency
	run.gossip    = gossip
	run.text      = save(w, c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	return run
}


/* the index of the first line of the agent's log with the text, or NOT_FOUND */
test_log_index :: proc(agency: ^Agency, agent: Entity_ID, text: string) -> uint {
	log: []string
	i:   uint

	log = agency_log_of(agency, agent)
	for i = 0; i < uint(len(log)); i += 1 {
		if ns_contains(log[i], text) do return i
	}
	return NOT_FOUND
}


/* KNOWLEDGE.md §7 and §12, AGENCY.md §10: what is kept is what is salient,
 * a busy agent notices less, and a store keeps what fits, the least salient
 * evicted first. */
test_salience :: proc() {
	run:      Salience_Run
	again:    Salience_Run
	store:    ^Knowledge_Store
	restored: ^Knowledge
	o:        ^Observation
	w2:       ^World
	deferred: []^Proposal_Group
	error:    string
	position: u64
	i:        uint

	run   = test_salience_run()
	store = knowledge_store_of(run.knowledge, 4)

	/* routine goes unkept; what its goal concerns is kept; while it drives, not */
	bg_check(run.idle == 0)
	bg_check(run.concerned == 1)
	bg_check(run.busy == 1)
	bg_check(test_logged(run.agency, "[wedge the lock] drive a nail in: drive"))
	for i = 0; i < knowledge_store_observation_count(store); i += 1 {
		o = knowledge_store_observation_at(store, i)
		if string(o.kind) == "moved" && o.actor != knowledge_store_self_referent(store) do bg_check(o.salience == BG_CONCERN)
	}
	/* being asked is noticed even while driving; answering is put off until the drive is done */
	bg_check(test_logged(run.agency, "worth -15, busy: not now"))
	bg_check(test_logged(run.agency, "answering: say R"))
	bg_check(test_log_index(run.agency, 4, "busy: not now") < test_log_index(run.agency, 4, "answering: say R"))
	/* ... at the boundary the drive completes, still holding its goal */
	bg_check(test_logged(run.agency, "t=5002ms [wedge the lock] asked by R5: worth +15, answering"))
	bg_check(ns_contains(knowledge_dump(run.knowledge, 4), "salience 30"))

	/* the gossip keeps four: what it said itself goes first, then the oldest it was told */
	store = knowledge_store_of(run.knowledge, run.gossip)
	bg_check(knowledge_store_observation_count(store) == 4)
	for i = 0; i < knowledge_store_observation_count(store); i += 1 {
		o = knowledge_store_observation_at(store, i)
		bg_check(o.salience == BG_ADDRESSED && o.other == knowledge_store_self_referent(store))
		bg_check(o.content != nil && strings.contains(string(o.content), fmt.tprintf("count: %d", i32(i) + 2)))
	}
	bg_check(knowledge_store_next_serial(store) > knowledge_store_observation_at(store, 3).serial)

	/* the same on replay, and saved and restored the same */
	again = test_salience_run()
	bg_check(world_state_hash(again.world) == world_state_hash(run.world))
	bg_check(again.text == run.text)
	w2 = restore(run.text, world_content_build(run.world), &deferred, &position, &error)
	bg_check(w2 != nil)
	restored = autorelease(knowledge_init_with_world(w2))
	knowledge_restore_saved_state(restored, saved_domain_state(run.text, "knowledge"))
	bg_check(knowledge_dump(restored, 4) == knowledge_dump(run.knowledge, 4))
	bg_check(knowledge_dump(restored, run.gossip) == knowledge_dump(run.knowledge, run.gossip))
	bg_check(knowledge_store_next_serial(knowledge_store_of(restored, run.gossip)) == knowledge_store_next_serial(store))
}


/* --- traces --------------------------------------------------------------- */

/* the agent's percept of a trace of that kind, present, or nil */
test_traced :: proc(store: ^Knowledge_Store, kind: cstring) -> ^Trace_Seen {
	i: uint

	for i = 0; i < knowledge_store_trace_count(store); i += 1 {
		if string(knowledge_store_trace_at(store, i).kind) == string(kind) && knowledge_store_trace_at(store, i).present do return knowledge_store_trace_at(store, i)
	}
	return nil
}


test_any_trace :: proc(w: ^World, kind: cstring) -> bool {
	traces: ^Store
	i:      uint

	traces = world_store_for_kind(w, world_kind_named(w, "Trace"))
	for i = 0; i < store_count(traces); i += 1 {
		if string(world_text_field(w, "Trace.traceKind", store_entity_at_index(traces, i))) == string(kind) do return true
	}
	return false
}


/* KNOWLEDGE.md Scenario 2's first half, "the cleaned workshop", with the
 * workshop's lock: at night the smith wedges the lock, which leaves tool
 * marks on it and scuffs on the floor; then washes the floor and touches up
 * the paint, which removes them and leaves traces of their own. The next
 * morning the foreman comes by. */
test_traces :: proc() {
	w:          ^World
	w2:         ^World
	c:          ^Committer
	s:          ^Scheduler
	activities: ^Activities
	knowledge:  ^Knowledge
	restored:   ^Knowledge
	traces:     ^Traces
	store:      ^Knowledge_Store
	g:          ^Proposal_Group
	paint:      ^Trace_Seen
	smell:      ^Trace_Seen
	soap:       ^Trace_Seen
	ev:         ^Event
	family:     ^tri.Index
	deferred:   []^Proposal_Group
	error:      string
	text:       string
	lock:       Entity_ID
	smith:      Entity_ID
	nails:      Entity_ID
	foreman:    Entity_ID
	position:   u64
	dried:      i64
	boundaries: uint
	i:          uint
	n:          i32

	w          = test_world(23)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	knowledge  = autorelease(knowledge_init_with_world(w))
	traces     = autorelease(traces_init_with_world(w))
	s          = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_add_domain(s, traces_as_domain(traces))
	g       = proposal_group_group_with_phase(.System, "setup: the workshop at night")
	lock    = proposal_group_create(g, "lock", "lock", on_tile(5, 4, 0))
	smith   = proposal_group_create(g, "smith", "smith", on_tile(4, 4, 0))
	nails   = proposal_group_create(g, "nails_10", "nails", held_by(smith, 0))
	foreman = proposal_group_create(g, "foreman", "foreman", on_tile(20, 20, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	lock    = proposal_group_id_for(g, lock)
	smith   = proposal_group_id_for(g, smith)
	nails   = proposal_group_id_for(g, nails)
	foreman = proposal_group_id_for(g, foreman)

	/* 2: every operation that removes traces leaves some of its own */
	family = tri.family_index(world_tri(w), "operations")
	n      = 0
	for i = 0; family != nil && i < tri.index_count(family); i += 1 {
		if tri.at(world_tri(w), tri.pattern(world_tri(w), cstring(tri.index_tag(family, i))), "removes.first") != nil {
			bg_check(tri.at(world_tri(w), tri.pattern(world_tri(w), cstring(tri.index_tag(family, i))), "leaves.first") != nil)
			n += 1
		}
	}
	bg_check(n == 2)

	/* the wedging leaves tool marks on the lock and scuffs on the floor */
	bg_check(perform(w, c, action_make("drive", smith, nails, lock), 0, &error) != nil)
	scheduler_run_until(s, time_make(6000))
	bg_check(test_any_trace(w, "tool_marks") && test_any_trace(w, "scuffs"))

	/* the cover-up: each removal leaves its own */
	bg_check(perform(w, c, action_make("wash_floor", smith, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(17000))
	bg_check(!test_any_trace(w, "scuffs") && test_any_trace(w, "damp_floor") && test_any_trace(w, "soap_smell"))
	bg_check(perform(w, c, action_make("touch_up", smith, lock, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(38000))
	bg_check(!test_any_trace(w, "tool_marks") && test_any_trace(w, "fresh_paint") && test_any_trace(w, "paint_smell"))
	g = proposal_group_group_with_phase(.System, "setup: the smith goes home")
	proposal_group_move_to(g, whole(smith), on_tile(25, 25, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(39000))

	/* 1: traces cost nothing overnight: the night passes in a boundary or two,
	 * the damp floor's run out, removed exactly when it does */
	boundaries = 0
	for test_any_trace(w, "damp_floor") && scheduler_step_until(s, time_make(12 * 3600000)) do boundaries += 1
	dried       = world_time(w).ms
	boundaries += scheduler_run_until(s, time_make(12 * 3600000))
	bg_check(boundaries <= 3)
	bg_check(dried == 16000 + 6 * 3600000)          /* washed from 6 s to 16 s */
	bg_check(!test_any_trace(w, "damp_floor") && test_any_trace(w, "soap_smell"))

	/* the morning: the foreman by the lock perceives fresh paint and smells
	 * it; nothing of the tool marks, the scuffs, or the damp; the smell of
	 * soap is too faint to notice in passing; and only what the traces are,
	 * never what made them */
	g = proposal_group_group_with_phase(.System, "setup: the foreman comes by")
	proposal_group_move_to(g, whole(foreman), on_tile(4, 5, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(12 * 3600000 + 1000))
	store = knowledge_store_of(knowledge, foreman)
	paint = test_traced(store, "fresh_paint")
	smell = test_traced(store, "paint_smell")
	bg_check(paint != nil && smell != nil && test_traced(store, "soap_smell") == nil)
	bg_check(test_traced(store, "tool_marks") == nil && test_traced(store, "scuffs") == nil && test_traced(store, "damp_floor") == nil)
	bg_check(paint != nil && paint.bearer != 0 && knowledge_store_referent(store, paint.bearer).truth == lock)
	/* aged analytically, from when it was made (the touch-up done at 37 s):
	 * fresh paint lasts 3 days */
	bg_check(paint != nil && i64(paint.strength) == 80 * (37000 + 3 * 86400000 - world_time(w).ms) / (3 * 86400000))
	bg_check(knowledge_store_finding(store, "#Cleaned", test_referent_of(store, lock)) == nil)

	/* it investigates (KNOWLEDGE.md §9, deliberate): half a minute watching
	 * closely, and it notices the faint smell of soap (the wash at 16 s; it
	 * lasts a day), and draws what takes thought: someone cleaned up by the
	 * lock */
	bg_check(perform(w, c, action_make("watch_closely", foreman, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(12 * 3600000 + 32000))
	soap  = test_traced(store, "soap_smell")
	smell = test_traced(store, "paint_smell")
	bg_check(soap != nil && soap.bearer == 0 && soap.x == 4 && soap.y == 4)
	bg_check(soap != nil && i64(soap.strength) == 50 * (16000 + 86400000 - soap.seen) / 86400000)
	bg_check(soap != nil && soap.strength < BG_TRACE_FLOOR && smell != nil && soap.strength < smell.strength)
	bg_check(knowledge_store_finding(store, "#Cleaned", test_referent_of(store, lock)) != nil &&
	         string(knowledge_store_finding(store, "#Cleaned", test_referent_of(store, lock)).rule) == "cleaned_nearby")
	/* the developer sees where each came from: its creation, in the touch-up's completion */
	for i = 0; i < world_event_count(w); i += 1 {
		ev = world_event_at(w, i)
		if paint != nil && string(ev.kind) == "created" && ev.subject == paint.truth {
			bg_check(ns_contains(committer_source_of_position(c, ev.group), "touch_up completes"))
		}
	}

	/* saved and restored the same */
	text = save(w, c, []Saved_System{knowledge_as_saved_system(knowledge), domain_as_saved_system(traces_as_domain(traces))})
	w2   = restore(text, world_content_build(w), &deferred, &position, &error)
	bg_check(w2 != nil)
	restored = autorelease(knowledge_init_with_world(w2))
	knowledge_restore_saved_state(restored, saved_domain_state(text, "knowledge"))
	bg_check(knowledge_dump(restored, foreman) == knowledge_dump(knowledge, foreman))
}


/* KNOWLEDGE.md §4 and Scenario 2's plated fitting: the fitting looks brass
 * and is steel. The foreman sees brass; a scratch test reveals steel, which
 * the foreman then knows however often it sees brass again, and leaves a
 * scratch anyone can see. The smith, watching, still sees brass. */
test_appearance :: proc() {
	w:           ^World
	w2:          ^World
	c:           ^Committer
	s:           ^Scheduler
	activities:  ^Activities
	knowledge:   ^Knowledge
	restored:    ^Knowledge
	traces:      ^Traces
	store:       ^Knowledge_Store
	g:           ^Proposal_Group
	deferred:    []^Proposal_Group
	error:       string
	text:        string
	fittingSeen: string
	fitting:     Entity_ID
	lock:        Entity_ID
	smith:       Entity_ID
	foreman:     Entity_ID
	position:    u64
	r:           u32

	w          = test_world(29)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	knowledge  = autorelease(knowledge_init_with_world(w))
	traces     = autorelease(traces_init_with_world(w))
	s          = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_add_domain(s, traces_as_domain(traces))
	g       = proposal_group_group_with_phase(.System, "setup: the fitting")
	fitting = proposal_group_create(g, "fitting", "fitting", on_tile(5, 4, 0))
	lock    = proposal_group_create(g, "lock", "lock", on_tile(5, 5, 0))
	foreman = proposal_group_create(g, "foreman", "foreman", on_tile(4, 4, 0))
	smith   = proposal_group_create(g, "smith", "smith", on_tile(2, 4, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	fitting = proposal_group_id_for(g, fitting)
	lock    = proposal_group_id_for(g, lock)
	foreman = proposal_group_id_for(g, foreman)
	smith   = proposal_group_id_for(g, smith)

	/* 3: perception reports the appearance: brass */
	store       = knowledge_store_of(knowledge, foreman)
	r           = test_referent_of(store, fitting)
	fittingSeen = knowledge_store_describe_referent(store, r)
	bg_check(ns_contains(fittingSeen, "material: \"brass\""))
	bg_check(!ns_contains(fittingSeen, "steel"))
	bg_check(tri.subtype(world_tri(w), tri.Type((^Body)(world_record(w, world_kind_named(w, "Body"), fitting)).material),
	                     tri.type_named(world_tri(w), "\"steel\"")) != 0)

	/* only the scratch test reveals steel, and leaves a scratch */
	bg_check(perform(w, c, action_make("test_scratch", foreman, fitting, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(5000))
	bg_check(ns_contains(knowledge_store_describe_referent(store, r), "material: \"steel\""))
	bg_check(!ns_contains(knowledge_store_describe_referent(store, r), "brass"))
	bg_check(test_any_trace(w, "scratch"))
	bg_check(test_traced(store, "scratch") != nil && test_traced(store, "scratch").bearer == r)
	/* seen again, it still looks brass; the foreman still knows steel */
	g = proposal_group_group_with_phase(.System, "setup: the foreman steps back")
	proposal_group_move_to(g, whole(foreman), on_tile(3, 4, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(6000))
	/* seen again as it stepped back: nothing has happened since
	 * (REALITY.md decision 7) */
	bg_check(knowledge_store_referent_at(store, 0) != nil && knowledge_store_referent(store, r).seen > 5000)
	bg_check(ns_contains(knowledge_store_describe_referent(store, r), "material: \"steel\""))
	/* the smith, who watched, sees the scratch, and still brass */
	bg_check(test_traced(knowledge_store_of(knowledge, smith), "scratch") != nil)
	bg_check(ns_contains(knowledge_store_describe_referent(knowledge_store_of(knowledge, smith), test_referent_of(knowledge_store_of(knowledge, smith), fitting)),
	                     "material: \"brass\""))

	/* a thing that is what it looks like: the test says so */
	g = proposal_group_group_with_phase(.System, "setup: the foreman goes to the lock")
	proposal_group_move_to(g, whole(foreman), on_tile(4, 5, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(7000))
	bg_check(perform(w, c, action_make("test_scratch", foreman, lock, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(11000))
	bg_check(knowledge_store_referent(store, test_referent_of(store, lock)).deeper != nil &&
	         string(knowledge_store_referent(store, test_referent_of(store, lock)).deeper) == "material: \"brass\"")

	/* saved and restored the same */
	text = save(w, c, []Saved_System{knowledge_as_saved_system(knowledge), domain_as_saved_system(traces_as_domain(traces))})
	w2   = restore(text, world_content_build(w), &deferred, &position, &error)
	bg_check(w2 != nil)
	restored = autorelease(knowledge_init_with_world(w2))
	knowledge_restore_saved_state(restored, saved_domain_state(text, "knowledge"))
	bg_check(knowledge_dump(restored, foreman) == knowledge_dump(knowledge, foreman))
}


/* KNOWLEDGE.md Scenario 2's second half, interpretation: the smith wedges the
 * lock at night, with the porter, who can't paint, watching; the porter goes
 * home, and the smith touches up the paint. In the morning the foreman, a
 * painter, the porter, and the carter, who neither paints nor saw the marks,
 * come by the lock. */
test_interpretation :: proc() {
	w:          ^World
	w2:         ^World
	c:          ^Committer
	s:          ^Scheduler
	activities: ^Activities
	knowledge:  ^Knowledge
	restored:   ^Knowledge
	traces:     ^Traces
	store:      ^Knowledge_Store
	g:          ^Proposal_Group
	f:          ^Finding
	deferred:   []^Proposal_Group
	error:      string
	text:       string
	lock:       Entity_ID
	smith:      Entity_ID
	nails:      Entity_ID
	foreman:    Entity_ID
	porter:     Entity_ID
	carter:     Entity_ID
	position:   u64

	w          = test_world(31)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	knowledge  = autorelease(knowledge_init_with_world(w))
	traces     = autorelease(traces_init_with_world(w))
	s          = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_add_domain(s, traces_as_domain(traces))
	g       = proposal_group_group_with_phase(.System, "setup: the workshop at night")
	lock    = proposal_group_create(g, "lock", "lock", on_tile(5, 4, 0))
	smith   = proposal_group_create(g, "smith", "smith", on_tile(4, 4, 0))
	nails   = proposal_group_create(g, "nails_10", "nails", held_by(smith, 0))
	porter  = proposal_group_create(g, "porter", "porter", on_tile(7, 6, 0))
	foreman = proposal_group_create(g, "foreman", "foreman", on_tile(25, 25, 0))
	carter  = proposal_group_create(g, "carter", "carter", on_tile(25, 2, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	lock    = proposal_group_id_for(g, lock)
	smith   = proposal_group_id_for(g, smith)
	nails   = proposal_group_id_for(g, nails)
	porter  = proposal_group_id_for(g, porter)
	foreman = proposal_group_id_for(g, foreman)
	carter  = proposal_group_id_for(g, carter)

	/* the wedging, watched by the porter, who sees the tool marks */
	bg_check(perform(w, c, action_make("drive", smith, nails, lock), 0, &error) != nil)
	scheduler_run_until(s, time_make(6000))
	store = knowledge_store_of(knowledge, porter)
	bg_check(test_traced(store, "tool_marks") != nil)
	g = proposal_group_group_with_phase(.System, "setup: the porter goes home")
	proposal_group_move_to(g, whole(porter), on_tile(25, 12, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(7000))

	/* the touch-up, unwatched */
	bg_check(perform(w, c, action_make("touch_up", smith, lock, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(28000))
	g = proposal_group_group_with_phase(.System, "setup: the smith goes home")
	proposal_group_move_to(g, whole(smith), on_tile(30, 30, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(8 * 3600000))

	/* the morning */
	g = proposal_group_group_with_phase(.System, "setup: they come by the lock")
	proposal_group_move_to(g, whole(foreman), on_tile(4, 4, 0))
	proposal_group_move_to(g, whole(porter), on_tile(6, 4, 0))
	proposal_group_move_to(g, whole(carter), on_tile(5, 6, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(8 * 3600000 + 1000))

	/* everyone sees the fresh paint */
	bg_check(test_traced(knowledge_store_of(knowledge, foreman), "fresh_paint") != nil)
	bg_check(test_traced(knowledge_store_of(knowledge, porter), "fresh_paint") != nil)
	bg_check(test_traced(knowledge_store_of(knowledge, carter), "fresh_paint") != nil)

	/* 5: expertise gates interpretation: the painter concludes something
	 * happened to the lock; the others see only paint */
	store = knowledge_store_of(knowledge, foreman)
	f     = knowledge_store_finding(store, "#Tampered", test_referent_of(store, lock))
	bg_check(f != nil && f.credence == 10 && string(f.rule) == "touched_up")
	bg_check(knowledge_store_finding(knowledge_store_of(knowledge, porter), "#Tampered", test_referent_of(knowledge_store_of(knowledge, porter), lock)) == nil)
	bg_check(knowledge_store_finding_count(knowledge_store_of(knowledge, carter)) == 0)

	/* 4: prior beliefs gate interpretation: the porter, who saw the tool
	 * marks, and sees them gone under fresh paint, concludes they were painted
	 * over; the painter, who never saw them, doesn't */
	store = knowledge_store_of(knowledge, porter)
	bg_check(test_traced(store, "tool_marks") == nil)
	f = knowledge_store_finding(store, "#CoveredUp", test_referent_of(store, lock))
	bg_check(f != nil && f.credence == 20 && string(f.rule) == "covered_up")
	bg_check(knowledge_store_finding(knowledge_store_of(knowledge, foreman), "#CoveredUp", test_referent_of(knowledge_store_of(knowledge, foreman), lock)) == nil)
	bg_check(f != nil && f.time >= 8 * 3600000)           /* drawn in the morning, when it saw the paint */

	/* 6: no truth in what they conclude: a finding is about a referent of
	 * theirs, with the rule that drew it, never what made the traces */
	bg_check(ns_contains(knowledge_dump(knowledge, porter), "finding #CoveredUp about R"))

	/* saved and restored the same */
	text = save(w, c, []Saved_System{knowledge_as_saved_system(knowledge), domain_as_saved_system(traces_as_domain(traces))})
	w2   = restore(text, world_content_build(w), &deferred, &position, &error)
	bg_check(w2 != nil)
	restored = autorelease(knowledge_init_with_world(w2))
	knowledge_restore_saved_state(restored, saved_domain_state(text, "knowledge"))
	bg_check(knowledge_dump(restored, foreman) == knowledge_dump(knowledge, foreman))
	bg_check(knowledge_dump(restored, porter) == knowledge_dump(knowledge, porter))

	/* KNOWLEDGE.md decision 11: a conclusion is retracted only when its
	 * premise is contradicted. The paint is scrubbed off, under their eyes,
	 * days before it would have dried. The porter, glancing, sees it gone,
	 * and the lock was still covered up; the painter looks closely, finds no
	 * paint where there should still be some, and no longer concludes the
	 * lock was touched up */
	{
		all: ^Store
		i:   uint

		all = world_store_for_kind(w, world_kind_named(w, "Trace"))
		g   = proposal_group_group_with_phase(.System, "setup: the paint scrubbed off")
		for i = 0; i < store_count(all); i += 1 {
			if string(world_text_field(w, "Trace.traceKind", store_entity_at_index(all, i))) == "fresh_paint" {
				proposal_group_destroy(g, whole(store_entity_at_index(all, i)), "scrubbed")
			}
		}
		committer_submit(c, g)
	}
	scheduler_run_until(s, time_make(8 * 3600000 + 2000))
	bg_check(!test_any_trace(w, "fresh_paint"))
	bg_check(perform(w, c, action_make("watch_closely", foreman, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(8 * 3600000 + 40000))
	store = knowledge_store_of(knowledge, porter)
	bg_check(knowledge_store_finding(store, "#CoveredUp", test_referent_of(store, lock)) != nil)
	store = knowledge_store_of(knowledge, foreman)
	bg_check(knowledge_store_finding(store, "#Tampered", test_referent_of(store, lock)) == nil)
}


/* KNOWLEDGE.md Scenario 3's notebook: the worker looks into the bin and
 * writes down where the nails are, puts the notebook in the bin, and goes;
 * the smith takes it and reads it. */
test_notebook :: proc() {
	w:          ^World
	w2:         ^World
	c:          ^Committer
	s:          ^Scheduler
	activities: ^Activities
	knowledge:  ^Knowledge
	restored:   ^Knowledge
	store:      ^Knowledge_Store
	thief:      ^Knowledge_Store
	g:          ^Proposal_Group
	t:          ^Testimony
	nails:      ^Referent
	deferred:   []^Proposal_Group
	error:      string
	text:       string
	writing:    string
	written:    bool
	before:     string
	described:  bool
	after:      string
	again:      bool
	h:          [8]Entity_ID
	notebook:   Entity_ID
	position:   u64
	rnails:     u32
	rbook:      u32
	told:       uint
	i:          uint

	w          = test_world(37)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	knowledge  = autorelease(knowledge_init_with_world(w))
	s          = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	committer_submit(c, workshop_setup(false, &h))
	scheduler_run_until(s, time_make(1))
	g        = proposal_group_group_with_phase(.System, "setup: the worker's notebook")
	notebook = proposal_group_create(g, "notebook", "notebook", held_by(4, 1))       /* the worker's */
	committer_submit(c, g)
	scheduler_run_until(s, time_make(2))
	bg_check(proposal_group_applied(g))
	notebook = proposal_group_id_for(g, notebook)

	/* the worker looks into the bin, and writes down where the nails are */
	store = knowledge_store_of(knowledge, 4)
	bg_check(perform(w, c, action_make("look_in", 4, 1, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(3))
	rnails  = test_referent_of(store, 2)
	rbook   = test_referent_of(store, notebook)
	writing, written = knowledge_store_writing_about(store, rnails)
	bg_check(written && rbook != 0)      // writing != nil
	{
		action: Action

		action         = action_make("write_down", Entity_ID(knowledge_store_self_referent(store)), Entity_ID(rbook), NO_ENTITY)
		action.content = world_intern(w, ns_utf8(writing))
		bg_check(perform_believed(w, c, store, action, 0, &error) != nil)
	}
	scheduler_run_until(s, time_make(4))

	/* 3: notebook content is a content entity authored by the character, with
	 * claims copied from beliefs at the time of writing */
	text = ns_string(world_text_field(w, "Record.writing", notebook))
	bg_check(ns_has_prefix(text, "#Writing & { author: #Agent & {"))
	bg_check(ns_contains(text, "coat: \"blue\""))
	bg_check(ns_contains(text, "entries: [#IsIn & { what: #Stack"))
	bg_check(ns_contains(text, "attribution: #Saw & { sure: 30 }"))
	bg_check(!ns_contains(text, "ref("))
	bg_check(test_happened(w, "wrote", 4, notebook))

	/* it puts the notebook in the bin, and goes off */
	bg_check(perform(w, c, action_make("put_in", 4, notebook, 1), 0, &error) != nil)
	scheduler_run_until(s, time_make(5))
	g = proposal_group_group_with_phase(.System, "setup: the worker goes off")
	proposal_group_move_to(g, whole(4), on_tile(20, 20, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(6))
	nails  = knowledge_store_referent(store, rnails)
	before, described = knowledge_store_describe_referent(store, rnails)
	told   = knowledge_store_testimony_count(store)
	bg_check(nails.present && nails.form == .In && nails.toldBy == 0)

	/* the smith takes it from the bin, and reads it */
	bg_check(perform(w, c, action_make("take", 5, notebook, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(1000))
	bg_check(perform(w, c, action_make("read", 5, notebook, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(2000))

	/* 4: the thief's beliefs cite the notebook, with the character as perceived root */
	thief = knowledge_store_of(knowledge, 5)
	bg_check(knowledge_store_testimony_count(thief) == 1)
	t = knowledge_store_testimony_at(thief, 0) if knowledge_store_testimony_count(thief) != 0 else nil
	bg_check(t != nil && t.via == test_referent_of(thief, notebook))
	bg_check(t != nil && t.source == test_referent_of(thief, 4) && t.root == t.source && t.attribution == .Saw)
	bg_check(t != nil && knowledge_store_referent(thief, t.thing).present && knowledge_store_referent(thief, t.thing).container == test_referent_of(thief, 1))
	bg_check(ns_contains(knowledge_dump(knowledge, 5), "wrote so in R"))

	/* 5: the theft leaves the worker's memory as it was */
	after, again = knowledge_store_describe_referent(store, rnails)
	bg_check(again && described && after == before)      // -isEqualToString: is NO from or to nil
	bg_check(knowledge_store_testimony_count(store) == told)
	for i = 0; i < knowledge_store_count(store); i += 1 {
		bg_check(knowledge_store_referent_at(store, i).truth != 5 || knowledge_store_referent_at(store, i).present)
	}

	/* saved and restored the same */
	text = save(w, c, []Saved_System{knowledge_as_saved_system(knowledge)})
	w2   = restore(text, world_content_build(w), &deferred, &position, &error)
	bg_check(w2 != nil)
	restored = autorelease(knowledge_init_with_world(w2))
	knowledge_restore_saved_state(restored, saved_domain_state(text, "knowledge"))
	bg_check(knowledge_dump(restored, 5) == knowledge_dump(knowledge, 5))
}


/* 6: the player's out-of-character notes never reach the character's
 * knowledge; the notebook view shows what the character knows, as it knows
 * it, without truth links */
test_play_notebook :: proc() {
	commands: []string
	out:      string
	knows:    uint
	book:     uint
	h:        u64

	commands = []string{"do 1", "walk w", "tell R4 R5", "ask R4 where R5", "notebook",
	                    "note check the loft again", "notes", "knows", "write R5"}
	out = test_session("workshop", commands, &h)
	bg_check(ns_contains(out, "Things you know of:\n"))
	bg_check(ns_contains(out, "  R5 #Stack, in R2"))
	bg_check(ns_contains(out, "R4 said so, having heard it from you"))
	bg_check(ns_contains(out, "1. check the loft again"))
	bg_check(ns_contains(out, "You hold no notebook."))
	/* the character's store, as the developer sees it, has no note in it */
	knows = ns_range_of(out, "what 4 knows")
	bg_check(knows != NOT_FOUND &&
	         !ns_contains(out[knows:], "loft"))
	/* the notebook view has no truth links */
	book = ns_range_of(out, "Things you know of:")
	bg_check(book != NOT_FOUND && book < knows &&
	         !ns_contains(out[book:][:knows - book], "truth"))

	/* nor do they change what the character says: told the same, with and
	 * without a note, the world is the same to the bit */
	{
		with:    string
		without: string
		h1:      u64
		h2:      u64

		with    = test_session("workshop", []string{"do 1", "walk w", "note the nails are in the loft",
		                                            "tell R4 R5", "hash"}, &h1)
		without = test_session("workshop", []string{"do 1", "walk w", "tell R4 R5", "hash"}, &h2)
		bg_check(h1 == h2)
		bg_check(ns_contains(with, "said: 4, other 5, #IsIn"))
		bg_check(!ns_contains(with[ns_range_of(with, "said: 4"):], "loft"))
		_ = without
	}
}


/* COMPONENTS.md Scenario 1's step 4: afterwards, someone looking into the bin finds the bent nail, an
 * individual among the clean ones, tool marks and all: evidence (§4). */
test_marked_nail_found :: proc() {
	scenario:  ^Marked_Nail
	w:         ^World
	c:         ^Committer
	s:         ^Scheduler
	knowledge: ^Knowledge
	store:     ^Knowledge_Store
	r:         ^Referent
	error:     string
	seen:      string
	i:         uint
	bin:       u32
	found:     bool

	scenario  = test_run_marked_nail(.Base, 42)
	w         = marked_nail_world(scenario)
	c         = marked_nail_committer(scenario)
	knowledge = autorelease(knowledge_init_with_world(w))
	s         = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	store = knowledge_store_of(knowledge, 5)
	bin   = test_referent_of(store, 1)
	bg_check(bin != 0)
	error = ""
	bg_check(perform_believed(w, c, store, action_make("look_in", Entity_ID(knowledge_store_self_referent(store)), Entity_ID(bin), NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	found = false
	for i = 0; i < knowledge_store_count(store); i += 1 {
		r     = knowledge_store_referent_at(store, i)
		seen  = knowledge_store_describe_referent(store, r.id)
		found = found || (r.form == .In && r.container == bin && string(r.kind) == "#Body" &&
		                  ns_contains(seen, "bent: true"))
	}
	bg_check(found)
	bg_check(ns_contains(knowledge_dump(knowledge, 5), "trace tool_marks on"))
}


/* KNOWLEDGE.md Scenario 2's swap: the worker sees the workshop's worn wrench
 * on the bench (`saw`, or not), goes off, and meanwhile the wrench is swapped
 * for a new one; back, it sees the new one. Its knowledge, dumped. */
test_swap_run :: proc(saw: bool) -> string {
	st:        Stage
	knowledge: ^Knowledge
	g:         ^Proposal_Group
	worker:    Entity_ID
	old:       Entity_ID

	st.w      = test_world(127)
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	g      = proposal_group_group_with_phase(.System, "setup: the bench")
	worker = proposal_group_create(g, "worker", "worker", on_tile(5, 6, 0) if saw else on_tile(20, 20, 0))
	old    = proposal_group_create(g, "wrench_250", "the old wrench", on_tile(6, 6, 0))
	proposal_group_set_of_to(g, "Body.toolMarks", whole(old), 40)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	old    = proposal_group_id_for(g, old)
	test_stage_move(&st, worker, 20, 20)
	g = proposal_group_group_with_phase(.System, "setup: the swap")
	proposal_group_move_to(g, whole(old), on_tile(25, 2, 0))
	proposal_group_create(g, "wrench_250", "the new wrench", on_tile(6, 6, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	test_stage_move(&st, worker, 5, 6)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	{
		restored: ^Knowledge
		text:     string

		/* what it noticed is saved */
		text     = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge)})
		restored = autorelease(knowledge_init_with_world(st.w))
		knowledge_restore_saved_state(restored, saved_domain_state(text, "knowledge"))
		bg_check(knowledge_dump(restored, worker) == knowledge_dump(knowledge, worker))
	}
	return knowledge_dump(knowledge, worker)
}


/* 4: prior beliefs gate interpretation. Recognition takes the new wrench
 * for the old (same kind, same place); one who saw the old one worn sees it
 * lose its tool marks, which don't wear off, and concludes it was replaced.
 * One who never saw the old one sees a new-looking wrench: nothing. */
test_wrench_replaced :: proc() {
	saw:   string
	never: string

	saw   = test_swap_run(true)
	never = test_swap_run(false)
	bg_check(ns_contains(saw, "toolMarks: 0"))
	bg_check(ns_contains(saw, "finding #Replaced about R2, +15 dB, by replaced"))
	bg_check(ns_contains(never, "#Wrench"))
	bg_check(!ns_contains(never, "#Replaced"))
	bg_check(test_swap_run(true) == saw)
}


/* KNOWLEDGE.md Scenario 3's check 2, the bump. By day the worker sees the
 * door open, and goes off; night falls, and someone shuts it. Back beside it
 * in the dark, it can't make it out, and remembers it open: the menu offers
 * going through, from the stale belief. Going through is a bump into the
 * shut door, which it feels: it believes it shut, and stays where it was.
 * `lamp`: it carries a shining lamp, and sees the door shut beside it. */
test_door_run :: proc(lamp: bool, menuText: ^string, afar: ^string, where_: ^Entity_ID) -> string {
	st:        Stage
	knowledge: ^Knowledge
	store:     ^Knowledge_Store
	g:         ^Proposal_Group
	menu:      ^Menu
	worker:    Entity_ID
	door:      Entity_ID
	error:     string
	entries:   [dynamic]string
	i:         uint
	rdoor:     u32

	st.w      = test_world(137)
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	g      = proposal_group_group_with_phase(.System, "setup: the loft door")
	worker = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	door   = proposal_group_create(g, "room_door", "the loft door", on_tile(4, 6, 0))
	proposal_group_set_of_to(g, "Door.ajar", whole(door), 1)
	if lamp do proposal_group_create(g, "lamp", "lamp", held_by(worker, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	door   = proposal_group_id_for(g, door)
	store  = knowledge_store_of(knowledge, worker)
	rdoor  = test_referent_of(store, door)

	/* off, night, the door shut behind its back */
	test_stage_move(&st, worker, 4, 15)
	knowledge_set_ambient(knowledge, 0)
	g = proposal_group_group_with_phase(.System, "setup: someone shuts the loft door")
	proposal_group_set_of_to(g, "Door.ajar", whole(door), 0)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	/* coming back: three tiles off, in the dark, it sees nothing there, and
	 * doesn't take that for its absence */
	test_stage_move(&st, worker, 4, 3)
	afar^ = strings.concatenate({knowledge_store_describe_referent(store, rdoor), " (there)" if knowledge_store_referent(store, rdoor).present else " (gone)"},
	                            context.temp_allocator)
	test_stage_move(&st, worker, 4, 5)

	menu    = menu_for_world_believed(store, st.w, true)
	entries = make([dynamic]string, context.temp_allocator)
	for i = 0; i < menu_count(menu); i += 1 do append(&entries, menu_describe_at(menu, i))
	menuText^ = strings.join(entries[:], "; ", context.temp_allocator)
	error = ""
	if ns_contains(menuText^, "go_through") {
		bg_check(perform_believed(st.w, st.c, store, action_make("go_through", Entity_ID(knowledge_store_self_referent(store)), Entity_ID(rdoor), NO_ENTITY), 0,
		                          &error) != nil)
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	}
	where_^ = Entity_ID(world_location_of(st.w, worker).y) if world_location_of(st.w, worker).form == .On_Tile else 0
	return knowledge_store_describe_referent(store, rdoor)
}


test_door_in_the_dark :: proc() {
	menu: string
	afar: string
	door: string
	y:    Entity_ID

	door = test_door_run(false, &menu, &afar, &y)
	bg_check(ns_contains(afar, "ajar: true") && ns_has_suffix(afar, " (there)"))
	bg_check(ns_contains(menu, "go_through item R"))
	bg_check(ns_contains(door, "ajar: false"))
	bg_check(y == 5)

	/* with a lamp (its reach two tiles), beside the door it sees it shut,
	 * and the menu doesn't offer going through */
	door = test_door_run(true, &menu, &afar, &y)
	bg_check(ns_contains(door, "ajar: false"))
	bg_check(!ns_contains(menu, "go_through") && y == 5)
}


/* COMPONENTS.md Scenario 2, "the forged permit". The harbour office's
 * permit P lets Alun into the warehouse: an authorization the office made,
 * linked to P; Alun holds a copy, C1, sealed with the office's seal; the
 * office's ledger lists P. A forger borrows C1 and, with a carved fake
 * stamp, makes C2 with the name changed; the guard sees it. A: a clerk makes
 * an exact duplicate, C3. B: C1 burns. */
test_forged_permit :: proc() {
	st:           Stage
	knowledge:    ^Knowledge
	store:        ^Knowledge_Store
	g:            ^Proposal_Group
	office:       Entity_ID
	permit:       Entity_ID
	auth:         Entity_ID
	reg:          Entity_ID
	ledger:       Entity_ID
	c1:           Entity_ID
	c2:           Entity_ID
	c3:           Entity_ID
	altered:      Entity_ID
	seal:         Entity_ID
	fake:         Entity_ID
	alun:         Entity_ID
	forger:       Entity_ID
	clerk:        Entity_ID
	guard:        Entity_ID
	veteran:      Entity_ID
	warehouse:    Entity_ID
	ev:           ^Event
	edge:         ^Edge
	error:        string
	seen:         string
	authority:    []Entity_ID
	forge:        Action
	i:            uint
	v:            i64
	derived:      bool
	madeByForger: bool
	stamped:      bool

	st.w      = test_world(151)
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	g         = proposal_group_group_with_phase(.System, "setup: the harbour office's procedure")
	office    = proposal_group_create(g, "harbour_office", "the harbour office", location_make_none())
	warehouse = proposal_group_create(g, "storeroom", "the warehouse", on_tile(20, 4, 0))
	alun      = proposal_group_create(g, "alun", "Alun", on_tile(3, 3, 0))
	forger    = proposal_group_create(g, "forger", "the forger", on_tile(4, 3, 0))
	clerk     = proposal_group_create(g, "clerk", "the clerk", on_tile(10, 10, 0))
	guard     = proposal_group_create(g, "guard", "the guard", on_tile(19, 4, 0))
	permit    = proposal_group_create(g, "content", "permit P", location_make_none())
	proposal_group_set_of_to_text(g, "Information.text", whole(permit), "Alun may enter the warehouse")
	proposal_group_set_of_to_text(g, "Information.issuer", whole(permit), "the harbour office")
	auth      = proposal_group_create(g, "authorization", "Alun's authorization", location_make_none())
	proposal_group_set_of_to_text(g, "Authorization.grants", whole(auth), "enter")
	proposal_group_set_of_to(g, "Authorization.over", whole(auth), i64(warehouse))
	proposal_group_set_of_to(g, "Authorization.grantee", whole(auth), i64(alun))
	proposal_group_relate(g, .Authorizes, whole(auth), whole(permit))
	reg       = proposal_group_create(g, "content", "the register", location_make_none())
	proposal_group_set_of_to_text(g, "Information.text", whole(reg), "permits issued")
	proposal_group_relate(g, .Lists, whole(reg), whole(permit))
	ledger    = proposal_group_create(g, "ledger", "the office's ledger", on_tile(10, 11, 0))
	proposal_group_set_of_to(g, "Inscription.inscribed", whole(ledger), i64(reg))
	seal      = proposal_group_create(g, "stamp", "the office seal", on_tile(11, 10, 0))
	proposal_group_set_of_to_text(g, "Stamp.presses", whole(seal), "the harbour anchor")
	proposal_group_set_of_to_text(g, "Stamp.sealOf", whole(seal), "the harbour office")
	veteran   = proposal_group_create(g, "guard", "a veteran guard, at the office", on_tile(11, 11, 0))
	c1        = proposal_group_create(g, "paper_copy", "C1", held_by(alun, 0))
	proposal_group_set_of_to(g, "Inscription.inscribed", whole(c1), i64(permit))
	proposal_group_set_of_to_text(g, "Inscription.reads", whole(c1), "Alun may enter the warehouse")
	proposal_group_set_of_to_text(g, "Inscription.claims", whole(c1), "the harbour office")
	proposal_group_set_of_to_text(g, "Inscription.penned", whole(c1), "a clerk's round hand")
	proposal_group_set_of_to_text(g, "Inscription.impression", whole(c1), "the harbour anchor")
	fake      = proposal_group_create(g, "stamp", "a carved fake stamp", held_by(forger, 1))
	proposal_group_set_of_to_text(g, "Stamp.presses", whole(fake), "an anchor, crudely cut")
	proposal_group_set_of_to_text(g, "Scribe.handwriting", whole(forger), "a careful, cramped hand")
	proposal_group_set_of_to_text(g, "Scribe.handwriting", whole(clerk), "a clerk's round hand")
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	office    = proposal_group_id_for(g, office)
	warehouse = proposal_group_id_for(g, warehouse)
	alun      = proposal_group_id_for(g, alun)
	forger    = proposal_group_id_for(g, forger)
	clerk     = proposal_group_id_for(g, clerk)
	guard     = proposal_group_id_for(g, guard)
	veteran   = proposal_group_id_for(g, veteran)
	permit    = proposal_group_id_for(g, permit)
	auth      = proposal_group_id_for(g, auth)
	reg       = proposal_group_id_for(g, reg)
	ledger    = proposal_group_id_for(g, ledger)
	seal      = proposal_group_id_for(g, seal)
	c1        = proposal_group_id_for(g, c1)
	fake      = proposal_group_id_for(g, fake)
	bg_check(world_get_field(st.w, "Inscription.inscribed", c1, &v) && v == i64(permit))

	/* 1: the forger borrows C1 and makes C2, the name changed, pressed with its fake stamp */
	g = proposal_group_group_with_phase(.System, "setup: Alun lends C1")
	proposal_group_move_to(g, whole(c1), held_by(forger, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(2))
	forge         = action_make("copy_out", forger, c1, NO_ENTITY)
	forge.content = world_intern(st.w, "Bran may enter the warehouse")
	error         = ""
	g = perform(st.w, st.c, forge, 0, &error)
	bg_check(g != nil)
	scheduler_run_until(st.s, time_make(3))
	c2 = NO_ENTITY
	for i = 0; i < proposal_group_count(g); i += 1 {
		if proposal_group_proposals(g)[i].kind == .Create && string(proposal_group_proposals(g)[i].name) == "paper_copy" {
			c2 = proposal_group_id_for(g, proposal_group_proposals(g)[i].handle)
		}
	}
	bg_check(c2 != NO_ENTITY && world_get_field(st.w, "Inscription.inscribed", c2, &v))
	altered = Entity_ID(v)
	bg_check(altered != permit && string(world_text_field(st.w, "Information.text", altered)) == "Bran may enter the warehouse")

	/* 2: the guard sees C2: what it says, and what can be seen of it */
	g = proposal_group_group_with_phase(.System, "setup: the forger shows C2 at the warehouse")
	proposal_group_move_to(g, whole(forger), on_tile(18, 4, 0))
	proposal_group_move_to(g, whole(c2), on_tile(18, 4, 0))
	proposal_group_move_to(g, whole(veteran), on_tile(18, 5, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(4))
	store = knowledge_store_of(knowledge, guard)
	seen  = knowledge_store_describe_referent(store, test_referent_of(store, c2))
	bg_check(ns_contains(seen, "reads: \"Bran may enter the warehouse\""))
	bg_check(ns_contains(seen, "claims: \"the harbour office\""))
	bg_check(ns_contains(seen, "penned: \"a careful, cramped hand\""))
	bg_check(ns_contains(seen, "impression: \"an anchor, crudely cut\""))
	/* 3: the player's view has only the claimed origin; the actual is in history */
	bg_check(!ns_contains(seen, "inscribed"))
	/* whether it is believed (KNOWLEDGE.md §4): the guard, who has never seen
	 * the office's seal, can't tell; the veteran, who has, sees the crude
	 * anchor isn't it, and finds C2 forged */
	bg_check(!ns_contains(knowledge_dump(knowledge, guard), "#Forged"))
	store = knowledge_store_of(knowledge, veteran)
	bg_check(knowledge_store_finding(store, "#Forged", test_referent_of(store, c2)) != nil)
	bg_check(test_referent_of(store, c1) != 0 && knowledge_store_finding(store, "#Forged", test_referent_of(store, c1)) == nil)

	/* 1 (checks): content, the office, the authorization have no location;
	 * copies, the ledger, the stamps have one */
	bg_check(world_location_of(st.w, permit).form == .None && world_location_of(st.w, altered).form == .None &&
	         world_location_of(st.w, office).form == .None && world_location_of(st.w, auth).form == .None)
	bg_check(world_location_of(st.w, c1).form != .None && world_location_of(st.w, c2).form != .None &&
	         world_location_of(st.w, ledger).form != .None && world_location_of(st.w, fake).form != .None)

	/* 2: P′ derived from P; its actual creation is the forger's; 3: it claims the office */
	derived = false
	for i = 0; i < world_edge_count(st.w); i += 1 {
		edge    = world_edge_at(st.w, i)
		derived = derived || (edge.kind == .Derived_From && edge.from == altered && edge.to == permit)
	}
	madeByForger = false
	stamped      = false
	for i = 0; i < world_event_count(st.w); i += 1 {
		ev           = world_event_at(st.w, i)
		madeByForger = madeByForger || (string(ev.kind) == "created" && ev.subject == altered && ev.actor == forger)
		stamped      = stamped || (string(ev.kind) == "stamped" && ev.subject == fake && ev.other == c2)
	}
	bg_check(derived && madeByForger)
	bg_check(string(world_text_field(st.w, "Information.issuer", altered)) == "the harbour office")
	/* 5: authority over the warehouse is the office's authorization alone; P′ confers nothing */
	authority = authorizations_over(st.w, warehouse)
	bg_check(len(authority) == 1 && authority[0] == auth)
	bg_check(content_authorizes(st.w, permit) && !content_authorizes(st.w, altered))
	/* authorize(action): Alun's going into the warehouse has the office's
	 * authorization; the forger's, none; neither is blocked by it */
	bg_check(len(authorize(st.w, action_make("look_in", alun, warehouse, NO_ENTITY))) == 1)
	bg_check(len(authorize(st.w, action_make("look_in", forger, warehouse, NO_ENTITY))) == 0)
	/* 6: the fake stamp, P′, C2 and the forger's creation are found through provenance */
	bg_check(stamped)

	/* A: the clerk makes an exact duplicate, C3: a new copy of P itself */
	g = proposal_group_group_with_phase(.System, "setup: C1 to the clerk, at the office")
	proposal_group_move_to(g, whole(c1), held_by(clerk, 0))
	proposal_group_move_to(g, whole(seal), held_by(clerk, 1))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(5))
	g = perform(st.w, st.c, action_make("copy_out", clerk, c1, NO_ENTITY), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(st.s, time_make(6))
	c3 = NO_ENTITY
	for i = 0; i < proposal_group_count(g); i += 1 {
		if proposal_group_proposals(g)[i].kind == .Create do c3 = proposal_group_id_for(g, proposal_group_proposals(g)[i].handle)
	}
	bg_check(c3 != NO_ENTITY && world_get_field(st.w, "Inscription.inscribed", c3, &v) && v == i64(permit))
	bg_check(string(world_text_field(st.w, "Inscription.impression", c3)) == "the harbour anchor")

	/* B: C1 burns; P persists, referenced by the ledger's register and by C3;
	 * what referred to C1 resolves to its tombstone; 4 */
	g = proposal_group_group_with_phase(.System, "setup: C1 burns")
	proposal_group_destroy(g, whole(c1), "burnt")
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(7))
	bg_check(!world_is_live(st.w, c1) && world_tombstone(st.w, c1) != nil)
	bg_check(world_is_live(st.w, permit) && world_is_live(st.w, reg) && world_is_live(st.w, c3))
	bg_check(len(authority) == 1)

	/* saved and restored: the content, its derivation, and the authority, the same */
	{
		w2:       ^World
		deferred: []^Proposal_Group
		position: u64

		w2 = restore(save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge)}), world_content_build(st.w), &deferred, &position,
		             &error)
		bg_check(w2 != nil && world_state_hash(w2) == world_state_hash(st.w))
		bg_check(w2 != nil && len(authorizations_over(w2, warehouse)) == 1 && !content_authorizes(w2, altered))
	}
}


/* DOMAIN_SIMULATION.md Scenario 2 and COMPONENTS.md §7, latent assembly
 * (provisional): the crank pump `key` (its seed), a "flow loss" committed
 * against it at hour 300, opened two levels by a worker with a wrench at
 * `openAt`; `saveAt`, if not 0: saved then, and opened in the restored world.
 * What was revealed: "role blueprint wear; ..." in role order, and the
 * culprit's role, or "" if none. */
Pump_Run :: struct {
	parts:    string,
	culprit:  string,
	menu:     string,       /* the worker's, before opening */
	pumpMass: i64,          /* g, after */
	total:    i64,          /* g, the pump and its parts */
	inside:   bool,         /* every part partOf the pump */
}


test_pump_opened :: proc(blueprint: cstring, key: cstring, failure: cstring, openAt: i64,
                         saveAt: i64, used: i64, abused: i64) -> Pump_Run {
	st:      Stage
	g:       ^Proposal_Group
	pump:    Entity_ID
	worker:  Entity_ID
	wrench:  Entity_ID
	parts:   ^Store
	at:      Location
	menu:    ^Menu
	found:   [dynamic]string
	entries: [dynamic]string
	error:   string
	run:     Pump_Run
	i:       uint
	v:       i64

	run = {}
	st.w   = test_world(157)
	st.c   = test_committer(st.w)
	st.s   = autorelease(scheduler_init_with_world(st.w, st.c))
	g      = proposal_group_group_with_phase(.System, "setup: the pump house")
	pump   = proposal_group_create(g, blueprint, key, on_tile(5, 5, 0))
	worker = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	wrench = proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump   = proposal_group_id_for(g, pump)
	worker = proposal_group_id_for(g, worker)
	wrench = proposal_group_id_for(g, wrench)
	g = proposal_group_group_with_phase(.System, "history: use, and a failure")
	proposal_group_set_of_to(g, "Latent.used", whole(pump), used)
	proposal_group_set_of_to(g, "Latent.abused", whole(pump), abused)
	proposal_group_set_of_to_text(g, "Latent.failure", whole(pump), failure)
	proposal_group_set_of_to(g, "Latent.failedAt", whole(pump), 300 * 3600000)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(2))

	menu    = menu_for_world(worker, st.w)
	entries = make([dynamic]string, context.temp_allocator)
	for i = 0; i < menu_count(menu); i += 1 do append(&entries, menu_describe_at(menu, i))
	run.menu = strings.join(entries[:], "; ", context.temp_allocator)

	if saveAt != 0 {
		text: string

		scheduler_run_until(st.s, time_make(saveAt))
		text  = save(st.w, st.c, []Saved_System{})
		error = ""
		st.w  = test_restore(text, world_content_build(st.w), &st.c, &error)
		st.s  = autorelease(scheduler_init_with_world(st.w, st.c))
	}
	scheduler_run_until(st.s, time_make(openAt))
	error = ""
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(openAt + 1000))
	bg_check(perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(openAt + 2000))

	found       = make([dynamic]string, context.temp_allocator)
	run.culprit = ""
	run.inside  = true
	parts       = world_store_for_kind(st.w, world_kind_named(st.w, "Part"))
	world_get_field(st.w, "Body.mass", pump, &run.pumpMass)
	run.total = run.pumpMass
	for i = 0; i < store_count(parts); i += 1 {
		e: Entity_ID

		e  = store_entity_at_index(parts, i)
		at = world_location_of(st.w, e)
		run.inside = run.inside && at.form == .Part_Of && at.place == pump
		world_get_field(st.w, "Part.wear", e, &v)
		append(&found, fmt.tprintf("%s %s %d", location_role(&at), world_info(st.w, e).blueprint, v))
		if v >= 60 do run.culprit = strings.clone(location_role(&at), context.temp_allocator)      // at is the loop's: copied, as stringWithUTF8String: did
		world_get_field(st.w, "Body.mass", e, &v)
		run.total += v
	}
	run.parts = strings.join(found[:], "; ", context.temp_allocator)
	return run
}


test_pump_open :: proc(key: cstring, failure: cstring, openAt: i64, saveAt: i64) -> Pump_Run {
	return test_pump_opened("crank_pump", key, failure, openAt, saveAt, 0, 0)
}


/* A revealed role's wear in a run's parts, or -1. */
test_wear_in :: proc(run: Pump_Run, role: string) -> i64 {
	fields: []string
	entry:  string
	i:      uint

	for i = 0; i < uint(len(ns_components_separated(run.parts, "; "))); i += 1 {
		entry  = ns_components_separated(run.parts, "; ")[i]
		fields = ns_components_separated(entry, " ")
		if len(fields) == 3 && fields[0] == role do return ns_long_long_value(fields[2])
	}
	return -1
}


/* LATENT_ASSEMBLY.md decisions 4-6: the pump `blueprint` `key`, `usedHours`
 * of use behind it, drawing from a well of `water` mL into its empty header
 * tank, worked an hour at a time for `hours` hours by a worker; saved and
 * restored after hour `saveAfter`, if not 0; then opened two levels. */
Pump_Work :: struct {
	used:       i64,
	abused:     i64,
	well:       i64,
	tank:       i64,
	flow:       i64,
	failedAt:   i64,
	blamedWear: i64,          /* the blamed part's, opened; -1 if none */
	failure:    string,
	blamed:     string,
	failedIn:   i32,          /* the hour it failed in, from 1; 0 if it didn't */
}


test_pump_work :: proc(blueprint: cstring, key: cstring, failure: cstring, water: i64,
                       usedHours: i64, hours: i32, saveAfter: i32) -> Pump_Work {
	st:     Stage
	g:      ^Proposal_Group
	pump:   Entity_ID
	well:   Entity_ID
	tank:   Entity_ID
	worker: Entity_ID
	wrench: Entity_ID
	parts:  ^Store
	run:    Pump_Work
	error:  string
	text:   cstring
	i:      uint
	t:      i64
	h:      i32

	run = {}
	st.w   = test_world(157)
	st.c   = test_committer(st.w)
	st.s   = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	g      = proposal_group_group_with_phase(.System, "setup: the pump on its well")
	pump   = proposal_group_create(g, blueprint, key, on_tile(5, 5, 0))
	well   = proposal_group_create(g, "well", "the well", on_tile(5, 6, 0))
	tank   = proposal_group_create(g, "header_tank", "the header tank", on_tile(5, 4, 0))
	worker = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	wrench = proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	proposal_group_set_of_to(g, "Pump.draws", whole(pump), i64(well))
	proposal_group_set_of_to(g, "Latent.riser", whole(pump), i64(tank))
	proposal_group_set_of_to(g, "Latent.used", whole(pump), usedHours * 3600000)
	if failure != nil do proposal_group_set_of_to_text(g, "Latent.failure", whole(pump), failure)
	proposal_group_set_of_to(g, "WaterStore.water", whole(well), water)
	proposal_group_set_of_to(g, "WaterStore.water", whole(tank), 0)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	pump   = proposal_group_id_for(g, pump)
	well   = proposal_group_id_for(g, well)
	tank   = proposal_group_id_for(g, tank)
	worker = proposal_group_id_for(g, worker)
	wrench = proposal_group_id_for(g, wrench)

	for h = 1; h <= hours; h += 1 {
		/* a worker rested and fed for every hour: its pace is not the point */
		t = world_time(st.w).ms
		g = proposal_group_group_with_phase(.System, "setup: the worker rested and fed")
		proposal_group_set_of_to(g, "Agent.fatigue", whole(worker), 0)
		proposal_group_set_of_to(g, "Agent.injury", whole(worker), 0)
		proposal_group_set_of_to(g, "Hungry.satiety", whole(worker), 80)
		proposal_group_set_of_to(g, "Hungry.fedAt", whole(worker), t)
		committer_submit(st.c, g)
		error = ""
		perform(st.w, st.c, action_make("work_pump", worker, pump, NO_ENTITY), 0, &error)
		scheduler_run_until(st.s, time_make(t + 3600000 + 1000))
		text = world_text_field(st.w, "Latent.failure", pump)
		if run.failedIn == 0 && text != nil && string(text) != "" && failure == nil do run.failedIn = h
		if h == saveAfter {
			saved: string      // the Objective-C's inner `text`, which shadowed the outer

			saved = save(st.w, st.c, []Saved_System{})
			st.w  = test_restore(saved, world_content_build(st.w), &st.c, &error)
			st.s  = autorelease(scheduler_init_with_world(st.w, st.c))
			scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
		}
	}
	world_get_field(st.w, "Latent.used", pump, &run.used)
	world_get_field(st.w, "Latent.abused", pump, &run.abused)
	world_get_field(st.w, "Latent.failedAt", pump, &run.failedAt)
	world_get_field(st.w, "WaterStore.water", well, &run.well)
	world_get_field(st.w, "WaterStore.water", tank, &run.tank)
	world_get_field(st.w, "Pump.flow", pump, &run.flow)
	text        = world_text_field(st.w, "Latent.failure", pump)
	run.failure = strings.clone(string(text) if text != nil else "", context.temp_allocator)
	text        = world_text_field(st.w, "Latent.blamed", pump)
	run.blamed  = strings.clone(string(text) if text != nil else "", context.temp_allocator)

	/* opened: the blamed part, if it is one, is as worn as a failure leaves it */
	perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	perform(st.w, st.c, action_make("open_up", worker, wrench, pump), 0, &error)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	run.blamedWear = -1
	parts          = world_store_for_kind(st.w, world_kind_named(st.w, "Part"))
	for i = 0; i < store_count(parts); i += 1 {
		if len(run.blamed) != 0 {
			text = world_text_field(st.w, "Part.fits", store_entity_at_index(parts, i))
			if text != nil && string(text) == run.blamed {
				world_get_field(st.w, "Part.wear", store_entity_at_index(parts, i), &run.blamedWear)
			}
		}
	}
	return run
}

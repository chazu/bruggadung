package lab

/*
 * Hunting (VILLAGE.md slice 7, content/hunting/): death, animals, the bow,
 * butchering, and a week of it.
 */

import "core:fmt"
import tri "../../triangle/odin/triangle"


/* Death (VILLAGE.md decision 7): a body whose injury reaches 100 is its
 * remains, whoever it is: a person's, a corpse as heavy as it was, where it
 * was; what it held falls there, and its mind goes with it. */
test_death :: proc() {
	error: string

	w := test_world(108)
	c := test_committer(w)
	activities := activities_with_world(w, c)
	knowledge  := autorelease(knowledge_init_with_world(w))
	agency     := autorelease(agency_init_with_world(w, c, knowledge))
	s          := autorelease(scheduler_init_with_world(w, c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))

	g := proposal_group_group_with_phase(.System, "setup: one hurt nearly to death, holding an axe, and one who strikes")
	victim  := proposal_group_create(g, "farmhand", "the victim", on_tile(5, 5, 0))
	striker := proposal_group_create(g, "farmhand", "the striker", on_tile(6, 5, 0))
	axe     := proposal_group_create(g, "axe", "an axe", held_by(victim, 0))
	proposal_group_set_of_to(g, "Agent.injury", whole(victim), 90)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	victim, striker, axe = proposal_group_id_for(g, victim), proposal_group_id_for(g, striker), proposal_group_id_for(g, axe)
	agency_mind_of(agency, victim)
	scheduler_run_until(s, time_make(2))
	mass := world_mass_of(w, victim)
	bg_check(agency_has_mind(agency, victim) && mass > 0)

	/* a blow: injury 105, so 100, and it dies */
	if perform(w, c, action_make("hit", striker, victim, NO_ENTITY), 0, &error) == nil do fmt.printf("    hit: %s\n", error)
	scheduler_run_until(s, time_make(3000))
	bg_check(!world_is_live(w, victim))
	found: [8]Entity_ID
	corpse := NO_ENTITY
	for e in found[:world_entities_near(w, on_tile(5, 5, 0), 0, raw_data(found[:]), len(found))] {
		if world_info(w, e) != nil && world_info(w, e).blueprint == "corpse" do corpse = e
	}
	bg_check(corpse != NO_ENTITY && world_mass_of(w, corpse) == mass)
	at := world_location_of(w, axe)
	bg_check(at.form == .On_Tile && at.x == 5 && at.y == 5)
	bg_check(!agency_has_mind(agency, victim))
	/* the striker lives, and is unhurt */
	injury: i64
	bg_check(world_is_live(w, striker) && world_get_field(w, "Agent.injury", striker, &injury) && injury == 0)
}


/* The animals (VILLAGE.md decision 7): a deer roams, wandering the woods and
 * grazing; one that sees a person runs off out of sight, and runs again
 * when it sees it again. A person draws no danger from anyone. */
test_animals :: proc() {
	w := test_world(109)
	why: string
	bg_check(world_set_terrain_map(w, "woods_map", &why))
	c := test_committer(w)
	committer_set_tracing(c, false)
	activities := activities_with_world(w, c)
	knowledge  := autorelease(knowledge_init_with_world(w))
	agency     := autorelease(agency_init_with_world(w, c, knowledge))
	s          := autorelease(scheduler_init_with_world(w, c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))
	done := Test_Done{}
	defer test_done_free(&done)

	g := proposal_group_group_with_phase(.System, "setup: a deer in the woods")
	deer := proposal_group_create(g, "deer", "a deer", on_tile(20, 12, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	deer = proposal_group_id_for(g, deer)
	bg_check(agency_has_mind(agency, deer))          /* its instinct: it roams */

	/* six hours of roaming: it moves, on woodland, and grazes an hour at a
	 * time */
	moved, off := 0, 0
	last := world_location_of(w, deer)
	for scheduler_step_until(s, time_make(6 * 3600 * 1000)) {
		test_count_done(w, &done)
		at := world_location_of(w, deer)
		if at.x != last.x || at.y != last.y do moved += 1
		if terrain_kind_info(world_terrain(w), terrain_at(world_terrain(w), at.x, at.y, 0)).name != "woodland" do off += 1
		last = at
	}
	if moved <= 10 || off != 0 do fmt.printf("    moved %d, off the woodland %d\n", moved, off)
	bg_check(moved > 10 && off == 0)
	bg_check(done.counts["graze"] >= 4 && done.counts["graze"] <= 6)

	/* a person three tiles off: it runs, out of sight */
	at := world_location_of(w, deer)
	px := at.x - 3 if at.x > 8 else at.x + 3
	g = proposal_group_group_with_phase(.System, "setup: a person comes near")
	person := proposal_group_create(g, "farmhand", "a person", on_tile(px, at.y, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	person = proposal_group_id_for(g, person)
	test_run_counting(s, w, &done, world_time(w).ms + 30 * 1000)
	bg_check(done.counts["flee"] >= 1)
	bg_check(!test_within(w, deer, person, 4))

	/* it comes near again: it runs again */
	at = world_location_of(w, deer)
	g = proposal_group_group_with_phase(.System, "setup: the person, near again")
	proposal_group_move_to(g, whole(person), on_tile(at.x - 2 if at.x > 7 else at.x + 2, at.y, 0))
	committer_submit(c, g)
	test_run_counting(s, w, &done, world_time(w).ms + 30 * 1000)
	bg_check(done.counts["flee"] >= 2)
	bg_check(!test_within(w, deer, person, 4))

	/* the person, who has seen the deer, holds no danger of it */
	store := knowledge_store_of(knowledge, person)
	bg_check(store != nil && knowledge_store_finding_count(store) == 0)
}


/* Activities seen completed, by operation, each once. */
Test_Done :: struct {
	counts: map[string]int,
	seen:   map[Entity_ID]bool,
}


test_done_free :: proc(d: ^Test_Done) {
	delete(d.counts)
	delete(d.seen)
}


/* Boundary by boundary up to t, counting what completes; then to t. */
test_run_counting :: proc(s: ^Scheduler, w: ^World, d: ^Test_Done, t: i64) {
	for scheduler_step_until(s, time_make(t)) do test_count_done(w, d)
	scheduler_run_until(s, time_make(t))
	test_count_done(w, d)
}


/* Counts the activities completed since last counted. */
test_count_done :: proc(w: ^World, d: ^Test_Done) {
	completed := u32(tri.type_named(world_tri(w), "\"completed\""))
	store := world_store_for_kind(w, world_kind_named(w, "Activity"))
	for i: uint = 0; i < store_count(store); i += 1 {
		a := (^Activity)(store_record_at_index(store, i))
		e := store_entity_at_index(store, i)
		if a.status != completed || e in d.seen do continue
		d.seen[e] = true
		op := world_text_field(w, "Activity.operation", e)
		if op != nil do d.counts[string(op)] += 1      /* interned: the world keeps it */
	}
}


/* Whether a and b are within so many tiles of each other. */
@(private = "file")
test_within :: proc(w: ^World, a: Entity_ID, b: Entity_ID, tiles: i32) -> bool {
	p, q := world_location_of(w, a), world_location_of(w, b)
	return abs(p.x - q.x) <= tiles && abs(p.y - q.y) <= tiles
}


/* The bow (VILLAGE.md decision 7): a hunter crouched three tiles from a
 * deer is unseen; from four it can't shoot; from three, the deer is wounded
 * by the bow's 40, the shot gives the hunter away, and the deer runs. Shot
 * at 70 injury, it dies: a carcass where it was, as heavy. */
test_bow :: proc() {
	error: string

	w := test_world(110)
	why: string
	bg_check(world_set_terrain_map(w, "woods_map", &why))
	c := test_committer(w)
	committer_set_tracing(c, false)
	activities := activities_with_world(w, c)
	knowledge  := autorelease(knowledge_init_with_world(w))
	agency     := autorelease(agency_init_with_world(w, c, knowledge))
	s          := autorelease(scheduler_init_with_world(w, c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))
	done := Test_Done{}
	defer test_done_free(&done)

	g := proposal_group_group_with_phase(.System, "setup: a deer, and a hunter with a bow out of its sight")
	deer   := proposal_group_create(g, "standing_deer", "a deer", on_tile(20, 12, 0))
	hunter := proposal_group_create(g, "farmhand", "a hunter", on_tile(12, 12, 0))
	bow    := proposal_group_create(g, "bow", "a bow", held_by(hunter, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	deer, hunter, bow = proposal_group_id_for(g, deer), proposal_group_id_for(g, hunter), proposal_group_id_for(g, bow)
	agency_mind_of(agency, deer)

	/* crouched, it comes within four tiles, then three: unseen */
	bg_check(perform(w, c, action_make("crouch", hunter, bow, NO_ENTITY), 0, &error) != nil)
	test_run_counting(s, w, &done, 2000)
	hiding: i64
	bg_check(world_get_field(w, "Agent.hiding", hunter, &hiding) && hiding == 1)
	test_move(c, hunter, 16, 12)
	test_run_counting(s, w, &done, 3000)
	error = ""
	bg_check(perform(w, c, action_make("shoot", hunter, bow, deer), 0, &error) == nil)
	test_move(c, hunter, 17, 12)
	test_run_counting(s, w, &done, 4000)
	ds := knowledge_store_of(knowledge, deer)
	bg_check(ds == nil || knowledge_store_finding_count(ds) == 0)

	/* the shot: wounded, the hunter seen, and the deer runs */
	error = ""
	if perform(w, c, action_make("shoot", hunter, bow, deer), 0, &error) == nil do fmt.printf("    shoot: %s\n", error)
	test_run_counting(s, w, &done, 20000)
	injury: i64
	bg_check(world_get_field(w, "Agent.injury", deer, &injury) && injury == 40)
	bg_check(world_get_field(w, "Agent.hiding", hunter, &hiding) && hiding == 0)
	bg_check(done.counts["flee"] >= 1 && !test_within(w, deer, hunter, 3))

	/* hurt to 70, and shot again: it dies, a carcass as heavy */
	at := world_location_of(w, deer)
	mass := world_mass_of(w, deer)
	g = proposal_group_group_with_phase(.System, "setup: the deer hurt to 70, the hunter near it")
	proposal_group_set_of_to(g, "Agent.injury", whole(deer), 70)
	proposal_group_move_to(g, whole(hunter), on_tile(at.x - 2 if at.x > 6 else at.x + 2, at.y, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	at = world_location_of(w, deer)
	error = ""
	if perform(w, c, action_make("shoot", hunter, bow, deer), 0, &error) == nil do fmt.printf("    shoot: %s\n", error)
	test_run_counting(s, w, &done, world_time(w).ms + 3000)
	bg_check(!world_is_live(w, deer))
	found: [8]Entity_ID
	carcass := NO_ENTITY
	for e in found[:world_entities_near(w, at, 0, raw_data(found[:]), len(found))] {
		if world_info(w, e) != nil && world_info(w, e).blueprint == "deer_carcass" do carcass = e
	}
	bg_check(carcass != NO_ENTITY && world_mass_of(w, carcass) == mass)
}


/* Moved by the system, at once. */
@(private = "file")
test_move :: proc(c: ^Committer, e: Entity_ID, x: i32, y: i32) {
	g := proposal_group_group_with_phase(.System, "setup: moved")
	proposal_group_move_to(g, whole(e), on_tile(x, y, 0))
	committer_submit(c, g)
}


/* Butchering (VILLAGE.md decision 7): a deer's carcass, a hand free, is
 * forty cuts of raw venison in that hand, a hide where it lay, and the rest
 * waste. With no hand free, it can't be. */
test_butcher :: proc() {
	error: string

	w := test_world(111)
	c := test_committer(w)
	activities := activities_with_world(w, c)
	s          := autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))

	g := proposal_group_group_with_phase(.System, "setup: a carcass, and a hunter beside it with a bow")
	carcass := proposal_group_create(g, "deer_carcass", "a carcass", on_tile(5, 5, 0))
	hunter  := proposal_group_create(g, "farmhand", "a hunter", on_tile(6, 5, 0))
	bow     := proposal_group_create(g, "bow", "a bow", held_by(hunter, 0))
	other   := proposal_group_create(g, "farmhand", "another, hands full", on_tile(4, 5, 0))
	proposal_group_create(g, "bow", "a bow", held_by(other, 0))
	proposal_group_create(g, "bow", "a bow", held_by(other, 1))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	carcass, hunter, bow, other = proposal_group_id_for(g, carcass), proposal_group_id_for(g, hunter), proposal_group_id_for(g, bow),
	                              proposal_group_id_for(g, other)

	error = ""
	bg_check(perform(w, c, action_make("butcher", other, carcass, NO_ENTITY), 0, &error) == nil)
	if perform(w, c, action_make("butcher", hunter, carcass, NO_ENTITY), 0, &error) == nil do fmt.printf("    butcher: %s\n", error)
	scheduler_run_until(s, time_make(31 * 60 * 1000))
	bg_check(!world_is_live(w, carcass))
	held: [2]Entity_ID
	meat := NO_ENTITY
	for e in held[:world_entities_at(w, hunter, .Held_By, raw_data(held[:]), 2)] do if e != bow do meat = e
	raw: i64
	bg_check(meat != NO_ENTITY && world_unit_of(w, meat) == "venison" && world_units_of(w, meat) == 40)
	bg_check(world_mass_of(w, meat) == 20000 && world_get_field(w, "Food.raw", meat, &raw) && raw == 1)
	found: [8]Entity_ID
	hide := NO_ENTITY
	for e in found[:world_entities_near(w, on_tile(5, 5, 0), 0, raw_data(found[:]), len(found))] {
		if world_info(w, e) != nil && world_info(w, e).blueprint == "deer_hide" do hide = e
	}
	bg_check(hide != NO_ENTITY && world_mass_of(w, hide) == 4000)
}


/* A week of hunting (issue #7's done-when): a hunter with a bow, bound to
 * its larder at the woods' edge through its working hours; deer in the
 * woods, kept up to four by the herd coming in from the east edge. Over
 * seven days the hunter brings meat home, the deer run from it when they
 * see it, and the herd never vanishes nor outgrows its four. */
test_hunting_week :: proc() {
	w := test_world(112)
	why: string
	bg_check(world_set_terrain_map(w, "woods_map", &why))
	c := test_committer(w)
	committer_set_tracing(c, false)
	activities := activities_with_world(w, c)
	knowledge  := autorelease(knowledge_init_with_world(w))
	agency     := autorelease(agency_init_with_world(w, c, knowledge))
	game       := autorelease(game_init_with_world(w))
	s          := autorelease(scheduler_init_with_world(w, c))
	agency_set_activities(agency, activities)
	scheduler_add_domain(s, game_as_domain(game))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))
	game_add_herd(game, "deer", 4, 6 * 3600 * 1000, 6 * 3600 * 1000, {{39, 4}, {39, 12}, {39, 20}})
	done := Test_Done{}
	defer test_done_free(&done)

	g := proposal_group_group_with_phase(.System, "setup: a hunter by its larder, three deer in the woods")
	larder := proposal_group_create(g, "larder", "the larder", on_tile(2, 11, 0))
	hunter := proposal_group_create(g, "huntsman", "the hunter", on_tile(3, 12, 0))
	proposal_group_create(g, "bow", "a bow", held_by(hunter, 0))
	for at in ([3][2]i32{{20, 6}, {26, 15}, {32, 9}}) do proposal_group_create(g, "deer", "a deer", on_tile(at.x, at.y, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	larder, hunter = proposal_group_id_for(g, larder), proposal_group_id_for(g, hunter)
	test_own_it(c, hunter, larder)
	scheduler_run_until(s, time_make(2))
	kept := u32(0)
	store := knowledge_store_of(knowledge, hunter)
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		if knowledge_store_referent_at(store, i).truth == larder do kept = knowledge_store_referent_at(store, i).id
	}
	bg_check(kept != 0)
	bg_check(agency_undertake_every_with(agency, hunter, "game_hunted", 7 * 3600 * 1000, 15 * 3600 * 1000, "work", FARM_DAY,
	                                     {{"larder", kept}}))

	fewest, most := 100, 0
	for d in 0 ..< i64(7) {
		for scheduler_step_until(s, time_make((d + 1) * FARM_DAY)) {
			test_count_done(w, &done)
			n := game_count(w, "deer")
			fewest, most = min(fewest, n), max(most, n)
		}
	}
	venison := 0
	inside: [16]Entity_ID
	for e in inside[:world_entities_at(w, larder, .In, raw_data(inside[:]), len(inside))] {
		u := world_unit_of(w, e)
		if u != nil && u == "venison" do venison += int(world_units_of(w, e))
	}
	fmt.printf("    a week: %d venison home, %d shots, %d butchered, %d flights, deer %d to %d\n", venison,
	           done.counts["shoot"], done.counts["butcher"], done.counts["flee"], fewest, most)
	bg_check(venison >= 40)
	bg_check(done.counts["flee"] > 0)
	bg_check(fewest >= 1 && most <= 4)
}


/* An ownership claim of the owner's on the thing, committed. */
@(private = "file")
test_own_it :: proc(c: ^Committer, owner: Entity_ID, thing: Entity_ID) {
	g := proposal_group_group_with_phase(.System, "setup: its own")
	claim := proposal_group_create(g, "ownership", "its own", location_make_none())
	proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
	proposal_group_relate(g, .Claimant, whole(claim), whole(owner))
	proposal_group_relate(g, .Claim_Subject, whole(claim), whole(thing))
	committer_submit(c, g)
}

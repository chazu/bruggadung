package lab

/*
 * Carrying (VILLAGE.md decision 11, content/carrying/): a backpack is
 * shouldered, onto the back, and both hands stay free; what is put in it
 * goes where its carrier goes, up to its load and no more; carried, a load
 * past the burden's light slows a walk; unpacked, a thing is taken out and
 * put in a larder; put back, it lies beside the larder. A basket is
 * held in a hand, and bears less.
 */

import "core:fmt"


test_carrying :: proc() {
	error: string

	w := test_world(116)
	why: string
	bg_check(world_set_terrain_map(w, "woods_map", &why))
	c := test_committer(w)
	activities := activities_with_world(w, c)
	s := autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))

	g := proposal_group_group_with_phase(.System, "setup: a farmer, a backpack and a basket, two sacks of grain, a larder")
	farmer := proposal_group_create(g, "farmer", "the farmer", on_tile(10, 10, 0))
	pack   := proposal_group_create(g, "backpack", "the backpack", on_tile(11, 10, 0))
	basket := proposal_group_create(g, "basket", "the basket", on_tile(11, 10, 0))
	one    := proposal_group_create(g, "grain_sack", "a sack", on_tile(10, 11, 0))
	two    := proposal_group_create(g, "grain_sack", "another", on_tile(10, 11, 0))
	larder := proposal_group_create(g, "larder", "the larder", on_tile(9, 10, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	farmer, pack, basket = proposal_group_id_for(g, farmer), proposal_group_id_for(g, pack), proposal_group_id_for(g, basket)
	one, two, larder = proposal_group_id_for(g, one), proposal_group_id_for(g, two), proposal_group_id_for(g, larder)
	t := i64(1)
	act :: proc(w: ^World, c: ^Committer, s: ^Scheduler, t: ^i64, a: Action, units: i64 = 0) -> bool {
		error: string
		ok := perform(w, c, a, units, &error) != nil
		if !ok do fmt.printf("    %s: %s\n", a.operation, error)
		t^ += 3000
		scheduler_run_until(s, time_make(t^))
		return ok
	}

	/* shouldered: on the back, both hands free */
	bg_check(act(w, c, s, &t, action_make("shoulder", farmer, pack, NO_ENTITY)))
	at := world_location_of(w, pack)
	bg_check(at.form == .Held_By && at.place == farmer && at.slot == BG_BACK && free_hands(w, farmer) == 2)

	/* fifteen kilograms of grain in it; another fifteen won't go */
	bg_check(act(w, c, s, &t, action_make("take", farmer, one, NO_ENTITY)))
	bg_check(act(w, c, s, &t, action_make("put_in", farmer, one, pack)))
	bg_check(world_location_of(w, one).form == .In && world_location_of(w, one).place == pack)
	bg_check(act(w, c, s, &t, action_make("take", farmer, two, NO_ENTITY)))
	act(w, c, s, &t, action_make("put_in", farmer, two, pack))
	bg_check(world_location_of(w, two).form == .Held_By)

	/* carried, thirty-one kilograms (the pack and its sack, the other sack
	 * in hand): sixteen past the light fifteen, a walk at 71% */
	bg_check(carried_mass(w, farmer) == 31000 && burdened_rate(w, farmer) == 100 * 40 / 56)
	error = ""
	bg_check(perform(w, c, action_make("walk_east", farmer, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(t + 1390))
	bg_check(world_location_of(w, farmer).x == 10)
	scheduler_run_until(s, time_make(t + 1420))
	bg_check(world_location_of(w, farmer).x == 11)
	g = proposal_group_group_with_phase(.System, "setup: the other sack put down")
	proposal_group_move_to(g, whole(two), on_tile(10, 11, 0))
	committer_submit(c, g)
	t += 1
	scheduler_run_until(s, time_make(t))
	t += 2000
	g = proposal_group_group_with_phase(.System, "setup: back beside the larder")
	proposal_group_move_to(g, whole(farmer), on_tile(10, 10, 0))
	committer_submit(c, g)
	t += 1
	scheduler_run_until(s, time_make(t))

	/* unpacked into the larder (taken out, put in); the pack put back
	 * beside it */
	bg_check(act(w, c, s, &t, action_make("take", farmer, one, NO_ENTITY)))
	bg_check(act(w, c, s, &t, action_make("put_in", farmer, one, larder)))
	bg_check(world_location_of(w, one).form == .In && world_location_of(w, one).place == larder)
	bg_check(act(w, c, s, &t, action_make("put_back", farmer, pack, larder)))
	at = world_location_of(w, pack)
	bg_check(at.form == .On_Tile && at.x == 9 && at.y == 10)

	/* a basket, in a hand: eight kilograms at most */
	bg_check(act(w, c, s, &t, action_make("take", farmer, basket, NO_ENTITY)))
	bg_check(free_hands(w, farmer) == 1)
	bg_check(act(w, c, s, &t, action_make("take", farmer, two, NO_ENTITY)))
	act(w, c, s, &t, action_make("put_in", farmer, two, basket))
	bg_check(world_location_of(w, two).form == .Held_By)
}


/*
 * Seed in a pack (content/carrying/'s kept_in_the_larder): a farmer back
 * from market, the backpack still on, kept seed back into it at the
 * harvest. Putting the pack back, it unpacks the seed into the larder, as
 * it would food or a hide, and the pack lies by the larder, empty. Seed
 * was neither: it stayed in the pack for good.
 */
test_seed_unpacked :: proc() {
	w := test_world(121)
	why: string
	bg_check(world_set_terrain_map(w, "farm_map", &why))
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

	g := proposal_group_group_with_phase(.System, "setup: a farmer, seed in the pack on its back, its larder")
	me     := proposal_group_create(g, "farmhand", "the farmer", on_tile(10, 2, 0))
	larder := proposal_group_create(g, "larder", "its larder", on_tile(12, 2, 0))
	pack   := proposal_group_create(g, "backpack", "its backpack", held_by(me, BG_BACK))
	seed   := proposal_group_create(g, "seed_grain", "seed kept back", in_(pack))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	me, larder = proposal_group_id_for(g, me), proposal_group_id_for(g, larder)
	pack, seed = proposal_group_id_for(g, pack), proposal_group_id_for(g, seed)
	test_own(c, me, larder)
	test_own(c, me, pack)
	scheduler_run_until(s, time_make(2))
	store := knowledge_store_of(knowledge, me)
	kept := u32(0)
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		if r := knowledge_store_referent_at(store, i); r.truth == larder do kept = r.id
	}
	bg_check(kept != 0)
	bg_check(agency_undertake_every_with(agency, me, "pack_returned", 0, 3600 * 1000, "home", FARM_DAY, {{"home", kept}}))
	scheduler_run_until(s, time_make(3600 * 1000))

	inside: [4]Entity_ID
	at := world_location_of(w, seed)
	lp, ll := world_location_of(w, pack), world_location_of(w, larder)
	ok := at.form == .In && at.place == larder && world_entities_at(w, pack, .In, raw_data(inside[:]), 4) == 0 &&
	      lp.form == .On_Tile && abs(lp.x - ll.x) <= 1 && abs(lp.y - ll.y) <= 1
	if !ok {
		fmt.printf("    seed at %v, pack at %v\n", at, world_location_of(w, pack))
		for line in agency_log_of(agency, me) do fmt.printf("    %s\n", line)
	}
	bg_check(ok)
}


/*
 * Things just alike, unpacked (KNOWLEDGE.md decision 18): three portions of
 * grain in the pack, bought at market. One taken out is the one it took,
 * in its hand, not one like it left in the pack where that was believed;
 * and a portion in hand is food to keep, as a stack is: so it puts each
 * away in turn. Before, the one left in the pack took over the taken one's
 * referent, a portion in hand was nothing to put away, and a hunter took
 * them out one after another until its hands were full, and never put the
 * pack back.
 */
test_look_alikes_unpacked :: proc() {
	w := test_world(125)
	why: string
	bg_check(world_set_terrain_map(w, "farm_map", &why))
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

	g := proposal_group_group_with_phase(.System, "setup: a farmer, three portions of grain in the pack on its back, its larder")
	me     := proposal_group_create(g, "farmhand", "the farmer", on_tile(10, 2, 0))
	larder := proposal_group_create(g, "larder", "its larder", on_tile(12, 2, 0))
	pack   := proposal_group_create(g, "backpack", "its backpack", held_by(me, BG_BACK))
	grains: [3]Entity_ID
	for &e in grains do e = proposal_group_create(g, "grain", "bought", in_(pack))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	me, larder, pack = proposal_group_id_for(g, me), proposal_group_id_for(g, larder), proposal_group_id_for(g, pack)
	for &e in grains do e = proposal_group_id_for(g, e)
	test_own(c, me, larder)
	test_own(c, me, pack)
	scheduler_run_until(s, time_make(2))
	store := knowledge_store_of(knowledge, me)
	kept := u32(0)
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		if r := knowledge_store_referent_at(store, i); r.truth == larder do kept = r.id
	}
	bg_check(kept != 0)

	/* one taken out by what it believes it is: that one is in its hand */
	error: string
	self_ := knowledge_store_self_referent(store)
	taken := test_referent_of(store, grains[0])
	bg_check(taken != 0 && perform_believed(w, c, store, action_make("take", Entity_ID(self_), Entity_ID(taken), NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	r := knowledge_store_referent(store, taken)
	bg_check(r.form == .Held_By && r.container == self_)
	bg_check(agency_undertake_every_with(agency, me, "pack_returned", 0, 3600 * 1000, "home", FARM_DAY, {{"home", kept}}))
	scheduler_run_until(s, time_make(3600 * 1000))

	inside: [4]Entity_ID
	lp, ll := world_location_of(w, pack), world_location_of(w, larder)
	ok := world_entities_at(w, larder, .In, raw_data(inside[:]), 4) == 3 && world_entities_at(w, pack, .In, raw_data(inside[:]), 4) == 0 &&
	      lp.form == .On_Tile && abs(lp.x - ll.x) <= 1 && abs(lp.y - ll.y) <= 1
	if !ok {
		fmt.printf("    pack at %v\n", lp)
		for line in agency_log_of(agency, me) do fmt.printf("    %s\n", line)
	}
	bg_check(ok)
}


/*
 * Free after an impossible goal (lab/src/agency_agency.odin): a farmer to
 * eat its supper, with nothing to eat anywhere it knows, and the pack on
 * its back to put back by its larder, both now. Supper found impossible, it
 * puts the pack back at once, as it would after a goal done. Waiting
 * instead, a seller hungry at three, with nothing to eat, never put back
 * the pack it had taken to market: the window was over before anything
 * woke it.
 */
test_free_after_impossible :: proc() {
	w := test_world(122)
	why: string
	bg_check(world_set_terrain_map(w, "farm_map", &why))
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

	g := proposal_group_group_with_phase(.System, "setup: a farmer, its empty pack on its back, its empty larder")
	me     := proposal_group_create(g, "farmhand", "the farmer", on_tile(10, 2, 0))
	larder := proposal_group_create(g, "larder", "its larder", on_tile(12, 2, 0))
	pack   := proposal_group_create(g, "backpack", "its backpack", held_by(me, BG_BACK))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	me, larder, pack = proposal_group_id_for(g, me), proposal_group_id_for(g, larder), proposal_group_id_for(g, pack)
	test_own(c, me, larder)
	test_own(c, me, pack)
	scheduler_run_until(s, time_make(1000))
	store := knowledge_store_of(knowledge, me)
	kept := u32(0)
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		if r := knowledge_store_referent_at(store, i); r.truth == larder do kept = r.id
	}
	bg_check(kept != 0)
	bg_check(agency_undertake_every_with(agency, me, "eat_supper", 0, 3600 * 1000, "home", FARM_DAY, {}))
	bg_check(agency_undertake_every_with(agency, me, "pack_returned", 0, 3600 * 1000, "home", FARM_DAY, {{"home", kept}}))
	agency_control(agency, me)
	/* at once, not when something next wakes it */
	scheduler_run_until(s, time_make(5000))

	impossible := test_logged_by(agency, me, "[eat supper] nothing I know of will do: impossible for now")
	/* put back, it is done (#Did of an instant operation), not impossible */
	back := world_location_of(w, pack).form == .On_Tile && test_logged_by(agency, me, "[put the pack back] done") &&
	        !test_logged_by(agency, me, "[put the pack back] nothing I know of will do")
	if !impossible || !back {
		fmt.printf("    supper impossible: %v, the pack put back: %v\n", impossible, back)
		for line in agency_log_of(agency, me) do fmt.printf("    %s\n", line)
	}
	bg_check(impossible && back)
}

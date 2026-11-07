package lab

import "core:fmt"

/*
 * Cooking (VILLAGE.md slice 4, content/cooking/): a portion taken from a
 * sack is food still, raw; cooked at a lit stove it is a meal, and
 * nourishes more; at a cold stove, or cooked again, it can't be. Of a stack
 * held, one portion is cooked.
 */

test_cooking :: proc() {
	error: string
	raw, nourishment, count: i64

	w := test_world(7)
	c := test_committer(w)
	activities := activities_with_world(w, c)
	s := autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	cook   := test_commit_create(c, "farmer", on_tile(5, 5, 0))
	larder := test_commit_create(c, "larder", on_tile(6, 5, 0))
	stove  := test_commit_create(c, "stove", on_tile(5, 6, 0))
	bg_check(cook != NO_ENTITY && larder != NO_ENTITY && stove != NO_ENTITY)
	g := proposal_group_group_with_phase(.System, "setup: a sack in the larder")
	sack := proposal_group_create(g, "grain_sack", "the sack", in_(larder))
	committer_submit(c, g)
	committer_commit_boundary(c)
	sack = proposal_group_id_for(g, sack)

	/* a portion taken: food still, raw, as the sack is; the sack one less */
	g = perform(w, c, action_make("take_some", cook, sack, NO_ENTITY), 1, &error)
	bg_check(g != nil)
	world_set_boundary(w, world_boundary(w) + 1)
	committer_commit_boundary(c)
	held: [2]Entity_ID
	bg_check(world_entities_at(w, cook, .Held_By, raw_data(held[:]), 2) == 1)
	portion := held[0]
	bg_check(world_get_field(w, "Food.raw", portion, &raw) && raw == 1)
	bg_check(world_get_field(w, "Food.nourishment", portion, &nourishment) && nourishment == 15)
	bg_check(world_get_field(w, "Stack.count", sack, &count) && count == 59)
	bg_check(world_info(w, portion) != nil && string(world_info(w, portion).blueprint) == "grain")

	/* at a cold stove it can't be cooked */
	bg_check(perform(w, c, action_make("cook", cook, portion, stove), 0, &error) == nil)

	/* lit, it can: twenty minutes, and it is a meal */
	g = perform(w, c, action_make("light", cook, stove, NO_ENTITY), 0, &error)
	bg_check(g != nil)
	world_set_boundary(w, world_boundary(w) + 1)
	committer_commit_boundary(c)
	error = ""
	bg_check(perform(w, c, action_make("cook", cook, portion, stove), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1200 * 1000 + 1))
	bg_check(world_get_field(w, "Food.raw", portion, &raw) && raw == 0)
	bg_check(world_get_field(w, "Food.nourishment", portion, &nourishment) && nourishment == 50)

	/* cooked, it isn't cooked again */
	bg_check(perform(w, c, action_make("cook", cook, portion, stove), 0, &error) == nil)

	/* of the harvest in hand, a stack, one portion is cooked, into the free
	 * hand; the rest is still raw. With no hand free, the whole of it is. */
	g = proposal_group_group_with_phase(.System, "setup: the harvest in hand")
	harvest := proposal_group_create(g, "grain_harvest", "the harvest", held_by(cook, 1))
	another := proposal_group_create(g, "grain_harvest", "another harvest", in_(larder))
	committer_submit(c, g)
	committer_commit_boundary(c)
	harvest, another = proposal_group_id_for(g, harvest), proposal_group_id_for(g, another)
	error = ""
	bg_check(perform(w, c, action_make("cook", cook, harvest, stove), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1200 * 1000 + 1))
	bg_check(world_get_field(w, "Food.raw", harvest, &raw) && raw == 0)
	bg_check(world_get_field(w, "Stack.count", harvest, &count) && count == 2)
	g = proposal_group_group_with_phase(.System, "setup: the meals put by, another harvest in hand")
	proposal_group_move_to(g, whole(harvest), in_(larder))
	proposal_group_move_to(g, whole(another), held_by(cook, 1))
	committer_submit(c, g)
	committer_commit_boundary(c)
	harvest = another
	g = proposal_group_group_with_phase(.System, "setup: the meal put by")
	proposal_group_move_to(g, whole(portion), in_(larder))
	committer_submit(c, g)
	committer_commit_boundary(c)
	error = ""
	bg_check(perform(w, c, action_make("cook", cook, harvest, stove), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1200 * 1000 + 1))
	bg_check(world_get_field(w, "Food.raw", harvest, &raw) && raw == 1)
	bg_check(world_get_field(w, "Stack.count", harvest, &count) && count == 1)
	bg_check(world_entities_at(w, cook, .Held_By, raw_data(held[:]), 2) == 2)
	meal := held[0] if held[1] == harvest else held[1]
	bg_check(world_get_field(w, "Food.raw", meal, &raw) && raw == 0)
	bg_check(world_get_field(w, "Food.nourishment", meal, &nourishment) && nourishment == 50)
	bg_check(world_units_of(w, meal) == 1)
}


/* Rationing (content/cooking/'s short_of_food): hungry, a farmer with a
 * sack of sixty portions at home (fifteen kilograms) takes one to cook;
 * with two (a tile's harvest, half a kilogram), short of food, it makes
 * no meal on hunger alone. */
test_rationing :: proc() {
	bg_check(test_rationing_takes("grain_sack") == 59)
	bg_check(test_rationing_takes("grain_harvest") == 2)
}


/* What is left in the farmer's own stack of grain (a `blueprint`) two
 * minutes after it gets hungry, it knowing what its larder holds. */
@(private = "file")
test_rationing_takes :: proc(blueprint: cstring) -> i64 {
	why: string
	count: i64

	w := test_world(104)
	bg_check(world_set_terrain_map(w, "village_map", &why))
	c := test_committer(w)
	activities := activities_with_world(w, c)
	knowledge  := autorelease(knowledge_init_with_world(w))
	agency     := autorelease(agency_init_with_world(w, c, knowledge))
	s          := autorelease(scheduler_init_with_world(w, c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))
	knowledge_set_omniscient(knowledge, true)      /* it knows what is in the larder */

	g := proposal_group_group_with_phase(.System, "setup: my larder, my grain, my stove")
	me    := proposal_group_create(g, "farmer", "me", on_tile(20, 70, 0))
	mine  := proposal_group_create(g, "larder", "my larder", on_tile(21, 70, 0))
	grain := proposal_group_create(g, blueprint, "my grain", in_(mine))
	stove := proposal_group_create(g, "stove", "my stove", on_tile(20, 72, 0))
	for thing in ([]Entity_ID{mine, grain, stove}) {
		claim := proposal_group_create(g, "ownership", "mine", location_make_none())
		proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
		proposal_group_relate(g, .Claimant, whole(claim), whole(me))
		proposal_group_relate(g, .Claim_Subject, whole(claim), whole(thing))
	}
	proposal_group_set_of_to(g, "Hungry.satiety", whole(me), 30)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1000))
	me, grain = proposal_group_id_for(g, me), proposal_group_id_for(g, grain)
	bg_check(world_is_live(w, me) && world_is_live(w, grain))
	agency_control(agency, me)
	scheduler_run_until(s, time_make(120000))
	bg_check(world_get_field(w, "Stack.count", grain, &count))
	if blueprint == "grain_harvest" && !test_logged_by(agency, me, "at home -1): unthinkable") {
		fmt.printf("    %s: not rationing\n", blueprint)
		for line in agency_log_of(agency, me) do fmt.printf("      %s\n", line)
	}
	return count
}

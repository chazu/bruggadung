package lab

/*
 * Forgetting (KNOWLEDGE.md decision 19): a meal an agent eats, it sees end,
 * and forgets, and that it was its own with it. A bed carried off while it
 * was away is lost, not ended: kept, until its memory of it fades. And its
 * habits give way (AGENCY.md §8): with as many as it holds, a new one takes
 * the weakest's place.
 */

test_forgetting :: proc() {
	error: string

	w := test_world(106)
	why: string
	bg_check(world_set_terrain_map(w, "village_map", &why))
	c := test_committer(w)
	activities := activities_with_world(w, c)
	knowledge  := autorelease(knowledge_init_with_world(w))
	s          := autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	st := Stage{w, c, s}

	g := proposal_group_group_with_phase(.System, "setup: a farmer, its meal in hand, its bed")
	me   := proposal_group_create(g, "farmer", "me", on_tile(10, 70, 0))
	meal := proposal_group_create(g, "grain", "my meal", held_by(me, 0))
	bed  := proposal_group_create(g, "bed", "my bed", on_tile(11, 70, 0))
	proposal_group_set_of_to(g, "Food.raw", whole(meal), 0)
	for thing in ([]Entity_ID{meal, bed}) {
		claim := proposal_group_create(g, "ownership", "mine", location_make_none())
		proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
		proposal_group_relate(g, .Claimant, whole(claim), whole(me))
		proposal_group_relate(g, .Claim_Subject, whole(claim), whole(thing))
	}
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1000))
	me, meal, bed = proposal_group_id_for(g, me), proposal_group_id_for(g, meal), proposal_group_id_for(g, bed)
	store  := knowledge_store_of(knowledge, me)
	r_meal := test_referent_of(store, meal)
	r_bed  := test_referent_of(store, bed)
	bg_check(r_meal != 0 && r_bed != 0 && knowledge_store_finding(store, "#Owned", r_meal) != nil)

	/* eaten: it saw it end, and forgets it, and that it was its own */
	bg_check(perform(w, c, action_make("eat", me, meal, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 61000))
	bg_check(!world_is_live(w, meal))
	bg_check(knowledge_store_referent(store, r_meal) == nil)
	bg_check(knowledge_store_finding(store, "#Owned", r_meal) == nil)

	/* the bed carried off while it was away: lost, not ended, and kept */
	test_stage_move(&st, me, 39, 66)
	test_stage_move(&st, bed, 38, 90)
	test_stage_move(&st, me, 10, 70)
	r := knowledge_store_referent(store, r_bed)
	bg_check(r != nil && !r.present && !r.ended)

	/* a season on, its memory of it faded below belief: forgotten */
	scheduler_run_until(s, time_make(world_time(w).ms + 90 * BG_MEMORY_STEP))
	test_stage_move(&st, me, 10, 71)
	bg_check(knowledge_store_referent(store, r_bed) == nil)
}


/* Sixteen habits held, each practised a day after the last: a seventeenth
 * takes the place of the weakest, the oldest of equals. */
test_habits_give_way :: proc() {
	w := test_world(107)
	c := test_committer(w)
	knowledge := autorelease(knowledge_init_with_world(w))
	agency    := autorelease(agency_init_with_world(w, c, knowledge))
	s         := autorelease(scheduler_init_with_world(w, c))

	g := proposal_group_group_with_phase(.System, "setup: a farmer")
	me := proposal_group_create(g, "farmer", "me", on_tile(5, 5, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	me = proposal_group_id_for(g, me)
	agency_control(agency, me)
	m := agency_mind_of(agency, me)
	bg_check(m != nil)
	for k in 0 ..< 17 {
		scheduler_run_until(s, time_make(i64(k + 1) * 86400000))
		agency_practise(agency, m, "eat:eat_it.food", u32(100 + k))
	}
	/* the newest held at full strength; of those faded alike to nothing,
	 * the oldest, the first, gone, and the second still held */
	held :: proc(m: ^Motivation, choice: u32) -> bool {
		for k in 0 ..< m.nhabits do if m.habits[k].choice == choice do return true
		return false
	}
	bg_check(m.nhabits == BG_MAX_HABITS)
	bg_check(habit_strength(m, world_intern(w, "eat:eat_it.food"), 116, world_time(w).ms) == BG_HABIT_GAIN)
	bg_check(!held(m, 100) && held(m, 101) && held(m, 116))
}

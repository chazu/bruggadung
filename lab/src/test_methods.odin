package lab

import "core:fmt"

/*
 * Methods as whole ways (METHODS.md). Decision 5: a goal achieved beneath
 * the subgoals posted for it is dropped with them. A fitter holding a 22 mm
 * spanner, who has seen the 19 mm gland nut and a 19 mm spanner by it up
 * close, and has walked off, goes back for that spanner (tighten the nut:
 * find a spanner that fits). On its way, someone else tightens the nut in
 * its sight: it gives up the spanner, and doesn't pick it up.
 */
test_goal_done_beneath :: proc() {
	st: Stage

	st.w       = test_world(71)
	st.c       = test_committer(st.w)
	committer_set_tracing(st.c, false)
	activities := activities_with_world(st.w, st.c)
	knowledge  := autorelease(knowledge_init_with_world(st.w))
	agency     := autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g := proposal_group_group_with_phase(.System, "setup: a fitter by the nut, and a spanner that fits by it")
	worker  := proposal_group_create(g, "worker", "Oskar", on_tile(2, 2, 0))
	proposal_group_create(g, "spanner_22", "spanner", held_by(worker, 0))
	nut     := proposal_group_create(g, "gland_nut", "gland nut", on_tile(3, 2, 0))
	fitting := proposal_group_create(g, "spanner_19", "the spanner that fits", on_tile(2, 3, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker, nut, fitting = proposal_group_id_for(g, worker), proposal_group_id_for(g, nut), proposal_group_id_for(g, fitting)
	test_stage_move(&st, worker, 12, 2)

	bg_check(agency_commit(agency, worker, "tighten_nut"))
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 2000))
	under_way := test_logged_by(agency, worker, "find a spanner that fits first")

	/* tightened by someone else, in its sight */
	g = proposal_group_group_with_phase(.System, "setup: someone else tightens the nut")
	proposal_group_set_of_to(g, "Fastener.tight", whole(nut), 1)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 40000))

	held := false
	hands: [2]Entity_ID
	for e in hands[:world_entities_at(st.w, worker, .Held_By, raw_data(hands[:]), 2)] do if e == fitting do held = true
	ok := under_way && test_logged_by(agency, worker, "tighten the nut is done meanwhile: giving up find a spanner that fits") &&
	      !held
	if !ok do for line in agency_log_of(agency, worker) do fmt.printf("      %s\n", line)
	bg_check(ok)
}


/*
 * What keeps least is taken first (METHODS.md, "What the working market
 * showed"): a hungry farmer, plenty of grain in its own larder and a cut of
 * venison bought (no ownership claim of its own: it lies in its larder), cooks
 * the venison, which keeps three days, before the grain, which keeps.
 */
test_eats_what_keeps_least :: proc() {
	why: string
	count: i64

	w := test_world(104)
	bg_check(world_set_terrain_map(w, "village_map", &why))
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
	knowledge_set_omniscient(knowledge, true)      /* it knows what is in the larder */

	g := proposal_group_group_with_phase(.System, "setup: my larder, my grain, venison bought, my stove")
	me      := proposal_group_create(g, "farmer", "me", on_tile(20, 70, 0))
	mine    := proposal_group_create(g, "larder", "my larder", on_tile(21, 70, 0))
	grain   := proposal_group_create(g, "grain_sack", "my grain", in_(mine))
	venison := proposal_group_create(g, "venison", "venison bought", in_(mine))
	stove   := proposal_group_create(g, "stove", "my stove", on_tile(20, 72, 0))
	for thing in ([]Entity_ID{mine, grain, stove}) {
		claim := proposal_group_create(g, "ownership", "mine", location_make_none())
		proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
		proposal_group_relate(g, .Claimant, whole(claim), whole(me))
		proposal_group_relate(g, .Claim_Subject, whole(claim), whole(thing))
	}
	proposal_group_set_of_to(g, "Hungry.satiety", whole(me), 30)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1000))
	me, grain, venison = proposal_group_id_for(g, me), proposal_group_id_for(g, grain), proposal_group_id_for(g, venison)
	bg_check(world_get_field(w, "Stack.count", grain, &count))
	before := count
	agency_control(agency, me)
	scheduler_run_until(s, time_make(120000))
	bg_check(world_get_field(w, "Stack.count", grain, &count))
	/* the venison taken out (cooked, or eaten), the grain untouched */
	ok := count == before && (!world_is_live(w, venison) || world_location_of(w, venison).form != .In)
	if !ok do for line in agency_log_of(agency, me) do fmt.printf("      %s\n", line)
	bg_check(ok)
}

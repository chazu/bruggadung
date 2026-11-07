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

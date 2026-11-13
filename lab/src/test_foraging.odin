package lab

import "core:fmt"

/*
 * Foraging (VILLAGE.md decision 12, content/foraging/): a farmer short of
 * food (two portions at home: rationing makes no meal on hunger) forages
 * the bramble beside it at the woods' edge, and eats the berries; the
 * bramble grows the handful back the next day. At night it doesn't forage.
 * With a sack at home, it cooks instead, and leaves the bramble be.
 */
test_foraging :: proc() {
	{
		w, agency, me, bramble, s := test_foraging_run("grain_harvest")
		patch := (^Patch)(world_record(w, world_kind_named(w, "Patch"), bramble))
		ok := test_logged_by(agency, me, "forage: forage R") && test_logged_by(agency, me, ": eat R") &&
		      patch != nil && patch.handfuls == 2
		if !ok do for line in agency_log_of(agency, me) do fmt.printf("      %s\n", line)
		bg_check(ok)
		/* a day on, grown back */
		scheduler_run_until(s, time_make(86400000 + 10 * 3600000))
		patch = (^Patch)(world_record(w, world_kind_named(w, "Patch"), bramble))
		bg_check(patch != nil && patch.handfuls >= 2)
	}
	/* at 02:00, short and hungry, it doesn't forage in the dark */
	{
		w, agency, me, bramble, _ := test_foraging_run("grain_harvest", 2)
		patch := (^Patch)(world_record(w, world_kind_named(w, "Patch"), bramble))
		ok := !test_logged_by(agency, me, "forage: forage R") && test_logged_by(agency, me, "night -1") && patch != nil &&
		      patch.handfuls == 3
		if !ok do for line in agency_log_of(agency, me) do fmt.printf("      %s\n", line)
		bg_check(ok)
	}
	{
		w, agency, me, bramble, _ := test_foraging_run("grain_sack")
		patch := (^Patch)(world_record(w, world_kind_named(w, "Patch"), bramble))
		ok := !test_logged_by(agency, me, "forage: forage R") && patch != nil && patch.handfuls == 3
		if !ok do for line in agency_log_of(agency, me) do fmt.printf("      %s\n", line)
		bg_check(ok)
	}
}


/* The farmer at the woods' edge, hungry, with `grain` in its own larder,
 * for an hour from `hour` o'clock. */
@(private = "file")
test_foraging_run :: proc(grain: cstring, hour: i64 = 8) -> (^World, ^Agency, Entity_ID, Entity_ID, ^Scheduler) {
	why: string

	w := test_world(104)
	bg_check(world_set_terrain_map(w, "village_map", &why))
	c := test_committer(w)
	activities := activities_with_world(w, c)
	knowledge  := autorelease(knowledge_init_with_world(w))
	agency     := autorelease(agency_init_with_world(w, c, knowledge))
	foraging   := autorelease(progressions_init_with_world(w))
	s          := autorelease(scheduler_init_with_world(w, c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))
	scheduler_add_domain(s, progressions_as_domain(foraging))
	knowledge_set_omniscient(knowledge, true)      /* it knows what is in its larder */

	g := proposal_group_group_with_phase(.System, "setup: a farmer at the woods' edge")
	me      := proposal_group_create(g, "farmer", "me", on_tile(45, 25, 0))
	larder  := proposal_group_create(g, "larder", "my larder", on_tile(47, 26, 0))
	food    := proposal_group_create(g, grain, "my grain", in_(larder))
	stove   := proposal_group_create(g, "stove", "my stove", on_tile(44, 27, 0))
	bramble := proposal_group_create(g, "bramble", "a bramble", on_tile(45, 22, 0))
	for thing in ([]Entity_ID{larder, food, stove}) {
		claim := proposal_group_create(g, "ownership", "mine", location_make_none())
		proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
		proposal_group_relate(g, .Claimant, whole(claim), whole(me))
		proposal_group_relate(g, .Claim_Subject, whole(claim), whole(thing))
	}
	proposal_group_set_of_to(g, "Hungry.satiety", whole(me), 30)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1000))
	me, bramble = proposal_group_id_for(g, me), proposal_group_id_for(g, bramble)
	bg_check(world_is_live(w, me) && world_is_live(w, bramble))
	scheduler_run_until(s, time_make(hour * 3600000))
	agency_control(agency, me)
	scheduler_run_until(s, time_make((hour + 1) * 3600000))
	return w, agency, me, bramble, s
}

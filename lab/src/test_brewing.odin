package lab

/*
 * Brewing (content/brewing/): a portion of grain mashed at a lit stove is
 * wort, as heavy; wort in a vat is ale five days on, where it lies; left
 * out, it sours in two. One who keeps the `brewing` routine, bound to its
 * own vat, stove and larder, mashes a portion of its grain of an evening,
 * sets it to work, and puts the ale by when it sees it.
 */

import "core:fmt"

@(private = "file")
BREW_DAY :: i64(86400000)

/* The things in a container whose blueprint is the one named. */
@(private = "file")
brewing_inside :: proc(w: ^World, container: Entity_ID, blueprint: string) -> []Entity_ID {
	inside: [64]Entity_ID

	found := make([dynamic]Entity_ID, context.temp_allocator)
	for e in inside[:min(world_entities_at(w, container, .In, raw_data(inside[:]), len(inside)), len(inside))] {
		if info := world_info(w, e); info != nil && string(info.blueprint) == blueprint do append(&found, e)
	}
	return found[:]
}


test_brewing :: proc() {
	error: string
	held: [2]Entity_ID

	w := test_world(141)
	c := test_committer(w)
	activities := activities_with_world(w, c)
	s          := autorelease(scheduler_init_with_world(w, c))
	perishing  := autorelease(perishing_init_with_world(w))
	scheduler_add_domain(s, perishing_as_domain(perishing))
	scheduler_set_activities(s, activities_as_activity_clock(activities))

	g := proposal_group_group_with_phase(.System, "setup: a brewer with a portion of grain, a stove, a vat; wort on the ground")
	brewer := proposal_group_create(g, "farmhand", "the brewer", on_tile(5, 5, 0))
	stove  := proposal_group_create(g, "stove", "the stove", on_tile(6, 5, 0))
	vat    := proposal_group_create(g, "vat", "the vat", on_tile(5, 6, 0))
	grain  := proposal_group_create(g, "grain", "a portion of grain", held_by(brewer, 0))
	left   := proposal_group_create(g, "wort", "wort left out", on_tile(4, 5, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	brewer, stove, vat = proposal_group_id_for(g, brewer), proposal_group_id_for(g, stove), proposal_group_id_for(g, vat)
	grain, left = proposal_group_id_for(g, grain), proposal_group_id_for(g, left)

	/* at a cold stove, nothing is mashed */
	bg_check(perform(w, c, action_make("mash", brewer, grain, stove), 0, &error) == nil)
	bg_check(perform(w, c, action_make("light", brewer, stove, NO_ENTITY), 0, &error) != nil)
	world_set_boundary(w, world_boundary(w) + 1)
	committer_commit_boundary(c)
	error = ""

	/* mashed: wort in hand, as heavy as the grain was, the grain gone */
	bg_check(perform(w, c, action_make("mash", brewer, grain, stove), 0, &error) != nil)
	scheduler_run_until(s, time_make(1300 * 1000))
	bg_check(!world_is_live(w, grain))
	if world_is_live(w, grain) do for line in committer_trace(c) do fmt.printf("    %s\n", line)
	n := world_entities_at(w, brewer, .Held_By, raw_data(held[:]), 2)
	bg_check(n == 1)
	if n != 1 {
		if error != "" do fmt.printf("    %s\n", error)
		return
	}
	wort := held[0]
	bg_check(string(world_info(w, wort).blueprint) == "wort" && world_mass_of(w, wort) == 250)

	/* set to work: in the vat, ale five days on, a measure, as heavy; not
	 * before. Wort left out has soured by then */
	bg_check(perform(w, c, action_make("put_in", brewer, wort, vat), 0, &error) != nil)
	scheduler_run_until(s, time_make(1400 * 1000))
	set := world_time(w).ms
	bg_check(world_location_of(w, wort).form == .In && world_location_of(w, wort).place == vat)
	scheduler_run_until(s, time_make(set + 5 * BREW_DAY - 3600 * 1000))
	bg_check(world_is_live(w, wort) && len(brewing_inside(w, vat, "ale")) == 0)
	bg_check(!world_is_live(w, left))
	scheduler_run_until(s, time_make(set + 5 * BREW_DAY))
	ale := brewing_inside(w, vat, "ale")
	bg_check(!world_is_live(w, wort) && len(ale) == 1)
	if len(ale) == 1 do bg_check(world_units_of(w, ale[0]) == 1 && world_mass_of(w, ale[0]) == 250)
	if error != "" do fmt.printf("    %s\n", error)
}


/* A brewer with a sack of grain in its larder, a stove with wood in it and
 * a vat, all its own, keeping the brewing routine: the first evening a
 * portion is mashed and set to work; a week on, ale is put by in the
 * larder, and another brew is on. */
test_brewing_routine :: proc() {
	w := test_world(142)
	why: string
	bg_check(world_set_terrain_map(w, "farm_map", &why))
	c := test_committer(w)
	committer_set_tracing(c, false)
	activities := activities_with_world(w, c)
	knowledge  := autorelease(knowledge_init_with_world(w))
	agency     := autorelease(agency_init_with_world(w, c, knowledge))
	perishing  := autorelease(perishing_init_with_world(w))
	s          := autorelease(scheduler_init_with_world(w, c))
	agency_set_activities(agency, activities)
	scheduler_add_domain(s, perishing_as_domain(perishing))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))

	g := proposal_group_group_with_phase(.System, "setup: a brewer, its larder with a sack of grain, its stove, its vat")
	me     := proposal_group_create(g, "farmhand", "the brewer", on_tile(17, 2, 0))
	larder := proposal_group_create(g, "larder", "its larder", on_tile(18, 1, 0))
	stove  := proposal_group_create(g, "stove", "its stove", on_tile(16, 1, 0))
	vat    := proposal_group_create(g, "vat", "its vat", on_tile(16, 3, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	me, larder, stove, vat = proposal_group_id_for(g, me), proposal_group_id_for(g, larder), proposal_group_id_for(g, stove), proposal_group_id_for(g, vat)
	for thing in ([]Entity_ID{larder, stove, vat}) do test_own(c, me, thing)
	g = proposal_group_group_with_phase(.System, "setup: the grain")
	sack := proposal_group_create(g, "grain_sack", "a sack of grain", in_(larder))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(2))
	sack = proposal_group_id_for(g, sack)
	test_own(c, me, sack)
	scheduler_run_until(s, time_make(3))
	error: string
	bg_check(perform(w, c, action_make("look_in", me, larder, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(5000))

	reason := agency_take_on_routine(agency, me, "brewing")
	if reason != "" do fmt.printf("    %s\n", reason)
	bg_check(reason == "")

	/* the first evening: a portion mashed, and wort in the vat */
	scheduler_run_until(s, time_make(BREW_DAY))
	on := len(brewing_inside(w, vat, "wort"))
	if on != 1 || world_units_of(w, sack) != 59 {
		fmt.printf("    %d wort in the vat, %d portions in the sack\n", on, world_units_of(w, sack))
		for line in agency_log_of(agency, me) do fmt.printf("    %s\n", line)
	}
	bg_check(on == 1 && world_units_of(w, sack) == 59)

	/* a week on: the ale seen, drawn and put by, and a brew on again */
	scheduler_run_until(s, time_make(7 * BREW_DAY))
	by, again := brewing_inside(w, larder, "ale"), len(brewing_inside(w, vat, "wort"))
	if len(by) != 1 || again != 1 {
		fmt.printf("    %d stacks of ale put by, %d wort in the vat, %d ale in it\n", len(by), again, len(brewing_inside(w, vat, "ale")))
		for line in agency_log_of(agency, me) do fmt.printf("    %s\n", line)
	}
	bg_check(len(by) == 1 && again == 1)
	held: [2]Entity_ID
	bg_check(world_entities_at(w, me, .Held_By, raw_data(held[:]), 2) == 0)
}

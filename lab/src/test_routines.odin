package lab

import "core:fmt"
import "core:strings"

/*
 * Routines (content/agency.tri's #Routine, content/village/routines.tri):
 * taken on, each goal a routine keeps is a commitment over its hours,
 * recurring, its slots bound to the agent's own of the kind the routine
 * says, as the agent knows it; one that says no kind, to what is given,
 * or left unbound. With nothing of its own of a kind, the routine isn't
 * taken on, and the reason says what is missing.
 */
test_routines :: proc() {
	HOUR :: i64(3600000)

	w := test_world(131)
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

	g := proposal_group_group_with_phase(.System, "setup: a farmer, a bed and a stove beside it, and a neighbour's bed")
	me     := proposal_group_create(g, "farmhand", "the farmer", on_tile(10, 2, 0))
	other  := proposal_group_create(g, "bed", "a neighbour's bed", on_tile(9, 2, 0))
	bed    := proposal_group_create(g, "bed", "its bed", on_tile(11, 2, 0))
	stove  := proposal_group_create(g, "stove", "the stove", on_tile(12, 2, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	me, other, bed, stove = proposal_group_id_for(g, me), proposal_group_id_for(g, other), proposal_group_id_for(g, bed), proposal_group_id_for(g, stove)
	test_own(c, me, bed)
	scheduler_run_until(s, time_make(1000))
	agency_control(agency, me)
	known :: proc(knowledge: ^Knowledge, me: Entity_ID, truth: Entity_ID) -> u32 {
		store := knowledge_store_of(knowledge, me)
		for i: uint = 0; i < knowledge_store_count(store); i += 1 {
			if r := knowledge_store_referent_at(store, i); r.truth == truth do return r.id
		}
		return 0
	}
	bg_check(known(knowledge, me, bed) != 0 && known(knowledge, me, stove) != 0 && known(knowledge, me, other) != 0)
	said :: proc(agency: ^Agency, line: string) -> bool {
		for l in agency_saved_state(agency) do if strings.contains(l, line) do return true
		return false
	}

	/* no stove of its own: not taken on, and why */
	reason := agency_take_on_routine(agency, me, "nights")
	bg_check(strings.contains(reason, "#Stove") && strings.contains(reason, "stove_stoked"))
	bg_check(!said(agency, "sleep_in_bed"))
	bg_check(agency_take_on_routine(agency, me, "no_such_routine") != "")

	/* the stove its own: its nights, each bound to its own, not the
	 * neighbour's bed, every day */
	test_own(c, me, stove)
	scheduler_run_until(s, time_make(2000))
	reason = agency_take_on_routine(agency, me, "nights")
	if reason != "" do fmt.printf("    %s\n", reason)
	bg_check(reason == "")
	bg_check(said(agency, fmt.tprintf("commitment %d stove_stoked %d %d home 0 1 stove %d", me, 19 * HOUR, 21 * HOUR, known(knowledge, me, stove))))
	bg_check(said(agency, fmt.tprintf("commitment %d sleep_in_bed %d %d home 0 1 bed %d", me, 22 * HOUR, 30 * HOUR, known(knowledge, me, bed))))
	bg_check(said(agency, fmt.tprintf("commitment %d eat_supper %d %d home 0 0", me, 18 * HOUR, 21 * HOUR)))
	bg_check(said(agency, fmt.tprintf("recurs %d 0 %d", me, 24 * HOUR)))

	/* a slot that says no kind: what is given, or left unbound; a market
	 * day's, every fourth day from the third */
	reason = agency_take_on_routine(agency, me, "going_to_market", {{"worksite", known(knowledge, me, other)}})
	bg_check(reason == "" && said(agency, fmt.tprintf("commitment %d pack_carried %d %d market 0 0", me, 48 * HOUR + 9 * HOUR + HOUR / 2, 48 * HOUR + 10 * HOUR)))
	bg_check(said(agency, fmt.tprintf("recurs %d 3 %d", me, 96 * HOUR)))
}

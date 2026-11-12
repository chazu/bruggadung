package lab

/*
 * Leatherwork (content/leatherwork/): leather in hand is sewn into what
 * its blueprint says, so many pieces of it used up; one who makes its
 * household's pouch takes the leather from where it is kept, sews it, and
 * puts the pouch by in the coffer.
 */

import "core:fmt"
import "core:strings"

@(private = "file")
HOUR :: i64(3600000)

/* The things in a container whose blueprint is the one named. */
@(private = "file")
leatherwork_inside :: proc(w: ^World, container: Entity_ID, blueprint: string) -> []Entity_ID {
	inside: [64]Entity_ID

	found := make([dynamic]Entity_ID, context.temp_allocator)
	for e in inside[:min(world_entities_at(w, container, .In, raw_data(inside[:]), len(inside)), len(inside))] {
		if info := world_info(w, e); info != nil && string(info.blueprint) == blueprint do append(&found, e)
	}
	return found[:]
}


test_leatherwork :: proc() {
	error: string
	held: [2]Entity_ID

	w := test_world(133)
	c := test_committer(w)
	activities := activities_with_world(w, c)
	s          := autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))

	g := proposal_group_group_with_phase(.System, "setup: two with leather in hand")
	one   := proposal_group_create(g, "farmhand", "one", on_tile(5, 5, 0))
	other := proposal_group_create(g, "farmhand", "another", on_tile(8, 5, 0))
	deer  := proposal_group_create(g, "deer_leather", "deer leather", held_by(one, 0))
	hare  := proposal_group_create(g, "hare_leather", "hare leather", held_by(other, 0))
	proposal_group_merge(g, whole(proposal_group_create(g, "deer_leather", "deer leather", held_by(one, 0))), whole(deer))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	one, other, deer, hare = proposal_group_id_for(g, one), proposal_group_id_for(g, other), proposal_group_id_for(g, deer),
	                         proposal_group_id_for(g, hare)

	/* a piece of deer leather, of two, is a backpack in the free hand; the
	 * other piece still held */
	bg_check(perform(w, c, action_make("sew", one, deer, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(2 * HOUR + 1000))
	bg_check(world_is_live(w, deer) && world_units_of(w, deer) == 1 && world_mass_of(w, deer) == 4000)
	bg_check(world_entities_at(w, one, .Held_By, raw_data(held[:]), 2) == 2)
	made := held[0] if held[0] != deer else held[1]
	bg_check(world_info(w, made) != nil && world_info(w, made).blueprint == "backpack" && world_mass_of(w, made) == 1000)

	/* a pouch takes two pieces of hare leather: of one, nothing is sewn */
	g = proposal_group_group_with_phase(.Action, "test: a pouch of one piece")
	reason := apply_declared_effect(w, action_make("sew", other, hare, NO_ENTITY), 0, 0, g)
	bg_check(strings.contains(reason, "too little"))
	/* of two, a pouch, and no leather left */
	g = proposal_group_group_with_phase(.System, "test: another piece with it")
	proposal_group_merge(g, whole(proposal_group_create(g, "hare_leather", "hare leather", held_by(other, 0))), whole(hare))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	bg_check(world_units_of(w, hare) == 2)
	bg_check(perform(w, c, action_make("sew", other, hare, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 2 * HOUR + 1000))
	bg_check(!world_is_live(w, hare))
	bg_check(world_entities_at(w, other, .Held_By, raw_data(held[:]), 2) == 1)
	bg_check(world_info(w, held[0]) != nil && world_info(w, held[0]).blueprint == "pouch")
	if error != "" do fmt.printf("    %s\n", error)
}


/* One who makes its household's pouch: two pieces of hare leather in its
 * larder, of which it knows; that evening they are a pouch in its coffer,
 * and the next it does nothing more, though there is leather again. */
test_making_a_pouch :: proc() {
	DAY :: 24 * HOUR
	error: string

	w := test_world(134)
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

	g := proposal_group_group_with_phase(.System, "setup: one at home, its larder with leather, its coffer")
	me     := proposal_group_create(g, "farmhand", "the maker", on_tile(17, 2, 0))
	larder := proposal_group_create(g, "larder", "its larder", on_tile(18, 1, 0))
	coffer := proposal_group_create(g, "coffer", "its coffer", on_tile(16, 1, 0))
	hare   := proposal_group_create(g, "hare_leather", "hare leather", in_(larder))
	proposal_group_merge(g, whole(proposal_group_create(g, "hare_leather", "hare leather", in_(larder))), whole(hare))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	me, larder, coffer = proposal_group_id_for(g, me), proposal_group_id_for(g, larder), proposal_group_id_for(g, coffer)
	test_own(c, me, larder)
	test_own(c, me, coffer)
	scheduler_run_until(s, time_make(2))
	bg_check(perform(w, c, action_make("look_in", me, larder, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(5000))
	store := knowledge_store_of(knowledge, me)
	kept, chest := u32(0), u32(0)
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if r.truth == larder do kept = r.id
		if r.truth == coffer do chest = r.id
	}
	bg_check(kept != 0 && chest != 0)
	bg_check(agency_undertake_every_with(agency, me, "pouch_made", 16 * HOUR, 19 * HOUR, "home", DAY, {{"store", kept}, {"coffer", chest}}))

	scheduler_run_until(s, time_make(DAY))
	pouches := leatherwork_inside(w, coffer, "pouch")
	if len(pouches) != 1 {
		fmt.printf("    %d pouches in the coffer\n", len(pouches))
		for line in agency_log_of(agency, me) do fmt.printf("    %s\n", line)
	}
	bg_check(len(pouches) == 1 && len(leatherwork_inside(w, larder, "hare_leather")) == 0)

	/* leather again, and a pouch in the coffer: none is made of it */
	g = proposal_group_group_with_phase(.System, "setup: two pieces more")
	more := proposal_group_create(g, "hare_leather", "hare leather", in_(larder))
	proposal_group_merge(g, whole(proposal_group_create(g, "hare_leather", "hare leather", in_(larder))), whole(more))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(DAY + 1000))
	more = proposal_group_id_for(g, more)
	bg_check(perform(w, c, action_make("look_in", me, larder, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(2 * DAY))
	bg_check(len(leatherwork_inside(w, coffer, "pouch")) == 1 && world_is_live(w, more) && world_units_of(w, more) == 2)
}

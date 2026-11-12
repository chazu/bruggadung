package lab

/*
 * Tanning (content/tanning/): a hide laid in a tan pit is the pit's
 * owners', and six days in it is leather, as heavy, where it lies; out of
 * the pit it is a raw hide, and rots in five; one
 * who dresses its household's hides takes them from where they are kept,
 * lays them in the tan, and puts the leather by.
 */

import "core:fmt"
import "core:slice"

@(private = "file")
TAN_DAY :: i64(86400000)

/* The things in a container whose blueprint is the one named. */
@(private = "file")
tanning_inside :: proc(w: ^World, container: Entity_ID, blueprint: string) -> []Entity_ID {
	inside: [64]Entity_ID

	found := make([dynamic]Entity_ID, context.temp_allocator)
	for e in inside[:min(world_entities_at(w, container, .In, raw_data(inside[:]), len(inside)), len(inside))] {
		if info := world_info(w, e); info != nil && string(info.blueprint) == blueprint do append(&found, e)
	}
	return found[:]
}


test_tanning :: proc() {
	error: string
	at: i64

	w := test_world(131)
	c := test_committer(w)
	activities := activities_with_world(w, c)
	s          := autorelease(scheduler_init_with_world(w, c))
	perishing  := autorelease(perishing_init_with_world(w))
	scheduler_add_domain(s, perishing_as_domain(perishing))
	scheduler_set_activities(s, activities_as_activity_clock(activities))

	g := proposal_group_group_with_phase(.System, "setup: a tanner with a hide, a pit, a chest; another by, with a pelt")
	tanner := proposal_group_create(g, "farmhand", "the tanner", on_tile(5, 5, 0))
	other  := proposal_group_create(g, "farmhand", "another", on_tile(5, 4, 0))
	pit    := proposal_group_create(g, "tan_pit", "the pit", on_tile(6, 5, 0))
	chest  := proposal_group_create(g, "larder", "the chest", on_tile(5, 6, 0))
	hide   := proposal_group_create(g, "deer_hide", "a hide", held_by(tanner, 0))
	second := proposal_group_create(g, "deer_hide", "a second hide", on_tile(4, 5, 0))
	pelt   := proposal_group_create(g, "hare_pelt", "a pelt", held_by(other, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	tanner, other, pit, chest = proposal_group_id_for(g, tanner), proposal_group_id_for(g, other), proposal_group_id_for(g, pit),
	                            proposal_group_id_for(g, chest)
	hide, second, pelt = proposal_group_id_for(g, hide), proposal_group_id_for(g, second), proposal_group_id_for(g, pelt)
	test_own(c, tanner, pit)
	test_own(c, tanner, chest)
	test_own(c, tanner, hide)
	scheduler_run_until(s, time_make(2))

	/* a raw hide rots in five days, from when it was made */
	scheduler_run_until(s, time_make(TAN_DAY))
	bg_check(world_is_live(w, hide) && world_get_field(w, "Becoming.becomesAt", hide, &at) && at > 0 && at <= 5 * TAN_DAY + 2)

	/* laid in the tan: in the pit, the pit's owner's, its time six days
	 * from then, and what it becomes there leather */
	bg_check(perform(w, c, action_make("steep", tanner, hide, pit), 0, &error) != nil)
	scheduler_run_until(s, time_make(TAN_DAY + 601 * 1000))
	laid := world_time(w).ms
	bg_check(world_location_of(w, hide).form == .In && world_location_of(w, hide).place == pit)
	bg_check(world_get_field(w, "Becoming.becomesAt", hide, &at) && at > TAN_DAY + 6 * TAN_DAY && at <= laid + 6 * TAN_DAY)
	bg_check(slice.equal(owners_of(w, hide), []Entity_ID{tanner}))
	/* another's pelt, laid in it by them, is the pit's owner's too */
	bg_check(perform(w, c, action_make("steep", other, pelt, pit), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 601 * 1000))
	bg_check(world_location_of(w, pelt).place == pit && slice.equal(owners_of(w, pelt), []Entity_ID{tanner}))

	/* five days on, past when it would have rotted raw, a hide still; and
	 * the one left raw on the ground has rotted */
	scheduler_run_until(s, time_make(laid + 5 * TAN_DAY))
	bg_check(world_is_live(w, hide) && len(tanning_inside(w, pit, "deer_leather")) == 0)
	bg_check(!world_is_live(w, second))
	/* taken out early, it is a raw hide again: its time five days from
	 * then, to rot */
	tanned := at
	bg_check(perform(w, c, action_make("take", tanner, hide, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 10 * 1000))
	bg_check(world_location_of(w, hide).place == tanner)
	bg_check(world_get_field(w, "Becoming.becomesAt", hide, &at) && at > tanned + 3 * TAN_DAY && at <= world_time(w).ms + 5 * TAN_DAY)
	/* put back, by any move, its tanning starts over: six days from then */
	bg_check(perform(w, c, action_make("put_in", tanner, hide, pit), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 10 * 1000))
	bg_check(world_location_of(w, hide).place == pit)
	bg_check(world_get_field(w, "Becoming.becomesAt", hide, &at) && at > tanned + 4 * TAN_DAY && at <= world_time(w).ms + 6 * TAN_DAY)
	again := at

	/* the pelt, left in, is leather at its time; the hide not yet */
	scheduler_run_until(s, time_make(tanned + TAN_DAY))
	bg_check(len(tanning_inside(w, pit, "hare_leather")) == 1 && !world_is_live(w, pelt))
	bg_check(world_is_live(w, hide))
	/* at its time, leather: a piece, as heavy, in the pit; the hide gone */
	scheduler_run_until(s, time_make(again - 1))
	bg_check(world_is_live(w, hide))
	scheduler_run_until(s, time_make(again))
	bg_check(!world_is_live(w, hide))
	leather := tanning_inside(w, pit, "deer_leather")
	bg_check(len(leather) == 1 && world_units_of(w, leather[0]) == 1 && world_mass_of(w, leather[0]) == 4000)
	if len(leather) != 1 do return

	/* drawn out and put by; a second piece put with it is one stack */
	bg_check(perform(w, c, action_make("take", tanner, leather[0], NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 10 * 1000))
	bg_check(perform(w, c, action_make("put_in", tanner, leather[0], chest), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 10 * 1000))
	bg_check(world_location_of(w, leather[0]).place == chest)
	third := test_commit_create(c, "deer_hide", held_by(tanner, 0))
	bg_check(perform(w, c, action_make("steep", tanner, third, pit), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 7 * TAN_DAY))
	more := tanning_inside(w, pit, "deer_leather")
	bg_check(len(more) == 1)
	if len(more) != 1 do return
	bg_check(perform(w, c, action_make("take", tanner, more[0], NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 10 * 1000))
	bg_check(perform(w, c, action_make("put_in", tanner, more[0], chest), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 10 * 1000))
	bg_check(world_units_of(w, leather[0]) == 2 && world_mass_of(w, leather[0]) == 8000 && !world_is_live(w, more[0]))
	if error != "" do fmt.printf("    %s\n", error)
}


/* A tanner who dresses its household's hides: three in its larder, of
 * which it knows; nine evenings on, they are leather, put by there. */
test_dressing_hides :: proc() {
	w := test_world(132)
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

	g := proposal_group_group_with_phase(.System, "setup: a tanner, its larder with three hides, its pit")
	me     := proposal_group_create(g, "farmhand", "the tanner", on_tile(17, 2, 0))
	larder := proposal_group_create(g, "larder", "its larder", on_tile(18, 1, 0))
	pit    := proposal_group_create(g, "tan_pit", "its pit", on_tile(16, 1, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	me, larder, pit = proposal_group_id_for(g, me), proposal_group_id_for(g, larder), proposal_group_id_for(g, pit)
	test_own(c, me, larder)
	test_own(c, me, pit)
	g = proposal_group_group_with_phase(.System, "setup: the hides")
	for blueprint in ([3]cstring{"deer_hide", "deer_hide", "hare_pelt"}) {
		test_own_in(g, me, proposal_group_create(g, blueprint, "a hide", in_(larder)))
	}
	committer_submit(c, g)
	scheduler_run_until(s, time_make(2))
	error: string
	bg_check(perform(w, c, action_make("look_in", me, larder, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(5000))
	store := knowledge_store_of(knowledge, me)
	known, kept := u32(0), u32(0)
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if r.truth == pit do known = r.id
		if r.truth == larder do kept = r.id
	}
	bg_check(known != 0 && kept != 0)
	knows := 0
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		if world_location_of(w, knowledge_store_referent_at(store, i).truth).place == larder do knows += 1
	}
	bg_check(knows == 3)
	bg_check(agency_undertake_every_with(agency, me, "pit_seen_to", 16 * 3600 * 1000, 18 * 3600 * 1000, "home", TAN_DAY,
	                                     {{"pit", known}}))
	bg_check(agency_undertake_every_with(agency, me, "hides_dressed", 16 * 3600 * 1000, 18 * 3600 * 1000, "home", TAN_DAY,
	                                     {{"pit", known}, {"store", kept}}))

	/* the first evening: all three in the tan */
	scheduler_run_until(s, time_make(TAN_DAY))
	laid := len(tanning_inside(w, pit, "deer_hide")) + len(tanning_inside(w, pit, "hare_pelt"))
	if laid != 3 {
		fmt.printf("    %d hides in the tan\n", laid)
		for line in agency_log_of(agency, me) do fmt.printf("    %s\n", line)
	}
	bg_check(laid == 3)

	/* a hide brought home since goes the same way; each evening it looks
	 * into the pit, and draws what it sees to be leather: nine days on, it
	 * is put by, two pieces of deer leather as one
	 * stack, and one of hare */
	g = proposal_group_group_with_phase(.System, "setup: another hide, six days on")
	scheduler_run_until(s, time_make(6 * TAN_DAY + 12 * 3600 * 1000))
	late := proposal_group_create(g, "hare_pelt", "a pelt", in_(larder))
	test_own_in(g, me, late)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(6 * TAN_DAY + 12 * 3600 * 1000 + 1))
	bg_check(perform(w, c, action_make("look_in", me, larder, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(9 * TAN_DAY))
	deer, hare := tanning_inside(w, larder, "deer_leather"), tanning_inside(w, larder, "hare_leather")
	if len(deer) != 1 || len(hare) != 1 {
		fmt.printf("    %d and %d stacks of leather put by\n", len(deer), len(hare))
		for i: uint = 0; i < knowledge_store_count(store); i += 1 {
			r := knowledge_store_referent_at(store, i)
			fmt.printf("    R%d (truth %d, present %v): %s\n", r.id, r.truth, r.present, knowledge_store_describe_referent(store, r.id))
		}
		for e in tanning_inside(w, pit, "deer_leather") do fmt.printf("    in the pit: deer leather %d\n", e)
		for e in tanning_inside(w, pit, "hare_leather") do fmt.printf("    in the pit: hare leather %d\n", e)
		for line in agency_log_of(agency, me) do fmt.printf("    %s\n", line)
	}
	bg_check(len(deer) == 1 && len(hare) == 1)
	if len(deer) == 1 && len(hare) == 1 do bg_check(world_units_of(w, deer[0]) == 2 && world_units_of(w, hare[0]) == 1)
	bg_check(len(tanning_inside(w, pit, "hare_pelt")) == 1 && len(tanning_inside(w, pit, "deer_leather")) == 0)
	held: [2]Entity_ID
	bg_check(world_entities_at(w, me, .Held_By, raw_data(held[:]), 2) == 0)
}


/* An ownership claim of `owner`'s on a thing made in the same group. */
@(private = "file")
test_own_in :: proc(g: ^Proposal_Group, owner: Entity_ID, thing: Entity_ID) {
	claim := proposal_group_create(g, "ownership", "its own", location_make_none())
	proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
	proposal_group_relate(g, .Claimant, whole(claim), whole(owner))
	proposal_group_relate(g, .Claim_Subject, whole(claim), whole(thing))
}

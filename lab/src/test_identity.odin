package lab

/*
 * Identity from context (KNOWLEDGE.md decision 18): a thing can't be in two
 * places. A bed just like one the agent left behind, seen elsewhere, is
 * another bed while the first is believed where it was; once the agent has
 * seen that place empty, a bed like it elsewhere is the first, moved. A
 * person goes about by itself: seen elsewhere, it is the same person.
 */

test_identity_from_context :: proc() {
	w := test_world(102)
	why: string
	bg_check(world_set_terrain_map(w, "village_map", &why))
	c := test_committer(w)
	knowledge := autorelease(knowledge_init_with_world(w))
	s := autorelease(scheduler_init_with_world(w, c))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	st := Stage{w, c, s}

	g := proposal_group_group_with_phase(.System, "setup: two beds, far apart, and a neighbour")
	me    := proposal_group_create(g, "farmer", "me", on_tile(10, 70, 0))
	mine  := proposal_group_create(g, "bed", "my bed", on_tile(11, 70, 0))
	other := proposal_group_create(g, "bed", "a bed like it", on_tile(40, 70, 0))
	who   := proposal_group_create(g, "hunter", "a neighbour", on_tile(12, 70, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1000))
	me, mine, other, who = proposal_group_id_for(g, me), proposal_group_id_for(g, mine), proposal_group_id_for(g, other),
	                       proposal_group_id_for(g, who)
	store := knowledge_store_of(knowledge, me)
	r_mine := test_referent_of(store, mine)
	r_who  := test_referent_of(store, who)
	bg_check(r_mine != 0 && r_who != 0)

	/* across the green, the neighbour gone on ahead: a bed like mine is
	 * another bed, mine still believed at home; the neighbour, seen there,
	 * is the neighbour */
	test_stage_move(&st, who, 41, 70)
	test_stage_move(&st, me, 39, 70)
	r_other := test_referent_of(store, other)
	bg_check(r_other != 0 && r_other != r_mine)
	bg_check(knowledge_store_referent(store, r_mine).present && knowledge_store_referent(store, r_mine).x == 11)
	bg_check(test_referent_of(store, who) == r_who && knowledge_store_referent(store, r_who).x == 41)

	/* home again, my bed is taken away under my eyes, out of sight of the
	 * green: I see its place empty. Across the green, a bed like it beside
	 * the other is mine, moved */
	test_stage_move(&st, me, 10, 70)
	test_stage_move(&st, mine, 38, 72)
	bg_check(!knowledge_store_referent(store, r_mine).present)
	test_stage_move(&st, me, 39, 71)
	bg_check(test_referent_of(store, mine) == r_mine && knowledge_store_referent(store, r_mine).present)
	bg_check(knowledge_store_referent(store, r_mine).x == 38 && knowledge_store_referent(store, r_mine).y == 72)
	bg_check(test_referent_of(store, other) == r_other)
}

package lab

/*
 * Identity from context (KNOWLEDGE.md decision 18): a thing can't be in two
 * places. A bed just like one the agent left behind, seen elsewhere, is
 * another bed while the first is believed where it was; once the agent has
 * seen that place empty, a bed like it elsewhere is the first, moved. A
 * person goes about by itself: seen elsewhere, it is the same person. A bed
 * moved while the agent wasn't looking is two to it until it finds the
 * first gone: then one like it, first seen since, is it. And what an agent
 * owns, it knows as its own, and takes from first.
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


/* Lost and found: a bed moved while its owner was away is seen first as
 * another; found gone from home, the one first seen since is it. */
test_identity_lost_and_found :: proc() {
	w := test_world(103)
	why: string
	bg_check(world_set_terrain_map(w, "village_map", &why))
	c := test_committer(w)
	knowledge := autorelease(knowledge_init_with_world(w))
	s := autorelease(scheduler_init_with_world(w, c))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	st := Stage{w, c, s}

	g := proposal_group_group_with_phase(.System, "setup: a bed, and its owner")
	me   := proposal_group_create(g, "farmer", "me", on_tile(10, 70, 0))
	mine := proposal_group_create(g, "bed", "my bed", on_tile(11, 70, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1000))
	me, mine = proposal_group_id_for(g, me), proposal_group_id_for(g, mine)
	store := knowledge_store_of(knowledge, me)
	r_mine := test_referent_of(store, mine)
	bg_check(r_mine != 0)

	/* away across the green, the bed carried off unseen and set down there */
	test_stage_move(&st, me, 39, 66)
	test_stage_move(&st, mine, 38, 72)
	test_stage_move(&st, me, 39, 71)
	found := u32(0)
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if r.truth == mine && r.id != r_mine do found = r.id
	}
	bg_check(found != 0 && knowledge_store_referent(store, r_mine).present)      /* another bed, mine at home */

	/* home: mine is gone, and the one across the green, first seen since,
	 * is it: one referent, the older, where that one was seen */
	test_stage_move(&st, me, 10, 70)
	bg_check(knowledge_store_referent(store, found) == nil)
	r := knowledge_store_referent(store, r_mine)
	bg_check(r != nil && r.present && r.x == 38 && r.y == 72)
}


/* Owning: a farmer knows its larder, sack and stove as its own, not its
 * neighbour's; hungry, it takes from its own sack, though the neighbour's
 * is nearer. */
test_identity_own :: proc() {
	w := test_world(104)
	why: string
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
	knowledge_set_omniscient(knowledge, true)      /* it knows what is in the larders */

	g := proposal_group_group_with_phase(.System, "setup: two larders, one mine")
	me      := proposal_group_create(g, "farmer", "me", on_tile(20, 70, 0))
	theirs  := proposal_group_create(g, "larder", "the neighbour's larder", on_tile(21, 70, 0))
	mine    := proposal_group_create(g, "larder", "my larder", on_tile(23, 70, 0))
	sack_t  := proposal_group_create(g, "grain_sack", "their grain", in_(theirs))
	sack_m  := proposal_group_create(g, "grain_sack", "my grain", in_(mine))
	stove   := proposal_group_create(g, "stove", "my stove", on_tile(20, 72, 0))
	for thing in ([]Entity_ID{mine, sack_m, stove}) {
		claim := proposal_group_create(g, "ownership", "mine", location_make_none())
		proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
		proposal_group_relate(g, .Claimant, whole(claim), whole(me))
		proposal_group_relate(g, .Claim_Subject, whole(claim), whole(thing))
	}
	proposal_group_set_of_to(g, "Hungry.satiety", whole(me), 30)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1000))
	me, theirs, mine = proposal_group_id_for(g, me), proposal_group_id_for(g, theirs), proposal_group_id_for(g, mine)
	sack_t, sack_m = proposal_group_id_for(g, sack_t), proposal_group_id_for(g, sack_m)
	store := knowledge_store_of(knowledge, me)

	/* its own it knows as its own; the neighbour's, not */
	self_ := knowledge_store_self_referent(store)
	owned := knowledge_store_finding(store, "#Owned", test_referent_of(store, mine))
	bg_check(owned != nil && owned.choice == self_)
	bg_check(knowledge_store_finding(store, "#Owned", test_referent_of(store, sack_m)) != nil)
	bg_check(knowledge_store_finding(store, "#Owned", test_referent_of(store, theirs)) == nil)

	/* hungry, it takes a portion from its own sack */
	agency_control(agency, me)
	scheduler_run_until(s, time_make(120000))
	count: i64
	bg_check(world_get_field(w, "Stack.count", sack_m, &count) && count == 59)
	bg_check(world_get_field(w, "Stack.count", sack_t, &count) && count == 60)
}

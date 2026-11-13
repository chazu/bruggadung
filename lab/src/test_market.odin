package lab

/*
 * The market (VILLAGE.md decision 9, slice 9; content/market/): a farmer
 * keeps a stall, setting out grain from its larder and posting its price;
 * a woodcutter, its larder short of grain, fetches its coins, reads the
 * price, and buys a lot at a time (it asks, the farmer hands the grain
 * over and says what is owed, it pays into the stall), taking each home,
 * until its larder holds enough. Coins and grain are conserved; the
 * farmer's stall holds what it was paid. After the market, the farmer
 * takes its takings home to its coffer, and the woodcutter puts back the
 * coins it didn't spend. With a pouch in its coffer (content/leatherwork/),
 * the woodcutter carries its purse in that, at its belt, and pays out of
 * it: no coins are in its hand, and the pouch goes back into the coffer
 * with what is left.
 */

import "core:fmt"
import "core:strings"


test_market :: proc() {
	test_market_run(115, false)
}


test_market_with_a_pouch :: proc() {
	test_market_run(135, true)
}


@(private = "file")
test_market_run :: proc(seed: u64, pouched: bool) {
	HOUR :: i64(3600 * 1000)

	w := test_world(seed)
	why: string
	bg_check(world_set_terrain_map(w, "woods_map", &why))
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

	g := proposal_group_group_with_phase(.System, "setup: a farmer by its stall and larder; a woodcutter by its own, and its coffer")
	stall    := proposal_group_create(g, "stall", "the stall", on_tile(12, 10, 0))
	board    := proposal_group_create(g, "price_board", "its board", on_tile(12, 10, 0))
	farmer   := proposal_group_create(g, "farmer", "the farmer", on_tile(11, 10, 0))
	flarder  := proposal_group_create(g, "larder", "the farmer's larder", on_tile(9, 10, 0))
	fgrain   := proposal_group_create(g, "grain_sack", "the farmer's grain", in_(flarder))
	fcoffer  := proposal_group_create(g, "coffer", "the farmer's coffer", on_tile(10, 11, 0))
	cutter   := proposal_group_create(g, "woodcutter", "the woodcutter", on_tile(15, 11, 0))
	clarder  := proposal_group_create(g, "larder", "the woodcutter's larder", on_tile(15, 12, 0))
	cgrain   := proposal_group_create(g, "grain_sack", "the woodcutter's grain", in_(clarder))
	coffer   := proposal_group_create(g, "coffer", "the coffer", on_tile(16, 12, 0))
	purse    := proposal_group_create(g, "coins_400", "the coins", in_(coffer))
	pouch    := proposal_group_create(g, "pouch", "the pouch", in_(coffer)) if pouched else NO_ENTITY
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	board = proposal_group_id_for(g, board)
	stall, farmer, flarder, cutter = proposal_group_id_for(g, stall), proposal_group_id_for(g, farmer), proposal_group_id_for(g, flarder), proposal_group_id_for(g, cutter)
	clarder, coffer, fcoffer = proposal_group_id_for(g, clarder), proposal_group_id_for(g, coffer), proposal_group_id_for(g, fcoffer)
	fgrain, cgrain, purse = proposal_group_id_for(g, fgrain), proposal_group_id_for(g, cgrain), proposal_group_id_for(g, purse)
	worn := proposal_group_id_for(g, pouch) if pouched else NO_ENTITY

	fstore := knowledge_store_of(knowledge, farmer)
	cstore := knowledge_store_of(knowledge, cutter)
	bg_check(agency_undertake_every_with(agency, farmer, "stall_kept", 0, 2 * HOUR, "market", 4 * 24 * HOUR,
	                                     {{"stall", test_market_referent(fstore, stall)}, {"board", test_market_referent(fstore, board)},
	                                      {"supply", test_market_referent(fstore, flarder)}}))
	bg_check(agency_undertake_every_with(agency, cutter, "grain_stocked", 0, 2 * HOUR, "market", 4 * 24 * HOUR,
	                                     {{"supply", test_market_referent(cstore, clarder)}, {"coffer", test_market_referent(cstore, coffer)}}))
	coins_before := test_market_count(w, "coin")
	grain_before := test_market_count(w, "grain")
	scheduler_run_until(s, time_make(HOUR))

	/* the stall: grain set out, its price posted on its board */
	written := world_text_field(w, "Record.writing", board)
	bg_check(written != nil && len(written) > 0)
	/* as the farmer wrote it, quotes and all: a #Writing with its author,
	 * one entry, the price of grain */
	{
		author: string
		entries, ok := writing_entries(written, &author)
		bg_check(ok && author != "" && len(entries) == 1 && strings.contains(string(written), "unit: \"grain\""))
		bg_check(test_happened(w, "wrote", farmer, board))
	}
	/* posting is the command's writing put on the board (declared,
	 * content/market/): saying nothing, or what is no writing, it fails */
	{
		trial := proposal_group_group_with_phase(.Action, "test: posting")
		post  := action_make("post", farmer, board, NO_ENTITY)
		bg_check(strings.contains(apply_declared_effect(w, post, 0, 0, trial), "post what?"))
		post.content = world_intern(w, "#Here & { what: #Body }")
		/* a posting is typed so (#Posting): the conflict is at what is said */
		bg_check(strings.contains(apply_declared_effect(w, post, 0, 0, trial), "conflict at said"))
		post.content = written
		bg_check(apply_declared_effect(w, post, 0, 0, trial) == "")
	}
	/* the woodcutter's larder: twenty kilograms of grain, or more; the
	 * stall holds what it was paid; nothing made or lost */
	inside: [8]Entity_ID
	stocked, paid: i64
	for e in inside[:world_entities_at(w, clarder, .In, raw_data(inside[:]), len(inside))] {
		if u := world_unit_of(w, e); u != nil && u == "grain" do stocked += world_mass_of(w, e)
	}
	for e in inside[:world_entities_at(w, stall, .In, raw_data(inside[:]), len(inside))] {
		if u := world_unit_of(w, e); u != nil && u == "coin" do paid += world_units_of(w, e)
	}
	if stocked < 20000 || paid == 0 {
		fmt.printf("    the woodcutter's larder holds %dg of grain; the stall %d coins\n", stocked, paid)
		for line in agency_log_of(agency, cutter) do fmt.printf("    cutter: %s\n", line)
		for line in agency_log_of(agency, farmer) do fmt.printf("    farmer: %s\n", line)
	}
	bg_check(stocked >= 20000)
	bg_check(paid > 0)
	bg_check(test_market_count(w, "coin") == coins_before && test_market_count(w, "grain") == grain_before)
	/* with a pouch: at its belt, the purse in it, and no coins in a hand,
	 * nor left loose in the coffer */
	if pouched {
		at := world_location_of(w, worn)
		bg_check(at.form == .Held_By && at.place == cutter && at.slot == BG_BELT)
		bg_check(test_market_units_in(w, worn, "coin") == coins_before - paid && test_market_units_in(w, coffer, "coin") == 0)
		held: [4]Entity_ID
		for e in held[:min(world_entities_at(w, cutter, .Held_By, raw_data(held[:]), len(held)), len(held))] {
			u := world_unit_of(w, e)
			bg_check(u == nil || u != "coin")
		}
		/* coins nobody carries pay for nothing: the farmer, by its stall,
		 * doesn't pay its takings there into its larder */
		for e in inside[:world_entities_at(w, stall, .In, raw_data(inside[:]), len(inside))] {
			if u := world_unit_of(w, e); u == nil || u != "coin" do continue
			refused: string
			perform(w, c, action_make("pay", farmer, e, flarder), 1, &refused)
			scheduler_run_until(s, time_make(HOUR + 2000))
			bg_check(test_market_units_in(w, flarder, "coin") == 0 && test_market_units_in(w, stall, "coin") == paid)
		}
	}

	/* after the market: the farmer's takings home to its coffer, the
	 * woodcutter's coins back in its own */
	bg_check(agency_undertake_every_with(agency, farmer, "takings_home", 2 * HOUR, 3 * HOUR, "market", 4 * 24 * HOUR,
	                                     {{"stall", test_market_referent(fstore, stall)}, {"coffer", test_market_referent(fstore, fcoffer)}}))
	bg_check(agency_undertake_every_with(agency, cutter, "coins_home", 2 * HOUR, 3 * HOUR, "market", 4 * 24 * HOUR,
	                                     {{"coffer", test_market_referent(cstore, coffer)}}))
	scheduler_run_until(s, time_make(3 * HOUR))
	takings := test_market_units_in(w, fcoffer, "coin")
	kept    := test_market_units_in(w, coffer, "coin")
	if pouched {
		/* the pouch back in the coffer, what is left in it */
		at := world_location_of(w, worn)
		bg_check(at.form == .In && at.place == coffer && kept == 0)
		kept = test_market_units_in(w, worn, "coin")
	}
	if takings != paid || kept != coins_before - paid || test_market_units_in(w, stall, "coin") != 0 {
		fmt.printf("    takings %d of %d paid; the woodcutter's coffer %d\n", takings, paid, kept)
		for line in agency_log_of(agency, farmer) do fmt.printf("    farmer: %s\n", line)
		for line in agency_log_of(agency, cutter) do fmt.printf("    cutter: %s\n", line)
	}
	bg_check(takings == paid && test_market_units_in(w, stall, "coin") == 0)
	bg_check(kept == coins_before - paid)
}


/* How many units of the unit are in the container. */
@(private = "file")
test_market_units_in :: proc(w: ^World, container: Entity_ID, unit: cstring) -> i64 {
	n: i64
	inside: [16]Entity_ID
	for e in inside[:world_entities_at(w, container, .In, raw_data(inside[:]), len(inside))] {
		if u := world_unit_of(w, e); u != nil && u == unit do n += world_units_of(w, e)
	}
	return n
}


/* The referent of the entity in the store; 0 if it hasn't one. */
@(private = "file")
test_market_referent :: proc(store: ^Knowledge_Store, e: Entity_ID) -> u32 {
	for i: uint = 0; store != nil && i < knowledge_store_count(store); i += 1 {
		if knowledge_store_referent_at(store, i).truth == e do return knowledge_store_referent_at(store, i).id
	}
	return 0
}


/* How many units of the unit there are, everywhere. */
@(private = "file")
test_market_count :: proc(w: ^World, unit: cstring) -> i64 {
	n: i64
	bodies := world_store_for_kind(w, world_kind_named(w, "Body"))
	for i: uint = 0; i < store_count(bodies); i += 1 {
		e := store_entity_at_index(bodies, i)
		if u := world_unit_of(w, e); u != nil && u == unit && world_is_live(w, e) do n += world_units_of(w, e)
	}
	return n
}

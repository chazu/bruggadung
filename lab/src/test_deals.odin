package lab

import "core:fmt"
import "core:strings"

/*
 * Asking and negotiation (NEGOTIATION.md, content/deals/): Ada, hungry past
 * asking and with nothing to eat, asks Bo, beside her with a portion of
 * grain in hand. As Bo is disposed, he gives it, lends it on terms, or
 * walks away; with nothing like it, he says so.
 */

@(private = "file")
Deals_Run :: struct {
	world:  ^World,
	agency: ^Agency,
	s:      ^Scheduler,
	c:      ^Committer,
	ada:    Entity_ID,
	bo:     Entity_ID,
	grain:  Entity_ID,
}

/* Bo's dispositions, and how hungry he is himself (his satiety). */
@(private = "file")
Bo :: struct {
	generosity: i64,
	shrewdness: i64,
	satiety:    i64,
	trusting:   i64,
	holds:      cstring,        /* what he holds: "grain", or nothing */
	adaCoins:   bool,           /* Ada holds a purse */
}


@(private = "file")
test_deals_run :: proc(bo: Bo, until: i64 = 300000) -> Deals_Run {
	why: string
	run: Deals_Run

	w := test_world(104)
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

	g   := proposal_group_group_with_phase(.System, "setup: Ada hungry, Bo beside her")
	ada := proposal_group_create(g, "farmer", "Ada", on_tile(20, 70, 0))
	b   := proposal_group_create(g, "farmer", "Bo", on_tile(22, 70, 0))
	proposal_group_set_of_to(g, "Hungry.satiety", whole(ada), 0)
	proposal_group_set_of_to(g, "Hungry.satiety", whole(b), bo.satiety)
	proposal_group_set_of_to(g, "Agent.generosity", whole(b), bo.generosity)
	proposal_group_set_of_to(g, "Agent.shrewdness", whole(b), bo.shrewdness)
	proposal_group_set_of_to(g, "Agent.trusting", whole(b), bo.trusting)
	grain := proposal_group_create(g, bo.holds, "Bo's grain", held_by(b, 0)) if bo.holds != nil else NO_ENTITY
	if bo.adaCoins do proposal_group_create(g, "coins_400", "Ada's purse", held_by(ada, 1))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1000))
	run.ada, run.bo = proposal_group_id_for(g, ada), proposal_group_id_for(g, b)
	if grain != NO_ENTITY do run.grain = proposal_group_id_for(g, grain)
	bg_check(world_is_live(w, run.ada) && world_is_live(w, run.bo))
	agency_control(agency, run.ada)
	agency_control(agency, run.bo)
	scheduler_run_until(s, time_make(until))
	run.world, run.agency, run.s, run.c = w, agency, s, c
	return run
}


@(private = "file")
test_deals_print :: proc(run: Deals_Run) {
	for line in agency_log_of(run.agency, run.ada) do fmt.printf("      Ada %s\n", line)
	for line in agency_log_of(run.agency, run.bo) do fmt.printf("      Bo  %s\n", line)
}


test_deals :: proc() {
	/* generous: he gives it, and she eats it, grateful */
	{
		run := test_deals_run(Bo{generosity = 100, shrewdness = 50, satiety = 100, holds = "grain"})
		ok := test_logged_by(run.agency, run.ada, "asking R") && test_logged_by(run.agency, run.bo, "a gift") &&
		      !test_logged_by(run.agency, run.bo, "nothing I know of will do") &&
		      !world_is_live(run.world, run.grain) && test_logged_by(run.agency, run.ada, "eat R")
		if !ok do test_deals_print(run)
		bg_check(ok)
		m := agency_mind_of(run.agency, run.ada)
		bg_check(m.nowed == 0)
	}
	/* mean and shrewd: they haggle to a loan, and she owes it */
	{
		run := test_deals_run(Bo{generosity = 0, shrewdness = 100, satiety = 100, holds = "grain"})
		m := agency_mind_of(run.agency, run.ada)
		debt := false
		for o in m.owed[:m.nowed] do if o.kind == .Debt && o.explicit do debt = true
		credit := false
		mb := agency_mind_of(run.agency, run.bo)
		for o in mb.owed[:mb.nowed] do if o.kind == .Credit do credit = true
		ok := debt && credit && test_logged_by(run.agency, run.bo, "it offers a loan") && !world_is_live(run.world, run.grain) &&
		      !test_logged_by(run.agency, run.bo, "nothing I know of will do")
		if !ok do test_deals_print(run)
		bg_check(ok)
	}
	/* in kind, as Bo is by default; given grain to spare a day on, Ada
	 * repays it, and Bo trusts her more */
	{
		run := test_deals_run(Bo{generosity = 30, shrewdness = 50, satiety = 100, holds = "grain"})
		agreed := test_logged_by(run.agency, run.bo, "offers in kind, worth +5 to it, against +5: agreed")
		trusted := knowledge_store_trust_in(knowledge_store_of(run.agency.knowledge, run.bo),
		                                    test_referent_of(knowledge_store_of(run.agency.knowledge, run.bo), run.ada))
		/* (a day on, fed, so she doesn't eat the whole sack: eating a stack
		 * held eats all of it, an old fault of hunger/'s) */
		scheduler_run_until(run.s, time_make(86400000 + 60000))
		g := proposal_group_group_with_phase(.System, "setup: a sack of grain for Ada")
		proposal_group_create(g, "grain_sack", "Ada's sack", held_by(run.ada, 0))
		proposal_group_set_of_to(g, "Hungry.satiety", whole(run.ada), 100)
		committer_submit(run.c, g)
		scheduler_run_until(run.s, time_make(86400000 + 7 * 3600000))
		repaid := test_logged_by(run.agency, run.ada, "#Repaid") && test_logged_by(run.agency, run.bo, "repaid it")
		after := knowledge_store_trust_in(knowledge_store_of(run.agency.knowledge, run.bo),
		                                  test_referent_of(knowledge_store_of(run.agency.knowledge, run.bo), run.ada))
		ok := agreed && repaid && after > trusted && agency_mind_of(run.agency, run.bo).nowed == 0
		if !ok {
			fmt.printf("    trust %d, then %d\n", trusted, after)
			test_deals_print(run)
		}
		bg_check(ok)
	}
	/* a loan unpaid past its term: Bo trusts her less */
	{
		run := test_deals_run(Bo{generosity = 0, shrewdness = 100, satiety = 100, holds = "grain"})
		scheduler_run_until(run.s, time_make(86400000 + 600000))
		ok := test_logged_by(run.agency, run.bo, "owes it still") && test_logged_by(run.agency, run.ada, "never repaid")
		if !ok do test_deals_print(run)
		bg_check(ok)
	}
	/* a sale: Bo trusts no one with a loan, and Ada has coins; they settle on
	 * a price, and she pays it */
	{
		run := test_deals_run(Bo{generosity = 0, shrewdness = 50, satiety = 100, trusting = -15, holds = "grain", adaCoins = true})
		scheduler_run_until(run.s, time_make(600000))
		paid := false
		held: [4]Entity_ID
		for e in held[:min(world_entities_at(run.world, run.bo, .Held_By, raw_data(held[:]), 4), 4)] {
			if u := world_unit_of(run.world, e); u != nil && u == "coin" && world_units_of(run.world, e) > 0 do paid = true
		}
		ok := test_logged_by(run.agency, run.ada, "for ") && paid && !world_is_live(run.world, run.grain)
		if !ok do test_deals_print(run)
		bg_check(ok)
	}
	/* peckish himself and trusting no one, mean: no deal they can make is
	 * worth it to both (he would sell, and she has no coins), and one of
	 * them walks away */
	{
		run := test_deals_run(Bo{generosity = 0, shrewdness = 50, satiety = 62, trusting = -20, holds = "grain"})
		ok := (test_logged_by(run.agency, run.bo, "Refuse") || test_logged_by(run.agency, run.ada, "Refuse")) &&
		      world_is_live(run.world, run.grain) && agency_mind_of(run.agency, run.ada).nowed == 0
		if !ok do test_deals_print(run)
		bg_check(ok)
	}
	/* with nothing like it, he says so */
	{
		run := test_deals_run(Bo{generosity = 100, shrewdness = 50, satiety = 100})
		ok := test_logged_by(run.agency, run.bo, "something it hasn't") && test_logged_by(run.agency, run.ada, "answered: #HaveNone")
		if !ok do test_deals_print(run)
		bg_check(ok)
	}
}


/*
 * Asking in the village (lab/PLAN.md, NEGOTIATION.md): Ada, hungry with
 * nothing to eat, has seen Kit keep things in her own larder (what is put
 * into hers she notices), so he eats from it with her, and has what she
 * has: she doesn't ask him. Bo, away, she doesn't know where to find; back
 * in sight, she goes to him and asks, and he gives from his larder, there
 * near him.
 */
test_asking_in_the_village :: proc() {
	why: string

	w := test_world(123)
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

	g    := proposal_group_group_with_phase(.System, "setup: Ada hungry, Kit beside her, Bo by his larder")
	ada  := proposal_group_create(g, "farmer", "Ada", on_tile(20, 70, 0))
	kit  := proposal_group_create(g, "farmer", "Kit", on_tile(21, 71, 0))
	bo   := proposal_group_create(g, "farmer", "Bo", on_tile(23, 70, 0))
	hers := proposal_group_create(g, "larder", "Ada's larder", on_tile(21, 70, 0))
	his  := proposal_group_create(g, "larder", "Bo's larder", on_tile(24, 70, 0))
	proposal_group_create(g, "grain_sack", "Bo's grain", in_(his))
	proposal_group_set_of_to(g, "Hungry.satiety", whole(ada), 0)
	proposal_group_set_of_to(g, "Agent.generosity", whole(bo), 100)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1000))
	ada, kit, bo = proposal_group_id_for(g, ada), proposal_group_id_for(g, kit), proposal_group_id_for(g, bo)
	hers, his = proposal_group_id_for(g, hers), proposal_group_id_for(g, his)
	test_own(c, ada, hers)
	test_own(c, kit, hers)
	test_own(c, bo, his)
	scheduler_run_until(s, time_make(2000))

	/* Kit keeps things in her larder, three times, as she watches; Bo sees
	 * inside his */
	error: string
	for _ in 0 ..< 3 {
		g = proposal_group_group_with_phase(.System, "setup: something to put away")
		a := proposal_group_create(g, "birch_firewood_20", "Kit's", held_by(kit, 0))
		committer_submit(c, g)
		scheduler_run_until(s, time_make(world_time(w).ms + 1000))
		a = proposal_group_id_for(g, a)
		bg_check(perform(w, c, action_make("put_in", kit, a, hers), 0, &error) != nil)
		scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	}
	bg_check(perform(w, c, action_make("look_in", bo, his, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	astore := knowledge_store_of(knowledge, ada)
	kitR := test_referent_of(astore, kit)
	habit := knowledge_store_finding(astore, "#Habit", kitR)
	bg_check(habit != nil && habit.choice == test_referent_of(astore, hers))

	/* Bo away at work; Ada hungry, and nobody to ask */
	g = proposal_group_group_with_phase(.System, "setup: Bo away")
	proposal_group_move_to(g, whole(bo), on_tile(70, 70, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(world_time(w).ms + 2 * 60000))
	agency_control(agency, ada)
	agency_control(agency, bo)
	scheduler_run_until(s, time_make(world_time(w).ms + 30 * 60000))
	askedKit := test_logged_by(agency, ada, fmt.tprintf("asking R%d", kitR))

	/* back in sight (someone come by: eating weighed again): asked, he
	 * gives from his larder */
	g = proposal_group_group_with_phase(.System, "setup: Bo home")
	proposal_group_move_to(g, whole(bo), on_tile(23, 71, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(world_time(w).ms + 30 * 60000))
	boR := test_referent_of(astore, bo)
	askedBo := test_logged_by(agency, ada, fmt.tprintf("asking R%d", boR))
	given := test_logged_by(agency, ada, "eat R")
	if askedKit || !askedBo || !given {
		fmt.printf("    asked Kit: %v, asked Bo: %v, ate: %v\n", askedKit, askedBo, given)
		for line in agency_log_of(agency, ada) do fmt.printf("      Ada %s\n", line)
		for line in agency_log_of(agency, bo) do fmt.printf("      Bo  %s\n", line)
	}
	bg_check(!askedKit && askedBo && given)
}


/*
 * Where neighbours live (KNOWLEDGE.md decision 27, village.tri's
 * where_villagers_live): Ada has never seen Bo, but everyone knows whose
 * each bed is, so she knows his, and him by sight. Hungry, with nothing at
 * home, she goes to his house and asks him there; he gives from his
 * larder (he has looked in it). His larder she doesn't know of: only beds
 * are common knowledge.
 */
test_where_neighbours_live :: proc() {
	why: string

	w := test_world(124)
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

	g      := proposal_group_group_with_phase(.System, "setup: Ada hungry at home, Bo at his, out of sight")
	ada    := proposal_group_create(g, "farmer", "Ada", on_tile(20, 70, 0))
	bo     := proposal_group_create(g, "farmer", "Bo", on_tile(36, 70, 0))
	herBed := proposal_group_create(g, "bed", "Ada's bed", on_tile(20, 69, 0))
	hisBed := proposal_group_create(g, "bed", "Bo's bed", on_tile(36, 69, 0))
	hers   := proposal_group_create(g, "larder", "Ada's larder", on_tile(21, 70, 0))
	his    := proposal_group_create(g, "larder", "Bo's larder", on_tile(37, 70, 0))
	proposal_group_create(g, "grain_sack", "Bo's grain", in_(his))
	for own in ([][2]Entity_ID{{ada, herBed}, {ada, hers}, {bo, hisBed}, {bo, his}}) {
		claim := proposal_group_create(g, "ownership", "its own", location_make_none())
		proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
		proposal_group_relate(g, .Claimant, whole(claim), whole(own[0]))
		proposal_group_relate(g, .Claim_Subject, whole(claim), whole(own[1]))
	}
	proposal_group_set_of_to(g, "Hungry.satiety", whole(ada), 0)
	proposal_group_set_of_to(g, "Agent.generosity", whole(bo), 100)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(2000))
	ada, bo = proposal_group_id_for(g, ada), proposal_group_id_for(g, bo)
	hisBed, his = proposal_group_id_for(g, hisBed), proposal_group_id_for(g, his)
	error: string
	bg_check(perform(w, c, action_make("look_in", bo, his, NO_ENTITY), 0, &error) != nil)      /* he knows what he has */
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))

	/* she knows his bed, and whose it is: him, by sight, never seen */
	astore := knowledge_store_of(knowledge, ada)
	boR    := u32(0)
	for i: uint = 0; i < knowledge_store_count(astore); i += 1 {
		if r := knowledge_store_referent_at(astore, i); r.known == bo do boR = r.id
	}
	bg_check(boR != 0 && knowledge_store_referent(astore, boR).seen == 0)
	bedR  := test_referent_of(astore, hisBed)
	owned := false
	for i: uint = 0; i < knowledge_store_finding_count(astore); i += 1 {
		f := knowledge_store_finding_at(astore, i)
		if f.about == bedR && f.choice == boR && string(f.kind) == "#Owned" && string(f.rule) == "common" do owned = true
	}
	bg_check(bedR != 0 && owned)
	bg_check(test_referent_of(astore, his) == 0)
	/* whom it knows by sight is saved, and restored */
	restored := autorelease(knowledge_init_with_world(w))
	knowledge_restore_saved_state(restored, knowledge_saved_state(knowledge))
	bg_check(knowledge_store_referent(knowledge_store_of(restored, ada), boR).known == bo)

	/* hungry: to his house, and asks him there; he gives */
	agency_control(agency, ada)
	agency_control(agency, bo)
	scheduler_run_until(s, time_make(world_time(w).ms + 60 * 60000))
	went   := test_logged_by(agency, ada, fmt.tprintf("at R%d's", boR))
	asked  := test_logged_by(agency, ada, fmt.tprintf("say R%d: #Ask", boR))
	given  := test_logged_by(agency, ada, "eat R")
	if !went || !asked || !given {
		fmt.printf("    went: %v, asked: %v, ate: %v\n", went, asked, given)
		for line in agency_log_of(agency, ada) do fmt.printf("      Ada %s\n", line)
		for line in agency_log_of(agency, bo) do fmt.printf("      Bo  %s\n", line)
	}
	bg_check(went && asked && given)
}


/*
 * Waiting at a neighbour's house is for an hour at most (NEGOTIATION.md
 * decision 3): Bo is away and stays away. Ada, hungry with nothing at
 * home, goes to his house and waits; after the hour she counts him asked,
 * for that goal, and with nobody else to ask finds eating impossible for
 * now. Two hungry
 * neighbours waiting at each other's houses waited for good.
 */
test_never_came_home :: proc() {
	why: string

	w := test_world(125)
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

	g      := proposal_group_group_with_phase(.System, "setup: Ada hungry at home, Bo far from his")
	ada    := proposal_group_create(g, "farmer", "Ada", on_tile(20, 70, 0))
	bo     := proposal_group_create(g, "farmer", "Bo", on_tile(70, 70, 0))
	herBed := proposal_group_create(g, "bed", "Ada's bed", on_tile(20, 69, 0))
	hisBed := proposal_group_create(g, "bed", "Bo's bed", on_tile(36, 69, 0))
	for own in ([][2]Entity_ID{{ada, herBed}, {bo, hisBed}}) {
		claim := proposal_group_create(g, "ownership", "its own", location_make_none())
		proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
		proposal_group_relate(g, .Claimant, whole(claim), whole(own[0]))
		proposal_group_relate(g, .Claim_Subject, whole(claim), whole(own[1]))
	}
	proposal_group_set_of_to(g, "Hungry.satiety", whole(ada), 0)
	committer_submit(c, g)
	scheduler_run_until(s, time_make(3000))
	ada = proposal_group_id_for(g, ada)

	agency_control(agency, ada)
	scheduler_run_until(s, time_make(world_time(w).ms + 30 * 60000))
	waited := test_logged_by(agency, ada, "to come home")
	early  := test_logged_by(agency, ada, "never came home")
	scheduler_run_until(s, time_make(world_time(w).ms + 60 * 60000))
	gaveUp := test_logged_by(agency, ada, "never came home")
	scheduler_run_until(s, time_make(world_time(w).ms + 120 * 60000))
	log  := agency_log_of(agency, ada)
	over := len(log) != 0 && strings.contains(log[len(log) - 1], "impossible for now")
	if !waited || early || !gaveUp || !over {
		fmt.printf("    waited: %v, early: %v, gave up: %v, over: %v\n", waited, early, gaveUp, over)
		for line in log do fmt.printf("      Ada %s\n", line)
	}
	bg_check(waited && !early && gaveUp && over)
}

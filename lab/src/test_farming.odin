package lab

/*
 * Farming (VILLAGE.md slice 6, content/farming/): a plot is an area, in
 * reach from anywhere on it or beside it. Sown a row at a time, seed for
 * its crop in hand, it stands sown once its last row is, and two sowing it
 * at once don't both count a row. Its growth is read from the time since,
 * never stepped, and it stands ripe the moment it is grown: the domain's
 * one wake. Harvested a row at a time, its yield is in the harvester's
 * hand, with what it holds of the kind; the last row reaped, it is bare.
 */

import "core:fmt"

FARM_DAY :: i64(86400000)

test_farming :: proc() {
	error: string
	v: i64

	w := test_world(106)
	why: string
	bg_check(world_set_terrain_map(w, "farm_map", &why))
	c := test_committer(w)
	activities := activities_with_world(w, c)
	farming := autorelease(farming_init_with_world(w))
	s := autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_add_domain(s, farming_as_domain(farming))

	g := proposal_group_group_with_phase(.System, "setup: a plot of 8 by 4, a farmhand beside it, seed in hand")
	plot := proposal_group_create(g, "grain_plot", "the plot", on_tile(4, 3, 0))
	proposal_group_set_of_to(g, "Area.east", whole(plot), 8)
	proposal_group_set_of_to(g, "Area.south", whole(plot), 4)
	me   := proposal_group_create(g, "farmhand", "me", on_tile(11, 7, 0))       /* beside its far corner */
	seed := proposal_group_create(g, "seed_grain", "the seed", held_by(me, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	plot, me, seed = proposal_group_id_for(g, plot), proposal_group_id_for(g, me), proposal_group_id_for(g, seed)
	stands := proc(w: ^World, plot: Entity_ID) -> u32 {return plot_of(w, plot).stands}

	/* in reach from beside its far corner */
	bg_check(view_can_reach(view_of(me, w), plot))

	/* a row sown: eight tiles, eight units of seed; the fourth, the last,
	 * and it stands sown, from then */
	for row in 0 ..< 4 {
		error = ""
		if perform(w, c, action_make("sow", me, seed, plot), 0, &error) == nil do fmt.printf("    sow %d: %s\n", row, error)
		scheduler_run_until(s, time_make(world_time(w).ms + 901 * 1000))
		if row < 3 do bg_check(plot_of(w, plot).sown == 8 * i64(row + 1) && stands(w, plot) == plot_stands(w, "bare"))
	}
	bg_check(stands(w, plot) == plot_stands(w, "sown") && plot_of(w, plot).sown == 0)
	bg_check(world_units_of(w, seed) == 500 - 32)
	sown := plot_of(w, plot).sownAt
	bg_check(sown > 3 * 900 * 1000 && sown <= world_time(w).ms)
	/* sown, it isn't sown again */
	bg_check(perform(w, c, action_make("sow", me, seed, plot), 0, &error) == nil)

	/* growing, in closed form: at any time, the time since sowing over a
	 * fortnight; nothing is stepped, so the boundaries between are only
	 * those that something else asks for */
	before := world_boundary(w)
	for k in 1 ..< 14 {
		at := sown + i64(k) * FARM_DAY + 3 * 3600 * 1000
		scheduler_run_until(s, time_make(at))
		bg_check(plot_growth(w, plot_of(w, plot), at) == (at - sown) * 100 / (14 * FARM_DAY))
		bg_check(stands(w, plot) == plot_stands(w, "sown"))
	}
	bg_check(world_boundary(w) - before <= 14)

	/* ripe at the very moment it is grown: its wake */
	scheduler_run_until(s, time_make(sown + 14 * FARM_DAY - 1))
	bg_check(stands(w, plot) == plot_stands(w, "sown"))
	scheduler_run_until(s, time_make(sown + 14 * FARM_DAY))
	bg_check(world_time(w).ms == sown + 14 * FARM_DAY && stands(w, plot) == plot_stands(w, "ripe"))

	/* a row reaped: sixteen portions of raw grain in the free hand; the next
	 * with them; the last, and it is bare */
	harvest := NO_ENTITY
	held: [2]Entity_ID
	for row in 0 ..< 4 {
		error = ""
		if perform(w, c, action_make("harvest", me, plot, NO_ENTITY), 0, &error) == nil do fmt.printf("    harvest %d: %s\n", row, error)
		scheduler_run_until(s, time_make(world_time(w).ms + 2400 * 1000))     /* slower, worn by the rows before */
		if row == 0 {
			for e in held[:world_entities_at(w, me, .Held_By, raw_data(held[:]), 2)] do if e != seed do harvest = e
			bg_check(harvest != NO_ENTITY && world_units_of(w, harvest) == 16 && world_unit_of(w, harvest) == "grain")
			bg_check(world_mass_of(w, harvest) == 16 * 250 && world_get_field(w, "Food.raw", harvest, &v) && v == 1)
		}
	}
	bg_check(world_is_live(w, harvest) && world_units_of(w, harvest) == 64)
	bg_check(world_entities_at(w, me, .Held_By, raw_data(held[:]), 2) == 2)
	bg_check(stands(w, plot) == plot_stands(w, "bare") && plot_of(w, plot).reaped == 0)

	/* two sowing a bare plot at once: one row counted, one seed spent */
	g = proposal_group_group_with_phase(.System, "setup: another, with seed, beside the plot")
	other      := proposal_group_create(g, "farmhand", "another", on_tile(3, 3, 0))
	other_seed := proposal_group_create(g, "seed_grain", "its seed", held_by(other, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	other, other_seed = proposal_group_id_for(g, other), proposal_group_id_for(g, other_seed)
	bg_check(view_can_reach(view_of(other, w), plot))
	error = ""
	bg_check(perform(w, c, action_make("sow", me, seed, plot), 0, &error) != nil)
	bg_check(perform(w, c, action_make("sow", other, other_seed, plot), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1200 * 1000))
	bg_check(plot_of(w, plot).sown == 8)
	bg_check(world_units_of(w, seed) + world_units_of(w, other_seed) == 468 + 500 - 8)

	/* saved, how the plot stood (its events) and a change still to commit
	 * (expecting it bare) are by name, not by type ID, which content
	 * renumbers; restored, the same save again, and the same state */
	g = proposal_group_group_with_phase(.System, "waiting: the plot sown")
	proposal_group_set_of_to_expecting(g, "Plot.stands", whole(plot), i64(plot_stands(w, "sown")),
	                                   i64(plot_stands(w, "bare")))
	committer_submit(c, g)
	text := save(w, c, nil)
	bg_check(ns_contains(text, "\"\\\"ripe\\\"\" \"Plot.stands\""))
	bg_check(ns_contains(text, "\"\\\"bare\\\"\" 0 \"\\\"sown\\\"\""))
	c2: ^Committer
	w2 := test_restore(text, world_content_build(w), &c2, &error)
	bg_check(w2 != nil && save(w2, c2, nil) == text && world_state_hash(w2) == world_state_hash(w))
}


/*
 * Three weeks of a plot tended (issue #6's done-when): a farmhand, bound to
 * its plot (8 by 4) through its working hours, its seed in a larder by the
 * meadow's edge. It sows the plot the first day, a row at a time, and puts
 * back the seed left; harvests it once ripe, takes the harvest in, and sows
 * it again. At every boundary the plot is ripe exactly when its closed form
 * says it is grown, and at times between, its growth is the time since its
 * last row was sown over a fortnight.
 */
test_farming_weeks :: proc() {
	w := test_world(107)
	why: string
	bg_check(world_set_terrain_map(w, "farm_map", &why))
	c := test_committer(w)
	committer_set_tracing(c, false)
	activities := activities_with_world(w, c)
	knowledge  := autorelease(knowledge_init_with_world(w))
	agency     := autorelease(agency_init_with_world(w, c, knowledge))
	farming    := autorelease(farming_init_with_world(w))
	s          := autorelease(scheduler_init_with_world(w, c))
	agency_set_activities(agency, activities)
	scheduler_add_domain(s, farming_as_domain(farming))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))

	g := proposal_group_group_with_phase(.System, "setup: a farmhand, its plot, its seed")
	plot := proposal_group_create(g, "grain_plot", "its plot", on_tile(4, 3, 0))
	proposal_group_set_of_to(g, "Area.east", whole(plot), 8)
	proposal_group_set_of_to(g, "Area.south", whole(plot), 4)
	me     := proposal_group_create(g, "farmhand", "the farmhand", on_tile(14, 2, 0))
	larder := proposal_group_create(g, "larder", "its larder", on_tile(16, 1, 0))
	proposal_group_create(g, "seed_grain", "its seed", in_(larder))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))                  /* it sees its larder, and the plot's east end */
	plot, me, larder = proposal_group_id_for(g, plot), proposal_group_id_for(g, me), proposal_group_id_for(g, larder)
	test_own(c, me, larder)
	scheduler_run_until(s, time_make(2))
	store := knowledge_store_of(knowledge, me)
	known, kept := u32(0), u32(0)
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if r.truth == plot do known = r.id
		if r.truth == larder do kept = r.id
	}
	bg_check(known != 0 && kept != 0)
	bg_check(agency_undertake_every_with(agency, me, "plot_tended", 7 * 3600 * 1000, 15 * 3600 * 1000, "work", FARM_DAY,
	                                     {{"plot", known}, {"larder", kept}}))

	wrong, checked, sowings := 0, 0, 0
	sown := plot_stands(w, "sown")
	ripe := plot_stands(w, "ripe")
	last := u32(0)
	for d in 0 ..< i64(21) {
		/* boundary by boundary, ripe just when it is grown */
		for scheduler_step_until(s, time_make((d + 1) * FARM_DAY)) {
			now := world_time(w).ms
			p   := plot_of(w, plot)
			if p.stands == sown && p.stands != last do sowings += 1
			last = p.stands
			if p.stands == sown || p.stands == ripe {
				if (p.stands == ripe) != (now >= p.sownAt + 14 * FARM_DAY) do wrong += 1
				/* and between this boundary and the next, as the closed form says */
				between := now + 7919
				if plot_growth(w, p, between) != min((between - p.sownAt) * 100 / (14 * FARM_DAY), 100) do wrong += 1
				checked += 1
			}
		}
		if d == 0 {
			/* sown the first day, the seed left put back */
			held: [2]Entity_ID
			bg_check(plot_of(w, plot).stands == sown)
			bg_check(world_entities_at(w, me, .Held_By, raw_data(held[:]), 2) == 0)
		}
	}
	bg_check(wrong == 0 && checked > 0)
	/* harvested once, its yield in the larder, and sown again */
	if sowings != 2 do fmt.printf("    sown %d times\n", sowings)
	bg_check(sowings == 2 && plot_of(w, plot).stands == sown)
	if village_portions_in(w, larder) != 64 do fmt.printf("    %d portions in the larder\n", village_portions_in(w, larder))
	bg_check(village_portions_in(w, larder) == 64)
	held: [2]Entity_ID
	bg_check(world_entities_at(w, me, .Held_By, raw_data(held[:]), 2) == 0)
}


/* An ownership claim of the owner's on the thing, committed. */
@(private = "file")
test_own :: proc(c: ^Committer, owner: Entity_ID, thing: Entity_ID) {
	g := proposal_group_group_with_phase(.System, "setup: its own")
	claim := proposal_group_create(g, "ownership", "its own", location_make_none())
	proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
	proposal_group_relate(g, .Claimant, whole(claim), whole(owner))
	proposal_group_relate(g, .Claim_Subject, whole(claim), whole(thing))
	committer_submit(c, g)
}


/*
 * Seed kept back from the harvest (content/farming/'s keep_back_seed): a
 * farmhand tends a ripe plot of 16 by 4, no seed in its larder. Holding
 * more than a sack's worth of the harvest, it keeps a sack of it back as
 * seed (the plot marked kept), takes the rest in, and sows the plot again
 * from the sack, the seed left put back; sown, the plot is no longer kept.
 */
test_keep_seed :: proc() {
	w := test_world(118)
	why: string
	bg_check(world_set_terrain_map(w, "farm_map", &why))
	c := test_committer(w)
	committer_set_tracing(c, false)
	activities := activities_with_world(w, c)
	knowledge  := autorelease(knowledge_init_with_world(w))
	agency     := autorelease(agency_init_with_world(w, c, knowledge))
	farming    := autorelease(farming_init_with_world(w))
	s          := autorelease(scheduler_init_with_world(w, c))
	agency_set_activities(agency, activities)
	scheduler_add_domain(s, farming_as_domain(farming))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))

	g := proposal_group_group_with_phase(.System, "setup: a farmhand, its ripe plot, its empty larder")
	plot := proposal_group_create(g, "grain_plot", "its plot", on_tile(2, 3, 0))
	proposal_group_set_of_to(g, "Area.east", whole(plot), 16)
	proposal_group_set_of_to(g, "Area.south", whole(plot), 4)
	proposal_group_set_of_to(g, "Plot.stands", whole(plot), i64(plot_stands(w, "ripe")))
	me     := proposal_group_create(g, "farmhand", "the farmhand", on_tile(18, 2, 0))
	larder := proposal_group_create(g, "larder", "its larder", on_tile(19, 1, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	plot, me, larder = proposal_group_id_for(g, plot), proposal_group_id_for(g, me), proposal_group_id_for(g, larder)
	test_own(c, me, larder)
	scheduler_run_until(s, time_make(2))
	store := knowledge_store_of(knowledge, me)
	known, kept := u32(0), u32(0)
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if r.truth == plot do known = r.id
		if r.truth == larder do kept = r.id
	}
	bg_check(known != 0 && kept != 0)
	bg_check(agency_undertake_every_with(agency, me, "plot_tended", 7 * 3600 * 1000, 15 * 3600 * 1000, "work", FARM_DAY,
	                                     {{"plot", known}, {"larder", kept}}))

	marked := false
	for scheduler_step_until(s, time_make(FARM_DAY)) do if plot_of(w, plot).kept do marked = true
	/* 128 portions reaped (two a tile), fifty kept back as five hundred units of
	 * seed, sixty-four of them sown; the rest of each in the larder */
	seed: i64
	inside: [8]Entity_ID
	for e in inside[:world_entities_at(w, larder, .In, raw_data(inside[:]), len(inside))] {
		if u := world_unit_of(w, e); u != nil && u == "seed grain" do seed += world_units_of(w, e)
	}
	held: [2]Entity_ID
	p := plot_of(w, plot)
	if p.stands != plot_stands(w, "sown") || village_portions_in(w, larder) != 78 || seed != 436 {
		fmt.printf("    stands %d, %d portions and %d seed in the larder\n", p.stands, village_portions_in(w, larder), seed)
		for line in agency_log_of(agency, me) do fmt.printf("    %s\n", line)
	}
	bg_check(marked && !p.kept && p.stands == plot_stands(w, "sown"))
	bg_check(village_portions_in(w, larder) == 78 && seed == 436)
	bg_check(world_entities_at(w, me, .Held_By, raw_data(held[:]), 2) == 0)
}

package lab

/*
 * Relief in levels (OROGEN.md decision 6, slice 3), on the ridge
 * (content/terrain/terrain.tri's ridge_map): a walk of one tile comes to the
 * level of the ground, a step up or down; nothing walks a cliff, up or
 * down; a hill hides what is behind it, until its crest; one reaches a
 * thing a step up or down the slope; an explorer finds its way over the
 * ridge; and on generated country a walker keeps to the ground.
 */

test_relief :: proc() {
	st:        Stage
	knowledge: ^Knowledge
	g:         ^Proposal_Group
	error:     string

	st.w = test_world(7)
	bg_check(world_set_terrain_map(st.w, "ridge_map", &error))
	if error != "" do return
	t := world_terrain(st.w)
	bg_check(world_tiles_wide(st.w) == 11 && world_tiles_high(st.w) == 5 && world_levels(st.w) == 4)

	/* the ground, from the west: 0 0 1 2 1 0 0 2 2 0 0 */
	profile := [11]i32{0, 0, 1, 2, 1, 0, 0, 2, 2, 0, 0}
	for e, x in profile {
		z, ok := terrain_ground_level(t, i32(x), 2)
		bg_check(ok && z == e)
	}
	/* a step: level, up, down; a cliff: blocked from below, a drop from above */
	how, level := terrain_step(t, 0, 2, 0, 1, 2)
	bg_check(how == .Level && level == 0)
	how, level = terrain_step(t, 1, 2, 0, 2, 2)
	bg_check(how == .Up && level == 1)
	how, level = terrain_step(t, 3, 2, 2, 4, 2)
	bg_check(how == .Down && level == 1)
	how, level = terrain_step(t, 6, 2, 0, 7, 2)
	bg_check(how == .Blocked && level == 0)
	how, level = terrain_step(t, 8, 2, 2, 9, 2)
	bg_check(how == .Drop && level == 2)
	how, _ = terrain_step(t, 0, 2, 0, -1, 2)
	bg_check(how == .Blocked)
	/* beside, for reaching: up the slope, not up the cliff */
	bg_check(terrain_beside(t, 1, 2, 0, 2, 2, 1) && terrain_beside(t, 2, 2, 1, 1, 2, 0) &&
	         terrain_beside(t, 1, 2, 0, 1, 3, 0) && !terrain_beside(t, 6, 2, 0, 7, 2, 2))

	/* a worker west of the ridge; a bucket east of it, four tiles off; one
	 * on the slope beside the worker; one on the plateau */
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	g = proposal_group_group_with_phase(.System, "setup: a worker west of the ridge, buckets about")
	worker := proposal_group_create(g, "worker", "worker", on_tile(1, 2, 0))
	behind := proposal_group_create(g, "bucket", "behind the ridge", on_tile(5, 2, 0))
	slope  := proposal_group_create(g, "bucket", "on the slope", on_tile(2, 2, 1))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1000))
	bg_check(proposal_group_applied(g))
	worker = proposal_group_id_for(g, worker)
	behind = proposal_group_id_for(g, behind)
	slope  = proposal_group_id_for(g, slope)
	store := knowledge_store_of(knowledge, worker)

	/* it sees the bucket on the slope, a level up, and not the one behind
	 * the ridge; nor the ground there */
	bg_check(test_referent_of(store, slope) != 0 && test_referent_of(store, behind) == 0)
	bg_check(!knowledge_in_sight(knowledge, on_tile(5, 2, 0), on_tile(1, 2, 0)) &&
	         !knowledge_in_sight(knowledge, on_tile(1, 2, 0), on_tile(5, 2, 0)))
	bg_check(knowledge_store_has_seen_x(store, 2, 2, 1) && knowledge_store_has_seen_x(store, 2, 2, 0) &&
	         !knowledge_store_has_seen_x(store, 5, 2, 0))
	/* and reaches the one on the slope from beside it */
	view := view_of(worker, st.w)
	bg_check(view_can_reach(view, slope) && !view_can_reach(view, behind))

	/* up the ridge a step at a time; from the crest it sees over */
	at := test_walk_once(st, worker, "walk_east")
	bg_check(at.x == 2 && at.level == 1)
	bg_check(test_referent_of(store, behind) == 0)
	at = test_walk_once(st, worker, "walk_east")
	bg_check(at.x == 3 && at.level == 2)
	bg_check(test_referent_of(store, behind) != 0 && knowledge_store_has_seen_x(store, 5, 2, 0))
	bg_check(knowledge_in_sight(knowledge, on_tile(5, 2, 0), on_tile(3, 2, 2)))
	/* down the far side, across the flat, and no further: the cliff */
	for _ in 0 ..< 5 do at = test_walk_once(st, worker, "walk_east")
	bg_check(at.x == 6 && at.level == 0)

	/* on the plateau, nothing steps off either edge */
	g = proposal_group_group_with_phase(.System, "setup: a worker on the plateau")
	high := proposal_group_create(g, "worker", "on the plateau", on_tile(8, 2, 2))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1))
	high = proposal_group_id_for(g, high)
	at = test_walk_once(st, high, "walk_east")
	bg_check(at.x == 8 && at.level == 2)
	at = test_walk_once(st, high, "walk_west")
	at = test_walk_once(st, high, "walk_west")
	bg_check(at.x == 7 && at.level == 2)

	/* an explorer west of the ridge finds its way over it: in a minute it
	 * has stood on the crest and seen the ground beyond */
	{
		w := test_world(7)
		bg_check(world_set_terrain_map(w, "ridge_map", &error))
		c          := test_committer(w)
		activities := activities_with_world(w, c)
		k          := autorelease(knowledge_init_with_world(w))
		agency     := autorelease(agency_init_with_world(w, c, k))
		s          := autorelease(scheduler_init_with_world(w, c))
		agency_set_activities(agency, activities)
		scheduler_set_activities(s, activities_as_activity_clock(activities))
		scheduler_set_perception(s, knowledge_as_perception_phase(k))
		scheduler_set_decision(s, agency_as_decision_phase(agency))
		g = proposal_group_group_with_phase(.System, "setup: an explorer west of the ridge")
		explorer := proposal_group_create(g, "worker", "explorer", on_tile(0, 2, 0))
		committer_submit(c, g)
		scheduler_run_until(s, time_make(1))
		explorer = proposal_group_id_for(g, explorer)
		agency_autopilot_explore(agency, explorer, 50)
		crest := false
		for second: i64 = 1; second <= 60; second += 1 {
			scheduler_run_until(s, time_make(second * 1000))
			here := world_location_of(w, explorer)
			if here.level == 2 && here.x == 3 do crest = true
			/* it stands on the ground, wherever it is */
			z, ok := terrain_ground_level(world_terrain(w), here.x, here.y)
			bg_check(ok && z == here.level)
		}
		es := knowledge_store_of(k, explorer)
		bg_check(crest && knowledge_store_has_seen_x(es, 6, 0, 0) && knowledge_store_has_seen_x(es, 5, 4, 0))
		/* the plateau it can't climb: it has seen its face, not its top's far side */
		bg_check(world_location_of(w, explorer).x <= 6)
	}

	/* on generated country, an explorer keeps to the ground, and gets about */
	{
		w := test_world(7)
		bg_check(world_set_terrain_map(w, "hills_map", &error))
		c          := test_committer(w)
		activities := activities_with_world(w, c)
		k          := autorelease(knowledge_init_with_world(w))
		agency     := autorelease(agency_init_with_world(w, c, k))
		s          := autorelease(scheduler_init_with_world(w, c))
		agency_set_activities(agency, activities)
		scheduler_set_activities(s, activities_as_activity_clock(activities))
		scheduler_set_perception(s, knowledge_as_perception_phase(k))
		scheduler_set_decision(s, agency_as_decision_phase(agency))
		start := on_tile(128, 128, world_ground_level(w, 128, 128))
		g = proposal_group_group_with_phase(.System, "setup: an explorer in the hills")
		explorer := proposal_group_create(g, "worker", "explorer", start)
		committer_submit(c, g)
		scheduler_run_until(s, time_make(1))
		bg_check(proposal_group_applied(g))
		explorer = proposal_group_id_for(g, explorer)
		agency_autopilot_explore(agency, explorer, 50)
		levels: [32]bool
		far: i32
		for second: i64 = 1; second <= 240; second += 1 {
			scheduler_run_until(s, time_make(second * 1000))
			here := world_location_of(w, explorer)
			z, ok := terrain_ground_level(world_terrain(w), here.x, here.y)
			bg_check(ok && z == here.level)
			levels[here.level] = true
			far = max(far, abs(here.x - start.x) + abs(here.y - start.y))
		}
		climbed := 0
		for l in levels do if l do climbed += 1
		bg_check(far >= 8 && climbed >= 2)
	}
}

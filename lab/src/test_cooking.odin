package lab

/*
 * Cooking (VILLAGE.md slice 4, content/cooking/): a portion taken from a
 * sack is food still, raw; cooked at a lit stove it is a meal, and
 * nourishes more; at a cold stove, or cooked again, it can't be.
 */

test_cooking :: proc() {
	error: string
	raw, nourishment, count: i64

	w := test_world(7)
	c := test_committer(w)
	activities := activities_with_world(w, c)
	s := autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	cook   := test_commit_create(c, "farmer", on_tile(5, 5, 0))
	larder := test_commit_create(c, "larder", on_tile(6, 5, 0))
	stove  := test_commit_create(c, "stove", on_tile(5, 6, 0))
	bg_check(cook != NO_ENTITY && larder != NO_ENTITY && stove != NO_ENTITY)
	g := proposal_group_group_with_phase(.System, "setup: a sack in the larder")
	sack := proposal_group_create(g, "grain_sack", "the sack", in_(larder))
	committer_submit(c, g)
	committer_commit_boundary(c)
	sack = proposal_group_id_for(g, sack)

	/* a portion taken: food still, raw, as the sack is; the sack one less */
	g = perform(w, c, action_make("take_some", cook, sack, NO_ENTITY), 1, &error)
	bg_check(g != nil)
	world_set_boundary(w, world_boundary(w) + 1)
	committer_commit_boundary(c)
	held: [2]Entity_ID
	bg_check(world_entities_at(w, cook, .Held_By, raw_data(held[:]), 2) == 1)
	portion := held[0]
	bg_check(world_get_field(w, "Food.raw", portion, &raw) && raw == 1)
	bg_check(world_get_field(w, "Food.nourishment", portion, &nourishment) && nourishment == 15)
	bg_check(world_get_field(w, "Stack.count", sack, &count) && count == 59)
	bg_check(world_info(w, portion) != nil && string(world_info(w, portion).blueprint) == "grain")

	/* at a cold stove it can't be cooked */
	bg_check(perform(w, c, action_make("cook", cook, portion, stove), 0, &error) == nil)

	/* lit, it can: twenty minutes, and it is a meal */
	g = perform(w, c, action_make("light", cook, stove, NO_ENTITY), 0, &error)
	bg_check(g != nil)
	world_set_boundary(w, world_boundary(w) + 1)
	committer_commit_boundary(c)
	error = ""
	bg_check(perform(w, c, action_make("cook", cook, portion, stove), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1200 * 1000 + 1))
	bg_check(world_get_field(w, "Food.raw", portion, &raw) && raw == 0)
	bg_check(world_get_field(w, "Food.nourishment", portion, &nourishment) && nourishment == 50)

	/* cooked, it isn't cooked again */
	bg_check(perform(w, c, action_make("cook", cook, portion, stove), 0, &error) == nil)
}

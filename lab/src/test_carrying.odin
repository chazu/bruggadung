package lab

/*
 * Carrying (VILLAGE.md decision 11, content/carrying/): a backpack is
 * shouldered, onto the back, and both hands stay free; what is put in it
 * goes where its carrier goes, up to its load and no more; carried, a load
 * past the burden's light slows a walk; unpacked, a thing is taken out and
 * put in a larder; put back, it lies beside the larder. A basket is
 * held in a hand, and bears less.
 */

import "core:fmt"


test_carrying :: proc() {
	error: string

	w := test_world(116)
	why: string
	bg_check(world_set_terrain_map(w, "woods_map", &why))
	c := test_committer(w)
	activities := activities_with_world(w, c)
	s := autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))

	g := proposal_group_group_with_phase(.System, "setup: a farmer, a backpack and a basket, two sacks of grain, a larder")
	farmer := proposal_group_create(g, "farmer", "the farmer", on_tile(10, 10, 0))
	pack   := proposal_group_create(g, "backpack", "the backpack", on_tile(11, 10, 0))
	basket := proposal_group_create(g, "basket", "the basket", on_tile(11, 10, 0))
	one    := proposal_group_create(g, "grain_sack", "a sack", on_tile(10, 11, 0))
	two    := proposal_group_create(g, "grain_sack", "another", on_tile(10, 11, 0))
	larder := proposal_group_create(g, "larder", "the larder", on_tile(9, 10, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	farmer, pack, basket = proposal_group_id_for(g, farmer), proposal_group_id_for(g, pack), proposal_group_id_for(g, basket)
	one, two, larder = proposal_group_id_for(g, one), proposal_group_id_for(g, two), proposal_group_id_for(g, larder)
	t := i64(1)
	act :: proc(w: ^World, c: ^Committer, s: ^Scheduler, t: ^i64, a: Action, units: i64 = 0) -> bool {
		error: string
		ok := perform(w, c, a, units, &error) != nil
		if !ok do fmt.printf("    %s: %s\n", a.operation, error)
		t^ += 3000
		scheduler_run_until(s, time_make(t^))
		return ok
	}

	/* shouldered: on the back, both hands free */
	bg_check(act(w, c, s, &t, action_make("shoulder", farmer, pack, NO_ENTITY)))
	at := world_location_of(w, pack)
	bg_check(at.form == .Held_By && at.place == farmer && at.slot == BG_BACK && free_hands(w, farmer) == 2)

	/* fifteen kilograms of grain in it; another fifteen won't go */
	bg_check(act(w, c, s, &t, action_make("take", farmer, one, NO_ENTITY)))
	bg_check(act(w, c, s, &t, action_make("put_in", farmer, one, pack)))
	bg_check(world_location_of(w, one).form == .In && world_location_of(w, one).place == pack)
	bg_check(act(w, c, s, &t, action_make("take", farmer, two, NO_ENTITY)))
	act(w, c, s, &t, action_make("put_in", farmer, two, pack))
	bg_check(world_location_of(w, two).form == .Held_By)

	/* carried, thirty-one kilograms (the pack and its sack, the other sack
	 * in hand): sixteen past the light fifteen, a walk at 71% */
	bg_check(carried_mass(w, farmer) == 31000 && burdened_rate(w, farmer) == 100 * 40 / 56)
	error = ""
	bg_check(perform(w, c, action_make("walk_east", farmer, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(t + 1390))
	bg_check(world_location_of(w, farmer).x == 10)
	scheduler_run_until(s, time_make(t + 1420))
	bg_check(world_location_of(w, farmer).x == 11)
	g = proposal_group_group_with_phase(.System, "setup: the other sack put down")
	proposal_group_move_to(g, whole(two), on_tile(10, 11, 0))
	committer_submit(c, g)
	t += 1
	scheduler_run_until(s, time_make(t))
	t += 2000
	g = proposal_group_group_with_phase(.System, "setup: back beside the larder")
	proposal_group_move_to(g, whole(farmer), on_tile(10, 10, 0))
	committer_submit(c, g)
	t += 1
	scheduler_run_until(s, time_make(t))

	/* unpacked into the larder (taken out, put in); the pack put back
	 * beside it */
	bg_check(act(w, c, s, &t, action_make("take", farmer, one, NO_ENTITY)))
	bg_check(act(w, c, s, &t, action_make("put_in", farmer, one, larder)))
	bg_check(world_location_of(w, one).form == .In && world_location_of(w, one).place == larder)
	bg_check(act(w, c, s, &t, action_make("put_back", farmer, pack, larder)))
	at = world_location_of(w, pack)
	bg_check(at.form == .On_Tile && at.x == 9 && at.y == 10)

	/* a basket, in a hand: eight kilograms at most */
	bg_check(act(w, c, s, &t, action_make("take", farmer, basket, NO_ENTITY)))
	bg_check(free_hands(w, farmer) == 1)
	bg_check(act(w, c, s, &t, action_make("take", farmer, two, NO_ENTITY)))
	act(w, c, s, &t, action_make("put_in", farmer, two, basket))
	bg_check(world_location_of(w, two).form == .Held_By)
}

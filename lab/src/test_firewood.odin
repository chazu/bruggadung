package lab

/*
 * Firewood (VILLAGE.md slice 5, content/firewood/): a tree felled is a trunk
 * where it stood; a length cut off it is a log, the trunk shorter, and its
 * last length the trunk itself, cut through; a log split is firewood, a
 * stack of twenty pieces; stoked into a stove, its fuel by their mass.
 */

import "core:fmt"

test_firewood :: proc() {
	error: string
	v, lengths, fuel: i64

	w := test_world(105)
	why: string
	bg_check(world_set_terrain_map(w, "village_map", &why))
	c := test_committer(w)
	activities := activities_with_world(w, c)
	s := autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))

	g := proposal_group_group_with_phase(.System, "setup: a woodcutter, a birch, an axe, a stove")
	me    := proposal_group_create(g, "woodcutter", "me", on_tile(60, 21, 0))
	tree  := proposal_group_create(g, "birch", "a birch", on_tile(60, 20, 0))
	axe   := proposal_group_create(g, "axe", "the axe", held_by(me, 0))
	stove := proposal_group_create(g, "stove", "a stove", on_tile(61, 21, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	me, tree, axe, stove = proposal_group_id_for(g, me), proposal_group_id_for(g, tree), proposal_group_id_for(g, axe),
	                       proposal_group_id_for(g, stove)

	/* felled: the tree gone, a trunk of three lengths where it stood */
	bg_check(perform(w, c, action_make("fell", me, axe, tree), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1200 * 1000 + 1))
	bg_check(!world_is_live(w, tree))
	trunk := test_entity_at(w, "birch_trunk", 60, 20)
	bg_check(trunk != NO_ENTITY && world_get_field(w, "Trunk.lengths", trunk, &lengths) && lengths == 3)

	/* bucked twice: two logs, the trunk one length; a third time, it is cut
	 * through, the last log */
	for k in 0 ..< 3 {
		error = ""
		if perform(w, c, action_make("buck", me, axe, trunk), 0, &error) == nil do fmt.printf("    buck %d: %s\n", k, error)
		scheduler_run_until(s, time_make(world_time(w).ms + 360 * 1000))      /* a little slower, worn by the felling */
	}
	bg_check(world_get_field(w, "Trunk.lengths", trunk, &lengths) && lengths == 1)
	bg_check(world_get_field(w, "Log.sawn", trunk, &v) && v == 100)
	log := test_entity_at(w, "birch_log", 60, 20)
	bg_check(log != NO_ENTITY && world_get_field(w, "Log.sawn", log, &v) && v == 100)

	/* a log split: twenty pieces of firewood where it lay */
	error = ""
	bg_check(perform(w, c, action_make("split", me, axe, log), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 360 * 1000))
	bg_check(!world_is_live(w, log))
	wood := test_entity_at(w, "birch_firewood_20", 60, 20)
	bg_check(wood != NO_ENTITY && world_units_of(w, wood) == 20)

	/* six pieces stoked: the stove's fuel up by six kilograms */
	bg_check(perform(w, c, action_make("take_some", me, wood, NO_ENTITY), 6, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	held := NO_ENTITY
	hands: [2]Entity_ID
	for e in hands[:world_entities_at(w, me, .Held_By, raw_data(hands[:]), 2)] do if e != axe do held = e
	bg_check(held != NO_ENTITY && world_units_of(w, held) == 6)
	world_get_field(w, "FuelContainer.fuel", stove, &fuel)
	before := fuel
	bg_check(perform(w, c, action_make("stoke", me, held, stove), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 40 * 1000))
	bg_check(world_get_field(w, "FuelContainer.fuel", stove, &fuel) && fuel == before + 6000)
	bg_check(!world_is_live(w, held))
}



/* The live entity of a blueprint on a tile, or NO_ENTITY. */
test_entity_at :: proc(w: ^World, blueprint: string, x: i32, y: i32) -> Entity_ID {
	for e: Entity_ID = 1; e < 10000; e += 1 {
		info := world_info(w, e)
		if info == nil || !world_is_live(w, e) || string(info.blueprint) != blueprint do continue
		at := world_location_of(w, e)
		if at.form == .On_Tile && at.x == x && at.y == y do return e
	}
	return NO_ENTITY
}

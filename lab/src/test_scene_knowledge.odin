package lab

/*
 * Knowledge scenes (scene_knowledge.odin; TESSERA.md slice 2, VILLAGE.md
 * slice 11): a farmer's world as it knows it. It sees a sack beside it, and
 * never a basket across the field. Gone off, its scene still has the sack
 * where it left it after the sack is carried off unseen; back, it sees the
 * sack gone.
 */

import "../../tessera"


test_scene_knowledge :: proc() {
	w := test_world(117)
	why: string
	bg_check(world_set_terrain_map(w, "woods_map", &why))
	c := test_committer(w)
	activities := activities_with_world(w, c)
	knowledge  := autorelease(knowledge_init_with_world(w))
	s          := autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))

	g := proposal_group_group_with_phase(.System, "setup: a farmer, a sack beside it, a basket across the field")
	farmer := proposal_group_create(g, "farmer", "the farmer", on_tile(10, 10, 0))
	sack   := proposal_group_create(g, "grain_sack", "the sack", on_tile(11, 10, 0))
	stone  := proposal_group_create(g, "basket", "the basket", on_tile(30, 10, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1000))
	farmer, sack, stone = proposal_group_id_for(g, farmer), proposal_group_id_for(g, sack), proposal_group_id_for(g, stone)
	store := knowledge_store_of(knowledge, farmer)
	extent := tessera.Extent{x0 = 0, y0 = 0, w = 40, h = 24, z0 = 0, z1 = 0, focus = 0}

	/* itself, the sack in sight; tiles never seen blank */
	k := scene_knowledge(knowledge, farmer, extent, 1, context.temp_allocator)
	bg_check(k != nil && k.meta.view == .Knowledge && k.meta.viewer == u64(farmer))
	if k == nil do return
	me := tessera.mark_find(k, u64(knowledge_store_self_referent(store)))
	bg_check(me != nil && me.x == 10 && me.y == 10 && .Actor in me.flags)
	known := test_scene_knowledge_referent(store, sack)
	m := tessera.mark_find(k, u64(known)) if known != 0 else nil
	bg_check(m != nil && m.x == 11 && m.y == 10 && .In_Sight in m.flags && .Gone not_in m.flags)
	bg_check(test_scene_knowledge_referent(store, stone) == 0)
	here := tessera.cell_at(k, 10, 10, 0)
	bg_check(here.seen == world_time(w).ms && .In_Sight in here.flags && here.terrain != 0)
	bg_check(tessera.cell_at(k, 30, 10, 0).seen == -1)

	/* gone off: the sack is where it left it, though it has been carried off */
	g = proposal_group_group_with_phase(.System, "setup: the farmer across the field")
	proposal_group_move_to(g, whole(farmer), on_tile(25, 20, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(2000))
	g = proposal_group_group_with_phase(.System, "setup: the sack carried off, unseen")
	proposal_group_move_to(g, whole(sack), on_tile(38, 20, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(3000))
	k = scene_knowledge(knowledge, farmer, extent, 2, context.temp_allocator)
	m = tessera.mark_find(k, u64(known))
	bg_check(m != nil && m.x == 11 && m.y == 10 && .Gone not_in m.flags && .In_Sight not_in m.flags)
	bg_check(.In_Sight not_in tessera.cell_at(k, 11, 10, 0).flags)

	/* back: gone from where it was */
	g = proposal_group_group_with_phase(.System, "setup: the farmer back")
	proposal_group_move_to(g, whole(farmer), on_tile(10, 10, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(4000))
	k = scene_knowledge(knowledge, farmer, extent, 3, context.temp_allocator)
	m = tessera.mark_find(k, u64(known))
	bg_check(m != nil && m.x == 11 && m.y == 10 && .Gone in m.flags && .In_Sight not_in m.flags)
}


/* The referent of the entity in the store; 0 if it hasn't one. */
@(private = "file")
test_scene_knowledge_referent :: proc(store: ^Knowledge_Store, e: Entity_ID) -> u32 {
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		if knowledge_store_referent_at(store, i).truth == e do return knowledge_store_referent_at(store, i).id
	}
	return 0
}

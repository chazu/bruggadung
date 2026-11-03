package lab

/*
 * Looks (TESSERA.md decision 6, looks.odin): a thing looks as the most
 * specific kind it is with a look; a kind several at once as the look that
 * prevails; a theme draws a look by its name or its family. Every physical
 * thing in the lab's worlds has a look the watcher's theme draws.
 */

test_looks :: proc() {
	h: [8]Entity_ID

	w := test_world(1)
	/* by type, up the parents: a lock is an assembly, a lodger an agent */
	bg_check(look_of_kind(w, "#Assembly") == "assembly" && look_of_kind(w, "#Agent") == "agent")
	bg_check(look_of_kind(w, "#Tap") == "tap" && look_of_kind(w, "#Bed") == "bed")
	bg_check(look_of_kind(w, "#Stove") == "stove" && look_of_kind(w, "#Body") == "body")
	/* several at once: an assembly over a water store, a water store over a
	 * body, an agent over all */
	bg_check(look_of_kind(w, "#Thing & #Assembly & #WaterStore") == "assembly")
	bg_check(look_of_kind(w, "#Thing & #Body & #WaterStore") == "water.store")
	bg_check(look_of_kind(w, "#Thing & #Container & #WaterStore") == "water.store")
	bg_check(look_of_kind(w, "#Nonesuch") == "")

	/* a blueprint's own look first: a farmer, a scarecrow */
	c := test_committer(w)
	bg_check(look_of_entity(w, test_commit_create(c, "farmer", on_tile(1, 1, 0))) == "agent.farmer")
	bg_check(look_of_entity(w, test_commit_create(c, "scarecrow", on_tile(2, 1, 0))) == "worksite.scarecrow")
	bg_check(look_of_entity(w, test_commit_create(c, "bed", on_tile(3, 1, 0))) == "bed")

	/* themes: by name, then by family; the text theme has `lab play`'s map */
	tc    := world_tri(w)
	text  := looks_glyphs(tc, "text", context.temp_allocator)
	tiles := looks_glyphs(tc, "tiles", context.temp_allocator)
	a, ok1 := glyph_for(text, "agent.farmer")
	f, ok2 := glyph_for(tiles, "agent.farmer")
	bg_check(ok1 && a.char == 'A' && ok2 && f.char == '@' && f.ink != a.ink)
	wall, ok3 := glyph_for(tiles, "wall.stone")
	bg_check(ok3 && wall.char == '#' && wall.has_ground)
	woods, ok4 := glyph_for(tiles, "ground.woodland")
	bg_check(ok4 && woods.char == '"')               /* the escaped quote, undone */
	_, ok5 := glyph_for(tiles, "nonesuch")
	bg_check(!ok5)

	/* every physical thing in the workshop, the cistern and the village has
	 * a look the tiles theme draws, and so does every terrain kind */
	worlds := [3]^World{test_world(2), test_world(3), test_world(101)}
	for setup, i in ([2]^Proposal_Group{workshop_setup(true, &h), cistern_setup(&h)}) {
		wc := test_committer(worlds[i])
		committer_submit(wc, setup)
		committer_commit_boundary(wc)
		bg_check(proposal_group_applied(setup))
	}
	things := 0
	village := autorelease(village_init_with_world(worlds[2], test_committer(worlds[2])))
	bg_check(village_error(village) == "")
	for v in worlds {
		body := world_kind_named(v, "Body")
		for i: u64 = 1; i < u64(world_next_id(v)); i += 1 {
			if world_record(v, body, Entity_ID(i)) == nil do continue
			look := look_of_entity(v, Entity_ID(i))
			_, drawn := glyph_for(tiles, look)
			bg_check(look != "" && look != "body" && drawn)
			things += 1
		}
		t := world_terrain(v)
		for k: uint = 1; t != nil && k <= terrain_kind_count(t); k += 1 {
			_, drawn := glyph_for(tiles, string(terrain_kind_info(t, Terrain_Kind(k)).look))
			bg_check(drawn)
		}
	}
	bg_check(things >= 5 + 6 + 12 + 16 + 4)    /* the workshop's, the cistern's, the village's people, beds, things */
}

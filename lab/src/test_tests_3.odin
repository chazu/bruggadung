package lab

// The lab's tests, part 3 of 3 (test/BGTests.m from test_spatial_index to
// the end): the spatial index, water and the reality bubble, paths,
// talking, routines, the nut of unknown size, the seized valve, the
// interrupted repair, the unattended stove, the body's needs, partial
// effects, attention, laws, traces, memory, light and sound, the cistern,
// saves; and the table of every test, ALL_TESTS.
//
// The split's rules (helpers are package-level, named test_<C name>):
// three helpers here would take a test's own name, and keep `_run` after it:
// cold_lodger → test_cold_lodger_run, stuffy_lodger → test_stuffy_lodger_run,
// habitual_belief → test_habitual_belief_run.

import "core:fmt"
import "core:slice"
import "core:strings"
import tri "../../triangle/odin/triangle"


test_spatial_index :: proc() {
	st: Stage
	g: ^Proposal_Group
	crates: [40]Entity_ID
	box: Entity_ID
	worker: Entity_ID
	found: [64]Entity_ID
	w2: ^World
	deferred: []^Proposal_Group
	error: string
	text: string
	position: u64

	st.w = test_world(191)
	st.c = test_committer(st.w)
	st.s = autorelease(scheduler_init_with_world(st.w, st.c))
	g    = proposal_group_group_with_phase(.System, "setup: crates about")
	for i: i32 = 0; i < 40; i += 1 {
		crates[i] = proposal_group_create(g, "crate", ns_utf8(fmt.tprintf("crate %d", i)),
		                                  on_tile((i * 7) % 32, (i * 13) % 32, 0))
	}
	box    = proposal_group_create(g, "crate", "a crate to hold", on_tile(31, 31, 0))
	worker = proposal_group_create(g, "worker", "worker", on_tile(25, 25, 0))
	for i: i32 = 0; i < 12; i += 1 {
		make_trace(st.w, g, "scuffs", NO_ENTITY, on_tile((i * 11) % 60, (i * 17) % 60, 0), 50, "the test")
	}
	make_trace(st.w, g, "scuffs", box, on_tile(31, 31, 0), 50, "the test")
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	for i := 0; i < 40; i += 1 {
		crates[i] = proposal_group_id_for(g, crates[i])
	}
	box    = proposal_group_id_for(g, box)
	worker = proposal_group_id_for(g, worker)
	bg_check(test_index_agrees(st.w) && test_traces_agree(st.w))

	/* across the corner of four chunks: a crate at (31, 31) and the one at (0, 0) */
	bg_check(world_entities_near(st.w, on_tile(31, 31, 0), 1, &found[0], 64) == 1 && found[0] == box)
	bg_check(world_entities_on_tile(st.w, on_tile(0, 0, 0), &found[0], 64) == 2 && found[0] == crates[0] &&
	         found[1] == crates[32])

	/* moved about, and one taken up */
	g = proposal_group_group_with_phase(.System, "crates moved")
	for i: i32 = 0; i < 40; i += 3 {
		proposal_group_move_to(g, whole(crates[i]), on_tile((i * 5 + 3) % 32, (i * 11 + 1) % 32, 0))
	}
	proposal_group_move_to(g, whole(box), held_by(worker, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(2))
	bg_check(proposal_group_applied(g) && test_index_agrees(st.w) && test_traces_agree(st.w))
	bg_check(world_entities_at(st.w, worker, .Held_By, &found[0], 64) == 1 && found[0] == box)
	bg_check(world_entities_near(st.w, on_tile(31, 31, 0), 0, &found[0], 64) == 0)

	/* a group refused: its moves undone, and the index with them */
	g = proposal_group_group_with_phase(.System, "a move refused")
	proposal_group_move_to(g, whole(crates[1]), on_tile(20, 20, 0))
	proposal_group_move_to(g, whole(crates[2]), on_tile(21, 20, 0))
	proposal_group_set_of_to(g, "Door.ajar", whole(crates[3]), 1)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(3))
	bg_check(!proposal_group_applied(g) && test_index_agrees(st.w) && test_traces_agree(st.w))

	/* saved and restored: built again from the locations */
	text = save(st.w, st.c, nil)
	w2   = restore(text, world_content_build(st.w), &deferred, &position, &error)
	bg_check(w2 != nil && test_index_agrees(w2) && test_traces_agree(w2))
}


/* TERRAIN.md, water past 32 by 32: on a yard 96 by 64, a puddle poured at
 * (68, 50) spreads west across hundreds of tiles, past where the domain's
 * old cap of 448 would have frozen it, and east not at all, past a wall
 * built down the yard at x 70; the water is all there, every boundary; and
 * saved, only the wet tiles are written. */
test_water_at_scale :: proc() {
	st: Stage
	fluid: ^Fluid_Domain
	g: ^Proposal_Group
	text: string
	x: i32
	y: i32
	wet: int
	conserved: bool

	st.w  = test_world(193)
	bg_check(world_set_terrain_map(st.w, "yard_map", nil))
	bg_check(world_tiles_wide(st.w) == 96 && world_tiles_high(st.w) == 64)
	st.c  = test_committer(st.w)
	fluid = autorelease(fluid_domain_init_with_world(st.w))
	st.s  = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_add_domain(st.s, fluid_domain_as_domain(fluid))
	g = proposal_group_group_with_phase(.System, "setup: a wall across the yard")
	for y = 0; y < 64; y += 1 {
		proposal_group_set_terrain(g, "stone_wall", on_tile(70, y, 0))
	}
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	bg_check(proposal_group_applied(g))
	world_set_water(st.w, 40000, 68, 50, 0)
	conserved = true
	for scheduler_step_until(st.s, time_make(3600000)) {
		conserved = conserved && world_total_tile_water(st.w) + fluid_domain_checked_out_water(fluid) == 40000
	}
	bg_check(conserved && world_total_tile_water(st.w) + fluid_domain_checked_out_water(fluid) == 40000)
	for wet, y = 0, 0; y < 64; y += 1 {
		for x = 71; x < 96; x += 1 {
			wet += 1 if world_water_at_x(st.w, x, y, 0) != 0 else 0
		}
	}
	bg_check(wet == 0 && world_wet_tiles(st.w, nil, 0) > 448 && world_water_at_x(st.w, 50, 50, 0) > 0)
	text = save(st.w, st.c, nil)
	bg_check(uint(len(ns_components_separated(text, "\ntile "))) - 1 == world_wet_tiles(st.w, nil, 0))
}


/* REALITY.md decision 7: work when something happens. On the yard, a
 * worker walks east; a watcher beside its path perceives it as it passes,
 * and decides; one far off, nothing concerning it, perceives once (to
 * begin) and rests, and its mind with it. A sound loud enough to carry
 * reaches it, and it looks. */
test_work_when_touched :: proc() {
	st: Stage
	activities: ^Activities
	knowledge: ^Knowledge
	agency: ^Agency
	g: ^Proposal_Group
	walker: Entity_ID
	near: Entity_ID
	far: Entity_ID
	error: string
	farSeen: i64
	farDecided: u64

	st.w = test_world(197)
	bg_check(world_set_terrain_map(st.w, "yard_map", nil))
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g      = proposal_group_group_with_phase(.System, "setup: a walker, a watcher, one far off")
	walker = proposal_group_create(g, "worker", "walker", on_tile(5, 10, 0))
	near   = proposal_group_create(g, "watchman", "watcher", on_tile(10, 12, 0))
	far    = proposal_group_create(g, "watchman", "far off", on_tile(80, 50, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	walker = proposal_group_id_for(g, walker)
	near   = proposal_group_id_for(g, near)
	far    = proposal_group_id_for(g, far)
	agency_control(agency, near)
	agency_control(agency, far)
	scheduler_run_until(st.s, time_make(1000))
	farSeen    = knowledge_store_of(knowledge, far).perceivedAt
	farDecided = agency_mind_of(agency, far).decisions
	bg_check(farSeen >= 0)

	for i := 0; i < 10; i += 1 {
		error = ""
		bg_check(perform(st.w, st.c, action_make("walk_east", walker, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1500))
	}
	bg_check(world_location_of(st.w, walker).x == 15)
	/* the watcher saw it go by, as far as it could see: four tiles, to 14 */
	bg_check(knowledge_store_of(knowledge, near).perceivedAt > 10000 &&
	         knowledge_store_referent(knowledge_store_of(knowledge, near),
	                                  test_referent_of(knowledge_store_of(knowledge, near), walker)).x == 14)
	/* the one far off rested throughout */
	bg_check(knowledge_store_of(knowledge, far).perceivedAt == farSeen && agency_mind_of(agency, far).decisions == farDecided)

	/* a clatter loud enough to carry thirty tiles reaches it */
	g = proposal_group_group_with_phase(.System, "setup: something falls, far off")
	make_trace(st.w, g, "clatter", NO_ENTITY, on_tile(80, 30, 0), 100, "a falling tin")
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 100))
	bg_check(knowledge_store_of(knowledge, far).perceivedAt > farSeen)
}


/* REALITY.md step 2: the reality bubble. No anchors, all is full. A
 * player anchors it: full a chunk round, reduced four, abstract sixteen,
 * frozen past, levels up and down as content says. Its centre stays
 * while it is within its margin of its chunk, and follows past it. A word
 * from it to someone at reduced detail leases them full, until the lease
 * runs out. Anchors and leases are saved. */
test_reality_bubble :: proc() {
	st: Stage
	g: ^Proposal_Group
	player: Entity_ID
	far: Entity_ID
	w2: ^World
	deferred: []^Proposal_Group
	error: string
	text: string
	position: u64
	cx: i32
	cy: i32
	cz: i32

	st.w = test_world(199)
	bg_check(world_set_terrain_map(st.w, "plain_map", nil))
	st.c = test_committer(st.w)
	st.s = autorelease(scheduler_init_with_world(st.w, st.c))
	g      = proposal_group_group_with_phase(.System, "setup: a player, and someone further off")
	player = proposal_group_create(g, "worker", "player", on_tile(100, 100, 0))
	far    = proposal_group_create(g, "worker", "far off", on_tile(100 + 2 * 32, 100, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	player = proposal_group_id_for(g, player)
	far    = proposal_group_id_for(g, far)

	/* no anchors: everything is full */
	bg_check(world_detail_at(st.w, on_tile(1000, 1000, 0)) == i32(Detail.Full) && world_detail_of(st.w, far) == i32(Detail.Full))

	/* the player anchors it, centred on its chunk, (3, 3), at the next boundary */
	bg_check(world_set_anchor(st.w, player, "player") && !world_set_anchor(st.w, player, "nonesuch"))
	scheduler_run_until(st.s, time_make(2))
	bg_check(reality_anchor_at(world_reality(st.w), 0, nil, &cx, &cy, &cz, nil) == player && cx == 3 && cy == 3 && cz == 0)
	bg_check(world_detail_at(st.w, on_tile(100, 100, 0)) == i32(Detail.Full) &&
	         world_detail_at(st.w, on_tile(100 + 32, 100 - 32, 0)) == i32(Detail.Full) &&
	         world_detail_at(st.w, on_tile(100 + 2 * 32, 100, 0)) == i32(Detail.Reduced) &&
	         world_detail_at(st.w, on_tile(100, 100 + 4 * 32, 0)) == i32(Detail.Reduced) &&
	         world_detail_at(st.w, on_tile(100 + 5 * 32, 100, 0)) == i32(Detail.Abstract) &&
	         world_detail_at(st.w, on_tile(100 + 16 * 32, 100, 0)) == i32(Detail.Abstract) &&
	         world_detail_at(st.w, on_tile(100 + 17 * 32, 100, 0)) == i32(Detail.Frozen))
	/* a level up: full; three up, reduced past its two; five, abstract past four */
	bg_check(world_detail_at(st.w, on_tile(100, 100, 1)) == i32(Detail.Full) && world_detail_at(st.w, on_tile(100, 100, 3)) == i32(Detail.Abstract) &&
	         world_detail_at(st.w, on_tile(100, 100, 5)) == i32(Detail.Frozen))
	bg_check(world_detail_of(st.w, far) == i32(Detail.Reduced) && world_detail_of(st.w, player) == i32(Detail.Full))

	/* across its chunk's edge, within the margin (4 tiles): the centre stays */
	g = proposal_group_group_with_phase(.System, "setup: the player steps out of its chunk")
	proposal_group_move_to(g, whole(player), on_tile(4 * 32 + 3, 100, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(3))
	reality_anchor_at(world_reality(st.w), 0, nil, &cx, &cy, &cz, nil)
	bg_check(cx == 3 && world_detail_of(st.w, far) == i32(Detail.Reduced))
	/* past it: the centre follows, and the one further off is nearer now */
	g = proposal_group_group_with_phase(.System, "setup: the player goes on")
	proposal_group_move_to(g, whole(player), on_tile(4 * 32 + 5, 100, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(4))
	reality_anchor_at(world_reality(st.w), 0, nil, &cx, &cy, &cz, nil)
	bg_check(cx == 4 && cy == 3 && world_detail_of(st.w, far) == i32(Detail.Full))
	g = proposal_group_group_with_phase(.System, "setup: back again")
	proposal_group_move_to(g, whole(player), on_tile(100, 100, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(5))
	bg_check(world_detail_of(st.w, far) == i32(Detail.Reduced))

	/* a word from the player to the one further off: contact, a lease */
	g = proposal_group_group_with_phase(.Action, "the player calls out")
	proposal_group_set_actor(g, player)
	proposal_group_emit_subject_other(g, "said", whole(player), whole(far))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(6))
	bg_check(world_detail_of(st.w, far) == i32(Detail.Full) && reality_lease_of(world_reality(st.w), far) == 6 + 60000)
	/* not every event is contact: a look isn't */
	bg_check(!reality_is_contact(world_reality(st.w), "looked") && reality_is_contact(world_reality(st.w), "struck"))

	/* saved, and restored, the same */
	text = save(st.w, st.c, nil)
	bg_check(ns_contains(text, "\nanchor ") && ns_contains(text, "\nlease "))
	w2 = restore(text, world_content_build(st.w), &deferred, &position, &error)
	bg_check(w2 != nil && world_state_hash(w2) == world_state_hash(st.w) && world_detail_of(w2, far) == i32(Detail.Full))

	/* the lease runs out: reduced again, and let go */
	scheduler_run_until(st.s, time_make(70000))
	bg_check(world_detail_of(st.w, far) == i32(Detail.Reduced) && reality_lease_count(world_reality(st.w)) == 0)
	/* no anchor left: all full again */
	world_remove_anchor(st.w, player)
	bg_check(world_detail_of(st.w, far) == i32(Detail.Full) && world_detail_at(st.w, on_tile(1000, 1000, 0)) == i32(Detail.Full))
}


/* REALITY.md step 3: reduced detail. A player anchors the plain; a walker
 * goes by two watchers, one at full detail beside the player, one three
 * chunks off at reduced. The one at full sees it pass; the one at reduced,
 * whose senses reach only what it takes part in, doesn't look up; walking
 * itself, a reduced agent walks as fast; and what it would wake for by
 * itself falls on the cadence's beat, ten seconds. A word from the player
 * leases it full, and then it hears. */
test_reduced_detail :: proc() {
	st: Stage
	activities: ^Activities
	knowledge: ^Knowledge
	agency: ^Agency
	g: ^Proposal_Group
	player: Entity_ID
	nearWatcher: Entity_ID
	farWatcher: Entity_ID
	nearWalker: Entity_ID
	farWalker: Entity_ID
	error: string
	nearSeen: i64
	farSeen: i64

	st.w = test_world(223)
	bg_check(world_set_terrain_map(st.w, "plain_map", nil))
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g           = proposal_group_group_with_phase(.System, "setup: a player, watchers, walkers")
	player      = proposal_group_create(g, "worker", "player", on_tile(100, 100, 0))
	nearWatcher = proposal_group_create(g, "watchman", "near watcher", on_tile(104, 104, 0))
	nearWalker  = proposal_group_create(g, "worker", "near walker", on_tile(100, 106, 0))
	farWatcher  = proposal_group_create(g, "watchman", "far watcher", on_tile(100 + 3 * 32, 104, 0))
	farWalker   = proposal_group_create(g, "worker", "far walker", on_tile(100 + 3 * 32 - 4, 106, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	player      = proposal_group_id_for(g, player)
	nearWatcher = proposal_group_id_for(g, nearWatcher)
	nearWalker  = proposal_group_id_for(g, nearWalker)
	farWatcher  = proposal_group_id_for(g, farWatcher)
	farWalker   = proposal_group_id_for(g, farWalker)
	bg_check(world_set_anchor(st.w, player, "player"))
	scheduler_run_until(st.s, time_make(1000))
	bg_check(world_detail_of(st.w, nearWatcher) == i32(Detail.Full) && world_detail_of(st.w, farWatcher) == i32(Detail.Reduced))
	nearSeen = knowledge_store_of(knowledge, nearWatcher).perceivedAt
	farSeen  = knowledge_store_of(knowledge, farWatcher).perceivedAt

	/* each walker goes by its watcher, eight steps */
	for i := 0; i < 8; i += 1 {
		error = ""
		bg_check(perform(st.w, st.c, action_make("walk_east", nearWalker, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
		bg_check(perform(st.w, st.c, action_make("walk_east", farWalker, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1500))
	}
	/* walking at reduced detail, as fast */
	bg_check(world_location_of(st.w, nearWalker).x == 108 && world_location_of(st.w, farWalker).x == 100 + 3 * 32 + 4)
	/* the watcher at full saw the walker go by; the one at reduced didn't look */
	bg_check(knowledge_store_of(knowledge, nearWatcher).perceivedAt > nearSeen)
	bg_check(knowledge_store_of(knowledge, farWatcher).perceivedAt == farSeen)
	/* and what it would wake for, by itself, falls on the beat */
	bg_check(knowledge_store_of(knowledge, farWatcher).perceiveBy == max(i64) ||
	         knowledge_store_of(knowledge, farWatcher).perceiveBy % 10000 == 0)

	/* a word from the player: leased full, it hears */
	g = proposal_group_group_with_phase(.Action, "the player calls out")
	proposal_group_set_actor(g, player)
	proposal_group_emit_subject_other(g, "said", whole(player), whole(farWatcher))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 100))
	bg_check(world_detail_of(st.w, farWatcher) == i32(Detail.Full) && knowledge_store_of(knowledge, farWatcher).perceivedAt > farSeen)
}


/* REALITY.md step 4: frozen. A distant anchor (full nowhere but its chunk,
 * abstract eight chunks round) on the plain; a worker ten chunks off sets
 * out to walk a tile. Frozen, nothing runs: a minute on, it hasn't moved,
 * nor looked, nor decided. The anchor comes nearer, and it rises: its walk,
 * long due, ends at once, and it looks. Another, frozen, hears a word from
 * the anchor: contact raises it, and it looks. */
test_frozen_detail :: proc() {
	st: Stage
	activities: ^Activities
	knowledge: ^Knowledge
	agency: ^Agency
	g: ^Proposal_Group
	anchor: Entity_ID
	walker: Entity_ID
	sleeper: Entity_ID
	error: string
	seen: i64
	sleeperSeen: i64
	decided: u64

	st.w = test_world(227)
	bg_check(world_set_terrain_map(st.w, "plain_map", nil))
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g       = proposal_group_group_with_phase(.System, "setup: an anchor, and two far off")
	anchor  = proposal_group_create(g, "worker", "anchor", on_tile(100, 100, 0))
	walker  = proposal_group_create(g, "worker", "walker", on_tile(100 + 10 * 32, 100, 0))
	sleeper = proposal_group_create(g, "watchman", "sleeper", on_tile(100 + 20 * 32, 100, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	anchor  = proposal_group_id_for(g, anchor)
	walker  = proposal_group_id_for(g, walker)
	sleeper = proposal_group_id_for(g, sleeper)
	agency_control(agency, walker)
	scheduler_run_until(st.s, time_make(500))
	bg_check(world_set_anchor(st.w, anchor, "distant"))
	scheduler_run_until(st.s, time_make(1000))
	bg_check(world_detail_of(st.w, walker) == i32(Detail.Frozen) && world_detail_of(st.w, sleeper) == i32(Detail.Frozen) &&
	         world_detail_of(st.w, anchor) == i32(Detail.Full))

	/* frozen, it sets out, and nothing runs: a minute on, where it was */
	error = ""
	bg_check(perform(st.w, st.c, action_make("walk_east", walker, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(2000))
	seen    = knowledge_store_of(knowledge, walker).perceivedAt
	decided = agency_mind_of(agency, walker).decisions
	scheduler_run_until(st.s, time_make(62000))
	bg_check(world_location_of(st.w, walker).x == 100 + 10 * 32)
	bg_check(knowledge_store_of(knowledge, walker).perceivedAt == seen && agency_mind_of(agency, walker).decisions == decided)

	/* the anchor comes within eight chunks: it rises, its walk ends, it looks */
	g = proposal_group_group_with_phase(.System, "setup: the anchor comes nearer")
	proposal_group_move_to(g, whole(anchor), on_tile(100 + 4 * 32, 100, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(62100))
	bg_check(world_detail_of(st.w, walker) != i32(Detail.Frozen))
	bg_check(knowledge_store_of(knowledge, walker).perceivedAt > seen)
	scheduler_run_until(st.s, time_make(62500))
	bg_check(world_location_of(st.w, walker).x == 100 + 10 * 32 + 1)

	/* the sleeper, still frozen, hears a word from the anchor: it rises */
	bg_check(world_detail_of(st.w, sleeper) == i32(Detail.Frozen))
	sleeperSeen = knowledge_store_of(knowledge, sleeper).perceivedAt
	g = proposal_group_group_with_phase(.Action, "the anchor calls out")
	proposal_group_set_actor(g, anchor)
	proposal_group_emit_subject_other(g, "said", whole(anchor), whole(sleeper))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(62600))
	bg_check(world_detail_of(st.w, sleeper) == i32(Detail.Full) && knowledge_store_of(knowledge, sleeper).perceivedAt > sleeperSeen)
}


/* A grid for BGPath, from rows of '#' (walls) and anything else. */
Test_Grid :: struct {
	rows: [^]cstring,
	high: i32,
}

test_grid_open :: proc(context_: rawptr, x: i32, y: i32) -> bool {
	g: ^Test_Grid

	g = (^Test_Grid)(context_)
	return y >= 0 && y < g.high && x >= 0 && x < i32(len(g.rows[y])) && ([^]u8)(g.rows[y])[x] != '#'
}


test_everywhere :: proc(context_: rawptr, x: i32, y: i32) -> bool {
	return true
}


test_at_star :: proc(context_: rawptr, x: i32, y: i32) -> bool {
	g: ^Test_Grid

	g = (^Test_Grid)(context_)
	return test_grid_open(context_, x, y) && ([^]u8)(g.rows[y])[x] == '*'
}


/* BGPath: the shortest way through a maze, step by step, never into a
 * wall; breadth-first to the nearest of what it looks for; no way out of a
 * box, the nearest it came; and bounded, the same few thousand tiles in an
 * endless plain. */
test_paths :: proc() {
	maze := [?]cstring{"#########",
	                   "#...#...#",
	                   "#.#.#.#.#",
	                   "#.#...#.#",
	                   "#########"}
	box := [?]cstring{"#####.....",
	                  "#...#.....",
	                  "#####....."}
	seek := [?]cstring{"..........",
	                   "....#.....",
	                   "..*.#...*."}
	grid: Test_Grid
	q: Path_Query
	r: Path_Result
	first: Path_Result
	walked: i64
	clear: bool

	/* the maze: from (1, 1) to beside (7, 1), round the walls, not into
	 * the dead end below */
	grid.rows  = &maze[0]
	grid.high  = 5
	q          = {}
	q.x        = 1
	q.y        = 1
	q.targeted = true
	q.tx       = 7
	q.ty       = 1
	q.context_ = &grid
	q.passable = test_grid_open
	first      = path_find(&q)
	bg_check(first.found && first.step == .East && first.steps == 9)
	for walked, clear = 0, true; walked < 20; walked += 1 {
		r = path_find(&q)
		if r.step == .None {
			break
		}
		q.x += 1 if r.step == .East else -1 if r.step == .West else 0
		q.y += 1 if r.step == .South else -1 if r.step == .North else 0
		clear = clear && test_grid_open(&grid, q.x, q.y)
	}
	bg_check(clear && walked == first.steps && abs(q.x - 7) <= 1 && abs(q.y - 1) <= 1)

	/* shut in a box: no way, but the nearest it came */
	grid.rows = &box[0]
	grid.high = 3
	q.x  = 1
	q.y  = 1
	q.tx = 9
	q.ty = 1
	r    = path_find(&q)
	bg_check(!r.found && r.x == 3 && r.y == 1 && r.step == .East)

	/* looking, not going: the nearest '*' by steps, round the wall */
	grid.rows  = &seek[0]
	q.targeted = false
	q.goal     = test_at_star
	q.x        = 6
	q.y        = 2
	r          = path_find(&q)
	bg_check(r.found && r.x == 8 && r.y == 2 && r.steps == 2 && r.step == .East)
	q.x = 5
	r   = path_find(&q)
	bg_check(r.found && r.x == 8 && r.steps == 3)          /* (2, 2) is 7 round the wall */

	/* an endless plain, the target a million tiles off: bounded, and toward it */
	q          = {}
	q.targeted = true
	q.tx       = 1000000
	q.ty       = 7
	q.passable = test_everywhere
	r          = path_find(&q)
	bg_check(!r.found && r.expanded <= BG_PATH_BUDGET && (r.step == .East || r.step == .South) &&
	         r.x > 4000)
}


/* Talking takes time (ACTIONS.md §5, AGENCY.md §11: conversations are
 * communicate activities): a remark is a second on the voice, the words
 * said when it ends. Walking while talking works; a second remark at once
 * doesn't, its voice taken; once said, it can speak again. */
test_talking_takes_time :: proc() {
	st: Stage
	g: ^Proposal_Group
	worker: Entity_ID
	smith: Entity_ID
	say: Action
	error: string
	said: uint
	when_: i64      // `when` is Odin's keyword

	st.w   = test_world(173)
	st.c   = test_committer(st.w)
	st.s   = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	g      = proposal_group_group_with_phase(.System, "setup: two in the yard")
	worker = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	smith  = proposal_group_create(g, "smith", "smith", on_tile(6, 5, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	smith  = proposal_group_id_for(g, smith)

	error       = ""
	say         = action_make("say", worker, smith, NO_ENTITY)
	say.content = world_intern(st.w, "#Here & {}")
	bg_check(perform(st.w, st.c, say, 0, &error) != nil)
	when_ = world_time(st.w).ms
	bg_check(perform(st.w, st.c, action_make("walk_south", worker, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	bg_check(perform(st.w, st.c, say, 0, &error) == nil)
	bg_check(error == "its voice is taken by say, starting")

	/* not said yet half a second in; said, with its words, at the second */
	scheduler_run_until(st.s, time_make(when_ + 500))
	said = 0
	for i: uint = 0; i < world_event_count(st.w); i += 1 {
		if string(world_event_at(st.w, i).kind) == "said" {
			said += 1
		}
	}
	bg_check(said == 0)
	scheduler_run_until(st.s, time_make(when_ + 1001))
	for i: uint = 0; i < world_event_count(st.w); i += 1 {
		if string(world_event_at(st.w, i).kind) == "said" {
			said += 1
			bg_check(string(world_event_at(st.w, i).detail) == "#Here & {}" && world_event_at(st.w, i).actor == worker &&
			         world_event_at(st.w, i).other == smith)
		}
	}
	bg_check(said == 1)
	/* and it walked meanwhile */
	bg_check(world_location_of(st.w, worker).y == 6)
	error = ""
	bg_check(perform(st.w, st.c, say, 0, &error) != nil)
}


/* AGENCY.md §8: a routine is built from commitments "with time windows (a
 * shift from 8 to 16)", every day. Oskar is to tighten the nut each day
 * between 60 s and 120 s past midnight: on day one he does; someone
 * loosens it overnight; on day two, in its window and not before, he does
 * again. Saved, it recurs. */
test_daily_commitment :: proc() {
	st: Stage
	activities: ^Activities
	knowledge: ^Knowledge
	agency: ^Agency
	g: ^Proposal_Group
	worker: Entity_ID
	nut: Entity_ID
	text: string
	v: i64
	day: i64

	day        = 86400000
	st.w       = test_world(71)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g      = proposal_group_group_with_phase(.System, "setup: the pump")
	worker = proposal_group_create(g, "worker", "Oskar", on_tile(5, 2, 0))
	proposal_group_create(g, "spanner_19", "spanner", held_by(worker, 0))
	nut    = proposal_group_create(g, "gland_nut", "gland nut", on_tile(6, 2, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	nut    = proposal_group_id_for(g, nut)
	bg_check(!agency_undertake_goal_from_until_source_every(agency, worker, "tighten_nut", 60000, 120000, "employment", 30000))
	bg_check(agency_undertake_goal_from_until_source_every(agency, worker, "tighten_nut", 60000, 120000, "employment", day))
	agency_control(agency, worker)

	/* day one */
	scheduler_run_until(st.s, time_make(120000))
	bg_check(world_get_field(st.w, "Fastener.tight", nut, &v) && v != 0)
	/* overnight, someone loosens it */
	scheduler_run_until(st.s, time_make(day / 2))
	g = proposal_group_group_with_phase(.System, "setup: someone loosens it")
	proposal_group_set_of_to(g, "Fastener.tight", whole(nut), 0)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(day + 59000))
	text = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	bg_check(ns_contains(text, "recurs "))
	bg_check(world_get_field(st.w, "Fastener.tight", nut, &v) && v == 0)
	/* day two, in its window */
	scheduler_run_until(st.s, time_make(day + 120000))
	bg_check(test_logged_by(agency, worker, "t=86460000ms [tighten the nut] tighten it"))
	bg_check(world_get_field(st.w, "Fastener.tight", nut, &v) && v != 0)
}


/* AGENCY.md §14, autopilot "continue my routine": the player hands Oskar,
 * beside the nut with a spanner, to agency from the start, past a
 * threshold of 10; his shift has him tighten the nut between 60 s and
 * 120 s. He waits for it, control not returning; at 60 s he takes it up,
 * worth more than the threshold (it is his routine); done, his routine is
 * done, and control returns. */
test_routine_autopilot :: proc() {
	st: Stage
	activities: ^Activities
	knowledge: ^Knowledge
	agency: ^Agency
	g: ^Proposal_Group
	worker: Entity_ID
	nut: Entity_ID
	notices: []string
	v: i64

	st.w       = test_world(71)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g      = proposal_group_group_with_phase(.System, "setup: the pump")
	worker = proposal_group_create(g, "worker", "Oskar", on_tile(5, 2, 0))
	proposal_group_create(g, "spanner_19", "spanner", held_by(worker, 0))
	nut    = proposal_group_create(g, "gland_nut", "gland nut", on_tile(6, 2, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	nut    = proposal_group_id_for(g, nut)
	bg_check(agency_undertake_goal_from_until_source(agency, worker, "tighten_nut", 60000, 120000, "employment"))
	bg_check(agency_autopilot_routine(agency, worker, 10))

	/* waiting for its routine: control stays with agency */
	scheduler_run_until(st.s, time_make(30000))
	bg_check(len(agency_take_notices(agency)) == 0 && agency_controls(agency, worker))
	bg_check(!(world_get_field(st.w, "Fastener.tight", nut, &v) && v != 0))

	/* its shift: taken up, though worth more than the threshold */
	scheduler_run_until(st.s, time_make(90000))
	bg_check(test_logged_by(agency, worker, "t=60000ms [-] weighing tighten the nut"))
	bg_check(world_get_field(st.w, "Fastener.tight", nut, &v) && v != 0)
	notices = agency_take_notices(agency)
	bg_check(len(notices) == 1 && notices[0] == "Control returns to you: its routine is done.")
}


/* KNOWLEDGE.md §11: conflicting beliefs coexist as competing hypotheses.
 * The worker has seen the nut plainly (19 mm) and stands four tiles off;
 * the smith, beside it, says the nut is 22 mm. Its belief and the smith's
 * claim coexist, the claim as credible as it finds the smith; less than
 * sure, it looks closer before it tightens. */
test_told_nut_run :: proc() -> Nut_Run {
	st: Stage
	activities: ^Activities
	knowledge: ^Knowledge
	agency: ^Agency
	g: ^Proposal_Group
	worker: Entity_ID
	smith: Entity_ID
	run: Nut_Run

	run        = {}
	st.w       = test_world(71)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g       = proposal_group_group_with_phase(.System, "setup: the pump")
	worker  = proposal_group_create(g, "worker", "Oskar", on_tile(5, 2, 0))
	smith   = proposal_group_create(g, "smith", "a fitter", on_tile(3, 3, 0))
	proposal_group_create(g, "spanner_19", "spanner", held_by(worker, 0))
	run.nut = proposal_group_create(g, "gland_nut", "gland nut", on_tile(6, 2, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker  = proposal_group_id_for(g, worker)
	smith   = proposal_group_id_for(g, smith)
	run.nut = proposal_group_id_for(g, run.nut)
	test_stage_move(&st, worker, 2, 2)
	test_stage_say(&st, smith, worker, "#IsLike & { what: #Fastener & { place: #OnTile & { x: 6, y: 2, level: 0 } }, " +
	                                   "as: #Fastener & { size: 22mm }, attribution: #Saw & { sure: 30 } }")
	run.fromAfar = knowledge_dump(knowledge, worker)
	bg_check(agency_commit(agency, worker, "tighten_nut"))
	scheduler_run_until(st.s, time_make(30000))
	run.world     = st.w
	run.knowledge = knowledge
	run.agency    = agency
	return run
}


test_tightened :: proc(run: Nut_Run) -> bool {
	v: i64

	return world_get_field(run.world, "Fastener.tight", run.nut, &v) && v != 0
}


test_unknown_nut :: proc() {
	base: Nut_Run
	wrong: Nut_Run
	seer: Nut_Run
	tag: Nut_Run
	again: Nut_Run
	spare: Nut_Run
	misfit: Nut_Run
	doubtful: Nut_Run
	sure: Nut_Run
	told: Nut_Run
	urgent: ^Agency
	mass: i64

	/* 1: four tiles off, the nut's size is only 16 to 22 mm: whether the 19
	 * mm spanner fits is unknown, with the residual nut.size and nothing else */
	base = test_nut_run("gland_nut", "spanner_19", false, nil)
	bg_check(ns_contains(base.fromAfar, "size: >=16mm & <=22mm"))
	/* 2: the residual becomes a goal: it looks closer, and then tightens it */
	bg_check(test_logged_by(base.agency, 1, "[tighten the nut] tighten it: unknown at nut.size: look closer first"))
	bg_check(test_logged_by(base.agency, 1, "[look closer] go and peer at it: a walk of "))
	bg_check(ns_contains(knowledge_store_describe_referent(knowledge_store_of(base.knowledge, 1),
	                                                        test_referent_of(knowledge_store_of(base.knowledge, 1), base.nut)),
	                     "size: 19mm"))     /* within reach, it sees it plainly */
	bg_check(test_logged_by(base.agency, 1, "[tighten the nut] back to it: look closer is done"))
	bg_check(test_logged_by(base.agency, 1, "[tighten the nut] tighten it: tighten R"))
	bg_check(test_tightened(base))

	/* A: the nut is truly 22 mm: up close it is incompatible, and the method
	 * fails; finding a spanner that fits (22 mm, the size it now believes) is
	 * impossible too, for it knows of none */
	wrong = test_nut_run("gland_nut_22", "spanner_19", false, nil)
	bg_check(test_logged_by(wrong.agency, 1, "look closer first"))
	bg_check(test_logged_by(wrong.agency, 1, "[tighten the nut] get one that fits: find a spanner that fits first"))
	bg_check(test_logged_by(wrong.agency, 1, "[find a spanner that fits] nothing I know of will do: impossible for now"))
	bg_check(test_logged_by(wrong.agency, 1, "[tighten the nut] nothing I know of will do: impossible for now"))
	bg_check(!test_tightened(wrong))

	/* A, with a 22 mm spanner on the bench by the nut: up close, it picks that
	 * one up, and tightens the nut with it */
	spare = test_nut_run("gland_nut_22", "spanner_19", false, "spanner_22")
	bg_check(test_logged_by(spare.agency, 1, "look closer first"))
	bg_check(test_logged_by(spare.agency, 1, "[find a spanner that fits] pick up one that fits: take_up"))
	bg_check(test_logged_by(spare.agency, 1, "[tighten the nut] back to it: find a spanner that fits is done"))
	bg_check(test_tightened(spare))
	/* with a 19 mm one there instead, nothing fits: it leaves it lying */
	misfit = test_nut_run("gland_nut_22", "spanner_19", false, "spanner_19")
	bg_check(!test_logged_by(misfit.agency, 1, "take_up") && !test_tightened(misfit))

	/* 3, B: the omniscient stub knows the size from afar: it never looks closer */
	seer = test_nut_run("gland_nut", "spanner_19", true, nil)
	bg_check(!test_logged_by(seer.agency, 1, "look closer") && !test_logged_by(seer.agency, 1, "peer_at"))
	bg_check(test_tightened(seer))

	/* 4: tags: with a 22 mm spanner instead, the same closer look finds it incompatible */
	tag = test_nut_run("gland_nut", "spanner_22", false, nil)
	bg_check(test_logged_by(tag.agency, 1, "look closer first"))
	bg_check(test_logged_by(tag.agency, 1, "impossible for now") && !test_tightened(tag))

	/* the urgency curve: at 90% of its window, +2, where a straight line
	 * would give +18 */
	urgent = test_urgent_nut()
	bg_check(test_logged_by(urgent, 1, "urgency +2"))

	/* 5: determinism */
	again = test_nut_run("gland_nut", "spanner_19", false, nil)
	bg_check(again.text == base.text)

	/* C: two hypotheses, 19 mm as it saw it, or 22 mm as it half remembers.
	 * At 300 in 1000 for 22, only 700 entails: under tightening's 900, so it
	 * looks closer first, and seen plainly the doubt is gone */
	doubtful = test_doubtful_nut_run(300, 0, &mass)
	bg_check(mass == 300 && ns_contains(doubtful.fromAfar, "or, 300 in 1000: size: 22mm"))
	bg_check(ns_contains(doubtful.fromAfar, "size: 19mm"))
	bg_check(test_logged_by(doubtful.agency, 1, "tighten it: unknown at nut.size (700 in 1000 entails, under 900): look closer first"))
	bg_check(test_tightened(doubtful))
	bg_check(!ns_contains(knowledge_dump(doubtful.knowledge, 1), "or, 300 in 1000"))
	/* told otherwise: its belief and the claim coexist */
	told = test_told_nut_run()
	bg_check(ns_contains(told.fromAfar, "size: 19mm"))
	bg_check(ns_contains(told.fromAfar, "or, 990 in 1000: size: 22mm\n"))
	bg_check(test_logged_by(told.agency, 1, "tighten it: unknown at nut.size (10 in 1000 entails, under 900): look closer first"))
	bg_check(test_tightened(told))

	/* the menu shows how sure: doubted, it is unknown, with the mass that
	 * entails and what to find out; undoubted, entailed */
	bg_check(ns_contains(test_doubtful_menu(300), ": unknown (700 in 1000 entails) (find out destination.size)"))
	bg_check(ns_contains(test_doubtful_menu(0), ": entailed"))
	/* at 50 in 1000, 950 entails: sure enough, it tightens it without looking */
	sure = test_doubtful_nut_run(50, 0, &mass)
	bg_check(!test_logged_by(sure.agency, 1, "look closer") && test_tightened(sure))

	/* more than one: 22 mm at 60, 24 mm at 50, so 890 entails, under 900,
	 * and it looks closer; both are kept, and saved, until it does */
	doubtful = test_doubtful_nut_run(60, 50, &mass)
	bg_check(mass == 110)
	bg_check(ns_contains(doubtful.fromAfar, "or, 60 in 1000: size: 22mm\n    or, 50 in 1000: size: 24mm"))
	bg_check(test_logged_by(doubtful.agency, 1, "tighten it: unknown at nut.size (890 in 1000 entails, under 900)"))
	bg_check(test_tightened(doubtful))
	/* 22 mm at 60, 24 mm at 30: 910 entails, sure enough */
	sure = test_doubtful_nut_run(60, 30, &mass)
	bg_check(mass == 90 && !test_logged_by(sure.agency, 1, "look closer") && test_tightened(sure))
}


/* --- the seized valve ------------------------------------------------------- */

Valve_Run :: struct {
	world:     ^World,
	committer: ^Committer,
	knowledge: ^Knowledge,
	valve:     Entity_ID,
	worker:    Entity_ID,
	wrench:    Entity_ID,
	pipe:      Entity_ID,
	delay:     i64,         /* bringing them to bear, ms */
	early:     bool,        /* turned before the stage and the delay were done */
	menu:      string,      /* the worker's, before it acts */
	trace:     string,
	turned:    bool,
	bent:      bool,
}


/* ACTIONS.md Scenario 1: the worker beside a valve (`valve`, seized or
 * not), holding what `tools` names ("", "wrench", "wrench pipe", "stone
 * wrench"), turns it; `steady`, if not 0, holds the torque there (Nm). With
 * a stone, it strikes the valve first and then holds the wrench alone.
 * "wrench near" and "pipe near" lie on tiles beside it, "pipe sacked" in a
 * sack on its tile, "pipe theirs" in a bystander's hand, "pipe far" out of
 * reach; "spare" lays a second wrench beside it. */
test_valve_run :: proc(valve: cstring, tools: cstring, steady: i64, seed: u64) -> Valve_Run {
	st: Stage
	activities: ^Activities
	knowledge: ^Knowledge
	g: ^Proposal_Group
	worker: Entity_ID
	pipe: Entity_ID
	stone: Entity_ID
	sack: Entity_ID
	other: Entity_ID
	store: ^Knowledge_Store
	menu: ^Menu
	entries: [dynamic]string
	error: string
	run: Valve_Run
	v: i64

	run        = {}
	st.w       = test_world(seed)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_add_domain(st.s, traces_as_domain(autorelease(traces_init_with_world(st.w))))
	g          = proposal_group_group_with_phase(.System, "setup: the water line")
	worker     = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	run.valve  = proposal_group_create(g, valve, "valve", on_tile(6, 5, 0))
	run.wrench = NO_ENTITY
	pipe       = NO_ENTITY
	stone      = NO_ENTITY
	/* strstr: strings.contains */
	if strings.contains(string(tools), "stone") {
		stone = proposal_group_create(g, "stone", "stone", held_by(worker, 0))
	} else if strings.contains(string(tools), "wrench near") {
		run.wrench = proposal_group_create(g, "wrench_250", "wrench", on_tile(4, 5, 0))
	} else if strings.contains(string(tools), "wrench") {
		run.wrench = proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	}
	if strings.contains(string(tools), "pipe near") {
		pipe = proposal_group_create(g, "pipe_600", "pipe", on_tile(4, 6, 0))
	} else if strings.contains(string(tools), "pipe sacked") {
		sack = proposal_group_create(g, "sack", "sack", on_tile(5, 5, 0))
		pipe = proposal_group_create(g, "pipe_600", "pipe", in_(sack))
	} else if strings.contains(string(tools), "pipe theirs") {
		other = proposal_group_create(g, "worker", "bystander", on_tile(5, 6, 0))
		pipe  = proposal_group_create(g, "pipe_600", "pipe", held_by(other, 0))
	} else if strings.contains(string(tools), "pipe far") {
		pipe = proposal_group_create(g, "pipe_600", "pipe", on_tile(8, 5, 0))
	} else if strings.contains(string(tools), "pipe") {
		pipe = proposal_group_create(g, "pipe_600", "pipe", held_by(worker, 1))
	}
	if strings.contains(string(tools), "spare") {
		proposal_group_create(g, "wrench_250", "a spare wrench", on_tile(5, 4, 0))
	}
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker     = proposal_group_id_for(g, worker)
	run.valve  = proposal_group_id_for(g, run.valve)
	run.wrench = proposal_group_id_for(g, run.wrench) if run.wrench != NO_ENTITY else NO_ENTITY
	run.pipe   = proposal_group_id_for(g, pipe) if pipe != NO_ENTITY else NO_ENTITY
	run.worker = worker
	stone      = proposal_group_id_for(g, stone) if stone != NO_ENTITY else NO_ENTITY

	/* the menu, as the worker knows it */
	store   = knowledge_store_of(knowledge, worker)
	menu    = menu_for_world_believed(store, st.w, true)
	entries = make([dynamic]string, context.temp_allocator)
	for i: uint = 0; i < menu_count(menu); i += 1 {
		append(&entries, menu_describe_at(menu, i))
	}
	run.menu = strings.join(entries[:], "; ", context.temp_allocator)

	error = ""
	if stone != NO_ENTITY {
		/* a blow first, then the wrench in that hand */
		bg_check(perform(st.w, st.c, action_make("strike", worker, stone, run.valve), 0, &error) != nil)
		scheduler_run_until(st.s, time_make(1000))
		g          = proposal_group_group_with_phase(.System, "setup: the stone down, the wrench up")
		proposal_group_move_to(g, whole(stone), on_tile(4, 5, 0))
		run.wrench = proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
		committer_submit(st.c, g)
		scheduler_run_until(st.s, time_make(2000))
		run.wrench = proposal_group_id_for(g, run.wrench)
	}
	run.delay = access_delay(st.w, action_make("rotate_valve", worker, run.valve, NO_ENTITY))
	bg_check(perform(st.w, st.c, action_make("rotate_valve", worker, run.valve, NO_ENTITY), steady, &error) != nil)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 2000 + run.delay - 1))
	run.early = world_get_field(st.w, "Valve.turned", run.valve, &v) && v != 0
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 3000))
	run.world     = st.w
	run.committer = st.c
	run.knowledge = knowledge
	run.trace     = strings.join(committer_trace(st.c), "\n", context.temp_allocator)
	run.turned    = world_get_field(st.w, "Valve.turned", run.valve, &v) && v != 0
	run.bent      = run.wrench != NO_ENTITY && world_get_field(st.w, "Body.bent", run.wrench, &v) && v != 0
	return run
}


/* ACTIONS.md §5: each provider belongs to at most one activity at a time,
 * counting those started for the same boundary and not yet committed:
 * taking up two things at once, the second is refused; walking while
 * taking one up is not; and once the first is done, the second can begin. */
test_providers_pending :: proc() {
	st: Stage
	activities: ^Activities
	g: ^Proposal_Group
	worker: Entity_ID
	seal: Entity_ID
	stone: Entity_ID
	error: string

	st.w       = test_world(7)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	g      = proposal_group_group_with_phase(.System, "setup: the bench")
	worker = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	seal   = proposal_group_create(g, "seal", "seal", on_tile(6, 5, 0))
	stone  = proposal_group_create(g, "stone", "stone", on_tile(5, 6, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	seal   = proposal_group_id_for(g, seal)
	stone  = proposal_group_id_for(g, stone)

	error = ""
	bg_check(perform(st.w, st.c, action_make("take_up", worker, seal, NO_ENTITY), 0, &error) != nil)
	bg_check(perform(st.w, st.c, action_make("take_up", worker, stone, NO_ENTITY), 0, &error) == nil)
	bg_check(ns_contains(error, "its hands are taken by take_up"))
	error = ""
	bg_check(perform(st.w, st.c, action_make("walk_east", worker, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(2))
	/* committed now, it is busy as before */
	bg_check(perform(st.w, st.c, action_make("take_up", worker, stone, NO_ENTITY), 0, &error) == nil)
	bg_check(ns_contains(error, "its hands are busy"))
	scheduler_run_until(st.s, time_make(1500))
	bg_check(world_location_of(st.w, seal).place == worker)
	error = ""
	bg_check(perform(st.w, st.c, action_make("take_up", worker, stone, NO_ENTITY), 0, &error) != nil)
}


/* Suspended while bringing wrench and pipe to bear, the stage owes, on
 * resuming, the rest of the stage and bringing them to bear as they lie
 * then: the pipe, put into a sack meanwhile, takes twice as long. */
test_access_resume :: proc() {
	st: Stage
	activities: ^Activities
	g: ^Proposal_Group
	worker: Entity_ID
	valve: Entity_ID
	wrench: Entity_ID
	pipe: Entity_ID
	sack: Entity_ID
	a: Entity_ID
	record: ^Activity
	error: string
	v: i64

	st.w       = test_world(5)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	g      = proposal_group_group_with_phase(.System, "setup: the water line")
	worker = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	valve  = proposal_group_create(g, "seized_valve", "valve", on_tile(6, 5, 0))
	wrench = proposal_group_create(g, "wrench_250", "wrench", on_tile(4, 5, 0))
	pipe   = proposal_group_create(g, "pipe_600", "pipe", on_tile(4, 6, 0))
	sack   = proposal_group_create(g, "sack", "sack", on_tile(5, 5, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	valve  = proposal_group_id_for(g, valve)
	wrench = proposal_group_id_for(g, wrench)
	pipe   = proposal_group_id_for(g, pipe)
	sack   = proposal_group_id_for(g, sack)

	/* 2 s of turning, 2 s of taking them up */
	error = ""
	g     = perform(st.w, st.c, action_make("rotate_valve", worker, valve, NO_ENTITY), 75, &error)
	bg_check(g != nil)
	scheduler_run_until(st.s, time_make(2))
	a      = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	record = (^Activity)(world_record(st.w, world_kind_named(st.w, "Activity"), a))
	bg_check(record != nil && record.due == 1 + 2000 + 2000)
	scheduler_run_until(st.s, time_make(1501))
	bg_check(activities_suspend(activities, a, "a shout", &error) != nil)
	scheduler_run_until(st.s, time_make(1502))

	/* meanwhile the pipe goes into the sack */
	g = proposal_group_group_with_phase(.System, "setup: the pipe sacked")
	proposal_group_move_to(g, whole(pipe), in_(sack))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(5000))

	/* resumed: 2 s of the stage and 3 s of bringing them to bear, less 1.5 s done */
	bg_check(activities_resume(activities, a, &error) != nil)
	scheduler_run_until(st.s, time_make(5001))
	record = (^Activity)(world_record(st.w, world_kind_named(st.w, "Activity"), a))
	bg_check(record.progress == 1500 && record.due == 5000 + 2000 + 3000 - 1500)
	scheduler_run_until(st.s, time_make(8499))
	bg_check(!(world_get_field(st.w, "Valve.turned", valve, &v) && v != 0))
	scheduler_run_until(st.s, time_make(8600))
	bg_check(world_get_field(st.w, "Valve.turned", valve, &v) && v != 0)
	bg_check(world_location_of(st.w, pipe).place == worker && world_location_of(st.w, wrench).place == worker)
}


test_seized_valve :: proc() {
	free_: Valve_Run
	bare: Valve_Run
	wrench: Valve_Run
	full: Valve_Run
	steady: Valve_Run
	struck: Valve_Run
	again: Valve_Run
	seen: string
	seed: u64
	bends: int
	frees: int

	/* 1: no leak: the menu for a seized valve is the menu for a free one */
	free_ = test_valve_run("water_valve", "", 0, 73)
	bare  = test_valve_run("seized_valve", "", 0, 73)
	bg_check(free_.menu == bare.menu)
	bg_check(ns_contains(bare.menu, "rotate_valve item"))
	bg_check(free_.turned)

	/* bare hands: 15 Nm, which the valve answers with nothing */
	bg_check(!bare.turned)
	bg_check(ns_contains(bare.trace, ": 15 Nm against 70 Nm: holds (expected to turn: rated 12 Nm)"))

	/* the wrench: 50 Nm, still nothing; the wrench is worn, in the stage's group */
	wrench = test_valve_run("seized_valve", "wrench", 0, 73)
	bg_check(!wrench.turned && !wrench.bent)
	bg_check(ns_contains(wrench.trace, ": 50 Nm against 70 Nm: holds"))
	bg_check(test_any_trace(wrench.world, "tool_marks"))

	/* 2, 3: wrench and pipe: the chain found reaches 0.6 m, 120 Nm, past the
	 * wrench's 80: risk, not refusal. Over seeds, sometimes the wrench bends
	 * first, sometimes the valve frees; the same seed, the same */
	bends = 0
	frees = 0
	for seed = 1; seed <= 20; seed += 1 {
		full = test_valve_run("seized_valve", "wrench pipe", 0, seed)
		bg_check(full.turned != full.bent)
		if full.bent {
			bends += 1
		}
		if full.turned {
			frees += 1
		}
	}
	bg_check(bends > 0 && frees > 0)
	full  = test_valve_run("seized_valve", "wrench pipe", 0, 5)
	again = test_valve_run("seized_valve", "wrench pipe", 0, 5)
	bg_check(full.turned == again.turned && full.trace == again.trace)

	/* a steady 75 Nm frees it, no risk */
	steady = test_valve_run("seized_valve", "wrench pipe", 75, 5)
	bg_check(steady.turned && !steady.bent)
	bg_check(ns_contains(steady.trace, ": 75 Nm against 70 Nm: turns"))

	/* the chain is searched in reach (ACTIONS.md §2), not only in hand:
	 * wrench and pipe lying beside it are taken up, into both hands */
	steady = test_valve_run("seized_valve", "wrench near pipe near", 75, 5)
	bg_check(steady.turned && !steady.bent)
	bg_check(ns_contains(steady.trace, "takes up one in reach; takes up one in reach"))
	bg_check(world_location_of(steady.world, steady.wrench).form == .Held_By &&
	         world_location_of(steady.world, steady.wrench).place == steady.worker)
	bg_check(world_location_of(steady.world, steady.pipe).place == steady.worker)
	/* which takes time: a take_up's second for each, added to the stage */
	bg_check(steady.delay == 2000 && !steady.early)
	/* a pipe in a sack standing on its tile: further to reach, still in
	 * reach, and twice as long to bring out */
	steady = test_valve_run("seized_valve", "wrench pipe sacked", 75, 5)
	bg_check(steady.turned && steady.delay == 2000 && !steady.early)
	bg_check(world_location_of(steady.world, steady.pipe).place == steady.worker)
	/* in hand already, none */
	steady = test_valve_run("seized_valve", "wrench pipe", 75, 5)
	bg_check(steady.turned && steady.delay == 0)
	/* not a pipe in another's hand, nor one out of reach: the wrench alone */
	wrench = test_valve_run("seized_valve", "wrench pipe theirs", 0, 73)
	bg_check(!wrench.turned && ns_contains(wrench.trace, ": 50 Nm against 70 Nm: holds"))
	bg_check(world_location_of(wrench.world, wrench.pipe).place != wrench.worker)
	wrench = test_valve_run("seized_valve", "wrench pipe far", 0, 73)
	bg_check(ns_contains(wrench.trace, ": 50 Nm against 70 Nm: holds"))
	/* the same reach: the one held, not a spare beside it */
	wrench = test_valve_run("seized_valve", "wrench spare", 0, 73)
	bg_check(!ns_contains(wrench.trace, "takes up"))
	/* the search is the same on every replay */
	full  = test_valve_run("seized_valve", "wrench near pipe near", 0, 5)
	again = test_valve_run("seized_valve", "wrench near pipe near", 0, 5)
	bg_check(full.trace == again.trace)

	/* 5: a blow with the stone loosens the bond, and the wrench alone turns it */
	struck = test_valve_run("seized_valve", "stone", 0, 73)
	bg_check(ns_contains(struck.trace, "struck, breaks free at 40 Nm now"))
	bg_check(struck.turned)

	/* 4: outcomes in the player's text are what can be perceived: the
	 * breakaway never appears */
	seen = knowledge_dump(bare.knowledge, 1)
	bg_check(!ns_contains(seen, "breakaway") && !ns_contains(seen, "70Nm"))
	bg_check(ns_contains(seen, "rating: 12Nm, turned: false"))
	/* and what it perceives of the outcome: freed, it hears the valve creak
	 * and sees it turned; bent, it hears the clang and sees the wrench bent;
	 * held, it hears nothing */
	seen = knowledge_dump(steady.knowledge, 1)
	bg_check(ns_contains(seen, "trace creak on"))
	bg_check(ns_contains(seen, "turned: true"))
	for seed = 1; seed <= 20; seed += 1 {
		full = test_valve_run("seized_valve", "wrench pipe", 0, seed)
		if full.bent {
			break
		}
	}
	seen = knowledge_dump(full.knowledge, 1)
	bg_check(full.bent && ns_contains(seen, "trace clang on"))
	bg_check(ns_contains(seen, "bent: true"))
	seen = knowledge_dump(bare.knowledge, 1)
	bg_check(!ns_contains(seen, "trace creak") && !ns_contains(seen, "trace clang"))
}


/* ACTIONS.md Scenario 3's recheck on resume: the worker, driving a nail of
 * its own into the lock, puts the drive down at 2 s; the smith takes its
 * nails; resuming is refused, with the reason, until they are back in its
 * hand. */
test_resume_recheck :: proc() {
	w: ^World
	c: ^Committer
	s: ^Scheduler
	activities: ^Activities
	g: ^Proposal_Group
	h: [8]Entity_ID
	a: Entity_ID
	error: string

	w          = test_world(79)
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	s          = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	committer_submit(c, workshop_setup(true, &h))
	scheduler_run_until(s, time_make(1))

	g = perform(w, c, action_make("drive", 4, 7, 3), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(s, time_make(2001))
	a = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	bg_check(activities_suspend(activities, a, "a shout", &error) != nil)
	scheduler_run_until(s, time_make(2002))
	bg_check(string(test_status_of(w, a)) == "\"suspended\"")

	/* the smith, beside the worker, takes the nails: still within reach, no
	 * longer in its hand */
	g = proposal_group_group_with_phase(.System, "setup: the smith takes the nails")
	proposal_group_move_to(g, whole(5), on_tile(4, 5, 0))
	proposal_group_move_to(g, whole(7), held_by(5, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(3000))
	error = ""
	bg_check(activities_resume(activities, a, &error) == nil)
	bg_check(error != "" && ns_contains(error, "what it needs no longer holds, at "))
	bg_check(string(test_status_of(w, a)) == "\"suspended\"")

	/* back in its hand: it resumes */
	g = proposal_group_group_with_phase(.System, "setup: the nails back")
	proposal_group_move_to(g, whole(7), held_by(4, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(4000))
	bg_check(activities_resume(activities, a, &error) != nil)
}


/* --- the interrupted repair --------------------------------------------------- */

/* the agent's activity of the operation, in that status ("running"), or 0 */
test_activity_of :: proc(w: ^World, actor: Entity_ID, operation: cstring, status: cstring) -> Entity_ID {
	record: ^Activity
	store: ^Store
	quoted: cstring

	quoted = fmt.ctprintf("\"%s\"", status)        /* snprintf into char[32]: the statuses are short */
	store  = world_store_for_kind(w, world_kind_named(w, "Activity"))
	for i: uint = 0; i < store_count(store); i += 1 {
		record = (^Activity)(store_record_at_index(store, i))
		if Entity_ID(record.actorRef) == actor && record.status == u32(tri.type_named(world_tri(w), quoted)) &&
		   string(world_text_field(w, "Activity.operation", store_entity_at_index(store, i))) == string(operation) {
			return store_entity_at_index(store, i)
		}
	}
	return NO_ENTITY
}


Repair_Run :: struct {
	world:              ^World,
	agency:             ^Agency,
	worker:             Entity_ID,
	trough:             Entity_ID,
	riser:              Entity_ID,
	pump:               Entity_ID,
	stage:              i64,          /* the dismantling, when suspended */
	progress:           i64,
	openWhileSuspended: bool,
	saved:              bool,         /* a save while suspended restores the same */
	nextSame:           bool,         /* and, restored, takes the same next boundary */
	talked:             bool,         /* saying something while dismantling */
	refused:            string,       /* why a second activity for the hands was refused */
}


/* ACTIONS.md Scenario 3, "the interrupted repair": the worker, with a wrench
 * and the miller's diagram (which wrongly shows the trough line's cock as
 * the pump's shutoff), repairs the pump by the recipe. At 60% of the last
 * stage of dismantling it is called away, and puts it down; the smith,
 * beside it, takes the wrench; later the wrench is back. `omniscient`: the
 * stub, which needs no diagram. */
test_repair_run :: proc(omniscient: bool, shout: bool) -> Repair_Run {
	st: Stage
	activities: ^Activities
	knowledge: ^Knowledge
	agency: ^Agency
	g: ^Proposal_Group
	wrench: Entity_ID
	diagram: Entity_ID
	smith: Entity_ID
	a: Entity_ID
	error: string
	text: string
	w2: ^World
	deferred: []^Proposal_Group
	position: u64
	run: Repair_Run
	start: i64
	v: i64

	run        = {}
	st.w       = test_world(83)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	knowledge_set_omniscient(knowledge, omniscient)
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g          = proposal_group_group_with_phase(.System, "setup: the mill")
	run.pump   = proposal_group_create(g, "pump", "pump", on_tile(10, 10, 0))
	run.trough = proposal_group_create(g, "cock_trough", "the trough line's cock", on_tile(9, 9, 0))
	run.riser  = proposal_group_create(g, "cock_pump", "the riser's cock", on_tile(11, 9, 0))
	run.worker = proposal_group_create(g, "worker", "worker", on_tile(10, 9, 0))
	smith      = proposal_group_create(g, "smith", "smith", on_tile(11, 10, 0))
	wrench     = proposal_group_create(g, "wrench_250", "wrench", held_by(run.worker, 0))
	diagram    = proposal_group_create(g, "diagram", "diagram", held_by(run.worker, 1))
	proposal_group_set_of_to_text(g, "Record.writing", whole(diagram),
	                              world_intern(st.w, "#Writing & { author: #Agent & { coat: \"white\" }, entries: [#Serves & { what: #Cock & " +
	                                                 "{ place: #OnTile & { x: 9, y: 9, level: 0 } }, line: \"pump\", attribution: #Saw & { sure: 30 } }] }"))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	run.pump   = proposal_group_id_for(g, run.pump)
	run.trough = proposal_group_id_for(g, run.trough)
	run.riser  = proposal_group_id_for(g, run.riser)
	run.worker = proposal_group_id_for(g, run.worker)
	smith      = proposal_group_id_for(g, smith)
	wrench     = proposal_group_id_for(g, wrench)
	diagram    = proposal_group_id_for(g, diagram)

	/* it reads the diagram, and sets to the repair */
	error = ""
	if !omniscient {
		bg_check(perform(st.w, st.c, action_make("read", run.worker, diagram, NO_ENTITY), 0, &error) != nil)
	}
	scheduler_run_until(st.s, time_make(1000))
	bg_check(agency_commit(agency, run.worker, "repair_pump"))
	scheduler_run_until(st.s, time_make(3000))
	a     = test_activity_of(st.w, run.worker, "dismantle", "running")
	start = 0
	bg_check(a != NO_ENTITY && world_get_field(st.w, "Activity.started", a, &start))

	/* 3: talking runs with the dismantling; a second activity for the hands
	 * is refused, with the reason */
	scheduler_run_until(st.s, time_make(start + 1000))
	{
		talk: Action

		talk         = action_make("say", run.worker, smith, NO_ENTITY)
		talk.content = world_intern(st.w, "#Here & {}")
		run.talked   = perform(st.w, st.c, talk, 0, &error) != nil
		error        = ""
		if perform(st.w, st.c, action_make("dismantle", run.worker, wrench, run.pump), 0, &error) == nil {
			run.refused = error         /* [[error copy] autorelease] */
		}
		error = ""
	}

	/* stage 3 is 60% done: called away, it puts the work down; the smith takes the wrench */
	if shout {
		/* the smith shouts its name, a second's shout ending then: agency decides */
		call: Action

		scheduler_run_until(st.s, time_make(start + 3000 + 3000 + 2000))
		call         = action_make("say", smith, run.worker, NO_ENTITY)
		call.content = world_intern(st.w, "#Call & { what: #Agent & { coat: \"blue\" } }")
		bg_check(perform(st.w, st.c, call, 0, &error) != nil)
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000 + 2))
		world_get_field(st.w, "Activity.progress", a, &run.progress)
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 10000))
		run.world  = st.w
		run.agency = agency
		return run
	}
	scheduler_run_until(st.s, time_make(start + 3000 + 3000 + 3000))
	bg_check(activities_suspend(activities, a, "someone shouts its name", &error) != nil)
	g = proposal_group_group_with_phase(.System, "setup: the smith takes the wrench")
	proposal_group_move_to(g, whole(wrench), held_by(smith, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	world_get_field(st.w, "Activity.stage", a, &run.stage)
	world_get_field(st.w, "Activity.progress", a, &run.progress)
	run.openWhileSuspended = world_get_field(st.w, "Pump.opened", run.pump, &v) && v != 0

	/* saved while suspended, and restored the same */
	text      = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	w2        = restore(text, world_content_build(st.w), &deferred, &position, &error)
	run.saved = w2 != nil && world_state_hash(w2) == world_state_hash(st.w)

	/* 5: restored, with its own knowledge and agency, it takes the next
	 * boundary exactly as the run that never saved */
	{
		st2: Stage
		activities2: ^Activities
		knowledge2: ^Knowledge
		agency2: ^Agency
		saved2: Saved_System
		next: i64

		st2.w       = test_restore(text, world_content_build(st.w), &st2.c, &error)
		activities2 = activities_with_world(st2.w, st2.c)
		knowledge2  = autorelease(knowledge_init_with_world(st2.w))
		agency2     = autorelease(agency_init_with_world(st2.w, st2.c, knowledge2))
		st2.s       = autorelease(scheduler_init_with_world(st2.w, st2.c))
		knowledge_set_omniscient(knowledge2, omniscient)
		saved2 = knowledge_as_saved_system(knowledge2)
		saved2.restore_saved_state(saved2.data, saved_domain_state(text, "knowledge"))
		saved2 = agency_as_saved_system(agency2)
		saved2.restore_saved_state(saved2.data, saved_domain_state(text, "agency"))
		agency_set_activities(agency2, activities2)
		scheduler_set_activities(st2.s, activities_as_activity_clock(activities2))
		scheduler_set_perception(st2.s, knowledge_as_perception_phase(knowledge2))
		scheduler_set_decision(st2.s, agency_as_decision_phase(agency2))
		/* nothing is due while it is suspended: the next boundary is the stop */
		next         = world_time(st.w).ms + 2000
		run.nextSame = scheduler_run_until(st2.s, time_make(next)) == 1
		run.nextSame = scheduler_run_until(st.s, time_make(next)) == 1 && run.nextSame && world_time(st2.w).ms == next &&
		               world_state_hash(st2.w) == world_state_hash(st.w) &&
		               save(st2.w, st2.c, []Saved_System{knowledge_as_saved_system(knowledge2), agency_as_saved_system(agency2)}) ==
		                  save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge), agency_as_saved_system(agency)})
	}

	/* the wrench back: the repair goes on */
	g = proposal_group_group_with_phase(.System, "setup: the wrench back")
	proposal_group_move_to(g, whole(wrench), held_by(run.worker, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 10000))
	run.world  = st.w
	run.agency = agency
	return run
}


test_interrupted_repair :: proc() {
	run: Repair_Run
	seer: Repair_Run
	shout: Repair_Run
	v: i64

	/* 1: the recipe binds through knowledge: by the diagram, the trough line's cock */
	run = test_repair_run(false, false)
	bg_check(test_logged_by(run.agency, run.worker, "[repair the pump] follow the recipe: shut_off R"))
	bg_check(world_get_field(run.world, "Cock.shut", run.trough, &v) && v != 0)
	bg_check(world_get_field(run.world, "Cock.shut", run.riser, &v) && v == 0)
	/* the omniscient stub binds the riser's */
	seer = test_repair_run(true, false)
	bg_check(world_get_field(seer.world, "Cock.shut", seer.riser, &v) && v != 0)
	bg_check(world_get_field(seer.world, "Cock.shut", seer.trough, &v) && v == 0)

	/* 4: suspended at 60% of the last stage: its progress kept, nothing committed */
	bg_check(run.stage == 2 && run.progress == 3000)
	bg_check(!run.openWhileSuspended)
	/* 6: resuming without the wrench is refused, with the reason */
	bg_check(test_logged_by(run.agency, run.worker, "could not resume dismantle: what it needs no longer holds"))
	/* 5: saved while suspended, restored the same, and the next boundary the same */
	bg_check(run.saved)
	bg_check(run.nextSame)
	/* 3: talking ran with the dismantling; a second dismantling was refused, its hands busy */
	bg_check(run.talked)
	bg_check(run.refused != "" && ns_contains(run.refused, "its hands are busy with activity"))
	/* the wrench back, it resumes, and the pump is open */
	bg_check(test_logged_by(run.agency, run.worker, "follow the recipe: resuming dismantle"))
	bg_check(world_get_field(run.world, "Pump.opened", run.pump, &v) && v != 0)
	bg_check(test_logged_by(run.agency, run.worker, "[repair the pump] done"))

	/* the shout as a soft interruption agency decides on: worth 15, more than
	 * the interruption, it puts the dismantling down, answers, and goes back */
	shout = test_repair_run(false, true)
	bg_check(test_logged_by(shout.agency, shout.worker, "called by R"))
	bg_check(test_logged_by(shout.agency, shout.worker, ": worth +15: putting dismantle down"))
	bg_check(test_logged_by(shout.agency, shout.worker, "answering: say R"))
	bg_check(test_logged_by(shout.agency, shout.worker, "follow the recipe: resuming dismantle"))
	bg_check(shout.progress == 3000)            /* put down as the shout is heard, 60% of the way */
	bg_check(world_get_field(shout.world, "Pump.opened", shout.pump, &v) && v != 0)
}


/* --- the unattended stove ------------------------------------------------------ */

Stove_Run :: struct {
	world:            ^World,
	committer:        ^Committer,
	air:              ^Atmosphere,
	thermal:          ^Thermal,
	room:             Entity_ID,
	shell:            Entity_ID,
	stove:            Entity_ID,
	rest:             Entity_ID,
	outAt:            i64,          /* when the stove went out, ms; 0 if it didn't */
	wokenAt:          i64,          /* when the rest ended */
	boundaries:       uint,
	litAt:            i64,
	roomHottest:      i64,          /* mK */
	stoveHottest:     i64,
	thermalBeforeLit: uint,         /* the thermal domain's steps before the fire's heat reached it */
	balanced:         bool,         /* after every boundary, both domains, and between them */
	text:             string,
}


/* DOMAIN_SIMULATION.md Scenario 1, "the unattended stove": a room of stone
 * with a stove and 3 kg of wood; a lodger, breathing, lights it and rests
 * for 8 hours, with a watch on the air. `stepped`: in one-minute steps
 * (variant C). `reversed`: the domains added the other way round.
 * `restsAbove`: the lodger rests easy only above it (mK), and lies down two
 * hours after lighting the stove, once the room has warmed. */
test_stove_run :: proc(damper: bool, stepped: bool, reversed: bool, restsAbove: i64) -> Stove_Run {
	w: ^World
	c: ^Committer
	s: ^Scheduler
	activities: ^Activities
	air: ^Atmosphere
	thermal: ^Thermal
	g: ^Proposal_Group
	worker: Entity_ID
	error: string
	run: Stove_Run
	v: i64
	end: i64

	run        = {}
	w          = test_world(89)
	bg_check(world_set_terrain_map(w, "rooms_map", nil))      /* TERRAIN.md: the rooms, from the map */
	c          = test_committer(w)
	activities = activities_with_world(w, c)
	air        = autorelease(atmosphere_init_with_world(w))
	thermal    = autorelease(thermal_init_with_world(w))
	s          = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_add_domain(s, thermal_as_domain(thermal) if reversed else atmosphere_as_domain(air))
	scheduler_add_domain(s, atmosphere_as_domain(air) if reversed else thermal_as_domain(thermal))
	g         = proposal_group_group_with_phase(.System, "setup: the room")
	run.room  = proposal_group_create(g, "room_air", "the room's air", location_make_none())
	run.shell = proposal_group_create(g, "room_shell", "the room's walls", location_make_none())
	run.stove = proposal_group_create(g, "stove", "stove", on_tile(2, 2, 0))
	worker    = proposal_group_create(g, "lodger", "lodger", on_tile(3, 2, 0))
	if !damper {
		proposal_group_set_of_to(g, "Combustor.damper", whole(run.stove), 0)
	}
	if restsAbove != 0 {
		proposal_group_set_of_to(g, "Respirator.restsAbove", whole(worker), restsAbove)
	}
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	run.room  = proposal_group_id_for(g, run.room)
	run.shell = proposal_group_id_for(g, run.shell)
	run.stove = proposal_group_id_for(g, run.stove)
	worker    = proposal_group_id_for(g, worker)
	g         = proposal_group_group_with_phase(.System, "setup: the walls bound the room")
	proposal_group_set_of_to(g, "ThermalBody.bounds", whole(run.shell), i64(run.room))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))

	error = ""
	run.thermalBeforeLit = thermal_steps(thermal)
	bg_check(perform(w, c, action_make("light", worker, run.stove, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(2))
	if world_get_field(w, "Combustor.lit", run.stove, &v) && v != 0 {
		run.litAt = world_time(w).ms
	}
	if restsAbove != 0 {
		scheduler_run_until(s, time_make(2 * 3600000))
	}
	g = perform(w, c, action_make("while_away", worker, NO_ENTITY, NO_ENTITY), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	run.rest     = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	run.balanced = true
	end          = 8 * 3600000 + 10000
	for world_time(w).ms < end {
		if stepped {
			scheduler_run_until(s, time_make(world_time(w).ms - world_time(w).ms % 60000 + 60000))
		} else if !scheduler_step_until(s, time_make(end)) {
			break
		}
		run.boundaries += 1
		run.balanced = run.balanced && atmosphere_balanced(air) && thermal_balanced(thermal) &&
		               atmosphere_sent(air) == thermal_received(thermal) + thermal_pending(thermal)
		if atmosphere_temperature_of(air, run.room) > run.roomHottest {
			run.roomHottest = atmosphere_temperature_of(air, run.room)
		}
		if thermal_temperature_of(thermal, run.stove) > run.stoveHottest {
			run.stoveHottest = thermal_temperature_of(thermal, run.stove)
		}
		if run.outAt == 0 && world_get_field(w, "Combustor.lit", run.stove, &v) && v == 0 {
			run.outAt = world_time(w).ms
		}
		if run.wokenAt == 0 && string(test_status_of(w, run.rest)) != "\"running\"" {
			run.wokenAt = world_time(w).ms
		}
	}
	run.world     = w
	run.committer = c
	run.air       = air
	run.thermal   = thermal
	run.text      = save(w, c, []Saved_System{domain_as_saved_system(atmosphere_as_domain(air)),
	                                          domain_as_saved_system(thermal_as_domain(thermal))})
	return run
}


test_unattended_stove :: proc() {
	a: Stove_Run
	again: Stove_Run
	b: Stove_Run
	stepped: Stove_Run
	reversed: Stove_Run
	d: Stove_Run
	restored: ^Atmosphere
	restoredThermal: ^Thermal
	restoredDomain: Domain
	original: Domain
	trace: string
	at: uint
	fuel: i64
	v: i64
	reached: i64
	cooled: i64

	/* A, the flue open: the fire burns 3 kg at 0.25 g a second, 12,000 s, and
	 * goes out then, to the millisecond, a predicted event; its iron takes
	 * three tenths of the heat and warms the room, and the room its walls; the
	 * lodger breathes, and its carbon dioxide stays well below stuffy; the
	 * rest runs its 8 hours; and every step balances exactly, in each domain
	 * and between them, with what is in transit */
	a = test_stove_run(true, false, false, 0)
	bg_check(a.balanced)
	bg_check(a.litAt > 0 && a.outAt == a.litAt + 12000000)
	bg_check(world_get_field(a.world, "FuelContainer.fuel", a.stove, &fuel) && fuel == 0)
	bg_check(a.wokenAt >= 8 * 3600000)
	bg_check(a.stoveHottest > 330000 && a.roomHottest > 285000)
	bg_check(atmosphere_temperature_of(a.air, a.room) > 277000)
	bg_check(thermal_temperature_of(a.thermal, a.shell) > 277000)
	bg_check(world_get_field(a.world, "GasStore.dioxide", a.room, &v) && v > 1500 && v < 3000)
	/* 2: time jumps: hundreds of steps for eight hours, not hundreds of
	 * thousands. The exchange with the solids lags a step and bounds them
	 * while it runs, and the lodger's warmth keeps it running: about 400 */
	bg_check(a.boundaries < 1000)
	/* 6: the thermal domain sleeps until the fire's heat reaches it */
	bg_check(a.thermalBeforeLit == 0 && thermal_steps(a.thermal) > 0)

	/* B, the damper left closed: the fire fills the room with carbon dioxide,
	 * and the watch wakes the rest at the boundary it crosses, within the
	 * event tolerance of a second */
	b = test_stove_run(false, false, false, 0)
	bg_check(b.balanced)
	bg_check(b.wokenAt > 0 && b.wokenAt < 3600000)
	trace = strings.join(committer_trace(b.committer), "\n", context.temp_allocator)
	at    = ns_range_of(trace, "reaches ")
	/* atoll: as -longLongValue, short of overflow */
	reached = ns_long_long_value(trace[at + 8:]) if at != NOT_FOUND else 0
	bg_check(reached >= 4000 && reached < 4000 + 50)

	/* 3, C: the same, in 480 one-minute steps: exactly as conserved, the
	 * fuel all burned, and the room's and walls' temperatures within a
	 * kelvin */
	stepped = test_stove_run(true, true, false, 0)
	bg_check(stepped.balanced)
	bg_check(world_get_field(stepped.world, "FuelContainer.fuel", stepped.stove, &fuel) && fuel == 0)
	bg_check(abs(atmosphere_temperature_of(stepped.air, stepped.room) - atmosphere_temperature_of(a.air, a.room)) < 1000)
	bg_check(abs(thermal_temperature_of(stepped.thermal, stepped.shell) - thermal_temperature_of(a.thermal, a.shell)) < 1000)
	bg_check(stepped.boundaries >= 480)

	/* determinism, and the domains' state saved */
	again = test_stove_run(true, false, false, 0)
	bg_check(again.text == a.text)
	restored       = autorelease(atmosphere_init_with_world(a.world))
	restoredDomain = atmosphere_as_domain(restored)
	original       = atmosphere_as_domain(a.air)
	restoredDomain.restore_saved_state(restoredDomain.data, saved_domain_state(a.text, "atmosphere"))
	bg_check(slice.equal(restoredDomain.saved_state(restoredDomain.data), original.saved_state(original.data)))
	restoredThermal = autorelease(thermal_init_with_world(a.world))
	restoredDomain  = thermal_as_domain(restoredThermal)
	original        = thermal_as_domain(a.thermal)
	restoredDomain.restore_saved_state(restoredDomain.data, saved_domain_state(a.text, "thermal"))
	bg_check(slice.equal(restoredDomain.saved_state(restoredDomain.data), original.saved_state(original.data)))

	/* 4: order independence: the domains run the other way round, bit for bit
	 * the same */
	reversed = test_stove_run(true, false, true, 0)
	bg_check(reversed.text == a.text)

	/* D, the comfort band: the lodger lies down in the warmed room, resting
	 * easy above 280 K, and the cold wakes it after the fire is out */
	d = test_stove_run(true, false, false, 280000)
	bg_check(d.balanced)
	bg_check(d.wokenAt > d.outAt && d.wokenAt < 8 * 3600000)
	trace  = strings.join(committer_trace(d.committer), "\n", context.temp_allocator)
	at     = ns_range_of(trace, "cools to ")
	cooled = ns_long_long_value(trace[at + 9:]) if at != NOT_FOUND else 0
	bg_check(cooled < 280000 && cooled > 280000 - 5)     /* within a second of the crossing */
}


/* DOMAIN_SIMULATION.md Scenario 1's check 6, local wake. A room of stale air
 * behind a tight door (no gap), off a corridor ten times its size that opens
 * to the outdoors; a second room off the corridor, through a gap; the room's
 * walls bound it. Everything else is fresh and at 275 K, so nothing moves:
 * both domains sleep, and an hour passes in a step. A worker opens the door:
 * the room and the corridor wake, and the room airs out; the back room, and
 * the thermal domain, sleep through it. Once the corridor has settled with
 * the outdoors, everything sleeps again. */
test_local_wake :: proc() {
	w: ^World
	c: ^Committer
	s: ^Scheduler
	air: ^Atmosphere
	thermal: ^Thermal
	airDomain: Domain
	thermalDomain: Domain
	g: ^Proposal_Group
	room: Entity_ID
	corridor: Entity_ID
	back: Entity_ID
	door: Entity_ID
	shell: Entity_ID
	worker: Entity_ID
	error: string
	n: uint
	before: uint
	balanced: bool
	v: i64
	u: i64

	w       = test_world(97)
	bg_check(world_set_terrain_map(w, "rooms_map", nil))      /* TERRAIN.md: the rooms, from the map */
	c       = test_committer(w)
	air     = autorelease(atmosphere_init_with_world(w))
	thermal = autorelease(thermal_init_with_world(w))
	s       = autorelease(scheduler_init_with_world(w, c))
	airDomain     = atmosphere_as_domain(air)
	thermalDomain = thermal_as_domain(thermal)
	scheduler_add_domain(s, airDomain)
	scheduler_add_domain(s, thermalDomain)
	g        = proposal_group_group_with_phase(.System, "setup: the rooms")
	corridor = proposal_group_create(g, "corridor", "the corridor", location_make_none())
	room     = proposal_group_create(g, "room_air", "the room's air", location_make_none())
	back     = proposal_group_create(g, "back_room", "the back room's air", location_make_none())
	shell    = proposal_group_create(g, "room_shell", "the room's walls", location_make_none())
	door     = proposal_group_create(g, "room_door", "the room's door", on_tile(4, 6, 0))
	worker   = proposal_group_create(g, "worker", "worker", on_tile(4, 5, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	corridor = proposal_group_id_for(g, corridor)
	room     = proposal_group_id_for(g, room)
	back     = proposal_group_id_for(g, back)
	shell    = proposal_group_id_for(g, shell)
	door     = proposal_group_id_for(g, door)
	worker   = proposal_group_id_for(g, worker)
	g = proposal_group_group_with_phase(.System, "setup: the doors, and a night's stale air")
	proposal_group_set_of_to(g, "GasStore.gap", whole(room), 0)
	proposal_group_set_of_to(g, "GasStore.dioxide", whole(room), 1600)
	proposal_group_set_of_to(g, "ThermalBody.bounds", whole(shell), i64(room))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(2))

	/* asleep: an hour in a step */
	bg_check(!airDomain.is_active(airDomain.data) && !thermalDomain.is_active(thermalDomain.data))
	n = scheduler_run_until(s, time_make(3600000))
	bg_check(n == 1 && atmosphere_steps(air) == 0 && thermal_steps(thermal) == 0)

	/* the door opens: the room and the corridor wake, not the back room */
	error = ""
	bg_check(perform(w, c, action_make("open_door", worker, door, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(3600001))
	bg_check(world_get_field(w, "Door.ajar", door, &v) && v == 1)
	bg_check(airDomain.is_active(airDomain.data))
	balanced = true
	for world_time(w).ms < 2 * 3600000 {
		if !scheduler_step_until(s, time_make(2 * 3600000)) {
			scheduler_run_until(s, time_make(2 * 3600000))
		}
		balanced = balanced && atmosphere_balanced(air)
	}
	bg_check(atmosphere_steps_of(air, room) > 0 && atmosphere_steps_of(air, corridor) > 0)
	bg_check(atmosphere_steps_of(air, back) == 0 && thermal_steps(thermal) == 0)
	/* aired: within the settle tolerance of the corridor, scaled */
	bg_check(world_get_field(w, "GasStore.dioxide", room, &v) && world_get_field(w, "GasStore.dioxide", corridor, &u) &&
	         abs(v - u / 10) <= 100)

	/* then everything settles and sleeps, in a few dozen steps */
	before = atmosphere_steps(air)
	for world_time(w).ms < 24 * 3600000 {
		if !scheduler_step_until(s, time_make(24 * 3600000)) {
			scheduler_run_until(s, time_make(24 * 3600000))
		}
		balanced = balanced && atmosphere_balanced(air)
	}
	bg_check(balanced)
	bg_check(!airDomain.is_active(airDomain.data) && !thermalDomain.is_active(thermalDomain.data))
	bg_check(atmosphere_steps(air) - before < 40)
	bg_check(atmosphere_steps_of(air, back) == 0 && thermal_steps(thermal) == 0)
}


/* AGENCY.md §6's warmth: a lodger by the cold stove, its body at `kelvin`
 * (mK). Interoception feels its body's heat, the thermal domain's, as
 * cold; cold enough, the needs generator raises *get warm*, and it lights
 * the stove. (cold_lodger: test_cold_lodger is the test's own name.) */
test_cold_lodger_run :: proc(kelvin: i64, numbness: i64, minds: ^^Agency, known: ^^Knowledge) -> Stove_Run {
	st: Stage
	activities: ^Activities
	knowledge: ^Knowledge
	agency: ^Agency
	air: ^Atmosphere
	thermal: ^Thermal
	g: ^Proposal_Group
	lodger: Entity_ID
	run: Stove_Run

	run        = {}
	st.w       = test_world(101)
	bg_check(world_set_terrain_map(st.w, "rooms_map", nil))      /* TERRAIN.md: the rooms, from the map */
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	air        = autorelease(atmosphere_init_with_world(st.w))
	thermal    = autorelease(thermal_init_with_world(st.w))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	scheduler_add_domain(st.s, atmosphere_as_domain(air))
	scheduler_add_domain(st.s, thermal_as_domain(thermal))
	g         = proposal_group_group_with_phase(.System, "setup: a cold room")
	run.room  = proposal_group_create(g, "room_air", "the room's air", location_make_none())
	run.stove = proposal_group_create(g, "stove", "stove", on_tile(2, 2, 0))
	lodger    = proposal_group_create(g, "lodger", "lodger", on_tile(3, 2, 0))
	proposal_group_set_of_to(g, "ThermalBody.heat", whole(lodger), kelvin * 245000 / 1000)
	proposal_group_set_of_to(g, "Agent.numbness", whole(lodger), numbness)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	run.room  = proposal_group_id_for(g, run.room)
	run.stove = proposal_group_id_for(g, run.stove)
	run.rest  = proposal_group_id_for(g, lodger)         /* the lodger */
	agency_control(agency, run.rest)
	scheduler_run_until(st.s, time_make(60000))
	run.world     = st.w
	run.committer = st.c
	run.air       = air
	run.thermal   = thermal
	minds^        = agency
	known^        = knowledge
	return run
}


/* The lodger, resting by the cold stove, cools (it breathes at rest): its
 * body crossing 307 K is felt as cold 30 at a boundary the thermal domain
 * predicted, not hours after. Returns how far below 307 K the body was then,
 * mK, or -1 if it never was. */
test_cooling_lodger :: proc() -> i64 {
	st: Stage
	activities: ^Activities
	knowledge: ^Knowledge
	thermal: ^Thermal
	g: ^Proposal_Group
	lodger: Entity_ID
	error: string

	st.w       = test_world(113)
	bg_check(world_set_terrain_map(st.w, "rooms_map", nil))      /* TERRAIN.md: the rooms, from the map */
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	thermal    = autorelease(thermal_init_with_world(st.w))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_add_domain(st.s, atmosphere_as_domain(autorelease(atmosphere_init_with_world(st.w))))
	scheduler_add_domain(st.s, thermal_as_domain(thermal))
	g      = proposal_group_group_with_phase(.System, "setup: a cold room")
	proposal_group_create(g, "room_air", "the room's air", location_make_none())
	lodger = proposal_group_create(g, "lodger", "lodger", on_tile(3, 2, 0))
	proposal_group_set_of_to(g, "ThermalBody.heat", whole(lodger), 307100 * 245000 / 1000)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	lodger = proposal_group_id_for(g, lodger)
	error  = ""
	bg_check(perform(st.w, st.c, action_make("while_away", lodger, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	for world_time(st.w).ms < 4 * 3600000 && scheduler_step_until(st.s, time_make(4 * 3600000)) {
		if knowledge_store_feels(knowledge_store_of(knowledge, lodger), "cold") >= 30 {
			return 307000 - thermal_temperature_of(thermal, lodger)
		}
	}
	return -1
}


test_cold_lodger :: proc() {
	cold: Stove_Run
	cool: Stove_Run
	agency: ^Agency
	knowledge: ^Knowledge
	v: i64
	below: i64

	/* 305 K, five below: it feels cold 50, more than 30: it lights the stove */
	cold = test_cold_lodger_run(305000, 0, &agency, &knowledge)
	bg_check(knowledge_store_feels(knowledge_store_of(knowledge, cold.rest), "cold") == 50)
	bg_check(test_logged_by(agency, cold.rest, "[get warm] light the stove: light R"))
	/* the pressure, by its curve: cold 50 is worth 30 (a straight line by 5
	 * tenths would give 25) */
	bg_check(test_logged_by(agency, cold.rest, "weighing get warm: +30 (cold +30)"))
	bg_check(world_get_field(cold.world, "Combustor.lit", cold.stove, &v) && v != 0)
	bg_check(test_logged_by(agency, cold.rest, "[get warm] done"))

	/* resting, it cools past 307 K, and feels it within a few mK */
	below = test_cooling_lodger()
	bg_check(below >= 0 && below < 5)

	/* numb (30), at 305 K it feels only 20: its body is as cold, but it
	 * leaves the stove cold (AGENCY.md §6: numbness hides cold) */
	cool = test_cold_lodger_run(305000, 30, &agency, &knowledge)
	bg_check(knowledge_store_feels(knowledge_store_of(knowledge, cool.rest), "cold") == 20)
	bg_check(world_get_field(cool.world, "Combustor.lit", cool.stove, &v) && v == 0)

	/* 308.5 K: cold 10, not pressing: the stove stays cold */
	cool = test_cold_lodger_run(308500, 0, &agency, &knowledge)
	bg_check(knowledge_store_feels(knowledge_store_of(knowledge, cool.rest), "cold") == 10)
	bg_check(!test_logged_by(agency, cool.rest, "get warm"))
	bg_check(world_get_field(cool.world, "Combustor.lit", cool.stove, &v) && v == 0)
}


/* AGENCY.md §6's air: a lodger in a room whose air holds `dioxide` mmol,
 * beside its shut door to the corridor. Interoception feels the air's carbon
 * dioxide as shortness of breath; enough, and it airs the room.
 * (stuffy_lodger: test_stuffy_lodger is the test's own name.) */
test_stuffy_lodger_run :: proc(dioxide: i64, felt: ^i32, minds: ^^Agency, who: ^Entity_ID, fatigue: ^i64) -> bool {
	st: Stage
	activities: ^Activities
	knowledge: ^Knowledge
	agency: ^Agency
	air: ^Atmosphere
	g: ^Proposal_Group
	room: Entity_ID
	corridor: Entity_ID
	door: Entity_ID
	lodger: Entity_ID
	v: i64

	st.w       = test_world(103)
	bg_check(world_set_terrain_map(st.w, "rooms_map", nil))      /* TERRAIN.md: the rooms, from the map */
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	air        = autorelease(atmosphere_init_with_world(st.w))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	scheduler_add_domain(st.s, atmosphere_as_domain(air))
	scheduler_add_domain(st.s, bodies_as_domain(autorelease(bodies_init_with_world(st.w))))
	g        = proposal_group_group_with_phase(.System, "setup: a shut room")
	corridor = proposal_group_create(g, "corridor", "the corridor", location_make_none())
	room     = proposal_group_create(g, "room_air", "the room's air", location_make_none())
	door     = proposal_group_create(g, "room_door", "the room's door", on_tile(4, 6, 0))
	lodger   = proposal_group_create(g, "lodger", "lodger", on_tile(4, 5, 0))
	proposal_group_set_of_to(g, "GasStore.dioxide", whole(room), dioxide)
	proposal_group_set_of_to(g, "GasStore.gap", whole(room), 0)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	room     = proposal_group_id_for(g, room)
	corridor = proposal_group_id_for(g, corridor)
	door     = proposal_group_id_for(g, door)
	lodger   = proposal_group_id_for(g, lodger)
	g = proposal_group_group_with_phase(.System, "setup: the door")
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(2))
	felt^  = knowledge_store_feels(knowledge_store_of(knowledge, lodger), "stuffy")
	agency_control(agency, lodger)
	scheduler_run_until(st.s, time_make(30000))
	minds^ = agency
	who^   = lodger
	if fatigue != nil {
		fatigue^ = 0
		world_get_field(st.w, "Agent.fatigue", lodger, fatigue)
	}
	return world_get_field(st.w, "Door.ajar", door, &v) && v != 0
}


test_stuffy_lodger :: proc() {
	agency: ^Agency
	lodger: Entity_ID
	felt: i32

	fatigue: i64

	/* 0.5% carbon dioxide: short of breath 40, more than 30: it opens the
	 * door; not enough to harm it */
	bg_check(test_stuffy_lodger_run(10000, &felt, &agency, &lodger, &fatigue))
	bg_check(felt == 40 && fatigue == 0)
	bg_check(test_logged_by(agency, lodger, "[air the room] open a door: open_door R"))
	bg_check(test_logged_by(agency, lodger, "[air the room] done"))
	/* 0.12%: 0, and the door stays shut */
	bg_check(!test_stuffy_lodger_run(2400, &felt, &agency, &lodger, nil))
	bg_check(felt == 0 && !test_logged_by(agency, lodger, "air the room"))
	/* AGENCY.md decision 17: 1%, short of breath 90, harms it, a point of
	 * fatigue every ten seconds: three in its first thirty, the door open
	 * and the air still clearing */
	bg_check(test_stuffy_lodger_run(20000, &felt, &agency, &lodger, &fatigue))
	bg_check(felt == 90 && fatigue == 3)
}


/* ACTIONS.md §5's partial effects: the worker saws a log through, eight
 * seconds with three checkpoints. `stop`: what happens at five seconds,
 * 62.5% of the way: nothing (0), suspended (1), aborted (2), or the saw
 * taken from its hand, so that completing fails (3). Then three seconds
 * more, and resuming if suspended. The log's cut as it goes, at each
 * second, into `cut`. */
test_saw_run :: proc(stop: i32, cut: ^[12]i64, status: ^cstring) -> bool {
	st: Stage
	activities: ^Activities
	g: ^Proposal_Group
	worker: Entity_ID
	log: Entity_ID
	saw: Entity_ID
	smith: Entity_ID
	a: Entity_ID
	error: string
	start: i64

	st.w       = test_world(107)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	g      = proposal_group_group_with_phase(.System, "setup: the sawhorse")
	worker = proposal_group_create(g, "worker", "worker", on_tile(3, 3, 0))
	smith  = proposal_group_create(g, "smith", "smith", on_tile(3, 4, 0))
	log    = proposal_group_create(g, "log", "log", on_tile(4, 3, 0))
	saw    = proposal_group_create(g, "hand_saw", "saw", held_by(worker, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	smith  = proposal_group_id_for(g, smith)
	log    = proposal_group_id_for(g, log)
	saw    = proposal_group_id_for(g, saw)
	error  = ""
	g      = perform(st.w, st.c, action_make("saw_through", worker, saw, log), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(st.s, time_make(2))
	a = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	world_get_field(st.w, "Activity.started", a, &start)
	for i: i64 = 0; i < 12; i += 1 {
		scheduler_run_until(st.s, time_make(start + i * 1000))
		cut[i] = -1
		world_get_field(st.w, "Log.sawn", log, &cut[i])
		if i == 5 && stop == 1 {
			bg_check(activities_suspend(activities, a, "called away", &error) != nil)
		}
		if i == 5 && stop == 2 {
			bg_check(activities_abort(activities, a, "enough", &error) != nil)
		}
		if i == 5 && stop == 3 {
			take: ^Proposal_Group

			take = proposal_group_group_with_phase(.System, "setup: the smith takes the saw")
			proposal_group_move_to(take, whole(saw), held_by(smith, 0))
			committer_submit(st.c, take)
		}
		if i == 8 && stop == 1 {
			bg_check(activities_resume(activities, a, &error) != nil)
		}
	}
	status^ = test_status_of(st.w, a)
	return true
}


/* A hard interruption, as the stage declares: a take whose item is snatched
 * from where it lay fails at once, there being nothing to come back to;
 * sawing whose saw is taken is suspended (below). */
test_hard_fail :: proc() {
	st: Stage
	activities: ^Activities
	g: ^Proposal_Group
	take: ^Proposal_Group
	worker: Entity_ID
	smith: Entity_ID
	saw: Entity_ID
	a: Entity_ID
	error: string
	trace: string
	start: i64

	st.w       = test_world(109)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	g      = proposal_group_group_with_phase(.System, "setup: a saw on the bench")
	worker = proposal_group_create(g, "worker", "worker", on_tile(3, 3, 0))
	smith  = proposal_group_create(g, "smith", "smith", on_tile(3, 4, 0))
	saw    = proposal_group_create(g, "hand_saw", "saw", on_tile(4, 3, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	smith  = proposal_group_id_for(g, smith)
	saw    = proposal_group_id_for(g, saw)
	error  = ""
	g      = perform(st.w, st.c, action_make("take_up", worker, saw, NO_ENTITY), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(st.s, time_make(2))
	a = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	world_get_field(st.w, "Activity.started", a, &start)
	take = proposal_group_group_with_phase(.System, "setup: the smith snatches the saw")
	proposal_group_move_to(take, whole(saw), held_by(smith, 0))
	committer_submit(st.c, take)
	scheduler_run_until(st.s, time_make(start + 500))
	bg_check(string(test_status_of(st.w, a)) == "\"failed\"")
	trace = strings.join(committer_trace(st.c), "\n", context.temp_allocator)
	bg_check(ns_contains(trace, ": failed (what it needs no longer holds, at roles.item.place)"))
	scheduler_run_until(st.s, time_make(start + 2000))
	bg_check(world_location_of(st.w, saw).place == smith)
}


/* AGENCY.md §6's rest: a worker already somewhat tired (40) saws a log
 * through, which takes it out of it (exertion 30): it feels tired 70, more
 * than 50, and lies down; rested through, eight hours on, its fatigue is
 * gone. */
/* ACTIONS.md §5: "rate = f(capabilities, shortfall, actor modifiers)" ...
 * "A change to any rate input, such as an injured hand ... recomputes it."
 * Provisionally (open question 4), fatigue and injury slow effortful work:
 * sawing a log (8 s, 30 exertion) takes a fresh worker 8 s, a worn-out one
 * (fatigue 100) half again as long, its quarters showing later; suspended
 * partway, what it has done is the effort, not the time. Resting goes at its
 * pace. */
test_sawn_after :: proc(fatigue: i64, at: i64, suspend: bool, injureAt: i64, done: ^i64) -> i64 {
	st: Stage
	activities: ^Activities
	g: ^Proposal_Group
	worker: Entity_ID
	log: Entity_ID
	saw: Entity_ID
	a: Entity_ID
	record: ^Activity
	error: string
	v: i64

	st.w       = test_world(193)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	g      = proposal_group_group_with_phase(.System, "setup: the sawhorse")
	worker = proposal_group_create(g, "worker", "worker", on_tile(3, 3, 0))
	log    = proposal_group_create(g, "log", "log", on_tile(4, 3, 0))
	saw    = proposal_group_create(g, "hand_saw", "saw", held_by(worker, 0))
	proposal_group_set_of_to(g, "Agent.fatigue", whole(worker), fatigue)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	log    = proposal_group_id_for(g, log)
	saw    = proposal_group_id_for(g, saw)
	error  = ""
	g      = perform(st.w, st.c, action_make("saw_through", worker, saw, log), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(st.s, time_make(2))
	a = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	if injureAt != 0 {
		/* hurt, mid-stroke: its pace changes from then */
		scheduler_run_until(st.s, time_make(injureAt))
		g = proposal_group_group_with_phase(.System, "setup: a cut hand")
		proposal_group_set_of_to(g, "Agent.injury", whole(worker), 100)
		committer_submit(st.c, g)
	}
	scheduler_run_until(st.s, time_make(at))
	if suspend {
		bg_check(activities_suspend(activities, a, "a break", &error) != nil)
		scheduler_run_until(st.s, time_make(at + 1))
	}
	record = (^Activity)(world_record(st.w, world_kind_named(st.w, "Activity"), a))
	done^  = record.progress if record != nil else -1
	v      = 0
	world_get_field(st.w, "Log.sawn", log, &v)
	return v
}


test_work_rate :: proc() {
	done: i64

	/* fresh: through at 8 s */
	bg_check(test_sawn_after(0, 8100, false, 0, &done) == 100)
	/* worn out: at 8 s half through (its quarters at 3, 6, 9 s), through at
	 * about 12 s */
	bg_check(test_sawn_after(100, 3000, false, 0, &done) == 0)
	bg_check(test_sawn_after(100, 3100, false, 0, &done) == 25)
	bg_check(test_sawn_after(100, 8100, false, 0, &done) == 50)
	bg_check(test_sawn_after(100, 12000, false, 0, &done) == 75)
	bg_check(test_sawn_after(100, 12200, false, 0, &done) == 100)
	/* suspended at 6 s worn out: four seconds' worth of sawing done, and the
	 * log shows half */
	bg_check(test_sawn_after(100, 6001, true, 0, &done) == 49 && done == 3960)
	/* a fresh worker cuts its hand two seconds in: from then it saws at its
	 * pace hurt, the rest (6 s of sawing) taking about 9 s: half through at
	 * 5 s, not 4, and through at 11 s, not 8 */
	bg_check(test_sawn_after(0, 4900, false, 2000, &done) == 25)
	bg_check(test_sawn_after(0, 5100, false, 2000, &done) == 50)
	bg_check(test_sawn_after(0, 11000, false, 2000, &done) == 75)
	bg_check(test_sawn_after(0, 11200, false, 2000, &done) == 100)
}


test_tired_worker :: proc() {
	st: Stage
	activities: ^Activities
	knowledge: ^Knowledge
	agency: ^Agency
	g: ^Proposal_Group
	worker: Entity_ID
	log: Entity_ID
	saw: Entity_ID
	error: string
	fatigue: i64

	st.w       = test_world(131)
	st.c       = test_committer(st.w)
	activities = activities_with_world(st.w, st.c)
	knowledge  = autorelease(knowledge_init_with_world(st.w))
	agency     = autorelease(agency_init_with_world(st.w, st.c, knowledge))
	st.s       = autorelease(scheduler_init_with_world(st.w, st.c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(st.s, activities_as_activity_clock(activities))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(st.s, agency_as_decision_phase(agency))
	g      = proposal_group_group_with_phase(.System, "setup: the sawhorse")
	worker = proposal_group_create(g, "worker", "worker", on_tile(3, 3, 0))
	log    = proposal_group_create(g, "log", "log", on_tile(4, 3, 0))
	saw    = proposal_group_create(g, "hand_saw", "saw", held_by(worker, 0))
	proposal_group_set_of_to(g, "Agent.fatigue", whole(worker), 40)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	log    = proposal_group_id_for(g, log)
	saw    = proposal_group_id_for(g, saw)
	bg_check(knowledge_store_feels(knowledge_store_of(knowledge, worker), "tired") == 40)
	/* fed 80, it feels hunger 20, as precisely as ever */
	bg_check(knowledge_store_feels(knowledge_store_of(knowledge, worker), "hunger") == 20)
	error = ""
	bg_check(perform(st.w, st.c, action_make("saw_through", worker, saw, log), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(10000))
	bg_check(world_get_field(st.w, "Agent.fatigue", worker, &fatigue) && fatigue == 70)
	bg_check(knowledge_store_feels(knowledge_store_of(knowledge, worker), "tired") == 70)
	/* exhausted, it would feel hunger only to the twenty: at 90, its 30 is felt 20 */
	g = proposal_group_group_with_phase(.System, "setup: worn out, and hungrier")
	proposal_group_set_of_to(g, "Agent.fatigue", whole(worker), 90)
	proposal_group_set_of_to(g, "Hungry.satiety", whole(worker), 70)
	proposal_group_set_of_to(g, "Hungry.fedAt", whole(worker), world_time(st.w).ms)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 2))
	bg_check(knowledge_store_feels(knowledge_store_of(knowledge, worker), "hunger") == 20 &&
	         knowledge_store_feels(knowledge_store_of(knowledge, worker), "tired") == 90)
	g = proposal_group_group_with_phase(.System, "setup: as tired as it was")
	proposal_group_set_of_to(g, "Agent.fatigue", whole(worker), 70)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 2))
	bg_check(knowledge_store_feels(knowledge_store_of(knowledge, worker), "hunger") == 30)
	agency_control(agency, worker)
	scheduler_run_until(st.s, time_make(20000))
	bg_check(test_logged_by(agency, worker, "weighing get some rest: +35 (tired +35)"))
	bg_check(test_logged_by(agency, worker, "[get some rest] lie down: while_away"))
	scheduler_run_until(st.s, time_make(9 * 3600000))
	bg_check(world_get_field(st.w, "Agent.fatigue", worker, &fatigue) && fatigue == 0)
	bg_check(knowledge_store_feels(knowledge_store_of(knowledge, worker), "tired") == 0)
	bg_check(test_logged_by(agency, worker, "[get some rest] done"))
}


/* AGENCY.md §6's pain: injury, a component field, is felt as pain, to the
 * band; adrenaline dulls it, not the injury. */
test_pain :: proc() {
	st: Stage
	knowledge: ^Knowledge
	g: ^Proposal_Group
	worker: Entity_ID
	injury: i64

	st.w      = test_world(139)
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	g      = proposal_group_group_with_phase(.System, "setup: a hurt hand")
	worker = proposal_group_create(g, "worker", "worker", on_tile(3, 3, 0))
	proposal_group_set_of_to(g, "Agent.injury", whole(worker), 45)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	bg_check(knowledge_store_feels(knowledge_store_of(knowledge, worker), "pain") == 40)
	g = proposal_group_group_with_phase(.System, "setup: a fright")
	proposal_group_set_of_to(g, "Agent.adrenaline", whole(worker), 30)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(2))
	bg_check(knowledge_store_feels(knowledge_store_of(knowledge, worker), "pain") == 10)
	bg_check(world_get_field(st.w, "Agent.injury", worker, &injury) && injury == 45)
	bg_check(ns_contains(knowledge_dump(knowledge, worker), "pain 10"))
}


/* KNOWLEDGE.md §5: "Each perceiver has an attention budget per boundary.
 * Salience decides what gets attention first." Mira, curious (she notices
 * anything), watches `takes` workers take up a stone each at one boundary,
 * the last of them speaking to her as well, while something clatters among
 * them. At rest she attends to ten events: the remark first (being
 * addressed), then the first nine takes; the rest go unnoticed. What is
 * left goes to the clatter, then to thinking it over. */
test_attention_scene :: proc(takes: uint) {
	st: Stage
	knowledge: ^Knowledge
	store: ^Knowledge_Store
	g: ^Proposal_Group
	mira: Entity_ID
	workers: [12]Entity_ID
	stones: [12]Entity_ID
	say: Action
	error: string
	moves: uint
	said: uint
	n: uint
	at: i64

	st.w      = test_world(167)
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	g    = proposal_group_group_with_phase(.System, "setup: a yard")
	/* two rows of six, in sight of her; the last beside her */
	mira = proposal_group_create(g, "mira", "mira", on_tile(8, 8, 0))
	proposal_group_set_of_to(g, "Agent.hiding", whole(mira), 0)
	for i: uint = 0; i < 12; i += 1 {
		place: Location         /* `at` in the Objective-C, which shadowed the time */

		place      = on_tile(4 + i32(i % 6), 7 if i < 6 else 9, 0)
		workers[i] = proposal_group_create(g, "worker", ns_utf8(fmt.tprintf("worker %d", i)), place)
		stones[i]  = proposal_group_create(g, "stone", ns_utf8(fmt.tprintf("stone %d", i)), place)
	}
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	mira = proposal_group_id_for(g, mira)
	for i: uint = 0; i < 12; i += 1 {
		workers[i] = proposal_group_id_for(g, workers[i])
		stones[i]  = proposal_group_id_for(g, stones[i])
	}
	/* the last worker starts speaking to her, a second's remark */
	error       = ""
	say         = action_make("say", workers[11], mira, NO_ENTITY)
	say.content = world_intern(st.w, "#Here & { what: #Agent }")
	bg_check(perform(st.w, st.c, say, 0, &error) != nil)
	scheduler_run_until(st.s, time_make(1000))

	/* and as it ends, they all take up their stones */
	for i: uint = 12 - takes; i < 12; i += 1 {
		bg_check(perform(st.w, st.c, action_make("take", workers[i], stones[i], NO_ENTITY), 0, &error) != nil)
	}
	/* and a clatter on the floor among them */
	g = proposal_group_group_with_phase(.System, "setup: something falls")
	make_trace(st.w, g, "clatter", NO_ENTITY, on_tile(8, 9, 0), 60, "a falling tin")
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1001))
	at = world_time(st.w).ms

	store = knowledge_store_of(knowledge, mira)
	moves = 0
	said  = 0
	for i: uint = 0; i < knowledge_store_observation_count(store); i += 1 {
		if knowledge_store_observation_at(store, i).time != at {
			continue
		}
		if string(knowledge_store_observation_at(store, i).kind) == "moved" {
			moves += 1
		}
		if string(knowledge_store_observation_at(store, i).kind) == "said" {
			said += 1
		}
	}
	bg_check(said == 1 && moves == (takes if takes < 9 else 9))
	/* the first nine takes, in the order they happened (committed) */
	n = 0
	for e: uint = 0; e < world_event_count(st.w); e += 1 {
		ev: ^Event
		kept: bool

		ev = world_event_at(st.w, e)
		if string(ev.kind) != "moved" || ev.actor == ev.subject || ev.actor == NO_ENTITY || ev.actor == mira {
			continue
		}
		kept = false
		for k: uint = 0; k < knowledge_store_observation_count(store); k += 1 {
			if knowledge_store_observation_at(store, k).time == at && string(knowledge_store_observation_at(store, k).kind) == "moved" &&
			   knowledge_store_observation_at(store, k).actor == test_referent_of(store, ev.actor) {
				kept = true
			}
		}
		bg_check(kept == (n < 9))
		n += 1
	}
	bg_check(n == takes)

	/* the clatter, new to her: with twelve takes, no attention is left to
	 * hear it; with eight, she hears it, but none is left to think it over
	 * (KNOWLEDGE.md §9: immediate interpretation, within the budget). At
	 * the next, quiet boundary, while it can still be heard, she does both */
	bg_check(test_heard_clatter(store) == (takes < 9))
	bg_check(!test_disturbed(store))
	scheduler_run_until(st.s, time_make(1500))
	bg_check(test_heard_clatter(store) && test_disturbed(store))
}


test_attention_budget :: proc() {
	test_attention_scene(12)
	test_attention_scene(8)
}


/* Whether the store has perceived a clatter. */
test_heard_clatter :: proc(store: ^Knowledge_Store) -> bool {
	for i: uint = 0; i < knowledge_store_trace_count(store); i += 1 {
		if string(knowledge_store_trace_at(store, i).kind) == "clatter" {
			return true
		}
	}
	return false
}


/* Whether the store has concluded a disturbance about anything. */
test_disturbed :: proc(store: ^Knowledge_Store) -> bool {
	for i: uint = 0; i < knowledge_store_finding_count(store); i += 1 {
		if string(knowledge_store_finding_at(store, i).kind) == "#Disturbance" {
			return true
		}
	}
	return false
}


/* INSTITUTIONS.md decision 8: particular rules are learned like anything
 * else. The town's firewood ordinance, posted on a notice by the commons:
 * the worker beside it reads it at a glance and knows it; the smith, out
 * of range, knows only the common law against theft; told it by the
 * worker, it knows it too. */
test_learning_laws :: proc() {
	st: Stage
	knowledge: ^Knowledge
	store: ^Knowledge_Store
	g: ^Proposal_Group
	worker: Entity_ID
	smith: Entity_ID
	notice: Entity_ID
	say: Action
	error: string
	ordinance: uint

	st.w      = test_world(199)
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	g      = proposal_group_group_with_phase(.System, "setup: the commons")
	proposal_group_create(g, "town", "the town", location_make_none())
	proposal_group_create(g, "theft_law", "the law against theft", location_make_none())
	proposal_group_create(g, "wood_law", "the firewood ordinance", location_make_none())
	worker = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	smith  = proposal_group_create(g, "smith", "smith", on_tile(14, 5, 0))
	notice = proposal_group_create(g, "seal_tag", "the notice", on_tile(6, 5, 0))
	proposal_group_set_of_to_text(g, "Record.writing", whole(notice),
	                              world_intern(st.w, "#Writing & { author: #Agent & { coat: \"black\" }, entries: [#LawSays & { law: #Law & " +
	                                                 "{ forbids: \"take\", wrong: \"unauthorized\", brings: \"fine\", weighs: 15 } }] }"))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1000))
	worker = proposal_group_id_for(g, worker)
	smith  = proposal_group_id_for(g, smith)

	/* everyone knows the common law; the worker read the ordinance too */
	store = knowledge_store_of(knowledge, smith)
	bg_check(knowledge_store_law_count(store) == 1 && string(knowledge_store_law_at(store, 0).wrong) == "\"anothers\"")
	store     = knowledge_store_of(knowledge, worker)
	ordinance = NOT_FOUND
	for i: uint = 0; i < knowledge_store_law_count(store); i += 1 {
		if string(knowledge_store_law_at(store, i).wrong) == "\"unauthorized\"" {
			ordinance = i
		}
	}
	bg_check(knowledge_store_law_count(store) == 2 && ordinance != NOT_FOUND && string(knowledge_store_law_at(store, ordinance).brings) == "\"fine\"" &&
	         knowledge_store_law_at(store, ordinance).weighs == 15)

	/* told it, the smith knows it */
	g = proposal_group_group_with_phase(.System, "setup: the smith comes over")
	proposal_group_move_to(g, whole(smith), on_tile(5, 6, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(2000))
	error       = ""
	say         = action_make("say", worker, smith, NO_ENTITY)
	say.content = world_intern(st.w, ns_utf8(knowledge_store_statement_of_law(store, ordinance)))
	bg_check(perform(st.w, st.c, say, 0, &error) != nil)
	scheduler_run_until(st.s, time_make(5000))
	bg_check(knowledge_store_law_count(knowledge_store_of(knowledge, smith)) == 2)
	/* saved and restored, it still knows it */
	{
		restored: ^Knowledge
		saved: Saved_System
		text: string

		text     = save(st.w, st.c, []Saved_System{knowledge_as_saved_system(knowledge)})
		restored = autorelease(knowledge_init_with_world(st.w))
		saved    = knowledge_as_saved_system(restored)
		saved.restore_saved_state(saved.data, saved_domain_state(text, "knowledge"))
		bg_check(knowledge_store_law_count(knowledge_store_of(restored, smith)) == 2 && knowledge_store_law_count(knowledge_store_of(restored, worker)) == 2)
	}
}


/* INSTITUTIONS.md decisions 2 and 3: a law is content an organization
 * issues, and whether an act breaks it is true (for the inspector); nothing
 * blocks it. The town's law against theft: Kasimir taking the merchant's
 * purse breaks it; the merchant taking its own doesn't; nor Kasimir, given
 * an authorization over it; nor taking a thing only reserved for someone. */
test_laws :: proc() {
	w: ^World
	c: ^Committer
	g: ^Proposal_Group
	town: Entity_ID
	law: Entity_ID
	merchant: Entity_ID
	kasimir: Entity_ID
	purse: Entity_ID
	claim: Entity_ID
	seal: Entity_ID
	held: Entity_ID
	broken: []Entity_ID
	error: string

	w = test_world(197)
	c = test_committer(w)
	g = proposal_group_group_with_phase(.System, "setup: the market")
	town     = proposal_group_create(g, "town", "the town", location_make_none())
	law      = proposal_group_create(g, "theft_law", "the law against theft", location_make_none())
	proposal_group_set_of_to(g, "Law.lawOf", whole(law), i64(town))
	merchant = proposal_group_create(g, "merchant", "merchant", on_tile(11, 10, 0))
	kasimir  = proposal_group_create(g, "kasimir", "kasimir", on_tile(9, 10, 0))
	purse    = proposal_group_create(g, "purse", "purse", on_tile(10, 10, 0))
	claim    = proposal_group_create(g, "ownership", "the merchant's purse", location_make_none())
	proposal_group_relate(g, .Claimant, whole(claim), whole(merchant))
	proposal_group_relate(g, .Claim_Subject, whole(claim), whole(purse))
	seal     = proposal_group_create(g, "seal", "seal", on_tile(10, 11, 0))
	held     = proposal_group_create(g, "reservation", "the seal, reserved", location_make_none())
	proposal_group_relate(g, .Claimant, whole(held), whole(merchant))
	proposal_group_relate(g, .Claim_Subject, whole(held), whole(seal))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(proposal_group_applied(g))
	town     = proposal_group_id_for(g, town)
	law      = proposal_group_id_for(g, law)
	merchant = proposal_group_id_for(g, merchant)
	kasimir  = proposal_group_id_for(g, kasimir)
	purse    = proposal_group_id_for(g, purse)
	seal     = proposal_group_id_for(g, seal)

	broken = laws_broken(w, action_make("take", kasimir, purse, NO_ENTITY))
	bg_check(len(broken) == 1 && broken[0] == law)
	bg_check(len(laws_broken(w, action_make("take", merchant, purse, NO_ENTITY))) == 0)
	bg_check(len(laws_broken(w, action_make("take", kasimir, seal, NO_ENTITY))) == 0)
	/* walking isn't taking */
	bg_check(len(laws_broken(w, action_make("walk_east", kasimir, NO_ENTITY, NO_ENTITY))) == 0)
	/* the act isn't blocked: he takes it */
	error = ""
	bg_check(perform(w, c, action_make("take", kasimir, purse, NO_ENTITY), 0, &error) != nil)
	committer_commit_boundary(c)
	bg_check(world_location_of(w, purse).place == kasimir)
	/* given an authorization over it, taking it is no theft */
	g = proposal_group_group_with_phase(.System, "setup: the merchant lets him")
	held = proposal_group_create(g, "authorization", "leave to take it", location_make_none())
	proposal_group_set_of_to(g, "Authorization.grantee", whole(held), i64(kasimir))
	proposal_group_set_of_to(g, "Authorization.over", whole(held), i64(purse))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(len(laws_broken(w, action_make("take", kasimir, purse, NO_ENTITY))) == 0)
}


/* KNOWLEDGE.md §3: "Traces on stacks trigger automatic individuation ...
 * marked units never merge." Ten nails on the floor; a scratch and a creak
 * put on the stack in one group mark one nail, split off first, and it
 * won't merge back. A nail with only a creak merges back once the creak
 * has run out. */
test_traced_units :: proc() {
	w: ^World
	c: ^Committer
	s: ^Scheduler
	g: ^Proposal_Group
	nails: Entity_ID
	marked: Entity_ID
	bearers: [2]Entity_ID
	traces: ^Store
	n: uint

	w     = test_world(163)
	c     = test_committer(w)
	nails = test_commit_create(c, "nails_10", on_tile(3, 3, 0))
	g     = proposal_group_group_with_phase(.System, "a scratch and a creak, on the stack")
	make_trace(w, g, "scratch", nails, location_make_none(), 40, "a file")
	make_trace(w, g, "creak", nails, location_make_none(), 40, "a file")
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(proposal_group_applied(g))
	bg_check(world_units_of(w, nails) == 9)
	traces = world_store_for_kind(w, world_kind_named(w, "Trace"))
	n      = 0
	for i: uint = 0; i < store_count(traces) && n < 2; i += 1 {
		bearers[n] = Entity_ID((^Trace)(store_record_at_index(traces, i)).bearer)
		n += 1
	}
	bg_check(n == 2 && bearers[0] == bearers[1] && bearers[0] != nails)
	marked = bearers[0]
	bg_check(world_is_live(w, marked) && world_units_of(w, marked) == 1 && world_has_edge(w, .Split_From, marked, nails))

	/* marked, it won't merge back */
	g = proposal_group_group_with_phase(.System, "put the marked nail back")
	proposal_group_merge(g, whole(marked), whole(nails))
	committer_submit(c, g)
	committer_commit_boundary(c)
	bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "one bears a trace"))

	/* a nail with only a creak on it: once the creak has run out, it does */
	s = autorelease(scheduler_init_with_world(w, c))
	g = proposal_group_group_with_phase(.System, "a creak alone, on the stack")
	make_trace(w, g, "creak", nails, location_make_none(), 40, "a file")
	committer_submit(c, g)
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	bg_check(proposal_group_applied(g) && world_units_of(w, nails) == 8)
	marked = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	marked = Entity_ID((^Trace)(store_record_for(traces, marked)).bearer)
	g = proposal_group_group_with_phase(.System, "put it back, creaking")
	proposal_group_merge(g, whole(marked), whole(nails))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	bg_check(!proposal_group_applied(g))
	scheduler_run_until(s, time_make(world_time(w).ms + 5000))
	g = proposal_group_group_with_phase(.System, "put it back, quiet now")
	proposal_group_merge(g, whole(marked), whole(nails))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	bg_check(proposal_group_applied(g) && world_units_of(w, nails) == 9)
}


/* KNOWLEDGE.md §3: "A trace whose perceivability would fall below its
 * kind's floor is removed at that time, which the trace system reports to
 * the scheduler as a nextEvent." A soap smell (floor 20), made at 60 to
 * last a day, is gone when it falls below 20: two thirds of the way, at
 * 16 h, a boundary of its own; scuffs (no floor) last their thirty days. */
test_trace_floor :: proc() {
	st: Stage
	traces: ^Traces
	tracesDomain: Domain
	g: ^Proposal_Group
	soap: Entity_ID
	scuffs: Entity_ID
	record: ^Trace
	born: i64

	st.w   = test_world(181)
	st.c   = test_committer(st.w)
	st.s   = autorelease(scheduler_init_with_world(st.w, st.c))
	traces = autorelease(traces_init_with_world(st.w))
	tracesDomain = traces_as_domain(traces)
	scheduler_add_domain(st.s, tracesDomain)
	g = proposal_group_group_with_phase(.System, "setup: a washed floor")
	make_trace(st.w, g, "soap_smell", NO_ENTITY, on_tile(4, 4, 0), 60, "a scrubbing")
	make_trace(st.w, g, "scuffs", NO_ENTITY, on_tile(4, 5, 0), 60, "boots")
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	soap   = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	scuffs = NO_ENTITY
	{
		for i: uint = 1; i < proposal_group_count(g); i += 1 {
			if proposal_group_proposals(g)[i].kind == .Create {
				scuffs = proposal_group_id_for(g, proposal_group_proposals(g)[i].handle)
			}
		}
	}
	record = (^Trace)(world_record(st.w, world_kind_named(st.w, "Trace"), soap))
	bg_check(record != nil && trace_gone(st.w, record) == record.created + 16 * 3600000 + 1)
	born = record.created
	bg_check(tracesDomain.horizon_at(tracesDomain.data, world_time(st.w)).nextEvent.ms == born + 16 * 3600000 + 1)
	/* still there just before; gone at its own boundary */
	bg_check(scheduler_run_until(st.s, time_make(born + 16 * 3600000)) == 1)
	bg_check(world_is_live(st.w, soap))
	bg_check(scheduler_run_until(st.s, time_make(born + 17 * 3600000)) == 2)
	bg_check(!world_is_live(st.w, soap) && world_is_live(st.w, scuffs))
}


/* KNOWLEDGE.md §3: foot traffic speeds a trace's decay, as its kind
 * declares. A damp floor and scuffs on one tile, a damp floor on the next;
 * a worker steps onto the first, off, and on again. Each step takes a
 * quarter of the damp's remaining life there; scuffs, and the damp next
 * door, keep theirs. */
test_trodden :: proc() {
	st: Stage
	g: ^Proposal_Group
	worker: Entity_ID
	damp: Entity_ID
	scuffs: Entity_ID
	beside: Entity_ID
	error: string
	v: i64
	left: i64
	born: i64

	st.w   = test_world(157)
	st.c   = test_committer(st.w)
	st.s   = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	g      = proposal_group_group_with_phase(.System, "setup: a mopped floor")
	worker = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	make_trace(st.w, g, "damp_floor", NO_ENTITY, on_tile(6, 5, 0), 80, "a mop")
	make_trace(st.w, g, "scuffs", NO_ENTITY, on_tile(6, 5, 0), 50, "boots")
	make_trace(st.w, g, "damp_floor", NO_ENTITY, on_tile(7, 5, 0), 80, "a mop")
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	damp   = NO_ENTITY
	scuffs = NO_ENTITY
	beside = NO_ENTITY
	{
		for i: uint = 0; i < proposal_group_count(g); i += 1 {
			if proposal_group_proposals(g)[i].kind == .Create {
				e: Entity_ID

				e = proposal_group_id_for(g, proposal_group_proposals(g)[i].handle)
				if world_text_field(st.w, "Trace.traceKind", e) != nil && string(world_text_field(st.w, "Trace.traceKind", e)) == "scuffs" {
					scuffs = e
				} else if world_get_field(st.w, "Trace.tileX", e, &v) && v == 7 {
					beside = e
				} else if world_get_field(st.w, "Trace.tileX", e, &v) && v == 6 {
					damp = e
				}
			}
		}
	}
	bg_check(damp != NO_ENTITY && scuffs != NO_ENTITY && beside != NO_ENTITY)

	/* onto it: a quarter of what is left of six hours, gone (within the
	 * second the step takes) */
	bg_check(world_get_field(st.w, "Trace.created", damp, &born))
	error = ""
	bg_check(perform(st.w, st.c, action_make("walk_east", worker, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(1001))
	bg_check(world_get_field(st.w, "Trace.expires", damp, &left))
	bg_check(abs((left - born) - 6 * 3600000 * 3 / 4) < 2000)
	bg_check(world_get_field(st.w, "Trace.expires", scuffs, &v) && v == born + 30 * 86400000)
	bg_check(world_get_field(st.w, "Trace.expires", beside, &v) && v == born + 6 * 3600000)
	/* off, and on again: another quarter of what is left */
	bg_check(perform(st.w, st.c, action_make("walk_west", worker, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(2002))
	bg_check(world_get_field(st.w, "Trace.expires", damp, &v) && v == left)
	bg_check(perform(st.w, st.c, action_make("walk_east", worker, NO_ENTITY, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(3003))
	bg_check(world_get_field(st.w, "Trace.expires", damp, &v) &&
	         abs((v - born) - 6 * 3600000 * 9 / 16) < 4000)
}


/* KNOWLEDGE.md §12: strength "decays at a rate set by salience and
 * repetition". The worker sees a stone beside it (`sightings` times, going
 * away for two minutes between), or moves it itself into a bin (`moves`),
 * then goes
 * away for ten days. The strength of its belief of where the stone is. */
test_remembered :: proc(sightings: i32, moves: bool, days: i64, recall: ^string) -> i32 {
	st: Stage
	knowledge: ^Knowledge
	store: ^Knowledge_Store
	g: ^Proposal_Group
	worker: Entity_ID
	stone: Entity_ID
	bin: Entity_ID
	error: string

	st.w      = test_world(151)
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	g      = proposal_group_group_with_phase(.System, "setup: a stone")
	worker = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	stone  = proposal_group_create(g, "stone", "stone", on_tile(6, 5, 0))
	bin    = proposal_group_create(g, "bin", "bin", on_tile(4, 5, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	stone  = proposal_group_id_for(g, stone)
	bin    = proposal_group_id_for(g, bin)
	for i: i32 = 1; i < sightings; i += 1 {
		test_stage_move(&st, worker, 25, 25)
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 120000))
		test_stage_move(&st, worker, 5, 5)
	}
	if moves {
		error = ""
		bg_check(perform(st.w, st.c, action_make("take", worker, stone, NO_ENTITY), 0, &error) != nil)
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
		bg_check(perform(st.w, st.c, action_make("put_in", worker, stone, bin), 0, &error) != nil)
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	}
	test_stage_move(&st, worker, 25, 25)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + days * BG_MEMORY_STEP))
	store = knowledge_store_of(knowledge, worker)
	if recall != nil {
		recall^ = knowledge_store_recall(store, knowledge_store_referent(store, test_referent_of(store, stone)))
	}
	return knowledge_store_strength_of(store, test_referent_of(store, stone))
}


/* Forgetting is a scheduled `nextEvent` (KNOWLEDGE.md §12): a stone seen
 * once fades below belief on the sixteenth day after it was last seen;
 * with nothing else happening, a boundary comes then, and it is forgotten
 * there, not at the next boundary something else brings: with nothing
 * holding it, the stone itself (KNOWLEDGE.md decision 19). */
test_scheduled_forgetting :: proc() {
	st: Stage
	knowledge: ^Knowledge
	perception: Perception_Phase
	store: ^Knowledge_Store
	g: ^Proposal_Group
	worker: Entity_ID
	stone: Entity_ID
	when_: i64      // `when` is Odin's keyword
	seen: i64

	st.w      = test_world(151)
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	perception = knowledge_as_perception_phase(knowledge)
	scheduler_set_perception(st.s, perception)
	g      = proposal_group_group_with_phase(.System, "setup: a stone")
	worker = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	stone  = proposal_group_create(g, "stone", "stone", on_tile(6, 5, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	stone  = proposal_group_id_for(g, stone)
	test_stage_move(&st, worker, 25, 25)
	store = knowledge_store_of(knowledge, worker)
	seen  = knowledge_store_referent(store, test_referent_of(store, stone)).seen
	when_ = knowledge_store_forgetting_of(store, test_referent_of(store, stone))
	bg_check(when_ == seen + 16 * BG_MEMORY_STEP)
	bg_check(perception.next_forgetting(perception.data).ms == when_)
	/* nothing but the forgetting between: one boundary there, one at the end */
	bg_check(scheduler_run_until(st.s, time_make(when_ - 1)) == 1)
	bg_check(knowledge_store_referent(store, test_referent_of(store, stone)).present)
	bg_check(scheduler_run_until(st.s, time_make(when_ + 3600000)) == 2)
	bg_check(test_referent_of(store, stone) == 0)
	bg_check(perception.next_forgetting(perception.data).ms == TIME_NEVER.ms)
}


/* KNOWLEDGE.md decision 12: perception forms doubts of its own when it
 * goes worse than usual. Worn out (fatigue 100), the worker sees the smith's
 * coat only as dark, and maybe brown, a doubt; rested and seeing it again
 * plainly, it has no doubt about it. */
test_doubts :: proc() {
	st: Stage
	knowledge: ^Knowledge
	store: ^Knowledge_Store
	g: ^Proposal_Group
	worker: Entity_ID
	smith: Entity_ID
	r: u32

	st.w      = test_world(157)
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	g      = proposal_group_group_with_phase(.System, "setup: a worn-out worker")
	worker = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	smith  = proposal_group_create(g, "smith", "smith", on_tile(7, 5, 0))
	proposal_group_set_of_to(g, "Agent.fatigue", whole(worker), 100)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1000))
	worker = proposal_group_id_for(g, worker)
	smith  = proposal_group_id_for(g, smith)
	store  = knowledge_store_of(knowledge, worker)
	r      = test_referent_of(store, smith)
	bg_check(r != 0 && ns_contains(knowledge_store_describe_referent(store, r), "coat: \"dark\""))
	bg_check(knowledge_store_hypotheses_of(store, r) == 1 && knowledge_store_mass_of(store, r, 0) == BG_DOUBT &&
	         ns_contains(knowledge_store_describe_supposed(store, r, 0), "coat: \"brown\""))
	g = proposal_group_group_with_phase(.System, "setup: rested")
	proposal_group_set_of_to(g, "Agent.fatigue", whole(worker), 0)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(2000))
	bg_check(knowledge_store_hypotheses_of(store, r) == 0 && ns_contains(knowledge_store_describe_referent(store, r), "coat: \"brown\""))
}


/* ACTIONS.md decision 14: talking takes as long as what is said. The worker
 * tells the smith beside it where three things are, in one account: three
 * seconds, not one, its voice busy all the while; the smith takes in each
 * claim. One claim alone takes a second. */
test_said_by :: proc(w: ^World, speaker: Entity_ID) -> bool {
	for i: uint = 0; i < world_event_count(w); i += 1 {
		if string(world_event_at(w, i).kind) == "said" && world_event_at(w, i).actor == speaker {
			return true
		}
	}
	return false
}


test_account :: proc() {
	st: Stage
	knowledge: ^Knowledge
	g: ^Proposal_Group
	action: Action
	worker: Entity_ID
	smith: Entity_ID
	error: string
	claim: string
	t0: i64

	for n: i32 = 1; n <= 3; n += 2 {
		st.w      = test_world(163)
		st.c      = test_committer(st.w)
		knowledge = autorelease(knowledge_init_with_world(st.w))
		st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
		scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
		scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
		g      = proposal_group_group_with_phase(.System, "setup: two in the workshop")
		worker = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
		smith  = proposal_group_create(g, "smith", "smith", on_tile(6, 5, 0))
		committer_submit(st.c, g)
		scheduler_run_until(st.s, time_make(1))
		worker = proposal_group_id_for(g, worker)
		smith  = proposal_group_id_for(g, smith)
		// a format: its braces doubled, as Odin's fmt reads them
		claim  = "#IsIn & {{ what: #Stack & {{ unit: \"iron_nail\" }}, within: #Container & {{ material: \"oak\", " +
		         "capacity: 40, place: #OnTile & {{ x: %d, y: 20, level: 0 }} }}, attribution: #Saw & {{ sure: 30 }} }}"
		action = action_make("say", worker, smith, NO_ENTITY)
		action.content = world_intern(st.w, ns_utf8(fmt.tprintf(claim, 2) if n == 1 else fmt.tprintf("#Account & {{ what: #Stack, entries: [%s, %s, %s] }}", fmt.tprintf(claim, 2), fmt.tprintf(claim, 12), fmt.tprintf(claim, 22))))
		error = ""
		t0    = world_time(st.w).ms
		bg_check(perform(st.w, st.c, action, 0, &error) != nil)
		scheduler_run_until(st.s, time_make(t0 + 1500))
		bg_check(test_said_by(st.w, worker) == (n == 1))
		bg_check(n == 1 || providers_busy(st.w, worker, "say", NO_ENTITY) != "")
		scheduler_run_until(st.s, time_make(t0 + 3500))
		bg_check(test_said_by(st.w, worker))
		bg_check(knowledge_store_testimony_count(knowledge_store_of(knowledge, smith)) == uint(n))
	}
}


/* KNOWLEDGE.md decision 14: light is a domain. A room (the shut room's air,
 * its door shut) and the yard; a lamp in the yard with an hour's oil. By the
 * clock: noon is day outdoors and dusk in the shut room, day with its door
 * open; before dawn it is dusk outdoors, dark indoors; at midnight it is
 * dark but by the lamp, until its oil is spent and it goes out. And what
 * an agent sees follows: in the yard at midnight, three tiles from the lamp
 * after it is out, it can't see the crate. */
test_light :: proc() {
	st: Stage
	knowledge: ^Knowledge
	g: ^Proposal_Group
	room: Entity_ID
	door: Entity_ID
	lamp: Entity_ID
	worker: Entity_ID
	crate: Entity_ID
	v: i64
	hour: i64
	yard: Location
	inside: Location
	byLamp: Location

	hour      = 3600000
	st.w      = test_world(167)
	bg_check(world_set_terrain_map(st.w, "rooms_map", nil))      /* TERRAIN.md: the rooms, from the map */
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	scheduler_add_domain(st.s, light_as_domain(autorelease(light_init_with_world(st.w))))
	knowledge_set_light(knowledge, autorelease(light_init_with_world(st.w)))
	g      = proposal_group_group_with_phase(.System, "setup: a room and the yard")
	room   = proposal_group_create(g, "room_air", "the room's air", location_make_none())
	door   = proposal_group_create(g, "room_door", "the room's door", on_tile(4, 6, 0))
	lamp   = proposal_group_create(g, "lamp", "the yard lamp", on_tile(20, 20, 0))
	proposal_group_set_of_to(g, "Lamp.oil", whole(lamp), hour)
	worker = proposal_group_create(g, "worker", "worker", on_tile(23, 20, 0))
	crate  = proposal_group_create(g, "crate", "crate", on_tile(26, 20, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	room   = proposal_group_id_for(g, room)
	door   = proposal_group_id_for(g, door)
	lamp   = proposal_group_id_for(g, lamp)
	worker = proposal_group_id_for(g, worker)
	crate  = proposal_group_id_for(g, crate)
	g = proposal_group_group_with_phase(.System, "setup: the room's door")
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(2))
	yard   = on_tile(10, 10, 0)
	inside = on_tile(2, 3, 0)
	byLamp = on_tile(21, 20, 0)

	bg_check(light_at(st.w, yard, 12 * hour) == 2 && light_at(st.w, inside, 12 * hour) == 1)
	bg_check(light_at(st.w, yard, 5 * hour + hour / 2) == 1 && light_at(st.w, inside, 5 * hour + hour / 2) == 0)
	bg_check(light_at(st.w, yard, hour / 2) == 0 && light_at(st.w, byLamp, hour / 2) == 2)
	/* the lamp's oil spent at an hour: out, and dark by it */
	scheduler_run_until(st.s, time_make(2 * hour))
	bg_check(world_get_field(st.w, "Lamp.shining", lamp, &v) && v == 0)
	bg_check(light_at(st.w, byLamp, 2 * hour) == 0)
	bg_check(test_referent_of(knowledge_store_of(knowledge, worker), crate) == 0)
	/* the morning: it sees the crate */
	scheduler_run_until(st.s, time_make(7 * hour))
	bg_check(test_referent_of(knowledge_store_of(knowledge, worker), crate) != 0)
	/* the door open, the room is as light as the yard */
	g = proposal_group_group_with_phase(.System, "setup: the door opened")
	proposal_group_set_of_to(g, "Door.ajar", whole(door), 1)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(7 * hour + 1000))
	bg_check(light_at(st.w, inside, 12 * hour) == 2)
}


/* KNOWLEDGE.md decision 14: sound is a domain too. A clatter in the shut
 * room (60): heard beside it; through the wall, from the corridor, too
 * faint; with the door open, heard there. And a clang by the listener (100)
 * drowns a clatter further off. */
test_hears_clatter :: proc(open: bool, clang: bool, listener: Location) -> bool {
	st: Stage
	knowledge: ^Knowledge
	g: ^Proposal_Group
	room: Entity_ID
	corridor: Entity_ID
	door: Entity_ID
	hearer: Entity_ID

	st.w      = test_world(169)
	bg_check(world_set_terrain_map(st.w, "rooms_map", nil))      /* TERRAIN.md: the rooms, from the map */
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	g        = proposal_group_group_with_phase(.System, "setup: a room off the corridor")
	corridor = proposal_group_create(g, "corridor", "the corridor", location_make_none())
	room     = proposal_group_create(g, "room_air", "the room's air", location_make_none())
	door     = proposal_group_create(g, "room_door", "the room's door", on_tile(4, 6, 0))
	hearer   = proposal_group_create(g, "watchman", "the listener", listener)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	room     = proposal_group_id_for(g, room)
	corridor = proposal_group_id_for(g, corridor)
	door     = proposal_group_id_for(g, door)
	hearer   = proposal_group_id_for(g, hearer)
	g = proposal_group_group_with_phase(.System, "setup: the door, and the sounds")
	if open {
		proposal_group_set_of_to(g, "Door.ajar", whole(door), 1)
	}
	make_trace(st.w, g, "clatter", NO_ENTITY, on_tile(2, 3, 0), 60, "the test")
	if clang {
		make_trace(st.w, g, "clang", NO_ENTITY, on_tile(listener.x + 1, listener.y, 0), 100, "the test")
	}
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(100))
	return test_traced(knowledge_store_of(knowledge, hearer), "clatter") != nil
}


test_sound :: proc() {
	/* beside it, in the room */
	bg_check(test_hears_clatter(false, false, on_tile(3, 3, 0)))
	/* in the corridor, four tiles off (rooms_map: past the wall below the
	 * room): through the wall, about 60 - 12 - 30, too faint (it fades over
	 * its two seconds) */
	bg_check(!test_hears_clatter(false, false, on_tile(5, 7, 0)))
	/* through the open door, about 60 - 12 - 10: heard */
	bg_check(test_hears_clatter(true, false, on_tile(5, 7, 0)))
	/* in the room, but a clang beside the listener drowns it */
	bg_check(!test_hears_clatter(false, true, on_tile(3, 4, 0)))
}


test_memory_rates :: proc() {
	/* seen once: BG_FADE a day */
	bg_check(test_remembered(1, false, 10, nil) == BG_SEEN - 10 * BG_FADE)
	/* sighted three times: half as fast */
	bg_check(test_remembered(3, false, 10, nil) == BG_SEEN - 10 * BG_FADE / 2)
	/* moved by its own hand (salience BG_OWN_DEED): half as fast too */
	bg_check(test_remembered(1, true, 10, nil) == BG_SEEN - 10 * BG_FADE * BG_NOTICE / BG_OWN_DEED)
	/* KNOWLEDGE.md decision 16: detail fades as strength does. Seen once,
	 * a day on, the stone's details are gone; sighted three times, it still
	 * remembers them a day on, and loses them the next */
	{
		once: string
		thrice: string

		test_remembered(1, false, 1, &once)
		test_remembered(3, false, 1, &thrice)
		bg_check(len(once) == 0 && ns_contains(thrice, "material: \"stone\""))
		test_remembered(3, false, 2, &thrice)
		bg_check(len(thrice) == 0)
	}
}


/* AGENCY.md Scenario 1's belief from habit. The worker puts the wrench
 * in the bin `times` times, taking it out again, then once in the crate,
 * and goes away. Six weeks on (its own doing, the wrench is remembered
 * twice as long as something only seen: a month isn't enough), its memory
 * of where the wrench is has faded:
 * by habit it believes it in the bin (wrongly, as Oskar does the hook);
 * with no habit, it doesn't know. The referent, described.
 * (habitual_belief: test_habitual_belief is the test's own name.) */
test_habitual_belief_run :: proc(times: i32, present: ^bool) -> string {
	st: Stage
	knowledge: ^Knowledge
	store: ^Knowledge_Store
	g: ^Proposal_Group
	worker: Entity_ID
	wrench: Entity_ID
	bin: Entity_ID
	crate: Entity_ID
	error: string

	st.w      = test_world(149)
	st.c      = test_committer(st.w)
	knowledge = autorelease(knowledge_init_with_world(st.w))
	st.s      = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_perception(st.s, knowledge_as_perception_phase(knowledge))
	g      = proposal_group_group_with_phase(.System, "setup: the tool bin")
	worker = proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	bin    = proposal_group_create(g, "bin", "bin", on_tile(6, 5, 0))
	crate  = proposal_group_create(g, "crate", "crate", on_tile(4, 5, 0))
	wrench = proposal_group_create(g, "wrench_250", "wrench", held_by(worker, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	bin    = proposal_group_id_for(g, bin)
	crate  = proposal_group_id_for(g, crate)
	wrench = proposal_group_id_for(g, wrench)
	error  = ""
	for i: i32 = 0; i < times; i += 1 {
		bg_check(perform(st.w, st.c, action_make("put_in", worker, wrench, bin), 0, &error) != nil)
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
		bg_check(perform(st.w, st.c, action_make("take", worker, wrench, NO_ENTITY), 0, &error) != nil)
		scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	}
	bg_check(perform(st.w, st.c, action_make("put_in", worker, wrench, crate), 0, &error) != nil)
	scheduler_run_until(st.s, time_make(world_time(st.w).ms + 1000))
	test_stage_move(&st, worker, 25, 25)
	scheduler_run_until(st.s, time_make(42 * BG_MEMORY_STEP))
	store    = knowledge_store_of(knowledge, worker)
	present^ = knowledge_store_referent(store, test_referent_of(store, wrench)).present
	return fmt.tprintf("%s (bin R%d, crate R%d)", knowledge_store_describe_referent(store, test_referent_of(store, wrench)),
	                   test_referent_of(store, bin), test_referent_of(store, crate))
}


test_habitual_belief :: proc() {
	habit: string
	none: string
	present: bool

	/* three times in the bin: six weeks on, it believes the wrench there,
	 * though it last put it in the crate */
	habit = test_habitual_belief_run(3, &present)
	bg_check(present && ns_contains(habit, "place: #Inside & { container: ref(2) }") &&
	         ns_contains(habit, "(bin R2, crate R3)"))
	/* once: no habit, and it doesn't know where it is, last seen in the crate */
	none  = test_habitual_belief_run(1, &present)
	bg_check(!present && ns_contains(none, "container: ref(3)"))
}


/* ACTIONS.md decision 11: graded shortfall is curves. The worker saws the
 * log with a saw `sharpness` sharp (the oak is 60 hard): the time it takes,
 * in ms; the cut's finish; and whether the saw slipped, scratching the log. */
test_shortfall_run :: proc(seed: u64, sharpness: i64, finish: ^i64, slipped: ^bool) -> i64 {
	st: Stage
	g: ^Proposal_Group
	worker: Entity_ID
	log: Entity_ID
	saw: Entity_ID
	a: Entity_ID
	error: string
	start: i64
	sawn: i64
	t: i64

	st.w = test_world(seed)
	st.c = test_committer(st.w)
	st.s = autorelease(scheduler_init_with_world(st.w, st.c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(st.w, st.c)))
	g      = proposal_group_group_with_phase(.System, "setup: the sawhorse")
	worker = proposal_group_create(g, "worker", "worker", on_tile(3, 3, 0))
	log    = proposal_group_create(g, "log", "log", on_tile(4, 3, 0))
	saw    = proposal_group_create(g, "hand_saw", "saw", held_by(worker, 0))
	proposal_group_set_of_to(g, "HandSaw.sharpness", whole(saw), sharpness)
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	log    = proposal_group_id_for(g, log)
	error  = ""
	g      = perform(st.w, st.c, action_make("saw_through", worker, proposal_group_id_for(g, saw), log), 0, &error)
	bg_check(g != nil)
	scheduler_run_until(st.s, time_make(2))
	a = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	world_get_field(st.w, "Activity.started", a, &start)
	for t = start; t < start + 60000; t += 500 {
		scheduler_run_until(st.s, time_make(t))
		sawn = 0
		if world_get_field(st.w, "Log.sawn", log, &sawn) && sawn == 100 {
			break
		}
	}
	finish^  = -1
	world_get_field(st.w, "Log.finish", log, finish)
	slipped^ = test_any_trace(st.w, "scratch")
	return t - start
}


test_shortfall :: proc() {
	finish: i64
	took: i64
	slipped: bool
	seed: u64
	slips: int

	/* as sharp as the oak is hard: eight seconds, a fine cut, no slip */
	took = test_shortfall_run(7, 60, &finish, &slipped)
	bg_check(took == 8000 && finish == 90 && !slipped)
	/* half as sharp: three times as long (a third of the rate, in whole
	 * percent), a rough cut, and a slip about one time in two, by the
	 * seeded draw */
	took = test_shortfall_run(7, 30, &finish, &slipped)
	bg_check(took > 24000 && took <= 24500 && finish == 40)      /* at a 33% rate, to the half second */
	for slips, seed = 0, 1; seed <= 40; seed += 1 {
		test_shortfall_run(seed, 30, &finish, &slipped)
		slips += 1 if slipped else 0
	}
	bg_check(slips > 10 && slips < 30)
	/* sharper than it needs: no faster, and the finest cut */
	took = test_shortfall_run(7, 90, &finish, &slipped)
	bg_check(took == 8000 && finish == 100 && !slipped)
}


test_partial_effects :: proc() {
	cut: [12]i64
	status: cstring

	/* the checkpoints are boundaries, at 2, 4 and 6 s: the cut shows a
	 * quarter at a time, then the whole on completion */
	test_saw_run(0, &cut, &status)
	bg_check(cut[1] == 0 && cut[2] == 25 && cut[3] == 25 && cut[4] == 50 && cut[6] == 75 && cut[7] == 75)
	bg_check(cut[8] == 100 && string(status) == "\"completed\"")

	/* suspended at 5 s: 62% shows, its progress kept; resumed at 8 s, it
	 * goes on from there, through the last checkpoint at 9 s, to the whole
	 * at 11 s */
	test_saw_run(1, &cut, &status)
	bg_check(cut[5] == 50 && cut[6] == 62 && cut[8] == 62)
	bg_check(cut[9] == 75 && cut[10] == 75 && cut[11] == 100 && string(status) == "\"completed\"")

	/* aborted at 5 s: its progress discarded, the 62% cut stays in the world */
	test_saw_run(2, &cut, &status)
	bg_check(cut[6] == 62 && cut[11] == 62 && string(status) == "\"aborted\"")

	/* the saw taken from its hand at 5 s: what sawing needs no longer holds,
	 * a hard interruption, and the cut stays where it got to */
	test_saw_run(3, &cut, &status)
	bg_check(cut[6] == 62 && cut[11] == 62 && string(status) == "\"suspended\"")
}


/* --- the cistern ----------------------------------------------------------- */

test_run_cistern :: proc(variant: Cistern_Variant) -> ^Cistern {
	w: ^World
	scenario: ^Cistern

	w        = test_world(7)
	scenario = autorelease(cistern_init_with_world(w, test_committer(w), variant))
	cistern_run(scenario)
	return scenario
}


test_check_cistern :: proc(scenario: ^Cistern) {
	results: []string

	results = cistern_results(scenario)
	for i := 0; i < len(results); i += 1 {
		if ns_has_prefix(results[i], "FAIL") {
			fmt.eprintf("    %s\n", results[i])
		}
	}
	bg_check(len(results) >= 4)
	bg_check(cistern_failure_count(scenario) == 0)
}


test_cistern :: proc() {
	base: ^Cistern
	a: i64
	b: i64

	base = test_run_cistern(.Base)
	test_check_cistern(base)
	/* the doc's numbers: about 7 L in each bucket, about 0.7 L on the floor */
	world_get_field(cistern_world(base), "WaterStore.water", 5, &a)
	world_get_field(cistern_world(base), "WaterStore.water", 6, &b)
	bg_check(a > 7000 && a < 7300 && b > 7000 && b < 7300)
	bg_check(world_total_tile_water(cistern_world(base)) > 650 && world_total_tile_water(cistern_world(base)) < 800)
	/* the puddle spread from the tile below the crack, and then settled: the domain sleeps */
	{
		fluid: Domain
		wet: int

		wet = 0
		for y: i32 = 0; y < 32; y += 1 {
			for x: i32 = 0; x < 32; x += 1 {
				if world_water_at_x(cistern_world(base), x, y, 0) != 0 {
					wet += 1
				}
			}
		}
		bg_check(wet > 9 && world_water_at_x(cistern_world(base), 5, 5, 0) < 100)
		bg_check(fluid_domain_checked_out_water(cistern_fluid(base)) == 0 && !world_is_tile_checked_out_x(cistern_world(base), 5, 5, 0))
		fluid = fluid_domain_as_domain(cistern_fluid(base))
		bg_check(fluid.horizon_at(fluid.data, world_time(cistern_world(base))).nextEvent.ms == TIME_NEVER.ms)
	}
}


test_cistern_b :: proc() {
	test_check_cistern(test_run_cistern(.Earlier))
}


/* A watch: A stops at 3 L, closing the tap; B fills on */
test_cistern_e :: proc() {
	test_check_cistern(test_run_cistern(.Stops_Early))
}


/* 2. order independence: the domain's inside order can't change anything */
test_cistern_d :: proc() {
	base: ^Cistern
	reversed: ^Cistern

	base     = test_run_cistern(.Base)
	reversed = test_run_cistern(.Reversed)
	test_check_cistern(reversed)
	bg_check(world_state_hash(cistern_world(reversed)) == world_state_hash(cistern_world(base)))
	bg_check(slice.equal(fluid_domain_log(cistern_fluid(reversed)), fluid_domain_log(cistern_fluid(base))))
}


/* While the water flows, the domain has it: commitment refuses to set it. */
test_checked_out :: proc() {
	w: ^World
	c: ^Committer
	scenario: ^Cistern
	g: ^Proposal_Group

	w        = test_world(7)
	c        = test_committer(w)
	scenario = autorelease(cistern_init_with_world(w, c, .Base))
	cistern_run_until(scenario, time_make(30000))
	bg_check(world_is_checked_out(w, 5) && fluid_domain_checked_out_water(cistern_fluid(scenario)) > 0)
	g = proposal_group_group_with_phase(.Action, "pour it out")
	proposal_group_set_of_to(g, "WaterStore.water", whole(5), 0)
	committer_submit(c, g)
	world_set_boundary(w, world_boundary(w) + 1)
	committer_commit_boundary(c)
	bg_check(!proposal_group_applied(g) && ns_contains(proposal_group_rejection(g), "checked out"))
	bg_check(cistern_total_water(scenario) == 15000)
}


/* Saving while the water flows: the domain checks in and keeps its carries,
 * and a world restored from the save, with a fresh domain given them, ends
 * exactly where the run that never saved does. */
test_cistern_save :: proc() {
	reference: ^Cistern
	scenario: ^Cistern
	w1: ^World
	w2: ^World
	c1: ^Committer
	c2: ^Committer
	text: string
	error: string
	deferred: []^Proposal_Group
	position: u64

	w1        = test_world(7)
	reference = autorelease(cistern_init_with_world(w1, test_committer(w1), .Base))
	cistern_run_until(reference, time_make(30000))
	cistern_finish(reference)
	w1        = test_world(7)
	c1        = test_committer(w1)
	scenario  = autorelease(cistern_init_with_world(w1, c1, .Base))
	cistern_run_until(scenario, time_make(30000))
	text = save(w1, c1, []Saved_System{domain_as_saved_system(fluid_domain_as_domain(cistern_fluid(scenario)))})
	bg_check(ns_contains(text, "domain fluid carry"))
	bg_check(!world_is_checked_out(w1, 5) && cistern_total_water(scenario) == 15000)

	error = ""
	w2    = restore(text, world_content_build(w1), &deferred, &position, &error)
	bg_check(w2 != nil)
	if w2 == nil {
		fmt.eprintf("    %s\n", error)
		return
	}
	bg_check(world_state_hash(w2) == world_state_hash(w1))
	c2 = test_committer(w2)
	committer_set_position(c2, position)
	committer_restore_deferred(c2, deferred)
	cistern_resume_with_world(scenario, w2, c2, saved_domain_state(text, "fluid"))
	cistern_finish(scenario)
	test_check_cistern(scenario)
	bg_check(world_state_hash(w2) == world_state_hash(cistern_world(reference)))
}


/* --- saves ----------------------------------------------------------------- */

test_restore :: proc(text: string, content: ^tri.Content, committer: ^^Committer, error: ^string) -> ^World {
	world: ^World
	deferred: []^Proposal_Group
	position: u64

	world = restore(text, content, &deferred, &position, error)
	if world == nil {
		return nil
	}
	committer^ = test_committer(world)
	committer_set_position(committer^, position)
	committer_restore_deferred(committer^, deferred)
	return world
}


/* Save halfway through the marked nail, restore into a fresh world, and carry
 * on: the restored world takes exactly the steps the original would have. */
test_save_and_resume :: proc() {
	reference: ^Marked_Nail
	scenario: ^Marked_Nail
	w1: ^World
	w2: ^World
	c1: ^Committer
	c2: ^Committer
	text: string
	error: string
	full: []string
	rest: []string
	before: uint

	/* the reference stops where the saving run does: a stop is a boundary */
	w1        = test_world(42)
	reference = autorelease(marked_nail_init_with_world(w1, test_committer(w1), .Base))
	marked_nail_run_until(reference, time_make(5500))
	marked_nail_finish(reference)
	w1        = test_world(42)
	c1        = test_committer(w1)
	scenario  = autorelease(marked_nail_init_with_world(w1, c1, .Base))
	marked_nail_run_until(scenario, time_make(5500))          /* after the hammering, before the nail comes out */
	text   = save(w1, c1, nil)
	before = uint(len(committer_trace(c1)))

	error = ""
	w2    = test_restore(text, world_content_build(w1), &c2, &error)
	bg_check(w2 != nil)
	if w2 == nil {
		fmt.eprintf("    %s\n", error)
		return
	}
	bg_check(world_state_hash(w2) == world_state_hash(w1))
	bg_check(save(w2, c2, nil) == text)
	bg_check(world_time(w2).ms == 5500 && world_boundary(w2) == world_boundary(w1) && world_next_id(w2) == world_next_id(w1))

	marked_nail_resume_with_world(scenario, w2, c2)
	marked_nail_finish(scenario)
	test_check_scenario(scenario)
	bg_check(world_state_hash(w2) == world_state_hash(marked_nail_world(reference)))
	/* the trace after the save is the reference's, line for line */
	full = committer_trace(marked_nail_committer(reference))
	rest = committer_trace(c2)
	bg_check(before + uint(len(rest)) == uint(len(full)))
	bg_check(uint(len(full)) >= before && slice.equal(rest, full[before:][:uint(len(full)) - before]))
}


/* Deferred groups are saved too: they commit at the restored world's next boundary. */
test_save_deferred_groups :: proc() {
	w1: ^World
	w2: ^World
	c1: ^Committer
	c2: ^Committer
	g: ^Proposal_Group
	claim: Entity_ID
	error: string

	w1    = test_world(3)
	c1    = test_committer(w1)
	claim = test_commit_create(c1, "ownership", location_make_none())
	g     = proposal_group_group_with_phase(.System, "later")
	proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 12)
	committer_restore_deferred(c1, []^Proposal_Group{g})
	w2 = test_restore(save(w1, c1, nil), world_content_build(w1), &c2, &error)
	bg_check(w2 != nil && len(committer_deferred_groups(c2)) == 1)
	world_set_boundary(w2, world_boundary(w2) + 1)
	committer_commit_boundary(c2)
	bg_check(len(committer_deferred_groups(c2)) == 0)
	{
		q: i64

		bg_check(world_get_field(w2, "Claim.quantity", claim, &q) && q == 12)
	}
}


test_restore_errors :: proc() {
	w: ^World
	c: ^Committer
	content: ^tri.Content
	error: string
	text: string

	w       = test_world(1)
	c       = test_committer(w)
	content = world_content_build(w)
	test_commit_create(c, "bin", on_tile(0, 0, 0))
	text    = save(w, c, nil)

	error = ""
	bg_check(restore("not a save\n", content, nil, nil, &error) == nil)
	bg_check(ns_contains(error, "not a bruggadung save"))
	bg_check(restore(ns_replace(text, "capacity", "volume"),
	                 content, nil, nil, &error) == nil)
	bg_check(ns_contains(error, "no field Container.volume"))
	bg_check(restore(ns_replace(text, "\\\"oak\\\"", "\\\"teak\\\""),
	                 content, nil, nil, &error) == nil)
	bg_check(ns_contains(error, "no type \"teak\""))
	bg_check(restore(ns_replace(text, "end\n", ""),
	                 content, nil, nil, &error) == nil)
	bg_check(ns_contains(error, "ends early"))
}


// BGAllTests: every test in the three parts, in the Objective-C's order.
ALL_TESTS := [?]Test_Case{
	{"store",                         test_store},
	{"registry_and_construction",     test_registry_and_construction},
	{"rollback",                      test_rollback},
	{"validation",                    test_validation},
	{"individuation_and_merge_rules", test_individuation_and_merge_rules},
	{"seeded_order",                  test_seeded_order},
	{"reaction_rounds",               test_reaction_rounds},
	{"scheduler_horizons",            test_scheduler_horizons},
	{"marked_nail",                   test_marked_nail},
	{"marked_nail_a",                 test_marked_nail_a},
	{"marked_nail_found",             test_marked_nail_found},
	{"marked_nail_b",                 test_marked_nail_b},
	{"marked_nail_replay",            test_marked_nail_replay},
	{"menu",                          test_menu},
	{"activity_interrupted",          test_activity_interrupted},
	{"activity_fails",                test_activity_fails},
	{"stages_and_suspension",         test_stages_and_suspension},
	{"stage_traces",                  test_stage_traces},
	{"play",                          test_play},
	{"play_talk",                     test_play_talk},
	{"stale_belief",                  test_stale_belief},
	{"missing_nails",                 test_missing_nails},
	{"asking",                        test_asking},
	{"routine",                       test_routine},
	{"needs",                         test_needs},
	{"habits",                        test_habits},
	{"promises",                      test_promises},
	{"two_hands",                     test_two_hands},
	{"coat_at_dusk",                  test_coat_at_dusk},
	{"unknown_nut",                   test_unknown_nut},
	{"seized_valve",                  test_seized_valve},
	{"access_resume",                 test_access_resume},
	{"providers_pending",             test_providers_pending},
	{"memory_rates",                  test_memory_rates},
	{"scheduled_forgetting",          test_scheduled_forgetting},
	{"trodden",                       test_trodden},
	{"trace_floor",                   test_trace_floor},
	{"work_rate",                     test_work_rate},
	{"traced_units",                  test_traced_units},
	{"attention_budget",              test_attention_budget},
	{"laws",                          test_laws},
	{"learning_laws",                 test_learning_laws},
	{"routine_autopilot",             test_routine_autopilot},
	{"daily_commitment",              test_daily_commitment},
	{"talking_takes_time",            test_talking_takes_time},
	{"reading_takes_time",            test_reading_takes_time},
	{"explore_autopilot",             test_explore_autopilot},
	{"explore_rooms",                 test_explore_rooms},
	{"paths",                         test_paths},
	{"spatial_index",                 test_spatial_index},
	{"water_at_scale",                test_water_at_scale},
	{"work_when_touched",             test_work_when_touched},
	{"reality_bubble",                test_reality_bubble},
	{"reduced_detail",                test_reduced_detail},
	{"frozen_detail",                 test_frozen_detail},
	{"recipe_autopilot",              test_recipe_autopilot},
	{"resume_recheck",                test_resume_recheck},
	{"interrupted_repair",            test_interrupted_repair},
	{"unattended_stove",              test_unattended_stove},
	{"local_wake",                    test_local_wake},
	{"cold_lodger",                   test_cold_lodger},
	{"stuffy_lodger",                 test_stuffy_lodger},
	{"partial_effects",               test_partial_effects},
	{"hard_fail",                     test_hard_fail},
	{"tired_worker",                  test_tired_worker},
	{"pain",                          test_pain},
	{"habitual_belief",               test_habitual_belief},
	{"forged_permit",                 test_forged_permit},
	{"issue_permit",                  test_issue_permit},
	{"latent_pump",                   test_latent_pump},
	{"pump_wear",                     test_pump_wear},
	{"part_condition",                test_part_condition},
	{"servicing",                     test_servicing},
	{"diligence",                     test_diligence},
	{"terrain",                       test_terrain},
	{"sight_and_memory",              test_sight_and_memory},
	{"rooms",                         test_rooms},
	{"air_follows_terrain",           test_air_follows_terrain},
	{"rooms_at_scale",                test_rooms_at_scale},
	{"pump_heat",                     test_pump_heat},
	{"pump_heat_running",             test_pump_heat_running},
	{"component_pump",                test_component_pump},
	{"improvise",                     test_improvise},
	{"door_in_the_dark",              test_door_in_the_dark},
	{"wrench_replaced",               test_wrench_replaced},
	{"rumour",                        test_rumour},
	{"memory_decay",                  test_memory_decay},
	{"salience",                      test_salience},
	{"going_without",                 test_going_without},
	{"starving_sight",                test_starving_sight},
	{"doubts",                        test_doubts},
	{"account",                       test_account},
	{"shortfall",                     test_shortfall},
	{"recipes",                       test_recipes},
	{"light",                         test_light},
	{"sound",                         test_sound},
	{"traces",                        test_traces},
	{"appearance",                    test_appearance},
	{"interpretation",                test_interpretation},
	{"notebook",                      test_notebook},
	{"play_notebook",                 test_play_notebook},
	{"false_alarm",                   test_false_alarm},
	{"play_autopilot",                test_play_autopilot},
	{"tempting_purse",                test_tempting_purse},
	{"cistern",                       test_cistern},
	{"cistern_b",                     test_cistern_b},
	{"cistern_d",                     test_cistern_d},
	{"cistern_e",                     test_cistern_e},
	{"checked_out",                   test_checked_out},
	{"cistern_save",                  test_cistern_save},
	{"save_and_resume",               test_save_and_resume},
	{"save_deferred_groups",          test_save_deferred_groups},
	{"restore_errors",                test_restore_errors},
	{"formatting",                    test_formatting},
	{"watcher",                       test_watcher},
	{"village",                       test_village},
	{"looks",                         test_looks},
	{"cooking",                       test_cooking},
	{"seen_kinds",                    test_seen_kinds},
	{"identity_from_context",         test_identity_from_context},
	{"identity_lost_and_found",       test_identity_lost_and_found},
	{"identity_own",                  test_identity_own},
	{"forgetting",                    test_forgetting},
	{"habits_give_way",               test_habits_give_way},
	{"history",                       test_history},
	{"firewood",                      test_firewood},
	{"farming",                       test_farming},
	{"farming_weeks",                 test_farming_weeks},
	{"death",                         test_death},
	{"animals",                       test_animals},
	{"bow",                           test_bow},
	{"aim",                           test_aim},
	{"butcher",                       test_butcher},
	{"hunting_week",                  test_hunting_week},
	{"perishing",                     test_perishing},
	{"market",                        test_market},
	{"carrying",                      test_carrying},
	{"scene_knowledge",               test_scene_knowledge},
	{"keep_seed",                     test_keep_seed},
	{"units_name_instances",          test_units_name_instances},
}

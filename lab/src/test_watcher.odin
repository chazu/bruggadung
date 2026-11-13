package lab

/*
 * Watching changes nothing: a crowd run in the slices a watcher takes, with
 * an autorelease pool drained after each and a truth scene, a worker's
 * knowledge scene and what it recalls of itself built between, ends where
 * the same crowd run in one go does (watcher.odin).
 */

import "core:strings"

import "../../tessera"


test_watcher :: proc() {
	hashes: [2]u64
	marks:  int
	known:  int                            /* slices the worker had knowledge in */

	for run in 0 ..< 2 {
		w, why := watcher_open("crowd", 12)
		bg_check(why == "")
		if why != "" do return
		if run == 0 {
			bg_check(watcher_step_until(&w, 20000, max(u64)))
		} else {
			/* uneven slices, as frames are: 1 ms to 1.4 s */
			for t: i64 = 1; t < 20000; t += 1 + (t * 7919) % 1400 {
				pool_push()
				watcher_step_until(&w, t, max(u64))
				s := scene_truth(w.world, {x0 = 0, y0 = 0, w = 96, h = 64, z0 = 0, z1 = 0, focus = 0}, u64(t),
				                 context.temp_allocator)
				bg_check(s != nil && s.meta.view == .Truth && s.meta.time == world_time(w.world).ms)
				if s != nil do marks = len(s.marks)
				k := watcher_scene(&w, w.ids[0], {x0 = 0, y0 = 0, w = 96, h = 64, z0 = 0, z1 = 0, focus = 0}, u64(t))
				bg_check(k != nil && k.meta.view == .Knowledge)
				if watcher_knows(&w, w.ids[0]) {
					known += 1
					me := watcher_self_of(&w, w.ids[0])
					m := tessera.mark_find(k, u64(me)) if k != nil else nil
					bg_check(m != nil && .Actor in m.flags && len(watcher_recall(&w, w.ids[0], me)) >= 3)
				}
				pool_drain()
			}
			watcher_step_until(&w, 20000, max(u64))
		}
		hashes[run] = world_state_hash(w.world)
		moved := 0                         /* the explorers went somewhere */
		for id, i in w.ids {
			x, y, _, _ := watcher_tile_of(&w, id)
			if x != (i32(i) * 37) % 96 || y != (i32(i) * 23) % 64 do moved += 1
		}
		bg_check(moved >= 3)
		delete(w.ids)
		delete(w.title)
	}
	bg_check(hashes[0] == hashes[1])
	bg_check(marks >= 12)                  /* the workers, and what they carry */
	bg_check(known > 10)

	/* a scene is clipped to the world, and names each worker where it stands */
	w, _ := watcher_open("crowd", 3)
	s := scene_truth(w.world, {x0 = -10, y0 = -10, w = 200, h = 200, z0 = -1, z1 = 3, focus = 0}, 1,
	                 context.temp_allocator)
	bg_check(s != nil && s.extent.x0 == 0 && s.extent.w == 96 && s.extent.h == 64 && s.extent.z1 == 0)
	for id in w.ids {
		x, y, z, ok := watcher_tile_of(&w, id)
		m := tessera.mark_find(s, u64(id)) if s != nil else nil
		bg_check(ok && m != nil && m.x == x && m.y == y && m.z == z && m.stack > 0)
		if m != nil do bg_check(tessera.look_name(s, m.look) == "agent")   /* a worker looks as an agent */
	}
	delete(w.ids)
	delete(w.title)
}


/*
 * What the watcher's panes read (watcher_inspect.odin): the marked nail's
 * proposal groups are in the log, the latest first, a line to each; the taking of a nail names the
 * operation that declares it and who and what filled its roles; the
 * operation's text is found in the content as it is written; and a
 * component's type is found wherever it is declared, a topic's additions
 * among them.
 */
test_watcher_panes :: proc() {
	w, why := watcher_open("marked-nail", 0)
	bg_check(why == "")
	if why != "" do return
	defer delete(w.title)
	bg_check(watcher_step_until(&w, 3_600_000, max(u64)))

	log := watcher_log(&w, NO_ENTITY, 1000)
	bg_check(len(log) > 5)
	for i in 1 ..< len(log) do bg_check(log[i].event < log[i - 1].event)
	bg_check(strings.contains(log[len(log) - 1].text, "setup: the workshop: created x"))   /* a line to a group */
	about := watcher_log(&w, 4, 1000)                  /* the worker's: fewer */
	bg_check(len(about) > 0 && len(about) < len(log))

	taken: u64
	for line in log do if watcher_declared_by(&w, line.event) == "take" do taken = line.event
	bg_check(strings.contains(watcher_event(&w, taken)[0].text, "event"))
	bg_check(taken != 0)
	if taken != 0 {
		named, actor := false, false
		for line in watcher_event(&w, taken) {
			if line.declared == "take" do named = true
			if line.entity == 4 && strings.has_prefix(line.text, "  actor:") do actor = true
		}
		bg_check(named && actor)
	}
	bg_check(watcher_declared_by(&w, log[len(log) - 1].event) == "")   /* the setup: code */

	decls := watcher_declared(&w, "take")
	bg_check(len(decls) == 1)
	if len(decls) == 1 {
		first, text := watcher_source(decls[0].file, decls[0].line)
		bg_check(first >= 1 && first <= decls[0].line && len(text) >= 2)
		bg_check(strings.contains(strings.join(text, "\n", context.temp_allocator), "take: #Taking"))
		bg_check(strings.trim_space(text[len(text) - 1]) != "")
	}
	bg_check(len(watcher_declared(&w, "#Agent")) > 1)   /* the root's, and topics' fields */
	bg_check(len(watcher_declared(&w, "no_such_thing")) == 0)
	bg_check(len(watcher_files(&w)) > 20)

	of := watcher_declarations_of(&w, 4)
	bg_check(len(of) >= 2 && len(watcher_declared(&w, of[0])) >= 1 && strings.has_prefix(of[1], "#"))
}

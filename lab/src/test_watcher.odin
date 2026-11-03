package lab

/*
 * Watching changes nothing: a crowd run in the slices a watcher takes, with
 * an autorelease pool drained after each and a truth scene built between,
 * ends where the same crowd run in one go does (watcher.odin).
 */

import "../../tessera"


test_watcher :: proc() {
	hashes: [2]u64
	marks:  int

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

	/* a scene is clipped to the world, and names each worker where it stands */
	w, _ := watcher_open("crowd", 3)
	s := scene_truth(w.world, {x0 = -10, y0 = -10, w = 200, h = 200, z0 = -1, z1 = 3, focus = 0}, 1,
	                 context.temp_allocator)
	bg_check(s != nil && s.extent.x0 == 0 && s.extent.w == 96 && s.extent.h == 64 && s.extent.z1 == 0)
	for id in w.ids {
		x, y, z, ok := watcher_tile_of(&w, id)
		m := tessera.mark_find(s, u64(id)) if s != nil else nil
		bg_check(ok && m != nil && m.x == x && m.y == y && m.z == z && m.stack > 0)
		if m != nil do bg_check(tessera.look_name(s, m.look) == "worker")
	}
	delete(w.ids)
	delete(w.title)
}

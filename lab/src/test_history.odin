package lab

/*
 * History (KNOWLEDGE.md decision 21): a debug field's changes aren't logged
 * unless the world asks; a walk's steps along the way are diagnostic, and
 * how it set out and ended is history; diagnostic events are compacted
 * after the window, counted into digests, and history keeps its indices;
 * a world saved between compactions resumes exactly.
 */

import "core:fmt"


/* A worker on the open floor, walking along a row and back, a walk of
 * twenty tiles each way, checked each second; history's window `window` ms
 * (0: kept for good); saved at `saveAt` and carried on in a world restored
 * from it (0: not); until `until` ms. Its save at the end. */
@(private = "file")
test_history_walks :: proc(window: i64, saveAt: i64, until: i64, debug := false) -> (text: string, w: ^World, walker: Entity_ID) {
	st:    Stage
	error: string

	debug_history = debug
	defer debug_history = false
	st.w = test_world(7)
	st.c = test_committer(st.w)
	st    = test_history_stage(st.w, st.c)
	world_set_history_window(st.w, window)
	g      := proposal_group_group_with_phase(.System, "setup: a worker")
	worker := proposal_group_create(g, "worker", "worker", on_tile(5, 5, 0))
	committer_submit(st.c, g)
	scheduler_run_until(st.s, time_make(1))
	worker = proposal_group_id_for(g, worker)
	for t := i64(1); t < until; t += 1000 {
		if saveAt != 0 && t == saveAt {
			saved := save(st.w, st.c, nil)
			st.w = test_restore(saved, world_content_build(st.w), &st.c, &error)
			if st.w == nil {
				bg_check(false)
				return "", nil, NO_ENTITY
			}
			st = test_history_stage(st.w, st.c)
		}
		if !test_history_walking(st.w, worker) {
			action := action_make(world_intern(st.w, "walk"), worker, NO_ENTITY, NO_ENTITY)
			east   := world_location_of(st.w, worker).x < 15
			action.way = world_intern(st.w, "eeeeeeeeeeeeeeeeeeee" if east else "wwwwwwwwwwwwwwwwwwww")
			bg_check(perform(st.w, st.c, action, 0, &error) != nil)
		}
		scheduler_run_until(st.s, time_make(t + 1000))
	}
	return save(st.w, st.c, nil), st.w, worker
}


@(private = "file")
test_history_stage :: proc(w: ^World, c: ^Committer) -> Stage {
	st := Stage{w = w, c = c}
	st.s = autorelease(scheduler_init_with_world(w, c))
	scheduler_set_activities(st.s, activities_as_activity_clock(activities_with_world(w, c)))
	return st
}


@(private = "file")
test_history_walking :: proc(w: ^World, who: Entity_ID) -> bool {
	n: uint

	mine := world_copy_activities_of(w, who, &n)
	defer free(mine)
	for i: uint = 0; i < n; i += 1 {
		record := (^Activity)(world_record(w, world_kind_named(w, "Activity"), mine[i]))
		if record != nil && record.status == ACTIVITYSTATUS_RUNNING do return true
	}
	return false
}


@(private = "file")
test_history_count :: proc(w: ^World, kind: string, detail: string, diagnostic: int) -> int {
	n := 0
	for ev in world_history(w) {
		if string(ev.kind) != kind || (detail != "" && (ev.detail == nil || string(ev.detail) != detail)) do continue
		if diagnostic < 0 || ev.diagnostic == (diagnostic == 1) do n += 1
	}
	return n
}


test_history :: proc() {
	/* 1: debug fields: an activity's timing is reckoned at every stage, and
	 * isn't history unless asked for; asked, the rest is the same */
	_, plain, walker := test_history_walks(0, 0, 60001)
	_, debug, _      := test_history_walks(0, 0, 60001, debug = true)
	bg_check(test_history_count(plain, "changed", "Activity.due", -1) == 0 &&
	         test_history_count(plain, "changed", "Activity.started", -1) == 0)
	bg_check(test_history_count(debug, "changed", "Activity.due", -1) > 0)
	bg_check(world_location_of(plain, walker) == world_location_of(debug, walker) &&
	         test_history_count(plain, "moved", "", -1) == test_history_count(debug, "moved", "", -1))

	/* 2: a walk's tiles between are diagnostic; where it set out for, its
	 * arrival and how it ended are history: in a minute, walks of twenty
	 * tiles, each arrival history, every tile before it not */
	walks     := test_history_count(plain, "changed", "Activity.way", 0)
	completed := test_history_count(plain, "changed", "Activity.status", 0)
	bg_check(walks >= 2 && completed >= 2 && walks - completed <= 1)
	bg_check(test_history_count(plain, "moved", "", 0) == completed)
	bg_check(test_history_count(plain, "moved", "", 1) >= 19 * completed)
	bg_check(test_history_count(plain, "changed", "Activity.stage", 0) == 0 &&
	         test_history_count(plain, "changed", "Activity.stage", 1) == test_history_count(plain, "moved", "", 1))

	/* 3: compacted, a minute's window, over five minutes: history is what it
	 * would have been, each event at its index; the diagnostic events
	 * older than the window are gone, counted in digests */
	_, kept, _              := test_history_walks(0, 0, 300001)
	compactText, compact, _ := test_history_walks(60000, 0, 300001)
	bg_check(world_event_count(compact) == world_event_count(kept))
	bg_check(test_history_count(compact, "moved", "", 0) == test_history_count(kept, "moved", "", 0) &&
	         test_history_count(compact, "changed", "", 0) == test_history_count(kept, "changed", "", 0) &&
	         test_history_count(compact, "created", "", 0) == test_history_count(kept, "created", "", 0))
	every := true
	for &ev in world_history(compact) do every &&= world_event_at(compact, uint(ev.index - 1)) == &ev
	bg_check(every)
	diagnostic := test_history_count(kept, "moved", "", 1) + test_history_count(kept, "changed", "Activity.stage", 1)
	left       := test_history_count(compact, "moved", "", 1) + test_history_count(compact, "changed", "Activity.stage", 1)
	digested   := 0
	for d in world_digests(compact) do digested += int(d.count)
	bg_check(left < diagnostic && digested > 0 && left + digested == diagnostic)
	/* the steps compacted are gone: their indices say so */
	gone := 0
	for ev in world_history(kept) {
		if ev.diagnostic && world_event_at(compact, uint(ev.index - 1)) == nil do gone += 1
	}
	bg_check(gone == digested)
	/* digests by chunk, kind and actor, for the window they were emitted in */
	placed := false
	for d in world_digests(compact) {
		if string(d.kind) == "moved" && d.placed && d.cx == 0 && d.cy == 0 && d.actor == walker && d.until - d.from == 60000 {
			placed = true
		}
	}
	bg_check(placed)
	if !placed do for d in world_digests(compact) do fmt.printf("    digest %v\n", d)

	/* 4: saved between compactions, restored and carried on: the same, to the
	 * last digest */
	resumedText, _, _ := test_history_walks(60000, 150001, 300001)
	bg_check(resumedText == compactText)
}

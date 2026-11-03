package lab

/*
 * BGBench — measuring the simulation at scale (REALITY.md, step 1): a crowd
 * on a yard, run for a while, and where the time went.
 *
 * (ported from the Objective-C lab's test/BGBench.m)
 */

import "core:fmt"
import "core:time"


@(private = "file")
ms_of :: proc(ns: u64) -> f64 {
	return f64(ns) / 1e6
}


/* `agents` on yard_map (96 x 64), every other one exploring, the rest idle
 * with minds of their own; run for `seconds` of the world's time. Prints
 * boundaries, perceptions and decisions, and the wall time of each phase.
 * Returns 0. */
bench_crowd :: proc(agents: i32, seconds: i64) -> i32 {
	return bench_crowd_spread(agents, seconds, false, nil)
}


/* The same, spread: on plain_map (1024 x 1024), ten tiles apart, so each
 * has as many near it however many there are. */
// anchored is a cstring, nil for none (the C string).
bench_crowd_spread :: proc(agents: i32, seconds: i64, spread: bool, anchored: cstring) -> i32 {
	side:       i32
	w:          ^World
	c:          ^Committer
	s:          ^Scheduler
	activities: ^Activities
	knowledge:  ^Knowledge
	agency:     ^Agency
	g:          ^Proposal_Group
	st:         Scheduler_Stats
	st0:        Scheduler_Stats
	p0:         u64
	d0:         u64
	e0:         uint
	ids:        [^]Entity_ID
	t0:         time.Tick
	t1:         time.Tick
	wall:       f64

	w = test_world(211)
	// a message to nil said NO
	if w == nil || !world_set_terrain_map(w, "plain_map" if spread else "yard_map", nil) {
		fmt.eprintf("bench: no map\n")
		return 1
	}
	/* spread: as many to a stretch of plain however many there are, ten
	 * tiles apart on a square; else all on the yard */
	for side = 1; side * side < agents; side += 1 {
	}
	c          = test_committer(w)
	committer_set_tracing(c, false)                  /* a large world's: no trace kept */
	activities = activities_with_world(w, c)
	knowledge  = autorelease(knowledge_init_with_world(w))
	agency     = autorelease(agency_init_with_world(w, c, knowledge))
	s          = autorelease(scheduler_init_with_world(w, c))
	agency_set_activities(agency, activities)
	scheduler_set_activities(s, activities_as_activity_clock(activities))
	scheduler_set_perception(s, knowledge_as_perception_phase(knowledge))
	scheduler_set_decision(s, agency_as_decision_phase(agency))
	ids = make([^]Entity_ID, int(agents + 1))
	g   = proposal_group_group_with_phase(.System, "bench: a crowd on the yard")
	for i: i32 = 0; i < agents; i += 1 {
		ids[i] = proposal_group_create(g, "worker", ns_utf8(fmt.tprintf("worker %d", i)),
		                               (on_tile(20 + (i % side) * 10, 20 + (i / side) * 10, 0) if spread
		                                else on_tile((i * 37) % 96, (i * 23) % 64, 0)))
	}
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	for i: i32 = 0; i < agents; i += 1 do ids[i] = proposal_group_id_for(g, ids[i])
	/* they start through the first second, not all at once, as a crowd
	 * would: their walks end at their own times */
	for i: i32 = 0; i < agents; i += 1 {
		scheduler_run_until(s, time_make(2 + i64(i) * 997 / i64(agents)))
		if i % 2 != 0 {
			agency_control(agency, ids[i])
		} else {
			agency_autopilot_explore(agency, ids[i], 50)
		}
	}
	/* the first anchors the reality bubble: the rest further off, less exactly */
	if anchored != nil {
		if !world_set_anchor(w, ids[0], anchored) {
			fmt.eprintf("bench: no kind of anchor called %s\n", anchored)
			return 1
		}
		world_settle_anchors(w)
	}
	st0 = scheduler_stats(s)
	p0  = knowledge_perceptions(knowledge)
	d0  = agency_decisions(agency)
	e0  = world_event_count(w)

	t0 = time.tick_now()             // clock_gettime( CLOCK_MONOTONIC)
	scheduler_run_until(s, time_make(1 + seconds * 1000))
	t1 = time.tick_now()
	wall = time.duration_milliseconds(time.tick_diff(t0, t1))

	st = scheduler_stats(s)
	st.boundaries   -= st0.boundaries
	st.horizonNs    -= st0.horizonNs
	st.domainsNs    -= st0.domainsNs
	st.commitNs     -= st0.commitNs
	st.perceptionNs -= st0.perceptionNs
	st.decisionNs   -= st0.decisionNs
	fmt.printf("crowd%s%s%s: %d agents (%d exploring), %d s of world time\n", " spread" if spread else "",
	           ", anchored by a " if anchored != nil else "", anchored if anchored != nil else "", agents,
	           (agents + 1) / 2, seconds)
	if anchored != nil {
		levels: [4]i32

		for i: i32 = 0; i < agents; i += 1 do levels[world_detail_of(w, ids[i])] += 1
		fmt.printf("  levels        %d full, %d reduced, %d abstract, %d frozen\n", levels[3], levels[2], levels[1],
		           levels[0])
	}
	fmt.printf("  wall          % 10.1f ms  (%.1f ms a world second)\n", wall, wall / f64(seconds))
	fmt.printf("  boundaries    % 10d     (%.1f a world second)\n", st.boundaries,
	           f64(st.boundaries) / f64(seconds))
	fmt.printf("  perceptions   % 10d     (%.1f a boundary)\n", knowledge_perceptions(knowledge) - p0,
	           f64(knowledge_perceptions(knowledge) - p0) / f64(st.boundaries) if st.boundaries != 0 else 0.0)
	fmt.printf("  decisions     % 10d     (%.1f a boundary)\n", agency_decisions(agency) - d0,
	           f64(agency_decisions(agency) - d0) / f64(st.boundaries) if st.boundaries != 0 else 0.0)
	fmt.printf("  horizon       % 10.1f ms\n", ms_of(st.horizonNs))
	fmt.printf("  domains       % 10.1f ms\n", ms_of(st.domainsNs))
	fmt.printf("  commit        % 10.1f ms\n", ms_of(st.commitNs))
	fmt.printf("  perception    % 10.1f ms\n", ms_of(st.perceptionNs))
	fmt.printf("  decision      % 10.1f ms\n", ms_of(st.decisionNs))
	fmt.printf("  events        % 10d\n", world_event_count(w) - e0)
	free(ids)
	return 0
}

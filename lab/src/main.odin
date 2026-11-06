/*
 * lab — the bruggadung simulation laboratory.
 *
 *   lab test [name]          run the tests (those whose names contain `name`)
 *   lab run <scenario>       run a scenario and print its trace and checks:
 *                            marked-nail, marked-nail-a, marked-nail-b,
 *                            cistern, cistern-b, cistern-d, cistern-e, village
 *   lab run village --counters
 *                            and, on stderr, what it cost (PERFORMANCE.md)
 *   lab save <scenario>      run a scenario and print the save of its end state
 *   lab menu <scenario> <ms> run a scenario to a time and print the worker's menu
 *   lab play <world> [--seed n] [--log file]
 *                            an interactive session on workshop or cistern;
 *                            the commands read are its replay log
 *   lab -C <dir> ...         read content from <dir> (default: content)
 *   lab --debug-history ...  keep debug fields' changes in history, too
 *                            (KNOWLEDGE.md decision 21)
 *
 * (ported from the Objective-C lab's main.m)
 */
package lab

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strings"


@(private = "file")
usage :: proc() -> i32 {
	fmt.eprintf("usage: lab [-C contentdir] [--debug-history] test [name]\n" +
	            "       lab [-C contentdir] run|save marked-nail|marked-nail-a|marked-nail-b|cistern...|village\n" +
	            "       lab [-C contentdir] run village --counters\n" +
	            "       lab [-C contentdir] menu marked-nail|marked-nail-a|marked-nail-b <ms>\n" +
	            "       lab [-C contentdir] play workshop|cistern|shed [--seed n] [--log file]\n" +
	            "       lab [-C contentdir] bench crowd|spread [agents] [seconds] [anchor[=kind]]\n")
	return 2
}


@(private = "file")
play :: proc(argv: []string, i: int) -> i32 {
	session: ^Play
	error:   string
	log:     ^libc.FILE
	seed:    u64
	line:    [1024]u8
	len_:    int
	tty:     bool
	argc:    int

	argc = len(argv)
	seed = 42
	log  = nil
	for k := i + 2; k + 1 < argc; k += 2 {
		if argv[k] == "--seed" {
			seed = u64(libc.strtoull(ns_utf8(argv[k + 1]), nil, 10))
		} else if argv[k] == "--log" {
			log = libc.fopen(ns_utf8(argv[k + 1]), "w")
		}
	}
	error   = ""
	session = play_world(argv[i + 1], seed, &error)
	if session == nil {
		fmt.eprintf("lab: %s\n", error)
		return 1
	}
	tty = os.is_tty(os.stdin)
	fmt.printf("%s", play_take_output(session))
	for {
		if tty {
			fmt.printf("> ")
			// fflush( stdout): fmt.printf has written it
		}
		if libc.fgets(raw_data(line[:]), i32(len(line)), libc.stdin) == nil do break
		len_ = len(string(cstring(&line[0])))
		for len_ != 0 && (line[len_ - 1] == '\n' || line[len_ - 1] == '\r') {
			len_ -= 1
			line[len_] = 0
		}
		if !tty do fmt.printf("> %s\n", string(line[:len_]))
		if log != nil do libc.fprintf(log, "%s\n", cstring(&line[0]))
		if !play_command(session, strings.clone(string(line[:len_]), context.temp_allocator)) do break
		fmt.printf("%s", play_take_output(session))
	}
	if log != nil do libc.fclose(log)
	return 0
}


@(private = "file")
run_cistern :: proc(name: string) -> i32 {
	variant:  Cistern_Variant
	scenario: ^Cistern
	world:    ^World
	lines:    []string

	if name == "cistern" {
		variant = .Base
	} else if name == "cistern-b" {
		variant = .Earlier
	} else if name == "cistern-e" {
		variant = .Stops_Early
	} else {
		variant = .Reversed
	}
	world = test_world(7)
	if world == nil do return 1
	release_shared_content_after_use()
	scenario = autorelease(cistern_init_with_world(world, test_committer(world), variant))
	cistern_run(scenario)
	fmt.printf("== trace\n")
	lines = committer_trace(cistern_committer(scenario))
	for i := 0; i < len(lines); i += 1 do fmt.printf("%s\n", lines[i])
	fmt.printf("\n== the fluid domain, per step\n")
	lines = fluid_domain_log(cistern_fluid(scenario))
	for i := 0; i < len(lines); i += 1 do fmt.printf("%s\n", lines[i])
	fmt.printf("\n== entities\n")
	for i: u64 = 1; i < world_next_id(world); i += 1 do fmt.printf("%s\n", world_describe_entity(world, Entity_ID(i)))
	fmt.printf("on the floor: %d mL\n", world_total_tile_water(world))
	fmt.printf("\n== checks\n")
	lines = cistern_results(scenario)
	for i := 0; i < len(lines); i += 1 do fmt.printf("%s\n", lines[i])
	return 1 if cistern_failure_count(scenario) != 0 else 0
}


/* The village: a week of days and nights, its people, its checks. */
@(private = "file")
run_village :: proc(save_: bool, counters := false) -> i32 {
	world := test_world(101)
	if world == nil do return 1
	release_shared_content_after_use()
	c := test_committer(world)
	village := autorelease(village_init_with_world(world, c))
	village_run(village)
	if counters {
		for line in village_counters(village) do fmt.eprintf("%s\n", line)
	}
	if save_ {
		fmt.printf("%s", save(world, c, nil))
		return 1 if village_failure_count(village) != 0 else 0
	}
	fmt.printf("== the village at t=%dms, boundary %d\n", world_time(world).ms, world_boundary(world))
	for i: u64 = 1; i < world_next_id(world); i += 1 do fmt.printf("%s\n", world_describe_entity(world, Entity_ID(i)))
	fmt.printf("\n== checks\n")
	for line in village_results(village) do fmt.printf("%s\n", line)
	fmt.printf("state hash %016x\n", world_state_hash(world))
	return 1 if village_failure_count(village) != 0 else 0
}


@(private = "file")
run_scenario :: proc(name: string, save_: bool, menuAt: i64) -> i32 {
	variant:  Marked_Nail_Variant
	scenario: ^Marked_Nail
	world:    ^World
	lines:    []string
	entities: ^Store

	if strings.has_prefix(name, "cistern") do return run_cistern(name)
	if name == "village" do return run_village(save_)
	if name == "marked-nail" {
		variant = .Base
	} else if name == "marked-nail-a" {
		variant = .Unmarked
	} else if name == "marked-nail-b" {
		variant = .Mixed_Goods
	} else {
		return usage()
	}

	world = test_world(42)
	if world == nil do return 1
	release_shared_content_after_use()
	scenario = autorelease(marked_nail_init_with_world(world, test_committer(world), variant))
	if menuAt >= 0 {
		menu:  ^Menu
		reach: [64]Entity_ID
		view:  ^View
		n:     uint

		marked_nail_run_until(scenario, time_make(menuAt))
		view = view_of(4, world)
		n    = view_reachable(view, raw_data(reach[:]), 64)
		fmt.printf("== what the worker (4) can see at t=%dms\n", menuAt)
		for i: uint = 0; i < n && i < 64; i += 1 do fmt.printf("%s\n", view_describe_entity(view, reach[i]))
		menu = menu_for_world(4, world)
		fmt.printf("\n== the worker's menu\n")
		for i: uint = 0; i < menu_count(menu); i += 1 do fmt.printf("%s\n", menu_describe_at(menu, i))
		return 0
	}
	marked_nail_run(scenario)
	if save_ {
		fmt.printf("%s", save(world, marked_nail_committer(scenario), nil))
		return 1 if marked_nail_failure_count(scenario) != 0 else 0
	}

	fmt.printf("== trace\n")
	lines = committer_trace(marked_nail_committer(scenario))
	for i := 0; i < len(lines); i += 1 do fmt.printf("%s\n", lines[i])

	fmt.printf("\n== entities at t=%dms, boundary %d\n", world_time(world).ms,
	           world_boundary(world))
	entities = world_store_for_kind(world, world_kind_named(world, "Body"))
	for i: u64 = 1; i < world_next_id(world); i += 1 do fmt.printf("%s\n", world_describe_entity(world, Entity_ID(i)))
	_ = entities

	fmt.printf("\n== checks\n")
	lines = marked_nail_results(scenario)
	for i := 0; i < len(lines); i += 1 do fmt.printf("%s\n", lines[i])
	fmt.printf("state hash %016x\n", world_state_hash(world))
	return 1 if marked_nail_failure_count(scenario) != 0 else 0
}


/* `anchor` (a player) or `anchor=<kind>`, or none. */
@(private = "file")
bench_anchor :: proc(argv: []string, k: int) -> cstring {
	if k >= len(argv) do return nil
	if argv[k] == "anchor" do return "player"
	if strings.has_prefix(argv[k], "anchor=") do return ns_utf8(argv[k][7:])
	return nil
}


main :: proc() {
	argv:   []string
	argc:   int
	i:      int
	status: i32

	argv = os.args
	argc = len(argv)
	i = 1
	if i + 1 < argc && argv[i] == "-C" {
		content_dir = argv[i + 1]
		i += 2
	}
	if i < argc && argv[i] == "--debug-history" {
		debug_history = true      /* debug fields' changes kept in history, too */
		i += 1
	}
	if i >= argc do os.exit(int(usage()))

	pool_push()
	if argv[i] == "test" {
		status = 1 if run_tests(ALL_TESTS[:], argv[i + 1] if i + 1 < argc else "") != 0 else 0
	} else if argv[i] == "run" && i + 2 < argc && argv[i + 1] == "village" && argv[i + 2] == "--counters" {
		status = run_village(false, counters = true)
	} else if argv[i] == "run" && i + 1 < argc {
		status = run_scenario(argv[i + 1], false, -1)
	} else if argv[i] == "save" && i + 1 < argc {
		status = run_scenario(argv[i + 1], true, -1)
	} else if argv[i] == "play" && i + 1 < argc {
		status = play(argv, i)
	} else if argv[i] == "bench" && i + 1 < argc && argv[i + 1] == "crowd" {
		status = bench_crowd_spread(libc.atoi(ns_utf8(argv[i + 2])) if i + 2 < argc else 100,
		                            i64(libc.atoll(ns_utf8(argv[i + 3]))) if i + 3 < argc else 60, false,
		                            bench_anchor(argv, i + 4))
	} else if argv[i] == "bench" && i + 1 < argc && argv[i + 1] == "spread" {
		status = bench_crowd_spread(libc.atoi(ns_utf8(argv[i + 2])) if i + 2 < argc else 100,
		                            i64(libc.atoll(ns_utf8(argv[i + 3]))) if i + 3 < argc else 60, true,
		                            bench_anchor(argv, i + 4))
	} else if argv[i] == "menu" && i + 2 < argc {
		status = run_scenario(argv[i + 1], false, i64(libc.strtoll(ns_utf8(argv[i + 2]), nil, 10)))
	} else {
		status = usage()
	}
	pool_drain()
	free_released_content()          // the worlds on it went with the pool
	os.exit(int(status))
}

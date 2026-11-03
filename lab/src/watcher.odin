package lab

/*
 * What the watcher (watcher/) can watch: a world and the scheduler that runs
 * it, made as `lab run` or `lab bench` makes them. The watcher runs
 * boundaries as world time passes on its clock and builds a truth scene
 * (scene_truth.odin) between frames; it never edits the world.
 *
 * Cut points: the scenarios' own checks run in `lab run`, not here; a
 * scenario watched past its end runs on with nothing more to do.
 */

import "core:strings"
import "core:time"


Watcher :: struct {
	title:     string,
	world:     ^World,
	scheduler: ^Scheduler,
	agency:    ^Agency,          // or nil: a scenario's agents run on a script
	follow:    Entity_ID,        // the one to follow first, or none
	ids:       []Entity_ID,      // the watcher deletes it
}

WATCHABLE :: "village, crowd [agents], spread [agents], cistern, cistern-b, cistern-d, cistern-e, " +
             "marked-nail, marked-nail-a, marked-nail-b"


/* A watchable world by name (WATCHABLE), its objects autoreleased into the
 * current pool: they last as long as it does. false, with why, if there's no
 * such thing or it can't be made. */
watcher_open :: proc(name: string, agents: i32) -> (w: Watcher, why: string) {
	switch {
	case name == "crowd" || name == "spread":
		crowd, ok := crowd_setup(agents, name == "spread", nil)
		if !ok do return {}, "no crowd"
		return Watcher {
			title     = strings.clone(name),
			world     = crowd.world,
			scheduler = crowd.scheduler,
			agency    = crowd.agency,
			follow    = crowd.ids[0] if len(crowd.ids) > 0 else 0,
			ids       = crowd.ids,
		}, ""
	case name == "village":
		world := test_world(101)
		if world == nil do return {}, "no world"
		village := autorelease(village_init_with_world(world, test_committer(world)))
		if village.error != "" do return {}, village.error
		ids := make([]Entity_ID, len(village.people))
		for v, i in village.people do ids[i] = v.id
		return Watcher {
			title     = strings.clone(name),
			world     = world,
			scheduler = village.scheduler,
			agency    = village.agency,
			follow    = ids[0],
			ids       = ids,
		}, ""
	case strings.has_prefix(name, "cistern"):
		variant: Cistern_Variant
		switch name {
		case "cistern":   variant = .Base
		case "cistern-b": variant = .Earlier
		case "cistern-d": variant = .Reversed
		case "cistern-e": variant = .Stops_Early
		case:             return {}, "no such cistern"
		}
		world := test_world(7)
		if world == nil do return {}, "no world"
		scenario := autorelease(cistern_init_with_world(world, test_committer(world), variant))
		return Watcher{title = strings.clone(name), world = world, scheduler = scenario.scheduler}, ""
	case strings.has_prefix(name, "marked-nail"):
		variant: Marked_Nail_Variant
		switch name {
		case "marked-nail":   variant = .Base
		case "marked-nail-a": variant = .Unmarked
		case "marked-nail-b": variant = .Mixed_Goods
		case:                 return {}, "no such marked nail"
		}
		world := test_world(42)
		if world == nil do return {}, "no world"
		scenario := autorelease(marked_nail_init_with_world(world, test_committer(world), variant))
		return Watcher{title = strings.clone(name), world = world, scheduler = scenario.scheduler, follow = 4}, ""
	}
	return {}, "nothing to watch called that"
}


/* Runs boundaries up to `t` (ms), for at most `budget` ns of wall time.
 * The world goes where it would have with nobody watching: no boundary is
 * put in for the watcher, as scheduler_run_until's stop would be. true once
 * every boundary before `t` has run. */
watcher_step_until :: proc(w: ^Watcher, t: i64, budget: u64) -> bool {
	start := time.tick_now()
	for u64(time.tick_since(start)) < budget {
		if !scheduler_step_until(w.scheduler, time_make(t)) do return true
	}
	return false
}


/* One boundary, whenever it comes; false if none ever will. */
watcher_step :: proc(w: ^Watcher) -> bool {
	return scheduler_step_until(w.scheduler, TIME_NEVER)
}


/* When the next boundary will be, or -1 for never. */
watcher_next_boundary :: proc(w: ^Watcher) -> i64 {
	t := scheduler_next_boundary_time(w.scheduler)
	return -1 if t.ms == TIME_NEVER.ms else t.ms
}


/* What the inspector says of an entity: its records, and if it has a mind,
 * what concerns it and what it has lately thought. Temporary strings.
 * (agency_mind_of would give it a mind: it isn't asked.) */
watcher_describe :: proc(w: ^Watcher, e: Entity_ID) -> []string {
	lines := make([dynamic]string, context.temp_allocator)
	/* world_describe_entity's "id blueprint: Kind.field=value ... at place",
	 * a line to each kind */
	text := world_describe_entity(w.world, e)
	colon := strings.index(text, ": ")
	if colon < 0 {
		append(&lines, text)
	} else {
		append(&lines, text[:colon])
		rest := text[colon + 2:]
		place := ""
		if at := strings.last_index(rest, " at "); at >= 0 {
			rest, place = rest[:at], rest[at + 1:]
		}
		kind := ""
		b := strings.builder_make(context.temp_allocator)
		for len(rest) > 0 {
			/* a field to the next space outside quotes */
			end, quoted := len(rest), false
			for i in 0 ..< len(rest) {
				if rest[i] == '"' do quoted = !quoted
				if rest[i] == ' ' && !quoted {
					end = i
					break
				}
			}
			field := rest[:end]
			rest = rest[min(end + 1, len(rest)):]
			dot := strings.index_byte(field, '.')
			if dot > 0 && field[:dot] != kind {
				if kind != "" do append(&lines, strings.to_string(b))
				kind = field[:dot]
				b = strings.builder_make(context.temp_allocator)
				strings.write_string(&b, kind)
				strings.write_string(&b, ":")
			}
			strings.write_string(&b, " ")
			strings.write_string(&b, field[dot + 1:] if dot > 0 else field)
		}
		if kind != "" do append(&lines, strings.to_string(b))
		if place != "" do append(&lines, place)
	}
	if w.agency != nil {
		for c in agency_concerns_of(w.agency, e) do append(&lines, strings.concatenate({"concern: ", c}, context.temp_allocator))
		log := agency_log_of(w.agency, e)
		for line in log[max(0, len(log) - 8):] do append(&lines, line)
	}
	return lines[:]
}


/* The tiles theme's glyphs (content/looks/tiles.tri), for the window:
 * temporary. */
watcher_glyphs :: proc(w: ^Watcher) -> []Glyph_Entry {
	return looks_glyphs(world_tri(w.world), "tiles", context.temp_allocator)
}


/* The tile an entity is on, through whatever holds it. */
watcher_tile_of :: proc(w: ^Watcher, e: Entity_ID) -> (x, y, level: i32, ok: bool) {
	tile: Location
	if !know_ground_tile(w.world, e, &tile) do return
	return tile.x, tile.y, tile.level, true
}

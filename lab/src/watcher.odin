package lab

/*
 * What the watcher (watcher/) can watch: a world and the scheduler that runs
 * it, made as `lab run` or `lab bench` makes them. The watcher runs
 * boundaries as world time passes on its clock and builds a scene between
 * frames: the truth (scene_truth.odin), or one agent's knowledge
 * (scene_knowledge.odin); it never edits the world.
 *
 * Cut points: the scenarios' own checks run in `lab run`, not here; a
 * scenario watched past its end runs on with nothing more to do. What the
 * inspector says of a referent is the agent's (its store's recall of it),
 * and of itself, its own mind (concerns, what it lately thought); never the
 * truth of it.
 */

import "core:fmt"
import "core:strings"
import "core:time"

import "../../tessera"


Watcher :: struct {
	title:     string,
	world:     ^World,
	scheduler: ^Scheduler,
	agency:    ^Agency,          // or nil: a scenario's agents run on a script
	knowledge: ^Knowledge,       // or nil: nobody's knowledge to show
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
			knowledge = crowd.knowledge,
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
			knowledge = village.knowledge,
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


/* The scene a frame draws of `extent`: the truth, or, `knower` not none, the
 * world as it knows it. Temporary. */
watcher_scene :: proc(w: ^Watcher, knower: Entity_ID, extent: tessera.Extent, seq: u64) -> ^tessera.Scene {
	if knower != NO_ENTITY && w.knowledge != nil {
		return scene_knowledge(w.knowledge, knower, extent, seq, context.temp_allocator)
	}
	return scene_truth(w.world, extent, seq, context.temp_allocator)
}


/* Whether the entity has knowledge to show: a store it has perceived into
 * (watching makes none). */
watcher_knows :: proc(w: ^Watcher, e: Entity_ID) -> bool {
	if w.knowledge == nil do return false
	store := knowledge_existing_store_of(w.knowledge, e)
	return store != nil && knowledge_store_referent(store, knowledge_store_self_referent(store)) != nil
}


/* The referent that is the knower itself, in its knowledge; 0 if none. */
watcher_self_of :: proc(w: ^Watcher, knower: Entity_ID) -> u32 {
	if !watcher_knows(w, knower) do return 0
	return knowledge_store_self_referent(knowledge_existing_store_of(w.knowledge, knower))
}


/* The tile the knower believes a referent is on (or its holder is). */
watcher_believed_tile :: proc(w: ^Watcher, knower: Entity_ID, referent: u32) -> (x, y, level: i32, ok: bool) {
	if !watcher_knows(w, knower) do return
	r := knowledge_store_referent(knowledge_existing_store_of(w.knowledge, knower), referent)
	if r == nil do return
	return r.x, r.y, r.level, true
}


/* A short name for an entity: its blueprint, and its id. Temporary. */
watcher_name :: proc(w: ^Watcher, e: Entity_ID) -> string {
	info := world_info(w.world, e)
	return fmt.tprintf("%s %d", info.blueprint if info != nil else "entity", e)
}


/* What the inspector says of a referent of the knower's: what it is, as the
 * knower recalls it, where it believes it, and how long since it saw it;
 * itself, its concerns and what it lately thought. Temporary strings. */
watcher_recall :: proc(w: ^Watcher, knower: Entity_ID, referent: u32) -> []string {
	lines := make([dynamic]string, context.temp_allocator)
	if !watcher_knows(w, knower) do return lines[:]
	store := knowledge_existing_store_of(w.knowledge, knower)
	r := knowledge_store_referent(store, referent)
	me := knowledge_store_referent(store, knowledge_store_self_referent(store))
	if r == nil do return lines[:]
	itself := r.id == me.id
	append(&lines, fmt.tprintf("R%d %s%s", r.id, r.kind, ": itself" if itself else ""))
	if known := knowledge_store_recall(store, r); known != "" do append(&lines, known)
	switch {
	case r.form == .In:      append(&lines, fmt.tprintf("in R%d", r.container))
	case r.form == .Held_By: append(&lines, fmt.tprintf("held by R%d", r.container))
	case r.form == .Part_Of: append(&lines, fmt.tprintf("part of R%d", r.container))
	case:                    append(&lines, fmt.tprintf("at %d, %d, level %d", r.x, r.y, r.level))
	}
	now := world_time(w.world).ms
	switch {
	case !r.present:         append(&lines, fmt.tprintf("not where it was seen, %s ago", watcher_ago(now - r.seen)))
	case r.seen == me.seen:  append(&lines, "in sight")
	case:                    append(&lines, fmt.tprintf("seen %s ago", watcher_ago(now - r.seen)))
	}
	if r.toldBy != 0 do append(&lines, fmt.tprintf("as R%d told it", r.toldBy))
	if itself && w.agency != nil {
		for c in agency_concerns_of(w.agency, knower) do append(&lines, strings.concatenate({"concern: ", c}, context.temp_allocator))
		log := agency_log_of(w.agency, knower)
		for line in log[max(0, len(log) - 8):] do append(&lines, line)
	}
	return lines[:]
}


/* A span of ms, roughly: "3d 4h", "2h 05m", "7m 30s", "12s". */
@(private = "file")
watcher_ago :: proc(ms: i64) -> string {
	s := max(ms, 0) / 1000
	switch {
	case s >= 86_400: return fmt.tprintf("%dd %dh", s / 86_400, s / 3600 % 24)
	case s >= 3600:   return fmt.tprintf("%dh %02dm", s / 3600, s / 60 % 60)
	case s >= 60:     return fmt.tprintf("%dm %02ds", s / 60, s % 60)
	}
	return fmt.tprintf("%ds", s)
}

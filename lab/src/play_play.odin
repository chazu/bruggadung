package lab

/*
 * BGPlay — an interactive session on one of the laboratory's worlds: the
 * command interface, the text map, and the developer inspector of DESIGN.md's
 * laboratory. A person (or a script) controls one agent:
 *
 *   look                  the map as the actor knows it: what it sees now,
 *                         and what it remembers, with the memory's age
 *   menu                  the actor's menu, from what it knows, numbered
 *   do <n> [amount]       perform menu entry n, now
 *   walk n|s|e|w          walk one tile
 *   wait <ms>             let time pass
 *   step                  run to the next boundary
 *   idle                  run until the actor has no activity under way
 *   ask <R> where <R>     ask someone in reach where something like it is
 *   ask <R> who <R>       ask someone who told them where it is
 *   tell <R> <R> [in <R>] tell someone where something is, as you believe;
 *                         in a container you don't believe it is in: a lie
 *   notebook              what the actor knows, as it knows it: what it
 *                         remembers where, what it was told and how much
 *                         it believes it, open questions, findings, traces
 *   write <R>             write where something is into a notebook held
 *   read <R>              read a record in reach
 *   note <text>, notes    the player's own notes, out of character: they
 *                         never reach the actor's knowledge
 *   autopilot <goal> [n]  hand the actor to agency, committed to the goal
 *                         (a #Goal in content), until something arises
 *                         worth more than n (20), or the goal is done
 *   as <id>               control another agent; agency answers for the
 *                         others when they are asked
 *   activities            the actor's activities, with their stages
 *   suspend <id>, resume <id>
 *                         the actor's choice: suspend keeps the progress
 *   knows [id]            the developer's view of an agent's knowledge store
 *   inspect <id>          the developer's view of an entity: truth,
 *                         relations, activities, history
 *   why <id>              what last changed it, and the chain of causes
 *   trace [n]             the last n lines of the commit trace
 *   save <file>, load <file>
 *   time, hash, help, quit
 *
 * Every command is deterministic given the world, so the commands typed are
 * the session's replay log: feeding them back reproduces it exactly.
 *
 * (ported from the Objective-C lab's play/BGPlay.m)
 */

import "core:fmt"
import "core:os"
import "core:strings"
import tri "../../triangle/odin/triangle"


// <BGInputSource>: play_as_input_source.
Play :: struct {
	using object: Object,
	name:         string,               // cloned
	world:        ^World,
	committer:    ^Committer,
	scheduler:    ^Scheduler,
	fluid:        ^Fluid_Domain,
	traces:       ^Traces,
	activities:   ^Activities,
	knowledge:    ^Knowledge,
	agency:       ^Agency,
	menu:         ^Menu,
	actor:        Entity_ID,
	out:          strings.Builder,
	notes:        [dynamic]string,      /* the player's, out of character; each cloned */
	inputDue:     bool,
	traceShown:   uint,
}


// play_world: a play's world, or a new play on a named world; told apart by
// their arguments.
play_world :: proc {
	play_world_named,
	play_world_of,
}


@(private = "file")
play_build_on :: proc(self: ^Play, world: ^World) {
	autorelease(self.world)
	autorelease(self.committer)
	autorelease(self.scheduler)
	autorelease(self.fluid)
	autorelease(self.traces)
	autorelease(self.activities)
	autorelease(self.agency)
	autorelease(self.knowledge)
	self.world      = retain(world)
	self.committer  = retain(test_committer(world))
	self.fluid      = fluid_domain_init_with_world(world)
	self.traces     = traces_init_with_world(world)
	self.activities = retain(activities_with_world(world, self.committer))
	self.knowledge  = knowledge_init_with_world(world)
	self.agency     = agency_init_with_world(world, self.committer, self.knowledge)
	self.scheduler  = scheduler_init_with_world(world, self.committer)
	scheduler_add_domain(self.scheduler, fluid_domain_as_domain(self.fluid))
	scheduler_add_domain(self.scheduler, traces_as_domain(self.traces))
	scheduler_set_activities(self.scheduler, activities_as_activity_clock(self.activities))
	scheduler_set_perception(self.scheduler, knowledge_as_perception_phase(self.knowledge))
	scheduler_set_decision(self.scheduler, agency_as_decision_phase(self.agency))
	scheduler_set_inputs(self.scheduler, play_as_input_source(self))
	self.traceShown = 0
}


/* "workshop" or "cistern"; nil, with the reason, for another name */
// +playWorld:seed:error: (play_world). Autoreleased, as before.
play_world_named :: proc(name: string, seed: u64, error: ^string) -> ^Play {
	play:  ^Play
	world: ^World
	setup: ^Proposal_Group
	h:     [8]Entity_ID

	if name != "workshop" && name != "cistern" && name != "shed" {
		if error != nil do error^ = fmt.tprintf("there is no world %s (workshop, cistern, shed)", name)
		return nil
	}
	world = test_world(seed)
	if world == nil {
		if error != nil do error^ = "the content does not load"
		return nil
	}
	play       = autorelease(object_new(Play, play_dealloc))
	play.name  = strings.clone(name)
	play.out   = strings.builder_make()
	play.notes = make([dynamic]string)
	/* the shed (TERRAIN.md): a map, a worker inside, a bucket past the doorway */
	if name == "shed" && !world_set_terrain_map(world, "shed_map", error) do return nil
	play_build_on(play, world)
	if name == "shed" {
		setup = proposal_group_group_with_phase(.System, "setup: the shed")
		h[3]  = proposal_group_create(setup, "worker", "worker", on_tile(9, 2, 0))
		proposal_group_create(setup, "bucket", "bucket", on_tile(12, 3, 0))
	} else {
		setup = workshop_setup(false, &h) if name == "workshop" else cistern_setup(&h)
	}
	committer_submit(play.committer, setup)
	play.inputDue = true
	scheduler_step_until(play.scheduler, world_time(world))
	play.actor = proposal_group_id_for(setup, h[6] if name == "cistern" else h[3])
	play_control_others(play)
	play.traceShown = uint(len(committer_trace(play.committer)))
	fmt.sbprintf(&play.out, "The %s, seed %d. You are %d. Type help for the commands.\n", name,
	             seed, play.actor)
	return play
}


/* Agency answers for every agent but the one played. */
@(private = "file")
play_control_others :: proc(self: ^Play) {
	agents: ^Store

	agents = world_store_for_kind(self.world, world_kind_named(self.world, "Agent"))
	for i: uint = 0; i < store_count(agents); i += 1 {
		if store_entity_at_index(agents, i) != self.actor do agency_control(self.agency, store_entity_at_index(agents, i))
	}
	agency_relinquish(self.agency, self.actor)
}


play_dealloc :: proc(self: ^Play) {
	delete(self.name)
	release(self.world)
	release(self.committer)
	release(self.scheduler)
	release(self.fluid)
	release(self.traces)
	release(self.activities)
	release(self.agency)
	release(self.knowledge)
	release(self.menu)
	strings.builder_destroy(&self.out)
	for i := 0; i < len(self.notes); i += 1 do delete(self.notes[i])
	delete(self.notes)
}


play_as_input_source :: proc(self: ^Play) -> Input_Source {
	return Input_Source {
		data              = self,
		next_input_time   = proc(data: rawptr) -> Time {
			return play_next_input_time((^Play)(data))
		},
		deliver_inputs_at = proc(data: rawptr, t: Time, world: ^World, committer: ^Committer) {
			play_deliver_inputs_at((^Play)(data), t, world, committer)
		},
	}
}


// -world (play_world).
play_world_of :: proc(self: ^Play) -> ^World {
	return self.world
}


play_actor :: proc(self: ^Play) -> Entity_ID {
	return self.actor
}


/* What the commands printed since the last call. */
// In the temporary allocator.
play_take_output :: proc(self: ^Play) -> string {
	s: string

	s = strings.clone(strings.to_string(self.out), context.temp_allocator)
	strings.builder_reset(&self.out)
	return s
}


/* --- inputs: a command performed now commits at a boundary now ----------------- */

@(private = "file")
play_next_input_time :: proc(self: ^Play) -> Time {
	return world_time(self.world) if self.inputDue else TIME_NEVER
}


@(private = "file")
play_deliver_inputs_at :: proc(self: ^Play, t: Time, world: ^World, committer: ^Committer) {
	self.inputDue = false      /* the groups were submitted when the command was given */
}


@(private = "file")
play_show_trace :: proc(self: ^Play) {
	trace: []string

	trace = committer_trace(self.committer)
	for i := self.traceShown; i < uint(len(trace)); i += 1 do fmt.sbprintf(&self.out, "%s\n", trace[i])
	self.traceShown = uint(len(trace))
}


@(private = "file")
play_show_news :: proc(self: ^Play) {
	news: []string

	news = knowledge_store_news(knowledge_store_of(self.knowledge, self.actor))
	for i := 0; i < len(news); i += 1 do fmt.sbprintf(&self.out, "  you notice: %s\n", news[i])
}


/* An action chosen from what the actor knows; walking is the actor's own.
 * The group submitted, or nil if it can't be attempted. */
@(private = "file")
play_perform :: proc(self: ^Play, action: Action, amount: i64) -> ^Proposal_Group {
	action := action
	g:     ^Proposal_Group
	error: string

	error = ""
	if action.roles[Role.Item] != 0 || action.roles[Role.Destination] != 0 {
		g = perform_believed(self.world, self.committer, knowledge_store_of(self.knowledge, self.actor), action, amount,
		                     &error)
	} else {
		action.roles[Role.Actor] = self.actor
		g = perform(self.world, self.committer, action, amount, &error)
	}
	if g == nil {
		fmt.sbprintf(&self.out, "You can't: %s.\n", error)
		return nil
	}
	self.inputDue = true
	scheduler_step_until(self.scheduler, world_time(self.world))
	play_show_trace(self)
	play_show_news(self)
	return g
}


/* --- looking -------------------------------------------------------------------- */



/* A character of the text theme (content/looks/text.tri) for a look; `none`
 * if the theme has nothing for it. */
@(private = "file")
text_glyph :: proc(glyphs: []Glyph_Entry, look: string, none: u8) -> u8 {
	g, ok := glyph_for(glyphs, look)
	return u8(g.char) if ok && g.char < 0x80 else none
}


/* The map as the actor knows it: tiles it has seen, what it remembers on
 * them, and its age, in the text theme (content/looks/text.tri). Nothing
 * here reads the world, except what is in sight now (its tiles' water). */
@(private = "file")
play_look :: proc(self: ^Play) {
	store:  ^Knowledge_Store
	me:     ^Referent
	r:      ^Referent
	holder: ^Referent
	now:    i64
	row:    [32]u8
	g:      u8

	store = knowledge_store_of(self.knowledge, self.actor)
	me    = knowledge_store_referent(store, knowledge_store_self_referent(store))
	now   = world_time(self.world).ms
	if me == nil {
		strings.write_string(&self.out, "You know nothing yet.\n")
		return
	}
	glyphs := looks_glyphs(world_tri(self.world), "text", context.temp_allocator)
	for y := me.y - 3; y <= me.y + 3; y += 1 {
		for x := me.x - 7; x <= me.x + 7; x += 1 {
			g = ' '
			solid := false
			if knowledge_store_has_seen_x(store, x, y, me.level) {
				kind: ^Terrain_Info
				tile: Location

				tile = on_tile(x, y, me.level)
				kind = (terrain_kind_info(world_terrain(self.world),
				                          knowledge_store_believed_terrain_at_x(store, x, y, me.level))
				        if world_terrain(self.world) != nil else nil)
				solid = kind != nil && kind.solid
				if knowledge_sees(self.knowledge, tile, on_tile(me.x, me.y, me.level)) &&
				   world_water_at_x(self.world, x, y, me.level) != 0 && (kind == nil || !kind.solid) {
					g = text_glyph(glyphs, "water", '~')
				} else {
					g = text_glyph(glyphs, string(kind.look) if kind != nil else "floor",
					               '#' if kind != nil && kind.solid else '.')
				}
			}
			for i: uint = 0; i < knowledge_store_count(store); i += 1 {
				r = knowledge_store_referent_at(store, i)
				if r.present && r.form == .On_Tile && r.x == x && r.y == y && !solid {
					g = '@' if r.id == me.id else text_glyph(glyphs, look_of_kind(self.world, string(r.kind)), 'o')
				}
			}
			if me.x == x && me.y == y do g = '@'
			row[x - me.x + 7] = g
		}
		row[15] = 0
		fmt.sbprintf(&self.out, "   %s\n", string(cstring(&row[0])))
	}
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		r = knowledge_store_referent_at(store, i)
		if r.id == me.id do continue
		holder = knowledge_store_referent(store, r.container) if r.container != 0 else nil
		fmt.sbprintf(&self.out, "R%d %s", r.id, r.kind)
		if !r.present {
			fmt.sbprintf(&self.out, ": not where you last saw it, %ds ago", (now - r.seen) / 1000)
		} else {
			if holder != nil {
				fmt.sbprintf(&self.out, " %s R%d", "in" if r.form == .In else "held by" if r.form == .Held_By else "part of",
				             holder.id)
			} else {
				fmt.sbprintf(&self.out, " at (%d, %d)", r.x, r.y)
			}
			if r.seen < now do fmt.sbprintf(&self.out, ", as you saw it %ds ago", (now - r.seen) / 1000)
		}
		fmt.sbprintf(&self.out, ": %s\n", r.features if r.features != nil else "")
	}
}


@(private = "file")
play_show_menu :: proc(self: ^Play) {
	store: ^Knowledge_Store
	a:     ^Action

	release(self.menu)
	store     = knowledge_store_of(self.knowledge, self.actor)
	self.menu = retain(menu_for_world_believed(store, self.world, true))
	for i: uint = 0; i < menu_count(self.menu); i += 1 {
		a = menu_action_at(self.menu, i)
		fmt.sbprintf(&self.out, "% 2d. %s", i + 1, a.operation)
		for ri := int(Role.Item); ri < int(Role.Count); ri += 1 {
			r := Role(ri)
			if a.roles[r] != 0 {
				fmt.sbprintf(&self.out, " %s R%d (%s)", ROLE_NAMES[r], a.roles[r],
				             knowledge_store_referent(store, u32(a.roles[r])).kind)
			}
		}
		if menu_match_at(self.menu, i) == tri.Match.Unknown {
			fmt.sbprintf(&self.out, "  [unknown: %s]",
			             strings.join(menu_residuals_at(self.menu, i), ", ", context.temp_allocator))
		}
		strings.write_string(&self.out, "\n")
	}
	if menu_count(self.menu) == 0 do strings.write_string(&self.out, "There is nothing you can do.\n")
}


/* --- the developer's inspector ------------------------------------------------- */

@(private = "file")
play_inspect :: proc(self: ^Play, e: Entity_ID) {
	record: ^Activity
	ev:     ^Event
	store:  ^Store
	other:  [64]Entity_ID
	n:      uint
	shown:  uint

	fmt.sbprintf(&self.out, "%s\n", world_describe_entity(self.world, e))
	for k := 0; k < int(Edge_Kind.Kind_Count); k += 1 {
		n = world_edges_from(self.world, Edge_Kind(k), e, raw_data(other[:]), 64)
		for i: uint = 0; i < n && i < 64; i += 1 {
			fmt.sbprintf(&self.out, "  %s -> %d\n", EDGE_KIND_NAMES[Edge_Kind(k)], other[i])
		}
		n = world_edges_to(self.world, Edge_Kind(k), e, raw_data(other[:]), 64)
		for i: uint = 0; i < n && i < 64; i += 1 {
			fmt.sbprintf(&self.out, "  %s <- %d\n", EDGE_KIND_NAMES[Edge_Kind(k)], other[i])
		}
	}
	if world_is_checked_out(self.world, e) do strings.write_string(&self.out, "  its water is checked out by the fluid domain\n")
	store = world_store_for_kind(self.world, world_kind_named(self.world, "Activity"))
	for i: uint = 0; i < store_count(store); i += 1 {
		record = (^Activity)(store_record_at_index(store, i))
		if record.actorRef == e || record.itemRef == e || record.destinationRef == e {
			fmt.sbprintf(&self.out, "  in activity %s\n", world_describe_entity(self.world, store_entity_at_index(store, i)))
		}
	}
	shown = 0
	// for( i = count; i-- > 0 && shown < 8;)
	history := world_history(self.world)
	for i := len(history); i > 0 && shown < 8; {
		i -= 1
		ev = &history[i]
		if ev.subject != e && ev.other != e do continue
		fmt.sbprintf(&self.out, "  event %d at boundary %d: %s%s%s (%s)\n", ev.index,
		             ev.boundary, ev.kind, " " if ev.detail != nil else "", ev.detail if ev.detail != nil else "",
		             play_source_of(self, ev))
		shown += 1
	}
}


@(private = "file")
play_source_of :: proc(self: ^Play, ev: ^Event) -> string {
	source, ok := committer_source_of_position(self.committer, ev.group)
	return source if ok else "before the save"
}


/* What last changed it, and why: the chain of causes back to an input. */
@(private = "file")
play_why :: proc(self: ^Play, e: Entity_ID) {
	ev:     ^Event
	where_: string

	ev = nil
	// for( i = count; i-- > 0 && ! ev;)
	history := world_history(self.world)
	for i := len(history); i > 0 && ev == nil; {
		i -= 1
		if history[i].subject == e do ev = &history[i]
	}
	if ev == nil {
		fmt.sbprintf(&self.out, "Nothing has happened to %d.\n", e)
		return
	}
	for depth: uint = 0; ev != nil && depth < 12; depth += 1 {
		where_ = location_format(ev.location)
		if len(where_) > 63 do where_ = where_[:63]      // BGLocationFormat into char[64]
		fmt.sbprintf(&self.out, "%*s%s %d%s%s%s%s at boundary %d, in \"%s\"\n", int(depth) * 2, "", ev.kind,
		             ev.subject, " " if ev.detail != nil else "", ev.detail if ev.detail != nil else "",
		             " to " if ev.location.form != .None else "", where_ if ev.location.form != .None else "",
		             ev.boundary, play_source_of(self, ev))
		ev = world_event_at(self.world, uint(ev.cause) - 1) if ev.cause != 0 else nil
		if ev != nil do fmt.sbprintf(&self.out, "%*sbecause:\n", int(depth) * 2, "")
	}
}


/* --- saves ------------------------------------------------------------------------ */

@(private = "file")
play_save :: proc(self: ^Play, path: string) {
	text: string

	text = save(self.world, self.committer,
	            []Saved_System{domain_as_saved_system(fluid_domain_as_domain(self.fluid)),
	                           knowledge_as_saved_system(self.knowledge),
	                           agency_as_saved_system(self.agency)})
	if os.write_entire_file(path, text) != nil {
		fmt.sbprintf(&self.out, "Cannot write %s.\n", path)
		return
	}
	fmt.sbprintf(&self.out, "Saved to %s.\n", path)
}


@(private = "file")
play_load :: proc(self: ^Play, path: string) {
	text:     string
	error:    string
	deferred: []^Proposal_Group
	world:    ^World
	position: u64

	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		fmt.sbprintf(&self.out, "Cannot read %s.\n", path)
		return
	}
	text  = strings.truncate_to_byte(string(data), 0)     // stringWithUTF8String: up to a NUL
	error = ""
	world = restore(text, world_content_build(self.world), &deferred, &position, &error)
	if world == nil {
		fmt.sbprintf(&self.out, "%s\n", error)
		return
	}
	play_build_on(self, world)
	committer_set_position(self.committer, position)
	committer_restore_deferred(self.committer, deferred)
	{
		d := fluid_domain_as_domain(self.fluid)
		d.restore_saved_state(d.data, saved_domain_state(text, "fluid"))
		k := knowledge_as_saved_system(self.knowledge)
		k.restore_saved_state(k.data, saved_domain_state(text, "knowledge"))
		a := agency_as_saved_system(self.agency)
		a.restore_saved_state(a.data, saved_domain_state(text, "agency"))
	}
	fmt.sbprintf(&self.out, "Loaded %s: t=%dms.\n", path, world_time(self.world).ms)
}


/* --- saying things ---------------------------------------------------------------- */

/* "R5" or "5": a referent of the actor's, or 0 */
@(private = "file")
play_referent_named :: proc(self: ^Play, word: string) -> u32 {
	word := word

	if ns_has_prefix(word, "R") || ns_has_prefix(word, "r") do word = word[1:]
	if len(word) == 0 ||
	   knowledge_store_referent(knowledge_store_of(self.knowledge, self.actor), u32(ns_long_long_value(word))) == nil {
		return 0
	}
	return u32(ns_long_long_value(word))
}


/* Says it to the referent; a question waits a little for the answer. */
@(private = "file")
play_say :: proc(self: ^Play, content: string, hearer: u32, question: bool) {
	store:  ^Knowledge_Store
	g:      ^Proposal_Group
	action: Action
	said:   Entity_ID

	store          = knowledge_store_of(self.knowledge, self.actor)
	action         = action_make(world_intern(self.world, "say"), Entity_ID(knowledge_store_self_referent(store)),
	                             Entity_ID(hearer), NO_ENTITY)
	action.content = world_intern(self.world, ns_utf8(content))
	g = play_perform(self, action, 0)
	if g == nil do return
	/* saying it takes a second: said before the next command */
	said = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
	for play_is_running(self, said) &&
	    scheduler_step_until(self.scheduler, time_make(world_time(self.world).ms + 600000)) {
	}
	/* the answer comes at the next boundaries, if it comes, as long again to say */
	for k := 0; question && k < 4; k += 1 {
		if !scheduler_step_until(self.scheduler, time_make(world_time(self.world).ms + 1000)) do break
	}
	play_show_trace(self)
	play_show_news(self)
}


@(private = "file")
play_ask :: proc(self: ^Play, words: []string) {
	store:   ^Knowledge_Store
	content: string
	who:     u32
	what:    u32

	store = knowledge_store_of(self.knowledge, self.actor)
	who   = play_referent_named(self, words[1]) if len(words) > 3 else 0
	what  = play_referent_named(self, words[3]) if len(words) > 3 else 0
	if who == 0 || what == 0 {
		strings.write_string(&self.out, "Ask whom, where or who, of what? ask <R> where <R>, ask <R> who <R>.\n")
		return
	}
	content = knowledge_store_ask_who_told_of(store, what) if words[2] == "who" else knowledge_store_ask_where_is(store, what)
	if content == "" {
		fmt.sbprintf(&self.out, "You don't believe R%d is in anything, to ask who told you.\n", what)
		return
	}
	play_say(self, content, who, true)
}


@(private = "file")
play_tell :: proc(self: ^Play, words: []string) {
	store:   ^Knowledge_Store
	content: string
	who:     u32
	what:    u32
	within:  u32

	store  = knowledge_store_of(self.knowledge, self.actor)
	who    = play_referent_named(self, words[1]) if len(words) > 2 else 0
	what   = play_referent_named(self, words[2]) if len(words) > 2 else 0
	within = play_referent_named(self, words[4]) if len(words) > 4 else 0
	if who == 0 || what == 0 || (len(words) > 3 && within == 0) {
		strings.write_string(&self.out, "Tell whom what? tell <R> <R> [in <R>].\n")
		return
	}
	content = knowledge_store_claim_that(store, what, within) if within != 0 else knowledge_store_claim_about(store, what)
	if content == "" {
		fmt.sbprintf(&self.out, "You can't say where R%d is: you believe it in nothing on the ground.\n", what)
		return
	}
	play_say(self, content, who, false)
}


/* --- the notebook ------------------------------------------------------------------ */

/* What the actor knows, as it knows it: never a truth link. */
@(private = "file")
play_show_notebook :: proc(self: ^Play) {
	store:  ^Knowledge_Store
	r:      ^Referent
	holder: ^Referent
	t:      ^Testimony
	u:      ^Testimony
	f:      ^Finding
	tr:     ^Trace_Seen
	places: strings.Builder
	n:      uint
	now:    i64

	store = knowledge_store_of(self.knowledge, self.actor)
	now   = world_time(self.world).ms
	strings.write_string(&self.out, "Things you know of:\n")
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		r = knowledge_store_referent_at(store, i)
		if r.id == knowledge_store_self_referent(store) do continue
		holder = knowledge_store_referent(store, r.container) if r.container != 0 else nil
		fmt.sbprintf(&self.out, "  R%d %s", r.id, r.kind)
		if !r.present {
			strings.write_string(&self.out, ", you don't know where")
		} else if holder != nil {
			fmt.sbprintf(&self.out, ", %s R%d", "in" if r.form == .In else "held by" if r.form == .Held_By else "part of",
			             holder.id)
		} else {
			fmt.sbprintf(&self.out, ", at (%d, %d)", r.x, r.y)
		}
		fmt.sbprintf(&self.out, "%s%s\n", fmt.tprintf(", %ds ago", (now - r.seen) / 1000) if r.seen < now else "",
		             fmt.tprintf(", R%d says", r.toldBy) if r.toldBy != 0 else "")
	}
	if knowledge_store_testimony_count(store) != 0 do strings.write_string(&self.out, "What you've been told:\n")
	for i: uint = 0; i < knowledge_store_testimony_count(store); i += 1 {
		t = knowledge_store_testimony_at(store, i)
		fmt.sbprintf(&self.out, "  R%d in R%d: R%d %s, %s%s\n", t.thing, t.container, t.source,
		             "wrote so" if t.via != 0 else "said so",
		             ("having seen it" if t.attribution == .Saw
		                else "having heard it from you" if t.attribution == .Heard_From && t.root == knowledge_store_self_referent(store)
		                else fmt.tprintf("having heard it from R%d", t.root) if t.attribution == .Heard_From
		                else "having heard it"),
		             "; so it was" if t.settled > 0 else "; it wasn't" if t.settled < 0 else "")
	}
	/* open questions: something claimed to be in more than one place */
	for i: uint = 0; i < knowledge_store_testimony_count(store); i += 1 {
		t      = knowledge_store_testimony_at(store, i)
		places = strings.builder_make(context.temp_allocator)
		n      = 0
		for j: uint = 0; j < knowledge_store_testimony_count(store); j += 1 {
			u = knowledge_store_testimony_at(store, j)
			if u.thing != t.thing || u.settled < 0 do continue
			if j < i do break      /* asked already */
			if ns_contains(strings.to_string(places), fmt.tprintf(" R%d ", u.container)) do continue
			fmt.sbprintf(&places, "%sin R%d (%+d dB) ", "or " if n != 0 else "", u.container,
			             knowledge_store_credence_that(store, u.thing, u.container))
			n += 1
		}
		if n > 1 do fmt.sbprintf(&self.out, "Where is R%d? %s\n", t.thing, strings.to_string(places))
	}
	if knowledge_store_finding_count(store) != 0 do strings.write_string(&self.out, "What you make of it:\n")
	for i: uint = 0; i < knowledge_store_finding_count(store); i += 1 {
		f = knowledge_store_finding_at(store, i)
		fmt.sbprintf(&self.out, "  R%d: %s (%+d dB)\n", f.about, f.kind, f.credence)
	}
	for i: uint = 0; i < knowledge_store_trace_count(store); i += 1 {
		tr = knowledge_store_trace_at(store, i)
		if tr.present {
			fmt.sbprintf(&self.out, "  %s %s, %d\n", tr.kind,
			             fmt.tprintf("on R%d", tr.bearer) if tr.bearer != 0 else fmt.tprintf("at (%d, %d)", tr.x, tr.y),
			             tr.strength)
		}
	}
}


/* write <R>: into a record the actor holds */
@(private = "file")
play_write :: proc(self: ^Play, words: []string) {
	store:   ^Knowledge_Store
	r:       ^Referent
	writing: string
	action:  Action
	what:    u32
	record:  u32

	store  = knowledge_store_of(self.knowledge, self.actor)
	what   = play_referent_named(self, words[1]) if len(words) > 1 else 0
	record = 0
	for i: uint = 0; i < knowledge_store_count(store) && record == 0; i += 1 {
		r = knowledge_store_referent_at(store, i)
		if r.present && r.form == .Held_By && r.container == knowledge_store_self_referent(store) && r.kind != nil &&
		   string(r.kind) == "#Record" {
			record = r.id
		}
	}
	if record == 0 {
		strings.write_string(&self.out, "You hold no notebook.\n")
		return
	}
	if what != 0 do writing = knowledge_store_writing_about(store, what)
	if what == 0 || writing == "" {
		strings.write_string(&self.out, "Write where what is? write <R>, for something you believe is in something.\n")
		return
	}
	action         = action_make(world_intern(self.world, "write_down"), Entity_ID(knowledge_store_self_referent(store)),
	                             Entity_ID(record), NO_ENTITY)
	action.content = world_intern(self.world, ns_utf8(writing))
	play_perform(self, action, 0)
}


/* --- autopilot ----------------------------------------------------------------------- */

@(private = "file")
play_autopilot :: proc(self: ^Play, words: []string) {
	notices:   []string
	threshold: i32

	threshold = ns_int_value(words[2]) if len(words) > 2 else 20
	if len(words) < 2 ||
	   !agency_autopilot_to_goal(self.agency, self.actor, world_intern(self.world, ns_utf8(words[1])), threshold) {
		fmt.sbprintf(&self.out, "There is no goal %s.\n", words[1] if len(words) > 1 else "")
		return
	}
	fmt.sbprintf(&self.out, "Autopilot: %s, until something is worth more than %d.\n", words[1], threshold)
	self.inputDue = true
	for agency_controls(self.agency, self.actor) &&
	    scheduler_step_until(self.scheduler, time_make(world_time(self.world).ms + 600000)) {
	}
	play_show_trace(self)
	play_show_news(self)
	notices = agency_take_notices(self.agency)
	for i := 0; i < len(notices); i += 1 do fmt.sbprintf(&self.out, "%s\n", notices[i])
	if agency_controls(self.agency, self.actor) {
		agency_relinquish(self.agency, self.actor)
		strings.write_string(&self.out, "Nothing more happens. Control returns to you.\n")
	}
	fmt.sbprintf(&self.out, "t=%dms\n", world_time(self.world).ms)
}


/* --- the commands ------------------------------------------------------------------ */

@(private = "file")
play_is_running :: proc(self: ^Play, activity: Entity_ID) -> bool {
	record: ^Activity

	record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), activity))
	return record != nil && record.status == u32(tri.type_named(world_tri(self.world), "\"running\""))
}


@(private = "file")
play_actor_busy :: proc(self: ^Play) -> bool {
	record:  ^Activity
	mine:    [^]Entity_ID
	n:       uint
	running: tri.Type
	busy:    bool

	running = tri.type_named(world_tri(self.world), "\"running\"")
	mine    = world_copy_activities_of(self.world, self.actor, &n)
	busy    = false
	for i: uint = 0; i < n && !busy; i += 1 {
		record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), mine[i]))
		busy   = record != nil && record.status == u32(running)
	}
	free(mine)
	return busy
}


@(private = "file")
play_list_activities :: proc(self: ^Play) {
	record: ^Activity
	mine:   [^]Entity_ID
	n:      uint
	any:    bool

	mine = world_copy_activities_of(self.world, self.actor, &n)
	any  = false
	for i: uint = 0; i < n; i += 1 {
		record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), mine[i]))
		if record == nil do continue
		fmt.sbprintf(&self.out, "%d %s: %s, stage %d, %dms done%s\n", mine[i],
		             world_text_field(self.world, "Activity.operation", mine[i]),
		             tri.type_name(world_tri(self.world), record.status), record.stage,
		             record.progress,
		             fmt.tprintf(", due at %dms", record.due) if record.due != 0 else "")
		any = true
	}
	free(mine)
	if !any do strings.write_string(&self.out, "You have done nothing yet.\n")
}


@(private = "file", rodata)
DETAIL_GLYPHS := [4]string{".", "A", "R", "F"}

/* The developer's view of the reality bubble (REALITY.md): the anchors,
 * and the level of detail of the chunks around the actor, a character a
 * chunk: F full, R reduced, A abstract, . frozen; @ where the actor is. */
@(private = "file")
play_show_reality :: proc(self: ^Play) {
	reality: ^Reality
	here:    Location
	tile:    Location
	e:       Entity_ID
	cx:      i32
	cy:      i32
	cz:      i32
	centred: bool
	kind:    i32

	reality = world_reality(self.world)
	if reality_anchor_count(reality) == 0 {
		strings.write_string(&self.out, "No anchors: the whole world is at full detail.\n")
		return
	}
	for i: uint = 0; i < reality_anchor_count(reality); i += 1 {
		e = reality_anchor_at(reality, i, &kind, &cx, &cy, &cz, &centred)
		fmt.sbprintf(&self.out, "anchor %d, a %s, centred %s\n", e, reality_kind_name(reality, kind),
		             fmt.tprintf("on chunk (%d, %d) level %d", cx, cy, cz) if centred else "nowhere yet")
	}
	for i: uint = 0; i < reality_lease_count(reality); i += 1 {
		until: i64

		e = reality_lease_at(reality, i, &until)
		fmt.sbprintf(&self.out, "%d held at full detail by contact until %dms\n", e, until)
	}
	here = world_location_of(self.world, self.actor)
	if here.form != .On_Tile do return
	for dy: i32 = -8; dy <= 8; dy += 1 {
		for dx: i32 = -8; dx <= 8; dx += 1 {
			tile = on_tile(here.x + dx * 32, here.y + dy * 32, here.level)
			if dx == 0 && dy == 0 {
				strings.write_string(&self.out, "@")
			} else if !world_is_tile_x(self.world, tile.x, tile.y, tile.level) {
				strings.write_string(&self.out, " ")         /* off the map */
			} else {
				strings.write_string(&self.out, DETAIL_GLYPHS[uint(world_detail_at(self.world, tile))])
			}
		}
		strings.write_string(&self.out, "\n")
	}
}


/* Runs one command line. NO when it was quit. */
play_command :: proc(self: ^Play, line: string) -> bool {
	words:  [dynamic]string
	error:  string
	parts:  []string
	verb:   string
	w:      string
	a:      ^Action
	g:      ^Proposal_Group
	e:      Entity_ID
	step:   Entity_ID
	n:      uint
	amount: i64

	parts = ns_components_separated(line, " ")
	words = make([dynamic]string, context.temp_allocator)
	for i := 0; i < len(parts); i += 1 {
		w = parts[i]
		if len(w) != 0 do append(&words, w)
	}
	if len(words) == 0 || ns_has_prefix(words[0], "#") do return true
	verb = words[0]
	n    = uint(ns_long_long_value(words[1])) if len(words) > 1 else 0
	e    = Entity_ID(n)

	if verb == "quit" do return false
	if verb == "help" {
		strings.write_string(&self.out, "look, menu, do <n> [amount], walk n|s|e|w, ask <R> where|who <R>, tell <R> <R> [in <R>],\n" +
		                                "notebook, write <R>, read <R>, note <text>, notes, autopilot <goal> [n],\n" +
		                                "wait <ms>, step, idle, as <id>,\n" +
		                                "activities, suspend <id>, resume <id>, knows [id], inspect <id>, why <id>, trace [n],\n" +
		                                "reality, anchor <kind>|off,\n" +
		                                "save <file>, load <file>, time, hash, quit\n")
	} else if verb == "look" {
		play_look(self)
	} else if verb == "reality" {
		play_show_reality(self)
	} else if verb == "anchor" && len(words) > 1 {
		if words[1] == "off" {
			world_remove_anchor(self.world, self.actor)
			strings.write_string(&self.out, "You no longer anchor the world.\n")
		} else if world_set_anchor(self.world, self.actor, ns_utf8(words[1])) {
			world_settle_anchors(self.world)
			fmt.sbprintf(&self.out, "You anchor the world, as a %s.\n", words[1])
		} else {
			fmt.sbprintf(&self.out, "There is no kind of anchor called %s.\n", words[1])
		}
	} else if verb == "menu" {
		play_show_menu(self)
	} else if verb == "do" {
		if self.menu == nil do play_show_menu(self)
		if n < 1 || n > menu_count(self.menu) {
			strings.write_string(&self.out, "There is no such entry; type menu.\n")
		} else {
			a      = menu_action_at(self.menu, n - 1)
			amount = ns_long_long_value(words[2]) if len(words) > 2 else 0
			play_perform(self, a^, amount)
		}
	} else if verb == "notebook" {
		play_show_notebook(self)
	} else if verb == "write" {
		play_write(self, words[:])
	} else if verb == "read" {
		if play_referent_named(self, words[1] if len(words) > 1 else "") == 0 {
			strings.write_string(&self.out, "Read what? read <R>.\n")
		} else {
			g = play_perform(self, action_make(world_intern(self.world, "read"),
			                                   Entity_ID(knowledge_store_self_referent(knowledge_store_of(self.knowledge, self.actor))),
			                                   Entity_ID(play_referent_named(self, words[1])), NO_ENTITY), 0)
			if g != nil {
				/* reading takes a second: read before the next command */
				step = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
				for play_is_running(self, step) &&
				    scheduler_step_until(self.scheduler, time_make(world_time(self.world).ms + 600000)) {
				}
				play_show_trace(self)
				play_show_news(self)
			}
		}
	} else if verb == "note" {
		append(&self.notes, strings.join(words[1:], " "))
		strings.write_string(&self.out, "Noted, for you; your character knows nothing of it.\n")
	} else if verb == "notes" {
		for i := 0; i < len(self.notes); i += 1 do fmt.sbprintf(&self.out, "%d. %s\n", i + 1, self.notes[i])
		if len(self.notes) == 0 do strings.write_string(&self.out, "You have no notes.\n")
	} else if verb == "autopilot" {
		play_autopilot(self, words[:])
	} else if verb == "ask" {
		play_ask(self, words[:])
	} else if verb == "tell" {
		play_tell(self, words[:])
	} else if verb == "walk" && len(words) > 1 {
		w = words[1]
		walk := fmt.tprintf("walk_%s", ("north" if ns_has_prefix(w, "n") else "south" if ns_has_prefix(w, "s")
		                                else "east" if ns_has_prefix(w, "e") else "west"))
		if len(walk) > 15 do walk = walk[:15]       // snprintf into char[16]
		g = play_perform(self, action_make(world_intern(self.world, ns_utf8(walk)), self.actor, NO_ENTITY, NO_ENTITY), 0)
		if g != nil {
			/* a step takes a second: the player's character arrives before the next command */
			step = proposal_group_id_for(g, proposal_group_proposals(g)[0].handle)
			for play_is_running(self, step) &&
			    scheduler_step_until(self.scheduler, time_make(world_time(self.world).ms + 600000)) {
			}
			play_show_trace(self)
			play_show_news(self)
		}
	} else if verb == "wait" {
		scheduler_run_until(self.scheduler, time_make(world_time(self.world).ms + i64(n)))
		play_show_trace(self)
		play_show_news(self)
		fmt.sbprintf(&self.out, "t=%dms\n", world_time(self.world).ms)
	} else if verb == "step" {
		if !scheduler_step_until(self.scheduler, time_make(max(i64) - 1)) {
			strings.write_string(&self.out, "Nothing more happens.\n")
		}
		play_show_trace(self)
		fmt.sbprintf(&self.out, "t=%dms\n", world_time(self.world).ms)
	} else if verb == "idle" {
		for play_actor_busy(self) &&
		    scheduler_step_until(self.scheduler, time_make(world_time(self.world).ms + 600000)) {
		}
		play_show_trace(self)
		fmt.sbprintf(&self.out, "t=%dms\n", world_time(self.world).ms)
	} else if verb == "as" {
		if world_record(self.world, world_kind_named(self.world, "Agent"), e) == nil {
			fmt.sbprintf(&self.out, "%d is not an agent.\n", e)
		} else {
			agency_relinquish(self.agency, self.actor)        /* off autopilot, if it was */
			self.actor = e
			play_control_others(self)
			release(self.menu)
			self.menu = nil
			fmt.sbprintf(&self.out, "You are %d.\n", e)
		}
	} else if verb == "activities" {
		play_list_activities(self)
	} else if verb == "suspend" || verb == "resume" {
		error = ""
		if (activities_suspend(self.activities, e, "the actor's choice", &error) == nil if verb == "suspend"
		    else activities_resume(self.activities, e, &error) == nil) {
			fmt.sbprintf(&self.out, "You can't: %s.\n", error)
		} else {
			self.inputDue = true
			scheduler_step_until(self.scheduler, world_time(self.world))
			play_show_trace(self)
		}
	} else if verb == "knows" {
		strings.write_string(&self.out, knowledge_dump(self.knowledge, e if e != 0 else self.actor))
	} else if verb == "inspect" {
		play_inspect(self, e)
	} else if verb == "why" {
		play_why(self, e)
	} else if verb == "trace" {
		parts = committer_trace(self.committer)
		last := n if n != 0 else 20
		for i := uint(len(parts)) - last if uint(len(parts)) > last else 0; i < uint(len(parts)); i += 1 {
			fmt.sbprintf(&self.out, "%s\n", parts[i])
		}
	} else if verb == "save" && len(words) > 1 {
		play_save(self, words[1])
	} else if verb == "load" && len(words) > 1 {
		play_load(self, words[1])
	} else if verb == "time" {
		fmt.sbprintf(&self.out, "t=%dms, boundary %d\n", world_time(self.world).ms,
		             world_boundary(self.world))
	} else if verb == "hash" {
		fmt.sbprintf(&self.out, "state hash %016x\n", world_state_hash(self.world))
	} else {
		fmt.sbprintf(&self.out, "What is \"%s\"? Type help.\n", verb)
	}
	return true
}

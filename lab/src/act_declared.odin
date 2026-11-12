package lab

/*
 * Declared effects (EFFECTS.md, content/actions.tri): what an operation
 * does, as its content says it, applied by the one procedure here. An
 * operation with no named effect (`effect`) has a declared one: its roles
 * as the effect leaves them (`after`), what it moves (`moves`), constructs
 * (`makes`) and destroys (`consumes`), whole or a portion of a stack, and
 * the events it emits (`emits`).
 *
 * Resolving it is a unification: the operation's pattern with the truth
 * projection of what fills its roles. Where that fails, a requirement the
 * operation states doesn't hold, and the failure's path is the reason.
 * Where it succeeds, the tags the roles bind have reached `after`, `moves`
 * and `emits`, and each concrete value there is a proposal.
 *
 * A staged operation's stages each have their own: the roles are the
 * operation's, and its tags reach every stage.
 *
 * Not built: `changes`; a move into an assembly.
 * Arithmetic in `after` (`handfuls: $h - 1`, `math.Clamp`) is worked out by
 * the unification: the pattern brings the operation's own arithmetic.
 */

import "core:fmt"
import "core:strconv"
import "core:strings"
import tri "../../triangle/odin/triangle"


/* A node as Triangle prints it, "" for nil. */
@(private = "file")
printed :: proc(tc: ^tri.Content, v: ^tri.Node) -> string {
	buf: [256]u8

	if v == nil do return ""
	n := tri.print(tc, v, raw_data(buf[:]), len(buf))
	if n == 0 || n >= len(buf) do return ""
	return strings.clone(string(buf[:n]), context.temp_allocator)
}


/* The entity a node refers to, `ref(7)`: false while it is open. */
@(private = "file")
ref_of :: proc(tc: ^tri.Content, v: ^tri.Node) -> (Entity_ID, bool) {
	s := printed(tc, v)
	if !strings.has_prefix(s, "ref(") || !strings.has_suffix(s, ")") do return NO_ENTITY, false
	id, ok := strconv.parse_u64(s[4:len(s) - 1], 10)
	return Entity_ID(id), ok && id != 0
}


/* A node's text, decoded: false unless it is a concrete text. */
@(private = "file")
text_of_node :: proc(tc: ^tri.Content, v: ^tri.Node) -> (string, bool) {
	buf: [256]u8

	if !strings.has_prefix(printed(tc, v), "\"") do return "", false
	n := tri.text(tc, v, raw_data(buf[:]), len(buf))
	if n == ~uint(0) || n >= len(buf) do return "", false
	return strings.clone(string(buf[:n]), context.temp_allocator), true
}


/* What `after` says of one field of a role's entity, as a proposal: nothing
 * while the value is open, or is what the field holds already. Of a
 * `portion` just split off the entity (a handle, its fields the entity's),
 * it is set outright: nobody else can have got to it. */
@(private = "file")
declared_set :: proc(world: ^World, entity: Entity_ID, portion: Entity_ID, kind: ^Component_Info, f: ^Field_Info,
                     record: rawptr, v: ^tri.Node, g: ^Proposal_Group) -> string {
	lo, hi: i64
	value: i64

	tc := world_tri(world)
	s  := printed(tc, v)
	switch f.value {
	case VALUE_QUANTITY:
		if tri.node_interval(v, &lo, &hi) == 0 || lo != hi do return ""
		value = lo
	case VALUE_BOOL:
		if s != "true" && s != "false" do return ""
		value = 1 if s == "true" else 0
	case VALUE_REF:
		e, ok := ref_of(tc, v)
		if !ok do return ""
		value = i64(e)
	case VALUE_TYPE:
		if !strings.has_prefix(s, "\"") do return ""
		value = i64(tri.type_named(tc, ns_utf8(s)))
	case VALUE_TEXT:
		text, ok := text_of_node(tc, v)
		was := (^cstring)(uintptr(record) + f.offset)^
		if !ok || text == string(was) do return ""
		if !strings.contains(string(f.flags), "proposable") {
			return fmt.tprintf("%s.%s is not an effect's to set", kind.name, f.name)
		}
		proposal_group_set_of_to_text(g, world_intern(world, ns_utf8(fmt.tprintf("%s.%s", kind.name, f.name))),
		                              whole(portion if portion != NO_ENTITY else entity), world_intern(world, ns_utf8(text)))
		return ""
	case:
		return ""
	}
	was: i64
	path := world_intern(world, ns_utf8(fmt.tprintf("%s.%s", kind.name, f.name)))
	if !world_get_field(world, path, entity, &was) || value == was do return ""
	if !strings.contains(string(f.flags), "proposable") {
		return fmt.tprintf("%s.%s is not an effect's to set", kind.name, f.name)
	}
	if portion != NO_ENTITY {
		proposal_group_set_of_to(g, path, whole(portion), value)
		return ""
	}
	/* from the value it was read with: if another gets there first, this fails */
	proposal_group_set_of_to_expecting(g, path, whole(entity), value, was)
	return ""
}


/* A whole number a node holds: false while it is open. */
@(private = "file")
int_of :: proc(v: ^tri.Node) -> (i64, bool) {
	lo, hi: i64

	if v == nil || tri.node_interval(v, &lo, &hi) == 0 || lo != hi do return 0, false
	return lo, true
}


/* The place a `moves` or a `makes` names, as a location: a tile, a container, or a
 * hand; into a hand is into a free one of theirs, unless it says which. */
@(private = "file")
declared_place :: proc(world: ^World, into: ^tri.Node) -> (Location, string) {
	lo, hi: i64

	tc   := world_tri(world)
	name := string(tri.type_name(tc, tri.node_type(into))) if into != nil else ""
	if strings.has_suffix(name, "#OnTile") {
		x, okx := int_of(tri.at(tc, into, "x"))
		y, oky := int_of(tri.at(tc, into, "y"))
		l, okl := int_of(tri.at(tc, into, "level"))
		if !okx || !oky || !okl do return {}, "a move onto a tile says which"
		return on_tile(i32(x), i32(y), i32(l)), ""
	}
	if strings.has_suffix(name, "#Inside") {
		container, ok := ref_of(tc, tri.at(tc, into, "container"))
		if !ok do return {}, "a move into a container says which: tag the role's id"
		return in_(container), ""
	}
	if !strings.has_suffix(name, "#Held") {
		return {}, fmt.tprintf("a move into %s is not built", name if name != "" else "nothing")
	}
	by, ok := ref_of(tc, tri.at(tc, into, "by"))
	if !ok do return {}, "a move into a hand says whose: tag the role's id"
	if hand := tri.at(tc, into, "hand"); hand != nil && tri.node_interval(hand, &lo, &hi) != 0 && lo == hi {
		return held_by(by, i32(lo)), ""
	}
	hand := free_hand(world, by)
	if hand < 0 do return {}, "no hand of theirs is free"
	return held_by(by, hand), ""
}


/* Where a step is in its operation, as a path with its dot: "" for an
 * operation with no stages, which is its own one step; else stage `index`. */
@(private = "file")
step_path :: proc(tc: ^tri.Content, pattern: ^tri.Node, index: i64) -> string {
	if tri.at(tc, pattern, "stages.first") == nil do return ""
	path := strings.builder_make(context.temp_allocator)
	strings.write_string(&path, "stages.")
	for _ in 0 ..< index do strings.write_string(&path, "rest.")
	strings.write_string(&path, "first.")
	return strings.to_string(path)
}


/* Whether a step says what it does: a named effect, something declared, or
 * a trace it leaves or removes (tending changes nothing but traces). */
@(private = "file")
step_says :: proc(tc: ^tri.Content, pattern: ^tri.Node, step: string) -> bool {
	if strings.has_prefix(printed(tc, tri.at(tc, pattern, ns_utf8(fmt.tprintf("%seffect", step)))), "\"") do return true
	for r in Role.Actor ..< Role.Count {
		if tri.at(tc, pattern, ns_utf8(fmt.tprintf("%safter.%s", step, ROLE_NAMES[r]))) != nil do return true
	}
	for list in ([?]string{"moves", "makes", "consumes", "emits", "leaves", "removes"}) {
		if tri.at(tc, pattern, ns_utf8(fmt.tprintf("%s%s.first", step, list))) != nil do return true
	}
	return false
}


/* Every operation's every step says what it does: "" if so, else the first
 * that doesn't. An `effect:` left out by mistake would otherwise load, and
 * do nothing. */
declared_check :: proc(tc: ^tri.Content) -> string {
	for name in ([?]cstring{"operations", "going"}) {
		family := tri.family_index(tc, name)
		if family == nil do continue
		n := tri.index_count(family)
		for o: uint = 0; o < n; o += 1 {
			operation := cstring(tri.index_tag(family, o))
			pattern   := tri.pattern(tc, operation)
			if pattern == nil do continue
			if tri.at(tc, pattern, "stages.first") == nil {
				if !step_says(tc, pattern, "") do return fmt.tprintf("the operation %s does nothing: it has no effect, named or declared", operation)
				continue
			}
			for k: i64 = 0; tri.at(tc, pattern, ns_utf8(fmt.tprintf("%sduration", step_path(tc, pattern, k)))) != nil; k += 1 {
				if !step_says(tc, pattern, step_path(tc, pattern, k)) {
					return fmt.tprintf("stage %d of the operation %s does nothing: it has no effect, named or declared", k, operation)
				}
			}
		}
	}
	return ""
}


/* A step's declared effect, as proposals added to `group`: the operation's
 * own, or its stage `stage`'s if it has stages. The reason if it can't be
 * built, "" for none. */
apply_declared_effect :: proc(world: ^World, action: Action, stage: i64, group: ^Proposal_Group) -> string {
	err: [256]u8
	failure: tri.Failure

	tc      := world_tri(world)
	pattern := tri.pattern(tc, action.operation) if action.operation != nil else nil
	if pattern == nil do return fmt.tprintf("there is no operation %s", action.operation)
	step := step_path(tc, pattern, stage)

	/* resolve: the pattern, with what fills its roles as it truly is */
	expr := strings.builder_make(context.temp_allocator)
	// Odin's fmt reads "{" as the start of an argument index: "{{" is a brace
	fmt.sbprintf(&expr, "%s & {{ roles: {{", tri.type_name(tc, tri.node_type(pattern)))
	for r in Role.Actor ..< Role.Count {
		if action.roles[r] == NO_ENTITY || tri.at(tc, pattern, ns_utf8(fmt.tprintf("roles.%s", ROLE_NAMES[r]))) == nil do continue
		fmt.sbprintf(&expr, " %s: %s,", ROLE_NAMES[r], truth_describe_entity(world, action.roles[r]))
	}
	/* the time this commits, for what the effect reckons from it */
	clock: [64]u8
	tri.format_quantity("time", world_time(world).ms, raw_data(clock[:]), len(clock))
	fmt.sbprintf(&expr, " }}, now: %s }}", cstring(&clock[0]))
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	truth := tri.value(tc, ns_utf8(strings.to_string(expr)), arena, &err[0], size_of(err))
	if truth == nil {
		return fmt.tprintf("the truth does not build: %s, in %s", cstring(&err[0]), strings.to_string(expr))
	}
	result := tri.unify(tc, pattern, truth, arena, &failure)
	if result == nil {
		return fmt.tprintf("%s fails at %s", action.operation, cstring(&failure.path[0]))
	}

	/* moves: first, since units moved off a stack are that role from then
	 * on, and `after` speaks of them */
	portions: [Role]Entity_ID
	for list := tri.at(tc, result, ns_utf8(fmt.tprintf("%smoves", step))); list != nil; list = tri.at(tc, list, "rest") {
		move := tri.at(tc, list, "first")
		if move == nil do break
		moved, ok := ref_of(tc, tri.at(tc, move, "moved"))
		if !ok do return fmt.tprintf("%s moves nothing: tag the role's id", action.operation)
		to, reason := declared_place(world, tri.at(tc, move, "into"))
		if reason != "" do return reason
		/* a portion: so many units, split off; all of them is the thing itself */
		if n, some := int_of(tri.at(tc, move, "portion")); some && n < world_units_of(world, moved) {
			part := proposal_group_split(group, whole(moved), n, to)
			for r in Role.Actor ..< Role.Count do if action.roles[r] == moved do portions[r] = part
			continue
		}
		/* where it is to go already (in a hand of theirs, in that container,
		 * on that tile): nothing moves */
		if at := world_location_of(world, moved); at.form == to.form && at.place == to.place &&
		   (at.form != .On_Tile || (at.x == to.x && at.y == to.y && at.level == to.level)) {
			continue
		}
		/* from where it is now: if someone else gets it first, this fails */
		proposal_group_move_to_expecting(group, whole(moved), to, world_location_of(world, moved))
	}

	/* after: each field a role is left with, by role, component and field */
	for r in Role.Actor ..< Role.Count {
		entity := action.roles[r]
		after  := tri.at(tc, result, ns_utf8(fmt.tprintf("%safter.%s", step, ROLE_NAMES[r])))
		if entity == NO_ENTITY || after == nil do continue
		for k: uint = 0; k < world_kind_count(world); k += 1 {
			record := world_record(world, k, entity)
			if record == nil do continue
			kind := world_kind_info(world, k)
			for i: uint = 0; i < kind.nfields; i += 1 {
				f := &kind.fields[i]
				v := tri.at(tc, after, f.name)
				if v == nil do continue
				if reason := declared_set(world, entity, portions[r], kind, f, record, v, group); reason != "" do return reason
			}
		}
	}

	/* makes: before what is consumed, which a thing made may stand where */
	for list := tri.at(tc, result, ns_utf8(fmt.tprintf("%smakes", step))); list != nil; list = tri.at(tc, list, "rest") {
		made := tri.at(tc, list, "first")
		if made == nil do break
		blueprint, ok := text_of_node(tc, tri.at(tc, made, "blueprint"))
		if !ok || blueprint == "" do return fmt.tprintf("%s makes nothing: it says no blueprint", action.operation)
		if tri.pattern(tc, ns_utf8(blueprint)) == nil do return fmt.tprintf("%s makes a %s, which is no blueprint", action.operation, blueprint)
		at, reason := declared_place(world, tri.at(tc, made, "at"))
		if reason != "" do return reason
		called, named := text_of_node(tc, tri.at(tc, made, "called"))
		thing := proposal_group_create(group, world_intern(world, ns_utf8(blueprint)),
		                               world_intern(world, ns_utf8(called if named else blueprint)), at)
		if from, carved := ref_of(tc, tri.at(tc, made, "splitFrom")); carved {
			proposal_group_relate(group, .Split_From, whole(thing), whole(from))
		}
	}

	/* consumes */
	for list := tri.at(tc, result, ns_utf8(fmt.tprintf("%sconsumes", step))); list != nil; list = tri.at(tc, list, "rest") {
		gone := tri.at(tc, list, "first")
		if gone == nil do break
		consumed, ok := ref_of(tc, tri.at(tc, gone, "consumed"))
		because, why := text_of_node(tc, tri.at(tc, gone, "because"))
		if !ok || !why do return fmt.tprintf("%s consumes nothing, or for no reason: tag the role's id, and say `because`", action.operation)
		reason := world_intern(world, ns_utf8(because))
		/* a portion: so many units, split off where the stack is, and gone */
		if n, some := int_of(tri.at(tc, gone, "portion")); some && n < world_units_of(world, consumed) {
			part := proposal_group_split(group, whole(consumed), n, world_location_of(world, consumed))
			proposal_group_destroy(group, whole(part), reason)
			continue
		}
		proposal_group_destroy(group, whole(consumed), reason)
	}

	/* emits */
	for list := tri.at(tc, result, ns_utf8(fmt.tprintf("%semits", step))); list != nil; list = tri.at(tc, list, "rest") {
		emit := tri.at(tc, list, "first")
		if emit == nil do break
		event, named := text_of_node(tc, tri.at(tc, emit, "event"))
		subject, has := ref_of(tc, tri.at(tc, emit, "subject"))
		other, _     := ref_of(tc, tri.at(tc, emit, "other"))
		if !named || !has do return fmt.tprintf("%s emits an event with no kind or subject", action.operation)
		proposal_group_emit_subject_other(group, world_intern(world, ns_utf8(event)), whole(subject), whole(other))
	}
	return ""
}

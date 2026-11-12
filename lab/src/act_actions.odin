package lab

/*
 * The action menu and performing actions (ACTIONS.md §1–4). Operations are
 * content: instances of #Operation in the "operations" family. An actor's
 * menu lists each operation and binding of its roles to entities in reach
 * whose match against their descriptions is not incompatible; unknown never
 * excludes. Performing an action checks it is on the menu, then runs the
 * operation's effect, which builds the proposal group commitment applies.
 *
 * (ported from the Objective-C lab's act/BGActions.m)
 */

import "core:fmt"
import "core:slice"
import "core:strings"
import tri "../../triangle/odin/triangle"


Role :: enum i32 {
	Actor = 0,
	Item,
	Destination,
	Count,
}

// BGRoleNames: indexed by Role.
ROLE_NAMES := #partial [Role]cstring{
	.Actor       = "actor",
	.Item        = "item",
	.Destination = "destination",
}

Action :: struct {
	operation: cstring,                     /* interned */
	roles:     [Role]Entity_ID,             /* NO_ENTITY for a role the operation doesn't have */
	content:   cstring,                     /* interned: what is said, for say; or nil */
	way:       cstring,                     /* interned: a walk's way, a letter a tile; or nil */
}

action_make :: #force_inline proc "contextless" (operation: cstring, actor, item, destination: Entity_ID) -> Action {
	a: Action

	a.operation          = operation
	a.roles[.Actor]       = actor
	a.roles[.Item]        = item
	a.roles[.Destination] = destination
	a.content            = nil
	return a
}


/* A stage's effort in ms of the declared pace, at `rate`: as long, in ms. */
at_rate :: #force_inline proc "contextless" (effort, rate: i64) -> i64 {
	return (effort * 100 + rate - 1) / rate if rate > 0 && rate < 100 else effort
}


/* --- helpers for C's buffers ------------------------------------------------- */

// A NUL-terminated buffer as a C string, and as an Odin string (up to its NUL).
@(private = "file")
buf_c :: proc(buf: []u8) -> cstring {
	return cstring(&buf[0])
}

@(private = "file")
buf_s :: proc(buf: []u8) -> string {
	return string(cstring(&buf[0]))
}

// snprintf(buf, len, "%s", s): as much of s as fits, and a NUL.
@(private = "file")
set_text :: proc(buf: []u8, s: string) {
	n := min(len(s), len(buf) - 1)
	copy(buf[:n], s[:n])
	buf[n] = 0
}

// What snprintf into a buffer of `size` bytes keeps of a string: size - 1
// bytes of it, as a C string in the temporary allocator.
@(private = "file")
bounded :: proc(s: string, size: int) -> cstring {
	return strings.clone_to_cstring(s[:min(len(s), size - 1)], context.temp_allocator)
}

// Whether a C string has text: `s && *s`.
has_text :: proc(s: cstring) -> bool {
	return s != nil && ([^]u8)(s)[0] != 0
}

// An assignment in a loop's condition, C's `(p = tri_at( ...))`.
@(private = "file")
got :: proc(dst: ^^tri.Node, v: ^tri.Node) -> bool {
	dst^ = v
	return v != nil
}

// strncmp( a, b, n) == 0.
@(private = "file")
strn_equal :: proc(a, b: cstring, n: int) -> bool {
	pa := ([^]u8)(a)
	pb := ([^]u8)(b)
	for i := 0; i < n; i += 1 {
		if pa[i] != pb[i] do return false
		if pa[i] == 0 do return true
	}
	return true
}


/* --- matching ---------------------------------------------------------------- */

/* Which roles an operation has: the features of its roles' type. */
@(private = "file")
has_role :: proc(content: ^tri.Content, pattern: ^tri.Node, role: Role) -> bool {
	path: cstring

	path = bounded(fmt.tprintf("roles.%s", ROLE_NAMES[role]), 32)
	return tri.at(content, pattern, path) != nil
}


/* NO when the entity's type is strictly more general than the role's: in a
 * description its type would leave the role open, but its kind is perceived. */
@(private = "file")
kind_fits :: proc(world: ^World, pattern: ^tri.Node, role: Role, entity: Entity_ID) -> bool {
	info: ^Entity_Info
	filler: ^tri.Node
	blueprint: ^tri.Node
	content: ^tri.Content
	wanted: tri.Type
	kind: tri.Type
	path: cstring

	content = world_tri(world)
	info    = world_info(world, entity)
	path    = bounded(fmt.tprintf("roles.%s", ROLE_NAMES[role]), 32)
	filler    = tri.at(content, pattern, path)
	blueprint = tri.pattern(content, info.blueprint) if info != nil else nil
	if filler == nil || blueprint == nil {
		return true
	}
	wanted = tri.node_type(filler)
	kind   = tri.node_type(blueprint)
	return !(kind != wanted && tri.subtype(content, wanted, kind) != 0)
}


/* Matches an operation against its roles' descriptions. */
@(private = "file")
match_described :: proc(world: ^World, pattern: ^tri.Node, action: Action, descriptions: ^[Role]string,
                        result: ^tri.Match_Result, reason: ^string) -> tri.Match {
	description: ^tri.Node
	expr: strings.Builder
	content: ^tri.Content
	arena: ^tri.Arena
	match: tri.Match
	copied := [?]cstring{"duration", "stages", "uses", "attention", "leaves", "removes", "partial",
	                     "checkpoints", "hard", "exertion", "floodWatch", "contest"}
	value: [4096]u8
	effect: [64]u8
	err: [256]u8

	content = world_tri(world)
	tri.print(content, tri.at(content, pattern, "effect"), &effect[0], size_of(effect))
	/* the operation's own type: a walk is a #Walk, an operation by its kind;
	 * what the operation itself declares, as it declares it */
	expr = strings.builder_make(context.temp_allocator)
	// Odin's fmt reads "{" as the start of an argument index: "{{" is a brace
	fmt.sbprintf(&expr, "%s & {{ effect: %s, ", tri.type_name(content, tri.node_type(pattern)), buf_c(effect[:]))
	for k := 0; k < len(copied); k += 1 {
		if tri.at(content, pattern, copied[k]) != nil {
			/* cut short, it would not build, or build as something else */
			if tri.print(content, tri.at(content, pattern, copied[k]), &value[0], size_of(value)) >= size_of(value) {
				if reason != nil do reason^ = fmt.tprintf("%s's %s is too long to describe", action.operation, copied[k])
				return .Incompatible
			}
			fmt.sbprintf(&expr, "%s: %s, ", copied[k], buf_c(value[:]))
		}
	}
	strings.write_string(&expr, "roles: {")
	for r in Role.Actor ..< Role.Count {
		if descriptions[r] != "" {
			fmt.sbprintf(&expr, " %s: %s,", ROLE_NAMES[r], descriptions[r])
		}
	}
	strings.write_string(&expr, " } }")
	/* worked out before, for the same operation and description */
	key := fmt.tprintf("described\x00%s\x00%s", action.operation, strings.to_string(expr))
	if m, ok := world_matched(world, key); ok {
		if result != nil do result^ = m.result
		if m.match == .Incompatible && reason != nil {
			failure := m.result.failure
			reason^ = fmt.tprintf("%s is ruled out at %s", action.operation, cstring(&failure.path[0]))
		}
		return m.match
	}
	arena       = tri.arena_new()
	description = tri.value(content, ns_utf8(strings.to_string(expr)), arena, &err[0], size_of(err))
	if description == nil {
		if reason != nil {
			reason^ = fmt.tprintf("the description does not build: %s, in %s", buf_c(err[:]), strings.to_string(expr))
		}
		tri.arena_free(arena)
		return .Incompatible
	}
	worked: tri.Match_Result
	match = tri.match_instance(content, action.operation, description, &worked)
	/* what it does is no requirement: a declared effect (`after`, `moves`,
	 * `consumes`, `emits`, and `now`; a stage's too) is nothing for the actor to find out, and an
	 * operation unknown only in that is entailed. A full list of residuals
	 * may have dropped some (REVIEW.md §4.2 (8)): then it stays unknown. */
	if match == .Unknown && worked.nresidual < tri.MAX_RESIDUAL {
		kept: uint = 0
		for i: uint = 0; i < worked.nresidual; i += 1 {
			path := string(cstring(&worked.residual[i][0]))
			done := false
			for field in ([?]string{"after", "moves", "makes", "consumes", "emits", "now", "parameter"}) {
				if path == field || strings.has_prefix(path, strings.concatenate({field, "."}, context.temp_allocator)) ||
				   (strings.has_prefix(path, "stages.") &&
				    strings.contains(path, strings.concatenate({".", field}, context.temp_allocator))) {
					done = true
				}
			}
			if done do continue
			worked.residual[kept] = worked.residual[i]
			kept += 1
		}
		worked.nresidual = kept
		if kept == 0 {
			match         = .Entailed
			worked.result = .Entailed
		}
	}
	if result != nil do result^ = worked
	if match == .Incompatible && reason != nil {
		reason^ = fmt.tprintf("%s is ruled out at %s", action.operation, cstring(&worked.failure.path[0]))
	}
	world_remember_match(world, key, Matched{match, worked})
	tri.arena_free(arena)
	return match
}


/* A believed kind more general than a role's isn't one (the same rule as kind_fits). */
@(private = "file")
believed_kind_fits :: proc(world: ^World, pattern: ^tri.Node, role: Role, kind: cstring) -> bool {
	filler: ^tri.Node
	k: ^tri.Node
	content: ^tri.Content
	arena: ^tri.Arena
	wanted: tri.Type
	have: tri.Type
	path: cstring
	fits: bool

	content = world_tri(world)
	path    = bounded(fmt.tprintf("roles.%s", ROLE_NAMES[role]), 32)
	filler  = tri.at(content, pattern, path)
	if filler == nil || kind == nil {
		return true
	}
	arena = tri.arena_new()
	k     = tri.value(content, kind, arena, nil, 0)
	fits  = true
	if k != nil {
		wanted = tri.node_type(filler)
		have   = tri.node_type(k)
		fits   = !(have != wanted && tri.subtype(content, wanted, have) != 0)
	}
	tri.arena_free(arena)
	return fits
}


/* As believed, with `supposing`'s competing hypothesis in place of its
 * belief (0: none). (The C's static match_believed: renamed, the public
 * one has its name.) */
@(private = "file")
match_believed_supposing :: proc(world: ^World, store: ^Knowledge_Store, action: Action, result: ^tri.Match_Result,
                                 reason: ^string, supposing: u32, h: uint) -> tri.Match {
	pattern: ^tri.Node
	me: ^Referent
	ref: ^Referent
	descriptions: [Role]string

	result^ = {}
	result.result = .Incompatible
	pattern = tri.pattern(world_tri(world), action.operation) if action.operation != nil else nil
	if pattern == nil || tri.at(world_tri(world), pattern, "effect") == nil {
		if reason != nil {
			reason^ = fmt.tprintf("there is no operation %s", action.operation if action.operation != nil else "?")
		}
		return .Incompatible
	}
	me = knowledge_store_referent(store, knowledge_store_self_referent(store))
	for r in Role.Actor ..< Role.Count {
		descriptions[r] = ""
		if !has_role(world_tri(world), pattern, r) {
			continue
		}
		ref = knowledge_store_referent(store, u32(action.roles[r]))
		/* formulate, from the store: the actor is itself; the rest are believed there, in reach */
		if ref == nil || me == nil || (r == .Actor) != (ref.id == me.id) || !ref.present ||
		   (ref.id != me.id && !referent_in_reach(me, ref, operation_range(world, action.operation))) {
			if reason != nil {
				reason^ = fmt.tprintf("you don't know of a %s in reach", ROLE_NAMES[r])
			}
			return .Incompatible
		}
		if !believed_kind_fits(world, pattern, r, ref.kind) {
			if reason != nil {
				reason^ = fmt.tprintf("R%d is not that kind of thing", ref.id)
			}
			return .Incompatible
		}
		if ref.id == supposing {
			descriptions[r] = knowledge_store_describe_supposed(store, ref.id, h)
		} else {
			descriptions[r] = knowledge_store_describe_referent(store, ref.id)
		}
	}
	return match_described(world, pattern, action, &descriptions, result, reason)
}


/* The match of an action whose roles are the actor's referents, from what
 * its store says; incompatible when a referent is not believed present and
 * in reach. */
match_believed :: proc(world: ^World, store: ^Knowledge_Store, action: Action, result: ^tri.Match_Result,
                       reason: ^string) -> tri.Match {
	return match_believed_supposing(world, store, action, result, reason, 0, 0)
}


/* The credence mass, in thousandths, of the hypotheses under which the
 * action is entailed (CONTENT_LANGUAGE.md §9); `any` gets whether some
 * hypothesis isn't incompatible. */
@(private = "file")
entailed_mass :: proc(world: ^World, store: ^Knowledge_Store, action: Action, believed: tri.Match, any_: ^bool) -> i32 {
	result: tri.Match_Result
	supposed: tri.Match
	h: uint
	doubted: u32
	mass: i32
	entailed: i32

	any_^ = believed != .Incompatible
	for r in Role.Actor ..< Role.Count {
		if action.roles[r] == 0 do continue
		mass = knowledge_store_supposed_mass_of(store, u32(action.roles[r]))
		if mass > 0 {
			doubted  = u32(action.roles[r])
			entailed = 1000 - mass if believed == .Entailed else 0
			for h = 0; h < knowledge_store_hypotheses_of(store, doubted); h += 1 {
				supposed  = match_believed_supposing(world, store, action, &result, nil, doubted, h)
				any_^     = any_^ || supposed != .Incompatible
				entailed += knowledge_store_mass_of(store, doubted, h) if supposed == .Entailed else 0
			}
			return entailed
		}
	}
	return 1000 if believed == .Entailed else 0
}


/* The match of one action from its actor's view. Incompatible, with the
 * reason, when the operation is unknown, a role is missing or out of reach,
 * or the descriptions rule it out. */
match_action :: proc(world: ^World, action: Action, result: ^tri.Match_Result, reason: ^string) -> tri.Match {
	pattern: ^tri.Node
	content: ^tri.Content
	view: ^View
	descriptions: [Role]string

	content = world_tri(world)
	pattern = tri.pattern(content, action.operation) if action.operation != nil else nil
	result^ = {}
	result.result = .Incompatible
	if pattern == nil || tri.at(content, pattern, "effect") == nil {
		if reason != nil {
			reason^ = fmt.tprintf("there is no operation %s", action.operation if action.operation != nil else "?")
		}
		return .Incompatible
	}
	view = view_of(action.roles[.Actor], world)
	for r in Role.Actor ..< Role.Count {
		descriptions[r] = ""
		if !has_role(content, pattern, r) {
			continue
		}
		/* formulate: the actor can bind only what it can reach, and not itself to another role */
		if action.roles[r] == 0 || !view_can_reach(view, action.roles[r], 1 if r == .Actor else operation_range(world, action.operation)) ||
		   (r != .Actor && action.roles[r] == action.roles[.Actor]) {
			if reason != nil {
				reason^ = fmt.tprintf("the %s is not in the actor's reach", ROLE_NAMES[r])
			}
			return .Incompatible
		}
		/* what kind of thing something is can be seen: a thing more general than the role isn't one */
		if !kind_fits(world, pattern, r, action.roles[r]) {
			if reason != nil {
				reason^ = fmt.tprintf("the %s %d is not that kind of thing", ROLE_NAMES[r], action.roles[r])
			}
			return .Incompatible
		}
		descriptions[r] = view_describe_entity(view, action.roles[r])
	}
	return match_described(world, pattern, action, &descriptions, result, reason)
}


/* --- the menu ---------------------------------------------------------------- */

@(private = "file")
cmp_string :: proc(a, b: cstring) -> bool {
	return strings.compare(string(a), string(b)) < 0
}


// _items, _matches, _masses with _count and _capacity: dynamic arrays, a
// menu's count their length.
Menu :: struct {
	using object: Object,
	items:     [dynamic]Action,
	matches:   [dynamic]tri.Match,
	masses:    [dynamic]i32,               /* the credence mass that entails, in thousandths */
	residuals: [dynamic][dynamic]string,   /* each menu item's, cloned */
	believed:  bool,
}


menu_dealloc :: proc(self: ^Menu) {
	delete(self.items)
	delete(self.matches)
	delete(self.masses)
	for i := 0; i < len(self.residuals); i += 1 {
		for j := 0; j < len(self.residuals[i]); j += 1 do delete(self.residuals[i][j])
		delete(self.residuals[i])
	}
	delete(self.residuals)
}


@(private = "file")
menu_add :: proc(self: ^Menu, action: Action, match: tri.Match, result: ^tri.Match_Result) {
	res: [dynamic]string

	append(&self.items, action)
	append(&self.matches, match)
	append(&self.masses, 1000 if match == .Entailed else 0)
	res = make([dynamic]string)
	for i: uint = 0; i < result.nresidual; i += 1 {
		append(&res, strings.clone_from_cstring(cstring(&result.residual[i][0])))
	}
	append(&self.residuals, res)
}


/* sorted by operation name, then by the bound entities */
menu_for_world :: proc(actor: Entity_ID, world: ^World) -> ^Menu {
	menu: ^Menu
	view: ^View
	content: ^tri.Content
	family: ^tri.Index
	result: tri.Match_Result
	match: tri.Match
	pattern: ^tri.Node
	ops: []cstring
	reach: [256]Entity_ID
	action: Action
	nreach: uint
	i: uint
	j: uint
	nops: uint
	o: uint
	item: bool
	destination: bool

	menu           = autorelease(object_new(Menu, menu_dealloc))
	menu.residuals = make([dynamic][dynamic]string)
	content        = world_tri(world)
	family         = tri.family_index(content, "operations")
	if family == nil {
		return menu
	}
	nops = tri.index_count(family)
	ops  = make([]cstring, nops if nops != 0 else 1, context.temp_allocator)
	for o = 0; o < nops; o += 1 {
		ops[o] = cstring(tri.index_tag(family, o))
	}
	slice.sort_by(ops[:nops], cmp_string)
	/* the index has an entry per variant: each operation once */
	j = 0
	for o = 0; o < nops; o += 1 {
		if j == 0 || string(ops[o]) != string(ops[j - 1]) {
			ops[j] = ops[o]
			j += 1
		}
	}
	nops = j

	view   = view_of(actor, world)
	nreach = view_reachable(view, &reach[0], 256)
	if nreach > 256 {
		nreach = 256
	}
	for o = 0; o < nops; o += 1 {
		pattern     = tri.pattern(content, ops[o])
		item        = has_role(content, pattern, .Item)
		destination = has_role(content, pattern, .Destination)
		/* every binding of the roles it has to entities in reach, in ID order */
		for i = 0; i < (nreach if item else 1); i += 1 {
			for j = 0; j < (nreach if destination else 1); j += 1 {
				action = action_make(world_intern(world, ops[o]), actor,
				                     reach[i] if item else NO_ENTITY,
				                     reach[j] if destination else NO_ENTITY)
				if (item && reach[i] == actor) || (destination && reach[j] == actor) ||
				   (item && destination && reach[i] == reach[j]) {
					continue
				}
				match = match_action(world, action, &result, nil)
				if match != .Incompatible {
					menu_add(menu, action, match, &result)
				}
			}
		}
	}
	return menu
}


/* The knowledge view's menu (KNOWLEDGE.md §13): built from the actor's
 * store, its roles bound to referents (R1, R2, ...) believed present and in
 * reach, described as the actor last perceived them. It can offer what is
 * no longer so. */
menu_for_world_believed :: proc(store: ^Knowledge_Store, world: ^World, believed: bool) -> ^Menu {
	menu: ^Menu
	content: ^tri.Content
	family: ^tri.Index
	result: tri.Match_Result
	match: tri.Match
	pattern: ^tri.Node
	me: ^Referent
	ref: ^Referent
	ops: []cstring
	reach: [256]Entity_ID
	actor: Entity_ID
	action: Action
	nreach: uint
	i: uint
	j: uint
	nops: uint
	o: uint
	item: bool
	destination: bool
	any_: bool
	mass: i32

	menu           = autorelease(object_new(Menu, menu_dealloc))
	menu.residuals = make([dynamic][dynamic]string)
	content        = world_tri(world)
	family         = tri.family_index(content, "operations")
	me             = knowledge_store_referent(store, knowledge_store_self_referent(store))
	if family == nil || me == nil {
		return menu
	}
	actor = Entity_ID(me.id)
	nops  = tri.index_count(family)
	ops   = make([]cstring, nops if nops != 0 else 1, context.temp_allocator)
	for o = 0; o < nops; o += 1 {
		ops[o] = cstring(tri.index_tag(family, o))
	}
	slice.sort_by(ops[:nops], cmp_string)
	j = 0
	for o = 0; o < nops; o += 1 {
		if j == 0 || string(ops[o]) != string(ops[j - 1]) {
			ops[j] = ops[o]
			j += 1
		}
	}
	nops = j
	/* what the actor believes is here, in reach, by referent */
	nreach = 0
	for i = 0; i < knowledge_store_count(store) && nreach < 256; i += 1 {
		ref = knowledge_store_referent_at(store, i)
		if ref.present && ref.id != me.id && referent_in_reach(me, ref) {
			reach[nreach] = Entity_ID(ref.id)
			nreach += 1
		}
	}
	for o = 0; o < nops; o += 1 {
		pattern     = tri.pattern(content, ops[o])
		item        = has_role(content, pattern, .Item)
		destination = has_role(content, pattern, .Destination)
		for i = 0; i < (nreach if item else 1); i += 1 {
			for j = 0; j < (nreach if destination else 1); j += 1 {
				if item && destination && reach[i] == reach[j] {
					continue
				}
				action = action_make(world_intern(world, ops[o]), actor, reach[i] if item else NO_ENTITY,
				                     reach[j] if destination else NO_ENTITY)
				match  = match_believed(world, store, action, &result, nil)
				mass   = entailed_mass(world, store, action, match, &any_)
				/* excluded only when every hypothesis rules it out */
				if any_ {
					menu_add(menu, action, .Entailed if mass == 1000 else .Unknown, &result)
					menu.masses[len(menu.masses) - 1] = mass
					/* what to find out: where the hypotheses part */
					for r := Role.Actor; mass < 1000 && r < .Count; r += Role(1) {
						if action.roles[r] != 0 && knowledge_store_supposed_mass_of(store, u32(action.roles[r])) > 0 {
							key: string

							key = string(knowledge_store_overrides_of(store, u32(action.roles[r]), 0))
							key = key[:min(len(key), 64 - 1)]
							if colon := strings.index_byte(key, ':'); colon >= 0 do key = key[:colon]
							append(&menu.residuals[len(menu.residuals) - 1], fmt.aprintf("%s.%s", ROLE_NAMES[r], key))
						}
					}
				}
			}
		}
	}
	menu.believed = believed
	return menu
}


/* YES for a knowledge view's menu: its roles are referents */
menu_believed :: proc(self: ^Menu) -> bool {
	return self.believed
}


menu_count :: proc(self: ^Menu) -> uint {
	return uint(len(self.items))
}


menu_action_at :: proc(self: ^Menu, i: uint) -> ^Action {
	return &self.items[i]
}


menu_match_at :: proc(self: ^Menu, i: uint) -> tri.Match {
	return self.matches[i]
}


/* what the actor would have to find out, for an unknown match. Settled:
 * []string, the menu's own (valid while the menu is). */
menu_residuals_at :: proc(self: ^Menu, i: uint) -> []string {
	return self.residuals[i][:]
}


/* "take item 2: entailed" */
menu_describe_at :: proc(self: ^Menu, i: uint) -> string {
	s: strings.Builder

	s = strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&s, "%s", self.items[i].operation)
	for r in Role.Item ..< Role.Count {
		if self.items[i].roles[r] != 0 {
			if self.believed {
				fmt.sbprintf(&s, " %s R%d", ROLE_NAMES[r], self.items[i].roles[r])
			} else {
				fmt.sbprintf(&s, " %s %d", ROLE_NAMES[r], self.items[i].roles[r])
			}
		}
	}
	strings.write_string(&s, ": entailed" if self.matches[i] == .Entailed else ": unknown")
	if len(self.masses) > 0 && self.masses[i] > 0 && self.masses[i] < 1000 {
		fmt.sbprintf(&s, " (%d in 1000 entails)", self.masses[i])
	}
	if len(menu_residuals_at(self, i)) != 0 {
		fmt.sbprintf(&s, " (find out %s)", strings.join(menu_residuals_at(self, i), ", ", context.temp_allocator))
	}
	return strings.to_string(s)
}


/* --- effects ----------------------------------------------------------------- */

// An effect's reason it can't be built, "" for none.
@(private = "file")
Effect :: #type proc(world: ^World, action: Action, amount: i64, group: ^Proposal_Group) -> string

/* One nail is driven, even from a stack: the proposal names one unit, and
 * commitment splits it off. */
@(private = "file")
effect_drive :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	parts: [64]Entity_ID
	nail: Ref
	i: uint
	n: uint
	index: i32

	nail  = unit(a.roles[.Item], 1) if world_is_stack(world, a.roles[.Item]) else whole(a.roles[.Item])
	n     = world_entities_at(world, a.roles[.Destination], .Part_Of, &parts[0], 64)
	index = 0
	for i = 0; i < n && i < 64; i += 1 {
		at := world_location_of(world, parts[i])
		if location_role(&at) == "wedge" {
			index += 1
		}
	}
	proposal_group_set_of_to(g, "Body.bent", nail, 1)
	proposal_group_set_of_to(g, "Body.toolMarks", nail, 3)
	proposal_group_move_to(g, nail, part_of(a.roles[.Destination], "wedge", index))
	return ""
}


@(private = "file")
effect_walk :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	at: Location
	op: string
	direction: int

	at        = world_location_of(world, a.roles[.Actor])
	op        = string(a.operation)
	direction = strings.index_byte(op, '_')
	if at.form != .On_Tile {
		return "one can walk only on the ground"
	}
	if direction < 0 do return "walk where?"
	switch op[direction + 1] if direction + 1 < len(op) else 0 {
	case 'n': at.y -= 1
	case 's': at.y += 1
	case 'e': at.x += 1
	case 'w': at.x -= 1
	case:     return "walk where?"
	}
	proposal_group_move_to(g, whole(a.roles[.Actor]), at)
	tread(world, at, g)
	return ""
}


/* A step onto a tile (KNOWLEDGE.md §3, foot traffic): each floor trace
 * there whose kind is `trodden` loses that percent of the life it has
 * left, in the step's group. */
@(private = "file")
tread :: proc(world: ^World, at: Location, g: ^Proposal_Group) {
	trace: ^Trace
	v: ^tri.Node
	here: [^]Entity_ID
	n: uint
	i: uint
	now: i64
	lo: i64
	hi: i64

	now = world_time(world).ms
	n   = world_traces_near(world, at, 0, &here)      /* the spatial index: this tile's alone */
	for i = 0; i < n; i += 1 {
		trace = (^Trace)(world_record(world, world_kind_named(world, "Trace"), here[i]))
		if trace == nil || trace.bearer != 0 || trace.tileX != i64(at.x) || trace.tileY != i64(at.y) ||
		   trace.tileLevel != i64(at.level) || trace.traceKind == nil || trace.expires <= now {
			continue
		}
		v = tri.at(world_tri(world), tri.pattern(world_tri(world), trace.traceKind), "trodden")
		if v == nil || tri.node_interval(v, &lo, &hi) == 0 || lo != hi || lo <= 0 {
			continue
		}
		proposal_group_set_of_to(g, "Trace.expires", whole(here[i]),
		                         now + (trace.expires - now) * (100 - lo) / 100)
	}
	free(here)
}


/* Saying changes nothing in the world either: the "said" event carries the
 * content, and whoever is in earshot perceives it (KNOWLEDGE.md §10). */
@(private = "file")
effect_say :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	if !has_text(a.content) {
		return "say what?"
	}
	proposal_group_emit_subject_other_detail(g, "said", whole(a.roles[.Actor]), whole(a.roles[.Item]), a.content)
	return ""
}


/* An analysis (KNOWLEDGE.md §4): what the actor finds beneath the item's
 * appearance, as the detail of an "analysed" event it perceives: its true
 * material. */
@(private = "file")
effect_analyse :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	body: ^Body
	detail: cstring

	body = (^Body)(world_record(world, world_kind_named(world, "Body"), a.roles[.Item]))
	if body == nil {
		return "there is nothing there to analyse"
	}
	detail = bounded(fmt.tprintf("material: %s", tri.type_name(world_tri(world), tri.Type(body.material))), 128)
	proposal_group_emit_subject_other_detail(g, "analysed", whole(a.roles[.Actor]), whole(a.roles[.Item]),
	                                         world_intern(world, detail))
	return ""
}


/* Writing (the copy operation, KNOWLEDGE.md §15): the command's #Writing,
 * its entries appended to what the record holds, under the author it has. */
@(private = "file")
effect_write :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	entries: [dynamic]string
	added: []string
	old: []string
	author: string
	was: string
	written: cstring
	is_added: bool
	is_old: bool

	if !has_text(a.content) {
		return "write what?"
	}
	author  = ""
	was     = ""
	// writing_entries' ok is false where BGWritingEntries returned nil
	added, is_added = writing_entries(a.content, &author)
	written = world_text_field(world, "Record.writing", a.roles[.Item])
	if has_text(written) {
		old, is_old = writing_entries(written, &was)
	}
	if !is_added || author == "" {
		return "that is not writing"
	}
	entries = make([dynamic]string, context.temp_allocator)
	if is_old {
		append(&entries, ..old)
	}
	append(&entries, ..added)
	proposal_group_set_of_to_text(g, "Record.writing", whole(a.roles[.Item]),
	                              world_intern(world, ns_utf8(fmt.tprintf("#Writing & {{ author: %s, entries: [%s] }",
	                                                                      was if was != "" else author,
	                                                                      strings.join(entries[:], ", ", context.temp_allocator)))))
	proposal_group_emit_subject_other_detail(g, "wrote", whole(a.roles[.Actor]), whole(a.roles[.Item]), a.content)
	return ""
}


/* Reading: an event the reader perceives, carrying what the record holds. */
@(private = "file")
effect_read :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	written: cstring

	written = world_text_field(world, "Record.writing", a.roles[.Item])
	if !has_text(written) {
		return "nothing is written in it"
	}
	proposal_group_emit_subject_other_detail(g, "read", whole(a.roles[.Actor]), whole(a.roles[.Item]), written)
	return ""
}


/* Eating: the food is gone, and the eater nourished by what the food gives
 * (its #Food's nourishment; none, nothing). How the body keeps it is the
 * body's (bodies_nourish). */
@(private = "file")
effect_eat :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	if world_record(world, world_kind_named(world, "Agent"), a.roles[.Actor]) == nil {
		return "only an agent eats"
	}
	food := (^Food)(world_record(world, world_kind_named(world, "Food"), a.roles[.Item]))
	bodies_nourish(world, g, a.roles[.Actor], food.nourishment if food != nil else 0, world_time(world).ms)
	/* of a stack held (a sack of grain), one: the rest is still held */
	if world_units_of(world, a.roles[.Item]) > 1 {
		one := proposal_group_split(g, whole(a.roles[.Item]), 1, world_location_of(world, a.roles[.Item]))
		proposal_group_destroy(g, whole(one), "eaten")
		return ""
	}
	proposal_group_destroy(g, whole(a.roles[.Item]), "eaten")
	return ""
}


/* Foraging a patch (content/foraging/): a handful of what it yields into a
 * free hand, the patch one fewer; stripped of the first of a full patch,
 * it begins to grow one back from now. A bare patch gives nothing. */
@(private = "file")
effect_forage :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	patch := (^Patch)(world_record(world, world_kind_named(world, "Patch"), a.roles[.Item]))
	if patch == nil do return "it is no patch"
	if patch.handfuls < 1 do return "there is nothing on it"
	yields := world_text_field(world, "Patch.yields", a.roles[.Item])
	if yields == nil || len(yields) == 0 do return "it yields nothing"
	hand := free_hand(world, a.roles[.Actor])
	if hand < 0 do return "no hand is free"
	proposal_group_create(g, yields, "a handful", held_by(a.roles[.Actor], hand))
	if patch.handfuls >= patch.most do proposal_group_set_of_to(g, "Patch.grewAt", whole(a.roles[.Item]), world_time(world).ms)
	proposal_group_set_of_to_expecting(g, "Patch.handfuls", whole(a.roles[.Item]), patch.handfuls - 1, patch.handfuls)
	return ""
}


/* Investigating changes nothing: it ends in an event the investigator
 * perceives, a close look. */
@(private = "file")
effect_investigate :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	proposal_group_emit_subject_other(g, "investigated", whole(a.roles[.Actor]), whole(a.roles[.Actor]))
	return ""
}


/* A trace of wear made by an effect: tool marks on what was used. */
@(private = "file")
wear :: proc(world: ^World, g: ^Proposal_Group, on: Entity_ID, strength: i64) {
	t: Entity_ID

	t = proposal_group_create(g, "trace", "tool marks, from use", location_make_none())
	proposal_group_set_of_to_text(g, "Trace.traceKind", whole(t), world_intern(world, "tool_marks"))
	proposal_group_set_of_to(g, "Trace.bearer", whole(t), i64(on))
	proposal_group_set_of_to(g, "Trace.magnitude", whole(t), strength)
	proposal_group_set_of_to(g, "Trace.created", whole(t), world_time(world).ms)
	proposal_group_set_of_to(g, "Trace.expires", whole(t), world_time(world).ms + 365 * 86400000)
}


/* What it costs the actor to bring a lever in reach to bear (ACTIONS.md
 * §2): 0 held, 1 on a tile in reach, 2 in a container (one it carries, or
 * one standing there); -1 if it isn't the actor's to take up: in another's
 * hand, or part of something. */
@(private = "file")
access_cost :: proc(world: ^World, actor: Entity_ID, e: Entity_ID) -> i32 {
	at: Location
	cost: i32
	e := e

	cost = 0
	for depth := 0; depth < 8; depth += 1 {
		at = world_location_of(world, e)
		#partial switch at.form {
		case .Held_By:
			return cost if at.place == actor else -1
		case .On_Tile:
			return cost if cost != 0 else 1
		case .In:
			cost = 2
			e    = at.place
			continue
		case:
			return -1
		}
	}
	return -1
}


/* The valve-turning chain (ACTIONS.md Scenario 1), searched in what the
 * actor can reach (§2), the same way every time to depth 3: the bare hand
 * on the handle (75 mm), a lever, or a lever with a sleeve over its handle.
 * The one that reaches furthest wins; at the same reach, the one cheaper to
 * bring to bear (held, then on a tile, then in a container), then the lower
 * entities. A chain needing more hands than are free isn't one. Returns the
 * reach (0.1 mm); `chain` gets the lever and sleeve (or none), `cost` what
 * each costs to bring to bear. */
@(private = "file")
turning_chain :: proc(world: ^World, actor: Entity_ID, chain: ^[2]Entity_ID, cost: ^[2]i32) -> i64 {
	l: ^Lever
	s: ^Lever
	reach: [256]Entity_ID
	cand: [64]Entity_ID
	ccost: [64]i32
	nreach: uint
	nc: uint
	i: uint
	j: uint
	lk: uint
	hands: i32
	need: i32
	c: i32
	bestCost: i32
	best: i64

	lk     = world_kind_named(world, "Lever")
	nreach = view_reachable(view_of(actor, world), &reach[0], 256)
	if nreach > 256 {
		nreach = 256
	}
	nc = 0
	for i = 0; i < nreach && nc < 64; i += 1 {
		if world_record(world, lk, reach[i]) == nil {
			continue
		}
		c = access_cost(world, actor, reach[i])
		if c < 0 {
			continue
		}
		cand[nc]  = reach[i]
		ccost[nc] = c
		nc += 1
	}
	hands    = free_hands(world, actor)
	best     = 750               /* the bare hand on the handle: 75 mm */
	bestCost = 0
	chain[0] = NO_ENTITY
	chain[1] = NO_ENTITY
	cost[0]  = 0
	cost[1]  = 0
	for i = 0; i < nc; i += 1 {
		l = (^Lever)(world_record(world, lk, cand[i]))
		if l.sleeve {
			continue
		}
		if (1 if ccost[i] != 0 else 0) <= hands &&
		   (l.leverage > best || (l.leverage == best && chain[0] != 0 && ccost[i] < bestCost)) {
			best     = l.leverage
			bestCost = ccost[i]
			chain[0] = cand[i]
			chain[1] = NO_ENTITY
			cost[0]  = ccost[i]
			cost[1]  = 0
		}
		for j = 0; j < nc; j += 1 {
			s = (^Lever)(world_record(world, lk, cand[j]))
			if j == i || !s.sleeve {
				continue
			}
			need = (1 if ccost[i] != 0 else 0) + (1 if ccost[j] != 0 else 0)
			if need > hands {
				continue
			}
			if s.leverage > best || (s.leverage == best && ccost[i] + ccost[j] < bestCost) {
				best     = s.leverage
				bestCost = ccost[i] + ccost[j]
				chain[0] = cand[i]
				chain[1] = cand[j]
				cost[0]  = ccost[i]
				cost[1]  = ccost[j]
			}
		}
	}
	return best
}


/* How fast the actor works now at stage `index` of the operation, in
 * percent of its declared pace (ACTIONS.md §5's rate = f(capabilities,
 * shortfall, actor modifiers)). Provisional, until the document's open
 * question 4 settles f: modifiers only, and only for a stage that takes
 * effort (its `exertion`); fatigue and injury slow it, 200 / (200 +
 * fatigue + injury): half again as long at 100 of them together; and going
 * without, by the pace it has lost (hunger/weakness.tri). Resting, waiting,
 * talking go at their pace. A walk goes at the pace its burden allows
 * (burdened_rate). */
work_rate :: proc(world: ^World, actor: Entity_ID, operation: cstring, index: i64) -> i64 {
	agent: ^Agent
	worn: i64

	agent = (^Agent)(world_record(world, world_kind_named(world, "Agent"), actor))
	if agent != nil && operation_effect_is(world, operation, "walk") do return burdened_rate(world, actor)
	if agent == nil || operation_exertion(world, operation, index) <= 0 {
		return 100
	}
	worn = agent.fatigue + agent.injury
	/* and going without takes its share of what is left (hunger/weakness.tri) */
	return 100 * 200 / (200 + (worn if worn > 0 else 0)) * (100 - weakness(world, actor, .Pace, world_time(world).ms)) / 100
}


/* How fast a walker goes, in percent, under what it carries
 * (content/carrying/'s burden): at full pace up to `light`, half at `light`
 * and `slows` more, a third at twice that. */
burdened_rate :: proc(world: ^World, actor: Entity_ID) -> i64 {
	tc      := world_tri(world)
	burden  := tri.pattern(tc, "burden")
	light   := int_feature(tc, burden, "light", 0)
	slows   := int_feature(tc, burden, "slows", 0)
	over    := carried_mass(world, actor) - light
	if burden == nil || slows <= 0 || over <= 0 do return 100
	return 100 * slows / (slows + over)
}


/* Whether the operation stows (content/actions.tri's `stow`). */
operation_stows :: proc(world: ^World, operation: cstring) -> bool {
	tc := world_tri(world)
	v  := tri.at(tc, tri.pattern(tc, operation), "stow") if operation != nil else nil
	return v != nil && tri.node_type(v) == tri.type_named(tc, "true")
}


/* Where something of `mass` grams an agent takes, or is handed, goes: for
 * an operation that stows, into a pack it carries (its back's first) that
 * has room for it, by count and by load; else a free hand. ok false if
 * neither. */
receiving :: proc(world: ^World, agent: Entity_ID, mass: i64, stows: bool) -> (Location, bool) {
	held:   [8]Entity_ID
	inside: [16]Entity_ID
	if stows {
		n := min(world_entities_at(world, agent, .Held_By, raw_data(held[:]), 8), 8)
		for pass in 0 ..< 2 {
			for e in held[:n] {
				load, capacity: i64
				if (world_location_of(world, e).slot == BG_BACK) != (pass == 0) do continue
				if !world_get_field(world, "Pack.load", e, &load) || !world_get_field(world, "Container.capacity", e, &capacity) do continue
				m := min(world_entities_at(world, e, .In, raw_data(inside[:]), 16), 16)
				bears := mass
				for c in inside[:m] do bears += world_mass_of(world, c)
				if bears <= load && i64(m) < capacity do return in_(e), true
			}
		}
	}
	hand := free_hand(world, agent)
	if hand < 0 do return {}, false
	return held_by(agent, hand), true
}


/* Whether an operation's effect is the one named. */
operation_effect_is :: proc(world: ^World, operation: cstring, effect: string) -> bool {
	e: [32]u8
	tc := world_tri(world)
	v  := tri.at(tc, tri.pattern(tc, operation), "effect")
	if v == nil do return false
	n := tri.print(tc, v, raw_data(e[:]), size_of(e))
	return n == uint(len(effect) + 2) && string(e[1:n - 1]) == effect
}


/* A curve's value at x (AGENCY.md §3's lookup tables, ACTIONS.md decision
 * 11): its points' `output` at their `input`, straight between them and
 * level beyond the ends. NO if it has no points. */
curve_at :: proc(content: ^tri.Content, curve: ^tri.Node, x: i64, out: ^i32) -> bool {
	p: ^tri.Node
	at: [16]i64
	w: [16]i64
	lo: i64
	hi: i64
	n: int
	k: int
	curve := curve

	for n = 0; curve != nil && n < 16 && got(&p, tri.at(content, curve, "first")); curve = tri.at(content, curve, "rest") {
		if tri.node_interval(tri.at(content, p, "input"), &lo, &hi) == 0 || lo != hi {
			continue
		}
		at[n] = lo
		if tri.node_interval(tri.at(content, p, "output"), &lo, &hi) == 0 || lo != hi {
			continue
		}
		w[n] = lo
		n += 1
	}
	if n == 0 {
		return false
	}
	if x <= at[0] {
		out^ = i32(w[0])
		return true
	}
	for k = 1; k < n; k += 1 {
		if x <= at[k] {
			out^ = i32(w[k - 1] + (w[k] - w[k - 1]) * (x - at[k - 1]) / (at[k] - at[k - 1]))
			return true
		}
	}
	out^ = i32(w[n - 1])
	return true
}


/* A role's entity by its site's name ("item"), or none. */
@(private = "file")
role_named :: proc(action: Action, site: string) -> Entity_ID {
	for r in Role.Actor ..< Role.Count {
		if string(ROLE_NAMES[r]) == site {
			return action.roles[r]
		}
	}
	return NO_ENTITY
}


/* A graded requirement (ACTIONS.md decision 11): what the operation's
 * offering role brings, as a percent of what its demanding role demands;
 * -1 if it has none, or either can't be read. */
capacity :: proc(world: ^World, action: Action) -> i64 {
	graded: ^tri.Node
	content: ^tri.Content
	offered: i64
	demanded: i64
	site: [32]u8
	field: [96]u8

	content = world_tri(world)
	graded  = tri.at(content, tri.pattern(content, action.operation), "graded") if action.operation != nil else nil
	if graded == nil || !text_of(content, graded, "offerer", site[:]) ||
	   !text_of(content, graded, "offers", field[:]) ||
	   !world_get_field(world, buf_c(field[:]), role_named(action, buf_s(site[:])), &offered) ||
	   !text_of(content, graded, "demander", site[:]) ||
	   !text_of(content, graded, "demands", field[:]) ||
	   !world_get_field(world, buf_c(field[:]), role_named(action, buf_s(site[:])), &demanded) || demanded <= 0 {
		return -1
	}
	return offered * 100 / demanded
}


/* The work rate, slowed by the graded requirement's `slowing` curve. */
graded_rate :: proc(world: ^World, action: Action, rate: i64) -> i64 {
	capacity_: i64
	slowing: i32

	capacity_ = capacity(world, action)
	if capacity_ < 0 ||
	   !curve_at(world_tri(world), tri.at(world_tri(world), tri.pattern(world_tri(world), action.operation), "graded.slowing"),
	             capacity_, &slowing) || slowing <= 0 {
		return rate
	}
	return rate * 100 / i64(slowing)
}


/* As the effect commits (ACTIONS.md decision 11): a mishap, by the chance
 * the `mishap` curve gives the capacity, a seeded draw, leaving its `slip`;
 * and the result's quality, as the `quality` curve gives it, set on
 * `grades`, a field of the demanding role's entity. */
@(private = "file")
grade :: proc(world: ^World, action: Action, group: ^Proposal_Group) {
	graded: ^tri.Node
	v: ^tri.Node
	content: ^tri.Content
	bearer: Entity_ID
	tile: Location
	capacity_: i64
	lo: i64
	hi: i64
	chance: i32
	quality: i32
	state: u64
	kind: [64]u8
	site: [32]u8
	field: [96]u8

	content   = world_tri(world)
	capacity_ = capacity(world, action)
	graded    = tri.at(content, tri.pattern(content, action.operation), "graded") if capacity_ >= 0 else nil
	if graded == nil {
		return
	}
	if curve_at(content, tri.at(content, graded, "mishap"), capacity_, &chance) && chance > 0 {
		state = mix(world_seed(world) ~ mix(world_boundary(world) * 0x100 + action.roles[.Actor]) ~ 0x6d6973686170)
		if i64(next(&state) % 1000) < i64(chance) &&
		   text_of(content, graded, "slip.trace", kind[:]) && text_of(content, graded, "slip.on", site[:]) &&
		   trace_site(world, action, buf_s(site[:]), &bearer, &tile) {
			v = tri.at(content, graded, "slip.strength")
			make_trace(world, group, buf_c(kind[:]), bearer, tile,
			           lo if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi else 0,
			           action.operation)
			proposal_group_emit_subject_other_detail(group, "mishap", whole(action.roles[.Actor]), whole(bearer), "slip")
		}
	}
	if curve_at(content, tri.at(content, graded, "quality"), capacity_, &quality) &&
	   text_of(content, graded, "grades", field[:]) &&
	   text_of(content, graded, "demander", site[:]) && role_named(action, buf_s(site[:])) != 0 {
		proposal_group_set_of_to(group, buf_c(field[:]), whole(role_named(action, buf_s(site[:]))), i64(quality))
	}
}


/* What weights the actor's groups for the operation when they conflict
 * (ACTIONS.md decision 13): its value of the field the operation declares
 * (`contest`, an Agent field: "quickness"); 0 if it declares none. */
contest_weight :: proc(world: ^World, actor: Entity_ID, operation: cstring) -> u64 {
	pattern: ^tri.Node
	v: ^tri.Node
	field: cstring
	printed: [64]u8
	value: i64
	n: uint

	pattern = tri.pattern(world_tri(world), operation) if operation != nil else nil
	v       = tri.at(world_tri(world), pattern, "contest") if pattern != nil else nil
	n       = tri.print(world_tri(world), v, &printed[0], size_of(printed)) if v != nil else 0
	if n < 3 || printed[0] != '"' {
		return 0
	}
	// The C wrote printed[n - 1] past the buffer when the text was cut; here only within it
	if n - 1 < len(printed) {
		printed[n - 1] = 0
	}
	field = bounded(fmt.tprintf("Agent.%s", cstring(&printed[1])), 96)
	value = 0
	if !world_get_field(world, field, actor, &value) || value <= 0 {
		return 0
	}
	return u64(value)
}


/* What it costs in time to bring the instruments the action will use to
 * bear (ACTIONS.md §2's access cost): take_up's duration for each one
 * on a tile in reach, twice that from a container; added to the first
 * stage. 0 for an action that searches for none. Saying an account takes
 * its duration again for each claim after the first (ACTIONS.md decision
 * 14), added the same way. */
access_delay :: proc(world: ^World, action: Action) -> i64 {
	said: ^tri.Node
	list: ^tri.Node
	arena: ^tri.Arena
	chain: [2]Entity_ID
	cost: [2]i32
	take: i64
	claims: i64
	effect: string

	effect = operation_effect(world, action.operation)
	/* talking takes as long as what is said (ACTIONS.md decision 14): an
	 * account a second more for each claim after the first */
	if effect == "say" && action.content != nil {
		arena  = tri.arena_new()
		said   = tri.value(world_tri(world), action.content, arena, nil, 0)
		claims = 0
		if said != nil && tri.subtype(world_tri(world), tri.node_type(said), tri.type_named(world_tri(world), "#Account")) != 0 {
			for list = tri.at(world_tri(world), said, "entries"); list != nil && tri.at(world_tri(world), list, "first") != nil;
			    list = tri.at(world_tri(world), list, "rest") {
				claims += 1
			}
		}
		tri.arena_free(arena)
		return (claims - 1) * operation_duration(world, action.operation) if claims > 1 else 0
	}
	if effect != "rotate" {
		return 0
	}
	take = operation_duration(world, "take_up")
	turning_chain(world, action.roles[.Actor], &chain, &cost)
	return take * i64(cost[0] + cost[1])
}


/* Turning a valve (ACTIONS.md Scenario 1), with the chain found as above.
 * A part not held is taken up into a free hand in the stage's group, from
 * where it is (if someone else gets it first, the stage fails); the time
 * that takes was added to the stage when it started (BGAccessDelay).
 * Torque is grip times reach, held at the command's amount (Nm) if any.
 * Past the lever's limit there is risk, not refusal: a seeded draw, in
 * proportion to the excess, bends it, giving way before the valve does
 * (the valve feels half its limit). The stage commits the torque applied,
 * with what the turner expected from the valve's rating; the valve
 * decides. Using a lever wears it. */
@(private = "file")
effect_rotate :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	agent: ^Agent
	inner: ^Lever
	valve: ^Valve
	actor: Entity_ID
	held: [8]Entity_ID
	chain: [2]Entity_ID
	lever: Entity_ID
	n: uint
	i: uint
	k: int
	hand: i32
	cost: [2]i32
	best: i64
	applied: i64
	limit: i64
	state: u64
	taken: bool
	detail: strings.Builder

	actor = a.roles[.Actor]
	agent = (^Agent)(world_record(world, world_kind_named(world, "Agent"), actor))
	valve = (^Valve)(world_record(world, world_kind_named(world, "Valve"), a.roles[.Item]))
	if agent == nil || valve == nil {
		return "there is nothing to turn"
	}
	best  = turning_chain(world, actor, &chain, &cost)
	lever = chain[0]
	inner = (^Lever)(world_record(world, world_kind_named(world, "Lever"), lever)) if lever != 0 else nil

	applied = agent.grip * best / 10000
	applied = applied * (100 - weakness(world, actor, .Grip, world_time(world).ms)) / 100   /* going without */
	if amount > 0 && amount * 1000 < applied {
		applied = amount * 1000
	}
	// detail[160], filled by snprintf and strncat: what fits, cut at the end
	detail = strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&detail, "expected to %s: rated %d Nm",
	             "turn" if applied >= valve.rating else "hold", valve.rating / 1000)

	/* what isn't held is taken up, into the free hands in order */
	n    = world_entities_at(world, actor, .Held_By, &held[0], 8)
	hand = 0
	for k = 0; k < 2; k += 1 {
		if chain[k] == 0 || cost[k] == 0 {
			continue
		}
		for ; i64(hand) < agent.hands; hand += 1 {
			taken = false
			for i = 0; i < n && i < 8 && !taken; i += 1 {
				taken = world_location_of(world, held[i]).slot == hand
			}
			if !taken {
				break
			}
		}
		proposal_group_move_to_expecting(g, whole(chain[k]), held_by(actor, hand), world_location_of(world, chain[k]))
		hand += 1
		strings.write_string(&detail, "; takes up one in reach")
	}

	if inner != nil {
		limit = inner.limit
		if applied > limit {
			state = mix(world_seed(world) ~ mix(world_boundary(world) * 0x100 + a.roles[.Item]))
			if i64(next(&state) % u64(applied)) < applied - limit {
				/* it bends: a trace, a clang, and less it bears from now on */
				proposal_group_set_of_to(g, "Body.bent", whole(lever), 1)
				make_trace(world, g, "clang", lever, location_make_none(), 80, "a lever giving")
				proposal_group_set_of_to(g, "Lever.limit", whole(lever), limit / 2)
				wear(world, g, lever, 60)
				applied = limit / 2
				strings.write_string(&detail, "; the lever bends")
			}
		}
		wear(world, g, lever, 10)
	}
	proposal_group_emit_subject_other_amount(g, "torqued", whole(a.roles[.Item]), whole(actor), applied,
	                                         world_intern(world, bounded(strings.to_string(detail), 160)))
	return ""
}


/* A blow with a stone: the valve feels it, and loosens. */
@(private = "file")
effect_strike :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	proposal_group_emit_subject_other_amount(g, "struck", whole(a.roles[.Destination]), whole(a.roles[.Actor]), 30000,
	                                         nil)
	return ""
}


/* Copying (COMPONENTS.md §8): a new copy, set down on the copier's tile, in
 * its hand, pressed with the seal it holds, if any. Copied as it is, it
 * references the same content. In other words (the command's), it is new
 * content, `derivedFrom` the original and claiming its issuer still; its
 * actual origin is this group's creation, the copier's. */
@(private = "file")
effect_copy :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	source: ^Inscription
	scribe: ^Scribe
	stamps: ^Store
	seal: Entity_ID
	at: Location
	content: Entity_ID
	copy_: Entity_ID
	i: uint
	reads: cstring
	issuer: cstring
	presses: cstring

	source = (^Inscription)(world_record(world, world_kind_named(world, "Inscription"), a.roles[.Item]))
	if source == nil || source.inscribed == 0 {
		return "there is nothing written there to copy"
	}
	content = Entity_ID(source.inscribed)
	reads   = world_text_field(world, "Information.text", content)
	issuer  = world_text_field(world, "Information.issuer", content)
	scribe  = (^Scribe)(world_record(world, world_kind_named(world, "Scribe"), a.roles[.Actor]))
	presses = ""
	seal    = NO_ENTITY
	stamps  = world_store_for_kind(world, world_kind_named(world, "Stamp"))
	for i = 0; i < store_count(stamps) && seal == 0; i += 1 {
		at = world_location_of(world, store_entity_at_index(stamps, i))
		if at.form == .Held_By && at.place == a.roles[.Actor] {
			seal    = store_entity_at_index(stamps, i)
			presses = world_text_field(world, "Stamp.presses", seal)
		}
	}
	if has_text(a.content) && (reads == nil || string(a.content) != string(reads)) {
		/* altered: new content, derived from the original */
		content = proposal_group_create(g, "content", "altered content", location_make_none())
		proposal_group_set_of_to_text(g, "Information.text", whole(content), a.content)
		proposal_group_set_of_to_text(g, "Information.issuer", whole(content), issuer if issuer != nil else "")
		proposal_group_relate(g, .Derived_From, whole(content), whole(Entity_ID(source.inscribed)))
		reads = a.content
	}
	at    = world_location_of(world, a.roles[.Actor])
	copy_ = proposal_group_create(g, "paper_copy", "a copy", at if at.form == .On_Tile else location_make_none())
	proposal_group_set_of_to(g, "Inscription.inscribed", whole(copy_), i64(content))
	proposal_group_set_of_to_text(g, "Inscription.reads", whole(copy_), reads if reads != nil else "")
	proposal_group_set_of_to_text(g, "Inscription.claims", whole(copy_), issuer if issuer != nil else "")
	proposal_group_set_of_to_text(g, "Inscription.penned", whole(copy_),
	                              world_text_field(world, "Scribe.handwriting", a.roles[.Actor]) if scribe != nil && world_text_field(world, "Scribe.handwriting", a.roles[.Actor]) != nil else "an unknown hand")
	proposal_group_set_of_to_text(g, "Inscription.impression", whole(copy_), presses if presses != nil else "")
	/* the seal pressed it: provenance, for whoever investigates */
	if seal != 0 {
		proposal_group_emit_subject_other(g, "stamped", whole(seal), whole(copy_))
	}
	return ""
}


/* A text feature of a node, unquoted, into buf; NO if it hasn't one. */
@(private = "file")
text_feature :: proc(content: ^tri.Content, node: ^tri.Node, path: cstring, buf: []u8) -> bool {
	at: ^tri.Node
	n: uint

	at = tri.at(content, node, path) if node != nil else nil
	n  = tri.print(content, at, &buf[0], uint(len(buf))) if at != nil else 0
	if n < 2 || n >= uint(len(buf)) || buf[0] != '"' {
		return false
	}
	copy(buf[:n - 2], buf[1:n - 1])
	buf[n - 2] = 0
	return true
}


/* Latent wear (LATENT_ASSEMBLY.md decisions 4-6,
 * content/machines/latent.tri): the assembly's use shared out among its roles
 * by how fast each wears, how hard abuse strains it, and its hidden
 * quality. */
@(private = "file")
BG_WEARS :: 2                       /* a role's points in 100 h of use, unless it says */
@(private = "file")
BG_PART_FAILED :: 60                /* the wear a failure leaves its culprit at, at least */
@(private = "file")
BG_WEAR_SPAN :: 100 * 3600000       /* the 100 h `wears` and `chance` are per */


/* The schema's entry for `role` among its parts, or nil. */
@(private = "file")
latent_role :: proc(content: ^tri.Content, schema: ^tri.Node, role: cstring) -> ^tri.Node {
	list: ^tri.Node
	entry: ^tri.Node
	name: [64]u8

	for list = tri.at(content, schema, "parts"); list != nil && got(&entry, tri.at(content, list, "first")); list = tri.at(content, list, "rest") {
		if text_feature(content, entry, "roleName", name[:]) && buf_s(name[:]) == string(role) {
			return entry
		}
	}
	return nil
}


@(private = "file")
int_feature :: proc(content: ^tri.Content, node: ^tri.Node, path: cstring, otherwise: i64) -> i64 {
	lo: i64
	hi: i64

	return lo if node != nil && tri.node_interval(tri.at(content, node, path), &lo, &hi) != 0 && lo == hi else otherwise
}


/* A role's hidden quality, 0 to 100: 50, give or take 20 by the unit's seed,
 * and the schema's bias for its kind of part. A candidate that is no part
 * (the housing) has a quality all the same. */
@(private = "file")
latent_quality :: proc(content: ^tri.Content, schema: ^tri.Node, seed: u64, role: cstring) -> i64 {
	entry: ^tri.Node
	list: ^tri.Node
	bias: ^tri.Node
	kind: [64]u8
	text: [64]u8
	q: i64

	q     = 30 + i64(mix_string(mix(seed ~ 0x7175616c697479), role) % 41)
	entry = latent_role(content, schema, role)
	if entry != nil && text_feature(content, entry, "partKind", kind[:]) {
		for list = tri.at(content, schema, "biases"); list != nil && got(&bias, tri.at(content, list, "first")); list = tri.at(content, list, "rest") {
			if text_feature(content, bias, "biased", text[:]) && buf_s(text[:]) == buf_s(kind[:]) {
				q += int_feature(content, bias, "bias", 0)
			}
		}
	}
	return 0 if q < 0 else 100 if q > 100 else q
}


/* How fast a role wears, in hundredths of a point per 100 h of use: what it
 * `wears`, by the quality of what fills it (half again as fast at 0, half
 * as fast at 100). */
@(private = "file")
role_rate :: proc(content: ^tri.Content, schema: ^tri.Node, role: cstring, quality: i64) -> i64 {
	return int_feature(content, latent_role(content, schema, role), "wears", BG_WEARS) * (150 - quality)
}


/* What `used` ms of use, `abused` of them abused (the role wears `strain`
 * times as fast then), wear what fills a role, in ten-thousandths of a
 * point. */
@(private = "file")
role_attrition :: proc(content: ^tri.Content, schema: ^tri.Node, role: cstring, quality: i64,
                       used: i64, abused: i64) -> i64 {
	strain: i64

	strain = int_feature(content, latent_role(content, schema, role), "strain", 1)
	return role_rate(content, schema, role, quality) * 100 * (used + abused * (strain - 1)) / BG_WEAR_SPAN
}


/* A role's wear unopened, in hundredths of a point: by the assembly's
 * history and the role's hidden quality. */
@(private = "file")
latent_wear :: proc(content: ^tri.Content, schema: ^tri.Node, seed: u64, role: cstring,
                    used: i64, abused: i64) -> i64 {
	return role_attrition(content, schema, role, latent_quality(content, schema, seed, role), used, abused) / 100
}


/* A part's quality: what it was made with, revealed from its assembly;
 * else 50, give or take 20, by its own seed. */
@(private = "file")
part_quality :: proc(world: ^World, part: Entity_ID, p: ^Part) -> i64 {
	return p.grade if p.grade >= 0 else 30 + i64(mix(world_info(world, part).seed ~ 0x7175616c697479) % 41)
}


/* How worn a part is, in ten-thousandths of a point: its attrition, or its
 * wear if that says more (a part content made worn). */
@(private = "file")
part_attrition :: proc(p: ^Part) -> i64 {
	return p.attrition if p.attrition > p.wear * 10000 else p.wear * 10000
}


/* The part in an assembly's role, or none. */
@(private = "file")
latent_part :: proc(world: ^World, assembly: Entity_ID, role: cstring) -> Entity_ID {
	in_: [64]Entity_ID
	n: uint
	i: uint

	n = world_entities_at(world, assembly, .Part_Of, &in_[0], 64)
	// The C read past in[64] when more than 64 were part of it; here only within it
	for i = 0; i < n && i < 64; i += 1 {
		at := world_location_of(world, in_[i])
		if location_role(&at) == string(role) {
			return in_[i]
		}
	}
	return NO_ENTITY
}


/* A role's wear, in hundredths of a point, after `d` ms more use, `dry` of
 * them abused; and how fast it wears (decision 7). Opened, it is the part's
 * in it, by that part's quality; an opened role empty has none. Unopened,
 * or no part (the housing), it is the role's, by the assembly's history. */
@(private = "file")
latent_condition :: proc(world: ^World, assembly: Entity_ID, latent: ^Latent, schema: ^tri.Node,
                         role: cstring, d: i64, dry: i64, rate: ^i64) -> i64 {
	entry: ^tri.Node
	p: ^Part
	content: ^tri.Content
	part: Entity_ID
	seed: u64
	q: i64

	content = world_tri(world)
	seed    = world_info(world, assembly).seed
	entry   = latent_role(content, schema, role)
	if entry != nil && int_feature(content, entry, "depth", 1) <= latent.revealed {
		part = latent_part(world, assembly, role)
		p    = (^Part)(world_record(world, world_kind_named(world, "Part"), part)) if part != 0 else nil
		if p == nil {
			rate^ = 0
			return 0
		}
		q     = part_quality(world, part, p)
		rate^ = role_rate(content, schema, role, q)
		return (part_attrition(p) + role_attrition(content, schema, role, q, d, dry)) / 100
	}
	rate^ = role_rate(content, schema, role, latent_quality(content, schema, seed, role))
	return latent_wear(content, schema, seed, role, latent.used + d, latent.abused + dry)
}


/* The culprit of `failure` among its candidates, after `d` ms more use,
 * `dry` of them abused: drawn by the seed, each weighted by its wear, as if
 * a hundred hours more worn, so that a unit new to use is weighted by how
 * fast each wears. "" if it has no candidates. */
@(private = "file")
latent_culprit :: proc(world: ^World, assembly: Entity_ID, latent: ^Latent, schema: ^tri.Node,
                       failure: cstring, d: i64, dry: i64, culprit: []u8) {
	list: ^tri.Node
	entry: ^tri.Node
	cands: ^tri.Node
	content: ^tri.Content
	text: [64]u8
	role: [64]u8
	total: i64
	rate: i64
	k: i64
	condition: i64

	content    = world_tri(world)
	culprit[0] = 0
	for list = tri.at(content, schema, "culprits"); list != nil && got(&entry, tri.at(content, list, "first")); list = tri.at(content, list, "rest") {
		if !text_feature(content, entry, "failing", text[:]) || buf_s(text[:]) != string(failure) {
			continue
		}
		total = 0
		for cands = tri.at(content, entry, "candidates"); cands != nil && text_feature(content, cands, "first", role[:]);
		    cands = tri.at(content, cands, "rest") {
			// the call, then its rate (as clang sequences the C's `latent_condition( ..., &rate) + rate`)
			condition = latent_condition(world, assembly, latent, schema, buf_c(role[:]), d, dry, &rate)
			total += condition + rate
		}
		if total <= 0 {
			return
		}
		k = i64(mix_string(mix(world_info(world, assembly).seed ~ 0x63756c70726974), failure) % u64(total))
		for cands = tri.at(content, entry, "candidates"); cands != nil && text_feature(content, cands, "first", role[:]);
		    cands = tri.at(content, cands, "rest") {
			condition = latent_condition(world, assembly, latent, schema, buf_c(role[:]), d, dry, &rate)
			k -= condition + rate
			if k < 0 {
				set_text(culprit, buf_s(role[:]))
				return
			}
		}
		return
	}
}


/* An assembly's use, `d` ms, `dry` of them abused, passed on to the parts
 * in it: each wears as its role does, by its own quality; one that is
 * itself an assembly is used as long, and so on in. The part blamed for a
 * failure now is worn at least as a failure leaves it; one that is an
 * assembly takes the failure on. */
@(private = "file")
latent_use :: proc(world: ^World, g: ^Proposal_Group, assembly: Entity_ID, d: i64, dry: i64,
                   blamed: cstring, failure: cstring, depth: i32) {
	latent: ^Latent
	inner: ^Latent
	p: ^Part
	info: ^Entity_Info
	schema: ^tri.Node
	content: ^tri.Content
	in_: [64]Entity_ID
	at: Location
	n: uint
	i: uint
	worn: i64
	culprit: bool

	content = world_tri(world)
	latent  = (^Latent)(world_record(world, world_kind_named(world, "Latent"), assembly))
	info    = world_info(world, assembly)
	schema  = tri.at(content, tri.pattern(content, info.blueprint), "latent") if latent != nil && info != nil else nil
	if schema == nil || depth > 8 {
		return
	}
	n = world_entities_at(world, assembly, .Part_Of, &in_[0], 64)
	// The C read past in[64] when more than 64 were part of it; here only within it
	for i = 0; i < n && i < 64; i += 1 {
		p = (^Part)(world_record(world, world_kind_named(world, "Part"), in_[i]))
		if p == nil {
			continue
		}
		at      = world_location_of(world, in_[i])
		culprit = blamed != nil && location_role(&at) == string(blamed)
		inner   = (^Latent)(world_record(world, world_kind_named(world, "Latent"), in_[i]))
		if inner != nil {
			proposal_group_set_of_to(g, "Latent.used", whole(in_[i]), inner.used + d)
			proposal_group_set_of_to(g, "Latent.abused", whole(in_[i]), inner.abused + dry)
			if culprit {
				proposal_group_set_of_to_text(g, "Latent.failure", whole(in_[i]), world_intern(world, failure))
				proposal_group_set_of_to(g, "Latent.failedAt", whole(in_[i]), world_time(world).ms)
			}
			latent_use(world, g, in_[i], d, dry, nil, nil, depth + 1)
			continue
		}
		worn = part_attrition(p) + role_attrition(content, schema, location_role_c(&at), part_quality(world, in_[i], p), d, dry)
		if culprit && worn < BG_PART_FAILED * 10000 {
			worn = BG_PART_FAILED * 10000
		}
		worn = 1000000 if worn > 1000000 else worn
		proposal_group_set_of_to(g, "Part.attrition", whole(in_[i]), worn)
		proposal_group_set_of_to(g, "Part.wear", whole(in_[i]), worn / 10000)
	}
}


/* Working a pump an hour (content/machines/pump.tri): it lifts water from
 * the store it draws from into its riser, at its flow; what it can't draw,
 * the store dry, it is worked dry, abused. The use risks each failure the
 * schema names: its chance, by the wear of its most worn candidate, drawn by
 * the seed and the use so far. Failed, its culprit is decided then, and a
 * flow loss costs it the flow its culprit's loss does. The parts opened in it
 * wear on. Seized, it can't be worked. */
@(private = "file")
effect_work :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	latent: ^Latent
	pump: ^Pump
	info: ^Entity_Info
	schema: ^tri.Node
	list: ^tri.Node
	entry: ^tri.Node
	cands: ^tri.Node
	content: ^tri.Content
	e: Entity_ID
	d: i64
	want: i64
	have: i64
	room: i64
	level: i64
	got_: i64
	dry: i64
	worst: i64
	w: i64
	rate: i64
	ppm: i64
	cap_: i64
	store: bool
	failed: bool
	failing: [64]u8
	role: [64]u8
	culprit: [64]u8

	content = world_tri(world)
	e       = a.roles[.Item]
	latent  = (^Latent)(world_record(world, world_kind_named(world, "Latent"), e))
	pump    = (^Pump)(world_record(world, world_kind_named(world, "Pump"), e))
	info    = world_info(world, e)
	schema  = tri.at(content, tri.pattern(content, info.blueprint), "latent") if latent != nil && pump != nil && info != nil else nil
	if schema == nil {
		return "there is no pump to work"
	}
	if latent.failure != nil && string(latent.failure) == "seized" {
		return "it is seized"
	}
	d = operation_duration(world, a.operation)

	/* the water: what its flow would lift, what the source has, what the riser takes */
	dry  = 0
	want = pump.lift * pump.flow / 100 * d / 60000
	if want > 0 && pump.draws != 0 {
		have  = 0
		level = 0
		world_get_field(world, "WaterStore.water", Entity_ID(pump.draws), &have)
		room  = want
		store = latent.riser != 0 && world_get_field(world, "WaterStore.water", Entity_ID(latent.riser), &level) &&
		        world_get_field(world, "WaterStore.waterCapacity", Entity_ID(latent.riser), &cap_)
		if store {
			room = cap_ - level
		}
		got_ = want if want < have else have
		got_ = got_ if got_ < room else room
		got_ = 0 if got_ < 0 else got_
		dry  = d * (want - have) / want if have < want else 0
		if got_ != 0 {
			proposal_group_set_of_to(g, "WaterStore.water", whole(Entity_ID(pump.draws)), have - got_)
			if store {
				proposal_group_set_of_to(g, "WaterStore.water", whole(Entity_ID(latent.riser)), level + got_)
			}
		}
	}
	proposal_group_set_of_to(g, "Latent.used", whole(e), latent.used + d)
	proposal_group_set_of_to(g, "Latent.abused", whole(e), latent.abused + dry)

	/* the risk: each failure in turn, while none has happened */
	failed     = false
	culprit[0] = 0
	if !has_text(latent.failure) {
		for list = tri.at(content, schema, "culprits"); !failed && list != nil && got(&entry, tri.at(content, list, "first"));
		    list = tri.at(content, list, "rest") {
			if !text_feature(content, entry, "failing", failing[:]) {
				continue
			}
			worst = 0
			for cands = tri.at(content, entry, "candidates"); cands != nil && text_feature(content, cands, "first", role[:]);
			    cands = tri.at(content, cands, "rest") {
				if latent_role(content, schema, buf_c(role[:])) != nil {
					w = latent_condition(world, e, latent, schema, buf_c(role[:]), 0, 0, &rate) / 100
					if w > worst {
						worst = 100 if w > 100 else w
					}
				}
			}
			/* in a million, for this use: chance/1000 per 100 h, ×(1 + 3 wear/100) */
			ppm = int_feature(content, entry, "chance", 0) * 10 * (100 + 3 * worst) * d / BG_WEAR_SPAN
			failed = i64(mix_string(mix(info.seed ~ u64(latent.used) ~ 0x6661696c), buf_c(failing[:])) % 1000000) < ppm
			if failed {
				latent_culprit(world, e, latent, schema, buf_c(failing[:]), d, dry, culprit[:])
			}
		}
	}

	/* the parts opened in it wear on; the culprit among them, as a failure leaves it */
	latent_use(world, g, e, d, dry, buf_c(culprit[:]) if failed else nil, buf_c(failing[:]) if failed else nil, 0)
	if failed {
		proposal_group_set_of_to_text(g, "Latent.failure", whole(e), world_intern(world, buf_c(failing[:])))
		proposal_group_set_of_to(g, "Latent.failedAt", whole(e), world_time(world).ms)
		proposal_group_set_of_to_text(g, "Latent.blamed", whole(e), world_intern(world, buf_c(culprit[:])))
		if buf_s(failing[:]) == "flow_loss" && latent_role(content, schema, buf_c(culprit[:])) != nil {
			proposal_group_set_of_to(g, "Pump.flow", whole(e), pump.flow - 80 if pump.flow > 80 else 0)
		}
		proposal_group_emit_subject_other(g, "failed", whole(e), whole(a.roles[.Actor]))
	}
	return ""
}


/* Opening a latent assembly a level further (content/machines/latent.tri): the
 * level's parts become entities, part of it, their mass carved out of its
 * own; each one worn by the assembly's use. The culprit of a failure
 * committed against it, decided at the failure or else now, is worn at least
 * as a failure leaves it; one that is itself an assembly takes the failure
 * on instead, and its use. */
@(private = "file")
effect_reveal :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	latent: ^Latent
	info: ^Entity_Info
	schema: ^tri.Node
	list: ^tri.Node
	entry: ^tri.Node
	content: ^tri.Content
	assembly: Entity_ID
	part: Entity_ID
	seed: u64
	depth: i64
	lo: i64
	hi: i64
	mass: i64
	carved: i64
	worn: i64
	quality: i64
	failure: cstring
	culprit: [64]u8
	role: [64]u8
	kind: [64]u8
	any_: bool

	content  = world_tri(world)
	assembly = a.roles[.Destination]
	latent   = (^Latent)(world_record(world, world_kind_named(world, "Latent"), assembly))
	info     = world_info(world, assembly)
	schema   = tri.at(content, tri.pattern(content, info.blueprint), "latent") if latent != nil && info != nil else nil
	if schema == nil {
		return "there is nothing inside to open"
	}
	seed  = info.seed
	depth = latent.revealed + 1

	/* the culprit: decided at the failure, or, a failure a scenario set, now
	 * and for good */
	culprit[0] = 0
	failure    = world_text_field(world, "Latent.failure", assembly)
	if has_text(failure) {
		if has_text(latent.blamed) {
			set_text(culprit[:], string(latent.blamed))
		} else {
			latent_culprit(world, assembly, latent, schema, failure, 0, 0, culprit[:])
			proposal_group_set_of_to_text(g, "Latent.blamed", whole(assembly), world_intern(world, buf_c(culprit[:])))
		}
	}

	/* the level's parts */
	any_   = false
	carved = 0
	for list = tri.at(content, schema, "parts"); list != nil && got(&entry, tri.at(content, list, "first")); list = tri.at(content, list, "rest") {
		if tri.node_interval(tri.at(content, entry, "depth"), &lo, &hi) == 0 || lo != depth ||
		   !text_feature(content, entry, "roleName", role[:]) ||
		   !text_feature(content, entry, "partKind", kind[:]) {
			continue
		}
		any_ = true
		mass = lo if tri.node_interval(tri.at(content, tri.pattern(content, buf_c(kind[:])), "mass"), &lo, &hi) != 0 && lo == hi else 0
		part = proposal_group_create(g, world_intern(world, buf_c(kind[:])), world_intern(world, buf_c(role[:])),
		                             part_of(assembly, string(world_intern(world, buf_c(role[:]))), 0))
		quality = latent_quality(content, schema, seed, buf_c(role[:]))
		worn    = role_attrition(content, schema, buf_c(role[:]), quality, latent.used, latent.abused)
		if buf_s(role[:]) == buf_s(culprit[:]) && worn < BG_PART_FAILED * 10000 {
			worn = BG_PART_FAILED * 10000
		}
		/* an assembly within: worn by its own parts, as long used; the
		 * culprit, it takes the failure on */
		if tri.at(content, tri.pattern(content, buf_c(kind[:])), "latent") != nil {
			worn = 0
			proposal_group_set_of_to(g, "Latent.used", whole(part), latent.used)
			proposal_group_set_of_to(g, "Latent.abused", whole(part), latent.abused)
			if buf_s(role[:]) == buf_s(culprit[:]) {
				proposal_group_set_of_to_text(g, "Latent.failure", whole(part), failure)
				proposal_group_set_of_to(g, "Latent.failedAt", whole(part), latent.failedAt)
			}
		}
		worn = 1000000 if worn > 1000000 else worn
		proposal_group_set_of_to(g, "Part.attrition", whole(part), worn)
		proposal_group_set_of_to(g, "Part.wear", whole(part), worn / 10000)
		proposal_group_set_of_to(g, "Part.grade", whole(part), quality)
		proposal_group_set_of_to(g, "Part.cameFrom", whole(part), i64(assembly))
		proposal_group_set_of_to_text(g, "Part.fits", whole(part), world_intern(world, buf_c(role[:])))
		proposal_group_emit_subject_other(g, "revealed", whole(part), whole(assembly))
		carved += mass
	}
	if !any_ {
		return "there is nothing further to open"
	}
	proposal_group_set_of_to(g, "Body.mass", whole(assembly),
	                         mass - carved if world_get_field(world, "Body.mass", assembly, &mass) else 0)
	proposal_group_set_of_to(g, "Latent.revealed", whole(assembly), depth)
	return ""
}


/* Replacing a part (provisional, content/machines/latent.tri): the worn one
 * out onto the actor's tile, the spare into its place; a part worn by the
 * assembly's failure, replaced, repairs it. */
@(private = "file")
effect_replace :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	worn: ^Part
	place: Location
	floor: Location
	e: Entity_ID
	k: int

	worn  = (^Part)(world_record(world, world_kind_named(world, "Part"), a.roles[.Destination]))
	place = world_location_of(world, a.roles[.Destination])
	if worn == nil || place.form != .Part_Of {
		return "there is no part in place to replace"
	}
	e = a.roles[.Actor]
	for k = 0; k < 16; k += 1 {
		floor = world_location_of(world, e)
		if floor.form == .On_Tile do break
		e = floor.place
	}
	if floor.form != .On_Tile {
		return "there is nowhere to put the old part"
	}
	proposal_group_move_to(g, whole(a.roles[.Destination]), floor)
	proposal_group_move_to(g, whole(a.roles[.Item]), place)
	proposal_group_set_of_to(g, "Part.cameFrom", whole(a.roles[.Item]), i64(place.place))
	if worn.wear >= 60 && world_record(world, world_kind_named(world, "Latent"), place.place) != nil {
		proposal_group_set_of_to_text(g, "Latent.failure", whole(place.place), "")
		proposal_group_set_of_to_text(g, "Latent.blamed", whole(place.place), "")
	}
	/* the pump's flow, by the delta: the old part's loss off, the new one's
	 * on (COMPONENTS.md §7) */
	{
		spare: ^Part
		pump: Entity_ID
		flow: i64
		delta: i64
		n: int

		spare = (^Part)(world_record(world, world_kind_named(world, "Part"), a.roles[.Item]))
		delta = (80 if worn.wear >= 60 else 0) - (80 if spare != nil && spare.wear >= 60 else 0)
		for pump, n = place.place, 0; pump != 0 && n < 8 && world_record(world, world_kind_named(world, "Pump"), pump) == nil; n += 1 {
			p: ^Part
			in_: Location

			in_  = world_location_of(world, pump)
			p    = (^Part)(world_record(world, world_kind_named(world, "Part"), pump))
			pump = in_.place if in_.form == .Part_Of else Entity_ID(p.cameFrom) if p != nil else NO_ENTITY
		}
		if pump != 0 && delta != 0 && world_get_field(world, "Pump.flow", pump, &flow) {
			proposal_group_set_of_to(g, "Pump.flow", whole(pump),
			                         100 if flow + delta > 100 else 0 if flow + delta < 0 else flow + delta)
		}
	}
	return ""
}


/* Cutting a strip from a hide (COMPONENTS.md Scenario 3): an individual
 * divided; the strip, a new entity on the floor, carved from it, with a
 * splitFrom edge. */
@(private = "file")
effect_cut :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	floor: Location
	e: Entity_ID
	strip: Entity_ID
	lo: i64
	hi: i64
	mass: i64
	cut: i64
	k: int

	cut = lo if tri.node_interval(tri.at(world_tri(world), tri.pattern(world_tri(world), "leather_strip"), "mass"), &lo, &hi) != 0 && lo == hi else 0
	if !world_get_field(world, "Body.mass", a.roles[.Item], &mass) || mass <= cut {
		return "there is not enough of it to cut a strip"
	}
	e = a.roles[.Actor]
	for k = 0; k < 16; k += 1 {
		floor = world_location_of(world, e)
		if floor.form == .On_Tile do break
		e = floor.place
	}
	strip = proposal_group_create(g, "leather_strip", "a strip", floor)
	proposal_group_relate(g, .Split_From, whole(strip), whole(a.roles[.Item]))
	proposal_group_set_of_to(g, "Body.mass", whole(a.roles[.Item]), mass - cut)
	return ""
}


/* Issuing a permit (ACTIONS.md §2, an office holder's capability): the
 * place from the command's description; the content, the office's
 * authorization linked to it, and a sealed copy in the grantee's hand. */
@(private = "file")
effect_issue :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	holder: ^Office_Holder
	place: ^tri.Node
	arena: ^tri.Arena
	store: ^Store
	at: Location
	office: Entity_ID
	where_: Entity_ID
	content: Entity_ID
	auth: Entity_ID
	copy_: Entity_ID
	i: uint
	x: i64
	y: i64
	level: i64
	hi: i64
	hand: i32
	issuer: cstring
	presses: cstring
	text: cstring

	holder = (^Office_Holder)(world_record(world, world_kind_named(world, "OfficeHolder"), a.roles[.Actor]))
	office = Entity_ID(holder.office) if holder != nil else NO_ENTITY
	if office == 0 || world_record(world, world_kind_named(world, "Organization"), office) == nil {
		return "it holds no office that issues permits"
	}
	if !has_text(a.content) {
		return "a permit for where?"
	}
	arena  = tri.arena_new()
	place  = tri.value(world_tri(world), a.content, arena, nil, 0)
	where_ = NO_ENTITY
	if place != nil && tri.node_interval(tri.at(world_tri(world), place, "place.x"), &x, &hi) != 0 &&
	   tri.node_interval(tri.at(world_tri(world), place, "place.y"), &y, &hi) != 0 &&
	   tri.node_interval(tri.at(world_tri(world), place, "place.level"), &level, &hi) != 0 {
		store = world_store_for_kind(world, world_kind_named(world, "Container"))
		for i = 0; i < store_count(store) && where_ == 0; i += 1 {
			at = world_location_of(world, store_entity_at_index(store, i))
			if at.form == .On_Tile && i64(at.x) == x && i64(at.y) == y && i64(at.level) == level {
				where_ = store_entity_at_index(store, i)
			}
		}
	}
	tri.arena_free(arena)
	if where_ == 0 {
		return "there is no such place"
	}
	hand = free_hand(world, a.roles[.Item])
	if hand < 0 {
		return "they have no hand free to take it"
	}
	issuer  = world_text_field(world, "Organization.orgName", office)
	presses = ""
	store   = world_store_for_kind(world, world_kind_named(world, "Stamp"))
	for i = 0; i < store_count(store); i += 1 {
		at = world_location_of(world, store_entity_at_index(store, i))
		if at.form == .Held_By && at.place == a.roles[.Actor] {
			presses = world_text_field(world, "Stamp.presses", store_entity_at_index(store, i))
		}
	}
	text    = bounded(fmt.tprintf("the bearer may enter the place at (%d, %d)", x, y), 256)
	content = proposal_group_create(g, "content", "an issued permit", location_make_none())
	proposal_group_set_of_to_text(g, "Information.text", whole(content), world_intern(world, text))
	proposal_group_set_of_to_text(g, "Information.issuer", whole(content), issuer if issuer != nil else "")
	auth = proposal_group_create(g, "authorization", "an issued authorization", location_make_none())
	proposal_group_set_of_to_text(g, "Authorization.grants", whole(auth), "enter")
	proposal_group_set_of_to(g, "Authorization.over", whole(auth), i64(where_))
	proposal_group_set_of_to(g, "Authorization.grantee", whole(auth), i64(a.roles[.Item]))
	proposal_group_relate(g, .Authorizes, whole(auth), whole(content))
	copy_ = proposal_group_create(g, "paper_copy", "the issued copy", held_by(a.roles[.Item], hand))
	proposal_group_set_of_to(g, "Inscription.inscribed", whole(copy_), i64(content))
	proposal_group_set_of_to_text(g, "Inscription.reads", whole(copy_), world_intern(world, text))
	proposal_group_set_of_to_text(g, "Inscription.claims", whole(copy_), issuer if issuer != nil else "")
	proposal_group_set_of_to_text(g, "Inscription.penned", whole(copy_),
	                              world_text_field(world, "Scribe.handwriting", a.roles[.Actor]) if world_text_field(world, "Scribe.handwriting", a.roles[.Actor]) != nil else "an unknown hand")
	proposal_group_set_of_to_text(g, "Inscription.impression", whole(copy_), presses if presses != nil else "")
	proposal_group_emit_subject_other(g, "issued", whole(a.roles[.Actor]), whole(a.roles[.Item]))
	return ""
}


/* Shaping a strip into a seal: it fits a seal's role. */
@(private = "file")
effect_shape :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	proposal_group_set_of_to_text(g, "Part.fits", whole(a.roles[.Item]), "seal")
	return ""
}


/* Servicing a part in place (LATENT_ASSEMBLY.md decision 8): it undoes its
 * role's `mends` per cent of the wear since the part was last serviced
 * (`tended`; since it was made, if never), and that is where it was last
 * serviced now. Quality is untouched: a poor part, serviced, wears as fast
 * again. Worn through, it is past servicing. */
@(private = "file")
effect_service :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	p: ^Part
	info: ^Entity_Info
	schema: ^tri.Node
	content: ^tri.Content
	part: Entity_ID
	place: Location
	worn: i64
	since: i64
	mends: i64

	content = world_tri(world)
	part    = a.roles[.Item]
	p       = (^Part)(world_record(world, world_kind_named(world, "Part"), part))
	place   = world_location_of(world, part)
	info    = world_info(world, place.place) if place.form == .Part_Of else nil
	schema  = tri.at(content, tri.pattern(content, info.blueprint), "latent") if info != nil && world_record(world, world_kind_named(world, "Latent"), place.place) != nil else nil
	if p == nil || schema == nil {
		return "there is no part in place to service"
	}
	if world_record(world, world_kind_named(world, "Latent"), part) != nil {
		return "it has parts of its own to service"
	}
	worn = part_attrition(p)
	if worn >= BG_PART_FAILED * 10000 {
		return "it is worn through, past servicing: it has to be replaced"
	}
	mends = int_feature(content, latent_role(content, schema, location_role_c(&place)), "mends", 0)
	if mends <= 0 {
		return "servicing won't help it"
	}
	since = worn - p.tended if worn > p.tended else 0
	worn -= since * mends / 100
	proposal_group_set_of_to(g, "Part.attrition", whole(part), worn)
	proposal_group_set_of_to(g, "Part.wear", whole(part), worn / 10000)
	proposal_group_set_of_to(g, "Part.tended", whole(part), worn)
	proposal_group_emit_subject_other(g, "serviced", whole(part), whole(a.roles[.Actor]))
	return ""
}


/* The claims covering an entity (COMPONENTS.md Scenario 3): on it; on an
 * assembly it is part of, or came out of, for kinds that cover parts
 * (content's `coverage`); and on what it was divided from. */
/* Whether claims of this kind cover what is part of what they claim. */
@(private = "file")
covers_parts :: proc(world: ^World, claim: ^Claim) -> bool {
	c: ^tri.Node
	family: ^tri.Index
	i: uint
	kind: [64]u8
	name: cstring

	family = tri.family_index(world_tri(world), "coverage")
	for i = 0; claim != nil && family != nil && i < tri.index_count(family); i += 1 {
		c    = tri.pattern(world_tri(world), cstring(tri.index_tag(family, i)))
		name = tri.type_name(world_tri(world), tri.Type(claim.kind))
		if tri.print(world_tri(world), tri.at(world_tri(world), c, "claimKind"), &kind[0], size_of(kind)) > 2 &&
		   strn_equal(cstring(&kind[1]), cstring(&([^]u8)(name)[1]), len(buf_s(kind[:])) - 2) &&
		   tri.node_type(tri.at(world_tri(world), c, "viaPartOf")) == tri.type_named(world_tri(world), "true") {
			return true
		}
	}
	return false
}


@(private = "file")
add_claims :: proc(world: ^World, on: Entity_ID, partsOnly: bool, found: ^[dynamic]Entity_ID) {
	claims: [16]Entity_ID
	m: uint
	j: uint

	m = world_edges_to(world, .Claim_Subject, on, &claims[0], 16)
	// The C read past claims[16] when more than 16 claimed it; here only within it
	for j = 0; j < m && j < 16; j += 1 {
		if (!partsOnly || covers_parts(world, (^Claim)(world_record(world, world_kind_named(world, "Claim"), claims[j])))) &&
		   !slice.contains(found[:], claims[j]) {
			append(found, claims[j])
		}
	}
}


/* Claims (COMPONENTS.md Scenario 3): those covering an entity, as entity
 * IDs. Settled: []Entity_ID, in the temporary allocator. */
claims_covering :: proc(world: ^World, entity: Entity_ID) -> []Entity_ID {
	found: [dynamic]Entity_ID
	part: ^Part
	at: Location
	up: Entity_ID
	source: Entity_ID
	k: int

	found = make([dynamic]Entity_ID, context.temp_allocator)
	/* on it */
	add_claims(world, entity, false, &found)
	/* on what it was divided from, for what has no claim of its own (a
	 * split leaves it claimed as its stack is; passed on since, it is
	 * claimed as it was passed) */
	if len(found) == 0 && world_edges_from(world, .Split_From, entity, &source, 1) != 0 {
		add_claims(world, source, false, &found)
	}
	/* on the assemblies it is part of, or came out of, up the chain: only
	 * for a part with no claim of its own (COMPONENTS.md decision 11:
	 * installing transfers nothing) */
	for up, k = (NO_ENTITY if len(found) != 0 else entity), 0; up != 0 && k < 8; k += 1 {
		at   = world_location_of(world, up)
		part = (^Part)(world_record(world, world_kind_named(world, "Part"), up))
		up   = at.place if at.form == .Part_Of else Entity_ID(part.cameFrom) if part != nil else NO_ENTITY
		if up != 0 {
			add_claims(world, up, true, &found)
		}
	}
	return found[:]
}


/* Whether ownership of it is an open question: claims covering it name
 * different claimants. */
ownership_open :: proc(world: ^World, entity: Entity_ID) -> bool {
	claims: []Entity_ID
	who: Entity_ID
	first: Entity_ID
	i: int

	claims = claims_covering(world, entity)
	first  = NO_ENTITY
	for i = 0; i < len(claims); i += 1 {
		if world_edges_from(world, .Claimant, claims[i], &who, 1) == 0 {
			continue
		}
		if first != 0 && who != first {
			return true
		}
		first = who
	}
	return false
}


/* What authority there is over an entity (COMPONENTS.md Scenario 2): the
 * reified authorizations over it, each linked to the content that states
 * it. Content no authorization links to confers nothing. Settled:
 * []Entity_ID, in the temporary allocator. */
authorizations_over :: proc(world: ^World, entity: Entity_ID) -> []Entity_ID {
	auth: ^Authorization
	found: [dynamic]Entity_ID
	store: ^Store
	i: uint

	found = make([dynamic]Entity_ID, context.temp_allocator)
	store = world_store_for_kind(world, world_kind_named(world, "Authorization"))
	for i = 0; i < store_count(store); i += 1 {
		auth = (^Authorization)(store_record_at_index(store, i))
		if Entity_ID(auth.over) == entity {
			append(&found, store_entity_at_index(store, i))
		}
	}
	return found[:]
}


/* ACTIONS.md §3's authorize(action), past its stub: the authorizations
 * granting the actor something over what the action binds. It never blocks
 * an attempt: whether an institution permits or forbids is §6's. Settled:
 * []Entity_ID, in the temporary allocator. */
authorize :: proc(world: ^World, action: Action) -> []Entity_ID {
	auth: ^Authorization
	found: [dynamic]Entity_ID
	store: ^Store
	i: uint

	found = make([dynamic]Entity_ID, context.temp_allocator)
	store = world_store_for_kind(world, world_kind_named(world, "Authorization"))
	for i = 0; i < store_count(store); i += 1 {
		auth = (^Authorization)(store_record_at_index(store, i))
		if Entity_ID(auth.grantee) != action.roles[.Actor] {
			continue
		}
		for r in Role.Item ..< Role.Count {
			if action.roles[r] != 0 && Entity_ID(auth.over) == action.roles[r] {
				append(&found, store_entity_at_index(store, i))
				break
			}
		}
	}
	return found[:]
}


/* Whether it is another's and not `who`'s: someone else claims it
 * (ownership or custody), and `who` doesn't own it, nor has it in keeping
 * (lent it, holding and using it is no wrong, till the loan's term is
 * over). What several own is each
 * one's own: a household's larder is every one of its people's. */
claimed_by_another :: proc(world: ^World, entity: Entity_ID, who: Entity_ID) -> bool {
	claim: ^Claim
	claims: []Entity_ID
	c: Entity_ID
	claimant: Entity_ID
	i: int

	another := false
	claims = claims_covering(world, entity)
	for i = 0; i < len(claims); i += 1 {
		c     = claims[i]
		claim = (^Claim)(world_record(world, world_kind_named(world, "Claim"), c))
		if claim == nil || claim.kind == u32(tri.type_named(world_tri(world), "\"reservation\"")) {
			continue      /* a reservation is no claim to it, unless an institution says so */
		}
		if world_edges_from(world, .Claimant, c, &claimant, 1) == 0 do continue
		/* a keeping past its term is no claim any more */
		if claim_lapsed(world, c) do continue
		/* its own, unless only in its custody: custody isn't ownership */
		if claimant == who {
			if claim.kind != u32(tri.type_named(world_tri(world), "\"custody\"")) do return false
			continue
		}
		another = true
	}
	return another
}


/* The laws the action breaks (INSTITUTIONS.md decision 2), as entity IDs:
 * true, for the inspector and for those who act on it; nothing blocks it. A
 * law forbids a kind of operation (the type `forbids` names: the action's
 * operation is of it, or of one under it) when the act is its kind of
 * wrong: "anothers", the
 * item claimed (owned or held in custody) by someone else and no
 * authorization of the actor over it; "unauthorized", no authorization over
 * what it binds. Settled: []Entity_ID, in the temporary allocator. */
laws_broken :: proc(world: ^World, action: Action) -> []Entity_ID {
	law: ^Law
	broken: [dynamic]Entity_ID
	laws: ^Store
	content: ^tri.Content
	i: uint
	authorized: bool
	wrong: bool

	broken     = make([dynamic]Entity_ID, context.temp_allocator)
	content    = world_tri(world)
	pattern   := tri.pattern(content, action.operation) if action.operation != nil else nil
	laws       = world_store_for_kind(world, world_kind_named(world, "Law"))
	authorized = len(authorize(world, action)) > 0
	for i = 0; pattern != nil && i < store_count(laws); i += 1 {
		law = (^Law)(store_record_at_index(laws, i))
		forbidden := tri.type_named(content, law.forbids) if law.forbids != nil else 0
		if forbidden == 0 || tri.subtype(content, tri.node_type(pattern), forbidden) == 0 {
			continue
		}
		if law.wrong == u32(tri.type_named(content, "\"anothers\"")) {
			wrong = !authorized && action.roles[.Item] != 0 &&
			        claimed_by_another(world, action.roles[.Item], action.roles[.Actor])
		} else {
			wrong = !authorized
		}
		if wrong {
			append(&broken, store_entity_at_index(laws, i))
		}
	}
	return broken[:]
}


/* Whether any authorization links to the content. */
content_authorizes :: proc(world: ^World, content: Entity_ID) -> bool {
	for i: uint = 0; i < world_edge_count(world); i += 1 {
		if world_edge_at(world, i).kind == .Authorizes && world_edge_at(world, i).to == content {
			return true
		}
	}
	return false
}


/* A custody claim (INSTITUTIONS.md decision 7) of the actor's on the
 * entity, in the group. */
@(private = "file")
take_custody :: proc(g: ^Proposal_Group, actor: Entity_ID, of: Entity_ID, key: cstring) {
	claim: Entity_ID

	claim = proposal_group_create(g, "custody", key, location_make_none())
	proposal_group_relate(g, .Claimant, whole(claim), whole(actor))
	proposal_group_relate(g, .Claim_Subject, whole(claim), whole(of))
}


/* Confiscating: the thing out of its holder's hand into the officer's, from
 * where it is (if it has moved meanwhile, the stage fails), and into the
 * watch's custody. */
@(private = "file")
effect_confiscate :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	hand: i32

	hand = free_hand(world, a.roles[.Actor])
	if hand < 0 {
		return "no hand is free"
	}
	proposal_group_move_to_expecting(g, whole(a.roles[.Item]), held_by(a.roles[.Actor], hand),
	                                 world_location_of(world, a.roles[.Item]))
	take_custody(g, a.roles[.Actor], a.roles[.Item], "confiscated")
	return ""
}


/* Arresting: the person into the watch's custody, an event it perceives;
 * what it does then is its own decision. */
@(private = "file")
effect_arrest :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	take_custody(g, a.roles[.Actor], a.roles[.Item], "under arrest")
	proposal_group_emit_subject_other_detail(g, "arrested", whole(a.roles[.Item]), whole(a.roles[.Actor]), nil)
	return ""
}


/* Fleeing: straight away from the one fled, as far as the operation runs
 * (`run`, four tiles if it says none), on the map, and along its edge where
 * straight away is off it. */
@(private = "file")
effect_flee :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	at: Location
	from: Location
	dx: i32
	dy: i32
	k: int

	at   = world_location_of(world, a.roles[.Actor])
	from = world_location_of(world, a.roles[.Item])
	if at.form != .On_Tile || from.form != .On_Tile {
		return "one can flee only on the ground"
	}
	dx = 1 if at.x > from.x else -1 if at.x < from.x else 0
	dy = 1 if at.y > from.y else -1 if at.y < from.y else 0
	if dx == 0 && dy == 0 {
		dx = 1
	}
	/* along an edge, when the way straight off is off the map */
	run := operation_run(world, a.operation)
	for k = 0; k < int(run); k += 1 {
		switch {
		case world_is_tile_x(world, at.x + dx, at.y + dy, at.level):
			at.x += dx
			at.y += dy
		case dx != 0 && world_is_tile_x(world, at.x + dx, at.y, at.level):
			at.x += dx
		case dy != 0 && world_is_tile_x(world, at.x, at.y + dy, at.level):
			at.y += dy
		case:
			k = int(run)
		}
	}
	proposal_group_move_to(g, whole(a.roles[.Actor]), at)
	tread(world, at, g)
	return ""
}


/* A blow (AGENCY.md §13): an injury to the one hit, which it feels, and
 * knows who dealt. Hitting oneself does nothing. */
@(private = "file")
effect_hit :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	if a.roles[.Item] == a.roles[.Actor] {
		return "one cannot hit oneself"
	}
	injure(world, g, a.roles[.Item], a.roles[.Actor], 15)
	return ""
}


/* Crouching (content/hunting/): hiding, seen only from beside it, until a
 * shot gives it away. */
@(private = "file")
effect_crouch :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	proposal_group_set_of_to(g, "Agent.hiding", whole(a.roles[.Actor]), 1)
	return ""
}


/* A shot (content/hunting/): it strikes by a seeded draw, as the bow aims
 * at that many tiles and the hunter's stalking; struck, the game is
 * wounded as the bow wounds, and knows who shot. Struck or missed, the
 * shot gives the hunter away. */
@(private = "file")
effect_shoot :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	wounds, aim, spread, stalking: i64
	here, there: Location
	game := a.roles[.Destination]
	if game == a.roles[.Actor] do return "one cannot shoot oneself"
	if !world_get_field(world, "Bow.wounds", a.roles[.Item], &wounds) do return "it shoots with no bow"
	world_get_field(world, "Bow.aim", a.roles[.Item], &aim)
	world_get_field(world, "Bow.spread", a.roles[.Item], &spread)
	world_get_field(world, "Agent.stalking", a.roles[.Actor], &stalking)
	if !know_ground_tile(world, a.roles[.Actor], &here) || !know_ground_tile(world, game, &there) do return "it has nothing to shoot at"
	proposal_group_set_of_to(g, "Agent.hiding", whole(a.roles[.Actor]), 0)
	/* the chance in a hundred: the bow's aim, less its spread each tile
	 * beyond the first, in the hunter's hands; drawn, seeded by the shot */
	tiles  := i64(max(abs(here.x - there.x), abs(here.y - there.y), 1))
	chance := max(aim - spread * (tiles - 1), 0) * stalking / 100
	state  := mix(world_seed(world) ~ mix(world_boundary(world) * 0x100 + u64(a.roles[.Actor])) ~ mix(u64(game)) ~ 0x73686f74)
	if i64(next(&state) % 100) >= chance {
		proposal_group_emit_subject_other_detail(g, "missed", whole(game), whole(a.roles[.Actor]), nil)
		return ""
	}
	injure(world, g, game, a.roles[.Actor], wounds)
	return ""
}


/* Butchering a carcass (content/hunting/butchering.tri): its meat, a stack
 * of so many cuts, in the butcher's free hand, or, stowing, a pack it
 * carries; its hide lying where it lay; the rest is waste. */
@(private = "file")
effect_butcher :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	cuts: i64
	carcass := a.roles[.Item]
	meat := world_text_field(world, "Carcass.yields", carcass)
	hide := world_text_field(world, "Carcass.hide", carcass)
	if meat == nil || len(meat) == 0 || !world_get_field(world, "Carcass.cuts", carcass, &cuts) do return "it is no carcass"
	each := int_feature(world_tri(world), tri.pattern(world_tri(world), meat), "unitMass", 0)
	place, ok := receiving(world, a.roles[.Actor], each * cuts, operation_stows(world, a.operation))
	if !ok do return "no hand is free"
	at := world_location_of(world, carcass)
	/* a cut each, gathered into one stack: each made as its blueprint is,
	 * so the count and the mass are declared */
	into := NO_ENTITY
	for _ in 0 ..< cuts {
		cut := proposal_group_create(g, meat, "meat", place)
		if into == NO_ENTITY do into = cut
		else do proposal_group_merge(g, whole(cut), whole(into))
	}
	if hide != nil && len(hide) > 0 do proposal_group_create(g, hide, "a hide", at)
	proposal_group_destroy(g, whole(carcass), "butchered")
	return ""
}


/* An injury to a body (things.tri's #Agent), which it feels, and knows who
 * dealt (a "struck" event, a #Struck finding); at 100 it dies. */
injure :: proc(world: ^World, g: ^Proposal_Group, victim: Entity_ID, by: Entity_ID, amount: i64) {
	injury: i64
	world_get_field(world, "Agent.injury", victim, &injury)
	after := min(injury + amount, 100)
	proposal_group_set_of_to(g, "Agent.injury", whole(victim), after)
	proposal_group_emit_subject_other_detail(g, "struck", whole(victim), whole(by), nil)
	if after >= 100 do die(world, g, victim)
}


/* Posting (content/market/): the command's #Writing on the stall's board,
 * in place of what it said: a price posted anew. */
@(private = "file")
effect_post :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	author: string

	if !has_text(a.content) do return "post what?"
	if _, ok := writing_entries(a.content, &author); !ok || author == "" do return "that is not writing"
	proposal_group_set_of_to_text(g, "Record.writing", whole(a.roles[.Item]), world_intern(world, a.content))
	proposal_group_emit_subject_other_detail(g, "wrote", whole(a.roles[.Actor]), whole(a.roles[.Item]), a.content)
	return ""
}


/* Shouldering a backpack (content/carrying/): onto the back, which is no
 * hand, if nothing is there already. */
@(private = "file")
effect_shoulder :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	held: [8]Entity_ID
	for e in held[:min(world_entities_at(world, a.roles[.Actor], .Held_By, raw_data(held[:]), 8), 8)] {
		if world_location_of(world, e).slot == BG_BACK do return "something is on its back already"
	}
	proposal_group_move_to(g, whole(a.roles[.Item]), held_by(a.roles[.Actor], BG_BACK))
	return ""
}


/* Death (VILLAGE.md decision 7, content/harm/): a body whose injury reaches
 * 100 is its remains (its `remains`, a blueprint: a deer's carcass, a
 * person's corpse), as heavy as it was, where it was; what it held falls
 * there. Its mind goes with it (agency), and its activities end, their
 * actor gone. */
die :: proc(world: ^World, g: ^Proposal_Group, body: Entity_ID) {
	held: [8]Entity_ID
	at := world_location_of(world, body)
	for e in held[:world_entities_at(world, body, .Held_By, raw_data(held[:]), len(held))] {
		proposal_group_move_to(g, whole(e), at)
	}
	blueprint := world_text_field(world, "Agent.remains", body)
	become(world, g, body, blueprint if blueprint != nil && blueprint != "" else "corpse", "died")
}


/* A thing that becomes another (a body its remains, food spoiled food): the
 * other made where it was, as heavy, its mass carved from it, none made or
 * lost; the thing ended, `why`. The new one's handle. */
become :: proc(world: ^World, g: ^Proposal_Group, e: Entity_ID, blueprint: cstring, why: cstring) -> Entity_ID {
	after := proposal_group_create(g, blueprint, why, world_location_of(world, e))
	proposal_group_relate(g, .Split_From, whole(after), whole(e))
	proposal_group_set_of_to(g, "Body.mass", whole(after), world_mass_of(world, e))
	proposal_group_set_of_to(g, "Body.mass", whole(e), 0)
	proposal_group_destroy(g, whole(e), why)
	return after
}


/* Hiring (AGENCY.md decision 15): the one hired is bound to the actor, its
 * loyalty to whoever employs it (decision 12). */
@(private = "file")
effect_hire :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	bond: Entity_ID

	if a.roles[.Item] == a.roles[.Actor] {
		return "one cannot hire oneself"
	}
	bond = proposal_group_create(g, "work_bond", "employment", location_make_none())
	proposal_group_set_of_to(g, "Bond.bondOf", whole(bond), i64(a.roles[.Item]))
	proposal_group_set_of_to(g, "Bond.toward", whole(bond), i64(a.roles[.Actor]))
	return ""
}


/* Through a door: onto its tile. */
@(private = "file")
effect_pass :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	proposal_group_move_to(g, whole(a.roles[.Actor]), world_location_of(world, a.roles[.Item]))
	return ""
}


/* Sawing's end: the log is sawn through. */
@(private = "file")
effect_saw :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	lengths, mass, unit_mass: i64

	/* a trunk of more than one length: a length sawn off, a log of its own
	 * (content/firewood/), and the trunk shorter, to saw again */
	trunk := a.roles[.Destination]
	if world_get_field(world, "Trunk.lengths", trunk, &lengths) && lengths > 1 {
		cuts := world_text_field(world, "Trunk.cutsInto", trunk)
		if cuts == nil || len(cuts) == 0 do return "it saws into nothing"
		world_get_field(world, "Body.mass", trunk, &mass)
		unit_mass = mass / lengths
		/* the log is carved from the trunk, which is lighter by as much */
		log := proposal_group_create(g, cuts, "a log sawn off", world_location_of(world, trunk))
		proposal_group_relate(g, .Split_From, whole(log), whole(trunk))
		proposal_group_set_of_to(g, "Trunk.lengths", whole(trunk), lengths - 1)
		proposal_group_set_of_to(g, "Body.mass", whole(trunk), mass - unit_mass)
		proposal_group_set_of_to(g, "Log.sawn", whole(trunk), 0)
		return ""
	}
	proposal_group_set_of_to(g, "Log.sawn", whole(trunk), 100)
	return ""
}


/* A blueprint's text field ("unit"), or "": a temporary string. */
@(private = "file")
blueprint_text :: proc(world: ^World, blueprint: cstring, field: cstring) -> string {
	buf: [256]u8

	tc      := world_tri(world)
	pattern := tri.pattern(tc, blueprint)
	v       := tri.at(tc, pattern, field) if pattern != nil else nil
	if v == nil do return ""
	tri.print(tc, v, raw_data(buf[:]), size_of(buf))
	s := string(cstring(raw_data(buf[:])))
	if len(s) < 2 || s[0] != '"' || s[len(s) - 1] != '"' do return ""
	return strings.clone(s[1:len(s) - 1], context.temp_allocator)
}


/* Sowing a row (content/farming/): as many tiles of the bare plot as a row
 * has, or as the seed in hand or the plot have left, a unit of the seed to
 * each. The last row sown, the plot stands sown, growing from now. Two
 * sowing it at once can't both count on the rows they read: the second
 * fails. */
@(private = "file")
effect_sow :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	seed := a.roles[.Item]
	at   := a.roles[.Destination]
	plot := plot_of(world, at)
	if plot == nil do return "it is no plot"
	if plot.stands != plot_stands(world, "bare") do return "it is sown already"
	sows  := world_text_field(world, "Seed.sows", seed)
	grows := world_text_field(world, "Plot.grows", at)
	if sows == nil || grows == nil || string(sows) != string(grows) do return "that seed doesn't sow it"
	east, south := world_area_extent(world, at)
	tiles := i64(east) * i64(south)
	n     := min(i64(east), tiles - plot.sown, world_units_of(world, seed))
	if n <= 0 do return "there is nothing to sow"
	if plot.sown + n >= tiles {
		proposal_group_set_of_to_expecting(g, "Plot.sown", whole(at), 0, plot.sown)
		proposal_group_set_of_to(g, "Plot.stands", whole(at), i64(plot_stands(world, "sown")))
		proposal_group_set_of_to(g, "Plot.sownAt", whole(at), world_time(world).ms)
		if plot.kept do proposal_group_set_of_to(g, "Plot.kept", whole(at), 0)   /* seed kept from the next harvest */
	} else {
		proposal_group_set_of_to_expecting(g, "Plot.sown", whole(at), plot.sown + n, plot.sown)
	}
	if n >= world_units_of(world, seed) {
		proposal_group_destroy(g, whole(seed), "sown")
	} else {
		proposal_group_destroy(g, whole(proposal_group_split(g, whole(seed), n, location_make_none())), "sown")
	}
	return ""
}


/* Keeping back seed (content/farming/): of a harvest in hand, a sack of
 * seed's worth (its `keptAs`, a blueprint) carved off as seed, as heavy,
 * into a pack or a free hand, or in its place if that is all of it; the
 * plot it is kept for marked, till it is sown again. */
@(private = "file")
effect_keep_seed :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	harvest, at := a.roles[.Item], a.roles[.Destination]
	plot := plot_of(world, at)
	if plot == nil do return "it is no plot"
	if plot.kept do return "seed is kept for it already"
	kept := world_text_field(world, "Food.keptAs", harvest)
	if kept == nil || len(kept) == 0 do return "it is no seed"
	tc := world_tri(world)
	seed := tri.pattern(tc, kept)
	mass := int_feature(tc, seed, "unitMass", 0) * int_feature(tc, seed, "count", 0)
	units := world_units_of(world, harvest)
	each := world_mass_of(world, harvest) / max(units, 1)
	if mass <= 0 || each <= 0 || mass % each != 0 do return "it can't be kept as that seed"
	k := mass / each
	if k > units do return "there is too little of it"
	part := whole(harvest)
	place := world_location_of(world, harvest)
	if k < units {
		ok: bool
		place, ok = receiving(world, a.roles[.Actor], mass, operation_stows(world, a.operation))
		if !ok do return "no hand is free"
		part = whole(proposal_group_split(g, whole(harvest), k, location_make_none()))
	}
	after := proposal_group_create(g, kept, "seed kept back", place)
	proposal_group_relate(g, .Split_From, whole(after), part)
	proposal_group_set_of_to(g, "Body.mass", part, 0)
	proposal_group_destroy(g, part, "kept back as seed")
	proposal_group_set_of_to(g, "Plot.kept", whole(at), 1)
	return ""
}


/* Harvesting a row of a ripe plot (content/farming/): what its tiles yield
 * is in the harvester's hand, with a stack of the kind it holds already
 * (not one cooked), else in a free one. The last row reaped, the plot is bare. */
@(private = "file")
effect_harvest :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	held: [8]Entity_ID

	at   := a.roles[.Item]
	plot := plot_of(world, at)
	if plot == nil do return "it is no plot"
	if plot.stands != plot_stands(world, "ripe") do return "it isn't ripe"
	yields := world_text_field(world, "Plot.yields", at)
	if yields == nil || len(yields) == 0 do return "it yields nothing"
	east, south := world_area_extent(world, at)
	tiles := i64(east) * i64(south)
	n     := min(i64(east), tiles - plot.reaped)
	if n <= 0 do return "there is nothing to reap"
	unit_ := blueprint_text(world, yields, "unit")
	with  := NO_ENTITY
	nheld := world_entities_at(world, a.roles[.Actor], .Held_By, raw_data(held[:]), 8)
	for e in held[:nheld] {
		u := world_unit_of(world, e)
		raw: i64
		if world_is_stack(world, e) && u != nil && string(u) == unit_ && with == NO_ENTITY &&
		   (!world_get_field(world, "Food.raw", e, &raw) || raw != 0) {
			with = e
		}
	}
	where_: Location
	if with != NO_ENTITY {
		where_ = world_location_of(world, with)
	} else {
		hand := free_hand(world, a.roles[.Actor])
		if hand < 0 do return "no hand is free"
		where_ = held_by(a.roles[.Actor], hand)
	}
	/* a tile's yield each, gathered into one stack */
	into := with
	for _ in 0 ..< n {
		got := proposal_group_create(g, yields, "a harvest", where_)
		if into == NO_ENTITY do into = got
		else do proposal_group_merge(g, whole(got), whole(into))
	}
	if plot.reaped + n >= tiles {
		proposal_group_set_of_to_expecting(g, "Plot.reaped", whole(at), 0, plot.reaped)
		proposal_group_set_of_to(g, "Plot.stands", whole(at), i64(plot_stands(world, "bare")))
	} else {
		proposal_group_set_of_to_expecting(g, "Plot.reaped", whole(at), plot.reaped + n, plot.reaped)
	}
	return ""
}


/* The region of air (a GasStore) over the entity's tile, or 0. */
air_over :: proc(world: ^World, e: Entity_ID) -> Entity_ID {
	at: Location
	p: Entity_ID
	k: int

	for p, k = e, 0; p != 0 && k < 64; k += 1 {
		at = world_location_of(world, p)
		if at.form == .On_Tile {
			break
		}
		p = at.place
	}
	if at.form != .On_Tile {
		return NO_ENTITY
	}
	return world_air_region_at(world, at)       /* the room's air (TERRAIN.md step 3) */
}


/* Tending changes nothing but traces, which the operation declares. */
@(private = "file")
effect_tend :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	return ""
}


/* A rest, rested through: fatigue is gone. */
@(private = "file")
effect_rest :: proc(world: ^World, a: Action, amount: i64, g: ^Proposal_Group) -> string {
	if world_record(world, world_kind_named(world, "Agent"), a.roles[.Actor]) != nil {
		proposal_group_set_of_to(g, "Agent.fatigue", whole(a.roles[.Actor]), 0)
	}
	return ""
}


@(private = "file")
Named_Effect :: struct {
	name:     string,
	function: Effect,
}

@(private = "file")
effects := [?]Named_Effect{
	{"drive",     effect_drive},
	{"walk",      effect_walk},
	{"say",       effect_say},
	{"tend",      effect_tend},
	{"analyse",   effect_analyse},
	{"write",     effect_write},
	{"read",      effect_read},
	{"eat",       effect_eat},
	{"sow",       effect_sow},
	{"keep_seed", effect_keep_seed},
	{"harvest",   effect_harvest},
	{"investigate", effect_investigate},
	{"rotate",    effect_rotate},
	{"confiscate", effect_confiscate},
	{"arrest",    effect_arrest},
	{"flee",      effect_flee},
	{"hit",       effect_hit},
	{"hire",      effect_hire},
	{"work",      effect_work},
	{"saw",       effect_saw},
	{"pass",      effect_pass},
	{"copy",      effect_copy},
	{"reveal",    effect_reveal},
	{"replace",   effect_replace},
	{"service",   effect_service},
	{"cut",       effect_cut},
	{"shape",     effect_shape},
	{"issue",     effect_issue},
	{"rest",      effect_rest},
	{"strike",    effect_strike},
	{"crouch",    effect_crouch},
	{"forage",    effect_forage},
	{"shoot",     effect_shoot},
	{"butcher",   effect_butcher},
	{"post",      effect_post},
	{"shoulder",  effect_shoulder},
}


/* How far a flight carries, in tiles (content/actions.tri's `run`). */
operation_run :: proc(world: ^World, op: cstring) -> i64 {
	lo, hi: i64
	tc := world_tri(world)
	v  := tri.at(tc, tri.pattern(tc, op), "run")
	return lo if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi && lo >= 1 else 4
}


/* How far the operation's other roles may be from its actor, in tiles
 * (content/actions.tri's `range`): 1, beside it. */
operation_range :: proc(world: ^World, operation: cstring) -> i32 {
	lo, hi: i64
	pattern := tri.pattern(world_tri(world), operation) if operation != nil else nil
	v := tri.at(world_tri(world), pattern, "range") if pattern != nil else nil
	return i32(lo) if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi && lo >= 1 else 1
}


/* The operation's effect name. Settled: (string, bool) #optional_ok, false
 * where the Objective-C returned nil (no operation, or no effect). */
operation_effect :: proc(world: ^World, operation: cstring) -> (string, bool) #optional_ok {
	pattern: ^tri.Node
	effect: [64]u8
	n: uint

	pattern = tri.pattern(world_tri(world), operation) if operation != nil else nil
	if pattern == nil || tri.at(world_tri(world), pattern, "effect") == nil {
		return "", false
	}
	n = tri.print(world_tri(world), tri.at(world_tri(world), pattern, "effect"), &effect[0], size_of(effect))
	/* unnamed, it prints as its type: the operation's effect is declared */
	if n < 2 || n >= size_of(effect) || effect[0] != '"' {
		return "", false
	}
	effect[n - 1] = 0          /* without its quotes */
	return strings.clone(string(cstring(&effect[1])), context.temp_allocator), true
}


/* The operation's duration in ms (0 if it has none). */
operation_duration :: proc(world: ^World, operation: cstring) -> i64 {
	pattern: ^tri.Node
	hi: i64
	lo: i64

	pattern = tri.pattern(world_tri(world), operation) if operation != nil else nil
	if pattern == nil || tri.node_interval(tri.at(world_tri(world), pattern, "duration"), &lo, &hi) == 0 || lo != hi {
		return 0
	}
	return lo
}


/* Stage `index` of an operation: its duration and effect. An operation with
 * a duration and no stages has one stage. NO past the last stage. The
 * effect is "" where the Objective-C's was nil. */
operation_stage :: proc(world: ^World, operation: cstring, index: i64, duration: ^i64, effect: ^string) -> bool {
	pattern: ^tri.Node
	stage: ^tri.Node
	path: strings.Builder
	content: ^tri.Content
	hi: i64
	k: i64
	text: [64]u8
	n: uint

	content = world_tri(world)
	pattern = tri.pattern(content, operation) if operation != nil else nil
	if pattern == nil {
		return false
	}
	if tri.at(content, pattern, "stages.first") == nil {
		/* one stage: the operation's own duration and effect */
		duration^ = operation_duration(world, operation)
		effect^   = operation_effect(world, operation)
		return index == 0 && duration^ > 0
	}
	path = strings.builder_make(context.temp_allocator)
	strings.write_string(&path, "stages")
	for k = 0; k < index; k += 1 {
		strings.write_string(&path, ".rest")
	}
	strings.write_string(&path, ".first")
	stage = tri.at(content, pattern, ns_utf8(strings.to_string(path)))
	if stage == nil || tri.node_interval(tri.at(content, stage, "duration"), duration, &hi) == 0 || duration^ != hi {
		return false
	}
	n = tri.print(content, tri.at(content, stage, "effect"), &text[0], size_of(text))
	if n < 2 || n >= size_of(text) {
		return false
	}
	/* unnamed, it prints as its type: "" */
	if text[0] != '"' {
		effect^ = ""
		return true
	}
	text[n - 1] = 0
	effect^ = strings.clone(string(cstring(&text[1])), context.temp_allocator)
	return true
}


/* Stage `index`'s partial effect (ACTIONS.md §5): the field, the role it
 * shows on (Role.Item or Role.Destination, as an i32), the whole it reaches, and its
 * checkpoints. NO if it declares none. */
operation_partial :: proc(world: ^World, operation: cstring, index: i64,
                          field: ^cstring, role: ^i32, whole: ^i64, checkpoints: ^i64) -> bool {
	pattern: ^tri.Node
	stage: ^tri.Node
	path: strings.Builder
	content: ^tri.Content
	lo: i64
	hi: i64
	k: i64
	text: [64]u8
	n: uint

	content = world_tri(world)
	pattern = tri.pattern(content, operation) if operation != nil else nil
	if pattern == nil {
		return false
	}
	stage = pattern
	if tri.at(content, pattern, "stages.first") != nil {
		path = strings.builder_make(context.temp_allocator)
		strings.write_string(&path, "stages")
		for k = 0; k < index; k += 1 {
			strings.write_string(&path, ".rest")
		}
		strings.write_string(&path, ".first")
		stage = tri.at(content, pattern, ns_utf8(strings.to_string(path)))
	} else if index != 0 {
		return false
	}
	n = tri.print(content, tri.at(content, stage, "partial.field"), &text[0], size_of(text)) if stage != nil else 0
	if n < 3 || n >= size_of(text) || text[0] != '"' ||
	   tri.node_interval(tri.at(content, stage, "partial.whole"), &lo, &hi) == 0 || lo != hi {
		return false
	}
	text[n - 1] = 0
	field^ = world_intern(world, cstring(&text[1]))
	whole^ = lo
	role^  = i32(Role.Destination)
	n      = tri.print(content, tri.at(content, stage, "partial.showsOn"), &text[0], size_of(text))
	if n > 2 && buf_s(text[:]) == "\"item\"" {
		role^ = i32(Role.Item)
	}
	checkpoints^ = lo if tri.node_interval(tri.at(content, stage, "checkpoints"), &lo, &hi) != 0 && lo == hi else 0
	return true
}


/* Whether the operation's stages but the last are diagnostic: what each
 * does is a step along the way, not history (KNOWLEDGE.md decision 21). */
operation_diagnostic_stages :: proc(world: ^World, operation: cstring) -> bool {
	content := world_tri(world)
	v := tri.at(content, tri.pattern(content, operation), "diagnosticStages") if operation != nil else nil
	return v != nil && tri.node_type(v) == tri.type_named(content, "true")
}


/* The fatigue stage `index` adds to its actor when it completes. */
operation_exertion :: proc(world: ^World, operation: cstring, index: i64) -> i64 {
	pattern: ^tri.Node
	stage: ^tri.Node
	path: strings.Builder
	content: ^tri.Content
	k: i64
	lo: i64
	hi: i64

	content = world_tri(world)
	pattern = tri.pattern(content, operation) if operation != nil else nil
	if pattern == nil {
		return 0
	}
	stage = pattern
	if tri.at(content, pattern, "stages.first") != nil {
		path = strings.builder_make(context.temp_allocator)
		strings.write_string(&path, "stages")
		for k = 0; k < index; k += 1 {
			strings.write_string(&path, ".rest")
		}
		strings.write_string(&path, ".first")
		stage = tri.at(content, pattern, ns_utf8(strings.to_string(path)))
	}
	return lo if stage != nil && tri.node_interval(tri.at(content, stage, "exertion"), &lo, &hi) != 0 && lo == hi else 0
}


/* Whether stage `index` fails on a hard interruption, rather than being
 * suspended. */
operation_fails_hard :: proc(world: ^World, operation: cstring, index: i64) -> bool {
	pattern: ^tri.Node
	stage: ^tri.Node
	path: strings.Builder
	content: ^tri.Content
	k: i64
	text: [16]u8

	content = world_tri(world)
	pattern = tri.pattern(content, operation) if operation != nil else nil
	if pattern == nil {
		return false
	}
	stage = pattern
	if tri.at(content, pattern, "stages.first") != nil {
		path = strings.builder_make(context.temp_allocator)
		strings.write_string(&path, "stages")
		for k = 0; k < index; k += 1 {
			strings.write_string(&path, ".rest")
		}
		strings.write_string(&path, ".first")
		stage = tri.at(content, pattern, ns_utf8(strings.to_string(path)))
	}
	return stage != nil && tri.print(content, tri.at(content, stage, "hard"), &text[0], size_of(text)) > 2 &&
	       buf_s(text[:]) == "\"fail\""
}


/* Performs an action chosen from the knowledge view: it must be on the
 * actor's believed menu. The world's side then resolves the referents to the
 * entities they track; if the world rules the action out (the thing isn't
 * there any more), what commits is the attempt (an "attempted" event, the
 * actor reaching where it believed the thing was), and perception corrects
 * the belief. */
perform_believed :: proc(world: ^World, committer: ^Committer, store: ^Knowledge_Store,
                         action: Action, amount: i64, error: ^string) -> ^Proposal_Group {
	ref: ^Referent
	holder: ^Referent
	group: ^Proposal_Group
	result: tri.Match_Result
	reason: string
	truth: Action
	where_: Entity_ID

	reason = ""
	if match_believed(world, store, action, &result, &reason) == .Incompatible {
		if error != nil {
			error^ = reason
		}
		return nil
	}
	/* the world's side: what the referents actually track */
	truth = action
	truth.roles[.Actor] = knowledge_store_agent(store)
	for r in Role.Item ..< Role.Count {
		ref            = knowledge_store_referent(store, u32(action.roles[r])) if action.roles[r] != 0 else nil
		truth.roles[r] = ref.truth if ref != nil else NO_ENTITY
	}
	if match_action(world, truth, &result, nil) != .Incompatible {
		return perform(world, committer, truth, amount, error)
	}

	/* it isn't as believed: the attempt is what happens, where the actor reached */
	ref    = knowledge_store_referent(store, u32(action.roles[.Item]))
	holder = knowledge_store_referent(store, ref.container) if ref != nil && ref.form == .In else nil
	where_ = holder.truth if holder != nil else (ref.truth if ref != nil else NO_ENTITY)
	group  = proposal_group_group_with_phase(.Action, fmt.tprintf("%d: %s (an attempt)",
	                                                              knowledge_store_agent(store), action.operation))
	proposal_group_set_actor(group, knowledge_store_agent(store))
	proposal_group_emit_subject_other(group, "attempted", whole(knowledge_store_agent(store)), whole(where_))
	committer_submit(committer, group)
	return group
}


/* The entity a trace site names, or the actor's tile for "tile" (0). */
@(private = "file")
trace_site :: proc(world: ^World, action: Action, site: string, bearer: ^Entity_ID, tile: ^Location) -> bool {
	at: Location
	e: Entity_ID
	k: int

	bearer^ = NO_ENTITY
	tile^   = {}
	if site == "tile" {
		for e, k = action.roles[.Actor], 0; e != 0 && k < 64; k += 1 {
			at = world_location_of(world, e)
			if at.form == .On_Tile {
				tile^ = at
				return true
			}
			e = at.place
		}
		return false
	}
	bearer^ = action.roles[.Actor] if site == "actor" else action.roles[.Item] if site == "item" else action.roles[.Destination] if site == "destination" else NO_ENTITY
	return bearer^ != NO_ENTITY
}


@(private = "file")
text_of :: proc(content: ^tri.Content, node: ^tri.Node, path: cstring, buf: []u8) -> bool {
	v: ^tri.Node
	n: uint

	v = tri.at(content, node, path) if node != nil else nil
	if v == nil {
		return false
	}
	n = tri.print(content, v, &buf[0], uint(len(buf)))
	// The C read buf[n - 1] past the buffer when the text was cut; here that is no text
	if n < 2 || buf[0] != '"' || n > uint(len(buf)) || buf[n - 1] != '"' {
		return false
	}
	copy(buf[:n - 2], buf[1:n - 1])
	buf[n - 2] = 0
	return true
}


/* The traces stage `index` of a staged operation declares, in its group. */
leave_stage_traces :: proc(world: ^World, action: Action, index: i64, group: ^Proposal_Group) {
	pattern: ^tri.Node
	stage: ^tri.Node
	list: ^tri.Node
	v: ^tri.Node
	path: strings.Builder
	content: ^tri.Content
	bearer: Entity_ID
	tile: Location
	lo: i64
	hi: i64
	k: i64
	kind: [64]u8
	site: [32]u8

	content = world_tri(world)
	pattern = tri.pattern(content, action.operation) if action.operation != nil else nil
	if pattern == nil || tri.at(content, pattern, "stages.first") == nil {
		return      /* one stage: the operation's own, left when it completes */
	}
	path = strings.builder_make(context.temp_allocator)
	strings.write_string(&path, "stages")
	for k = 0; k < index; k += 1 {
		strings.write_string(&path, ".rest")
	}
	strings.write_string(&path, ".first")
	stage = tri.at(content, pattern, ns_utf8(strings.to_string(path)))
	for list = tri.at(content, stage, "leaves") if stage != nil else nil; list != nil && tri.at(content, list, "first") != nil;
	    list = tri.at(content, list, "rest") {
		if !text_of(content, tri.at(content, list, "first"), "trace", kind[:]) ||
		   !text_of(content, tri.at(content, list, "first"), "on", site[:]) ||
		   !trace_site(world, action, buf_s(site[:]), &bearer, &tile) {
			continue
		}
		v = tri.at(content, tri.at(content, list, "first"), "strength")
		make_trace(world, group, buf_c(kind[:]), bearer, tile, lo if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi else 0,
		           action.operation)
	}
}


/* The traces the operation declares (KNOWLEDGE.md §3,
 * content/traces/traces.tri), as proposals added to `group`: those it removes
 * destroyed, those it leaves created, made now and running out after their
 * kind's `lasts`. Called with its effect, when an instant action is performed
 * or an activity completes. */
leave_traces :: proc(world: ^World, action: Action, group: ^Proposal_Group) {
	pattern: ^tri.Node
	list: ^tri.Node
	v: ^tri.Node
	record: ^Trace
	traces: ^Store
	bearer: Entity_ID
	t: Entity_ID
	tile: Location
	content: ^tri.Content
	i: uint
	lo: i64
	hi: i64
	strength: i64
	kind: [64]u8
	site: [32]u8
	text: cstring

	content = world_tri(world)
	pattern = tri.pattern(content, action.operation) if action.operation != nil else nil
	traces  = world_store_for_kind(world, world_kind_named(world, "Trace"))
	for list = tri.at(content, pattern, "removes") if pattern != nil else nil; list != nil && tri.at(content, list, "first") != nil;
	    list = tri.at(content, list, "rest") {
		if !text_of(content, tri.at(content, list, "first"), "trace", kind[:]) ||
		   !text_of(content, tri.at(content, list, "first"), "on", site[:]) ||
		   !trace_site(world, action, buf_s(site[:]), &bearer, &tile) {
			continue
		}
		for i = 0; i < store_count(traces); i += 1 {
			record = (^Trace)(store_record_at_index(traces, i))
			t      = store_entity_at_index(traces, i)
			text   = world_text_field(world, "Trace.traceKind", t)
			if text == nil || string(text) != buf_s(kind[:]) || Entity_ID(record.bearer) != bearer {
				continue
			}
			if bearer == 0 && (record.tileX != i64(tile.x) || record.tileY != i64(tile.y) || record.tileLevel != i64(tile.level)) {
				continue
			}
			proposal_group_destroy(group, whole(t), "removed")
		}
	}
	for list = tri.at(content, pattern, "leaves") if pattern != nil else nil; list != nil && tri.at(content, list, "first") != nil;
	    list = tri.at(content, list, "rest") {
		if !text_of(content, tri.at(content, list, "first"), "trace", kind[:]) ||
		   !text_of(content, tri.at(content, list, "first"), "on", site[:]) ||
		   !trace_site(world, action, buf_s(site[:]), &bearer, &tile) {
			continue
		}
		v        = tri.at(content, tri.at(content, list, "first"), "strength")
		strength = lo if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi else 0
		make_trace(world, group, buf_c(kind[:]), bearer, tile, strength, action.operation)
	}
	grade(world, action, group)
}


/* A trace of `kind` (content/traces/traces.tri) on the bearer, or on the
 * tile if none, at `strength`, made in the group; `by` says what left it. */
make_trace :: proc(world: ^World, group: ^Proposal_Group, kind: cstring, bearer: Entity_ID,
                   tile: Location, strength: i64, by: cstring) {
	v: ^tri.Node
	t: Entity_ID
	lo: i64
	hi: i64
	lasts: i64
	key: cstring

	v     = tri.at(world_tri(world), tri.pattern(world_tri(world), kind), "lasts")
	lasts = lo if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi else 0
	key   = bounded(fmt.tprintf("%s, left by %s", kind, by), 128)
	t = proposal_group_create(group, "trace", key, location_make_none())
	proposal_group_set_of_to_text(group, "Trace.traceKind", whole(t), world_intern(world, kind))
	proposal_group_set_of_to(group, "Trace.bearer", whole(t), i64(bearer))
	proposal_group_set_of_to(group, "Trace.tileX", whole(t), i64(tile.x))
	proposal_group_set_of_to(group, "Trace.tileY", whole(t), i64(tile.y))
	proposal_group_set_of_to(group, "Trace.tileLevel", whole(t), i64(tile.level))
	proposal_group_set_of_to(group, "Trace.magnitude", whole(t), strength)
	proposal_group_set_of_to(group, "Trace.created", whole(t), world_time(world).ms)
	proposal_group_set_of_to(group, "Trace.expires", whole(t), world_time(world).ms + lasts)
}


/* An effect, as proposals added to `group`: a named one by its code; with
 * no name (""), the declared effect of the operation, or of its stage
 * `stage` if it has stages (act_declared.odin). The
 * reason if it can't be built, "" for none. */
apply_named_effect :: proc(world: ^World, effect: string, action: Action, stage: i64, amount: i64,
                           group: ^Proposal_Group) -> string {
	if effect == "" do return apply_declared_effect(world, action, stage, amount, group)
	for i := 0; i < len(effects); i += 1 {
		if effects[i].name == effect {
			return effects[i].function(world, action, amount, group)
		}
	}
	return fmt.tprintf("no code for the effect %s", effect)
}


/* An operation's effect, as proposals added to `group`: what an instant
 * action commits, and what a timed activity commits when it is due. The
 * reason if it can't be built, "" for none. */
apply_effect :: proc(world: ^World, action: Action, amount: i64, group: ^Proposal_Group) -> string {
	effect: string
	has_effect: bool

	/* named, or declared (""); an operation that isn't one has neither */
	effect, has_effect = operation_effect(world, action.operation)
	return apply_named_effect(world, effect if has_effect else "", action, 0, amount, group)
}


/* The activity entity an action starts, with its bindings. */
@(private = "file")
start_activity :: proc(world: ^World, action: Action, amount: i64, g: ^Proposal_Group) -> Entity_ID {
	a: Entity_ID
	key: cstring

	key = bounded(fmt.tprintf("activity of %d at %d: %s", action.roles[.Actor], world_boundary(world), action.operation), 96)
	a = proposal_group_create(g, "activity", key, location_make_none())
	proposal_group_set_of_to_text(g, "Activity.operation", whole(a), action.operation)
	proposal_group_set_of_to(g, "Activity.actorRef", whole(a), i64(action.roles[.Actor]))
	proposal_group_set_of_to(g, "Activity.itemRef", whole(a), i64(action.roles[.Item]))
	proposal_group_set_of_to(g, "Activity.destinationRef", whole(a), i64(action.roles[.Destination]))
	proposal_group_set_of_to(g, "Activity.amount", whole(a), amount)
	if has_text(action.content) {
		proposal_group_set_of_to_text(g, "Activity.words", whole(a), action.content)
	}
	if has_text(action.way) {
		proposal_group_set_of_to_text(g, "Activity.way", whole(a), action.way)
	}
	return a
}


/* The providers an operation's activity uses: "hands", "legs". */
@(private = "file")
providers_of :: proc(content: ^tri.Content, operation: cstring, out: [][16]u8, max_: uint) -> uint {
	list: ^tri.Node
	n: uint
	text: [32]u8
	len_: int

	n = 0
	for list = tri.at(content, tri.pattern(content, operation), "uses") if operation != nil else nil;
	    list != nil && tri.at(content, list, "first") != nil && n < max_;
	    list = tri.at(content, list, "rest") {
		tri.print(content, tri.at(content, list, "first"), &text[0], size_of(text))
		len_ = len(buf_s(text[:]))
		if len_ > 2 && text[0] == '"' && text[len_ - 1] == '"' {
			set_text(out[n][:], string(text[1:len_ - 1]))
			n += 1
		}
	}
	return n
}


/* Why the actor can't start (or resume) an activity of `operation` now: a
 * running activity of its, other than `except`, uses a provider this one
 * needs (ACTIONS.md §5: an actor runs two activities at once only if they
 * use different providers). "" when it can. */
providers_busy :: proc(world: ^World, actor: Entity_ID, operation: cstring, except: Entity_ID) -> string {
	record: ^Activity
	other: cstring
	mine: [^]Entity_ID
	busy: string
	nmine: uint
	content: ^tri.Content
	running: tri.Type
	nwanted: uint
	nused: uint
	i: uint
	j: uint
	k: uint
	wanted: [4][16]u8
	used: [4][16]u8

	content = world_tri(world)
	nwanted = providers_of(content, operation, wanted[:], 4)
	running = tri.type_named(content, "\"running\"")
	mine    = world_copy_activities_of(world, actor, &nmine)
	busy    = ""
	for i = 0; nwanted != 0 && busy == "" && i < nmine; i += 1 {
		record = (^Activity)(world_record(world, world_kind_named(world, "Activity"), mine[i]))
		if record == nil || record.status != u32(running) || mine[i] == except {
			continue
		}
		other = world_text_field(world, "Activity.operation", mine[i])
		nused = providers_of(content, other, used[:], 4)
		for j = 0; j < nwanted && busy == ""; j += 1 {
			for k = 0; k < nused && busy == ""; k += 1 {
				if buf_s(wanted[j][:]) == buf_s(used[k][:]) {
					busy = fmt.tprintf("its %s %s busy with activity %d (%s)", buf_c(wanted[j][:]),
					                   "are" if buf_s(wanted[j][:]) != "voice" else "is",
					                   mine[i], other)
				}
			}
		}
	}
	free(mine)
	return busy
}


/* The same, for activities started but not yet committed: an actor's
 * providers are its own to allocate (ACTIONS.md §5), so two activities
 * submitted for one boundary can't both have its hands. */
@(private = "file")
providers_pending :: proc(world: ^World, committer: ^Committer, actor: Entity_ID, operation: cstring) -> string {
	p: ^Proposal
	group: ^Proposal_Group
	pending: []^Proposal_Group
	content: ^tri.Content
	nwanted: uint
	nused: uint
	j: uint
	k: uint
	q: uint
	wanted: [4][16]u8
	used: [4][16]u8

	content = world_tri(world)
	nwanted = providers_of(content, operation, wanted[:], 4)
	pending = committer_deferred_groups(committer) if nwanted != 0 else nil
	for i := 0; i < len(pending); i += 1 {
		group = pending[i]
		if proposal_group_actor(group) != actor {
			continue
		}
		for q = 0; q < proposal_group_count(group); q += 1 {
			p = &proposal_group_proposals(group)[q]
			if p.kind != .Set_Field || p.name == nil || string(p.name) != "Activity.operation" ||
			   !is_handle(p.target.entity) {
				continue
			}
			nused = providers_of(content, p.key, used[:], 4)
			for j = 0; j < nwanted; j += 1 {
				for k = 0; k < nused; k += 1 {
					if buf_s(wanted[j][:]) == buf_s(used[k][:]) {
						return fmt.tprintf("its %s %s taken by %s, starting", buf_c(wanted[j][:]),
						                   "are" if buf_s(wanted[j][:]) != "voice" else "is", p.key)
					}
				}
			}
		}
	}
	return ""
}


/* Performs an action: if it is on the actor's menu, submits a group (phase
 * action) for the next boundary. An instant operation's group carries its
 * effect. One with a duration starts a timed activity, whose effect commits
 * when it is due; fill starts an activity that ends by a watch or an event
 * (BGActivities). `amount` is the command's parameter: how many, for
 * take_some; how many millilitres, for fill. nil, with the reason, if it
 * can't be attempted. */
perform :: proc(world: ^World, committer: ^Committer, action: Action, amount: i64, error: ^string) -> ^Proposal_Group {
	group: ^Proposal_Group
	result: tri.Match_Result
	effect: string
	reason: string
	source: strings.Builder
	activity: Entity_ID
	stageEffect: string
	duration: i64
	rate: i64

	reason = ""
	if match_action(world, action, &result, &reason) == .Incompatible {
		if error != nil {
			error^ = reason
		}
		return nil
	}
	/* a walk goes by its way, and only a walk has one */
	if (string(action.operation) == "walk") != has_text(action.way) {
		if error != nil {
			error^ = "only a walk has a way" if has_text(action.way) else "a walk needs a way"
		}
		return nil
	}
	effect = operation_effect(world, action.operation)
	if !operation_stage(world, action.operation, 0, &duration, &stageEffect) {
		duration = 0
	}
	if duration > 0 || effect == "fill" {
		reason = providers_busy(world, action.roles[.Actor], action.operation, NO_ENTITY)
		if reason == "" {
			reason = providers_pending(world, committer, action.roles[.Actor], action.operation)
		}
		if reason != "" {
			if error != nil {
				error^ = reason
			}
			return nil
		}
	}
	source = strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&source, "%d: %s", action.roles[.Actor], action.operation)
	for r in Role.Item ..< Role.Count {
		if action.roles[r] != 0 {
			fmt.sbprintf(&source, " %s %d", ROLE_NAMES[r], action.roles[r])
		}
	}
	if amount != 0 {
		fmt.sbprintf(&source, " (%d)", amount)
	}
	group = proposal_group_group_with_phase(.Action, strings.to_string(source))
	proposal_group_set_actor(group, action.roles[.Actor])
	proposal_group_set_weight(group, contest_weight(world, action.roles[.Actor], action.operation))
	if effect == "fill" {
		/* an activity that ends by its watch on the bucket, or by the tap running dry */
		if amount < 1 {
			if error != nil {
				error^ = "fill to how many millilitres?"
			}
			return nil
		}
		activity = start_activity(world, action, amount, group)
		proposal_group_set_of_to(group, "Activity.watchHolder", whole(activity), i64(action.roles[.Destination]))
		proposal_group_set_of_to(group, "Activity.watchAtLeast", whole(activity), amount)
		proposal_group_set_of_to(group, "Tap.open", whole(action.roles[.Item]), 1)
	} else if duration > 0 {
		/* a timed activity: its first stage's effect commits when the stage is due */
		activity = start_activity(world, action, amount, group)
		proposal_group_set_of_to(group, "Activity.started", whole(activity), world_time(world).ms)
		rate = graded_rate(world, action, work_rate(world, action.roles[.Actor], action.operation, 0))
		proposal_group_set_of_to(group, "Activity.pace", whole(activity), rate)
		proposal_group_set_of_to(group, "Activity.due", whole(activity),
		                         world_time(world).ms + at_rate(duration, rate) + access_delay(world, action))
		/* a watch on the floor at the actor's feet */
		{
			v: ^tri.Node
			floor: Location
			e: Entity_ID
			lo: i64
			hi: i64
			k: int

			v = tri.at(world_tri(world), tri.pattern(world_tri(world), action.operation), "floodWatch")
			e = action.roles[.Actor]
			for k = 0; k < 16; k += 1 {
				floor = world_location_of(world, e)
				if floor.form == .On_Tile do break
				e = floor.place
			}
			if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi && lo > 0 && floor.form == .On_Tile {
				proposal_group_set_of_to(group, "Activity.watchFloor", whole(activity), lo)
				proposal_group_set_of_to(group, "Activity.watchX", whole(activity), i64(floor.x))
				proposal_group_set_of_to(group, "Activity.watchY", whole(activity), i64(floor.y))
				proposal_group_set_of_to(group, "Activity.watchLevel", whole(activity), i64(floor.level))
			}
		}
		if effect == "rest" && air_over(world, action.roles[.Actor]) != 0 {
			breather: ^Respirator

			/* resting, with a watch on the air: woken when it grows stuffy, or
			 * leaves the band the sleeper rests easy in */
			proposal_group_set_of_to(group, "Activity.watchHolder", whole(activity), i64(air_over(world, action.roles[.Actor])))
			proposal_group_set_of_to(group, "Activity.watchDioxide", whole(activity), amount if amount > 0 else 4000)
			breather = (^Respirator)(world_record(world, world_kind_named(world, "Respirator"), action.roles[.Actor]))
			if breather != nil && breather.restsAbove != 0 {
				proposal_group_set_of_to(group, "Activity.watchCool", whole(activity), breather.restsAbove)
			}
			if breather != nil && breather.restsBelow != 0 {
				proposal_group_set_of_to(group, "Activity.watchWarm", whole(activity), breather.restsBelow)
			}
		}
	} else {
		reason = apply_effect(world, action, amount, group)
		if reason != "" {
			if error != nil {
				error^ = reason
			}
			return nil
		}
		leave_traces(world, action, group)
		/* a declared effect read the truth to be built: stale when it comes
		 * to commit, it is resolved again (as an activity's is, BGActivities) */
		if effect == "" do group.again, group.action, group.amount = perform_again, action, amount
	}
	committer_submit(committer, group)
	return group
}


/* An instant operation's declared effect, rejected because what it read is
 * no longer so: its group built afresh from the truth as it now is. nil if
 * what the operation requires no longer holds: it has failed. */
@(private = "file")
perform_again :: proc(world: ^World, was: ^Proposal_Group) -> ^Proposal_Group {
	group := proposal_group_group_with_phase(.Action, proposal_group_source(was))
	proposal_group_set_actor(group, was.actor)
	proposal_group_set_weight(group, was.weight)
	if apply_effect(world, was.action, was.amount, group) != "" do return nil
	leave_traces(world, was.action, group)
	group.again, group.action, group.amount, group.tries = perform_again, was.action, was.amount, was.tries + 1
	return group
}

package lab

/*
 * BGView — what an actor can bind and what it can tell about each entity:
 * the stub of the knowledge view (ACTIONS.md §3, KNOWLEDGE.md §13) until
 * perception exists. It is the truth projection, limited the way the menu
 * contract requires:
 *
 *   - formulate: only entities in reach can be bound (the actor's tile and
 *     the eight around it, and anything inside, held, or installed there)
 *   - appearsBeginnable: a description carries only fields whose @field
 *     flags say they can be perceived; hidden fields stay open, so they make
 *     a match unknown, and unknown never excludes
 *
 * (ported from the Objective-C lab's act/BGView.m)
 */

import "core:fmt"
import "core:strings"
import tri "../../triangle/odin/triangle"


View :: struct {
	using object: Object,
	world:        ^World,
	actor:        Entity_ID,
}


/* How many of an agent's hands are free. */
free_hands :: proc(world: ^World, agent: Entity_ID) -> i32 {
	a:    ^Agent
	held: [8]Entity_ID
	n:    uint

	a = (^Agent)(world_record(world, world_kind_named(world, "Agent"), agent))
	if a == nil do return 0
	n = world_entities_at(world, agent, .Held_By, raw_data(held[:]), 8)
	used: i32
	for e in held[:min(n, 8)] do if world_location_of(world, e).slot != BG_BACK do used += 1      /* the back is no hand */
	return i32(a.hands) - used
}


/* Where a worn pack is carried (content/carrying/): held, by no hand. */
BG_BACK :: i32(8)


/* All an agent carries, in grams: what it holds, in its hands and on its
 * back, and what is in that. */
carried_mass :: proc(world: ^World, agent: Entity_ID) -> i64 {
	held:   [8]Entity_ID
	inside: [16]Entity_ID
	total:  i64
	for e in held[:min(world_entities_at(world, agent, .Held_By, raw_data(held[:]), 8), 8)] {
		total += world_mass_of(world, e)
		for c in inside[:min(world_entities_at(world, e, .In, raw_data(inside[:]), 16), 16)] do total += world_mass_of(world, c)
	}
	return total
}


/* The first free hand of an agent, or -1. */
free_hand :: proc(world: ^World, agent: Entity_ID) -> i32 {
	a:     ^Agent
	held:  [8]Entity_ID
	i:     uint
	n:     uint
	hand:  i32
	taken: bool

	a = (^Agent)(world_record(world, world_kind_named(world, "Agent"), agent))
	if a == nil do return -1
	n = world_entities_at(world, agent, .Held_By, raw_data(held[:]), 8)
	for hand = 0; i64(hand) < a.hands; hand += 1 {
		taken = false
		for i = 0; i < n && i < 8 && !taken; i += 1 {
			taken = world_location_of(world, held[i]).slot == hand
		}
		if !taken do return hand
	}
	return -1
}


// +viewOf:inWorld:, autoreleased.
view_of :: proc(actor: Entity_ID, world: ^World) -> ^View {
	view: ^View

	view       = autorelease(object_new(View, view_dealloc))
	view.world = retain(world)
	view.actor = actor
	return view
}


view_dealloc :: proc(self: ^View) {
	release(self.world)
}


view_actor :: proc(self: ^View) -> Entity_ID {
	return self.actor
}


/* The tile something is on, through whatever holds it; NO if none. */
@(private = "file")
ground_tile :: proc(world: ^World, e: Entity_ID, tile: ^Location) -> bool {
	e := e
	loc:   Location
	guard: uint

	for guard = 0; guard < 64; guard += 1 {
		loc = world_location_of(world, e)
		if loc.form == .On_Tile {
			tile^ = loc
			return true
		}
		if loc.form == .None || loc.place == 0 do return false
		e = loc.place
	}
	return false
}


view_can_reach :: proc(self: ^View, entity: Entity_ID, range: i32 = 1) -> bool {
	here:  Location
	there: Location

	if !world_is_live(self.world, entity) || !world_is_physical(self.world, entity) do return false
	if !ground_tile(self.world, self.actor, &here) || !ground_tile(self.world, entity, &there) do return false
	/* an area, from on it or beside it (content/things.tri) */
	if world_location_of(self.world, entity).form == .On_Tile {
		east, south := world_area_extent(self.world, entity)
		there = area_nearest(there, east, south, here)
	}
	return here.level == there.level && abs(here.x - there.x) <= range && abs(here.y - there.y) <= range
}


/* entities in reach, the actor included, in ID order. Settled: `out` is a
 * [^]Entity_ID filled up to max_. */
view_reachable :: proc(self: ^View, out: [^]Entity_ID, max_: uint) -> uint {
	bodies: ^Store
	e:      Entity_ID
	i:      uint
	n:      uint

	bodies = world_store_for_kind(self.world, world_kind_named(self.world, "Body"))
	n      = 0
	for i = 0; i < store_count(bodies); i += 1 {
		e = store_entity_at_index(bodies, i)
		if !view_can_reach(self, e) do continue
		if n < max_ do out[n] = e
		n += 1
	}
	return n
}


@(private = "file")
append_text :: proc(s: ^strings.Builder, text: cstring) {
	strings.write_string(s, "\"")
	if text != nil {
		for p := ([^]u8)(text); p[0] != 0; p = p[1:] {
			if p[0] != '"' && p[0] != '\n' do strings.write_byte(s, p[0])
		}
	}
	strings.write_string(s, "\"")
}


@(private = "file")
append_place :: proc(s: ^strings.Builder, loc: Location) {
	loc := loc
	#partial switch loc.form {
	case .On_Tile:
		fmt.sbprintf(s, "#OnTile & {{ x: %d, y: %d, level: %d }}", loc.x, loc.y, loc.level)
	case .In:
		fmt.sbprintf(s, "#Inside & {{ container: ref(%d) }}", loc.place)
	case .Held_By:
		fmt.sbprintf(s, "#Held & {{ by: ref(%d), hand: %d }}", loc.place, loc.slot)
	case .Part_Of:
		fmt.sbprintf(s, "#Installed & {{ assembly: ref(%d), role: ", loc.place)
		append_text(s, location_role_c(&loc))
		fmt.sbprintf(s, ", index: %d }}", loc.slot)
	case:
		strings.write_string(s, "#Place")
	}
}


/* its parts: the kind (a type expression), and the perceivable fields
 * ("mass: 90g, material: \"iron\", ..."), without id or place. "" where the
 * Objective-C returned nil (no such entity). */
view_kind_of :: proc(self: ^View, entity: Entity_ID) -> string {
	return kind_of_entity(self.world, entity)
}


/* A kind seen at a glance (content/knowledge.tri's #Seen, KNOWLEDGE.md
 * decision 17): its type, and where it stands among the components, which
 * orders a conjunction of them. */
Seen_Kind :: struct {
	type:  tri.Type,
	name:  cstring,
	order: int,
}

/* The `seen` family, in the components' order, then the family's. */
seen_kinds_load :: proc(content: ^tri.Content) -> [dynamic]Seen_Kind {
	kinds  := make([dynamic]Seen_Kind)
	family := tri.family_index(content, "seen")
	for i: uint = 0; family != nil && i < tri.index_count(family); i += 1 {
		node := tri.pattern(content, cstring(tri.index_tag(family, i)))
		buf: [128]u8
		v := tri.at(content, node, "kindOf") if node != nil else nil
		n := tri.print(content, v, &buf[0], size_of(buf)) if v != nil else 0
		if n < 3 do continue
		buf[n - 1] = 0
		t := tri.type_named(content, cstring(&buf[1]))
		if t == tri.Type(0xFFFFFFFF) do continue
		order := COMPONENT_COUNT + int(i)
		for k in 0 ..< COMPONENT_COUNT do if tri.type_named(content, COMPONENTS[k].type) == t do order = k
		append(&kinds, Seen_Kind{t, tri.type_name(content, t), order})
	}
	for i := 1; i < len(kinds); i += 1 {
		for j := i; j > 0 && kinds[j].order < kinds[j - 1].order; j -= 1 do kinds[j], kinds[j - 1] = kinds[j - 1], kinds[j]
	}
	return kinds
}

/* What an entity is, as the senses can tell it (KNOWLEDGE.md decision 17):
   the seen kinds its blueprint's type, or a component it has, is a kind
   of, and of those only the most specific (#Agent says #Body). One left is
   the kind; more, their conjunction; none, #Thing. An inner state (a
   stomach) is no seen kind, so it doesn't show; a kind no list names shows
   as the seen kinds above it. What has no body (a claim, a bond) is its
   type. "" for no entity. Worked out once for each entity, and kept
   (World.seenAs) until it gains or loses a component. */
kind_of_entity :: proc(world: ^World, entity: Entity_ID) -> string {
	info := world_info(world, entity)
	if info == nil do return ""
	if v, ok := world.seenAs[entity]; ok && v.blueprint == info.blueprint do return v.kind
	kind := kind_of_entity_worked_out(world, entity, info)
	world_forget_seen_as(world, entity)
	world.seenAs[entity] = Seen_As{info.blueprint, strings.clone(kind)}
	return kind
}


@(private = "file")
kind_of_entity_worked_out :: proc(world: ^World, entity: Entity_ID, info: ^Entity_Info) -> string {
	tc      := world_tri(world)
	pattern := tri.pattern(tc, info.blueprint)
	if pattern == nil do return "#Thing"
	blueprint := tri.node_type(pattern)
	/* what has no body isn't seen at all: it is what it is (a claim, a
	 * bond), for the views that describe it */
	if world_record(world, world_kind_named(world, "Body"), entity) == nil {
		name := tri.type_name(tc, blueprint)
		return string(name) if name != nil && !strings.contains_any(string(name), "[ &") else "#Thing"
	}
	applies := make([dynamic]int, context.temp_allocator)
	for s, i in world.seen {
		is := tri.subtype(tc, blueprint, s.type) != 0
		for k: uint = 0; !is && k < world_kind_count(world); k += 1 {
			if world_record(world, k, entity) == nil do continue
			is = tri.subtype(tc, tri.type_named(tc, world_kind_info(world, k).type), s.type) != 0
		}
		if is do append(&applies, i)
	}
	kept := make([dynamic]cstring, context.temp_allocator)
	for a in applies {
		implied := false
		for b in applies {
			if b != a && tri.subtype(tc, world.seen[b].type, world.seen[a].type) != 0 do implied = true
		}
		if !implied do append(&kept, world.seen[a].name)
	}
	if len(kept) == 0 do return "#Thing"
	if len(kept) == 1 do return string(kept[0])
	s := strings.builder_make(context.temp_allocator)
	strings.write_string(&s, "#Thing")
	for t in kept do fmt.sbprintf(&s, " & %s", t)
	return strings.to_string(s)
}


/* The field that says what `f` looks like (KNOWLEDGE.md §4), "appears(f)",
 * if it says anything other than "natural"; otherwise `f`. */
@(private = "file")
appearance_of :: proc(kind: ^Component_Info, f: ^Field_Info, record: rawptr, natural: u32) -> ^Field_Info {
	g:    ^Field_Info
	i:    uint
	buf:  [64]u8
	flag: string

	flag = fmt.bprintf(buf[:len(buf) - 1], "appears(%s)", f.name)      // snprintf's 63 and a NUL
	for i = 0; i < kind.nfields; i += 1 {
		g = &kind.fields[i]
		if g.value == f.value && strings.contains(string(g.flags), flag) && g.value == VALUE_TYPE &&
		   (^u32)(rawptr(uintptr(record) + g.offset))^ != 0 && (^u32)(rawptr(uintptr(record) + g.offset))^ != natural {
			return g
		}
	}
	return f
}


view_features_of :: proc(self: ^View, entity: Entity_ID) -> string {
	return view_features_of_all(self, entity, false)
}


/* every field the inspector sees, hidden ones too: the omniscient stub's */
view_features_of_all :: proc(self: ^View, entity: Entity_ID, all: bool) -> string {
	kind:   ^Component_Info
	f:      ^Field_Info
	record: rawptr
	s:      strings.Builder
	buf:    [64]u8
	i:      uint
	k:      uint

	s = strings.builder_make(context.temp_allocator)
	if world_record(self.world, world_kind_named(self.world, "Agent"), entity) != nil {
		fmt.sbprintf(&s, "freeHands: %d", free_hands(self.world, entity))
	}
	/* the perceivable fields of each component; the rest stay open */
	for k = 0; k < world_kind_count(self.world); k += 1 {
		record = world_record(self.world, k, entity)
		if record == nil do continue
		kind = world_kind_info(self.world, k)
		for i = 0; i < kind.nfields; i += 1 {
			f = &kind.fields[i]
			if !strings.contains(string(f.flags), "perceive") &&
			   !(all && strings.contains(string(f.flags), "inspect") && strings.contains(string(f.flags), "content")) {
				continue
			}
			fmt.sbprintf(&s, "%s%s: ", ", " if strings.builder_len(s) != 0 else "", f.name)
			/* what the senses report: its appearance, if it has one */
			f = appearance_of(kind, f, record, u32(tri.type_named(world_tri(self.world), "\"natural\"")))
			at := rawptr(uintptr(record) + f.offset)
			switch f.value {
			case VALUE_QUANTITY:
				tri.format_quantity(f.kind, (^i64)(at)^, raw_data(buf[:]), len(buf))
				fmt.sbprintf(&s, "%s", cstring(&buf[0]))
			case VALUE_TYPE:
				fmt.sbprintf(&s, "%s", tri.type_name(world_tri(self.world), (^u32)(at)^))
			case VALUE_BOOL:
				strings.write_string(&s, "true" if (^bool)(at)^ else "false")
			case VALUE_REF:
				fmt.sbprintf(&s, "ref(%d)", (^u64)(at)^)
			case VALUE_TEXT:
				append_text(&s, (^cstring)(at)^)
			case:
				strings.write_string(&s, "_")
			}
		}
	}
	return strings.to_string(s)
}


/* The truth projection of an entity (EFFECTS.md): its description as it
 * is, every field of every component it has, whether or not anyone could
 * perceive it, and its material as it is, not as it appears. What a
 * declared effect is resolved against; never an agent's to reason from.
 * "" for no such entity. */
truth_describe_entity :: proc(world: ^World, entity: Entity_ID) -> string {
	buf: [64]u8

	if world_info(world, entity) == nil do return ""
	s := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&s, "%s & {{ id: ref(%d)", kind_of_entity(world, entity), entity)
	if world_is_physical(world, entity) {
		strings.write_string(&s, ", place: ")
		append_place(&s, world_location_of(world, entity))
	}
	if world_record(world, world_kind_named(world, "Agent"), entity) != nil {
		fmt.sbprintf(&s, ", freeHands: %d", free_hands(world, entity))
	}
	for k: uint = 0; k < world_kind_count(world); k += 1 {
		record := world_record(world, k, entity)
		if record == nil do continue
		kind := world_kind_info(world, k)
		for i: uint = 0; i < kind.nfields; i += 1 {
			f  := &kind.fields[i]
			at := rawptr(uintptr(record) + f.offset)
			switch f.value {
			case VALUE_QUANTITY:
				tri.format_quantity(f.kind, (^i64)(at)^, raw_data(buf[:]), len(buf))
				fmt.sbprintf(&s, ", %s: %s", f.name, cstring(&buf[0]))
			case VALUE_TYPE:
				/* an enum not yet set is no value: left open */
				if name := tri.type_name(world_tri(world), (^u32)(at)^); (^u32)(at)^ != 0 && name != nil {
					fmt.sbprintf(&s, ", %s: %s", f.name, name)
				}
			case VALUE_BOOL:
				fmt.sbprintf(&s, ", %s: %s", f.name, "true" if (^bool)(at)^ else "false")
			case VALUE_REF:
				fmt.sbprintf(&s, ", %s: ref(%d)", f.name, (^u64)(at)^)
			case VALUE_TEXT:
				fmt.sbprintf(&s, ", %s: ", f.name)
				append_text(&s, (^cstring)(at)^)
			}
		}
	}
	strings.write_string(&s, " }")
	return strings.to_string(s)
}


/* the entity's description, as a Triangle expression; "" where the
 * Objective-C returned nil (no such entity) */
view_describe_entity :: proc(self: ^View, entity: Entity_ID) -> string {
	s:        strings.Builder
	features: string

	if world_info(self.world, entity) == nil do return ""
	s = strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&s, "%s & {{ id: ref(%d)", view_kind_of(self, entity), entity)
	if world_is_physical(self.world, entity) {
		strings.write_string(&s, ", place: ")
		append_place(&s, world_location_of(self.world, entity))
	}
	features = view_features_of(self, entity)
	if len(features) != 0 do fmt.sbprintf(&s, ", %s", features)
	strings.write_string(&s, " }")
	return strings.to_string(s)
}

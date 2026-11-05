package lab

// BGKnowledge — what agents know (KNOWLEDGE.md): the system, part 1 of its
// implementation (know/BGKnowledge.m, lines 1720–3876): making it, light and
// sight, recognition's helpers, salience, the stores by agent, what a claim
// heard does, settling testimony, merging identities, perceiving traces, and
// interpretation. The header's types, the instance structs, the file's first
// statics and the store are the part before this; perceiving a boundary,
// saves and the developer's view, the part after.
//
// BGKnowledge.m's static functions and variables cross the split, so each is
// package-level @(private), named know_ + its C name in snake case. Methods,
// private ones too, are named by the class rule.
//
// What a perception phase changed (an NSMutableArray of lines, `news`) is
// `^[dynamic]string`; the store keeps it, so each line put in it is cloned
// into context.allocator (k1_say), as anything an object keeps is.

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import tri "../../triangle/odin/triangle"


// --- this file's own helpers -------------------------------------------------

// [news addObject:line]: the news is kept by the store, so the line is
// cloned.
@(private = "file")
k1_say :: proc(news: ^[dynamic]string, line: string) {
	append(news, strings.clone(line))
}

// snprintf( buf + strlen( buf), size - strlen( buf), "%s", s): appended,
// cut to fit, NUL-terminated.
@(private = "file")
k1_cat :: proc(buf: [^]u8, size: uint, s: string) {
	used: uint
	room: uint
	n: uint

	used = uint(len(cstring(buf)))
	if used >= size do return
	room = size - used
	n = min(uint(len(s)), room - 1)
	if n > 0 do mem.copy(&buf[used], raw_data(s), int(n))
	buf[used + n] = 0
}

// What snprintf into a buffer of `size` bytes keeps of a text.
@(private = "file")
k1_clip :: proc(s: string, size: int) -> string {
	return s[:min(len(s), size - 1)]
}

// A C string from a buffer tri_print filled.
@(private = "file")
k1_buf :: #force_inline proc(buf: []u8) -> cstring {
	return cstring(&buf[0])
}


/* --- the system ------------------------------------------------------------------ */

knowledge_init_with_world :: proc(world: ^World) -> ^Knowledge {
	self := object_new(Knowledge, knowledge_dealloc)
	self.world      = retain(world)
	self.stores     = make([dynamic]^Knowledge_Store)
	self.eventsSeen = world_event_count(world)
	self.ambient    = 2
	self.verifyInterpretation = verify_interpretation
	return self
}


/* Set by the tests: every Knowledge made weighs what incremental
 * interpretation skips, and says here what it would have changed
 * (PERFORMANCE.md decision 2). Each line the array's own. */
verify_interpretation: bool
interpretation_missed: [dynamic]string


knowledge_dealloc :: proc(self: ^Knowledge) {
	release(self.world)
	for s in self.stores do release(s)
	delete(self.stores)
	free(self.touched)
	// the caches keep their keys and texts cloned
	for k, v in self.blurred {
		delete(k)
		delete(v)
	}
	delete(self.blurred)
	for _, v in self.features do delete(v)
	delete(self.features)
	free(self.perceived)
	wakes_free(self.perceiveWakes)
	wakes_free(self.forgetWakes)
	object_release(self.light)
	free(self.ancestry)
	for rule in self.rules do delete(rule.premises)
	delete(self.rules)
}


knowledge_name :: proc(self: ^Knowledge) -> string {
	return "knowledge"
}


knowledge_set_omniscient :: proc(self: ^Knowledge, flag: bool) {
	self.omniscient = flag
}


knowledge_set_compact_always :: proc(self: ^Knowledge, flag: bool) {
	self.compactAlways = flag
}


knowledge_set_dusk :: proc(self: ^Knowledge, flag: bool) {
	self.ambient = 1 if flag else 2
}


knowledge_set_ambient :: proc(self: ^Knowledge, light: i32) {
	self.ambient = 0 if light < 0 else 2 if light > 2 else light
}


// `light` is the light domain (a ^Light): retained.
knowledge_set_light :: proc(self: ^Knowledge, light: rawptr) {
	object_autorelease(self.light)
	self.light = object_retain(light)
}


knowledge_light_at :: proc(self: ^Knowledge, tile: Location) -> i32 {
	lamp: ^Lamp
	lamps: ^Store
	at: Location
	i: uint

	if self.light != nil do return light_at(self.world, tile, world_time(self.world).ms)
	if self.ambient >= 2 do return self.ambient
	lamps = world_store_for_kind(self.world, world_kind_named(self.world, "Lamp"))
	for i = 0; i < store_count(lamps); i += 1 {
		lamp = (^Lamp)(store_record_at_index(lamps, i))
		if lamp.shining && know_ground_tile(self.world, store_entity_at_index(lamps, i), &at) && at.level == tile.level &&
		   i64(abs(at.x - tile.x)) <= lamp.reach && i64(abs(at.y - tile.y)) <= lamp.reach {
			return 2
		}
	}
	return self.ambient
}


/* Whether nothing opaque stands between two tiles of a level (TERRAIN.md):
 * the cells a straight line passes through, the ends apart (a wall itself
 * is seen), one way or the other, so sight is mutual. */
@(private)
know_line_clear :: proc(t: ^Terrain, x0: i32, y0: i32, x1: i32, y1: i32, z: i32) -> bool {
	dx: i32
	dy: i32
	sx: i32
	sy: i32
	err: i32
	e2: i32
	x: i32
	y: i32

	dx  = abs(x1 - x0)
	dy  = -abs(y1 - y0)
	sx  = 1 if x0 < x1 else -1
	sy  = 1 if y0 < y1 else -1
	err = dx + dy
	x   = x0
	y   = y0
	for {
		e2 = 2 * err
		if e2 >= dy {
			err += dy
			x   += sx
		}
		if e2 <= dx {
			err += dx
			y   += sy
		}
		if x == x1 && y == y1 do return true
		if terrain_opaque(t, x, y, z) do return false
	}
}


/* Whether a tile is in the agent's line of sight: on its level, within
 * BG_SIGHT, and nothing opaque between (light aside). */
knowledge_in_sight :: proc(self: ^Knowledge, tile: Location, here: Location) -> bool {
	t: ^Terrain

	if self.omniscient do return true
	if tile.level != here.level || abs(tile.x - here.x) > BG_SIGHT || abs(tile.y - here.y) > BG_SIGHT do return false
	if abs(tile.x - here.x) <= 1 && abs(tile.y - here.y) <= 1 do return true
	t = world_terrain(self.world)
	return t == nil || know_line_clear(t, here.x, here.y, tile.x, tile.y, here.level) ||
	       know_line_clear(t, tile.x, tile.y, here.x, here.y, here.level)
}


/* Whether the agent here can see the tile: in its line of sight, and lit,
 * or within arm's reach. */
/* What might be in sight from a tile: what stands on the ground within
 * BG_SIGHT of it (the world's spatial index, TERRAIN.md), and what is in,
 * on, held by or part of that, all the way down; everything, for an
 * omniscient eye. Malloc'd into *out; returns how many. */
knowledge_candidates_from :: proc(self: ^Knowledge, here: Location, out: ^[^]Entity_ID) -> uint {
	bodies: ^Store
	list: [^]Entity_ID
	n: uint
	i: uint

	if self.omniscient {
		bodies = world_store_for_kind(self.world, world_kind_named(self.world, "Body"))
		n      = store_count(bodies)
		list   = make([^]Entity_ID, n if n != 0 else 1)
		for i = 0; i < n; i += 1 do list[i] = store_entity_at_index(bodies, i)
		out^ = list
		return n
	}
	return world_things_near(self.world, here, BG_SIGHT, out)
}


knowledge_sees :: proc(self: ^Knowledge, tile: Location, here: Location) -> bool {
	if self.omniscient do return true
	if !knowledge_in_sight(self, tile, here) do return false
	if abs(tile.x - here.x) <= 1 && abs(tile.y - here.y) <= 1 do return true
	return knowledge_light_at(self, tile) > 0
}


/* How long a feature usually lasts (content/knowledge.tri): long, unless
 * said. */
knowledge_persistence_of :: proc(self: ^Knowledge, feature: cstring) -> i64 {
	tc: ^tri.Content
	family: ^tri.Index
	i: uint
	lo: i64
	hi: i64
	name: [64]u8

	tc     = world_tri(self.world)
	family = tri.family_index(tc, "persistence")
	for i = 0; family != nil && i < tri.index_count(family); i += 1 {
		p: ^tri.Node

		p = tri.pattern(tc, cstring(tri.index_tag(family, i)))
		if tri.at(tc, p, "feature") != nil && tri.print(tc, tri.at(tc, p, "feature"), &name[0], size_of(name)) > 2 {
			name[len(k1_buf(name[:])) - 1] = 0
			if string(cstring(&name[1])) == string(feature) && tri.node_interval(tri.at(tc, p, "persists"), &lo, &hi) != 0 {
				return lo
			}
		}
	}
	return 10000 * 86400000
}


/* Where what memory keeps of the referent and the percept conflict, every
 * path, into `paths` ("coat, bent"); how many, and how many agree. */
// `paths` is a buffer of `length` bytes.
knowledge_conflicts_of :: proc(self: ^Knowledge, r: ^Referent, store: ^Knowledge_Store, kind: string, features: string,
                               paths: [^]u8, length: uint, agree: ^i32) -> i32 {
	x: ^tri.Node
	y: ^tri.Node
	found: [8][256]u8
	n: uint
	i: uint

	/* both from the store's knowledge arena */
	x      = knowledge_store_parsed(store, fmt.tprintf("%s & {{ %s }}", kind, know_lasting(knowledge_store_recall(store, r))))
	y      = knowledge_store_parsed(store, fmt.tprintf("%s & {{ %s }}", kind, know_lasting(features)))
	n      = tri.conflicts(world_tri(self.world), x, y, &found[0], 8) if x != nil && y != nil else 0
	paths[0] = 0
	for i = 0; i < n; i += 1 {
		k1_cat(paths, length, fmt.tprintf("%s%s", ", " if i != 0 else "", k1_buf(found[i][:])))
	}
	agree^ = i32(len(split_top_level(know_lasting(features)))) - i32(n)
	return i32(n)
}


/* Whether memory holds anything concrete of the referent to know it by: a
 * feature with one value. One told of only as "someone" has nothing, and a
 * percept matching it is a weak match (KNOWLEDGE.md §6), not a binding. */
knowledge_knows_anything_of :: proc(self: ^Knowledge, r: ^Referent, store: ^Knowledge_Store) -> bool {
	pairs: []string
	pair: string
	k: int

	pairs = split_top_level(knowledge_store_recall(store, r))
	for k = 0; k < len(pairs); k += 1 {
		pair = pairs[k]
		if !ns_contains(pair, "|") && !ns_contains(pair, ">=") &&
		   !ns_contains(pair, "<=") && !ns_contains(pair, ": #") &&
		   !ns_has_prefix(pair, "id:") && !ns_has_prefix(pair, "place:") {
			return true
		}
	}
	return false
}


/* Whether every conflict is on a feature that changes within a week. */
knowledge_short_lived :: proc(self: ^Knowledge, paths: cstring) -> bool {
	each: []string
	i: int

	each = split_top_level(ns_string(paths))
	for i = 0; i < len(each); i += 1 {
		if knowledge_persistence_of(self, ns_utf8(each[i])) > 7 * 86400000 do return false
	}
	return len(each) > 0
}


/* The percept's features, unified with what memory keeps, so a match keeps
 * the more specific; the percept's, if they don't unify. */
knowledge_unified :: proc(self: ^Knowledge, r: ^Referent, store: ^Knowledge_Store, kind: string, features: string) -> string {
	both: ^tri.Node
	arena: ^tri.Arena
	out: strings.Builder
	remembered: string
	keys: [64][32]u8
	printed: [512]u8
	n: uint
	k: uint
	j: uint

	remembered = knowledge_store_recall(store, r)
	arena      = tri.arena_new()
	both       = tri.value(world_tri(self.world), ns_utf8(fmt.tprintf("%s & {{ %s }} & {{ %s }}", kind, remembered, features)),
	                       arena, nil, 0)
	if both == nil {
		tri.arena_free(arena)
		return features
	}
	/* the features either had, as unified */
	n = know_feature_keys(ns_utf8(remembered), &keys[0], 32)
	n += know_feature_keys(ns_utf8(features), &keys[n], 32)
	out = strings.builder_make(context.temp_allocator)
	for k = 0; k < n; k += 1 {
		for j = 0; j < k && string(k1_buf(keys[j][:])) != string(k1_buf(keys[k][:])); j += 1 {
		}
		if j < k || tri.at(world_tri(self.world), both, k1_buf(keys[k][:])) == nil do continue
		tri.print(world_tri(self.world), tri.at(world_tri(self.world), both, k1_buf(keys[k][:])), &printed[0], size_of(printed))
		fmt.sbprintf(&out, "%s%s: %s", ", " if strings.builder_len(out) != 0 else "", k1_buf(keys[k][:]), k1_buf(printed[:]))
	}
	tri.arena_free(arena)
	return strings.to_string(out)
}


/* The percept's features as seen from `distance` tiles: each feature with
 * an acuity (content/knowledge.tri) blurred `blur` steps for each tile
 * beyond arm's reach. *blurred is set if any was. */
knowledge_blur :: proc(self: ^Knowledge, features: string, kind: cstring, distance: i32, blurred: ^bool) -> string {
	node: ^tri.Node
	p: ^tri.Node
	wide: ^tri.Node
	tc: ^tri.Content
	family: ^tri.Index
	arena: ^tri.Arena
	out: strings.Builder
	pairs: []string
	pair: string
	k: int
	i: uint
	lo: i64
	hi: i64
	name: [64]u8
	printed: [256]u8

	key: string
	known: string
	ok: bool
	didBlur: bool

	tc     = world_tri(self.world)
	family = tri.family_index(tc, "acuity")
	if distance <= 1 || family == nil || tri.index_count(family) == 0 do return features
	/* the same features of the same kind, from as far, blur the same: kept,
	 * so a crowd seen again and again is described once (a cache, bounded) */
	key = fmt.tprintf("%s|%d|%s", kind, distance, features)
	if known, ok = self.blurred[key]; ok {
		if ns_has_prefix(known, "1") do blurred^ = true
		return strings.clone(known[1:], context.temp_allocator)
	}
	didBlur = false
	arena   = tri.arena_new()
	node    = tri.value(tc, ns_utf8(fmt.tprintf("%s & {{ %s }}", kind, features)), arena, nil, 0)
	pairs = split_top_level(features)
	out   = strings.builder_make(context.temp_allocator)
	for k = 0; k < len(pairs); k += 1 {
		pair = pairs[k]
		for i = 0; node != nil && i < tri.index_count(family); i += 1 {
			p = tri.pattern(tc, cstring(tri.index_tag(family, i)))
			if tri.at(tc, p, "feature") == nil || tri.print(tc, tri.at(tc, p, "feature"), &name[0], size_of(name)) < 3 do continue
			name[len(k1_buf(name[:])) - 1] = 0
			if !ns_has_prefix(pair, fmt.tprintf("%s: ", cstring(&name[1]))) ||
			   tri.node_interval(tri.at(tc, p, "blur"), &lo, &hi) == 0 {
				continue
			}
			wide = tri.generalize(tc, node, cstring(&name[1]), i32(lo) * (distance - 1), arena)
			if wide != nil && tri.at(tc, wide, cstring(&name[1])) != nil {
				tri.print(tc, tri.at(tc, wide, cstring(&name[1])), &printed[0], size_of(printed))
				pair     = fmt.tprintf("%s: %s", cstring(&name[1]), k1_buf(printed[:]))
				blurred^ = true
				didBlur  = true
			}
		}
		fmt.sbprintf(&out, "%s%s", ", " if strings.builder_len(out) != 0 else "", pair)
	}
	tri.arena_free(arena)
	if len(self.blurred) > 65536 {
		for bk, bv in self.blurred {
			delete(bk)
			delete(bv)
		}
		clear(&self.blurred)
	}
	self.blurred[strings.clone(key)] = strings.clone(fmt.tprintf("%d%s", 1 if didBlur else 0, strings.to_string(out)))
	return strings.to_string(out)
}


// Not retained.
knowledge_set_concerns :: proc(self: ^Knowledge, concerns: Concerns) {
	self.concerns = concerns
}


knowledge_concerns :: proc(self: ^Knowledge) -> Concerns {
	return self.concerns
}


/* --- salience ------------------------------------------------------------------- */

/* What the agent's running activities demand of its attention. */
knowledge_attention_of :: proc(self: ^Knowledge, agent: Entity_ID) -> i32 {
	record: ^Activity
	mine: [^]Entity_ID
	tc: ^tri.Content
	v: ^tri.Node
	n: uint
	i: uint
	lo: i64
	hi: i64
	demand: i32

	tc     = world_tri(self.world)
	mine   = world_copy_activities_of(self.world, agent, &n)
	demand = 0
	for i = 0; i < n; i += 1 {
		record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), mine[i]))
		if record == nil || record.status != ACTIVITYSTATUS_RUNNING || record.operation == nil do continue
		v = tri.at(tc, tri.pattern(tc, record.operation), "attention")
		if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi && lo > i64(demand) do demand = i32(lo)
	}
	free(mine)
	return demand
}


/* Whether the description is entailed by one of the patterns. */
// A nil description is "".
knowledge_concerns_description :: proc(self: ^Knowledge, patterns: []string, description: string) -> bool {
	d: ^tri.Node
	p: ^tri.Node
	result: tri.Match_Result
	tc: ^tri.Content
	arena: ^tri.Arena
	i: int
	yes: bool

	if len(patterns) == 0 || description == "" do return false
	tc    = world_tri(self.world)
	arena = tri.arena_new()
	d     = tri.value(tc, ns_utf8(description), arena, nil, 0)
	yes   = false
	for i = 0; d != nil && i < len(patterns) && !yes; i += 1 {
		p   = tri.value(tc, ns_utf8(patterns[i]), arena, nil, 0)
		yes = p != nil && tri.match(tc, p, d, &result) == .Entailed
	}
	tri.arena_free(arena)
	return yes
}


/* What something said is about: its `what`, printed. */
// "" for nil: its only caller (concerns:description:) takes "" as nil.
knowledge_topic_of :: proc(self: ^Knowledge, content: cstring) -> string {
	said: ^tri.Node
	arena: ^tri.Arena
	topic: string
	printed: [2048]u8

	arena = tri.arena_new()
	said  = tri.value(world_tri(self.world), content, arena, nil, 0) if content != nil else nil
	topic = ""
	if said != nil && tri.at(world_tri(self.world), said, "what") != nil {
		tri.print(world_tri(self.world), tri.at(world_tri(self.world), said, "what"), &printed[0], size_of(printed))
		topic = strings.clone_from_cstring(k1_buf(printed[:]), context.temp_allocator)
	}
	tri.arena_free(arena)
	return topic
}


knowledge_hear :: proc(self: ^Knowledge, claim: cstring, speaker: u32, agent: Entity_ID) {
	store: ^Knowledge_Store

	store = knowledge_store_of(self, agent)
	knowledge_believe(self, claim, speaker, 0, 0, world_time(self.world).ms, store, knowledge_store_mutable_news(store))
}


knowledge_store_of :: proc(self: ^Knowledge, agent: Entity_ID) -> ^Knowledge_Store {
	store: ^Knowledge_Store
	lo: uint
	hi: uint
	i: uint

	/* by halving: the stores are in agent order */
	lo = 0
	hi = uint(len(self.stores))
	for lo < hi {
		i = (lo + hi) / 2
		if self.stores[i].agent < agent {
			lo = i + 1
		} else {
			hi = i
		}
	}
	if lo < uint(len(self.stores)) {
		store = self.stores[lo]
		if store.agent == agent do return store
	}
	store = autorelease(knowledge_store_init_with_agent(agent, self.world))
	inject_at(&self.stores, int(lo), retain(store))
	return store
}


/* --- perception ------------------------------------------------------------------ */

@(private)
know_contains :: proc(set: [^]Entity_ID, n: uint, e: Entity_ID) -> bool {
	i: uint

	for i = 0; i < n; i += 1 {
		if set[i] == e do return true
	}
	return false
}


@(private)
Seen :: struct {
	entity: Entity_ID,
	depth:  i32,
}


/* An event noticed, waiting for attention: its observation, where it is in
 * history, and the news it would make. */
@(private)
Candidate :: struct {
	o:     Observation,
	event: uint,
	news:  []string,      /* autoreleased: the temporary allocator */
}


/* the most salient first; in event order among equals */
// qsort's comparator as slice.sort_by's: whether x comes before y.
@(private)
know_cmp_candidates :: proc(x: Candidate, y: Candidate) -> bool {
	if x.o.salience != y.o.salience do return x.o.salience > y.o.salience
	return x.event < y.event
}


// qsort's comparator as slice.sort_by's: whether x comes before y.
@(private)
know_cmp_seen :: proc(x: Seen, y: Seen) -> bool {
	if x.depth != y.depth do return x.depth < y.depth
	return x.entity < y.entity
}


@(private)
know_node_int :: proc(tc: ^tri.Content, node: ^tri.Node, path: cstring, value: ^i64) -> bool {
	v: ^tri.Node
	hi: i64

	v = tri.at(tc, node, path) if node != nil else nil
	return v != nil && tri.node_interval(v, value, &hi) != 0 && value^ == hi
}


/* The features a printed description fixes, without its id and place: what
 * a claim says of a thing, as a referent keeps them. A field left open
 * prints as its bare type, and says nothing. */
// Malloc'd: the caller frees it (delete).
@(private)
know_concrete_features :: proc(printed: cstring) -> cstring {
	@(static, rodata) open := [?]string{"int", "fixed", "text", "ref", "bool", "atom", "mass", "length", "time",
	                                    "force", "torque", "heat", "temperature", "volume", "amount", "_"}
	out: strings.Builder
	s: string
	start: int
	end: int
	p: int
	field: int
	pair: string
	key: string
	value: string
	colon: uint
	depth: i32
	k: int
	quoted: bool
	keep: bool

	out   = strings.builder_make(context.temp_allocator)
	s     = string(printed)
	start = strings.index_byte(s, '{')
	end   = strings.last_index_byte(s, '}')
	if start < 0 || end < 0 || end < start do return strings.clone_to_cstring("")
	depth  = 0
	quoted = false
	field = start + 1
	for p = start + 1; p <= end; p += 1 {
		if s[p] == '"' && s[p - 1] != '\\' do quoted = !quoted
		if quoted do continue
		if s[p] == '{' || s[p] == '[' {
			depth += 1
		} else if (s[p] == '}' || s[p] == ']') && depth > 0 {
			depth -= 1
		} else if (s[p] == ',' && depth == 0) || p == end {
			pair  = ns_trim_whitespace(s[field:p])
			field = p + 1
			colon = ns_range_of(pair, ": ")
			if colon == NOT_FOUND do continue
			key   = pair[:colon]
			value = pair[colon + 2:]
			keep  = key != "id" && key != "place"
			for k = 0; keep && k < len(open); k += 1 do keep = value != open[k]
			if keep && ns_has_prefix(value, "#") && !ns_contains(value, " ") do keep = false
			if keep do fmt.sbprintf(&out, "%s%s", ", " if strings.builder_len(out) != 0 else "", pair)
		}
	}
	return strings.clone_to_cstring(strings.to_string(out))
}


/* Told (a diagram, say) which line something serves: what it says, kept
 * with the referent beyond its looks, as an analysis's finding is; the
 * referent recognized by its kind on the tile the claim gives. */
knowledge_serves :: proc(self: ^Knowledge, claim: ^tri.Node, speaker: u32, store: ^Knowledge_Store, news: ^[dynamic]string) {
	r: ^Referent
	m: ^Referent
	kind: cstring
	i: uint
	x: i64
	y: i64
	line: [64]u8

	kind = tri.type_name(world_tri(self.world), tri.node_type(tri.at(world_tri(self.world), claim, "what")))
	if !know_node_int(world_tri(self.world), claim, "what.place.x", &x) || !know_node_int(world_tri(self.world), claim, "what.place.y", &y) ||
	   tri.print(world_tri(self.world), tri.at(world_tri(self.world), claim, "line"), &line[0], size_of(line)) < 3 {
		return
	}
	for i = 0; i < knowledge_store_count(store); i += 1 {
		r = knowledge_store_referent_at(store, i)
		if r.kind == nil || string(r.kind) != string(kind) || r.form != .On_Tile || i64(r.x) != x || i64(r.y) != y do continue
		m = knowledge_store_mutable_referent(store, r.id)
		delete(m.deeper)
		m.deeper = strings.clone_to_cstring(k1_clip(fmt.tprintf("serves: %s", k1_buf(line[:])), 128))
		k1_say(news, fmt.tprintf("R%d serves %s, R%d says", r.id, k1_buf(line[:]), speaker))
		return
	}
}


/* Told something is reserved for someone (ACTIONS.md §7): a #Reserved
 * finding about the thing, recognized among the referents of its kind that
 * look alike, its choice whom it is reserved for. */
knowledge_reserved :: proc(self: ^Knowledge, claim: ^tri.Node, speaker: u32, store: ^Knowledge_Store, news: ^[dynamic]string) {
	knowledge_named(self, claim, "#Reserved", "reserved for", speaker, store, news)
}


/* Told something is someone's own (INSTITUTIONS.md): an #Owned finding,
 * its choice the owner, as for a reservation. */
knowledge_owned :: proc(self: ^Knowledge, claim: ^tri.Node, speaker: u32, store: ^Knowledge_Store, news: ^[dynamic]string) {
	knowledge_named(self, claim, "#Owned", "owned by", speaker, store, news)
}


/* Told of a wrong (INSTITUTIONS.md decision 6): that the thing is its
 * holder's own, if it didn't know, and taken by the taker, on the
 * speaker's word (its trust in the speaker, the finding's credence). */
knowledge_grieved :: proc(self: ^Knowledge, claim: ^tri.Node, speaker: u32, store: ^Knowledge_Store, news: ^[dynamic]string) {
	who: ^tri.Node
	f: Finding
	taker: u32
	thing: u32

	thing = knowledge_named(self, claim, "#Owned", "owned by", speaker, store, news)
	who   = tri.at(world_tri(self.world), claim, "taker")
	taker = knowledge_person(self, who, store, news) if who != nil else 0
	if taker == 0 || thing == 0 || knowledge_store_finding(store, "#Taken", thing) != nil do return
	f = {}
	f.kind     = world_intern(self.world, "#Taken")
	f.about    = thing
	f.choice   = taker
	f.credence = knowledge_store_trust_in(store, speaker)
	f.rule     = world_intern(self.world, "told")
	f.time     = world_time(self.world).ms
	knowledge_store_add_finding(store, f)
	k1_say(news, fmt.tprintf("R%d took R%d, R%d says", taker, thing, speaker))
}


/* A claim naming a holder of something (#ReservedFor, #OwnedBy): a finding
 * of the kind about the thing, recognized among the referents of its kind
 * that look alike, its choice the holder. */
knowledge_named :: proc(self: ^Knowledge, claim: ^tri.Node, kind_: cstring, saying: cstring, speaker: u32,
                        store: ^Knowledge_Store, news: ^[dynamic]string) -> u32 {
	what: ^tri.Node
	r: ^Referent
	f: Finding
	kind: string
	i: uint
	holder: u32
	thing: u32
	printed: [2048]u8
	features: cstring

	holder = knowledge_person(self, tri.at(world_tri(self.world), claim, "holder"), store, news)
	what   = tri.at(world_tri(self.world), claim, "what")
	if holder == 0 || what == nil do return 0
	kind = ns_string(tri.type_name(world_tri(self.world), tri.node_type(what)))
	tri.print(world_tri(self.world), what, &printed[0], size_of(printed))
	features = know_concrete_features(k1_buf(printed[:]))
	thing    = 0
	for i = 0; i < knowledge_store_count(store) && thing == 0; i += 1 {
		r = knowledge_store_referent_at(store, i)
		if r.kind != nil && string(r.kind) == kind && r.id != holder &&
		   knowledge_looks_alike(self, r, store, kind, ns_string(features)) {
			thing = r.id
		}
	}
	/* never seen: something like it, as said */
	if thing == 0 {
		m: ^Referent

		m           = knowledge_store_add_referent(store, 0)
		m.kind      = strings.clone_to_cstring(kind)
		m.features  = strings.clone_to_cstring(string(features))
		m.toldBy    = speaker
		thing       = m.id
	}
	delete(features)
	if knowledge_store_finding(store, kind_, thing) != nil do return thing
	f = {}
	f.kind     = world_intern(self.world, kind_)
	f.about    = thing
	f.choice   = holder
	f.credence = knowledge_store_trust_in(store, speaker)
	f.rule     = world_intern(self.world, "told")
	f.time     = world_time(self.world).ms
	knowledge_store_add_finding(store, f)
	k1_say(news, fmt.tprintf("R%d is %s R%d, R%d says", thing, saying, holder, speaker))
	return thing
}


/* Credence (dB, -30 to 30) as a probability, in thousandths. */
@(private)
know_permille_of :: proc(db: i32) -> i32 {
	@(static, rodata) table := [61]i32 {
		1, 1, 2, 2, 3, 3, 4, 5, 6, 8, 10, 12, 16, 20, 25, 31, 38, 48, 59, 74, 91, 112, 137, 166, 201, 240, 285, 334,
		387, 443, 500, 557, 613, 666, 715, 760, 799, 834, 863, 888, 909, 926, 941, 952, 962, 969, 975, 980, 984, 988,
		990, 992, 994, 995, 996, 997, 997, 998, 998, 999, 999,
	}
	db := db

	db = -30 if db < -30 else 30 if db > 30 else db
	return table[db + 30]
}


/* A claim of what something is like (#IsLike): the thing, by its looks;
 * where the claim conflicts with what the agent believes of it, a competing
 * hypothesis (KNOWLEDGE.md §11), as credible as the speaker is to it. */
knowledge_is_like :: proc(self: ^Knowledge, claim: ^tri.Node, speaker: u32, store: ^Knowledge_Store, news: ^[dynamic]string) {
	what: ^tri.Node
	as: ^tri.Node
	r: ^Referent
	overrides: [dynamic]string
	pairs: []string
	kind: string
	pair: string
	key: string
	mine: string
	has_mine: bool
	i: uint
	k: int
	thing: u32
	printed: [2048]u8
	features: cstring

	what = tri.at(world_tri(self.world), claim, "what")
	as   = tri.at(world_tri(self.world), claim, "as")
	if what == nil || as == nil do return
	kind = ns_string(tri.type_name(world_tri(self.world), tri.node_type(what)))
	tri.print(world_tri(self.world), what, &printed[0], size_of(printed))
	features = know_concrete_features(k1_buf(printed[:]))
	thing    = 0
	for i = 0; i < knowledge_store_count(store) && thing == 0; i += 1 {
		r = knowledge_store_referent_at(store, i)
		if r.kind != nil && string(r.kind) == kind && r.id != speaker &&
		   knowledge_looks_alike(self, r, store, kind, ns_string(features)) {
			thing = r.id
		}
	}
	delete(features)
	if thing == 0 do return
	/* the claimed features that differ from what it believes */
	tri.print(world_tri(self.world), as, &printed[0], size_of(printed))
	features  = know_concrete_features(k1_buf(printed[:]))
	pairs     = split_top_level(strings.clone_from_cstring(features, context.temp_allocator))
	delete(features)
	overrides = make([dynamic]string, context.temp_allocator)
	for k = 0; k < len(pairs); k += 1 {
		pair = pairs[k]
		/* what it says: a feature with one value, not one the type leaves open */
		if !ns_contains(pair, ": ") || ns_contains(pair, "|") ||
		   ns_contains(pair, ">=") || ns_contains(pair, "<=") {
			continue
		}
		key      = pair[:ns_range_of(pair, ": ")]
		mine     = ""
		has_mine = false
		{
			believed: []string
			j: int

			believed = split_top_level(knowledge_store_recall(store, knowledge_store_referent(store, thing)))
			for j = 0; j < len(believed) && !has_mine; j += 1 {
				if ns_range_of(believed[j], strings.concatenate({key, ": "}, context.temp_allocator)) == 0 {
					mine     = believed[j]
					has_mine = true
				}
			}
		}
		if has_mine && mine != pair do append(&overrides, pair)
	}
	if len(overrides) == 0 do return
	knowledge_store_suppose(store, strings.join(overrides[:], ", ", context.temp_allocator), thing,
	                        know_permille_of(knowledge_store_trust_in(store, speaker)))
	k1_say(news, fmt.tprintf("R%d may be otherwise, R%d says: %s", thing, speaker,
	                         strings.join(overrides[:], ", ", context.temp_allocator)))
}


/* The referent of someone a claim names by how they look ("heard it from
 * ..."): one of that kind that looks alike, the lowest first, or a new one,
 * believed nowhere. 0 if the description says no more than its kind does. */
knowledge_person :: proc(self: ^Knowledge, description: ^tri.Node, store: ^Knowledge_Store, news: ^[dynamic]string) -> u32 {
	r: ^Referent
	bare: ^tri.Node
	m: ^Referent
	tc: ^tri.Content
	arena: ^tri.Arena
	kind: string
	features: string
	i: uint
	printed: [2048]u8
	concrete: cstring
	defaults: cstring

	tc   = world_tri(self.world)
	kind = ns_string(tri.type_name(tc, tri.node_type(description)))
	tri.print(tc, description, &printed[0], size_of(printed))
	concrete = know_concrete_features(k1_buf(printed[:]))
	arena    = tri.arena_new()
	bare     = tri.value(tc, ns_utf8(kind), arena, nil, 0)
	printed[0] = 0
	if bare != nil do tri.print(tc, bare, &printed[0], size_of(printed))
	tri.arena_free(arena)
	defaults = know_concrete_features(k1_buf(printed[:]))
	if string(concrete) == string(defaults) {
		delete(concrete)
		delete(defaults)
		return 0
	}
	delete(defaults)
	features = strings.clone_from_cstring(concrete, context.temp_allocator)
	for i = 0; i < knowledge_store_count(store); i += 1 {
		r = knowledge_store_referent_at(store, i)
		if r.kind != nil && string(r.kind) == kind && knowledge_looks_alike(self, r, store, kind, features) {
			delete(concrete)
			return r.id
		}
	}
	m           = knowledge_store_add_referent(store, 0)
	m.kind      = strings.clone_to_cstring(kind)
	m.features  = concrete
	k1_say(news, fmt.tprintf("R%d: %s, heard of", m.id, kind))
	return m.id
}


/* A claim heard is testimony (KNOWLEDGE.md §10, §11). For #IsIn: the
 * container, recognized by its kind on the tile the claim gives, or a new
 * referent there; the thing, recognized as one of its kind believed in it or
 * claimed to be, else as one not where it was believed that the claim's
 * description fits, else a new referent; and its source and perceived root
 * from the attribution. Once its credence reaches BG_BELIEVE, and no other
 * claim of where it is weighs more, the thing is believed in the container,
 * as of the claim's `when`, told by the speaker. */
knowledge_believe :: proc(self: ^Knowledge, content: cstring, speaker: u32, record: u32, utterance: u64, now: i64,
                          store: ^Knowledge_Store, news: ^[dynamic]string) {
	claim: ^tri.Node
	what: ^tri.Node
	within: ^tri.Node
	attribution: ^tri.Node
	description: ^tri.Node
	r: ^Referent
	m: ^Referent
	t: Testimony
	tc: ^tri.Content
	arena: ^tri.Arena
	result: tri.Match_Result
	kind: cstring
	ckind: cstring
	c: ^Referent
	x: i64
	y: i64
	level: i64
	when_: i64
	sure: i64
	credence: i32
	form: Location_Form
	held: bool
	cid: u32
	thing: u32
	i: uint
	j: uint
	pass: i32
	printed: [2048]u8

	tc    = world_tri(self.world)
	arena = tri.arena_new()
	claim = tri.value(tc, content, arena, nil, 0)
	if claim != nil && tri.subtype(tc, tri.node_type(claim), tri.type_named(tc, "#Account")) != 0 {
		/* an account (ACTIONS.md decision 14): each of its claims, in order */
		list: ^tri.Node

		for list = tri.at(tc, claim, "entries"); list != nil && tri.at(tc, list, "first") != nil; list = tri.at(tc, list, "rest") {
			tri.print(tc, tri.at(tc, list, "first"), &printed[0], size_of(printed))
			knowledge_believe(self, k1_buf(printed[:]), speaker, record, utterance, now, store, news)
		}
		tri.arena_free(arena)
		return
	}
	if claim != nil && tri.subtype(tc, tri.node_type(claim), tri.type_named(tc, "#Serves")) != 0 {
		knowledge_serves(self, claim, speaker, store, news)
		tri.arena_free(arena)
		return
	}
	if claim != nil && tri.subtype(tc, tri.node_type(claim), tri.type_named(tc, "#IsLike")) != 0 {
		knowledge_is_like(self, claim, speaker, store, news)
		tri.arena_free(arena)
		return
	}
	if claim != nil && tri.subtype(tc, tri.node_type(claim), tri.type_named(tc, "#ReservedFor")) != 0 {
		knowledge_reserved(self, claim, speaker, store, news)
		tri.arena_free(arena)
		return
	}
	if claim != nil && tri.subtype(tc, tri.node_type(claim), tri.type_named(tc, "#LawSays")) != 0 {
		/* a law stated (INSTITUTIONS.md decision 8): learned, by what it says */
		law: ^tri.Node
		k: Known_Law
		weighs: i64
		forbids: [64]u8

		law = tri.at(tc, claim, "law")
		if law != nil && tri.at(tc, law, "forbids") != nil && tri.print(tc, tri.at(tc, law, "forbids"), &forbids[0], size_of(forbids)) > 2 &&
		   tri.at(tc, law, "wrong") != nil && tri.at(tc, law, "brings") != nil {
			forbids[len(k1_buf(forbids[:])) - 1] = 0
			k.forbids = world_intern(self.world, cstring(&forbids[1]))
			k.wrong   = world_intern(self.world, tri.type_name(tc, tri.node_type(tri.at(tc, law, "wrong"))))
			k.brings  = world_intern(self.world, tri.type_name(tc, tri.node_type(tri.at(tc, law, "brings"))))
			k.weighs  = i32(weighs) if know_node_int(tc, law, "weighs", &weighs) else 0
			knowledge_store_learn_law(store, k)
			k1_say(news, fmt.tprintf("a law: no %s, when %s, or %s (R%d says)", k.forbids, k.wrong,
			                         k.brings, speaker))
		}
		tri.arena_free(arena)
		return
	}
	if claim != nil && tri.subtype(tc, tri.node_type(claim), tri.type_named(tc, "#RecipeSays")) != 0 {
		/* a recipe stated (ACTIONS.md decision 12): learned, if it is one */
		v: ^tri.Node
		recipe: [64]u8
		n: uint

		v = tri.at(tc, claim, "recipe")
		n = tri.print(tc, v, &recipe[0], size_of(recipe)) if v != nil else 0
		if n > 2 && recipe[0] == '"' {
			recipe[n - 1] = 0
			v = tri.at(tc, tri.pattern(tc, cstring(&recipe[1])), "sequence") if tri.pattern(tc, cstring(&recipe[1])) != nil else nil
			if v != nil && tri.node_type(v) == tri.type_named(tc, "true") {
				knowledge_store_learn_recipe(store, cstring(&recipe[1]))
				k1_say(news, fmt.tprintf("a recipe: %s (R%d says)", cstring(&recipe[1]), speaker))
			}
		}
		tri.arena_free(arena)
		return
	}
	if claim != nil && tri.type_named(tc, "#Priced") != 0 && tri.subtype(tc, tri.node_type(claim), tri.type_named(tc, "#Priced")) != 0 {
		/* a price posted (content/market/): who sells goods of what unit, at
		 * how many coins a unit, on the board it was read on (standing on the
		 * stall) */
		coins: i64
		unit: [64]u8
		seller := knowledge_person(self, tri.at(tc, claim, "holder"), store, news) if tri.at(tc, claim, "holder") != nil else 0
		n := tri.print(tc, tri.at(tc, claim, "what.unit"), &unit[0], size_of(unit)) if tri.at(tc, claim, "what.unit") != nil else 0
		if seller != 0 && seller != knowledge_store_self_referent(store) && record != 0 && n > 2 && unit[0] == '"' &&
		   know_node_int(tc, claim, "coins", &coins) {
			unit[n - 1] = 0
			knowledge_store_learn_price(store, Known_Price{seller, record, world_intern(self.world, cstring(&unit[1])), i32(coins), now})
			k1_say(news, fmt.tprintf("R%d sells %s at %d coins, R%d says", seller, cstring(&unit[1]), coins, speaker))
		}
		tri.arena_free(arena)
		return
	}
	if claim != nil && tri.subtype(tc, tri.node_type(claim), tri.type_named(tc, "#Hiring")) != 0 {
		/* a deal posted (AGENCY.md decision 15): someone hires, and where to
		 * find them; believed there, unless seen since */
		site: ^tri.Node
		f: Finding
		employer: u32
		sx: i64
		sy: i64
		sl: i64

		employer = knowledge_person(self, tri.at(tc, claim, "holder"), store, news) if tri.at(tc, claim, "holder") != nil else 0
		site     = tri.at(tc, claim, "site")
		if employer != 0 && employer != knowledge_store_self_referent(store) {
			m = knowledge_store_mutable_referent(store, employer)
			if site != nil && m.seen == 0 && know_node_int(tc, site, "x", &sx) && know_node_int(tc, site, "y", &sy) &&
			   know_node_int(tc, site, "level", &sl) {
				m.form    = .On_Tile
				m.x       = i32(sx)
				m.y       = i32(sy)
				m.level   = i32(sl)
				m.present = true
				m.toldBy  = speaker
			}
			f = {}
			f.kind     = world_intern(self.world, "#Hires")
			f.about    = employer
			f.credence = knowledge_store_trust_in(store, speaker)
			f.rule     = world_intern(self.world, "told")
			f.time     = now
			knowledge_store_retract_finding(store, "#Hires", employer)
			knowledge_store_add_finding(store, f)
			k1_say(news, fmt.tprintf("R%d hires, R%d says", employer, speaker))
		}
		tri.arena_free(arena)
		return
	}
	if claim != nil && tri.subtype(tc, tri.node_type(claim), tri.type_named(tc, "#Grievance")) != 0 {
		knowledge_grieved(self, claim, speaker, store, news)
		tri.arena_free(arena)
		return
	}
	if claim != nil && tri.subtype(tc, tri.node_type(claim), tri.type_named(tc, "#OwnedBy")) != 0 {
		knowledge_owned(self, claim, speaker, store, news)
		tri.arena_free(arena)
		return
	}
	held  = claim != nil && tri.subtype(tc, tri.node_type(claim), tri.type_named(tc, "#IsHeld")) != 0
	if claim == nil || (!held && (tri.subtype(tc, tri.node_type(claim), tri.type_named(tc, "#IsIn")) == 0 ||
	                              !know_node_int(tc, claim, "within.place.x", &x) || !know_node_int(tc, claim, "within.place.y", &y) ||
	                              !know_node_int(tc, claim, "within.place.level", &level))) {
		tri.arena_free(arena)
		return
	}
	if !know_node_int(tc, claim, "when", &when_) do when_ = now
	form   = .Held_By if held else .In
	what   = tri.at(tc, claim, "what")
	within = tri.at(tc, claim, "holder") if held else tri.at(tc, claim, "within")
	kind   = tri.type_name(tc, tri.node_type(what))
	ckind  = tri.type_name(tc, tri.node_type(within))

	/* who it says saw it */
	t = {}
	t.source      = speaker
	t.root        = speaker
	t.attribution = .Saw
	t.sure        = BG_UNSTATED
	attribution   = tri.at(tc, claim, "attribution")
	if attribution != nil && know_node_int(tc, attribution, "sure", &sure) do t.sure = i32(sure)
	if attribution != nil && tri.subtype(tc, tri.node_type(attribution), tri.type_named(tc, "#Pledged")) != 0 {
		t.attribution = .Pledged
	} else if attribution != nil && tri.subtype(tc, tri.node_type(attribution), tri.type_named(tc, "#Heard")) != 0 {
		description   = tri.at(tc, attribution, "from")
		t.root        = knowledge_person(self, description, store, news) if description != nil else 0
		t.attribution = .Heard_From if t.root != 0 else .Heard
	}

	/* the container, or who holds it */
	cid = knowledge_person(self, within, store, news) if held else 0
	if held && cid == 0 {
		tri.arena_free(arena)
		return
	}
	for i = 0; i < knowledge_store_count(store) && cid == 0; i += 1 {
		r = knowledge_store_referent_at(store, i)
		if r.kind != nil && string(r.kind) == string(ckind) && r.form == .On_Tile && i64(r.x) == x && i64(r.y) == y &&
		   i64(r.level) == level {
			cid = r.id
		}
	}
	if cid == 0 {
		tri.print(tc, within, &printed[0], size_of(printed))
		m           = knowledge_store_add_referent(store, 0)
		m.kind      = strings.clone_to_cstring(string(ckind))
		m.features  = know_concrete_features(k1_buf(printed[:]))
		m.form      = .On_Tile
		m.x         = i32(x)
		m.y         = i32(y)
		m.level     = i32(level)
		m.seen      = when_
		m.present   = true
		m.toldBy    = speaker
		cid         = m.id
		k1_say(news, fmt.tprintf("R%d: %s, at (%d, %d), R%d says", cid, ckind, i32(x), i32(y),
		                         speaker))
	}

	/* the thing */
	thing = 0
	for pass = 0; pass < 3 && thing == 0; pass += 1 {
		for i = 0; i < knowledge_store_count(store) && thing == 0; i += 1 {
			r = knowledge_store_referent_at(store, i)
			if r.kind == nil || string(r.kind) != string(kind) || r.id == cid || r.id == knowledge_store_self_referent(store) do continue
			if pass == 0 && r.present && r.form == form && r.container == cid do thing = r.id
			for j = 0; pass == 0 && thing == 0 && j < knowledge_store_testimony_count(store); j += 1 {
				if knowledge_store_testimony_at(store, j).thing == r.id && knowledge_store_testimony_at(store, j).container == cid do thing = r.id
			}
			/* promised: by its looks, what the one promising holds first (it
			 * will hand over what it has: a wage, AGENCY.md decision 15) */
			if pass == 1 && t.attribution == .Pledged && r.present && r.form == .Held_By &&
			   r.container == speaker {
				description = tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, r.id)), arena, nil, 0)
				if description != nil && tri.match(tc, what, description, &result) != .Incompatible do thing = r.id
			}
			/* by its looks, among those it doesn't know where they are; or,
			 * promised somewhere, among all: where it is now says nothing of then */
			if pass == 2 && (!r.present || t.attribution == .Pledged) {
				description = tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, r.id)), arena, nil, 0)
				if description != nil && tri.match(tc, what, description, &result) != .Incompatible do thing = r.id
			}
		}
	}
	if thing == 0 {
		tri.print(tc, what, &printed[0], size_of(printed))
		m           = knowledge_store_add_referent(store, 0)
		m.kind      = strings.clone_to_cstring(string(kind))
		m.features  = know_concrete_features(k1_buf(printed[:]))
		thing       = m.id
	}

	t.thing     = thing
	t.container = cid
	t.via       = record
	t.when_      = when_
	t.heard     = now
	t.utterance = utterance
	knowledge_store_add_testimony(store, t)
	if t.attribution == .Pledged {
		/* about a time to come: held, not believed of now */
		k1_say(news, fmt.tprintf("R%d promises R%d will be in R%d by %dms", speaker, thing, cid,
		                         when_))
		tri.arena_free(arena)
		return
	}
	credence = knowledge_store_credence_that(store, thing, cid)

	m = knowledge_store_mutable_referent(store, thing)
	if m.present && m.toldBy == 0 && m.seen >= when_ && !(m.form == form && m.container == cid) {
		/* seen elsewhere since: sight outranks it, and seen elsewhere as it was said, it is false */
		if m.seen == when_ {
			know_settle(store, thing, cid, false, now, news)
		} else {
			k1_say(news, fmt.tprintf("R%d says R%d is in R%d: seen elsewhere since", speaker, thing,
			                         cid))
		}
		tri.arena_free(arena)
		return
	}
	if m.present && m.form == form && m.container == cid {
		k1_say(news, fmt.tprintf("R%d is in R%d, R%d says too (%+d dB)", thing, cid, speaker,
		                         credence))
		if credence >= BG_BELIEVE do knowledge_learn_outcome_of(self, thing, cid, when_, now, store, news)
		tri.arena_free(arena)
		return
	}
	if credence < BG_BELIEVE ||
	   (m.present && m.toldBy != 0 && (m.form == .In || m.form == .Held_By) &&
	    knowledge_store_credence_that(store, thing, m.container) > credence) {
		k1_say(news, fmt.tprintf("R%d says R%d is in R%d: not believed (%+d dB)", speaker, thing,
		                         cid, credence))
		tri.arena_free(arena)
		return
	}
	c           = knowledge_store_referent(store, cid)
	m.form      = form
	m.container = cid
	m.x         = c.x
	m.y         = c.y
	m.level     = c.level
	m.slot      = 0
	m.role[0]   = 0
	m.seen      = when_
	m.present   = true
	m.toldBy    = speaker
	k1_say(news, fmt.tprintf("R%d is in R%d, R%d says (%+d dB)", thing, cid, speaker, credence))
	knowledge_learn_outcome_of(self, thing, cid, when_, now, store, news)
	tri.arena_free(arena)
}


/* Believing, on someone's word, where a promised thing is as of after its
 * deadline, the agent learns the promise's outcome (AGENCY.md §7: hearers
 * perceive it "when they learn the outcome"): kept if it is where it was
 * promised, broken if elsewhere. */
knowledge_learn_outcome_of :: proc(self: ^Knowledge, thing: u32, container: u32, when_: i64, now: i64,
                                   store: ^Knowledge_Store, news: ^[dynamic]string) {
	t: ^Testimony
	i: uint

	for i = 0; i < knowledge_store_testimony_count(store); i += 1 {
		t = knowledge_store_testimony_at(store, i)
		if t.settled != 0 || t.attribution != .Pledged || t.thing != thing || when_ < t.when_ do continue
		know_settle(store, thing, t.container, t.container == container, now, news)
	}
}


/* The features, without what comes and goes as a thing is used: free hands. */
@(private)
know_lasting :: proc(features: string) -> string {
	kept: [dynamic]string
	pairs: []string
	i: int

	pairs = split_top_level(features) if len(features) != 0 else []string{}
	kept  = make([dynamic]string, context.temp_allocator)
	for i = 0; i < len(pairs); i += 1 {
		if !ns_has_prefix(pairs[i], "freeHands:") do append(&kept, pairs[i])
	}
	return strings.join(kept[:], ", ", context.temp_allocator)
}


/* Whether a percept could be the referent by its looks: the features memory
 * keeps of it unify with those perceived, but for what comes and goes. */
knowledge_looks_alike :: proc(self: ^Knowledge, r: ^Referent, store: ^Knowledge_Store, kind: string, features: string) -> bool {
	both: ^tri.Node
	arena: ^tri.Arena
	expr: string

	expr  = fmt.tprintf("%s & {{ %s }} & {{ %s }}", kind, know_lasting(knowledge_store_recall(store, r)), know_lasting(features))
	/* whether they unify, worked out before for the same text */
	key := fmt.tprintf("alike\x00%s", expr)
	if m, ok := world_matched(self.world, key); ok do return m.match == .Entailed
	arena = tri.arena_new()
	both  = tri.value(world_tri(self.world), ns_utf8(expr), arena, nil, 0)
	tri.arena_free(arena)
	world_remember_match(self.world, key, Matched{match = .Entailed if both != nil else .Incompatible})
	return both != nil
}


/* Testimony that the thing is inside the container is settled: seen true,
 * and its source and root are trusted more, or found false, and they are
 * trusted less. */
@(private)
know_settle :: proc(store: ^Knowledge_Store, thing: u32, container: u32, true_: bool, now: i64,
                    news: ^[dynamic]string) {
	t: ^Testimony
	i: uint
	delta: i32

	delta = BG_CONFIRMED if true_ else -BG_REFUTED
	for i = 0; i < knowledge_store_testimony_count(store); i += 1 {
		t = knowledge_store_mutable_testimony_at(store, i)
		if t.settled != 0 || t.thing != thing || t.container != container do continue
		if t.attribution == .Pledged && !true_ && now < t.when_ do continue      /* not due yet */
		t.settled = 1 if true_ else -1
		knowledge_store_adjust_trust_in(store, t.source, delta)
		if t.root != 0 && t.root != t.source do knowledge_store_adjust_trust_in(store, t.root, delta)
		if t.attribution == .Pledged {
			k1_say(news, fmt.tprintf("R%d promised R%d would be in R%d: %s", t.source, thing, container,
			                         "kept" if true_ else "broken"))
		} else {
			k1_say(news, fmt.tprintf("R%d said R%d was in R%d: %s", t.source, thing, container,
			                         "so it is" if true_ else "it isn't"))
		}
	}
}


/* The holder's loyalty to the entity (AGENCY.md §12): its strongest bond
 * toward it, or 0. */
@(private)
know_loyalty :: proc(world: ^World, holder: Entity_ID, toward: Entity_ID) -> i32 {
	bond: ^Bond
	bonds: ^Store
	i: uint
	most: i32

	most  = 0
	bonds = world_store_for_kind(world, world_kind_named(world, "Bond"))
	for i = 0; i < store_count(bonds); i += 1 {
		bond = (^Bond)(store_record_at_index(bonds, i))
		if Entity_ID(bond.bondOf) == holder && Entity_ID(bond.toward) == toward && bond.loyalty > i64(most) do most = i32(bond.loyalty)
	}
	return most
}


/* Each identity hypothesis whose credence reaches the threshold content
 * declares (`recognition`'s `mergeAt`): the two merged, into the older. */
knowledge_merge_identities :: proc(self: ^Knowledge, store: ^Knowledge_Store, news: ^[dynamic]string) {
	h: ^Identity
	v: ^tri.Node
	tc: ^tri.Content
	family: ^tri.Index
	i: uint
	threshold: i64
	lo: i64
	hi: i64
	a: u32
	b: u32
	credence: i32

	tc        = world_tri(self.world)
	family    = tri.family_index(tc, "recognition")
	threshold = max(i64)
	for i = 0; family != nil && i < tri.index_count(family); i += 1 {
		v = tri.at(tc, tri.pattern(tc, cstring(tri.index_tag(family, i))), "mergeAt")
		if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi do threshold = lo
	}
	for i = 0; i < knowledge_store_identity_count(store); {
		h = knowledge_store_identity_at(store, i)
		if i64(h.credence) < threshold {
			i += 1
			continue
		}
		a        = h.a
		b        = h.b
		credence = h.credence
		knowledge_store_merge_referent(store, a, b)
		k1_say(news, fmt.tprintf("R%d is R%d (%+d dB): one, not two", a, b, credence))
		i = 0
	}
}


/* The referent a perceived entity was bound to this phase, or 0. */
@(private)
know_bound_to :: proc(e: Entity_ID, agent: Entity_ID, me: u32, seen: [^]Seen, assigned: [^]u32, nseen: uint) -> u32 {
	i: uint

	if e == agent do return me
	for i = 0; e != 0 && i < nseen; i += 1 {
		if seen[i].entity == e do return assigned[i]
	}
	return 0
}


/* Where a sound was made: what made it's tile, or the floor's; NO if the
 * trace isn't one. */
@(private)
know_sound_from :: proc(world: ^World, tc: ^tri.Content, record: ^Trace, trace: Entity_ID, tile: ^Location) -> bool {
	v: ^tri.Node
	kind: cstring
	sense: [16]u8

	kind = world_text_field(world, "Trace.traceKind", trace)
	v    = tri.at(tc, tri.pattern(tc, kind), "sense") if kind != nil else nil
	sense[0] = 0
	if v != nil do tri.print(tc, v, &sense[0], size_of(sense))
	if string(k1_buf(sense[:])) != "\"hearing\"" do return false
	if record.bearer != 0 do return know_ground_tile(world, Entity_ID(record.bearer), tile)
	tile.form  = .On_Tile
	tile.x     = i32(record.tileX)
	tile.y     = i32(record.tileY)
	tile.level = i32(record.tileLevel)
	return true
}


/* Traces in reach of their sense: on what it sees, or on the floor; how
 * strong each seems now. One it perceived at a site it perceives again, and
 * doesn't find, is gone. */
/* the strongest first; in the world's order among equals */
// qsort's comparator as slice.sort_by's: whether x comes before y.
@(private)
know_cmp_fresh :: proc(x: Trace_Seen, y: Trace_Seen) -> bool {
	if x.strength != y.strength do return x.strength > y.strength
	return x.truth < y.truth
}


// `seen` and `assigned` are nseen long; *budget is what attention is left.
knowledge_perceive_traces :: proc(self: ^Knowledge, store: ^Knowledge_Store, here: Location, now: i64, seen: [^]Seen,
                                  assigned: [^]u32, nseen: uint, closely: bool, budget: ^int, news: ^[dynamic]string) {
	record: ^Trace
	v: ^tri.Node
	old: ^Trace_Seen
	t: Trace_Seen
	tile: Location
	traces: ^Store
	tc: ^tri.Content
	i: uint
	j: uint
	found: [^]bool
	strength: i64
	range: [3]i32
	loudest: i64
	fresh: [64]Trace_Seen
	nfresh: uint
	near: [^]Entity_ID
	nnear: uint
	sensed: i32
	sense: [16]u8
	kind: cstring

	tc       = world_tri(self.world)
	traces   = world_store_for_kind(self.world, world_kind_named(self.world, "Trace"))
	/* the traces it could sense: those a sound could carry from (the
	 * spatial index, TERRAIN.md), the farthest reach of any sense; all of
	 * them, to an omniscient eye */
	if self.omniscient {
		nnear = store_count(traces)
		near  = make([^]Entity_ID, nnear if nnear != 0 else 1)
		for i = 0; i < nnear; i += 1 do near[i] = store_entity_at_index(traces, i)
	} else {
		nnear = world_traces_near(self.world, here, BG_SOUND_REACH, &near)
	}
	range[0] = BG_SIGHT
	range[1] = BG_SMELL + (1 if closely else 0)
	range[2] = BG_HEARING
	nfresh    = 0
	/* sound (KNOWLEDGE.md decision 14): the loudest heard here, which masks
	 * what is much quieter */
	loudest = 0
	for i = 0; !self.omniscient && i < nnear; i += 1 {
		record = (^Trace)(store_record_for(traces, near[i]))
		if record != nil && know_sound_from(self.world, tc, record, near[i], &tile) {
			strength = loudness(self.world, trace_strength(record, now), tile, here)
			loudest  = strength if strength > loudest else loudest
		}
	}
	for i = 0; i < nnear; i += 1 {
		record = (^Trace)(store_record_for(traces, near[i]))
		if record == nil do continue
		kind     = world_text_field(self.world, "Trace.traceKind", near[i])
		strength = trace_strength(record, now)
		v = tri.at(tc, tri.pattern(tc, kind), "sense") if kind != nil else nil
		sense[0] = 0
		if v != nil do tri.print(tc, v, &sense[0], size_of(sense))
		sensed = 1 if string(k1_buf(sense[:])) == "\"smell\"" else 2 if string(k1_buf(sense[:])) == "\"hearing\"" else 0
		t = {}
		/* a sound, heard as loud as it carries here: through walls and doors,
		 * unless masked by a louder one; from what made it, if seen, else
		 * from where it came */
		if sensed == 2 && !self.omniscient {
			if !know_sound_from(self.world, tc, record, near[i], &tile) do continue
			strength = loudness(self.world, strength, tile, here)
			if strength < (BG_TRACE_FLOOR_CLOSE if closely else BG_TRACE_FLOOR) || strength < loudest - BG_SOUND_MASK {
				continue      /* too faint to notice, or drowned out */
			}
			for j = 0; record.bearer != 0 && j < nseen && seen[j].entity != Entity_ID(record.bearer); j += 1 {
			}
			t.bearer = assigned[j] if record.bearer != 0 && j < nseen else 0
			t.x      = tile.x
			t.y      = tile.y
			t.level  = tile.level
			t.kind     = world_intern(self.world, kind)
			t.strength = i32(strength)
			t.seen     = now
			t.present  = true
			t.truth    = near[i]        /* developer-only */
			if !knowledge_store_knows_trace(store, t) {
				if nfresh < 64 {
					fresh[nfresh] = t
					nfresh += 1
				}
				continue
			}
			knowledge_store_note_trace(store, t)
			continue
		}
		if kind == nil || strength <= 0 || strength < (BG_TRACE_FLOOR_CLOSE if closely else BG_TRACE_FLOOR) {
			continue      /* too faint to notice */
		}
		if record.bearer != 0 {
			for j = 0; j < nseen && seen[j].entity != Entity_ID(record.bearer); j += 1 {
			}
			if j == nseen || !know_ground_tile(self.world, Entity_ID(record.bearer), &tile) {
				continue      /* it doesn't see what bears it */
			}
			t.bearer = assigned[j]
			t.x      = tile.x
			t.y      = tile.y
			t.level  = tile.level
		} else {
			t.x     = i32(record.tileX)
			t.y     = i32(record.tileY)
			t.level = i32(record.tileLevel)
		}
		if !self.omniscient && (t.level != here.level || abs(t.x - here.x) > range[sensed] ||
		                        abs(t.y - here.y) > range[sensed]) {
			continue
		}
		t.kind     = world_intern(self.world, kind)
		t.strength = i32(strength)
		t.seen     = now
		t.present  = true
		t.truth    = near[i]        /* developer-only */
		/* known already, it is seen as it is now; new, it waits for attention */
		if !knowledge_store_knows_trace(store, t) {
			if nfresh < 64 {
				fresh[nfresh] = t
				nfresh += 1
			}
			continue
		}
		knowledge_store_note_trace(store, t)
	}

	free(near)

	/* new to it: the strongest first get what attention is left (KNOWLEDGE.md
	 * §5); a close look, investigating, attends to all of them */
	slice.sort_by(fresh[:nfresh], know_cmp_fresh)
	for i = 0; i < nfresh; i += 1 {
		t = fresh[i]
		if !closely {
			left := budget^
			budget^ -= 1
			if left <= 0 {
				k1_say(news, fmt.tprintf("no attention left for the %s", t.kind))
				self.short = true      /* attended to later: it perceives again next */
				continue
			}
		}
		knowledge_store_note_trace(store, t)
		k1_say(news, fmt.tprintf("R%d bears %s (%d)", t.bearer, t.kind, t.strength) if t.bearer != 0 else fmt.tprintf("%s at (%d, %d) (%d)", t.kind, t.x, t.y, t.strength))
	}
	if budget^ < 0 do budget^ = 0

	/* gone: perceived before, where it would be perceived now, and not found */
	found = make([^]bool, knowledge_store_trace_count(store) + 1)
	for i = 0; i < knowledge_store_trace_count(store); i += 1 do found[i] = knowledge_store_trace_at(store, i).seen == now
	for i = 0; i < knowledge_store_trace_count(store); i += 1 {
		old = knowledge_store_trace_at(store, i)
		if found[i] || !old.present do continue
		if !closely && old.strength < BG_TRACE_FLOOR {
			continue      /* caught only on a close look: a glance can't miss it */
		}
		v = tri.at(tc, tri.pattern(tc, old.kind), "sense")
		sense[0] = 0
		if v != nil do tri.print(tc, v, &sense[0], size_of(sense))
		sensed = 1 if string(k1_buf(sense[:])) == "\"smell\"" else 2 if string(k1_buf(sense[:])) == "\"hearing\"" else 0
		if old.bearer != 0 {
			for j = 0; j < nseen && assigned[j] != old.bearer; j += 1 {
			}
			if j == nseen || !know_ground_tile(self.world, seen[j].entity, &tile) {
				continue      /* not looking at what bore it */
			}
		} else {
			tile.x     = old.x
			tile.y     = old.y
			tile.level = old.level
		}
		if !self.omniscient && (tile.level != here.level || abs(tile.x - here.x) > range[sensed] ||
		                        abs(tile.y - here.y) > range[sensed]) {
			continue
		}
		old = knowledge_store_mutable_trace_at(store, i)
		old.present = false
		old.seen    = now
		k1_say(news, fmt.tprintf("the %s on R%d is gone", old.kind, old.bearer) if old.bearer != 0 else fmt.tprintf("the %s at (%d, %d) is gone", old.kind, old.x, old.y))
	}
	free(found)
}


/* Whether the agent perceives a trace of the kind on the referent: there
 * now, or (`gone`) there before and not any more. */
/* A quoted text feature of a description ("claims: \"the harbour office\""),
 * or nil. */
// nil is ("", false).
@(private)
know_quoted_feature :: proc(description: string, name: string) -> (string, bool) #optional_ok {
	at: uint
	end: int
	key: string

	key = fmt.tprintf("%s: \"", name)
	at  = ns_range_of(description, key)
	if at == NOT_FOUND do return "", false
	end = strings.index(description[at + uint(len(key)):], "\"")
	if end < 0 do return "", false
	return description[at + uint(len(key)):][:end], true
}


/* Whether the referent's description may hold the text: its kind, or what
 * it knows of the thing, does. */
@(private)
know_may_say :: proc(r: ^Referent, text: string) -> bool {
	return r != nil && ((r.kind != nil && strings.contains(string(r.kind), text)) ||
	                    (r.features != nil && strings.contains(string(r.features), text)) ||
	                    (r.deeper != nil && strings.contains(string(r.deeper), text)))
}


/* Whether the referent is a copy claiming an issuer whose seal the agent has
 * seen, with an impression not that seal's. */
@(private)
know_misprinted :: proc(store: ^Knowledge_Store, referent: u32) -> bool {
	copy_: string
	claims: string
	impression: string
	has_impression: bool
	seal: string
	i: uint

	/* what memory recalls of a thing is generalized from what it knows, key
	 * by key, and never adds a key: without the text in what it knows, the
	 * description won't have it (and describing everything, as memory
	 * fades it, is what costs) */
	if !know_may_say(knowledge_store_referent(store, referent), "claims: \"") do return false
	copy_                      = knowledge_store_describe_referent(store, referent)
	claims                     = know_quoted_feature(copy_, "claims")
	impression, has_impression = know_quoted_feature(copy_, "impression")
	if len(claims) == 0 || !has_impression do return false
	for i = 0; i < knowledge_store_count(store); i += 1 {
		if !know_may_say(knowledge_store_referent_at(store, i), "sealOf: \"") do continue
		seal = knowledge_store_describe_referent(store, knowledge_store_referent_at(store, i).id)
		seal_of, has_seal_of := know_quoted_feature(seal, "sealOf")
		presses, has_presses := know_quoted_feature(seal, "presses")
		if has_seal_of && seal_of == claims && has_presses &&
		   presses != impression {
			return true
		}
	}
	return false
}


/* Whether it noticed the referent lose some of `field`, wear that comes and
 * never goes. */
@(private)
know_unworn :: proc(store: ^Knowledge_Store, referent: u32, field: cstring) -> bool {
	o: ^Observation
	i: uint

	for i = 0; i < knowledge_store_observation_count(store); i += 1 {
		o = knowledge_store_observation_at(store, i)
		if string(o.kind) == "unworn" && o.subject == referent && o.content != nil && string(o.content) == string(field) do return true
	}
	return false
}


/* A whole-number feature of a description's features ("toolMarks: 40"). */
@(private)
know_int_feature :: proc(features: cstring, field: cstring, value: ^i64) -> bool {
	s: string
	f: string
	p: int
	at: int
	n: int

	if features == nil do return false
	s = string(features)
	f = string(field)
	n = len(f)
	for p = 0; ; p += n {
		at = strings.index(s[p:], f)
		if at < 0 do break
		p += at
		if (p == 0 || s[p - 1] == ' ' || s[p - 1] == '{') && strings.has_prefix(s[p + n:], ": ") &&
		   p + n + 2 < len(s) && (s[p + n + 2] == '-' || (s[p + n + 2] >= '0' && s[p + n + 2] <= '9')) {
			value^ = ns_long_long_value(s[p + n + 2:])      /* atoll */
			return true
		}
	}
	return false
}


@(private)
know_bears :: proc(store: ^Knowledge_Store, referent: u32, kind: cstring, gone: bool) -> bool {
	t: ^Trace_Seen
	i: uint

	for i = 0; i < knowledge_store_trace_count(store); i += 1 {
		t = knowledge_store_trace_at(store, i)
		if t.bearer == referent && string(t.kind) == string(kind) && t.present == !gone do return true
	}
	return false
}


/* Whether, of the rule's signs on the referent, the agent remembers one it
 * no longer finds that should still be there (KNOWLEDGE.md decision 11):
 * as strong as it seemed, less what fading evenly over its kind's `lasts`
 * takes since, still above its kind's floor and faint (10). */
knowledge_contradicted :: proc(self: ^Knowledge, rule: ^tri.Node, r: ^Referent, store: ^Knowledge_Store, now: i64) -> bool {
	t: ^Trace_Seen
	list: ^tri.Node
	premise: ^tri.Node
	v: ^tri.Node
	kind: ^tri.Node
	tc: ^tri.Content
	i: uint
	lasts: i64
	floor: i64
	lo: i64
	hi: i64
	left: i64
	text: [64]u8

	tc = world_tri(self.world)
	for list = tri.at(tc, rule, "premises"); list != nil; list = tri.at(tc, list, "rest") {
		premise = tri.at(tc, list, "first")
		if premise == nil do break
		v = tri.at(tc, premise, "sign")
		if v == nil || tri.print(tc, v, &text[0], size_of(text)) <= 2 do continue
		text[len(k1_buf(text[:])) - 1] = 0
		kind  = tri.pattern(tc, cstring(&text[1]))
		v     = tri.at(tc, kind, "lasts") if kind != nil else nil
		lasts = lo if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi else 0
		v     = tri.at(tc, kind, "floor") if kind != nil else nil
		floor = lo if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi else 0
		for i = 0; lasts > 0 && i < knowledge_store_trace_count(store); i += 1 {
			t = knowledge_store_trace_at(store, i)
			if t.bearer != r.id || t.present || string(t.kind) != string(cstring(&text[1])) do continue
			left = i64(t.strength) - (now - t.seen) * 100 / lasts
			if left > floor && left > 10 do return true
		}
	}
	return false
}


/* Whether the agent perceives a trace of the kind on the floor at the
 * referent's tile or beside it. */
@(private)
know_near :: proc(store: ^Knowledge_Store, r: ^Referent, kind: cstring) -> bool {
	t: ^Trace_Seen
	i: uint

	for i = 0; i < knowledge_store_trace_count(store); i += 1 {
		t = knowledge_store_trace_at(store, i)
		if t.bearer == 0 && t.present && string(t.kind) == string(kind) && t.level == r.level &&
		   abs(t.x - r.x) <= 1 && abs(t.y - r.y) <= 1 {
			return true
		}
	}
	return false
}


/* The container the agent was seen to put things into at least `times`
 * times, by that referent; the most often, the lowest first; or 0. */
/* Where the agent itself has put the thing at least `times` times, the most;
 * or 0: its habit for it (AGENCY.md §8), as it remembers doing it. */
@(private)
know_own_usual_place :: proc(store: ^Knowledge_Store, thing: u32, times: i64) -> u32 {
	o: ^Observation
	c: ^Referent
	i: uint
	j: uint
	best: u32
	n: i64
	most: i64

	best = 0
	most = 0
	for i = 0; i < knowledge_store_observation_count(store); i += 1 {
		o = knowledge_store_observation_at(store, i)
		c = knowledge_store_referent(store, o.other)
		if string(o.kind) != "moved" || o.actor != knowledge_store_self_referent(store) || o.subject != thing || c == nil || c.kind == nil ||
		   string(c.kind) == "#Agent" {
			continue
		}
		for n, j = 0, 0; j < knowledge_store_observation_count(store); j += 1 {
			if string(knowledge_store_observation_at(store, j).kind) == "moved" && knowledge_store_observation_at(store, j).actor == knowledge_store_self_referent(store) &&
			   knowledge_store_observation_at(store, j).subject == thing && knowledge_store_observation_at(store, j).other == o.other {
				n += 1
			}
		}
		if n >= times && (n > most || (n == most && o.other < best)) {
			most = n
			best = o.other
		}
	}
	return best
}


@(private)
know_usual_place :: proc(store: ^Knowledge_Store, actor: u32, times: i64) -> u32 {
	o: ^Observation
	c: ^Referent
	i: uint
	j: uint
	best: u32
	n: i64
	most: i64

	best = 0
	most = 0
	for i = 0; i < knowledge_store_observation_count(store); i += 1 {
		o = knowledge_store_observation_at(store, i)
		c = knowledge_store_referent(store, o.other)
		if string(o.kind) != "moved" || o.actor != actor || c == nil || c.kind == nil || string(c.kind) == "#Agent" do continue
		for n, j = 0, 0; j < knowledge_store_observation_count(store); j += 1 {
			if string(knowledge_store_observation_at(store, j).kind) == "moved" && knowledge_store_observation_at(store, j).actor == actor &&
			   knowledge_store_observation_at(store, j).other == o.other {
				n += 1
			}
		}
		if n >= times && (n > most || (n == most && o.other < best)) {
			most = n
			best = o.other
		}
	}
	return best
}


/* A rule's premise, as interpretation reads it. */
Premise_Kind :: enum u8 {
	Unreadable,         /* a premise it can't read never holds */
	Sign,               /* a trace of the kind on the referent, there now */
	Formerly,           /* one there before, and not any more */
	Misprinted,
	Unworn,
	Repeated,           /* `n` times put in the same place: the usual place */
	Wearing,            /* wear seen at least `n` */
	Near,               /* a trace of the kind on the floor at it or beside it */
	Sighted,            /* in sight now, seen as the kind */
}

Read_Premise :: struct {
	kind: Premise_Kind,
	text: cstring,      /* interned: the trace kind, or the field */
	n:    i64,
}

/* An interpretation rule (content/knowledge.tri's #Rule), read from content
 * once, as it is: content doesn't change while the world runs. */
Read_Rule :: struct {
	node:       ^tri.Node,
	tag:        cstring,            /* interned: the rule's name */
	concludes:  cstring,            /* interned: what it concludes; nil, a rule it can't use */
	deliberate: bool,
	skill:      cstring,            /* interned: the agent's field (Agent.<skill>), or nil */
	mastery:    i64,
	weight:     i32,
	repeated:   bool,               /* weighed again as what it watches changes */
	sighted:    bool,               /* over what is in sight now: weighed at every perception */
	premises:   []Read_Premise,
	/* what its premises read beyond the referent's own looks and evidence
	 * (PERFORMANCE.md decision 2) */
	misprint:   bool,               /* every referent's description, as memory fades it: weighed always */
	nearby:     bool,               /* the floor's traces: weighed for all when one came or went */
	usual:      bool,               /* others' kinds: weighed for all when a kind changed, or one is new */
}


/* The rules, read (once). */
@(private)
know_rules :: proc(self: ^Knowledge) -> []Read_Rule {
	v:    ^tri.Node
	lo:   i64
	hi:   i64
	n:    uint
	text: [64]u8

	if self.rulesRead do return self.rules[:]
	self.rulesRead = true
	tc     := world_tri(self.world)
	family := tri.family_index(tc, "rules")
	for i: uint = 0; family != nil && i < tri.index_count(family); i += 1 {
		rule := Read_Rule{}
		rule.node = tri.pattern(tc, cstring(tri.index_tag(family, i)))
		rule.tag  = world_intern(self.world, cstring(tri.index_tag(family, i)))
		v = tri.at(tc, rule.node, "deliberate")
		rule.deliberate = v != nil && tri.node_type(v) == tri.type_named(tc, "true")
		v = tri.at(tc, rule.node, "concludes")
		n = tri.print(tc, v, &text[0], size_of(text)) if v != nil else 0
		if n >= 3 {
			text[n - 1] = 0
			rule.concludes = world_intern(self.world, cstring(&text[1]))
		}
		v = tri.at(tc, rule.node, "mastery")
		rule.mastery = lo if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi else 0
		v = tri.at(tc, rule.node, "skill")
		if v != nil && tri.print(tc, v, &text[0], size_of(text)) > 2 && text[0] == '"' {
			text[len(k1_buf(text[:])) - 1] = 0
			rule.skill = world_intern(self.world, ns_utf8(k1_clip(fmt.tprintf("Agent.%s", cstring(&text[1])), 96)))
		}
		v = tri.at(tc, rule.node, "weight")
		rule.weight = i32(lo) if v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi else 0
		premises := make([dynamic]Read_Premise)
		for list := tri.at(tc, rule.node, "premises"); list != nil; list = tri.at(tc, list, "rest") {
			premise := tri.at(tc, list, "first")
			if premise == nil do break
			p := Read_Premise{}
			if tri.at(tc, premise, "repeated") != nil || tri.at(tc, premise, "wearing") != nil {
				rule.repeated = true      /* and how worn a part is seen to be: serviced, it is less */
			}
			/* the first of its features that reads, in this order */
			if v = tri.at(tc, premise, "sign"); v != nil && tri.print(tc, v, &text[0], size_of(text)) > 2 {
				p.kind = .Sign
			} else if v = tri.at(tc, premise, "formerly"); v != nil && tri.print(tc, v, &text[0], size_of(text)) > 2 {
				p.kind = .Formerly
			} else if v = tri.at(tc, premise, "misprinted"); v != nil {
				p.kind = .Misprinted
			} else if v = tri.at(tc, premise, "unworn"); v != nil && tri.print(tc, v, &text[0], size_of(text)) > 2 {
				p.kind = .Unworn
			} else if v = tri.at(tc, premise, "repeated"); v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi {
				p.kind = .Repeated
				p.n    = lo
			} else if v = tri.at(tc, premise, "wearing"); v != nil && tri.node_interval(v, &lo, &hi) != 0 && lo == hi {
				p.kind = .Wearing
				p.n    = lo
			} else if v = tri.at(tc, premise, "near"); v != nil && tri.print(tc, v, &text[0], size_of(text)) > 2 {
				p.kind = .Near
			} else if v = tri.at(tc, premise, "sighted"); v != nil && tri.print(tc, v, &text[0], size_of(text)) > 2 {
				p.kind = .Sighted
			}
			if p.kind == .Sign || p.kind == .Formerly || p.kind == .Unworn || p.kind == .Near || p.kind == .Sighted {
				text[len(k1_buf(text[:])) - 1] = 0
				p.text = world_intern(self.world, cstring(&text[1]))
			}
			rule.misprint ||= p.kind == .Misprinted
			rule.nearby   ||= p.kind == .Near
			rule.usual    ||= p.kind == .Repeated
			rule.sighted  ||= p.kind == .Sighted
			append(&premises, p)
		}
		shrink(&premises)
		rule.premises = premises[:]
		append(&self.rules, rule)
	}
	return self.rules[:]
}


/* Whether the rule's premises hold of the referent, and what the last one
 * that chooses chose (a usual place). */
@(private)
know_premises_hold :: proc(store: ^Knowledge_Store, rule: ^Read_Rule, r: ^Referent, now: i64) -> (holds: bool, choice: u32) {
	holds = true
	for &p in rule.premises {
		if !holds do break
		switch p.kind {
		case .Sign:       holds = know_bears(store, r.id, p.text, false)
		case .Formerly:   holds = know_bears(store, r.id, p.text, true)
		case .Misprinted: holds = know_misprinted(store, r.id)
		case .Unworn:     holds = know_unworn(store, r.id, p.text)
		case .Repeated:
			choice = know_usual_place(store, r.id, p.n)
			holds  = choice != 0
		case .Wearing:
			worn: i64

			holds = r.features != nil && know_int_feature(r.features, "wear", &worn) && worn >= p.n
		case .Near:       holds = r.present && know_near(store, r, p.text)
		case .Sighted:    holds = r.present && r.seen == now && r.kind != nil && string(r.kind) == string(p.text)
		case .Unreadable: holds = false      /* a premise it can't read never holds */
		}
	}
	return
}


/* What premises read of a referent itself, hashed (FNV-1a): its kind
 * alone, and with its features and place. */
@(private)
know_looks_of :: proc(r: ^Referent) -> (looks: u64, kind: u64) {
	fnv :: proc(h: u64, s: cstring) -> u64 {
		h := h
		if s == nil do return (h ~ 0xff) * 0x100000001b3
		for b in transmute([]u8)string(s) do h = (h ~ u64(b)) * 0x100000001b3
		return (h ~ 0xfe) * 0x100000001b3
	}
	kind  = fnv(0xcbf29ce484222325, r.kind)
	looks = fnv(kind, r.features)
	looks = mix(looks ~ (u64(u32(r.x)) | u64(u32(r.y)) << 32))
	looks = mix(looks ~ (u64(u32(r.level)) | (u64(1) << 32 if r.present else 0)))
	return
}


/* Immediate interpretation: each rule the agent has the expertise for, over
 * each referent; a rule whose premises all hold adds its finding.
 *
 * Incrementally (PERFORMANCE.md decision 2): a rule is weighed again for a
 * referent only when weighing it could come out otherwise than it did. What
 * premises read is the referent's looks and place, the traces it bears, the
 * observations of what it did or had done to it, and the findings about it;
 * each change to those marks it (knowledge_store_evidence_changed), and its
 * looks are compared with how they were. Weighed for every referent: a rule
 * newly within the agent's expertise; a misprint, which reads every
 * description as memory fades it; a `near` premise when the floor's traces
 * changed; a usual place when a kind changed or a referent is new; and
 * everything when investigating, or after a merge or a forgetting. A
 * finding that waited for attention is weighed again. Nothing it skips
 * would have changed: `verifyInterpretation` weighs the skipped too, and
 * counts any that would. */
knowledge_interpret :: proc(self: ^Knowledge, store: ^Knowledge_Store, deliberately: bool, budget: int, news: ^[dynamic]string) {
	r:        ^Referent
	f:        Finding
	j:        uint
	skill:    i64
	choice:   u32
	holds:    bool
	existing: ^Finding
	budget := budget

	rules := know_rules(self)
	if len(store.eligible) != len(rules) do resize(&store.eligible, len(rules))
	/* each referent: whether anything its rules read changed since they were
	 * last weighed for it */
	n            := knowledge_store_count(store)
	changed      := make([]bool, n, context.temp_allocator)
	now          := make([]Weighing, n, context.temp_allocator)
	kindsChanged := false
	for j = 0; j < n; j += 1 {
		r = knowledge_store_referent_at(store, j)
		now[j].looks, now[j].kind = know_looks_of(r)
		was, ok := store.weighed[r.id]
		changed[j] = !ok || was.retry || was.looks != now[j].looks || store.staleAll || r.id in store.stale
		kindsChanged ||= !ok || was.kind != now[j].kind
	}
	floorChanged := store.floorChanged
	store.staleAll     = false
	store.floorChanged = false
	clear(&store.stale)      /* what changes from here on is for the next time */

	for &rule, ri in rules {
		if rule.deliberate && !deliberately do continue      /* it takes thought: only when investigating */
		if rule.concludes == nil do continue
		/* expertise: the agent's own skill, which it knows */
		if rule.skill != nil {
			skill = 0
			if !world_get_field(self.world, rule.skill, knowledge_store_agent(store), &skill) || skill < rule.mastery {
				store.eligible[ri] = false
				continue
			}
		}
		all := deliberately || !store.eligible[ri] || rule.misprint || rule.sighted || (rule.nearby && floorChanged) ||
		       (rule.usual && kindsChanged)
		store.eligible[ri] = true
		/* a rule over repetition is weighed again as what it is seen to do
		 * changes (provisionally, the one kind of premise that can stop
		 * holding without merely fading: the usual place moves on) */
		for j = 0; j < n; j += 1 {
			r = knowledge_store_referent_at(store, j)
			if r.id == knowledge_store_self_referent(store) do continue
			/* unchanged, and not changed by this pass either (a finding about
			 * it another rule drew): weighing it again would come out the same */
			if !all && !changed[j] && !(r.id in store.stale) {
				if self.verifyInterpretation do know_verify_skipped(self, store, &rule, r)
				continue
			}
			existing = knowledge_store_finding(store, rule.concludes, r.id)
			/* contradicted (KNOWLEDGE.md decision 11): looking closely, no trace
			 * where one should still be; a trace merely faded, it stands */
			if existing != nil && !rule.repeated && deliberately &&
			   knowledge_contradicted(self, rule.node, r, store, world_time(self.world).ms) {
				k1_say(news, fmt.tprintf("R%d: no longer %s: the signs should still be there, and aren't",
				                         r.id, existing.kind))
				knowledge_store_retract_finding(store, rule.concludes, r.id)
				continue
			}
			if existing != nil && !rule.repeated && !rule.sighted do continue
			holds, choice = know_premises_hold(store, &rule, r, world_time(self.world).ms)
			if existing != nil {
				/* what is in sight now is drawn afresh while it is (a danger
				 * still there after running from it raises running again) */
				if holds && choice == existing.choice {
					if rule.sighted do existing.time = world_time(self.world).ms
					continue
				}
				/* its premise no longer holds as it did: retracted (KNOWLEDGE.md §9) */
				k1_say(news, fmt.tprintf("R%d: no longer %s (R%d), by %s", r.id, existing.kind,
				                         existing.choice, existing.rule))
				knowledge_store_retract_finding(store, rule.concludes, r.id)
			}
			if !holds do continue
			/* immediate interpretation spends attention (KNOWLEDGE.md §9): with
			 * none left, it waits for a boundary that has some */
			if !deliberately {
				left := budget
				budget -= 1
				if left <= 0 {
					k1_say(news, fmt.tprintf("no attention left to think R%d over", r.id))
					self.short = true      /* attended to later: it perceives again next */
					now[j].retry = true
					continue
				}
			}
			f = {}
			f.kind     = rule.concludes
			f.about    = r.id
			f.choice   = choice
			f.credence = rule.weight
			f.rule     = rule.tag
			f.time     = world_time(self.world).ms
			knowledge_store_add_finding(store, f)
			k1_say(news, fmt.tprintf("R%d: %s, by %s (%+d dB)", r.id, f.kind, f.rule, f.credence))
		}
	}
	/* as they were weighed */
	for j = 0; j < n; j += 1 do store.weighed[knowledge_store_referent_at(store, j).id] = now[j]
}


/* A pair interpretation skipped, weighed anyway: had it changed anything,
 * a miss is counted (for tests: PERFORMANCE.md decision 2). */
@(private)
know_verify_skipped :: proc(self: ^Knowledge, store: ^Knowledge_Store, rule: ^Read_Rule, r: ^Referent) {
	existing := knowledge_store_finding(store, rule.concludes, r.id)
	if existing != nil && !rule.repeated do return
	holds, choice := know_premises_hold(store, rule, r, world_time(self.world).ms)
	if existing == nil && !holds do return
	if existing != nil && holds && choice == existing.choice do return
	self.interpretationMisses += 1
	append(&interpretation_missed, fmt.aprintf("agent %d, R%d, by %s at %dms: skipped, but it would %s",
	                                           knowledge_store_agent(store), r.id, rule.tag, world_time(self.world).ms,
	                                           "conclude" if existing == nil else "retract"))
}


/* Seen again with less of a wear the rules watch for (#Unworn) than it had
 * when last seen: noticed, an anomaly, kept as an observation for them. */
knowledge_notice_wear_lost :: proc(self: ^Knowledge, r: ^Referent, features: string, store: ^Knowledge_Store, now: i64,
                                   news: ^[dynamic]string) {
	rule: ^tri.Node
	list: ^tri.Node
	v: ^tri.Node
	tc: ^tri.Content
	family: ^tri.Index
	o: Observation
	i: uint
	before: i64
	after: i64
	field: [64]u8

	if r.features == nil || r.id == knowledge_store_self_referent(store) do return
	tc     = world_tri(self.world)
	family = tri.family_index(tc, "rules")
	for i = 0; family != nil && i < tri.index_count(family); i += 1 {
		rule = tri.pattern(tc, cstring(tri.index_tag(family, i)))
		for list = tri.at(tc, rule, "premises"); list != nil && tri.at(tc, list, "first") != nil; list = tri.at(tc, list, "rest") {
			v = tri.at(tc, tri.at(tc, list, "first"), "unworn")
			if v == nil || tri.print(tc, v, &field[0], size_of(field)) < 3 do continue
			field[len(k1_buf(field[:])) - 1] = 0
			if !know_int_feature(r.features, cstring(&field[1]), &before) || !know_int_feature(ns_utf8(features), cstring(&field[1]), &after) ||
			   after >= before || know_unworn(store, r.id, cstring(&field[1])) {
				continue
			}
			o = {}
			o.time     = now
			o.kind     = world_intern(self.world, "unworn")
			o.subject  = r.id
			o.content  = world_intern(self.world, cstring(&field[1]))
			o.salience = BG_ANOMALY
			knowledge_store_add_observation(store, o, false)
			k1_say(news, fmt.tprintf("R%d looks new: its %s is gone", r.id, cstring(&field[1])))
		}
	}
}

package lab

/*
 * Saves (ARCHITECTURE.md "Saves"): the world's authoritative state and the
 * committer's, as text. Saved: the entity table and ID counter, every
 * component store, locations, edges, tombstones, history, the clock and
 * boundary, and the commit position and deferred groups. Rebuilt on load:
 * everything derived (there are no indexes yet). A restored world takes the
 * same next step as one that never saved.
 *
 * Fields and types are written by name, so a save can be read into content
 * that has changed: a field the content no longer has is an error, and a
 * field the save lacks starts at zero.
 *
 * (ported from the Objective-C lab's save/BGSave.m)
 */

import "core:c/libc"
import "core:fmt"
import "core:mem"
import "core:strings"
import tri "../../triangle/odin/triangle"


/*
 * The format, one record per line, tokens separated by spaces; strings are
 * quoted with \" \\ \n escapes, and an absent string is -:
 *
 *   bruggadung-save 1
 *   content <hash>
 *   world <seed> <time ms> <boundary> <next ID> <commit position>
 *   entity <id> "<blueprint>" <seed>
 *   record <Kind> <id> <field> <value> ...       a type is "<type name>"
 *   location <id> <location>
 *   edge <kind> <from> <to>
 *   tombstone <id> "<blueprint>" <successor> <cause> "<reason>"
 *   event <index> <boundary> <round> "<kind>" <subject> <other> <amount> <detail> <cause> <group> <location> <actor>
 *   tile <x> <y> <level> water <mL>
 *   group <phase> <cause> <handles> "<source>" <actor>
 *   proposal <kind> <target> <unit> <other> <unit> <value> <edge> <name> <key> <handle> <location>
 *   domain <name> <what the domain keeps>
 *   end
 *
 * where <location> is <form> <place> <x> <y> <level> <slot> "<role>".
 */

@(private = "file")
BG_SAVE_VERSION :: 1


/* --- writing ----------------------------------------------------------------- */

// The bytes as they are: appendFormat:@"%c" of each (the lab's strings are
// ASCII).
@(private = "file")
put_string :: proc(out: ^strings.Builder, s: cstring) {
	if s == nil {
		strings.write_string(out, " -")
		return
	}
	strings.write_string(out, " \"")
	for p := ([^]u8)(s); p[0] != 0; p = p[1:] {
		if p[0] == '"' || p[0] == '\\' {
			strings.write_byte(out, '\\')
			strings.write_byte(out, p[0])
		} else if p[0] == '\n' {
			strings.write_string(out, "\\n")
		} else {
			strings.write_byte(out, p[0])
		}
	}
	strings.write_string(out, "\"")
}


@(private = "file")
put_location :: proc(out: ^strings.Builder, loc: Location) {
	loc := loc
	fmt.sbprintf(out, " %d %d %d %d %d %d", i32(loc.form), loc.place, loc.x, loc.y, loc.level, loc.slot)
	put_string(out, location_role_c(&loc))
}


@(private = "file")
put_record :: proc(out: ^strings.Builder, world: ^World, kind: uint, entity: Entity_ID, record: rawptr) {
	info: ^Component_Info
	f:    ^Field_Info
	p:    rawptr

	info = world_kind_info(world, kind)
	fmt.sbprintf(out, "record %s %d", info.name, entity)
	for i: uint = 0; i < info.nfields; i += 1 {
		f = &info.fields[i]
		p = rawptr(uintptr(record) + f.offset)
		switch f.value {
		case VALUE_QUANTITY:
			fmt.sbprintf(out, " %s %d", f.name, (^i64)(p)^)
		case VALUE_REF:
			fmt.sbprintf(out, " %s %d", f.name, (^u64)(p)^)
		case VALUE_BOOL:
			fmt.sbprintf(out, " %s %s", f.name, "true" if (^bool)(p)^ else "false")
		case VALUE_TYPE:
			fmt.sbprintf(out, " %s", f.name)
			put_string(out, tri.type_name(world_tri(world), tri.Type((^u32)(p)^)))
		case VALUE_TEXT:
			fmt.sbprintf(out, " %s", f.name)
			put_string(out, (^cstring)(p)^)
		case:
			/* structures are not stored yet */
		}
	}
	strings.write_string(out, "\n")
}


/* The save as text. Each saved system (domains, knowledge) checks in first,
 * and adds what it keeps itself as "domain <name> ..." lines. */
// the domains as []Saved_System (nil for none); the text in the
// temporary allocator.
save :: proc(world: ^World, committer: ^Committer, domains: []Saved_System) -> string {
	state:    string
	domain:   Saved_System
	info:     ^Entity_Info
	stone:    ^Tombstone
	ev:       ^Event
	edge:     ^Edge
	p:        ^Proposal
	group:    ^Proposal_Group
	out:      strings.Builder
	lines:    []string
	deferred: []^Proposal_Group
	store:    ^Store

	/* stocks at rest first: every domain checks in, and keeps its own state aside */
	out = strings.builder_make(context.temp_allocator)
	for i := 0; i < len(domains); i += 1 {
		domain = domains[i]
		lines  = domain.saved_state(domain.data)
		for j := 0; j < len(lines); j += 1 {
			fmt.sbprintf(&out, "domain %s %s\n", domain.name(domain.data), lines[j])
		}
	}
	state = strings.to_string(out)
	out   = strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&out, "bruggadung-save %d\n", BG_SAVE_VERSION)
	fmt.sbprintf(&out, "content %016x\n", tri.content_hash(world_content_build(world)))
	fmt.sbprintf(&out, "world %d %d %d %d %d\n", world_seed(world), world_time(world).ms,
	             world_boundary(world), world_next_id(world), committer_position(committer))
	/* terrain (TERRAIN.md): its map, then the chunks that differ from it,
	 * each cell by kind, in runs */
	if world_terrain(world) != nil {
		terrain: ^Terrain
		cells:   [BG_CHUNK * BG_CHUNK]Terrain_Kind
		corners: [][3]i32
		nchunks: uint
		run:     uint

		terrain = world_terrain(world)
		fmt.sbprintf(&out, "terrain %s\n", terrain_map(terrain) if terrain_map(terrain) != nil else "-")
		nchunks = terrain_changed(terrain, nil, 0)
		corners = make([][3]i32, nchunks if nchunks != 0 else 1)
		terrain_changed(terrain, raw_data(corners), nchunks)
		for c: uint = 0; c < nchunks; c += 1 {
			terrain_chunk_cells(terrain, corners[c][0], corners[c][1], corners[c][2], raw_data(cells[:]))
			fmt.sbprintf(&out, "terrain-chunk %d %d %d", corners[c][0], corners[c][1], corners[c][2])
			for cell: uint = 0; cell < BG_CHUNK * BG_CHUNK; cell += run {
				for run = 1; cell + run < BG_CHUNK * BG_CHUNK && cells[cell + run] == cells[cell]; run += 1 {
				}
				fmt.sbprintf(&out, " %s*%d", terrain_kind_info(terrain, cells[cell]).name if cells[cell] != 0 else "-",
				             run)
			}
			strings.write_string(&out, "\n")
		}
		delete(corners)
	}

	/* the reality bubble's anchors, centres and all, and its leases */
	{
		reality: ^Reality
		e:       Entity_ID
		until:   i64
		cx:      i32
		cy:      i32
		cz:      i32
		centred: bool
		kind:    i32

		reality = world_reality(world)
		for i: uint = 0; i < reality_anchor_count(reality); i += 1 {
			e = reality_anchor_at(reality, i, &kind, &cx, &cy, &cz, &centred)
			fmt.sbprintf(&out, "anchor %d %s %d %d %d %d\n", e, reality_kind_name(reality, kind),
			             cx, cy, cz, 1 if centred else 0)
		}
		for i: uint = 0; i < reality_lease_count(reality); i += 1 {
			e = reality_lease_at(reality, i, &until)
			fmt.sbprintf(&out, "lease %d %d\n", e, until)
		}
	}

	store = world_entities(world)
	for i: uint = 0; i < store_count(store); i += 1 {
		info = (^Entity_Info)(store_record_at_index(store, i))
		fmt.sbprintf(&out, "entity %d", store_entity_at_index(store, i))
		put_string(&out, info.blueprint)
		fmt.sbprintf(&out, " %d\n", info.seed)
	}
	for k: uint = 0; k < world_kind_count(world); k += 1 {
		store = world_store_for_kind(world, k)
		for i: uint = 0; i < store_count(store); i += 1 {
			put_record(&out, world, k, store_entity_at_index(store, i), store_record_at_index(store, i))
		}
	}
	store = world_locations(world)
	for i: uint = 0; i < store_count(store); i += 1 {
		fmt.sbprintf(&out, "location %d", store_entity_at_index(store, i))
		put_location(&out, (^Location)(store_record_at_index(store, i))^)
		strings.write_string(&out, "\n")
	}
	for i: uint = 0; i < world_edge_count(world); i += 1 {
		edge = world_edge_at(world, i)
		fmt.sbprintf(&out, "edge %s %d %d\n", EDGE_KIND_NAMES[edge.kind], edge.from, edge.to)
	}
	store = world_tombstones(world)
	for i: uint = 0; i < store_count(store); i += 1 {
		stone = (^Tombstone)(store_record_at_index(store, i))
		fmt.sbprintf(&out, "tombstone %d", store_entity_at_index(store, i))
		put_string(&out, stone.blueprint)
		fmt.sbprintf(&out, " %d %d", stone.successor, stone.cause)
		put_string(&out, cstring(&stone.reason[0]))
		strings.write_string(&out, "\n")
	}
	/* history's place (KNOWLEDGE.md decision 21), then what of it is kept,
	 * and what was compacted, counted */
	{
		window, compactAt, whole, due, next := world_history_place(world)
		fmt.sbprintf(&out, "history %d %d %d %d %d\n", window, compactAt, whole, due, next)
	}
	for d in world_digests(world) {
		fmt.sbprintf(&out, "digest %d %d %d %d %d %d", d.from, d.until, 1 if d.placed else 0, d.cx, d.cy, d.level)
		put_string(&out, d.kind)
		put_string(&out, d.detail)
		fmt.sbprintf(&out, " %d %d %d %d\n", d.actor, d.count, d.first, d.last)
	}
	for &kept in world_history(world) {
		ev = &kept
		fmt.sbprintf(&out, "event %d %d %d", ev.index, ev.boundary, ev.round)
		put_string(&out, ev.kind)
		fmt.sbprintf(&out, " %d %d %d", ev.subject, ev.other, ev.amount)
		put_string(&out, ev.detail)
		fmt.sbprintf(&out, " %d %d", ev.cause, ev.group)
		put_location(&out, ev.location)
		fmt.sbprintf(&out, " %d %d\n", ev.actor, 1 if ev.diagnostic else 0)
	}
	{
		wet: [][3]i32
		n:   uint

		n   = world_wet_tiles(world, nil, 0)
		wet = make([][3]i32, n if n != 0 else 1)
		world_wet_tiles(world, raw_data(wet), n)
		for i: uint = 0; i < n; i += 1 {
			fmt.sbprintf(&out, "tile %d %d %d water %d\n", wet[i][0], wet[i][1], wet[i][2],
			             world_water_at_x(world, wet[i][0], wet[i][1], wet[i][2]))
		}
		delete(wet)
	}
	deferred = committer_deferred_groups(committer)
	for i := 0; i < len(deferred); i += 1 {
		group = deferred[i]
		fmt.sbprintf(&out, "group %d %d %d", i32(proposal_group_phase(group)), proposal_group_cause(group),
		             proposal_group_handle_count(group))
		put_string(&out, ns_utf8(proposal_group_source(group)))
		fmt.sbprintf(&out, " %d %d %d\n", proposal_group_actor(group), proposal_group_weight(group),
		             1 if proposal_group_diagnostic(group) else 0)
		for j: uint = 0; j < proposal_group_count(group); j += 1 {
			p = &proposal_group_proposals(group)[j]
			fmt.sbprintf(&out, "proposal %d %d %d %d %d %d %d", i32(p.kind),
			             p.target.entity, p.target.unit,
			             p.other.entity, p.other.unit,
			             p.value, i32(p.edge))
			put_string(&out, p.name)
			put_string(&out, p.key)
			fmt.sbprintf(&out, " %d", p.handle)
			put_location(&out, p.location)
			fmt.sbprintf(&out, " %d", 1 if p.expects else 0)
			put_location(&out, p.expected)
			strings.write_string(&out, "\n")
		}
	}
	strings.write_string(&out, state)
	strings.write_string(&out, "end\n")
	return strings.to_string(out)
}


/* The lines a save keeps for the named domain, for -restoreSavedState:. */
// In the temporary allocator.
saved_domain_state :: proc(text: string, domain: string) -> []string {
	lines:  [dynamic]string
	all:    []string
	prefix: string
	line:   string

	lines  = make([dynamic]string, context.temp_allocator)
	prefix = fmt.tprintf("domain %s ", domain)
	all    = ns_components_separated(text, "\n")
	for i := 0; i < len(all); i += 1 {
		line = all[i]
		if ns_has_prefix(line, prefix) do append(&lines, line[len(prefix):])
	}
	return lines[:]
}


/* --- reading ----------------------------------------------------------------- */

@(private = "file")
BG_MAX_TOKENS :: 1100     /* a terrain chunk: up to 1024 runs */

@(private = "file")
BG_Line :: struct {
	tokens: [BG_MAX_TOKENS]cstring,
	quoted: [BG_MAX_TOKENS]bool,
	n:      i32,
}

/* Splits a line in place. NO if a string is unterminated or there are too many tokens. */
@(private = "file")
split_line :: proc(s: [^]u8, line: ^BG_Line) -> bool {
	s := s
	w: [^]u8

	line.n = 0
	for {
		for s[0] == ' ' do s = s[1:]
		if s[0] == 0 do return true
		if line.n == BG_MAX_TOKENS do return false
		line.quoted[line.n] = s[0] == '"'
		if s[0] == '"' {
			s = s[1:]
			w = s
			line.tokens[line.n] = cstring(w)
			for s[0] != 0 && s[0] != '"' {
				if s[0] == '\\' && s[1] != 0 {
					s = s[1:]
					w[0] = '\n' if s[0] == 'n' else s[0]
					w = w[1:]
					s = s[1:]
					continue
				}
				w[0] = s[0]
				w = w[1:]
				s = s[1:]
			}
			if s[0] != '"' do return false
			s = s[1:]
			w[0] = 0
		} else {
			line.tokens[line.n] = cstring(s)
			for s[0] != 0 && s[0] != ' ' do s = s[1:]
			if s[0] != 0 {
				s[0] = 0
				s = s[1:]
			}
		}
		line.n += 1
	}
}


@(private = "file")
token_string :: proc(line: ^BG_Line, i: i32) -> cstring {
	if i >= line.n do return nil
	if !line.quoted[i] && string(line.tokens[i]) == "-" do return nil
	return line.tokens[i]
}


@(private = "file")
token_u64 :: proc(line: ^BG_Line, i: i32) -> u64 {
	return u64(libc.strtoull(line.tokens[i], nil, 10)) if i < line.n else 0
}


@(private = "file")
token_i64 :: proc(line: ^BG_Line, i: i32) -> i64 {
	return i64(libc.strtoll(line.tokens[i], nil, 10)) if i < line.n else 0
}


// strncpy( dst, src, size - 1) into a zeroed buffer of `size`.
@(private = "file")
copy_cut :: proc(dst: []u8, src: cstring) {
	p := ([^]u8)(src)
	for i := 0; i < len(dst) - 1 && p[i] != 0; i += 1 do dst[i] = p[i]
}


@(private = "file")
token_location :: proc(line: ^BG_Line, i: i32) -> Location {
	loc:  Location
	role: cstring

	loc       = location_make_none()
	loc.form  = Location_Form(token_i64(line, i))
	loc.place = token_u64(line, i + 1)
	loc.x     = i32(token_i64(line, i + 2))
	loc.y     = i32(token_i64(line, i + 3))
	loc.level = i32(token_i64(line, i + 4))
	loc.slot  = i32(token_i64(line, i + 5))
	role      = token_string(line, i + 6)
	if role != nil do copy_cut(loc.role[:], role)
	return loc
}


// "" for none (nil).
@(private = "file")
restore_record :: proc(world: ^World, line: ^BG_Line) -> string {
	info:   ^Component_Info
	f:      ^Field_Info
	text:   cstring
	kind:   uint
	type:   tri.Type
	record: rawptr
	p:      rawptr

	kind = world_kind_named(world, line.tokens[1])
	if kind == NOT_FOUND do return fmt.tprintf("the content has no component %s", line.tokens[1])
	info      = world_kind_info(world, kind)
	record, _ = mem.alloc(int(info.size))     // calloc: zeroed
	for i: i32 = 3; i + 1 < line.n; i += 2 {
		f = nil
		for j: uint = 0; j < info.nfields && f == nil; j += 1 {
			if string(info.fields[j].name) == string(line.tokens[i]) do f = &info.fields[j]
		}
		if f == nil {
			free(record)
			return fmt.tprintf("the content has no field %s.%s", info.name, line.tokens[i])
		}
		p = rawptr(uintptr(record) + f.offset)
		switch f.value {
		case VALUE_QUANTITY:
			(^i64)(p)^ = token_i64(line, i + 1)
		case VALUE_REF:
			(^u64)(p)^ = token_u64(line, i + 1)
		case VALUE_BOOL:
			(^bool)(p)^ = string(line.tokens[i + 1]) == "true"
		case VALUE_TYPE:
			type = tri.type_named(world_tri(world), line.tokens[i + 1])
			if type == tri.BOTTOM {
				free(record)
				return fmt.tprintf("the content has no type %s (for %s.%s)", line.tokens[i + 1],
				                   info.name, f.name)
			}
			(^u32)(p)^ = u32(type)
		case VALUE_TEXT:
			text = token_string(line, i + 1)
			(^cstring)(p)^ = world_intern(world, text) if text != nil else nil
		case:
		}
	}
	world_set_record(world, record, kind, token_u64(line, 2))
	free(record)
	return ""
}


// strrchr( s, c)
@(private = "file")
last_byte :: proc(s: cstring, c: u8) -> [^]u8 {
	p := ([^]u8)(s)
	last: [^]u8 = nil
	for i := 0; ; i += 1 {
		if p[i] == c do last = p[i:]
		if p[i] == 0 do break
	}
	return last
}


/* A world restored from a save, on `content`, or nil with the reason. The
 * groups that were deferred come back in `deferred`, for the committer made
 * on the new world (with -restoreDeferred:), and its commit position in
 * `position`. */
// deferred is ^[]^Proposal_Group (the slice in the temporary
// allocator; the groups autoreleased), error ^string; each may be nil.
restore :: proc(text: string, content: ^tri.Content, deferred: ^[]^Proposal_Group, position: ^u64,
                error: ^string) -> ^World {
	world:   ^World
	group:   ^Proposal_Group
	groups:  [dynamic]^Proposal_Group
	problem: string                 // "" for none (nil)
	stone:   Tombstone
	ev:      Event
	p:       Proposal
	line:    BG_Line
	s:       string
	buf:     cstring
	next:    [^]u8
	cur:     [^]u8
	edge:    int
	lineno:  i32
	ended:   bool

	buf     = strings.clone_to_cstring(text)
	world   = nil
	group   = nil
	groups  = make([dynamic]^Proposal_Group, context.temp_allocator)
	problem = ""
	ended   = false
	lineno  = 0
	for cur = ([^]u8)(buf); cur != nil && cur[0] != 0 && problem == "" && !ended; cur = next {
		next = nil
		for k := 0; cur[k] != 0; k += 1 {
			if cur[k] == '\n' {
				next = cur[k:]
				break
			}
		}
		if next != nil {
			next[0] = 0
			next = next[1:]
		}
		lineno += 1
		if !split_line(cur, &line) {
			problem = "a malformed line"
			break
		}
		if line.n == 0 do continue
		s = string(line.tokens[0])
		if lineno == 1 {
			if s != "bruggadung-save" || token_i64(&line, 1) != BG_SAVE_VERSION {
				problem = "not a bruggadung save of a version this lab reads"
			}
			continue
		}
		if s == "content" do continue         /* by name, so other content can read it */
		if s == "world" {
			world = world_with_content(content, token_u64(&line, 1), &problem)
			if world != nil {                 // messages to nil did nothing
				world_set_time(world, time_make(token_i64(&line, 2)))
				world_set_boundary(world, token_u64(&line, 3))
				world_set_next_id(world, token_u64(&line, 4))
			}
			if position != nil do position^ = token_u64(&line, 5)
			continue
		}
		if world == nil {
			problem = "no world line before the state"
			break
		}
		if s == "entity" {
			world_add_entity(world, token_u64(&line, 1),
			                 token_string(&line, 2) if token_string(&line, 2) != nil else "",
			                 token_u64(&line, 3))
		} else if s == "record" {
			problem = restore_record(world, &line) if line.n >= 3 else "a short record"
		} else if s == "location" {
			world_set_location(world, token_location(&line, 2), token_u64(&line, 1))
		} else if s == "edge" {
			for edge = 0; edge < int(Edge_Kind.Kind_Count); edge += 1 {
				if line.n > 1 && string(line.tokens[1]) == string(EDGE_KIND_NAMES[Edge_Kind(edge)]) do break
			}
			if edge == int(Edge_Kind.Kind_Count) {
				problem = "an unknown edge kind"
			} else {
				world_add_edge(world, Edge_Kind(edge), token_u64(&line, 2), token_u64(&line, 3))
			}
		} else if s == "tombstone" {
			stone = {}
			stone.blueprint = token_string(&line, 2) if token_string(&line, 2) != nil else ""
			stone.successor = token_u64(&line, 3)
			stone.cause     = token_u64(&line, 4)
			if token_string(&line, 5) != nil do copy_cut(stone.reason[:], token_string(&line, 5))
			world_restore_tombstone(world, stone, token_u64(&line, 1))
		} else if s == "history" {
			world_restore_history(world, token_i64(&line, 1), token_i64(&line, 2), token_u64(&line, 3),
			                      token_u64(&line, 4), token_u64(&line, 5))
		} else if s == "digest" {
			world_restore_digest(world, Digest{
				from   = token_i64(&line, 1),
				until  = token_i64(&line, 2),
				placed = token_u64(&line, 3) != 0,
				cx     = i32(token_i64(&line, 4)),
				cy     = i32(token_i64(&line, 5)),
				level  = i32(token_i64(&line, 6)),
				kind   = world_intern(world, token_string(&line, 7) if token_string(&line, 7) != nil else ""),
				detail = world_intern(world, token_string(&line, 8)) if token_string(&line, 8) != nil else nil,
				actor  = token_u64(&line, 9),
				count  = token_u64(&line, 10),
				first  = token_u64(&line, 11),
				last   = token_u64(&line, 12),
			})
		} else if s == "event" {
			ev = {}
			ev.boundary = token_u64(&line, 2)
			ev.round    = u32(token_u64(&line, 3))
			ev.kind     = world_intern(world, token_string(&line, 4) if token_string(&line, 4) != nil else "")
			ev.subject  = token_u64(&line, 5)
			ev.other    = token_u64(&line, 6)
			ev.amount   = token_i64(&line, 7)
			ev.detail   = world_intern(world, token_string(&line, 8)) if token_string(&line, 8) != nil else nil
			ev.cause    = token_u64(&line, 9)
			ev.group    = token_u64(&line, 10)
			ev.location = token_location(&line, 11)
			ev.actor    = token_u64(&line, 18)
			ev.diagnostic = token_u64(&line, 19) != 0
			ev.index    = token_u64(&line, 1)
			if !world_restore_event(world, ev) do problem = "events out of order"
		} else if s == "terrain" {
			if token_string(&line, 1) != nil do world_set_terrain_map(world, token_string(&line, 1), &problem)
		} else if s == "terrain-chunk" {
			x0:   i32
			y0:   i32
			z:    i32
			at:   int
			run:  int
			star: [^]u8

			x0 = i32(token_i64(&line, 1))
			y0 = i32(token_i64(&line, 2))
			z  = i32(token_i64(&line, 3))
			at = 0
			for t: i32 = 4; t < line.n && problem == ""; t += 1 {
				star = last_byte(line.tokens[t], '*')
				run  = int(libc.strtol(cstring(star[1:]), nil, 10)) if star != nil else 0
				if star == nil || run <= 0 || at + run > BG_CHUNK * BG_CHUNK {
					problem = "a malformed terrain chunk"
					break
				}
				star[0] = 0
				for r := 0; r < run; r, at = r + 1, at + 1 {
					if string(line.tokens[t]) != "-" &&
					   !world_set_terrain(world, line.tokens[t], x0 + i32(at % BG_CHUNK), y0 + i32(at / BG_CHUNK), z) {
						problem = fmt.tprintf("no terrain kind %s, or a chunk off the map", line.tokens[t])
					}
				}
			}
			if problem == "" && at != BG_CHUNK * BG_CHUNK do problem = "a malformed terrain chunk"
		} else if s == "anchor" {
			if line.n < 7 || reality_kind_named(world_reality(world), token_string(&line, 2)) < 0 {
				problem = "an anchor of no kind"
			} else {
				reality_restore_anchor(world_reality(world), token_u64(&line, 1),
				                       reality_kind_named(world_reality(world), token_string(&line, 2)),
				                       i32(token_i64(&line, 3)), i32(token_i64(&line, 4)),
				                       i32(token_i64(&line, 5)), token_i64(&line, 6) != 0)
			}
		} else if s == "lease" {
			reality_lease(world_reality(world), token_u64(&line, 1), token_i64(&line, 2))
		} else if s == "tile" {
			if line.n < 6 || string(line.tokens[4]) != "water" {
				problem = "an unknown tile stock"
			} else {
				world_set_water(world, token_i64(&line, 5), i32(token_i64(&line, 1)), i32(token_i64(&line, 2)),
				                i32(token_i64(&line, 3)))
			}
		} else if s == "group" {
			group = proposal_group_group_with_phase(Phase(token_i64(&line, 1)),
			                                        string(token_string(&line, 4) if token_string(&line, 4) != nil else ""))
			proposal_group_set_cause(group, token_u64(&line, 2))
			proposal_group_set_handle_count(group, token_u64(&line, 3))
			proposal_group_set_actor(group, token_u64(&line, 5))
			proposal_group_set_weight(group, token_u64(&line, 6))
			proposal_group_set_diagnostic(group, token_u64(&line, 7) != 0)
			append(&groups, group)       // autoreleased: they live as long as the array would have
		} else if s == "proposal" {
			if group == nil {
				problem = "a proposal outside a group"
				break
			}
			p = {}
			p.kind          = Proposal_Kind(token_i64(&line, 1))
			p.target.entity = token_u64(&line, 2)
			p.target.unit   = u32(token_u64(&line, 3))
			p.other.entity  = token_u64(&line, 4)
			p.other.unit    = u32(token_u64(&line, 5))
			p.value         = token_i64(&line, 6)
			p.edge          = Edge_Kind(token_i64(&line, 7))
			p.name          = token_string(&line, 8)
			p.key           = token_string(&line, 9)
			p.handle        = token_u64(&line, 10)
			p.location      = token_location(&line, 11)
			p.expects       = token_i64(&line, 18) != 0
			p.expected      = token_location(&line, 19)
			proposal_group_add_proposal(group, p)
		} else if s == "domain" {
			/* the domain's own: saved_domain_state */
		} else if s == "end" {
			ended = true
		} else {
			problem = fmt.tprintf("an unknown record \"%s\"", s)
		}
	}
	delete(buf)
	if problem == "" && !ended do problem = "the save ends early"
	if problem != "" {
		if error != nil do error^ = fmt.tprintf("cannot restore the save: %s (line %d)", problem, lineno)
		return nil
	}
	if deferred != nil do deferred^ = groups[:]
	/* restoring wrote every record; nothing has happened since the save */
	{
		n: uint

		free(world_take_touched(world, &n))
		free(world_take_vacated(world, &n))
		world_mark_anchors_settled(world)
	}
	return world
}

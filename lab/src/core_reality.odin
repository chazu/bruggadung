package lab

/*
 * BGReality — the reality bubble (REALITY.md, step 2): anchors, the levels
 * of detail they give the chunks around them, and the leases contact
 * gives. Plain C: the world owns one, and asks it.
 */

/*
 * BGReality: anchor kinds read once from content; anchors and leases in
 * small sorted arrays (there are few anchors; leases last a while).
 */

import "core:fmt"
import "core:mem"
import tri "../../triangle/odin/triangle"

Detail :: enum i32 {
	Frozen   = 0,
	Abstract = 1,
	Reduced  = 2,
	Full     = 3,
}

Reach :: struct {
	across: i32,            /* chunks, any direction on its level */
	up:     i32,            /* levels */
	down:   i32,
}

@(private = "file")
BG_CHUNK_TILES :: 32

@(private = "file")
Anchor_Kind :: struct {
	name:   cstring,
	reach:  [3]Reach,       /* abstract, reduced, full */
	margin: i32,
}

@(private = "file")
Anchor :: struct {
	entity:  Entity_ID,
	kind:    i32,
	cx:      i32,
	cy:      i32,
	z:       i32,
	centred: bool,
}

@(private = "file")
Lease :: struct {
	entity: Entity_ID,
	until:  i64,
}

Reality :: struct {
	kinds:        [^]Anchor_Kind,
	nkinds:       i32,
	contact:      [^]cstring,
	ncontact:     i32,
	lease:        i64,
	anchors:      [^]Anchor,
	nanchors:     uint,
	anchorcap:    uint,
	leases:       [^]Lease,
	nleases:      uint,
	leasecap:     uint,
	reducedOwn:   bool,         /* reduced agents sense only what they take part in */
	reducedEvery: i64,          /* reduced agents' own wakes, put off to this cadence */
}

// realloc: the block resized, in the context allocator.
@(private = "file")
realloc :: proc(p: rawptr, old_size, new_size: uint) -> rawptr {
	q, _ := mem.resize(p, int(old_size), int(new_size))
	return q
}

@(private = "file")
int_at :: proc(content: ^tri.Content, node: ^tri.Node, path: cstring, otherwise: i64) -> i64 {
	lo: i64
	hi: i64

	if node != nil && tri.node_interval(tri.at(content, node, path), &lo, &hi) != 0 && lo == hi do return lo
	return otherwise
}

@(private = "file")
dup_string :: proc(s: cstring) -> cstring {
	n: uint
	d: [^]u8

	n = uint(len(s)) + 1
	d = make([^]u8, n)
	mem.copy(d, rawptr(s), int(n))
	return cstring(d)
}

// A content instance by its tag, its defaults applied.
node_of :: proc(content: ^tri.Content, tag: cstring) -> ^tri.Node {
	node: ^tri.Node

	node = tri.spec(content, tag)          /* its defaults applied */
	return node if node != nil else tri.pattern(content, tag)
}

/* From content: the `anchors` family's kinds, and the `contact` rule. */
reality_new :: proc(content: ^tri.Content) -> ^Reality {
	levels := [3]string{"abstract", "reduced", "full"}
	node: ^tri.Node
	list: ^tri.Node
	family: ^tri.Index
	r: ^Reality
	i: uint
	n: uint
	k: uint
	path: cstring
	text: [64]u8

	r = new(Reality)
	family = tri.family_index(content, "anchors")
	n = tri.index_count(family) if family != nil else 0
	r.kinds = make([^]Anchor_Kind, n + 1)
	for i = 0; i < n; i += 1 {
		node = node_of(content, cstring(tri.index_tag(family, i)))
		r.kinds[i].name = dup_string(cstring(tri.index_tag(family, i)))
		r.kinds[i].margin = i32(int_at(content, node, "margin", 4))
		for k = 0; k < 3; k += 1 {
			path = fmt.ctprintf("%s.across", levels[k])
			r.kinds[i].reach[k].across = i32(int_at(content, node, path, -1))
			path = fmt.ctprintf("%s.up", levels[k])
			r.kinds[i].reach[k].up = i32(int_at(content, node, path, 0))
			path = fmt.ctprintf("%s.down", levels[k])
			r.kinds[i].reach[k].down = i32(int_at(content, node, path, 0))
		}
	}
	r.nkinds = i32(n)

	family = tri.family_index(content, "levels")
	for i = 0; family != nil && i < tri.index_count(family); i += 1 {
		if string(cstring(tri.index_tag(family, i))) != "reduced" do continue
		node = node_of(content, cstring(tri.index_tag(family, i)))
		r.reducedEvery = int_at(content, node, "every", 0)
		n = tri.print(content, tri.at(content, node, "senses"), &text[0], size_of(text)) if node != nil && tri.at(content, node, "senses") != nil else 0
		r.reducedOwn = n > 0 && string(cstring(&text[0])) == "\"own\""
	}

	family = tri.family_index(content, "contact")
	node = node_of(content, cstring(tri.index_tag(family, 0))) if family != nil && tri.index_count(family) != 0 else nil
	r.lease = int_at(content, node, "lease", 0)
	for list = tri.at(content, node, "kinds") if node != nil else nil; list != nil && tri.at(content, list, "first") != nil;
	    list = tri.at(content, list, "rest") {
		n = tri.print(content, tri.at(content, list, "first"), &text[0], size_of(text))
		if n < 2 || n >= size_of(text) || text[0] != '"' do continue
		text[n - 1] = 0
		r.contact = ([^]cstring)(realloc(r.contact, uint(r.ncontact) * size_of(cstring), uint(r.ncontact + 1) * size_of(cstring)))
		r.contact[r.ncontact] = dup_string(cstring(&text[1]))
		r.ncontact += 1
	}
	return r
}

reality_free :: proc(r: ^Reality) {
	i: i32

	if r == nil do return
	for i = 0; i < r.nkinds; i += 1 do delete(r.kinds[i].name)
	free(r.kinds)
	for i = 0; i < r.ncontact; i += 1 do delete(r.contact[i])
	free(r.contact)
	free(r.anchors)
	free(r.leases)
	free(r)
}

detail_name :: proc(detail: Detail) -> cstring {
	#partial switch detail {
	case .Full:     return "full"
	case .Reduced:  return "reduced"
	case .Abstract: return "abstract"
	case:           return "frozen"
	}
}

/* Kinds of anchor: -1 if none is named so. */
reality_kind_named :: proc(r: ^Reality, name: cstring) -> i32 {
	i: i32

	for i = 0; name != nil && i < r.nkinds; i += 1 {
		if string(r.kinds[i].name) == string(name) do return i
	}
	return -1
}

reality_kind_name :: proc(r: ^Reality, kind: i32) -> cstring {
	return r.kinds[kind].name if kind >= 0 && kind < r.nkinds else nil
}

reality_reach :: proc(r: ^Reality, kind: i32, level: Detail) -> Reach {
	none: Reach

	none = {}
	none.across = -1
	if kind < 0 || kind >= r.nkinds || level < .Abstract || level > .Full do return none
	return r.kinds[kind].reach[i32(level) - i32(Detail.Abstract)]
}

/* --- anchors -------------------------------------------------------------------- */

@(private = "file")
anchor_index :: proc(r: ^Reality, entity: Entity_ID, found: ^bool) -> uint {
	lo: uint
	hi: uint
	mid: uint

	lo = 0
	hi = r.nanchors
	for lo < hi {
		mid = (lo + hi) / 2
		if r.anchors[mid].entity < entity {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	found^ = lo < r.nanchors && r.anchors[lo].entity == entity
	return lo
}

@(private = "file")
anchor_make :: proc(r: ^Reality, entity: Entity_ID) -> ^Anchor {
	i: uint
	found: bool

	i = anchor_index(r, entity, &found)
	if found do return &r.anchors[i]
	if r.nanchors == r.anchorcap {
		old := r.anchorcap
		r.anchorcap = r.anchorcap * 2 if r.anchorcap != 0 else 8
		r.anchors = ([^]Anchor)(realloc(r.anchors, old * size_of(Anchor), r.anchorcap * size_of(Anchor)))
	}
	mem.copy(&r.anchors[i + 1], &r.anchors[i], int((r.nanchors - i) * size_of(Anchor)))
	r.anchors[i] = {}
	r.anchors[i].entity = entity
	r.nanchors += 1
	return &r.anchors[i]
}

/* Anchors, in entity order. Setting one again changes its kind; its centre
 * is set when it is next centred. */
reality_set_anchor :: proc(r: ^Reality, entity: Entity_ID, kind: i32) -> bool {
	if kind < 0 || kind >= r.nkinds || entity == NO_ENTITY do return false
	anchor_make(r, entity).kind = kind
	return true
}

/* Restoring: an anchor as saved, centre and all. */
reality_restore_anchor :: proc(r: ^Reality, entity: Entity_ID, kind: i32, cx: i32, cy: i32, z: i32, centred: bool) {
	a: ^Anchor

	if kind < 0 || kind >= r.nkinds do return
	a = anchor_make(r, entity)
	a.kind = kind
	a.cx = cx
	a.cy = cy
	a.z = z
	a.centred = centred
}

reality_remove_anchor :: proc(r: ^Reality, entity: Entity_ID) {
	i: uint
	found: bool

	i = anchor_index(r, entity, &found)
	if !found do return
	mem.copy(&r.anchors[i], &r.anchors[i + 1], int((r.nanchors - i - 1) * size_of(Anchor)))
	r.nanchors -= 1
}

reality_anchor_count :: proc(r: ^Reality) -> uint {
	return r.nanchors
}

// Each out-parameter may be nil.
reality_anchor_at :: proc(r: ^Reality, i: uint, kind: ^i32, cx: ^i32, cy: ^i32, z: ^i32, centred: ^bool) -> Entity_ID {
	a: ^Anchor

	if i >= r.nanchors do return NO_ENTITY
	a = &r.anchors[i]
	if kind != nil do kind^ = a.kind
	if cx != nil do cx^ = a.cx
	if cy != nil do cy^ = a.cy
	if z != nil do z^ = a.z
	if centred != nil do centred^ = a.centred
	return a.entity
}

@(private = "file")
chunk_of :: proc(v: i32) -> i32 {
	return v / BG_CHUNK_TILES if v >= 0 else -((-v + BG_CHUNK_TILES - 1) / BG_CHUNK_TILES)
}

/* An anchor standing on (x, y, z): its centre moved there, if it hasn't
 * one, or has gone its kind's margin past its centre's chunk. YES if the
 * centre moved. */
reality_centre :: proc(r: ^Reality, entity: Entity_ID, x: i32, y: i32, z: i32) -> bool {
	a: ^Anchor
	i: uint
	out: i32
	dx: i32
	dy: i32
	found: bool

	i = anchor_index(r, entity, &found)
	if !found do return false
	a = &r.anchors[i]
	if a.centred && a.z == z {
		/* how far past its centre's chunk it stands, in tiles */
		dx = a.cx * BG_CHUNK_TILES - x if x < a.cx * BG_CHUNK_TILES else x - (a.cx * BG_CHUNK_TILES + BG_CHUNK_TILES - 1)
		dy = a.cy * BG_CHUNK_TILES - y if y < a.cy * BG_CHUNK_TILES else y - (a.cy * BG_CHUNK_TILES + BG_CHUNK_TILES - 1)
		out = dx if dx > dy else dy
		if out <= r.kinds[a.kind].margin do return false
	}
	a.cx = chunk_of(x)
	a.cy = chunk_of(y)
	a.z = z
	a.centred = true
	return true
}

/* The level of detail of a tile: the highest any anchor's centre gives it;
 * full with no anchors at all. */
reality_detail_at :: proc(r: ^Reality, x: i32, y: i32, z: i32) -> Detail {
	if r == nil do return .Full
	return detail_by(r, r.anchors, r.nanchors, x, y, z)
}

@(private = "file")
detail_by :: proc(r: ^Reality, anchors: [^]Anchor, n: uint, x: i32, y: i32, z: i32) -> Detail {
	a: ^Anchor
	reach: ^Reach
	best: Detail
	i: uint
	d: i32
	dx: i32
	dy: i32
	dz: i32
	k: i32

	if n == 0 do return .Full
	best = .Frozen
	for i = 0; i < n && best < .Full; i += 1 {
		a = &anchors[i]
		if !a.centred do continue
		dx = chunk_of(x) - a.cx
		dy = chunk_of(y) - a.cy
		d = abs(dx) if abs(dx) > abs(dy) else abs(dy)
		dz = z - a.z
		for k = 2; k >= 0 && Detail(k + 1) > best; k -= 1 {
			reach = &r.kinds[a.kind].reach[k]
			if reach.across >= 0 && d <= reach.across && dz <= reach.up && -dz <= reach.down {
				best = Detail(k + 1)
				break
			}
		}
	}
	return best
}

/* --- anchors kept ------------------------------------------------------------------- */

/* The anchors as they are, kept to compare with later (what rose from
 * frozen when they moved, REALITY.md step 4). One block, the anchors
 * after the count, as the C's flexible array: free() it. */
Anchors_Kept :: struct {
	n:       uint,
	anchors: [0]Anchor,
}

@(private = "file")
kept_anchors :: #force_inline proc(kept: ^Anchors_Kept) -> [^]Anchor {
	return ([^]Anchor)(&kept.anchors)
}

reality_keep_anchors :: proc(r: ^Reality) -> ^Anchors_Kept {
	kept: ^Anchors_Kept

	p, _ := mem.alloc(size_of(Anchors_Kept) + int(r.nanchors + 1) * size_of(Anchor))
	kept = (^Anchors_Kept)(p)
	kept.n = r.nanchors
	if r.nanchors != 0 do mem.copy(kept_anchors(kept), r.anchors, int(r.nanchors * size_of(Anchor)))
	return kept
}

reality_kept_count :: proc(kept: ^Anchors_Kept) -> uint {
	return kept.n if kept != nil else 0
}

/* The level of a chunk's tiles by the anchors kept. */
reality_detail_kept :: proc(r: ^Reality, kept: ^Anchors_Kept, x: i32, y: i32, z: i32) -> Detail {
	return detail_by(r, kept_anchors(kept), kept.n, x, y, z) if kept != nil else .Full
}

/* An anchor's box, the chunks its abstract reach covers: (cx, cy, z) low
 * and high. `same`: the anchor is as it is now, same kind, same centre.
 * (kept nil: the anchors now.) */
reality_kept_box :: proc(r: ^Reality, kept: ^Anchors_Kept, i: uint, entity: ^Entity_ID, lo: ^[3]i32, hi: ^[3]i32,
                         same: ^bool) -> bool {
	a: ^Anchor
	now: ^Anchor
	reach: ^Reach
	k: uint
	found: bool

	if kept != nil {
		a = &kept_anchors(kept)[i] if i < kept.n else nil
	} else {
		a = &r.anchors[i] if i < r.nanchors else nil
	}
	if a == nil || !a.centred do return false
	reach = &r.kinds[a.kind].reach[0]        /* abstract reaches furthest */
	lo[0] = a.cx - reach.across
	lo[1] = a.cy - reach.across
	lo[2] = a.z - reach.down
	hi[0] = a.cx + reach.across
	hi[1] = a.cy + reach.across
	hi[2] = a.z + reach.up
	entity^ = a.entity
	if same != nil && kept != nil {
		/* kept: is it as it is now? */
		k = anchor_index(r, a.entity, &found)
		now = &r.anchors[k] if found else nil
		same^ = now != nil && now.kind == a.kind && now.centred == a.centred && now.cx == a.cx && now.cy == a.cy &&
		        now.z == a.z
	}
	return true
}

/* Whether anchor i, as it is now, is as it was kept. */
reality_kept_same :: proc(r: ^Reality, kept: ^Anchors_Kept, i: uint) -> bool {
	now: ^Anchor
	k: uint

	if i >= r.nanchors do return false
	now = &r.anchors[i]
	for k = 0; kept != nil && k < kept.n; k += 1 {
		ka := &kept_anchors(kept)[k]
		if ka.entity == now.entity {
			return ka.kind == now.kind && ka.centred == now.centred && ka.cx == now.cx && ka.cy == now.cy && ka.z == now.z
		}
	}
	return false
}

/* --- leases ----------------------------------------------------------------------- */

@(private = "file")
lease_index :: proc(r: ^Reality, entity: Entity_ID, found: ^bool) -> uint {
	lo: uint
	hi: uint
	mid: uint

	lo = 0
	hi = r.nleases
	for lo < hi {
		mid = (lo + hi) / 2
		if r.leases[mid].entity < entity {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	found^ = lo < r.nleases && r.leases[lo].entity == entity
	return lo
}

/* Leases: full detail until a time. A lease again keeps the later end. */
reality_lease :: proc(r: ^Reality, entity: Entity_ID, until: i64) {
	i: uint
	found: bool

	if entity == NO_ENTITY do return
	i = lease_index(r, entity, &found)
	if found {
		if until > r.leases[i].until do r.leases[i].until = until
		return
	}
	if r.nleases == r.leasecap {
		old := r.leasecap
		r.leasecap = r.leasecap * 2 if r.leasecap != 0 else 16
		r.leases = ([^]Lease)(realloc(r.leases, old * size_of(Lease), r.leasecap * size_of(Lease)))
	}
	mem.copy(&r.leases[i + 1], &r.leases[i], int((r.nleases - i) * size_of(Lease)))
	r.leases[i].entity = entity
	r.leases[i].until = until
	r.nleases += 1
}

reality_lease_of :: proc(r: ^Reality, entity: Entity_ID) -> i64 {
	i: uint
	found: bool

	i = lease_index(r, entity, &found)
	return r.leases[i].until if found else 0
}

/* Lets go of the leases ended by `now`. */
reality_prune :: proc(r: ^Reality, now: i64) {
	i: uint
	k: uint

	k = 0
	for i = 0; i < r.nleases; i += 1 {
		if r.leases[i].until > now {
			r.leases[k] = r.leases[i]
			k += 1
		}
	}
	r.nleases = k
}

reality_lease_count :: proc(r: ^Reality) -> uint {
	return r.nleases
}

// until may be nil.
reality_lease_at :: proc(r: ^Reality, i: uint, until: ^i64) -> Entity_ID {
	if i >= r.nleases do return NO_ENTITY
	if until != nil do until^ = r.leases[i].until
	return r.leases[i].entity
}

/* What runs at a level (content's `levels`, REALITY.md step 3): whether its
 * agents sense only what they take part in, and the cadence their own
 * wakes are put off to (0: none). Below reduced, as reduced; full, all
 * senses and no cadence. */
reality_own_senses_at :: proc(r: ^Reality, level: Detail) -> bool {
	return level < .Full && r.reducedOwn
}

reality_cadence_at :: proc(r: ^Reality, level: Detail) -> i64 {
	return r.reducedEvery if level < .Full else 0
}

/* A wake at `at`, at a level: put off to the cadence's next beat, if any. */
reality_beat :: proc(r: ^Reality, level: Detail, at: i64) -> i64 {
	every: i64

	every = reality_cadence_at(r, level)
	if every <= 0 || at <= 0 || at == max(i64) do return at
	return (at + every - 1) / every * every
}

/* Contact: whether an event's kind counts, and how long its lease runs. */
reality_is_contact :: proc(r: ^Reality, kind: cstring) -> bool {
	i: i32

	for i = 0; kind != nil && i < r.ncontact; i += 1 {
		if string(r.contact[i]) == string(kind) do return true
	}
	return false
}

reality_contact_lease :: proc(r: ^Reality) -> i64 {
	return r.lease
}

reality_hash :: proc(r: ^Reality, h: u64) -> u64 {
	h := h
	i: uint

	for i = 0; i < r.nanchors; i += 1 {
		h = mix(h ~ r.anchors[i].entity ~ (u64(u32(r.anchors[i].kind)) << 40) ~
		        (u64(u32(r.anchors[i].cx)) << 8) ~ (u64(u32(r.anchors[i].cy)) << 24) ~
		        (u64(u32(r.anchors[i].z)) << 56) ~ u64(r.anchors[i].centred))
	}
	for i = 0; i < r.nleases; i += 1 do h = mix(h ~ r.leases[i].entity ~ (u64(r.leases[i].until) << 16))
	return h
}

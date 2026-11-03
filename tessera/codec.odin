package tessera

// Frames and diffs: the binary form scenes travel in.
//
//   "TESS" format kind          kind 1 a frame, 2 a diff
//   meta                        view, seq, time, content, viewer
//   frame: extent, looks, cells, marks, overlays, annotations
//   diff:  the seq it follows, focus, looks added, cells changed (spans),
//          marks removed and put, overlays removed and put, annotations
//          (all, if any changed)
//
// Integers are LEB128 varints, signed ones zigzagged; the content hash is
// eight bytes, little-endian; a string is its length and bytes, one that may
// be absent its length plus one (0: absent). Runs of equal cells, and of
// equal overlay values, are stored once with their length. Decoding checks
// every length against what is left, so no input makes it allocate more than
// the input could describe.

import "base:intrinsics"
import "base:runtime"

@(private = "file") KIND_FRAME :: 1
@(private = "file") KIND_DIFF :: 2

// --- writing -----------------------------------------------------------------------------------

@(private = "file")
W :: struct {
	b:   [dynamic]u8,
	err: runtime.Allocator_Error,
}

@(private = "file")
w_bytes :: proc(w: ^W, b: []u8) {
	if w.err != nil do return
	if _, err := append(&w.b, ..b); err != nil do w.err = err
}

@(private = "file")
w_u8 :: proc(w: ^W, v: u8) {
	v := v
	w_bytes(w, ([^]u8)(&v)[:1])
}

@(private = "file")
w_uv :: proc(w: ^W, v: u64) {
	b: [10]u8
	n := 0
	v := v
	for {
		b[n] = u8(v & 0x7f)
		v >>= 7
		if v != 0 do b[n] |= 0x80
		n += 1
		if v == 0 do break
	}
	w_bytes(w, b[:n])
}

@(private = "file")
w_sv :: proc(w: ^W, v: i64) {
	w_uv(w, (u64(v) << 1) ~ u64(v >> 63))
}

@(private = "file")
w_u64 :: proc(w: ^W, v: u64) {
	b: [8]u8
	for i in 0 ..< 8 do b[i] = u8(v >> (8 * uint(i)))
	w_bytes(w, b[:])
}

@(private = "file")
w_str :: proc(w: ^W, s: string) {
	w_uv(w, u64(len(s)))
	w_bytes(w, transmute([]u8)s)
}

// "" is absent.
@(private = "file")
w_opt_str :: proc(w: ^W, s: string) {
	if s == "" {
		w_uv(w, 0)
		return
	}
	w_uv(w, u64(len(s)) + 1)
	w_bytes(w, transmute([]u8)s)
}

@(private = "file")
w_cell :: proc(w: ^W, c: Cell) {
	w_sv(w, c.seen)
	w_uv(w, u64(c.fluid))
	w_uv(w, u64(c.terrain))
	w_uv(w, u64(transmute(u16)c.flags))
	w_u8(w, c.light)
}

@(private = "file")
w_mark :: proc(w: ^W, m: Mark) {
	w_uv(w, m.id)
	w_uv(w, m.holder)
	w_sv(w, m.seen)
	w_sv(w, i64(m.x))
	w_sv(w, i64(m.y))
	w_sv(w, i64(m.z))
	w_uv(w, u64(m.look))
	w_sv(w, i64(m.stack))
	w_uv(w, u64(transmute(u16)m.flags))
	w_opt_str(w, m.label)
}

// Runs of equal values: the count of runs, then each run's length and value.
@(private = "file")
w_runs :: proc(w: ^W, values: []$T, put: proc(w: ^W, v: T)) where intrinsics.type_is_comparable(T) {
	runs := 0
	for i := 0; i < len(values); runs += 1 {
		j := i + 1
		for j < len(values) && values[j] == values[i] do j += 1
		i = j
	}
	w_uv(w, u64(runs))
	for i := 0; i < len(values); {
		j := i + 1
		for j < len(values) && values[j] == values[i] do j += 1
		w_uv(w, u64(j - i))
		put(w, values[i])
		i = j
	}
}

@(private = "file")
w_value :: proc(w: ^W, v: i32) {
	w_sv(w, i64(v))
}

@(private = "file")
w_overlay :: proc(w: ^W, o: Overlay) {
	w_str(w, o.name)
	w_sv(w, i64(o.lo))
	w_sv(w, i64(o.hi))
	w_uv(w, u64(transmute(u32)o.tags))
	w_runs(w, o.values, w_value)
}

@(private = "file")
w_annotations :: proc(w: ^W, s: ^Scene) {
	w_uv(w, u64(len(s.annotations)))
	for n in s.annotations {
		w_u8(w, u8(n.kind))
		w_uv(w, u64(transmute(u32)n.tags))
		w_uv(w, u64(n.look))
		w_uv(w, u64(len(n.points)))
		for p in n.points {
			w_sv(w, i64(p.x))
			w_sv(w, i64(p.y))
			w_sv(w, i64(p.z))
		}
		w_opt_str(w, n.text)
	}
}

@(private = "file")
w_head :: proc(w: ^W, kind: u8, m: Meta) {
	w_bytes(w, transmute([]u8)string("TESS"))
	w_u8(w, FORMAT)
	w_u8(w, kind)
	w_u8(w, u8(m.view))
	w_uv(w, m.seq)
	w_sv(w, m.time)
	w_u64(w, m.content)
	w_uv(w, m.viewer)
}

@(private = "file")
finish :: proc(w: ^W) -> ([]u8, runtime.Allocator_Error) {
	if w.err != nil {
		delete(w.b)
		return nil, w.err
	}
	return w.b[:], nil
}

// A frame: the whole scene.
encode_frame :: proc(s: ^Scene, allocator := context.allocator) -> ([]u8, runtime.Allocator_Error) {
	w := W{b = make([dynamic]u8, 0, 256, allocator)}
	w_head(&w, KIND_FRAME, s.meta)
	e := s.extent
	w_sv(&w, i64(e.x0))
	w_sv(&w, i64(e.y0))
	w_uv(&w, u64(e.w))
	w_uv(&w, u64(e.h))
	w_sv(&w, i64(e.z0))
	w_sv(&w, i64(e.z1))
	w_sv(&w, i64(e.focus))
	w_uv(&w, u64(len(s.looks)))
	for l in s.looks do w_str(&w, l)
	w_runs(&w, s.cells, w_cell)
	w_uv(&w, u64(len(s.marks)))
	for m in s.marks do w_mark(&w, m)
	w_uv(&w, u64(len(s.overlays)))
	for o in s.overlays do w_overlay(&w, o)
	w_annotations(&w, s)
	return finish(&w)
}

// Whether `to` can be said as changes to `from`.
@(private = "file")
diffable :: proc(from, to: ^Scene) -> bool {
	a, b := from.extent, to.extent
	if from.meta.view != to.meta.view || from.meta.viewer != to.meta.viewer ||
	   a.x0 != b.x0 || a.y0 != b.y0 || a.w != b.w || a.h != b.h || a.z0 != b.z0 || a.z1 != b.z1 {
		return false
	}
	if len(to.looks) < len(from.looks) do return false
	for l, i in from.looks do if l != to.looks[i] do return false
	return true
}

@(private = "file")
overlay_same :: proc(a, b: ^Overlay) -> bool {
	if a.name != b.name || a.lo != b.lo || a.hi != b.hi || a.tags != b.tags do return false
	for v, i in a.values do if v != b.values[i] do return false
	return true
}

@(private = "file")
annotation_same :: proc(a, b: Annotation) -> bool {
	if a.kind != b.kind || a.tags != b.tags || a.look != b.look || a.text != b.text ||
	   len(a.points) != len(b.points) {
		return false
	}
	for p, i in a.points do if p != b.points[i] do return false
	return true
}

// A diff: what `to` changes of `from` (whose seq it names). When a diff
// can't say it (another view, extent, or viewer, or appearance keys not
// extending from's), a frame instead, and is_frame says so.
encode_diff :: proc(from, to: ^Scene, allocator := context.allocator) -> (data: []u8, is_frame: bool, err: runtime.Allocator_Error) {
	if from == nil || !diffable(from, to) {
		data, err = encode_frame(to, allocator)
		return data, true, err
	}
	w := W{b = make([dynamic]u8, 0, 256, allocator)}
	w_head(&w, KIND_DIFF, to.meta)
	w_uv(&w, from.meta.seq)
	w_sv(&w, i64(to.extent.focus))
	w_uv(&w, u64(len(to.looks) - len(from.looks)))
	for l in to.looks[len(from.looks):] do w_str(&w, l)
	// cells: spans of changed ones, each after a gap from the last
	n := len(to.cells)
	spans := 0
	for i := 0; i < n; {
		if from.cells[i] == to.cells[i] {
			i += 1
			continue
		}
		for i < n && from.cells[i] != to.cells[i] do i += 1
		spans += 1
	}
	w_uv(&w, u64(spans))
	end := 0
	for i := 0; i < n; {
		if from.cells[i] == to.cells[i] {
			i += 1
			continue
		}
		j := i
		for j < n && from.cells[j] != to.cells[j] do j += 1
		w_uv(&w, u64(i - end))
		w_uv(&w, u64(j - i))
		for k in i ..< j do w_cell(&w, to.cells[k])
		end, i = j, j
	}
	// marks: removed (ids rising, by their gaps), then put
	removed, put := 0, 0
	for m in from.marks do if mark_find(to, m.id) == nil do removed += 1
	for m in to.marks {
		was := mark_find(from, m.id)
		if was == nil || was^ != m do put += 1
	}
	w_uv(&w, u64(removed))
	last: u64 = 0
	for m in from.marks do if mark_find(to, m.id) == nil {
		w_uv(&w, m.id - last)
		last = m.id
	}
	w_uv(&w, u64(put))
	for m in to.marks {
		was := mark_find(from, m.id)
		if was == nil || was^ != m do w_mark(&w, m)
	}
	// overlays: removed by name, then put whole
	removed, put = 0, 0
	for &o in from.overlays do if overlay_named(to, o.name) == nil do removed += 1
	for &o in to.overlays {
		was := overlay_named(from, o.name)
		if was == nil || !overlay_same(was, &o) do put += 1
	}
	w_uv(&w, u64(removed))
	for o in from.overlays do if overlay_named(to, o.name) == nil do w_str(&w, o.name)
	w_uv(&w, u64(put))
	for &o in to.overlays {
		was := overlay_named(from, o.name)
		if was == nil || !overlay_same(was, &o) do w_overlay(&w, o)
	}
	// annotations: all of them, if any changed
	same := len(from.annotations) == len(to.annotations)
	for i := 0; same && i < len(to.annotations); i += 1 do same = annotation_same(from.annotations[i], to.annotations[i])
	w_u8(&w, 0 if same else 1)
	if !same do w_annotations(&w, to)
	data, err = finish(&w)
	return data, false, err
}

// --- reading -------------------------------------------------------------------------------------

Decode_Error :: enum u8 {
	None,
	Not_Tessera,
	Other_Version,
	Truncated,
	Number_Too_Large,
	Out_Of_Range,
	Count_Too_Large,
	String_With_Nul,
	Out_Of_Memory,
	Bad_Extent,
	Too_Many_Looks,
	Empty_Look,
	Cells_Dont_Fit,
	Bad_Mark,
	Overlay_Without_Name,
	Overlay_Doesnt_Fit,
	Bad_Annotation,
	No_Base,
	Other_Base,
	Other_View,
	Focus_Outside,
	Changed_Cells_Outside,
	Removed_Out_Of_Order,
	Removed_Mark_Missing,
	Removed_Overlay_Missing,
	Bad_Annotations_Flag,
	Unknown_Kind,
	Unknown_View,
	Data_After_End,
}

// Why a frame or diff didn't decode, in words.
DECODE_ERROR_TEXT := [Decode_Error]string {
	.None                    = "",
	.Not_Tessera             = "not a Tessera frame or diff",
	.Other_Version           = "another version of the format",
	.Truncated               = "truncated",
	.Number_Too_Large        = "a number too large",
	.Out_Of_Range            = "a value out of range",
	.Count_Too_Large         = "a count larger than the data",
	.String_With_Nul         = "a string with a NUL in it",
	.Out_Of_Memory           = "out of memory",
	.Bad_Extent              = "an empty or oversized extent, or an unknown view",
	.Too_Many_Looks          = "too many appearance keys",
	.Empty_Look              = "an empty appearance key",
	.Cells_Dont_Fit          = "the cells' runs don't fit the extent",
	.Bad_Mark                = "a mark without an id, or its own holder",
	.Overlay_Without_Name    = "an overlay without a name",
	.Overlay_Doesnt_Fit      = "an overlay's runs don't fit its cells",
	.Bad_Annotation          = "an annotation of no kind, or without its points",
	.No_Base                 = "a diff without the frame it follows",
	.Other_Base              = "a diff that follows another frame",
	.Other_View              = "a diff of another view",
	.Focus_Outside           = "a focus outside the extent",
	.Changed_Cells_Outside   = "changed cells outside the extent",
	.Removed_Out_Of_Order    = "marks removed out of order",
	.Removed_Mark_Missing    = "a mark removed that isn't there",
	.Removed_Overlay_Missing = "an overlay removed that isn't there",
	.Bad_Annotations_Flag    = "a diff's annotations are malformed",
	.Unknown_Kind            = "neither a frame nor a diff",
	.Unknown_View            = "an unknown view",
	.Data_After_End          = "data after the end",
}

@(private = "file")
R :: struct {
	data: []u8,
	p:    int,
	err:  Decode_Error,
}

@(private = "file")
r_fail :: proc(r: ^R, e: Decode_Error) {
	if r.err == .None do r.err = e
}

@(private = "file")
r_left :: proc(r: ^R) -> int {
	return len(r.data) - r.p
}

@(private = "file")
r_u8 :: proc(r: ^R) -> u8 {
	if r.err != .None || r.p >= len(r.data) {
		r_fail(r, .Truncated)
		return 0
	}
	r.p += 1
	return r.data[r.p - 1]
}

@(private = "file")
r_uv :: proc(r: ^R) -> u64 {
	v: u64 = 0
	for shift: uint = 0; shift < 70; shift += 7 {
		b := r_u8(r)
		if r.err != .None do return 0
		if shift == 63 && b > 1 {
			r_fail(r, .Number_Too_Large)
			return 0
		}
		v |= u64(b & 0x7f) << shift
		if b & 0x80 == 0 do return v
	}
	r_fail(r, .Number_Too_Large)
	return 0
}

@(private = "file")
r_sv :: proc(r: ^R) -> i64 {
	u := r_uv(r)
	return i64(u >> 1) ~ -i64(u & 1)
}

@(private = "file")
r_s32 :: proc(r: ^R) -> i32 {
	v := r_sv(r)
	if v < i64(min(i32)) || v > i64(max(i32)) {
		r_fail(r, .Out_Of_Range)
		return 0
	}
	return i32(v)
}

@(private = "file")
r_bounded :: proc(r: ^R, limit: u64) -> u64 {
	v := r_uv(r)
	if r.err == .None && v > limit do r_fail(r, .Out_Of_Range)
	return 0 if r.err != .None else v
}

@(private = "file")
r_u64 :: proc(r: ^R) -> u64 {
	v: u64 = 0
	for i in 0 ..< 8 do v |= u64(r_u8(r)) << (8 * uint(i))
	return v
}

// A count of items each at least `least` bytes: no more than the rest could hold.
@(private = "file")
r_count :: proc(r: ^R, least: int) -> int {
	n := r_uv(r)
	if r.err == .None && n > u64(r_left(r) / max(least, 1)) do r_fail(r, .Count_Too_Large)
	return 0 if r.err != .None else int(n)
}

// A string's bytes, in the data; an absent one (optional) is "".
@(private = "file")
r_str :: proc(r: ^R, optional: bool) -> string {
	n := r_uv(r)
	if r.err != .None do return ""
	if optional {
		if n == 0 do return ""
		n -= 1
	}
	if n > u64(r_left(r)) {
		r_fail(r, .Truncated)
		return ""
	}
	s := r.data[r.p:][:n]
	for b in s do if b == 0 {
		r_fail(r, .String_With_Nul)
		return ""
	}
	r.p += int(n)
	return string(s)
}

@(private = "file")
r_cell :: proc(r: ^R) -> (c: Cell) {
	c.seen = r_sv(r)
	c.fluid = u32(r_bounded(r, u64(max(u32))))
	c.terrain = u16(r_bounded(r, u64(max(u16))))
	c.flags = transmute(Cell_Flags)u16(r_bounded(r, u64(max(u16))))
	c.light = r_u8(r)
	return
}

@(private = "file")
r_mark :: proc(r: ^R, s: ^Scene) {
	m: Mark
	m.id = r_uv(r)
	m.holder = r_uv(r)
	m.seen = r_sv(r)
	m.x = r_s32(r)
	m.y = r_s32(r)
	m.z = r_s32(r)
	m.look = u16(r_bounded(r, u64(max(u16))))
	stack := r_sv(r)
	if stack < i64(min(i16)) || stack > i64(max(i16)) do r_fail(r, .Out_Of_Range)
	m.stack = i16(stack)
	m.flags = transmute(Mark_Flags)u16(r_bounded(r, u64(max(u16))))
	m.label = r_str(r, true)
	if r.err == .None && !mark_put(s, m) do r_fail(r, .Bad_Mark)
}

@(private = "file")
r_overlay :: proc(r: ^R, s: ^Scene) {
	name := r_str(r, false)
	lo, hi := r_s32(r), r_s32(r)
	tags := transmute(Tags)u32(r_bounded(r, u64(max(u32))))
	runs := r_count(r, 2)
	if r.err != .None do return
	if name == "" {
		r_fail(r, .Overlay_Without_Name)
		return
	}
	v := overlay_put(s, name, lo, hi, tags)
	if v == nil {
		r_fail(r, .Out_Of_Memory)
		return
	}
	at := 0
	for _ in 0 ..< runs {
		n := r_uv(r)
		value := r_s32(r)
		if r.err != .None do return
		if n == 0 || n > u64(len(v) - at) {
			r_fail(r, .Overlay_Doesnt_Fit)
			return
		}
		for _ in 0 ..< n {
			v[at] = value
			at += 1
		}
	}
	if at != len(v) do r_fail(r, .Overlay_Doesnt_Fit)
}

@(private = "file")
clear_annotations :: proc(s: ^Scene) {
	for n in s.annotations do free_annotation(n, s.allocator)
	clear(&s.annotations)
}

@(private = "file")
r_annotations :: proc(r: ^R, s: ^Scene) {
	n := r_count(r, 5)
	for _ in 0 ..< n {
		kind := r_u8(r)
		tags := transmute(Tags)u32(r_bounded(r, u64(max(u32))))
		look := u16(r_bounded(r, u64(max(u16))))
		np := r_count(r, 3)
		if r.err != .None do return
		points := make([]Point, np, s.allocator)
		defer delete(points, s.allocator)
		for &p in points do p = {r_s32(r), r_s32(r), r_s32(r)}
		text := r_str(r, true)
		if r.err != .None do return
		if !annotation_add(s, Annotation_Kind(kind), tags, look, points, text) {
			r_fail(r, .Bad_Annotation)
			return
		}
	}
}

@(private = "file")
r_looks :: proc(r: ^R, s: ^Scene, n: int) {
	if len(s.looks) + n > MAX_LOOKS do r_fail(r, .Too_Many_Looks)
	for _ in 0 ..< n {
		name := r_str(r, false)
		if r.err != .None do return
		if name == "" || !look_append(s, name) {
			r_fail(r, .Empty_Look)
			return
		}
	}
}

@(private = "file")
decode_frame :: proc(r: ^R, meta: Meta, allocator: runtime.Allocator) -> ^Scene {
	e: Extent
	e.x0 = r_s32(r)
	e.y0 = r_s32(r)
	e.w = i32(r_bounded(r, u64(max(i32))))
	e.h = i32(r_bounded(r, u64(max(i32))))
	e.z0 = r_s32(r)
	e.z1 = r_s32(r)
	e.focus = r_s32(r)
	if r.err != .None do return nil
	s := scene_new(meta, e, allocator)
	if s == nil {
		r_fail(r, .Bad_Extent)
		return nil
	}
	r_looks(r, s, r_count(r, 1))
	runs, at := r_count(r, 6), 0
	for _ in 0 ..< runs {
		n := r_uv(r)
		c := r_cell(r)
		if r.err != .None do break
		if n == 0 || n > u64(len(s.cells) - at) {
			r_fail(r, .Cells_Dont_Fit)
			break
		}
		for _ in 0 ..< n {
			s.cells[at] = c
			at += 1
		}
	}
	if r.err == .None && at != len(s.cells) do r_fail(r, .Cells_Dont_Fit)
	// (a range's end is evaluated each time round: counts are read first)
	marks := r_count(r, 10)
	for _ in 0 ..< marks do r_mark(r, s)
	overlays := r_count(r, 6)
	for _ in 0 ..< overlays do r_overlay(r, s)
	r_annotations(r, s)
	if r.err != .None {
		scene_free(s)
		return nil
	}
	return s
}

@(private = "file")
decode_diff :: proc(r: ^R, meta: Meta, base: ^Scene, allocator: runtime.Allocator) -> ^Scene {
	from := r_uv(r)
	focus := r_s32(r)
	if r.err != .None do return nil
	switch {
	case base == nil:                                                   r_fail(r, .No_Base)
	case from != base.meta.seq:                                         r_fail(r, .Other_Base)
	case meta.view != base.meta.view || meta.viewer != base.meta.viewer: r_fail(r, .Other_View)
	}
	if r.err != .None do return nil
	s := scene_copy(base, allocator)
	if s == nil {
		r_fail(r, .Out_Of_Memory)
		return nil
	}
	s.meta = meta
	if !set_focus(s, focus) do r_fail(r, .Focus_Outside)
	r_looks(r, s, r_count(r, 1))
	spans, at := r_count(r, 2), 0
	for _ in 0 ..< spans {
		gap, n := r_uv(r), r_uv(r)
		if r.err != .None do break
		left := u64(len(s.cells) - at)
		if gap > left || n == 0 || n > left - gap {
			r_fail(r, .Changed_Cells_Outside)
			break
		}
		at += int(gap)
		for _ in 0 ..< n {
			s.cells[at] = r_cell(r)
			at += 1
		}
	}
	id: u64 = 0
	removed := r_count(r, 1)
	for _ in 0 ..< removed {
		gap := r_uv(r)
		if r.err != .None do break
		if gap == 0 || gap > max(u64) - id {
			r_fail(r, .Removed_Out_Of_Order)
			break
		}
		id += gap
		if !mark_remove(s, id) do r_fail(r, .Removed_Mark_Missing)
	}
	put := r_count(r, 10)
	for _ in 0 ..< put do r_mark(r, s)
	removed = r_count(r, 1)
	for _ in 0 ..< removed {
		name := r_str(r, false)
		if r.err != .None do break
		k := 0
		for k < len(s.overlays) && s.overlays[k].name != name do k += 1
		if k == len(s.overlays) {
			r_fail(r, .Removed_Overlay_Missing)
			break
		}
		free_overlay(s.overlays[k], s.allocator)
		ordered_remove(&s.overlays, k)
	}
	put = r_count(r, 6)
	for _ in 0 ..< put do r_overlay(r, s)
	changed := r_u8(r)
	if r.err == .None && changed > 1 do r_fail(r, .Bad_Annotations_Flag)
	if r.err == .None && changed == 1 {
		clear_annotations(s)
		r_annotations(r, s)
	}
	if r.err != .None {
		scene_free(s)
		return nil
	}
	return s
}

// A scene from a frame, or from a diff applied to `base` (whose seq it must
// follow; base is left as it is). nil, and why, if the data is malformed,
// truncated, of another format, or a diff without its base.
decode :: proc(data: []u8, base: ^Scene = nil, allocator := context.allocator) -> (^Scene, Decode_Error) {
	if len(data) < 6 || string(data[:4]) != "TESS" do return nil, .Not_Tessera
	r := R{data = data, p = 4}
	format, kind := r_u8(&r), r_u8(&r)
	if format != FORMAT do return nil, .Other_Version
	view := r_u8(&r)
	meta := Meta {
		view    = View(view),
		seq     = r_uv(&r),
		time    = r_sv(&r),
		content = r_u64(&r),
		viewer  = r_uv(&r),
	}
	if r.err == .None && view > u8(View.Knowledge) do r_fail(&r, .Unknown_View)
	s: ^Scene
	if r.err == .None {
		switch kind {
		case KIND_FRAME: s = decode_frame(&r, meta, allocator)
		case KIND_DIFF:  s = decode_diff(&r, meta, base, allocator)
		case:            r_fail(&r, .Unknown_Kind)
		}
	}
	if r.err == .None && r.p != len(r.data) {
		r_fail(&r, .Data_After_End)
		scene_free(s)
		s = nil
	}
	if s == nil && r.err == .None do r.err = .Truncated
	return s, r.err if s == nil else .None
}

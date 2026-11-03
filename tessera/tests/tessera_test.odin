// Tessera's tests: building scenes, the text form, frames and diffs, and
// decoding anything without harm. golden/ holds what the C encoder (format
// 1, before the port) made of the room: the Odin one must make the same.
//
//   odin test tessera/tests
package tessera_test

import "core:log"
import "core:testing"
import tess "../"

KNOW :: tess.Meta{.Knowledge, 1, 1000, 0xab, 4}
ROOM :: tess.Extent{3, 2, 4, 3, 0, 1, 0}

GOLDEN_FRAME :: #load("golden/room.frame")
GOLDEN_DIFF :: #load("golden/room-later.diff")
GOLDEN_LATER :: #load("golden/room-later.txt", string)

text :: proc(s: ^tess.Scene) -> string {
	return tess.scene_text(s, context.temp_allocator)
}

same :: proc(t: ^testing.T, a, b: ^tess.Scene, loc := #caller_location) -> bool {
	x, y := text(a), text(b)
	if x != y do log.infof("differ:\n%s  --\n%s", x, y, location = loc)
	return x == y
}

// A room as a character knows it: a floor, a wall, the character and a
// pump, a cup in the character's hand, an overlay, annotations.
room :: proc() -> ^tess.Scene {
	s := tess.scene_new(KNOW, ROOM)
	floor, wall := tess.look(s, "floor"), tess.look(s, "wall.stone")
	for y in i32(2) ..< 5 do for x in i32(3) ..< 7 {
		c := tess.cell_at(s, x, y, 0)
		c.terrain = wall if x == 6 else floor
		c.seen = 1000
		c.light = 200
		c.flags = {.In_Sight}
	}
	tess.cell_at(s, 4, 3, 0).fluid = 500
	me := tess.Mark{id = 4, seen = 1000, x = 3, y = 3, look = tess.look(s, "#Agent"), flags = {.Actor, .In_Sight}, label = "R4"}
	pump := tess.Mark{id = 7, seen = 900, x = 5, y = 2, look = tess.look(s, "#Pump"), flags = {.In_Sight}}
	cup := tess.Mark{id = 9, holder = 4, seen = 1000, x = 3, y = 3, look = tess.look(s, "#Part"), label = "a \"cup\""}
	tess.mark_put(s, cup)
	tess.mark_put(s, me)
	tess.mark_put(s, pump)
	heat := tess.overlay_put(s, "heat", 270, 320, {.Developer_Only})
	heat[tess.cell_index(s, 5, 2, 0)] = 305
	path := []tess.Point{{3, 3, 0}, {4, 3, 0}, {5, 2, 0}}
	tess.annotation_add(s, .Path, {}, 0, path, "to the pump")
	tess.annotation_add(s, .Callout, {.Developer_Only}, 0, path[2:], "worn 30")
	return s
}

// The room a moment later: the character moved, a tile wet, a key added,
// the pump gone from sight, the overlay changed, an annotation dropped, the
// focus a level up.
later :: proc(s: ^tess.Scene) -> ^tess.Scene {
	t := tess.scene_copy(s)
	m := t.meta
	m.seq = 2
	m.time = 2000
	tess.set_meta(t, m)
	me := tess.mark_find(t, 4)^
	me.x = 4
	me.seen = 2000
	tess.mark_put(t, me)
	tess.mark_remove(t, 7)
	tess.mark_put(t, tess.Mark{id = 12, seen = 2000, x = 6, y = 3, look = tess.look(t, "#Door"), stack = 1})
	tess.cell_at(t, 5, 4, 0).fluid = 250
	tess.cell_at(t, 3, 4, 1).seen = 2000
	tess.overlay_put(t, "heat", 270, 320, {.Developer_Only})[0] = 290
	tess.overlay_put(t, "age", 0, 60, {})
	tess.strip_developer(t)          // the callout goes, and the heat with it
	tess.overlay_put(t, "heat", 270, 320, {.Developer_Only})[1] = 280
	tess.set_focus(t, 1)
	return t
}

roundtrip :: proc(t: ^testing.T, s: ^tess.Scene) -> (r: ^tess.Scene, n: int) {
	b, _ := tess.encode_frame(s)
	defer delete(b)
	err: tess.Decode_Error
	r, err = tess.decode(b)
	if r == nil do log.infof("decode: %v", err)
	return r, len(b)
}

@(test)
building :: proc(t: ^testing.T) {
	bad := []tess.Extent{{0, 0, 0, 1, 0, 0, 0}, {0, 0, 1, 1, 1, 0, 0}, {0, 0, 1, 1, 0, 1, 2},
	                     {0, 0, 100000, 100000, 0, 0, 0}, {max(i32), 0, 2, 1, 0, 0, 0}}
	for e in bad do testing.expect(t, tess.scene_new(KNOW, e) == nil)
	odd := KNOW
	odd.view = tess.View(7)
	testing.expect(t, tess.scene_new(odd, ROOM) == nil)

	s := tess.scene_new(KNOW, ROOM)
	defer tess.scene_free(s)
	testing.expect_value(t, len(s.cells), 24)
	testing.expect(t, tess.cell_at(s, 2, 2, 0) == nil && tess.cell_at(s, 7, 2, 0) == nil && tess.cell_at(s, 3, 2, 2) == nil)
	testing.expect(t, tess.cell_at(s, 3, 2, 0).seen == -1 && tess.cell_at(s, 3, 2, 0).terrain == 0)
	testing.expect_value(t, tess.cell_index(s, 4, 2, 1), 13)
	// appearance keys: made once, in order; none for nothing
	testing.expect(t, tess.look(s, "floor") == 1 && tess.look(s, "wall") == 2 && tess.look(s, "floor") == 1)
	testing.expect(t, tess.look(s, "") == 0 && tess.look_find(s, "door") == 0)
	testing.expect(t, tess.look_name(s, 2) == "wall" && tess.look_name(s, 3) == "" && tess.look_name(s, 0) == "")
	// marks: by id; put again, replaced; no id, or its own holder, refused
	a := tess.Mark{id = 5, x = 3, y = 2, look = 1, label = "five"}
	b := tess.Mark{id = 2, holder = 5, x = 3, y = 2, look = 1}
	testing.expect(t, tess.mark_put(s, a) && tess.mark_put(s, b))
	testing.expect(t, s.marks[0].id == 2 && s.marks[1].id == 5)
	a.x = 4
	a.label = "moved"
	testing.expect(t, tess.mark_put(s, a) && len(s.marks) == 2 && tess.mark_find(s, 5).x == 4)
	testing.expect_value(t, tess.mark_find(s, 5).label, "moved")
	testing.expect(t, !tess.mark_put(s, tess.Mark{}) && !tess.mark_put(s, tess.Mark{id = 3, holder = 3}))
	testing.expect(t, tess.mark_remove(s, 2) && !tess.mark_remove(s, 2) && len(s.marks) == 1)
	// overlays: one per name
	v := tess.overlay_put(s, "heat", 0, 10, {})
	testing.expect(t, v != nil && raw_data(tess.overlay_put(s, "heat", 0, 20, {.Developer_Only})) == raw_data(v))
	testing.expect(t, len(s.overlays) == 1 && s.overlays[0].hi == 20 && s.overlays[0].tags == {.Developer_Only})
	testing.expect(t, tess.overlay_put(s, "", 0, 1, {}) == nil)
	// annotations: points needed, a callout has one
	p := []tess.Point{{1, 1, 0}, {2, 2, 0}}
	testing.expect(t, tess.annotation_add(s, .Arrow, {}, 0, p, ""))
	testing.expect(t, !tess.annotation_add(s, .Callout, {}, 0, p, "x") && !tess.annotation_add(s, .Line, {}, 0, p[:0], ""))
	testing.expect(t, !tess.annotation_add(s, tess.Annotation_Kind(9), {}, 0, p[:1], ""))
	// focus moves within the levels
	testing.expect(t, tess.set_focus(s, 1) && !tess.set_focus(s, 2) && s.extent.focus == 1)
	// a copy is the same, and apart
	c := tess.scene_copy(s)
	defer tess.scene_free(c)
	testing.expect(t, same(t, s, c))
	tess.cell_at(c, 3, 2, 0).terrain = 1
	testing.expect_value(t, tess.cell_at(s, 3, 2, 0).terrain, 0)
}

// An extent whose cells overflow 64 bits when multiplied in one go: the C
// version wrapped 2^30 x 2^30 x 16 levels to 0 cells and accepted it, so a
// 38-byte frame made a scene whose cell_at read past its cells.
@(test)
extent_overflow :: proc(t: ^testing.T) {
	e := tess.Extent{0, 0, 1 << 30, 1 << 30, 0, 15, 0}
	testing.expect(t, tess.scene_new(KNOW, e) == nil)
	frame := []u8{'T', 'E', 'S', 'S', 1, 1, 1,                     // format, a frame, knowledge
	              1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4,                // seq, time, content, viewer
	              0, 0, 0x80, 0x80, 0x80, 0x80, 4, 0x80, 0x80, 0x80, 0x80, 4, 0, 30, 0,   // the extent
	              0, 0, 0, 0, 0}                                   // no looks, cells, marks, overlays, annotations
	s, err := tess.decode(frame)
	testing.expect(t, s == nil && err == .Bad_Extent)
}

@(test)
text_form :: proc(t: ^testing.T) {
	s := tess.scene_new(KNOW, tess.Extent{0, 0, 2, 1, 0, 0, 0})
	defer tess.scene_free(s)
	tess.cell_at(s, 1, 0, 0).terrain = tess.look(s, "floor")
	tess.cell_at(s, 1, 0, 0).seen = 500
	tess.mark_put(s, tess.Mark{id = 4, seen = 500, x = 1, look = tess.look(s, "#Agent"), flags = {.Actor}, label = "R\"4\""})
	tess.overlay_put(s, "age", 0, 60, {})[1] = 30
	tess.annotation_add(s, .Callout, {.Developer_Only}, 0, []tess.Point{{1, 0, 0}}, "hi\n\x01")
	testing.expect_value(t, text(s),
		"tessera knowledge seq 1 time 1000 content 00000000000000ab viewer 4\n" +
		"extent 0 0 2 1 levels 0 0 focus 0\n" +
		"look 1 \"floor\"\n" +
		"look 2 \"#Agent\"\n" +
		"cell 1 0 0 terrain 1 seen 500 light 0 fluid 0 flags 0\n" +
		"mark 4 at 1 0 0 look 2 stack 0 flags 1 seen 500 holder 0 label \"R\\\"4\\\"\"\n" +
		"overlay \"age\" lo 0 hi 60 flags 0\n" +
		"  at 1 0 0 30\n" +
		"annotation callout flags 1 look 0 points 1,0,0 text \"hi\\n\\x01\"\n")
}

@(test)
golden :: proc(t: ^testing.T) {
	a := room()
	defer tess.scene_free(a)
	b := later(a)
	defer tess.scene_free(b)
	f, _ := tess.encode_frame(a)
	defer delete(f)
	testing.expect(t, string(f) == string(GOLDEN_FRAME), "the frame isn't the C encoder's")
	d, is_frame, _ := tess.encode_diff(a, b)
	defer delete(d)
	testing.expect(t, !is_frame && string(d) == string(GOLDEN_DIFF), "the diff isn't the C encoder's")
	testing.expect_value(t, text(b), GOLDEN_LATER)
	// and the C encoder's bytes decode to the same scenes
	ra, ea := tess.decode(GOLDEN_FRAME)
	defer tess.scene_free(ra)
	testing.expect(t, ea == .None && same(t, ra, a))
	rb, eb := tess.decode(GOLDEN_DIFF, ra)
	defer tess.scene_free(rb)
	testing.expect(t, eb == .None && same(t, rb, b))
}

@(test)
frames :: proc(t: ^testing.T) {
	s := room()
	r, _ := roundtrip(t, s)
	testing.expect(t, r != nil && same(t, s, r))
	tess.scene_free(r)
	tess.scene_free(s)
	// a large blank map is small: runs of equal cells
	s = tess.scene_new(tess.Meta{.Truth, 1, 0, 0, 0}, tess.Extent{-100, -100, 512, 512, -2, 2, 0})
	n: int
	r, n = roundtrip(t, s)
	testing.expect(t, r != nil && same(t, s, r) && n < 64)
	tess.scene_free(r)
	tess.scene_free(s)
}

@(test)
diffs :: proc(t: ^testing.T) {
	a := room()
	defer tess.scene_free(a)
	b := later(a)
	defer tess.scene_free(b)
	d, is_frame, _ := tess.encode_diff(a, b)
	f, _ := tess.encode_frame(b)
	testing.expect(t, !is_frame && len(d) < len(f))
	r, err := tess.decode(d, a)
	testing.expect(t, r != nil && same(t, r, b))
	tess.scene_free(r)
	// the base is left as it was
	a2 := room()
	testing.expect(t, same(t, a, a2))
	tess.scene_free(a2)
	// a diff needs its own frame
	r, err = tess.decode(d)
	testing.expect(t, r == nil && err == .No_Base)
	r, err = tess.decode(d, b)
	testing.expect(t, r == nil && err == .Other_Base)
	delete(d)
	delete(f)

	// nothing changed: a diff of almost nothing
	d, is_frame, _ = tess.encode_diff(b, b)
	testing.expect(t, !is_frame && len(d) < 40)
	delete(d)

	// what a diff can't say is a frame: another extent, another view, or
	// appearance keys made in another order
	other := tess.scene_new(KNOW, tess.Extent{0, 0, 4, 3, 0, 1, 0})
	d, is_frame, _ = tess.encode_diff(a, other)
	testing.expect(t, is_frame)
	r, _ = tess.decode(d, a)
	testing.expect(t, r != nil && same(t, r, other))
	tess.scene_free(r)
	delete(d)
	tess.scene_free(other)
	other = tess.scene_new(tess.Meta{.Truth, 2, 0, 0, 0}, ROOM)
	d, is_frame, _ = tess.encode_diff(a, other)
	testing.expect(t, is_frame)
	delete(d)
	tess.scene_free(other)
	other = tess.scene_new(KNOW, ROOM)
	tess.look(other, "wall.stone")
	tess.look(other, "floor")
	d, is_frame, _ = tess.encode_diff(a, other)
	testing.expect(t, is_frame)
	delete(d)
	tess.scene_free(other)
	d, is_frame, _ = tess.encode_diff(nil, a)
	testing.expect(t, is_frame)
	delete(d)

	// a stream: each diff applied to the last scene decoded
	shown, _ := roundtrip(t, a)
	now := tess.scene_copy(a)
	for step in i32(0) ..< 20 {
		next := tess.scene_copy(now)
		m := next.meta
		m.seq += 1
		m.time += 1000
		tess.set_meta(next, m)
		me := tess.mark_find(next, 4)^
		me.x = 3 + step % 4
		tess.mark_put(next, me)
		tess.cell_at(next, 3 + step % 4, 4, step % 2).seen = m.time
		if step == 10 do tess.look(next, "#Lamp")
		d, _, _ = tess.encode_diff(now, next)
		got, _ := tess.decode(d, shown)
		delete(d)
		testing.expect(t, got != nil)
		if got == nil {
			tess.scene_free(next)
			break
		}
		tess.scene_free(shown)
		shown = got
		tess.scene_free(now)
		now = next
	}
	testing.expect(t, same(t, shown, now))
	tess.scene_free(shown)
	tess.scene_free(now)
}

@(test)
developer :: proc(t: ^testing.T) {
	s := room()
	defer tess.scene_free(s)
	testing.expect_value(t, tess.strip_developer(s), 2)
	testing.expect(t, len(s.overlays) == 0 && len(s.annotations) == 1 && s.annotations[0].text == "to the pump")
	testing.expect_value(t, tess.strip_developer(s), 0)
}

// No input harms the decoder: every truncation fails cleanly, and every bit
// changed either fails or gives a scene. (A read out of bounds would stop
// the test: Odin checks every index.)
@(test)
malformed :: proc(t: ^testing.T) {
	a := room()
	defer tess.scene_free(a)
	b := later(a)
	defer tess.scene_free(b)
	f, _ := tess.encode_frame(a)
	defer delete(f)
	d, _, _ := tess.encode_diff(a, b)
	defer delete(d)
	clean := true
	for x in ([][]u8{f, d}) {
		for n in 0 ..< len(x) {
			if r, _ := tess.decode(x[:n], a); r != nil {
				clean = false
				tess.scene_free(r)
			}
		}
		flipped := make([]u8, len(x))
		defer delete(flipped)
		for i in 0 ..< len(x) do for bit in uint(0) ..< 8 {
			copy(flipped, x)
			flipped[i] ~= u8(1) << bit
			r, _ := tess.decode(flipped, a)
			tess.scene_free(r)
		}
	}
	testing.expect(t, clean)
	r, err := tess.decode(transmute([]u8)string("TESS\x01\x01\x00\x01"))
	testing.expect(t, r == nil && err == .Truncated)
	r, err = tess.decode(transmute([]u8)string("TESS\x09\x01"))
	testing.expect(t, r == nil && err == .Other_Version)
	r, err = tess.decode(transmute([]u8)string("nope"))
	testing.expect(t, r == nil && err == .Not_Tessera)
	// a count that claims more than the data holds is refused, not allocated
	huge := []u8{'T', 'E', 'S', 'S', 1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	             0, 0, 2, 1, 0, 0, 0,               // 2 x 1, one level
	             0xff, 0xff, 0xff, 0xff, 0x0f}      // looks: 4 billion
	r, err = tess.decode(huge)
	testing.expect(t, r == nil && err == .Count_Too_Large)
	testing.expect_value(t, tess.DECODE_ERROR_TEXT[.Count_Too_Large], "a count larger than the data")
}

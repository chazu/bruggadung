/*
Package tessera holds scenes of tile worlds with z-levels, for anything that
draws them (TESSERA.md).

A scene is plain data: an extent of tiles over levels; a cell for each tile
at each level (its terrain, when it was seen, its light, its fluid); marks,
the things drawn on cells; overlays, scalar fields over the cells; and
annotations, lines and callouts. A producer builds one from a simulation, a
backend draws it, and neither touches the other.

Every scene has a view. A truth scene (the developer's) names entities; a
knowledge scene (one character's) names that character's referents, and
shows only what it knows. Overlays and annotations may be tagged
Developer_Only; a backend showing a player's view strips them.

Scenes travel as frames (complete) and diffs (the changes since an earlier
frame), in a compact binary form (codec.odin): in-process, over a pipe, or
in a recording.

A scene's fields are for reading. Change cells in place (cell_at); change
everything else through these procedures, which keep marks in id order,
overlays in name order, and the scene's own copies of every string.
Everything a scene holds is in its allocator. A label or text of "" is none.
*/
package tessera

import "base:runtime"
import "core:slice"
import "core:strings"

FORMAT :: 1                    // the encoding's version
MAX_CELLS :: 64 * 1024 * 1024
MAX_LOOKS :: 65535

View :: enum u8 {
	Truth     = 0,
	Knowledge = 1,
}

// A rectangle of tiles over a range of levels, and the level looked at.
Extent :: struct {
	x0, y0, w, h: i32,         // tiles
	z0, z1:       i32,         // levels, inclusive
	focus:        i32,         // z0 <= focus <= z1
}

// What a scene is of: its view, its place in a stream of frames, the
// simulation time, the content its appearance keys belong to, and (a
// knowledge scene) whose knowledge it is.
Meta :: struct {
	view:    View,
	seq:     u64,              // frame sequence: a diff names the one it follows
	time:    i64,              // simulation ms
	content: u64,              // the content hash
	viewer:  u64,              // knowledge: the entity whose store it is
}

Cell_Flag :: enum u16 {
	In_Sight,                  // seen now, not remembered
	Open,                      // no floor: the level below shows through
	Door,
}
Cell_Flags :: distinct bit_set[Cell_Flag; u16]

// A tile at one level. A new scene's cells are blank: terrain 0 (none),
// never seen, dark, dry, no flags.
Cell :: struct {
	seen:    i64,              // ms it was last seen; -1 never
	fluid:   u32,              // water, mL on the tile
	terrain: u16,              // appearance key of what the cell is
	flags:   Cell_Flags,
	light:   u8,               // 0 dark .. 255 full daylight
}

BLANK_CELL :: Cell{seen = -1}

Mark_Flag :: enum u16 {
	Actor,                     // the one the viewer plays or follows
	Gone,                      // knowledge: no longer believed where it was seen
	In_Sight,                  // knowledge: seen now, not remembered
}
Mark_Flags :: distinct bit_set[Mark_Flag; u16]

// A thing drawn: on a cell, or, with a holder, held by or inside another
// mark (drawn as that one; listed by a backend).
Mark :: struct {
	id:      u64,              // entity (truth) or referent (knowledge); unique in a scene, not 0
	holder:  u64,              // the mark it is held by or inside, or 0
	seen:    i64,              // knowledge: ms it was last seen
	x, y, z: i32,              // its tile (a held mark: its holder's)
	look:    u16,              // appearance key
	stack:   i16,              // order among the marks on one cell, lowest first
	flags:   Mark_Flags,
	label:   string,           // or ""; the scene keeps its own copy
}

// Overlays and annotations the player may not see.
Tag :: enum u32 {
	Developer_Only,
}
Tags :: distinct bit_set[Tag; u32]

// A scalar field over the extent's cells (heat, CO2, light, knowledge age),
// with the range a backend maps to its palette.
Overlay :: struct {
	name:   string,
	values: []i32,             // one per cell, as cell_index orders them
	lo, hi: i32,
	tags:   Tags,
}

Annotation_Kind :: enum u8 {
	Line    = 0,
	Arrow   = 1,
	Path    = 2,
	Callout = 3,
}

Point :: struct {
	x, y, z: i32,
}

// A line, an arrow, a path through tiles, or a callout at a point.
Annotation :: struct {
	kind:   Annotation_Kind,
	tags:   Tags,
	look:   u16,
	points: []Point,
	text:   string,            // or ""
}

Scene :: struct {
	meta:        Meta,
	extent:      Extent,
	cells:       []Cell,       // level by level from z0, row by row, x fastest
	looks:       [dynamic]string,   // looks[k - 1] names key k
	marks:       [dynamic]Mark,     // by id
	overlays:    [dynamic]Overlay,  // by name
	annotations: [dynamic]Annotation,
	allocator:   runtime.Allocator,
}

// --- building -------------------------------------------------------------------------------

// A blank scene, or nil if the extent is empty, inverted, its focus out of
// range, or over MAX_CELLS cells.
scene_new :: proc(meta: Meta, extent: Extent, allocator := context.allocator) -> ^Scene {
	n, ok := extent_cells(extent)
	if !ok || !view_ok(meta.view) do return nil
	cells, err := make([]Cell, n, allocator)
	if err != nil do return nil
	for &c in cells do c = BLANK_CELL
	s := new(Scene, allocator)
	if s == nil {
		delete(cells, allocator)
		return nil
	}
	s^ = Scene {
		meta        = meta,
		extent      = extent,
		cells       = cells,
		looks       = make([dynamic]string, allocator),
		marks       = make([dynamic]Mark, allocator),
		overlays    = make([dynamic]Overlay, allocator),
		annotations = make([dynamic]Annotation, allocator),
		allocator   = allocator,
	}
	return s
}

scene_free :: proc(s: ^Scene) {
	if s == nil do return
	a := s.allocator
	for l in s.looks do delete(l, a)
	delete(s.looks)
	for m in s.marks do delete(m.label, a)
	delete(s.marks)
	for o in s.overlays do free_overlay(o, a)
	delete(s.overlays)
	for n in s.annotations do free_annotation(n, a)
	delete(s.annotations)
	delete(s.cells, a)
	free(s, a)
}

scene_copy :: proc(src: ^Scene, allocator := context.allocator) -> ^Scene {
	if src == nil do return nil
	s := scene_new(src.meta, src.extent, allocator)
	if s == nil do return nil
	copy(s.cells, src.cells)
	for l in src.looks do look_append(s, l)
	for m in src.marks do mark_put(s, m)
	for o in src.overlays {
		v := overlay_put(s, o.name, o.lo, o.hi, o.tags)
		if v == nil {
			scene_free(s)
			return nil
		}
		copy(v, o.values)
	}
	for n in src.annotations do annotation_add(s, n.kind, n.tags, n.look, n.points, n.text)
	return s
}

// The meta, unless its view is unknown.
set_meta :: proc(s: ^Scene, meta: Meta) {
	if view_ok(meta.view) do s.meta = meta
}

// The focus may move within the extent's levels; false if it can't.
set_focus :: proc(s: ^Scene, focus: i32) -> bool {
	if focus < s.extent.z0 || focus > s.extent.z1 do return false
	s.extent.focus = focus
	return true
}

// --- appearance keys --------------------------------------------------------------------------

// A name's key, made if new (1, 2, ...); 0 for "". Keys stay as they are
// made: a scene copied keeps them, and adds after.
look :: proc(s: ^Scene, name: string) -> u16 {
	if k := look_find(s, name); k != 0 || name == "" do return k
	return look_append(s, name) ? u16(len(s.looks)) : 0
}

look_find :: proc(s: ^Scene, name: string) -> u16 {
	if name == "" do return 0
	for l, i in s.looks do if l == name do return u16(i + 1)
	return 0
}

// The name of a key, or "" if there is none.
look_name :: proc(s: ^Scene, key: u16) -> string {
	return key != 0 && int(key) <= len(s.looks) ? s.looks[key - 1] : ""
}

// --- cells ---------------------------------------------------------------------------------

// A cell's place in cells, or -1 outside the extent.
cell_index :: proc(s: ^Scene, x, y, z: i32) -> int {
	e := s.extent
	dx, dy := i64(x) - i64(e.x0), i64(y) - i64(e.y0)
	if dx < 0 || dy < 0 || dx >= i64(e.w) || dy >= i64(e.h) || z < e.z0 || z > e.z1 do return -1
	return (int(z - e.z0) * int(e.h) + int(dy)) * int(e.w) + int(dx)
}

// The cell at a tile and level, or nil outside the extent.
cell_at :: proc(s: ^Scene, x, y, z: i32) -> ^Cell {
	i := cell_index(s, x, y, z)
	return i < 0 ? nil : &s.cells[i]
}

// --- marks ---------------------------------------------------------------------------------

// Adds a mark, or replaces the one with its id; false if the id is 0 or its
// holder is itself.
mark_put :: proc(s: ^Scene, m: Mark) -> bool {
	if m.id == 0 || m.holder == m.id do return false
	m := m
	m.label = strings.clone(m.label, s.allocator) if m.label != "" else ""
	i, found := mark_slot(s, m.id)
	if found {
		delete(s.marks[i].label, s.allocator)
		s.marks[i] = m
	} else {
		inject_at(&s.marks, i, m)
	}
	return true
}

mark_remove :: proc(s: ^Scene, id: u64) -> bool {
	i, found := mark_slot(s, id)
	if !found do return false
	delete(s.marks[i].label, s.allocator)
	ordered_remove(&s.marks, i)
	return true
}

// The mark with an id, or nil. For reading: it moves when marks are put or
// removed.
mark_find :: proc(s: ^Scene, id: u64) -> ^Mark {
	i, found := mark_slot(s, id)
	return &s.marks[i] if found else nil
}

// --- overlays and annotations --------------------------------------------------------------------

// Adds an overlay, its values all 0, or returns the one of that name (its
// range and tags updated): its values, to fill in; nil for no name.
overlay_put :: proc(s: ^Scene, name: string, lo, hi: i32, tags: Tags) -> []i32 {
	if name == "" do return nil
	for &o in s.overlays do if o.name == name {
		o.lo, o.hi, o.tags = lo, hi, tags
		return o.values
	}
	values, err := make([]i32, len(s.cells), s.allocator)
	if err != nil do return nil
	at := 0                    // by name: the order never depends on history
	for at < len(s.overlays) && s.overlays[at].name < name do at += 1
	inject_at(&s.overlays, at, Overlay{strings.clone(name, s.allocator), values, lo, hi, tags})
	return values
}

// Adds an annotation; false if it has no points, or is a callout with more
// than one, or of no kind.
annotation_add :: proc(s: ^Scene, kind: Annotation_Kind, tags: Tags, look: u16, points: []Point, text: string) -> bool {
	if len(points) == 0 || kind > .Callout || (kind == .Callout && len(points) != 1) do return false
	append(&s.annotations, Annotation {
		kind   = kind,
		tags   = tags,
		look   = look,
		points = slice.clone(points, s.allocator),
		text   = strings.clone(text, s.allocator) if text != "" else "",
	})
	return true
}

// What a player's view may show: the developer-only overlays and
// annotations taken out. Returns how many were.
strip_developer :: proc(s: ^Scene) -> int {
	removed, k := 0, 0
	for o in s.overlays {
		if .Developer_Only in o.tags {
			free_overlay(o, s.allocator)
			removed += 1
		} else {
			s.overlays[k] = o
			k += 1
		}
	}
	resize(&s.overlays, k)
	k = 0
	for n in s.annotations {
		if .Developer_Only in n.tags {
			free_annotation(n, s.allocator)
			removed += 1
		} else {
			s.annotations[k] = n
			k += 1
		}
	}
	resize(&s.annotations, k)
	return removed
}

// --- within the package -----------------------------------------------------------------------

// How many cells an extent has, checked a factor at a time so no product
// wraps: a frame's extent comes from its data.
@(private)
extent_cells :: proc(e: Extent) -> (int, bool) {
	if e.w <= 0 || e.h <= 0 || e.z1 < e.z0 || e.focus < e.z0 || e.focus > e.z1 do return 0, false
	levels := u64(i64(e.z1) - i64(e.z0)) + 1
	area := u64(e.w) * u64(e.h)          // < 2^62
	if area > MAX_CELLS || levels > MAX_CELLS || area * levels > MAX_CELLS do return 0, false
	// tile coordinates stay in range
	if i64(e.x0) + i64(e.w) > i64(max(i32)) || i64(e.y0) + i64(e.h) > i64(max(i32)) do return 0, false
	return int(area * levels), true
}

@(private)
view_ok :: proc(v: View) -> bool {
	return v == .Truth || v == .Knowledge
}

// Adds a look by name with no checks of its own: copying and decoding keep
// tables as given.
@(private)
look_append :: proc(s: ^Scene, name: string) -> bool {
	if len(s.looks) >= MAX_LOOKS do return false
	append(&s.looks, strings.clone(name, s.allocator))
	return true
}

@(private)
mark_slot :: proc(s: ^Scene, id: u64) -> (int, bool) {
	return slice.binary_search_by(s.marks[:], id, proc(m: Mark, id: u64) -> slice.Ordering {
		return slice.cmp(m.id, id)
	})
}

@(private)
overlay_named :: proc(s: ^Scene, name: string) -> ^Overlay {
	for &o in s.overlays do if o.name == name do return &o
	return nil
}

@(private)
free_overlay :: proc(o: Overlay, a: runtime.Allocator) {
	delete(o.name, a)
	delete(o.values, a)
}

@(private)
free_annotation :: proc(n: Annotation, a: runtime.Allocator) {
	delete(n.points, a)
	delete(n.text, a)
}

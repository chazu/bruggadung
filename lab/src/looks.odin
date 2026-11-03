package lab

/*
 * Looks (TESSERA.md decision 6; content/things.tri's #Look, content/looks/):
 * what a thing's look is, and what a theme draws for a look.
 *
 * A thing looks as the most specific kind it is with a look: its blueprint,
 * then its blueprint's type, then that type's parents in turn. A kind
 * several at once (a conjunction, "#Thing & #Assembly & #WaterStore") looks
 * as whichever of them has the look that prevails most. The world keeps the
 * `looks` family as it loads (world.looks); themes are read when a backend
 * asks (looks_glyphs).
 */

import "core:strings"
import "core:unicode/utf8"
import tri "../../triangle/odin/triangle"


Look_Entry :: struct {
	kind:     string,                // a type ("#Bed") or a blueprint ("scarecrow")
	look:     string,
	prevails: i64,
}

Looks :: struct {
	entries: [dynamic]Look_Entry,    // as the family lists them
}


// The `looks` family, copied out of content.
looks_load :: proc(content: ^tri.Content) -> Looks {
	looks := Looks{entries = make([dynamic]Look_Entry)}
	family := tri.family_index(content, "looks")
	for i: uint = 0; family != nil && i < tri.index_count(family); i += 1 {
		node := node_of(content, cstring(tri.index_tag(family, i)))
		kind, ok1 := looks_text(content, node, "kindOf")
		look, ok2 := looks_text(content, node, "look")
		if !ok1 || !ok2 do continue
		prevails, hi: i64
		if tri.node_interval(tri.at(content, node, "prevails"), &prevails, &hi) == 0 || prevails != hi do prevails = 0
		append(&looks.entries, Look_Entry{strings.clone(kind), strings.clone(look), prevails})
	}
	return looks
}


looks_free :: proc(looks: ^Looks) {
	for e in looks.entries {
		delete(e.kind)
		delete(e.look)
	}
	delete(looks.entries)
}


// A kind's look: a type or blueprint by name, or a conjunction of types; ""
// for one with none.
look_of_kind :: proc(world: ^World, kind: string) -> string {
	best: ^Look_Entry
	for part in strings.split(kind, " & ", context.temp_allocator) {
		e := looks_of_type(world, strings.trim_space(part))
		if e != nil && (best == nil || e.prevails > best.prevails) do best = e
	}
	return best.look if best != nil else ""
}


// An entity's look: its blueprint's, or else its kind's as it is seen.
look_of_entity :: proc(world: ^World, e: Entity_ID) -> string {
	info := world_info(world, e)
	if info == nil do return ""
	if l := looks_entry(world, string(info.blueprint)); l != nil do return l.look
	return look_of_kind(world, kind_of_entity(world, e))
}


// What a theme draws for a look: its glyph, ink, and the tile's ground if it
// fills one.
Glyph_Entry :: struct {
	look:       string,
	char:       rune,
	ink:        [3]u8,
	ground:     [3]u8,
	has_ground: bool,
}

// A theme's glyphs ("text", "tiles"), in the family's order, in `allocator`.
looks_glyphs :: proc(content: ^tri.Content, theme: string, allocator := context.allocator) -> []Glyph_Entry {
	glyphs := make([dynamic]Glyph_Entry, allocator)
	family := tri.family_index(content, "glyphs")
	for i: uint = 0; family != nil && i < tri.index_count(family); i += 1 {
		node := node_of(content, cstring(tri.index_tag(family, i)))
		of, ok1 := looks_text(content, node, "theme")
		look, ok2 := looks_text(content, node, "look")
		char, ok3 := looks_text(content, node, "char")
		if !ok1 || !ok2 || !ok3 || of != theme || len(char) == 0 do continue
		g := Glyph_Entry{look = strings.clone(look, allocator)}
		g.char, _ = utf8.decode_rune_in_string(char)
		g.ink = looks_colour(content, node, "ink", {200, 200, 200})
		if tri.at(content, node, "ground.first") != nil {
			g.ground, g.has_ground = looks_colour(content, node, "ground", {}), true
		}
		append(&glyphs, g)
	}
	return glyphs[:]
}


// A theme's glyph for a look: by its name, then by its family (the part
// before its first dot); false if neither.
glyph_for :: proc(glyphs: []Glyph_Entry, look: string) -> (Glyph_Entry, bool) {
	for g in glyphs do if g.look == look do return g, true
	if dot := strings.index_byte(look, '.'); dot > 0 {
		for g in glyphs do if g.look == look[:dot] do return g, true
	}
	return {}, false
}


// --- within the file ------------------------------------------------------------------

// The look of a type or blueprint by name, or of its type's parents in turn.
@(private = "file")
looks_of_type :: proc(world: ^World, name: string) -> ^Look_Entry {
	if e := looks_entry(world, name); e != nil do return e
	tc := world_tri(world)
	t := tri.type_named(tc, strings.clone_to_cstring(name, context.temp_allocator))
	for guard := 0; t != tri.Type(0xFFFFFFFF) && guard < 64; guard += 1 {
		if n := tri.type_name(tc, t); n != nil {
			if e := looks_entry(world, string(n)); e != nil do return e
		}
		t = tri.primary_parent(tc, t)
	}
	return nil
}

@(private = "file")
looks_entry :: proc(world: ^World, kind: string) -> ^Look_Entry {
	for &e in world.looks.entries do if e.kind == kind do return &e
	return nil
}

// The text at path, unquoted (\" and \\ undone).
@(private = "file")
looks_text :: proc(content: ^tri.Content, node: ^tri.Node, path: cstring) -> (string, bool) {
	buf: [256]u8
	v := tri.at(content, node, path) if node != nil else nil
	if v == nil do return "", false
	n := len(string(cstring(&buf[0]))) if tri.print(content, v, &buf[0], size_of(buf)) > 0 else 0
	if n < 2 || buf[0] != '"' || buf[n - 1] != '"' do return "", false
	s := strings.builder_make(context.temp_allocator)
	for i := 1; i < n - 1; i += 1 {
		if buf[i] == '\\' && i + 1 < n - 1 do i += 1
		strings.write_byte(&s, buf[i])
	}
	return strings.to_string(s), true
}

// A colour at path: its first three numbers, 0 to 255; `otherwise` if
// there aren't three.
@(private = "file")
looks_colour :: proc(content: ^tri.Content, node: ^tri.Node, path: cstring, otherwise: [3]u8) -> [3]u8 {
	c: [3]u8
	lo, hi: i64
	list := tri.at(content, node, path)
	for k in 0 ..< 3 {
		first := tri.at(content, list, "first") if list != nil else nil
		if first == nil || tri.node_interval(first, &lo, &hi) == 0 || lo != hi do return otherwise
		c[k] = u8(clamp(lo, 0, 255))
		list = tri.at(content, list, "rest")
	}
	return c
}

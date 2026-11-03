package tess_raylib

import "core:strings"
import rl "vendor:raylib"

// How an appearance key is drawn: a glyph, its colour, the tile's colour.
Glyph :: struct {
	ch: rune,
	fg: rl.Color,
	bg: rl.Color,
}

// A backend's mapping from appearance keys to glyphs (TESSERA.md, decision
// 6). A key is matched by its whole name, then by the part before its first
// dot ("wall.stone", then "wall"). A name with neither is drawn as its first
// letter, in a colour of its own: a look nobody gave a glyph still shows,
// and two such looks seldom look alike.
Theme :: struct {
	glyphs:     map[string]Glyph,
	background: rl.Color,
}

// An empty theme on a dark background: the caller gives it its glyphs
// (the lab's from content: content/looks/tiles.tri).
theme_make :: proc(allocator := context.allocator) -> Theme {
	return Theme{glyphs = make(map[string]Glyph, allocator), background = {8, 8, 10, 255}}
}

// A colour from red, green and blue, opaque.
rgb :: proc(c: [3]u8) -> rl.Color {
	return {c[0], c[1], c[2], 255}
}

theme_free :: proc(t: ^Theme) {
	for k in t.glyphs do delete(k, t.glyphs.allocator)
	delete(t.glyphs)
}

// Gives a key, or a family of keys (the part before a dot), its glyph.
theme_set :: proc(t: ^Theme, key: string, g: Glyph) {
	if k, _, just_inserted, _ := map_entry(&t.glyphs, key); just_inserted {
		k^ = strings.clone(key, t.glyphs.allocator)
	}
	t.glyphs[key] = g
}

theme_glyph :: proc(t: ^Theme, key: string) -> Glyph {
	if key == "" do return {' ', {0, 0, 0, 255}, t.background}
	if g, ok := t.glyphs[key]; ok do return g
	if dot := strings.index_byte(key, '.'); dot > 0 {
		if g, ok := t.glyphs[key[:dot]]; ok do return g
	}
	h: u32 = 2166136261               // FNV-1a: the same colour every run
	for b in transmute([]u8)key do h = (h ~ u32(b)) * 16777619
	colour := rl.ColorFromHSV(f32(h % 360), 0.55, 0.95)
	first := rune(key[0])
	if key[0] == '#' && len(key) > 1 do first = rune(key[1])
	return {first, colour, t.background}
}

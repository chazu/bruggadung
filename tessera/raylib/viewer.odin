/*
Package tess_raylib is Tessera's first window backend (TESSERA.md, slice 4):
scenes drawn top-down as glyph tiles, through raylib, which comes with Odin
(vendor:raylib).

It draws a scene and takes the viewer's own input: the camera (pan, zoom),
the focus level, and selecting a mark. It knows nothing of what a scene came
from. Running a simulation, and what a selected mark is, are the caller's.

The draw order is TESSERA.md's: terrain, fluid, marks by stack order, then
light and memory; levels below show, dimmer the deeper, through cells with no
floor. In
a knowledge scene a tile never seen is black, one remembered (not in sight)
is dimmed by its age, and a mark believed gone isn't drawn. Overlays and
annotations aren't drawn yet (slice 5).
*/
package tess_raylib

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

import "../../tessera"

HEADER_PX :: 18
PANEL_PX  :: 15

// What the viewer looks at, and how. Change it freely between frames.
Viewer :: struct {
	centre:   [2]f32,          // the tile at the middle of the map
	tile:     f32,             // px a tile is drawn
	focus:    i32,             // the level looked at
	levels:   [2]i32,          // the levels there are, inclusive: the focus stays in them
	depth:    i32,             // how many levels below the focus show through open cells
	selected: u64,             // a mark's id, or 0
	shade:    bool,            // darken by light
	panel:    i32,             // px wide at most, the panel on the right
	share:    f32,             // of the window's width, at most, the panel takes
	fonts:    Fonts,           // viewer_free lets them go
}

viewer_make :: proc(centre: [2]f32, focus: i32, levels: [2]i32) -> Viewer {
	return Viewer{centre = centre, tile = 22, focus = focus, levels = levels, depth = 16, shade = true, panel = 380,
	              share = 0.4}
}

viewer_free :: proc(v: ^Viewer) {
	fonts_free(&v.fonts)
}

// The map's part of the window, left of the panel.
map_pane :: proc(v: ^Viewer) -> rl.Rectangle {
	return {0, 0, f32(rl.GetScreenWidth() - panel_width(v)), f32(rl.GetScreenHeight())}
}

// How wide the panel is drawn: `panel`, or its `share` of a narrow window.
panel_width :: proc(v: ^Viewer) -> i32 {
	return min(v.panel, i32(f32(rl.GetScreenWidth()) * v.share))
}

// The tiles in view, a tile round them, and the focus level with the
// `depth` levels below it: the extent to ask a producer for.
viewer_extent :: proc(v: ^Viewer) -> tessera.Extent {
	pane := map_pane(v)
	half := [2]f32{pane.width, pane.height} / (2 * v.tile)
	x0 := i32(v.centre.x - half.x) - 1
	y0 := i32(v.centre.y - half.y) - 1
	return tessera.Extent {
		x0 = x0, y0 = y0,
		w = i32(2 * half.x) + 3, h = i32(2 * half.y) + 3,
		z0 = max(v.focus - v.depth, v.levels[0]), z1 = v.focus,
		focus = v.focus,
	}
}

// The tile under a point of the window.
tile_at :: proc(v: ^Viewer, p: [2]f32) -> [2]i32 {
	pane := map_pane(v)
	t := v.centre + (p - [2]f32{pane.width, pane.height} / 2) / v.tile
	return {i32(t.x + 0.5) if t.x >= -0.5 else i32(t.x - 0.5), i32(t.y + 0.5) if t.y >= -0.5 else i32(t.y - 0.5)}
}

// Where a tile's top-left corner is drawn.
tile_origin :: proc(v: ^Viewer, x, y: i32) -> [2]f32 {
	pane := map_pane(v)
	return ([2]f32{f32(x), f32(y)} - v.centre - 0.5) * v.tile + [2]f32{pane.width, pane.height} / 2
}

// The viewer's own input, against the scene on screen: arrows or WASD (or a
// right-button drag) pan, the wheel zooms (over the map: over the panel it
// is the caller's), Page Up and Page Down (or < and
// >) change level, a click selects the top mark on a tile (again: the next
// one down), Escape lets go of it. Returns whether the selection changed.
viewer_input :: proc(v: ^Viewer, s: ^tessera.Scene) -> bool {
	step := 24 / v.tile * rl.GetFrameTime() * 30
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) do v.centre.x -= step
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) do v.centre.x += step
	if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) do v.centre.y -= step
	if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) do v.centre.y += step
	if rl.IsMouseButtonDown(.RIGHT) do v.centre -= rl.GetMouseDelta() / v.tile
	if wheel := rl.GetMouseWheelMove(); wheel != 0 && rl.GetMousePosition().x < map_pane(v).width {
		v.tile = clamp(v.tile * (1.15 if wheel > 0 else 1 / 1.15), 6, 64)
	}
	shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
	if rl.IsKeyPressed(.PAGE_UP) || (shift && rl.IsKeyPressed(.PERIOD)) do v.focus = min(v.focus + 1, v.levels[1])
	if rl.IsKeyPressed(.PAGE_DOWN) || (shift && rl.IsKeyPressed(.COMMA)) do v.focus = max(v.focus - 1, v.levels[0])
	if rl.IsKeyPressed(.ESCAPE) && v.selected != 0 {
		v.selected = 0
		return true
	}
	mouse := rl.GetMousePosition()
	if s == nil || !rl.IsMouseButtonPressed(.LEFT) || mouse.x >= map_pane(v).width do return false
	t := tile_at(v, mouse)
	_, shown, _ := shown_at(s, t.x, t.y, v.focus)
	on := marks_on(s, t.x, t.y, shown, context.temp_allocator)
	before := v.selected
	if len(on) == 0 {
		v.selected = 0
	} else {
		next := 0         // the top one, or the one under the one selected
		for m, i in on do if m.id == v.selected do next = (i + 1) % len(on)
		v.selected = on[next].id
	}
	return v.selected != before
}

// The marks standing on a tile (not held), top first: by stack, then id.
marks_on :: proc(s: ^tessera.Scene, x, y, z: i32, allocator := context.temp_allocator) -> []tessera.Mark {
	on := make([dynamic]tessera.Mark, allocator)
	for m in s.marks do if m.holder == 0 && m.x == x && m.y == y && m.z == z do append(&on, m)
	for i in 1 ..< len(on) {   // few to a tile: an insertion sort, top first
		for j := i; j > 0 && above(on[j], on[j - 1]); j -= 1 do on[j], on[j - 1] = on[j - 1], on[j]
	}
	return on[:]
}

@(private)
above :: proc(a, b: tessera.Mark) -> bool {
	return a.stack > b.stack || (a.stack == b.stack && a.id > b.id)
}

// Draws a scene into the map pane, and the panel: `header` lines at the top
// left of the map, `panel` lines in the panel, wrapped to it.
viewer_draw :: proc(v: ^Viewer, s: ^tessera.Scene, theme: ^Theme, header, panel: []string) {
	rl.ClearBackground(theme.background)
	pane := map_pane(v)
	if s != nil do draw_map(v, s, theme)
	if v.selected != 0 && s != nil {
		if m := tessera.mark_find(s, v.selected); m != nil {
			for m.holder != 0 {             // held: its holder's tile shows it
				h := tessera.mark_find(s, m.holder)
				if h == nil do break
				m = h
			}
			if _, shown, _ := shown_at(s, m.x, m.y, v.focus); m.z == shown {
				o := tile_origin(v, m.x, m.y)
				rl.DrawRectangleLinesEx({o.x - 1, o.y - 1, v.tile + 2, v.tile + 2}, 2, {255, 220, 80, 255})
			}
		}
	}
	y: f32 = 6
	for line in header {
		rl.DrawRectangleV({4, y - 2}, {text_width(&v.fonts, line, HEADER_PX) + 8, HEADER_PX + 4}, {0, 0, 0, 180})
		draw_text(&v.fonts, line, {8, y}, HEADER_PX, {230, 230, 220, 255})
		y += HEADER_PX + 4
	}
	rl.DrawRectangle(i32(pane.width), 0, panel_width(v), rl.GetScreenHeight(), {18, 18, 24, 255})
	rl.DrawLine(i32(pane.width), 0, i32(pane.width), rl.GetScreenHeight(), {70, 70, 80, 255})
	y = 10
	for line in panel {
		for part in wrap(&v.fonts, line, f32(panel_width(v) - 20), PANEL_PX) {
			if y > f32(rl.GetScreenHeight()) - PANEL_PX do return
			draw_text(&v.fonts, part, {pane.width + 10, y}, PANEL_PX, {210, 210, 200, 255})
			y += PANEL_PX + 3
		}
		y += 4
	}
}

@(private)
draw_map :: proc(v: ^Viewer, s: ^tessera.Scene, theme: ^Theme) {
	e := s.extent
	knowing := s.meta.view == .Knowledge
	font := font_at(&v.fonts, i32(v.tile * 0.85 + 0.5))
	for y in e.y0 ..< e.y0 + e.h {
		for x in e.x0 ..< e.x0 + e.w {
			o := tile_origin(v, x, y)
			c, z, dim := shown_at(s, x, y, v.focus)
			if c == nil do continue
			if knowing && c.seen < 0 {   // never seen: nothing known of it
				rl.DrawRectangleV(o, {v.tile, v.tile}, {0, 0, 0, 255})
				continue
			}
			g := theme_glyph(theme, tessera.look_name(s, c.terrain))
			if c.fluid > 0 {
				depth := min(f32(c.fluid) / 20000, 1)   // mL on a tile: 20 L looks deep
				g.bg = mix(g.bg, {30, 70, 160, 255}, 0.35 + 0.5 * depth)
				g.fg, g.ch = {120, 170, 255, 255}, '~'
			}
			on := marks_on(s, x, y, z)
			shown := 0                   // marks drawn: not those believed gone
			for m in on {
				if .Gone in m.flags do continue
				if shown == 0 {
					top := theme_glyph(theme, tessera.look_name(s, m.look))
					g.ch, g.fg = top.ch, top.fg
				}
				shown += 1
			}
			if knowing && .In_Sight not_in c.flags {
				dim *= remembered(s.meta.time - c.seen)
			} else if v.shade {
				dim *= 0.6 + 0.4 * f32(c.light) / 255      // the night still readable
			}
			bg, fg := scale(g.bg, dim), scale(g.fg, dim)
			rl.DrawRectangleV(o, {v.tile, v.tile}, bg)
			if g.ch != ' ' && g.ch != 0 do draw_glyph(font, g.ch, o, v.tile, fg)
			if shown > 1 do rl.DrawRectangleV(o + {v.tile - 4, 1}, {3, 3}, scale({255, 255, 255, 255}, dim))
		}
	}
}

// The cell a tile shows from the focus level, its level, and how dim: the
// focus level's, or through cells with no floor the first below that has
// one (in a knowledge scene, that is known of), dimmer the deeper. nil if
// the tile isn't in the scene.
@(private)
shown_at :: proc(s: ^tessera.Scene, x, y, focus: i32) -> (c: ^tessera.Cell, z: i32, dim: f32) {
	c, z, dim = tessera.cell_at(s, x, y, focus), focus, 1
	if c == nil do return
	knowing := s.meta.view == .Knowledge
	for (.Open in c.flags) && (!knowing || c.seen >= 0) {
		below := tessera.cell_at(s, x, y, z - 1)
		if below == nil || (knowing && below.seen < 0) do break
		c, z = below, z - 1
		dim = 0.7 if z == focus - 1 else max(dim * 0.95, 0.3)
	}
	return
}

// How bright a tile remembered is, seen `age` ms ago: half, fading to a
// quarter over two days.
@(private)
remembered :: proc(age: i64) -> f32 {
	DAYS2 :: 2 * 86_400_000
	return 0.5 - 0.25 * f32(clamp(age, 0, DAYS2)) / DAYS2
}

// A glyph centred on its tile, at the size its font was made for.
@(private)
draw_glyph :: proc(font: rl.Font, ch: rune, o: [2]f32, tile: f32, fg: rl.Color) {
	buf: [8]u8
	n := copy(buf[:], fmt.bprintf(buf[:7], "%c", ch))
	buf[n] = 0
	size := f32(font.baseSize)
	w := rl.MeasureTextEx(font, cstring(&buf[0]), size, 0)
	at := o + ([2]f32{tile, tile} - w) / 2
	rl.DrawTextCodepoint(font, ch, {f32(int(at.x + 0.5)), f32(int(at.y + 0.5))}, size, fg)
}

@(private)
scale :: proc(c: rl.Color, k: f32) -> rl.Color {
	return {u8(f32(c.r) * k), u8(f32(c.g) * k), u8(f32(c.b) * k), c.a}
}

@(private)
mix :: proc(a, b: rl.Color, k: f32) -> rl.Color {
	return {
		u8(f32(a.r) * (1 - k) + f32(b.r) * k),
		u8(f32(a.g) * (1 - k) + f32(b.g) * k),
		u8(f32(a.b) * (1 - k) + f32(b.b) * k),
		255,
	}
}

// A temporary C string.
@(private)
cstr :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

// A line broken at spaces into parts at most `width` px wide (a word wider
// than that stands alone). Temporary.
wrap :: proc(f: ^Fonts, line: string, width: f32, px: i32) -> []string {
	parts := make([dynamic]string, context.temp_allocator)
	rest := line
	for len(rest) > 0 {
		if text_width(f, rest, px) <= width {
			append(&parts, rest)
			break
		}
		cut, i := 0, 0
		for i < len(rest) {
			j := strings.index_byte(rest[i:], ' ')
			end := len(rest) if j < 0 else i + j
			if text_width(f, rest[:end], px) > width do break
			cut = end
			if j < 0 do break
			i = end + 1
		}
		if cut == 0 do cut = strings.index_byte(rest, ' ') if strings.index_byte(rest, ' ') > 0 else len(rest)
		append(&parts, rest[:cut])
		rest = strings.trim_left_space(rest[cut:])
	}
	return parts[:]
}

package tess_raylib

import rl "vendor:raylib"

// DejaVu Sans Mono 2.37 (fonts/DejaVu-LICENSE: Bitstream Vera's terms, and
// DejaVu's changes in the public domain), built into the program: readable at
// small sizes, and with the symbols a glyph theme wants (♣, ≈, ⌂, ☺, box
// drawing, shades) beside ASCII and Latin-1.
FONT_TTF :: #load("fonts/DejaVuSansMono.ttf")

// The code points each size's atlas holds; any other draws as '?'.
@(private)
RANGES :: [?][2]rune {
	{0x20, 0x7E},              // ASCII
	{0xA0, 0xFF},              // Latin-1
	{0x391, 0x3C9},            // Greek
	{0x2010, 0x2027},          // dashes, bullets
	{0x2190, 0x2199},          // arrows
	{0x2219, 0x221E}, {0x2248, 0x2248}, {0x2260, 0x2265},
	{0x2302, 0x2302}, {0x2320, 0x2321},
	{0x2500, 0x259F},          // box drawing, blocks, shades
	{0x25A0, 0x25CF},          // squares, triangles, circles
	{0x263A, 0x263C}, {0x2640, 0x2642}, {0x2660, 0x266B},   // faces, suits, notes
}

// Fonts by pixel size, made as they are first wanted: drawn at the size it
// was rasterised at, a glyph stays sharp at every zoom.
Fonts :: struct {
	sizes:      [dynamic]i32,
	fonts:      [dynamic]rl.Font,
	codepoints: [dynamic]rune,
}

// The font at a size (at least 6 px). Only once the window is open.
font_at :: proc(f: ^Fonts, size: i32) -> rl.Font {
	px := max(size, 6)
	for s, i in f.sizes do if s == px do return f.fonts[i]
	if len(f.codepoints) == 0 {
		for r in RANGES do for c in r[0] ..= r[1] do append(&f.codepoints, c)
	}
	font := rl.LoadFontFromMemory(".ttf", raw_data(FONT_TTF), i32(len(FONT_TTF)), px,
	                              raw_data(f.codepoints), i32(len(f.codepoints)))
	rl.SetTextureFilter(font.texture, .BILINEAR)
	append(&f.sizes, px)
	append(&f.fonts, font)
	return font
}

fonts_free :: proc(f: ^Fonts) {
	for font in f.fonts do rl.UnloadFont(font)
	delete(f.sizes)
	delete(f.fonts)
	delete(f.codepoints)
}

// A line of text at a size, and how wide it is.
draw_text :: proc(f: ^Fonts, text: string, at: [2]f32, px: i32, colour: rl.Color) {
	rl.DrawTextEx(font_at(f, px), cstr(text), at, f32(px), 0, colour)
}

text_width :: proc(f: ^Fonts, text: string, px: i32) -> f32 {
	return rl.MeasureTextEx(font_at(f, px), cstr(text), f32(px), 0).x
}

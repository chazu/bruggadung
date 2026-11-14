package orogen

// A map as text, a character to a tile: for the tool, tests, and reading
// a map by eye.

import "core:strings"

// A tile's character: water `~`, sand `:`, grass `.`, stone `^`, outside
// the world a space.
class_glyph :: proc(c: Class) -> byte {
	#partial switch c {
	case .Water:
		return '~'
	case .Sand:
		return ':'
	case .Grass:
		return '.'
	case .Stone:
		return '^'
	}
	return ' '
}

// An elevation's character: 0 to 9, then a to z, then `+`.
elevation_glyph :: proc(e: i32) -> byte {
	switch {
	case e < 0:
		return '-'
	case e < 10:
		return '0' + byte(e)
	case e < 36:
		return 'a' + byte(e - 10)
	}
	return '+'
}

// The tiles of `w` by `h` from (x0, y0), a row to a line: each tile's
// ground class, or with `elevations` the level of its top (the ground,
// or the water over it).
map_text :: proc(m: Map, x0, y0, w, h: i32, elevations := false, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	row := make([]Column, int(w), context.temp_allocator)
	for j in 0 ..< h {
		columns(m, x0, y0 + j, w, 1, row)
		for c in row {
			switch {
			case c.class == .None:
				strings.write_byte(&b, ' ')
			case elevations:
				strings.write_byte(&b, elevation_glyph(top(m, c)))
			case:
				strings.write_byte(&b, class_glyph(c.class))
			}
		}
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

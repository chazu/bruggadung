// Orogen's tests: a column is the same whenever and however it is asked
// for; a map that wraps meets itself at the seam; cells follow from their
// column. golden/ holds a small map as the tool printed it: every platform
// must make the same, tile for tile.
//
//   odin test orogen/tests
package orogen_test

import "core:testing"
import orogen "../"

GOLDEN :: #load("golden/small.txt", string)
GOLDEN_ELEVATIONS :: #load("golden/small-elevations.txt", string)

small :: proc() -> orogen.Map {
	return orogen.map_make(7, 64, 24)
}

@(test)
the_golden_map :: proc(t: ^testing.T) {
	m := small()
	testing.expect_value(t, orogen.map_fault(m), "")
	testing.expect(t, orogen.map_text(m, 0, 0, 64, 24, false, context.temp_allocator) == GOLDEN, "classes moved")
	testing.expect(t, orogen.map_text(m, 0, 0, 64, 24, true, context.temp_allocator) == GOLDEN_ELEVATIONS,
	               "elevations moved")
}

// Asked backwards, one at a time, and in a block: the same columns.
@(test)
any_order :: proc(t: ^testing.T) {
	m := small()
	first: [24][64]orogen.Column
	for y in i32(0) ..< 24 do for x in i32(0) ..< 64 {
		c, ok := orogen.column(m, x, y)
		testing.expect(t, ok)
		first[y][x] = c
	}
	for y := i32(23); y >= 0; y -= 1 do for x := i32(63); x >= 0; x -= 1 {
		c, _ := orogen.column(m, x, y)
		testing.expect_value(t, c, first[y][x])
		e, _ := orogen.elevation(m, x, y)
		testing.expect_value(t, e, c.elevation)
	}
	block: [10 * 12]orogen.Column
	orogen.columns(m, 50, 15, 10, 12, block[:])
	for j in i32(0) ..< 12 do for i in i32(0) ..< 10 {
		x, y := 50 + i, 15 + j
		if x < 64 && y < 24 {
			testing.expect_value(t, block[j * 10 + i], first[y][x])
		} else {
			testing.expect_value(t, block[j * 10 + i].class, orogen.Class.None)
		}
	}
}

@(test)
the_edge :: proc(t: ^testing.T) {
	m := small()
	for p in ([][2]i32{{-1, 0}, {64, 0}, {0, -1}, {0, 24}}) {
		_, ok := orogen.column(m, p.x, p.y)
		testing.expect(t, !ok)
		testing.expect_value(t, orogen.cell(m, p.x, p.y, 10), orogen.Class.None)
	}
	testing.expect_value(t, orogen.cell(m, 5, 5, -1), orogen.Class.None)
	testing.expect_value(t, orogen.cell(m, 5, 5, m.levels), orogen.Class.None)
}

// East meets west: a tile a world's width away is the same tile, and the
// ground is no rougher across the seam than anywhere else.
@(test)
the_seam :: proc(t: ^testing.T) {
	m := orogen.map_make(11, 128, 48, true)
	testing.expect_value(t, orogen.map_fault(m), "")
	inside, across: i32
	for y in i32(0) ..< 48 {
		for x in i32(0) ..< 128 {
			c, ok := orogen.column(m, x, y)
			testing.expect(t, ok)
			for far in ([]i32{x + 128, x - 128, x + 5 * 128}) {
				again, ok2 := orogen.column(m, far, y)
				testing.expect(t, ok2)
				testing.expect_value(t, again, c)
			}
			next, _ := orogen.elevation(m, x + 1, y)
			if x == 127 {
				across = max(across, abs(next - c.elevation))
			} else {
				inside = max(inside, abs(next - c.elevation))
			}
		}
	}
	testing.expect(t, across <= inside, "the seam is rougher than the ground")
	_, off := orogen.column(m, 0, 48)
	testing.expect(t, !off, "north and south don't wrap")

	narrow := orogen.map_make(11, 100, 48, true)
	testing.expect(t, orogen.map_fault(narrow) != "", "a wrapping map is whole spans wide")
}

// A column's cells: rock and earth beneath, the ground at its elevation,
// air over it; water over a seabed, up to sea level.
@(test)
cells_of_a_column :: proc(t: ^testing.T) {
	m := small()
	seen: [orogen.Class]int
	steps, cliffs: int
	for y in i32(0) ..< 24 do for x in i32(0) ..< 64 {
		c, _ := orogen.column(m, x, y)
		seen[c.class] += 1
		testing.expect(t, c.elevation >= m.lowest && c.elevation <= m.highest)
		testing.expect_value(t, c.class == .Water, c.elevation < m.sea)
		for z in i32(0) ..< m.levels {
			k := orogen.cell(m, x, y, z)
			switch {
			case z < c.elevation:
				testing.expect(t, k == .Earth || k == .Rock)
				if c.elevation - z > m.soil do testing.expect_value(t, k, orogen.Class.Rock)
			case z == c.elevation:
				testing.expect_value(t, k, c.class)
			case c.class == .Water && z < m.sea:
				testing.expect_value(t, k, orogen.Class.Water)
			case:
				testing.expect_value(t, k, orogen.Class.Air)
			}
		}
		testing.expect_value(t, orogen.cell(m, x, y, orogen.top(m, c) + 1), orogen.Class.Air)
		if east, ok := orogen.elevation(m, x + 1, y); ok {
			d := abs(east - c.elevation)
			if d == 1 do steps += 1
			if d >= 2 {
				cliffs += 1
				if c.class != .Water do testing.expect_value(t, c.class, orogen.Class.Stone)
			}
		}
	}
	testing.expect(t, seen[.Water] > 0 && seen[.Sand] > 0 && seen[.Grass] > 0 && seen[.Stone] > 0,
	               "the small map has sea, shore, grass and stone")
	testing.expect(t, steps > 0, "the small map has steps")
	_ = cliffs
}

@(test)
seeds_differ :: proc(t: ^testing.T) {
	a, b := orogen.map_make(1, 64, 24), orogen.map_make(2, 64, 24)
	testing.expect(t, orogen.map_text(a, 0, 0, 64, 24, true, context.temp_allocator) !=
	                  orogen.map_text(b, 0, 0, 64, 24, true, context.temp_allocator))
}

@(test)
faults :: proc(t: ^testing.T) {
	m := small()
	m.highest = m.levels - 1
	testing.expect(t, orogen.map_fault(m) != "")
	m = small()
	m.span = 48
	testing.expect(t, orogen.map_fault(m) != "")
	m = small()
	m.octaves = 6
	testing.expect(t, orogen.map_fault(m) != "")
	m = small()
	m.sea = m.lowest - 1
	testing.expect(t, orogen.map_fault(m) != "")
}

@(test)
class_names :: proc(t: ^testing.T) {
	for c in orogen.Class {
		back, ok := orogen.class_named(orogen.class_name(c))
		testing.expect(t, ok)
		testing.expect_value(t, back, c)
	}
	_, ok := orogen.class_named("swamp")
	testing.expect(t, !ok)
}

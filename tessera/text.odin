package tessera

// A scene as text: a line for each thing in it, in a fixed order, cells and
// overlay values only where they differ from blank. Two scenes print the
// same exactly when they are the same: for tests, logs and diffs by eye.

import "core:fmt"
import "core:strings"

scene_text :: proc(s: ^Scene, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	write_scene_text(&b, s)
	return strings.to_string(b)
}

write_scene_text :: proc(b: ^strings.Builder, s: ^Scene) {
	m, e := s.meta, s.extent
	fmt.sbprintf(b, "tessera %s seq %d time %d content %016x viewer %d\n",
	             "truth" if m.view == .Truth else "knowledge", m.seq, m.time, m.content, m.viewer)
	fmt.sbprintf(b, "extent %d %d %d %d levels %d %d focus %d\n", e.x0, e.y0, e.w, e.h, e.z0, e.z1, e.focus)
	for l, i in s.looks {
		fmt.sbprintf(b, "look %d ", i + 1)
		write_quoted(b, l)
		strings.write_byte(b, '\n')
	}
	for c, i in s.cells {
		if c == BLANK_CELL do continue
		strings.write_string(b, "cell ")
		write_xyz(b, s, i)
		fmt.sbprintf(b, " terrain %d seen %d light %d fluid %d flags %d\n",
		             c.terrain, c.seen, c.light, c.fluid, transmute(u16)c.flags)
	}
	for k in s.marks {
		fmt.sbprintf(b, "mark %d at %d %d %d look %d stack %d flags %d seen %d holder %d",
		             k.id, k.x, k.y, k.z, k.look, k.stack, transmute(u16)k.flags, k.seen, k.holder)
		if k.label != "" {
			strings.write_string(b, " label ")
			write_quoted(b, k.label)
		}
		strings.write_byte(b, '\n')
	}
	for o in s.overlays {
		strings.write_string(b, "overlay ")
		write_quoted(b, o.name)
		fmt.sbprintf(b, " lo %d hi %d flags %d\n", o.lo, o.hi, transmute(u32)o.tags)
		for v, i in o.values do if v != 0 {
			strings.write_string(b, "  at ")
			write_xyz(b, s, i)
			fmt.sbprintf(b, " %d\n", v)
		}
	}
	@(static, rodata) kinds := [Annotation_Kind]string {
		.Line    = "line",
		.Arrow   = "arrow",
		.Path    = "path",
		.Callout = "callout",
	}
	for n in s.annotations {
		fmt.sbprintf(b, "annotation %s flags %d look %d points", kinds[n.kind], transmute(u32)n.tags, n.look)
		for p in n.points do fmt.sbprintf(b, " %d,%d,%d", p.x, p.y, p.z)
		if n.text != "" {
			strings.write_string(b, " text ")
			write_quoted(b, n.text)
		}
		strings.write_byte(b, '\n')
	}
}

// A string in double quotes, byte by byte: quotes and backslashes escaped,
// a newline as \n, other control bytes as \xNN.
@(private = "file")
write_quoted :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for i in 0 ..< len(s) {
		c := s[i]
		switch {
		case c == '"' || c == '\\': strings.write_byte(b, '\\'); strings.write_byte(b, c)
		case c == '\n':             strings.write_string(b, "\\n")
		case c < 0x20 || c == 0x7f: fmt.sbprintf(b, "\\x%02x", c)
		case:                       strings.write_byte(b, c)
		}
	}
	strings.write_byte(b, '"')
}

// The tile and level of the i-th cell.
@(private = "file")
write_xyz :: proc(b: ^strings.Builder, s: ^Scene, i: int) {
	e := s.extent
	per := int(e.w) * int(e.h)
	fmt.sbprintf(b, "%d %d %d", i64(e.x0) + i64(i % per % int(e.w)), i64(e.y0) + i64(i % per / int(e.w)),
	             i64(e.z0) + i64(i / per))
}

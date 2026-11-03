package lab

// Odin's fmt against printf, for each kind of format the lab uses: the
// scenario hashes are of printed text, which the Objective-C lab printed
// with printf. Odin's fmt is not printf (a width pads a number with zeros
// unless the format has the space flag; `{` starts a placeholder), so the
// lab's formats are written to print what printf did; this holds the rule
// to the pinned Odin release, and says when a new one changes it.

import "core:c/libc"
import "core:fmt"

@(private = "file")
Format_Case :: struct {
	c_fmt, odin_fmt: cstring,
	value:           union {i64, u64, f64, string, rune},
}

@(private = "file", rodata)
FORMAT_CASES := [?]Format_Case {
	{"%lld", "%d", i64(-9223372036854775807 - 1)},
	{"%lld", "%d", i64(0)},
	{"%llu", "%d", u64(18446744073709551615)},
	{"%+d", "%+d", i64(0)},
	{"%+d", "%+d", i64(-3)},
	{"%+d", "%+d", i64(12)},
	{"%10llu", "% 10d", u64(4096)},
	{"%-10lld|", "%-10d|", i64(-42)},
	{"%016llx", "%016x", u64(0x82409220f2de70ec)},
	{"%08x", "%08x", u64(0xbeef)},
	{"%02x", "%02x", u64(7)},
	{"%2x", "% 2x", u64(7)},
	{"%-14s|", "%-14s|", "cistern-b"},
	{"%15s|", "%15s|", "marked-nail"},
	{"%c", "%c", 'x'},
	{"%.1f", "%.1f", 0.05},
	{"%.1f", "%.1f", 0.25},
	{"%.1f", "%.1f", 2.35},
	{"%.1f", "%.1f", -0.04},
	{"%.1f", "%.1f", f64(1e15)},
	{"%10.1f", "% 10.1f", 21.75},
	{"%10.1f", "% 10.1f", -273.15},
	{"#A & { x: %lld }", "#A & {{ x: %d }}", i64(7)},
	{"}} %s {{", "}}}} %s {{{{", "both"},
}

test_formatting :: proc() {
	buf: [256]u8
	for k in FORMAT_CASES {
		ofmt := string(k.odin_fmt)
		odin: string
		switch v in k.value {
		case i64:    libc.snprintf(raw_data(buf[:]), len(buf), k.c_fmt, v);              odin = fmt.tprintf(ofmt, v)
		case u64:    libc.snprintf(raw_data(buf[:]), len(buf), k.c_fmt, v);              odin = fmt.tprintf(ofmt, v)
		case f64:    libc.snprintf(raw_data(buf[:]), len(buf), k.c_fmt, v);              odin = fmt.tprintf(ofmt, v)
		case rune:   libc.snprintf(raw_data(buf[:]), len(buf), k.c_fmt, i32(v));         odin = fmt.tprintf(ofmt, v)
		case string: libc.snprintf(raw_data(buf[:]), len(buf), k.c_fmt, ns_utf8(v));     odin = fmt.tprintf(ofmt, v)
		}
		printed := string(cstring(raw_data(buf[:])))
		bg_check(printed == odin)
		if printed != odin do fmt.eprintf("      %s: printf %q, fmt %q\n", k.c_fmt, printed, odin)
	}
}

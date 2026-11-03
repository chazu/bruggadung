// The Odin spike: what a port of the lab rests on, checked on each platform.
//
//   cd lab && odin run odin            (or: make -C lab odin-spike)
//
// 1. The content build: Triangle, linked as a C library, loads lab/content
//    and gives the content hash the Objective-C lab was generated against
//    (BG_CONTENT_HASH in src/generated/BGComponents.h).
// 2. Formatting: the scenario hashes are of printed text, so Odin's fmt must
//    print what the lab's printf formats print, for each kind of format the
//    lab uses (tallied from lab/src).
package lab

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import tri "../../triangle/odin/triangle"

main :: proc() {
	failed := 0
	if !check_content() do failed += 1
	failed += check_formatting()
	if failed > 0 {
		fmt.printf("spike: %d failed\n", failed)
		os.exit(1)
	}
	fmt.println("spike: as the Objective-C lab")
}

check_content :: proc() -> bool {
	content := load_content()
	if content == nil do return false
	defer tri.content_free(content)
	got := tri.content_hash(content)
	want, ok := expected_hash()
	if !ok {
		fmt.eprintln("spike: no BG_CONTENT_HASH in src/generated/BGComponents.h")
		return false
	}
	fmt.printf("content %016x: %d types, %d instances, %d diagnostics\n",
	           got, tri.type_count(content), tri.instance_count(content), tri.diag_count(content))
	if got != want {
		fmt.printf("  but the lab expects %016x\n", want)
		return false
	}
	return true
}

expected_hash :: proc() -> (u64, bool) {
	data, err := os.read_entire_file("src/generated/BGComponents.h", context.temp_allocator)
	if err != nil do return 0, false
	text := string(data)
	key :: "#define BG_CONTENT_HASH 0x"
	i := strings.index(text, key)
	if i < 0 do return 0, false
	rest := text[i + len(key):]
	end := strings.index_any(rest, "ULL\n")
	return strconv.parse_u64_of_base(rest[:end], 16)
}

// Each case: a C format, the Odin format meant to print the same, a value.
// Odin's fmt is not printf: a width pads a number with zeros unless the
// format has the space flag, so printf's %10d is Odin's "% 10d" (and printf's
// own space flag, which the lab never uses, has no Odin equivalent). Strings
// pad with spaces either way. The rule holds for the pinned Odin release;
// this table is what says so when the release changes.
Case :: struct {
	c_fmt, odin_fmt: cstring,
	value:           union {i64, u64, f64, string, rune},
}

CASES := [?]Case {
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
}

check_formatting :: proc() -> int {
	failed := 0
	buf: [256]u8
	for k in CASES {
		ofmt := string(k.odin_fmt)
		odin: string
		switch v in k.value {
		case i64:    libc.snprintf(raw_data(buf[:]), len(buf), k.c_fmt, v);              odin = fmt.tprintf(ofmt, v)
		case u64:    libc.snprintf(raw_data(buf[:]), len(buf), k.c_fmt, v);              odin = fmt.tprintf(ofmt, v)
		case f64:    libc.snprintf(raw_data(buf[:]), len(buf), k.c_fmt, v);              odin = fmt.tprintf(ofmt, v)
		case rune:   libc.snprintf(raw_data(buf[:]), len(buf), k.c_fmt, i32(v));         odin = fmt.tprintf(ofmt, v)
		case string: libc.snprintf(raw_data(buf[:]), len(buf), k.c_fmt, tri.to_c(v));    odin = fmt.tprintf(ofmt, v)
		}
		c := string(cstring(raw_data(buf[:])))
		if c != odin {
			fmt.printf("  %-8s printf %q, but fmt %q\n", k.c_fmt, c, odin)
			failed += 1
		}
	}
	fmt.printf("formatting: %d of %d cases as printf\n", len(CASES) - failed, len(CASES))
	return failed
}

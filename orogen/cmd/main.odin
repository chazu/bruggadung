// The orogen tool: a map printed as text, a character to a tile.
//
//   orogen [--seed N] [--wide W] [--high H] [--wraps] [--elevations]
//          [--at X,Y] [--size W,H]
//
// Prints the whole map, or the `--size` tiles from `--at`; with
// `--elevations`, each tile's surface level in place of its ground class.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import orogen "../"

main :: proc() {
	seed: u64 = 1
	wide, high: i32 = 96, 40
	wraps, elevations: bool
	at, size: [2]i32
	sized: bool

	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		value :: proc(args: []string, i: ^int) -> string {
			if i^ + 1 >= len(args) do usage()
			i^ += 1
			return args[i^]
		}
		switch arg {
		case "--seed":
			n, ok := strconv.parse_u64(value(args, &i))
			if !ok do usage()
			seed = n
		case "--wide":
			wide = number(value(args, &i))
		case "--high":
			high = number(value(args, &i))
		case "--wraps":
			wraps = true
		case "--elevations":
			elevations = true
		case "--at":
			at = pair(value(args, &i))
		case "--size":
			size = pair(value(args, &i))
			sized = true
		case:
			usage()
		}
	}

	m := orogen.map_make(seed, wide, high, wraps)
	if fault := orogen.map_fault(m); fault != "" {
		fmt.eprintfln("orogen: %s", fault)
		os.exit(1)
	}
	if !sized do size = {wide - at.x, high - at.y}
	fmt.print(orogen.map_text(m, at.x, at.y, size.x, size.y, elevations))
}

number :: proc(s: string) -> i32 {
	n, ok := strconv.parse_int(s)
	if !ok do usage()
	return i32(n)
}

pair :: proc(s: string) -> [2]i32 {
	comma := strings.index_byte(s, ',')
	if comma < 0 do usage()
	return {number(s[:comma]), number(s[comma + 1:])}
}

usage :: proc() -> ! {
	fmt.eprintln("usage: orogen [--seed N] [--wide W] [--high H] [--wraps] [--elevations] [--at X,Y] [--size W,H]")
	os.exit(2)
}

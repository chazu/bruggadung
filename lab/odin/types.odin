package lab

// The types every part of the laboratory shares: entity IDs, simulation
// time, seeds, and locations (src/core/BGTypes.h). Plain data, so stores and
// proposals hold them by value.

import "core:fmt"

// An entity is an ID from the world's counter, never reused. 0 is no entity.
// A proposal group names the entities it creates by handles, which have the
// top bit set until the group applies.
Entity_ID :: u64

NO_ENTITY :: Entity_ID(0)
HANDLE_BIT :: u64(0x8000000000000000)

handle :: #force_inline proc "contextless" (n: u64) -> Entity_ID {
	return Entity_ID(HANDLE_BIT | n)
}

is_handle :: #force_inline proc "contextless" (e: Entity_ID) -> bool {
	return e & HANDLE_BIT != 0
}

// NSNotFound: what a lookup of an index returns when there is none.
NOT_FOUND :: uint(max(int))

// Simulation time, in milliseconds.
Time :: struct {
	ms: i64,
}

time_make :: #force_inline proc "contextless" (ms: i64) -> Time {
	return Time{ms}
}

TIME_NEVER :: Time{max(i64)}

// Seeds and the deterministic streams drawn from them (splitmix64). Nothing
// that must not depend on creation order derives from an entity ID.
mix :: #force_inline proc "contextless" (x: u64) -> u64 {
	x := x
	x += 0x9e3779b97f4a7c15
	x = (x ~ (x >> 30)) * 0xbf58476d1ce4e5b9
	x = (x ~ (x >> 27)) * 0x94d049bb133111eb
	return x ~ (x >> 31)
}

// BGMixString: the bytes of a C string, up to its NUL (none for nil).
mix_string :: proc "contextless" (h: u64, s: cstring) -> u64 {
	h := h
	if s != nil {
		for p := ([^]u8)(s); p[0] != 0; p = p[1:] do h = mix(h ~ u64(p[0]))
	}
	return mix(h ~ 0xff)
}

// The same for an Odin string: its bytes, up to a NUL if it has one, as the
// C one would read them.
mix_text :: proc "contextless" (h: u64, s: string) -> u64 {
	h := h
	for i in 0 ..< len(s) {
		if s[i] == 0 do break
		h = mix(h ~ u64(s[i]))
	}
	return mix(h ~ 0xff)
}

next :: #force_inline proc "contextless" (state: ^u64) -> u64 {
	state^ = mix(state^)
	return state^
}

// Location: the one exclusive relation every physical entity has.
Location_Form :: enum i32 {
	None     = 0,
	On_Tile,               // x, y, level
	In,                    // place: a container
	Held_By,               // place: an agent; slot: the hand
	Part_Of,               // place: an assembly; role and slot: the index
}

Location :: struct {
	form:  Location_Form,
	place: Entity_ID,
	x:     i32,
	y:     i32,
	level: i32,
	slot:  i32,
	role:  [16]u8,         // NUL-terminated, the rest zero
}

location_make_none :: #force_inline proc "contextless" () -> Location {
	return {}
}

on_tile :: #force_inline proc "contextless" (x, y, level: i32) -> Location {
	return Location{form = .On_Tile, x = x, y = y, level = level}
}

// BGIn (`in` is Odin's keyword).
in_ :: #force_inline proc "contextless" (container: Entity_ID) -> Location {
	return Location{form = .In, place = container}
}

held_by :: #force_inline proc "contextless" (agent: Entity_ID, hand: i32) -> Location {
	return Location{form = .Held_By, place = agent, slot = hand}
}

// The role is cut to 15 bytes, as strncpy into the C struct cut it.
part_of :: proc "contextless" (assembly: Entity_ID, role: string, index: i32) -> Location {
	loc := Location{form = .Part_Of, place = assembly, slot = index}
	for i in 0 ..< min(len(role), len(loc.role) - 1) {
		if role[i] == 0 do break
		loc.role[i] = role[i]
	}
	return loc
}

// A location's role as a string (up to its NUL).
location_role :: proc(loc: ^Location) -> string {
	n := 0
	for n < len(loc.role) && loc.role[n] != 0 do n += 1
	return string(loc.role[:n])
}

// The role as a C string: a location's role is always NUL-terminated.
location_role_c :: proc(loc: ^Location) -> cstring {
	return cstring(&loc.role[0])
}

location_equal :: #force_inline proc "contextless" (a, b: Location) -> bool {
	return a == b
}

// The location as text, such as "in(7)" or "heldBy(3, 0)".
location_format :: proc(loc: Location, allocator := context.temp_allocator) -> string {
	loc := loc
	switch loc.form {
	case .None:    return fmt.aprintf("nowhere", allocator = allocator)
	case .On_Tile: return fmt.aprintf("onTile(%d, %d, %d)", loc.x, loc.y, loc.level, allocator = allocator)
	case .In:      return fmt.aprintf("in(%d)", loc.place, allocator = allocator)
	case .Held_By: return fmt.aprintf("heldBy(%d, %d)", loc.place, loc.slot, allocator = allocator)
	case .Part_Of: return fmt.aprintf("partOf(%d, %s, %d)", loc.place, location_role(&loc), loc.slot, allocator = allocator)
	}
	return ""
}

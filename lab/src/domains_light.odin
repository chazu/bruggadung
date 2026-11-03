package lab

// BGLight — light as a domain (KNOWLEDGE.md decision 14), giving perception
// its conditions (§5). Daylight follows the clock: day from `dawn` to
// `nightfall` (content/light/light.tri's `daylight`), twilight `twilight`
// either side, night between. Indoors, in a room with air (content/air/air.tri)
// none of whose doorways stands open, it is a step darker.
// A lamp shining lights its `reach`, burning its oil down as it does (as
// of `oilAt`, computed when read); spent, it goes out. A lit fire glows a
// tile round. Nothing is stepped between: the horizon is the next change
// of the daylight, or the next lamp to burn out.
//
// (ported from the Objective-C lab's domains/BGLight.m)

import tri "../../triangle/odin/triangle"


@(private = "file")
BG_DAY :: i64(86400000)


// The tile an entity stands on, or is on through what holds it.
@(private = "file")
ground_tile :: proc(world: ^World, e: Entity_ID, tile: ^Location) -> bool {
	loc:   Location
	guard: uint
	e     := e

	for guard = 0; guard < 64; guard += 1 {
		loc = world_location_of(world, e)
		if loc.form == .On_Tile {
			tile^ = loc
			return true
		}
		if loc.form == .None || loc.place == 0 {
			return false
		}
		e = loc.place
	}
	return false
}


// The authored daylight: dawn, nightfall, and the twilight either side.
@(private = "file")
authored_daylight :: proc(world: ^World, dawn: ^i64, nightfall: ^i64, twilight: ^i64) -> bool {
	pattern: ^tri.Node
	v:       ^tri.Node
	content: ^tri.Content
	family:  ^tri.Index
	lo:      i64
	hi:      i64

	content = world_tri(world)
	family  = tri.family_index(content, "light")
	pattern = tri.pattern(content, cstring(tri.index_tag(family, 0))) if family != nil && tri.index_count(family) != 0 else nil
	if pattern == nil {
		return false
	}
	v = tri.at(content, pattern, "dawn")
	if v == nil || tri.node_interval(v, &lo, &hi) == 0 || lo != hi {
		return false
	}
	dawn^ = lo
	v = tri.at(content, pattern, "nightfall")
	if v == nil || tri.node_interval(v, &lo, &hi) == 0 || lo != hi {
		return false
	}
	nightfall^ = lo
	v = tri.at(content, pattern, "twilight")
	if v == nil || tri.node_interval(v, &lo, &hi) == 0 || lo != hi {
		return false
	}
	twilight^ = lo
	return true
}


// Daylight outdoors at t: 2 day, 1 twilight, 0 night; day if none is
// authored.
@(private = "file")
outdoors :: proc(world: ^World, t: i64) -> i32 {
	dawn:      i64
	nightfall: i64
	twilight:  i64
	h:         i64

	if !authored_daylight(world, &dawn, &nightfall, &twilight) {
		return 2
	}
	h = t % BG_DAY
	if h >= dawn && h < nightfall {
		return 2
	}
	if (h >= dawn - twilight && h < dawn) || (h >= nightfall && h < nightfall + twilight) {
		return 1
	}
	return 0
}


// Whether a tile is shut in: in a room with air (TERRAIN.md step 3) none
// of whose ways out stands open, a doorway with no door or its door ajar.
@(private = "file")
shut_in :: proc(world: ^World, tile: Location) -> bool {
	air: Entity_ID

	air = world_air_region_at(world, tile)
	return air != 0 && world_air_is_shut_in(world, air)
}


// Daylight outdoors at t: 2 day, 1 twilight, 0 night.
daylight :: proc(world: ^World, t: i64) -> i32 {
	return outdoors(world, t)
}


// What oil a lamp has left to burn at t (ms).
lamp_oil :: proc(lamp: ^Lamp, t: i64) -> i64 {
	left: i64

	left = lamp.oil
	if lamp.shining && t > lamp.oilAt {
		left -= t - lamp.oilAt
	}
	return 0 if left < 0 else left
}


// The light at a tile at t: 2 day, 1 dusk, 0 night.
light_at :: proc(world: ^World, tile: Location, t: i64) -> i32 {
	lamp:  ^Lamp
	fire:  ^Combustor
	store: ^Store
	at:    Location
	i:     uint
	light: i32

	// the day, shaded in a room shut in
	light = outdoors(world, t)
	if light > 0 && shut_in(world, tile) {
		light -= 1
	}
	// lamps with oil left, shining
	store = world_store_for_kind(world, world_kind_named(world, "Lamp"))
	for i = 0; light < 2 && i < store_count(store); i += 1 {
		lamp = (^Lamp)(store_record_at_index(store, i))
		if lamp.shining && lamp_oil(lamp, t) > 0 && ground_tile(world, store_entity_at_index(store, i), &at) &&
		   at.level == tile.level && i64(abs(at.x - tile.x)) <= lamp.reach && i64(abs(at.y - tile.y)) <= lamp.reach {
			light = 2
		}
	}
	// fires, a tile round
	store = world_store_for_kind(world, world_kind_named(world, "Combustor"))
	for i = 0; light < 2 && i < store_count(store); i += 1 {
		fire = (^Combustor)(store_record_at_index(store, i))
		if fire.lit && ground_tile(world, store_entity_at_index(store, i), &at) && at.level == tile.level &&
		   abs(at.x - tile.x) <= 1 && abs(at.y - tile.y) <= 1 {
			light = 2
		}
	}
	return light
}


Light :: struct {
	using object: Object,
	world:        ^World,
}


light_init_with_world :: proc(world: ^World) -> ^Light {
	self := object_new(Light, light_dealloc)
	self.world = retain(world)
	return self
}


light_dealloc :: proc(self: ^Light) {
	release(self.world)
}


light_name :: proc(self: ^Light) -> string {
	return "light"
}


light_is_active :: proc(self: ^Light) -> bool {
	return true
}


// The next change of the daylight, or the next lamp to burn out.
light_horizon_at :: proc(self: ^Light, t: Time) -> Horizon {
	lamp:      ^Lamp
	lamps:     ^Store
	h:         Horizon
	i:         uint
	marks:     [4]i64
	dawn:      i64
	nightfall: i64
	twilight:  i64
	day:       i64
	when_:     i64
	k:         int

	h.safeStep  = TIME_NEVER
	h.nextEvent = TIME_NEVER
	if authored_daylight(self.world, &dawn, &nightfall, &twilight) {
		marks[0] = dawn - twilight
		marks[1] = dawn
		marks[2] = nightfall
		marks[3] = nightfall + twilight
		for day = t.ms - t.ms % BG_DAY; day <= t.ms + BG_DAY; day += BG_DAY {
			for k = 0; k < 4; k += 1 {
				if day + marks[k] > t.ms && day + marks[k] < h.nextEvent.ms {
					h.nextEvent = time_make(day + marks[k])
				}
			}
		}
	}
	lamps = world_store_for_kind(self.world, world_kind_named(self.world, "Lamp"))
	for i = 0; i < store_count(lamps); i += 1 {
		lamp = (^Lamp)(store_record_at_index(lamps, i))
		if !lamp.shining || lamp.oil <= 0 {
			continue
		}
		when_ = lamp.oilAt + lamp.oil
		if when_ > t.ms && when_ < h.nextEvent.ms {
			h.nextEvent = time_make(when_)
		}
	}
	return h
}


// A lamp spent by t1 goes out.
light_advance_from :: proc(self: ^Light, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	lamp:  ^Lamp
	group: ^Proposal_Group
	lamps: ^Store
	i:     uint

	lamps = world_store_for_kind(world, world_kind_named(world, "Lamp"))
	group = nil
	for i = 0; i < store_count(lamps); i += 1 {
		lamp = (^Lamp)(store_record_at_index(lamps, i))
		if !lamp.shining || lamp_oil(lamp, t1.ms) > 0 {
			continue
		}
		if group == nil {
			group = proposal_group_group_with_phase(.Process, "light: a lamp burns out")
		}
		proposal_group_set_of_to(group, "Lamp.shining", whole(store_entity_at_index(lamps, i)), 0)
		proposal_group_set_of_to(group, "Lamp.oil", whole(store_entity_at_index(lamps, i)), 0)
		proposal_group_set_of_to(group, "Lamp.oilAt", whole(store_entity_at_index(lamps, i)), t1.ms)
	}
	if group != nil {
		committer_submit(committer, group)
	}
}


light_check_in_all :: proc(self: ^Light) {
}


light_saved_state :: proc(self: ^Light) -> []string {
	return make([]string, 0, context.temp_allocator)
}


light_restore_saved_state :: proc(self: ^Light, lines: []string) {
}


light_as_domain :: proc(self: ^Light) -> Domain {
	return Domain{
		data                = self,
		name                = proc(data: rawptr) -> string {return light_name((^Light)(data))},
		check_in_all        = proc(data: rawptr) {light_check_in_all((^Light)(data))},
		saved_state         = proc(data: rawptr) -> []string {return light_saved_state((^Light)(data))},
		restore_saved_state = proc(data: rawptr, lines: []string) {light_restore_saved_state((^Light)(data), lines)},
		is_active           = proc(data: rawptr) -> bool {return light_is_active((^Light)(data))},
		horizon_at          = proc(data: rawptr, t: Time) -> Horizon {return light_horizon_at((^Light)(data), t)},
		advance_from        = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
			light_advance_from((^Light)(data), t0, t1, world, committer)
		},
	}
}

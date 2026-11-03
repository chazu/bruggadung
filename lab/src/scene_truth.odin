package lab

/*
 * Truth scenes: Tessera's developer view of a world (TESSERA.md, decision
 * 2, slice 2), built from world state at a boundary. A backend draws them;
 * nothing here draws.
 *
 * Cut points: a mark's appearance key is its entity's look (looks.odin: its
 * blueprint's, its kind's, content/things.tri's #Look); a terrain kind's is
 * its own `look` (content/terrain/terrain.tri). One with none is keyed by its
 * blueprint's name. Light is light_at's 0, 1 or 2, as 0, 128 or 255.
 */

import "../../tessera"


/* A truth scene of `extent` (clipped to the world's tiles and levels), as the
 * world stands now: nil if nothing of the extent is in the world. `seq`
 * numbers it among the frames a watcher publishes. */
scene_truth :: proc(world: ^World, extent: tessera.Extent, seq: u64,
                    allocator := context.allocator) -> ^tessera.Scene {
	e := extent
	e.x0, e.y0 = max(e.x0, 0), max(e.y0, 0)
	e.w = min(extent.x0 + extent.w, world_tiles_wide(world)) - e.x0
	e.h = min(extent.y0 + extent.h, world_tiles_high(world)) - e.y0
	e.z0, e.z1 = max(e.z0, 0), min(e.z1, world_levels(world) - 1)
	e.focus = clamp(e.focus, e.z0, e.z1)
	now := world_time(world).ms
	s := tessera.scene_new({view = .Truth, seq = seq, time = now}, e, allocator)
	if s == nil do return nil

	terrain := world_terrain(world)
	for z := e.z0; z <= e.z1; z += 1 {
		for y := e.y0; y < e.y0 + e.h; y += 1 {
			for x := e.x0; x < e.x0 + e.w; x += 1 {
				c := tessera.cell_at(s, x, y, z)
				c.seen = now
				c.flags = {.In_Sight}
				if terrain != nil {
					info := terrain_kind_info(terrain, terrain_at(terrain, x, y, z))
					if info != nil {
						c.terrain = tessera.look(s, string(info.look))
						if !info.floored do c.flags += {.Open}
					}
				}
				c.fluid = u32(clamp(world_water_at_x(world, x, y, z), 0, i64(max(u32))))
				c.light = u8(min(light_at(world, on_tile(x, y, z), now) * 128, 255))
			}
		}
	}

	agent := world_kind_named(world, "Agent")
	entities := world_entities(world)
	for i: uint = 0; i < store_count(entities); i += 1 {
		id := store_entity_at_index(entities, i)
		info := world_info(world, id)
		tile: Location
		if info == nil || !know_ground_tile(world, id, &tile) do continue
		if tile.x < e.x0 || tile.y < e.y0 || tile.x >= e.x0 + e.w || tile.y >= e.y0 + e.h ||
		   tile.level < e.z0 || tile.level > e.z1 {
			continue
		}
		loc := world_location_of(world, id)
		is_agent := world_record(world, agent, id) != nil
		look := look_of_entity(world, id)
		tessera.mark_put(s, tessera.Mark {
			id     = u64(id),
			holder = u64(loc.place) if loc.form != .On_Tile else 0,
			seen   = now,
			x      = tile.x,
			y      = tile.y,
			z      = tile.level,
			look   = tessera.look(s, look if look != "" else string(info.blueprint)),
			stack  = 10 if is_agent else 0,
		})
	}
	return s
}

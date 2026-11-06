package lab

/*
 * Knowledge scenes: Tessera's player view (TESSERA.md, decision 2, slice 2),
 * one agent's world as it knows it, built only from its knowledge store and
 * what it perceives now. A backend draws them; nothing here draws.
 *
 * Cut points:
 * - cells: a tile it has seen has the terrain it believes there (its store's
 *   recall of a tile changed unseen, else the tile's); one it never saw is
 *   blank. A tile in sight now (knowledge_sees, from where it believes
 *   itself) is seen now, with its light and water as perceived. A
 *   remembered one is dark and dry (the store keeps no light or water, an
 *   open question in TESSERA.md) and seen when its store last saw any of
 *   its chunk (BG_CHUNK tiles a side): the store keeps no time a tile.
 * - marks: its referents, by referent id, where it believes them, looking as
 *   the kind it believes they are (looks.odin's look_of_kind); held or
 *   inside, they hang off their holder's mark. Itself is the Actor; one seen
 *   at its latest perception is In_Sight; one not where it was last seen is
 *   Gone, at that tile; one it saw end isn't there. It is drawn above
 *   anyone else, and they above things (a look of the family `agent`).
 * - nothing here reads a referent's `truth`, or any entity but the viewer's
 *   (for its sight).
 */

import "core:strings"

import "../../tessera"


/* A knowledge scene of `extent` (clipped to the world's tiles and levels):
 * the world as `agent` knows it now, from its store in `knowledge` (blank if
 * it has none yet). nil if nothing of the extent is in the world. `seq` numbers it among the frames a
 * watcher publishes. */
scene_knowledge :: proc(knowledge: ^Knowledge, agent: Entity_ID, extent: tessera.Extent, seq: u64,
                        allocator := context.allocator) -> ^tessera.Scene {
	world := knowledge.world
	e := extent
	e.x0, e.y0 = max(e.x0, 0), max(e.y0, 0)
	e.w = min(extent.x0 + extent.w, world_tiles_wide(world)) - e.x0
	e.h = min(extent.y0 + extent.h, world_tiles_high(world)) - e.y0
	e.z0, e.z1 = max(e.z0, 0), min(e.z1, world_levels(world) - 1)
	e.focus = clamp(e.focus, e.z0, e.z1)
	now := world_time(world).ms
	s := tessera.scene_new({view = .Knowledge, seq = seq, time = now, viewer = u64(agent)}, e, allocator)
	if s == nil do return nil

	store := knowledge_existing_store_of(knowledge, agent)   /* watching makes none */
	if store == nil do return s
	me := knowledge_store_referent(store, knowledge_store_self_referent(store))
	here := on_tile(me.x, me.y, me.level) if me != nil else Location{}
	terrain := world_terrain(world)
	for z := e.z0; z <= e.z1; z += 1 {
		for y := e.y0; y < e.y0 + e.h; y += 1 {
			for x := e.x0; x < e.x0 + e.w; x += 1 {
				if !knowledge_store_has_seen_x(store, x, y, z) do continue
				c := tessera.cell_at(s, x, y, z)
				if terrain != nil {
					info := terrain_kind_info(terrain, knowledge_store_believed_terrain_at_x(store, x, y, z))
					if info != nil {
						c.terrain = tessera.look(s, string(info.look))
						if !info.floored do c.flags += {.Open}
					}
				}
				tile := on_tile(x, y, z)
				if me != nil && knowledge_sees(knowledge, tile, here) {
					c.seen = now
					c.flags += {.In_Sight}
					c.fluid = u32(clamp(world_water_at_x(world, x, y, z), 0, i64(max(u32))))
					c.light = u8(min(knowledge_light_at(knowledge, tile) * 128, 255))
				} else {
					c.seen = knowledge_store_chunk_seen_at_x(store, x, y, z)
				}
			}
		}
	}

	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if r.ended || r.x < e.x0 || r.y < e.y0 || r.x >= e.x0 + e.w || r.y >= e.y0 + e.h ||
		   r.level < e.z0 || r.level > e.z1 {
			continue
		}
		flags: tessera.Mark_Flags
		if me != nil && r.id == me.id do flags += {.Actor}
		if !r.present do flags += {.Gone}
		if r.present && me != nil && r.seen == me.seen do flags += {.In_Sight}
		look := look_of_kind(world, string(r.kind)) if r.kind != nil else ""
		stack: i16 = 20 if .Actor in flags else 10 if strings.has_prefix(look, "agent") else 0
		tessera.mark_put(s, tessera.Mark {
			id     = u64(r.id),
			holder = u64(r.container) if r.form != .On_Tile else 0,
			seen   = r.seen,
			x      = r.x,
			y      = r.y,
			z      = r.level,
			look   = tessera.look(s, look if look != "" else "body"),
			stack  = stack,
			flags  = flags,
		})
	}
	return s
}

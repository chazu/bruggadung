package lab

// BGBodies — the body's fields that change with time alone (AGENCY.md §6,
// VILLAGE.md decision 2): hunger, and what going without does.
//
// Hunger is #Hungry's (content/hunger/body.tri): `satiety`, how full the
// stomach is, and `reserves`, what the body has to draw on, both as of
// `fedAt`, and computed when read. The stomach empties a point at a time over
// `emptiesIn`. While it isn't empty, reserves refill over `refillsIn`; once it
// is, they fall over `lastsFor`. Nothing is computed between: the domain's
// horizon is the next time anyone's satiety crosses into another band of
// ten (so interoception, and the needs it feels, are refreshed there), or
// its reserves run out. Eating nourishes through bodies_nourish: the food
// says how much, the body how it keeps it.
//
// Weakness (content/hunger/weakness.tri) is read from reserves by curves,
// where it acts: attention, the pace of work, perception, grip.
//
// Going without harms the body (AGENCY.md decision 17). With no reserves
// left, a point of injury every `harmsEvery`. Freezing (cold BG_FREEZING) or
// smothering (short of breath BG_SMOTHERING), a point of harm every period
// (cold slowly, air fast), at each multiple of it: fatigue up to BG_WEARY,
// then injury. World state, as the body is, not as it is felt; the domain's
// horizon is the next such point.
//
// (ported from the Objective-C lab's domains/BGBodies.m)

import tri "../../triangle/odin/triangle"


BG_HUNGER_BAND :: 10           // the precision hunger is felt with


BG_FREEZING :: 50              // cold that harms: 5 K below 310 K
BG_SMOTHERING :: 50            // shortness of breath that harms: 0.6% carbon dioxide
BG_FREEZE_PERIOD :: 60000      // ms a point of harm from freezing
BG_SMOTHER_PERIOD :: 10000     // ... from smothering
BG_WEARY :: 50                 // the fatigue freezing or smothering adds, before it injures


// --- hunger -----------------------------------------------------------------------

// Its #Hungry record, or nil: what has none doesn't get hungry.
hungry_of :: proc(world: ^World, e: Entity_ID) -> ^Hungry {
	return (^Hungry)(world_record(world, world_kind_named(world, "Hungry"), e))
}

// ms a point of a field lasts that runs its 100 points over `span`.
@(private = "file")
per_point :: proc(span: i64) -> i64 {
	return max(span / 100, 1)
}

// How full the stomach is at t, 0 to 100; 100 for what doesn't get hungry.
satiety :: proc(h: ^Hungry, t: i64) -> i64 {
	if h == nil do return 100
	s := h.satiety
	if t > h.fedAt do s -= (t - h.fedAt) / per_point(h.emptiesIn)
	return max(s, 0)
}

// When the stomach is empty, as of the last meal.
hunger_empties_at :: proc(h: ^Hungry) -> i64 {
	return h.fedAt + h.satiety * per_point(h.emptiesIn)
}

// What the body has in reserve at t, 0 to 100; 100 for what doesn't get
// hungry. Refilling until the stomach is empty, falling after.
reserves :: proc(h: ^Hungry, t: i64) -> i64 {
	if h == nil do return 100
	if t <= h.fedAt do return h.reserves
	empty := hunger_empties_at(h)
	r := min(h.reserves + (min(t, empty) - h.fedAt) / per_point(h.refillsIn), 100)
	if t > empty do r -= (t - empty) / per_point(h.lastsFor)
	return max(r, 0)
}

// When reserves run out, as of the last meal.
hunger_exhausted_at :: proc(h: ^Hungry) -> i64 {
	empty := hunger_empties_at(h)
	r := min(h.reserves + (empty - h.fedAt) / per_point(h.refillsIn), 100)
	return empty + r * per_point(h.lastsFor)
}

// Eating's way into the body: satiety `n` more (100 at most), as of t, and
// reserves as they stand then. Proposed into g; nothing, for what doesn't
// get hungry.
bodies_nourish :: proc(world: ^World, g: ^Proposal_Group, eater: Entity_ID, n: i64, t: i64) {
	h := hungry_of(world, eater)
	if h == nil do return
	proposal_group_set_of_to(g, "Hungry.satiety", whole(eater), min(satiety(h, t) + max(n, 0), 100))
	proposal_group_set_of_to(g, "Hungry.reserves", whole(eater), reserves(h, t))
	proposal_group_set_of_to(g, "Hungry.fedAt", whole(eater), t)
}


// --- weakness ---------------------------------------------------------------------

// What going without weakens (content/hunger/weakness.tri's `weakens`).
Weakens :: enum {
	Attention,
	Pace,
	Perception,
	Grip,
}

// A curve from reserves to the percent lost, copied out of content.
Weakness_Curve :: struct {
	n:      int,
	input:  [16]i64,
	output: [16]i64,
}

Weakness_Table :: [Weakens]Weakness_Curve

// The `weakness` family's curves. One that content doesn't give loses
// nothing.
weakness_load :: proc(content: ^tri.Content) -> Weakness_Table {
	table: Weakness_Table
	text:  [32]u8
	p:     ^tri.Node
	lo:    i64
	hi:    i64

	family := tri.family_index(content, "weakness")
	for i: uint = 0; family != nil && i < tri.index_count(family); i += 1 {
		node := node_of(content, cstring(tri.index_tag(family, i)))
		if node == nil || tri.at(content, node, "weakens") == nil do continue
		n := tri.print(content, tri.at(content, node, "weakens"), &text[0], size_of(text))
		which: Weakens
		switch string(text[:n]) {
		case "\"attention\"":  which = .Attention
		case "\"pace\"":       which = .Pace
		case "\"perception\"": which = .Perception
		case "\"grip\"":       which = .Grip
		case:                  continue
		}
		c := &table[which]
		c.n = 0
		for list := tri.at(content, node, "lost"); list != nil && c.n < len(c.input); list = tri.at(content, list, "rest") {
			p = tri.at(content, list, "first")
			if p == nil do break
			if tri.node_interval(tri.at(content, p, "input"), &lo, &hi) == 0 || lo != hi do continue
			x := lo
			if tri.node_interval(tri.at(content, p, "output"), &lo, &hi) == 0 || lo != hi do continue
			c.input[c.n], c.output[c.n] = x, lo
			c.n += 1
		}
	}
	return table
}

// How much of `which` a body has lost to going without at t, in percent:
// its curve at the reserves it has then (as curve_at reads a curve).
weakness :: proc(world: ^World, e: Entity_ID, which: Weakens, t: i64) -> i64 {
	h := hungry_of(world, e)
	c := &world.weakness[which]
	if h == nil || c.n == 0 do return 0
	x := reserves(h, t)
	if x <= c.input[0] do return c.output[0]
	for k in 1 ..< c.n {
		if x <= c.input[k] {
			return c.output[k - 1] + (c.output[k] - c.output[k - 1]) * (x - c.input[k - 1]) / (c.input[k] - c.input[k - 1])
		}
	}
	return c.output[c.n - 1]
}


// --- the body's heat and breath ----------------------------------------------------

// How cold its body is, 0 to 100: ten points a kelvin below 310 K.
coldness :: proc(world: ^World, agent: Entity_ID) -> i64 {
	body: ^Thermal_Body
	cold: i64

	body = (^Thermal_Body)(world_record(world, world_kind_named(world, "ThermalBody"), agent))
	if body == nil || body.heatCapacity == 0 {
		return 0
	}
	cold = (310000 - body.heat * 1000 / body.heatCapacity) / 100
	return 0 if cold < 0 else (100 if cold > 100 else cold)
}


// How short of breath the air over it makes something that breathes, 0 to
// 100: ten points for every 0.1% of carbon dioxide above 0.1%.
breathlessness :: proc(world: ^World, agent: Entity_ID) -> i64 {
	gas:    ^Gas_Store
	stuffy: i64

	if world_record(world, world_kind_named(world, "Respirator"), agent) == nil {
		return 0
	}
	gas = (^Gas_Store)(world_record(world, world_kind_named(world, "GasStore"), air_over(world, agent)))
	if gas == nil || gas.total == 0 {
		return 0
	}
	stuffy = (gas.dioxide * 1000000 / gas.total - 1000) / 100
	return 0 if stuffy < 0 else (100 if stuffy > 100 else stuffy)
}


// Its periods of harm, if going without: starving (no reserves left),
// freezing, smothering; 0 where it isn't.
@(private = "file")
deprivation :: proc(world: ^World, entity: Entity_ID, t: i64, periods: ^[3]i64) {
	h := hungry_of(world, entity)
	periods[0] = max(h.harmsEvery, 1) if h != nil && reserves(h, t) == 0 else 0
	periods[1] = BG_FREEZE_PERIOD if coldness(world, entity) >= BG_FREEZING else 0
	periods[2] = BG_SMOTHER_PERIOD if breathlessness(world, entity) >= BG_SMOTHERING else 0
}


Bodies :: struct {
	using object: Object,
	world:        ^World,
}


bodies_init_with_world :: proc(world: ^World) -> ^Bodies {
	self := object_new(Bodies, bodies_dealloc)
	self.world = retain(world)
	return self
}


bodies_dealloc :: proc(self: ^Bodies) {
	release(self.world)
}


bodies_name :: proc(self: ^Bodies) -> string {
	return "bodies"
}


@(private = "file")
bodies_agents :: proc(self: ^Bodies) -> ^Store {
	return world_store_for_kind(self.world, world_kind_named(self.world, "Agent"))
}


bodies_is_active :: proc(self: ^Bodies) -> bool {
	return store_count(bodies_agents(self)) > 0
}


// The next time an agent's satiety falls to a multiple of the band, or its
// reserves run out, or going without harms it.
bodies_horizon_at :: proc(self: ^Bodies, t: Time) -> Horizon {
	h:       Horizon
	periods: [3]i64

	h.safeStep  = TIME_NEVER
	h.nextEvent = TIME_NEVER
	agents := bodies_agents(self)
	for i: uint = 0; i < store_count(agents); i += 1 {
		entity := store_entity_at_index(agents, i)
		// the next point of harm, going without
		deprivation(self.world, entity, t.ms, &periods)
		for k in 0 ..< 3 {
			if periods[k] != 0 && (t.ms / periods[k] + 1) * periods[k] < h.nextEvent.ms {
				h.nextEvent = time_make((t.ms / periods[k] + 1) * periods[k])
			}
		}
		hungry := hungry_of(self.world, entity)
		if hungry == nil do continue
		// reserves running out: harm begins
		if out := hunger_exhausted_at(hungry); out > t.ms && out < h.nextEvent.ms do h.nextEvent = time_make(out)
		now := satiety(hungry, t.ms)
		if now <= 0 do continue
		band  := ((now - 1) / BG_HUNGER_BAND) * BG_HUNGER_BAND     // the next multiple below
		when_ := hungry.fedAt + (hungry.satiety - band) * per_point(hungry.emptiesIn)
		if when_ > t.ms && when_ < h.nextEvent.ms do h.nextEvent = time_make(when_)
	}
	return h
}


// Satiety and reserves are read, not stepped; but going without, a point of
// harm for each multiple of its period passed, as the body was at t0:
// starving, injury; freezing or smothering, fatigue up to BG_WEARY, then
// injury.
bodies_advance_from :: proc(self: ^Bodies, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	group:   ^Proposal_Group
	periods: [3]i64

	agents := bodies_agents(self)
	for i: uint = 0; i < store_count(agents); i += 1 {
		entity := store_entity_at_index(agents, i)
		agent  := (^Agent)(store_record_at_index(agents, i))
		deprivation(world, entity, t0.ms, &periods)
		starved, harm: i64
		if periods[0] != 0 do starved = t1.ms / periods[0] - t0.ms / periods[0]
		for k in 1 ..< 3 {
			if periods[k] != 0 do harm += t1.ms / periods[k] - t0.ms / periods[k]
		}
		if starved == 0 && harm == 0 do continue
		fatigue := agent.fatigue
		injury  := min(agent.injury + starved, 100)
		for ; harm > 0; harm -= 1 {
			if fatigue < BG_WEARY {
				fatigue += 1
			} else if injury < 100 {
				injury += 1
			}
		}
		if group == nil do group = proposal_group_group_with_phase(.Process, "bodies: going without")
		if fatigue != agent.fatigue do proposal_group_set_of_to(group, "Agent.fatigue", whole(entity), fatigue)
		if injury != agent.injury do proposal_group_set_of_to(group, "Agent.injury", whole(entity), injury)
	}
	if group != nil do committer_submit(committer, group)
}


bodies_check_in_all :: proc(self: ^Bodies) {
}


bodies_saved_state :: proc(self: ^Bodies) -> []string {
	return make([]string, 0, context.temp_allocator)
}


bodies_restore_saved_state :: proc(self: ^Bodies, lines: []string) {
}


bodies_as_domain :: proc(self: ^Bodies) -> Domain {
	return Domain{
		data                = self,
		name                = proc(data: rawptr) -> string {return bodies_name((^Bodies)(data))},
		check_in_all        = proc(data: rawptr) {bodies_check_in_all((^Bodies)(data))},
		saved_state         = proc(data: rawptr) -> []string {return bodies_saved_state((^Bodies)(data))},
		restore_saved_state = proc(data: rawptr, lines: []string) {bodies_restore_saved_state((^Bodies)(data), lines)},
		is_active           = proc(data: rawptr) -> bool {return bodies_is_active((^Bodies)(data))},
		horizon_at          = proc(data: rawptr, t: Time) -> Horizon {return bodies_horizon_at((^Bodies)(data), t)},
		advance_from        = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
			bodies_advance_from((^Bodies)(data), t0, t1, world, committer)
		},
	}
}

package lab

// BGBodies — body stocks (AGENCY.md §6): how fed an agent is. The stock is
// component state, `Agent.fed` as of `Agent.fedAt`, and falls a point every
// three minutes, computed when read; eating sets it again. Nothing is computed
// between: the domain's horizon is the next time anyone's hunger crosses
// into another band of ten, so the agent's interoception, and the needs it
// feels, are refreshed there.
//
// Going without harms the body (AGENCY.md decision 17): an agent starving
// (hunger BG_STARVING or more), freezing (cold BG_FREEZING), or smothering
// (short of breath BG_SMOTHERING) takes a point of harm every period of the
// stock's (hunger slowly, cold faster, air fastest), at each multiple of it:
// fatigue up to BG_WEARY, then injury. World state, as the body is, not as
// it is felt; the domain's horizon is the next such point.
//
// (ported from the Objective-C lab's domains/BGBodies.m)


BG_HUNGER_PERIOD :: 180000     // ms a point of `fed` lasts: empty in five hours
BG_HUNGER_BAND :: 10           // the precision hunger is felt with


BG_STARVING :: 90              // hunger that harms: fed 10 or less
BG_FREEZING :: 50              // cold that harms: 5 K below 310 K
BG_SMOTHERING :: 50            // shortness of breath that harms: 0.6% carbon dioxide
BG_STARVE_PERIOD :: 600000     // ms a point of harm from starving
BG_FREEZE_PERIOD :: 60000      // ... from freezing
BG_SMOTHER_PERIOD :: 10000     // ... from smothering
BG_WEARY :: 50                 // the fatigue going without adds, before it injures


// How fed the agent is at t, 0 to 100.
satiety :: proc(agent: ^Agent, t: i64) -> i64 {
	fed: i64

	fed = agent.fed
	if t > agent.fedAt {
		fed -= (t - agent.fedAt) / BG_HUNGER_PERIOD
	}
	return 0 if fed < 0 else fed
}


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


// Its stocks' periods of harm, if going without: 0 where it isn't.
@(private = "file")
deprivation :: proc(world: ^World, entity: Entity_ID, agent: ^Agent, t: i64, periods: ^[3]i64) {
	periods[0] = BG_STARVE_PERIOD if 100 - satiety(agent, t) >= BG_STARVING else 0
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


// The next time an agent's stock falls to a multiple of the band, for each
// agent not yet starved.
bodies_horizon_at :: proc(self: ^Bodies, t: Time) -> Horizon {
	agent:   ^Agent
	agents:  ^Store
	h:       Horizon
	i:       uint
	now:     i64
	band:    i64
	when_:   i64
	periods: [3]i64
	k:       int

	h.safeStep  = TIME_NEVER
	h.nextEvent = TIME_NEVER
	agents      = bodies_agents(self)
	for i = 0; i < store_count(agents); i += 1 {
		agent = (^Agent)(store_record_at_index(agents, i))
		// the next point of harm, going without
		deprivation(self.world, store_entity_at_index(agents, i), agent, t.ms, &periods)
		for k = 0; k < 3; k += 1 {
			if periods[k] != 0 && (t.ms / periods[k] + 1) * periods[k] < h.nextEvent.ms {
				h.nextEvent = time_make((t.ms / periods[k] + 1) * periods[k])
			}
		}
		now = satiety(agent, t.ms)
		if now <= 0 {
			continue
		}
		band  = ((now - 1) / BG_HUNGER_BAND) * BG_HUNGER_BAND     // the next multiple below
		when_ = agent.fedAt + (agent.fed - band) * BG_HUNGER_PERIOD
		if when_ > t.ms && when_ < h.nextEvent.ms {
			h.nextEvent = time_make(when_)
		}
	}
	return h
}


// The stock is read, not stepped; but going without, a point of harm for
// each multiple of its period passed, as the body was at t0: fatigue up to
// BG_WEARY, then injury.
bodies_advance_from :: proc(self: ^Bodies, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	agent:   ^Agent
	group:   ^Proposal_Group
	agents:  ^Store
	i:       uint
	periods: [3]i64
	harm:    i64
	fatigue: i64
	injury:  i64
	k:       int

	agents = bodies_agents(self)
	group  = nil
	for i = 0; i < store_count(agents); i += 1 {
		agent = (^Agent)(store_record_at_index(agents, i))
		deprivation(world, store_entity_at_index(agents, i), agent, t0.ms, &periods)
		harm = 0
		for k = 0; k < 3; k += 1 {
			if periods[k] != 0 {
				harm += t1.ms / periods[k] - t0.ms / periods[k]
			}
		}
		if harm == 0 {
			continue
		}
		fatigue = agent.fatigue
		injury  = agent.injury
		for ; harm > 0; harm -= 1 {
			if fatigue < BG_WEARY {
				fatigue += 1
			} else if injury < 100 {
				injury += 1
			}
		}
		if group == nil {
			group = proposal_group_group_with_phase(.Process, "bodies: going without")
		}
		if fatigue != agent.fatigue {
			proposal_group_set_of_to(group, "Agent.fatigue", whole(store_entity_at_index(agents, i)), fatigue)
		}
		if injury != agent.injury {
			proposal_group_set_of_to(group, "Agent.injury", whole(store_entity_at_index(agents, i)), injury)
		}
	}
	if group != nil {
		committer_submit(committer, group)
	}
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

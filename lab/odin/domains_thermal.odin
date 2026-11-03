package lab

// BGThermal — the heat of solids (DOMAIN_SIMULATION.md Scenario 1): a
// stove's iron, a room's shell (content/heat/heat.tri, ThermalBody), in whole
// joules. Its records mirror its values after each step.
//
// Coupled (BGCoupledDomain): it publishes its bodies' temperatures at step
// start, and takes heat contributions for its bodies, which it applies over
// its next step: the atmosphere's exchange between the air and what it
// touches, and a fire's share for its stove. A shell exchanges with the
// outdoors, at 275 K, itself. It sleeps when nothing is in transit to it and
// every body with an outside is within half a kelvin of it: so it wakes when
// its contributions arrive.
//
// (domains/BGThermal.h and .m)

import "core:fmt"
import "core:mem"


Thermal_State :: struct {
	entity:     Entity_ID,
	heat:       i64,         // J
	capacity:   i64,         // J/K
	toOutdoors: i64,         // W/K
	carry:      i64,         // the outdoors' exchange, J·10⁻⁶
	pending:    i64,         // contributions in transit to it, J
}


Thermal :: struct {
	using object: Object,
	world:        ^World,
	bodies:       [^]Thermal_State,     // in entity order, as many as the world has
	nbodies:      i32,
	bodycap:      i32,
	ledgered:     bool,
	initial:      i64,                  // J, in the bodies
	inflow:       i64,                  // from the outdoors
	received:     i64,                  // contributions applied
	steps:        uint,
}


@(private = "file")
BG_OUT_TEMPERATURE :: 275000      // mK


thermal_init_with_world :: proc(world: ^World) -> ^Thermal {
	self := object_new(Thermal, thermal_dealloc)
	self.world = retain(world)
	return self
}


thermal_dealloc :: proc(self: ^Thermal) {
	free(self.bodies)
	release(self.world)
}


thermal_name :: proc(self: ^Thermal) -> string {
	return "thermal"
}


thermal_steps :: proc(self: ^Thermal) -> uint {
	return self.steps
}


// Contributions applied, and held in transit, J.
thermal_received :: proc(self: ^Thermal) -> i64 {
	return self.received
}


thermal_pending :: proc(self: ^Thermal) -> i64 {
	sum: i64
	i:   i32

	sum = 0
	for i = 0; i < self.nbodies; i += 1 {
		sum += self.bodies[i].pending
	}
	return sum
}


// --- reading the world ------------------------------------------------------------

@(private = "file")
thermal_body_of :: proc(self: ^Thermal, entity: Entity_ID) -> i32 {
	lo:  i32
	hi:  i32
	mid: i32

	lo = 0
	hi = self.nbodies
	for lo < hi {
		mid = (lo + hi) / 2
		if self.bodies[mid].entity < entity {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo < self.nbodies && self.bodies[lo].entity == entity {
		return lo
	}
	if self.nbodies == self.bodycap {
		old := self.bodycap
		self.bodycap = self.bodycap * 2 if self.bodycap != 0 else 16
		q, _ := mem.resize(rawptr(self.bodies), int(old) * size_of(Thermal_State), int(self.bodycap) * size_of(Thermal_State))
		self.bodies = ([^]Thermal_State)(q)
	}
	mem.copy(&self.bodies[lo + 1], &self.bodies[lo], int(self.nbodies - lo) * size_of(Thermal_State))
	self.bodies[lo] = {}
	self.bodies[lo].entity = entity
	self.nbodies += 1
	return lo
}


// The bodies' values from their records, which mirror ours.
@(private = "file")
thermal_load :: proc(self: ^Thermal) {
	body:  ^Thermal_Body
	store: ^Store
	i:     uint
	k:     i32

	store = world_store_for_kind(self.world, world_kind_named(self.world, "ThermalBody"))
	for i = 0; i < store_count(store); i += 1 {
		body = (^Thermal_Body)(store_record_at_index(store, i))
		// a part inside an assembly joins no domain (COMPONENTS.md §7): its
		// heat is the assembly's
		if world_location_of(self.world, store_entity_at_index(store, i)).form == .Part_Of {
			continue
		}
		k = thermal_body_of(self, store_entity_at_index(store, i))
		if k < 0 {
			continue
		}
		self.bodies[k].heat       = body.heat
		self.bodies[k].capacity   = body.heatCapacity
		self.bodies[k].toOutdoors = body.toOutdoors
	}
}


@(private = "file")
temperature :: proc(b: ^Thermal_State) -> i64 {
	return b.heat * 1000 / b.capacity
}


// Whether a body takes part in it: not while it is part of an assembly.
thermal_participates :: proc(self: ^Thermal, body: Entity_ID) -> bool {
	i: i32

	thermal_load(self)
	for i = 0; i < self.nbodies; i += 1 {
		if self.bodies[i].entity == body && world_location_of(self.world, body).form != .Part_Of {
			return true
		}
	}
	return false
}


// A body's temperature now, in millikelvin.
thermal_temperature_of :: proc(self: ^Thermal, entity: Entity_ID) -> i64 {
	i: i32

	thermal_load(self)
	for i = 0; i < self.nbodies; i += 1 {
		if self.bodies[i].entity == entity {
			return temperature(&self.bodies[i])
		}
	}
	return 0
}


// --- the domain -----------------------------------------------------------------

thermal_is_active :: proc(self: ^Thermal) -> bool {
	i: i32

	thermal_load(self)
	for i = 0; i < self.nbodies; i += 1 {
		if self.bodies[i].pending != 0 ||
		   (self.bodies[i].toOutdoors != 0 && abs(temperature(&self.bodies[i]) - BG_OUT_TEMPERATURE) >= 500) {
			return true
		}
	}
	return false
}


// The outdoors' exchange is explicit: a step moves no more than an eighth
// of the way to 275 K. The exchange with the air is the atmosphere's to
// bound. Nothing here is a discrete event.
thermal_horizon_at :: proc(self: ^Thermal, t: Time) -> Horizon {
	h:    Horizon
	step: i64
	i:    i32

	thermal_load(self)
	h.nextEvent = TIME_NEVER
	h.safeStep  = TIME_NEVER
	for i = 0; i < self.nbodies; i += 1 {
		if self.bodies[i].toOutdoors != 0 {
			step = self.bodies[i].capacity * 1000 / (8 * self.bodies[i].toOutdoors)
			if step < h.safeStep.ms {
				h.safeStep = time_make(step)
			}
		}
	}
	return h
}


thermal_publish_into :: proc(self: ^Thermal, snapshot: ^Snapshot) {
	i: i32

	thermal_load(self)
	for i = 0; i < self.nbodies; i += 1 {
		snapshot_set_quantity(snapshot, .Temperature, self.bodies[i].entity, temperature(&self.bodies[i]))
	}
}


thermal_takes_contribution :: proc(self: ^Thermal, contribution: Contribution) -> bool {
	return contribution.quantity == .Heat &&
	       world_record(self.world, world_kind_named(self.world, "ThermalBody"), contribution.target) != nil
}


thermal_receive_contribution :: proc(self: ^Thermal, contribution: Contribution) {
	k: i32

	thermal_load(self)
	k = thermal_body_of(self, contribution.target)
	if k >= 0 {
		self.bodies[k].pending += contribution.amount
	}
}


// -advanceFrom:to:world:committer:
thermal_advance_from_to_world_committer :: proc(self: ^Thermal, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	thermal_advance_from_to_world_committer_snapshot(self, t0, t1, world, committer, nil, nil)
}


// -advanceFrom:to:world:committer:snapshot:outbox:
thermal_advance_from_to_world_committer_snapshot :: proc(self: ^Thermal, t0: Time, t1: Time, world: ^World, committer: ^Committer,
                                                         snapshot: ^Snapshot, outbox: ^Contributions) {
	b:  ^Thermal_State
	dt: i64
	q:  i64
	i:  i32

	dt = t1.ms - t0.ms
	thermal_load(self)
	if dt <= 0 {
		return
	}
	if !self.ledgered {
		self.initial = 0
		for i = 0; i < self.nbodies; i += 1 {
			self.initial += self.bodies[i].heat
		}
		self.ledgered = true
	}
	for i = 0; i < self.nbodies; i += 1 {
		b = &self.bodies[i]
		// the outdoors, from the step-start temperature
		q = 0
		if b.toOutdoors != 0 {
			b.carry += b.toOutdoors * (BG_OUT_TEMPERATURE - temperature(b)) * dt
			q        = b.carry / 1000000
			b.carry %= 1000000
		}
		// what was in transit to it
		b.heat        += q + b.pending
		self.inflow   += q
		self.received += b.pending
		b.pending      = 0
		world_set_field_of_value(self.world, "ThermalBody.heat", b.entity, b.heat)
	}
	self.steps += 1
}


// Heat in the bodies is what there was, plus what came from outdoors, plus
// the contributions applied, exactly.
thermal_balanced :: proc(self: ^Thermal) -> bool {
	sum: i64
	i:   i32

	sum = 0
	for i = 0; i < self.nbodies; i += 1 {
		sum += self.bodies[i].heat
	}
	return !self.ledgered || sum == self.initial + self.inflow + self.received
}


// --- saves -----------------------------------------------------------------------

thermal_check_in_all :: proc(self: ^Thermal) {
}


thermal_saved_state :: proc(self: ^Thermal) -> []string {
	lines: [dynamic]string
	i:     i32

	lines = make([dynamic]string, context.temp_allocator)
	append(&lines, fmt.tprintf("thermal %d %d %d %d %d", 1 if self.ledgered else 0,
	                           u64(self.steps), self.initial, self.inflow, self.received))
	for i = 0; i < self.nbodies; i += 1 {
		append(&lines, fmt.tprintf("body %d %d %d", u64(self.bodies[i].entity), self.bodies[i].carry, self.bodies[i].pending))
	}
	return lines[:]
}


thermal_restore_saved_state :: proc(self: ^Thermal, lines: []string) {
	e:     i64
	steps: i64
	v:     [3]i64
	i:     int
	text:  string
	flag:  i64
	k:     i32

	self.nbodies = 0
	for i = 0; i < len(lines); i += 1 {
		text = lines[i]
		if sscanf(text, "thermal %d %llu %lld %lld %lld", &flag, &steps, &v[0], &v[1], &v[2]) == 5 {
			self.ledgered = i32(flag) != 0
			self.steps    = uint(u64(steps))
			self.initial  = v[0]
			self.inflow   = v[1]
			self.received = v[2]
		} else if sscanf(text, "body %llu %lld %lld", &e, &v[0], &v[1]) == 3 {
			k = thermal_body_of(self, Entity_ID(u64(e)))
			if k < 0 {
				continue
			}
			self.bodies[k].carry   = v[0]
			self.bodies[k].pending = v[1]
		}
	}
	thermal_load(self)
}


// sscanf for the formats the saves use: literal text, white space (any run
// of it, none too), and integer conversions (%d, %lld, %llu: an optional
// sign, then digits, an unsigned one wrapping as strtoull does), each stored
// as 64 bits for the caller to narrow as C stored it. The number of
// conversions made before the first failure.
@(private = "file")
sscanf :: proc(text: string, format: string, out: ..^i64) -> int {
	is_space :: proc(c: u8) -> bool {
		return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f'
	}
	i, f, n := 0, 0, 0
	for f < len(format) {
		c := format[f]
		if is_space(c) {
			for f < len(format) && is_space(format[f]) do f += 1
			for i < len(text) && is_space(text[i]) do i += 1
			continue
		}
		if c == '%' {
			f += 1
			for f < len(format) && (format[f] == 'l' || format[f] == 'h') do f += 1
			f += 1         // d or u
			for i < len(text) && is_space(text[i]) do i += 1
			j := i
			neg := false
			if j < len(text) && (text[j] == '+' || text[j] == '-') {
				neg = text[j] == '-'
				j += 1
			}
			if j >= len(text) || text[j] < '0' || text[j] > '9' do return n
			v: u64 = 0
			for j < len(text) && text[j] >= '0' && text[j] <= '9' {
				v = v * 10 + u64(text[j] - '0')
				j += 1
			}
			i = j
			out[n]^ = i64(-v if neg else v)
			n += 1
			continue
		}
		if i >= len(text) || text[i] != c do return n
		i += 1
		f += 1
	}
	return n
}


thermal_as_domain :: proc(self: ^Thermal) -> Domain {
	return Domain{
		data                 = self,
		name                 = proc(data: rawptr) -> string {return thermal_name((^Thermal)(data))},
		check_in_all         = proc(data: rawptr) {thermal_check_in_all((^Thermal)(data))},
		saved_state          = proc(data: rawptr) -> []string {return thermal_saved_state((^Thermal)(data))},
		restore_saved_state  = proc(data: rawptr, lines: []string) {thermal_restore_saved_state((^Thermal)(data), lines)},
		is_active            = proc(data: rawptr) -> bool {return thermal_is_active((^Thermal)(data))},
		horizon_at           = proc(data: rawptr, t: Time) -> Horizon {return thermal_horizon_at((^Thermal)(data), t)},
		advance_from         = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
			thermal_advance_from_to_world_committer((^Thermal)(data), t0, t1, world, committer)
		},
		publish_into         = proc(data: rawptr, snapshot: ^Snapshot) {thermal_publish_into((^Thermal)(data), snapshot)},
		takes_contribution   = proc(data: rawptr, contribution: Contribution) -> bool {
			return thermal_takes_contribution((^Thermal)(data), contribution)
		},
		receive_contribution = proc(data: rawptr, contribution: Contribution) {
			thermal_receive_contribution((^Thermal)(data), contribution)
		},
		advance_coupled      = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer,
		                            snapshot: ^Snapshot, outbox: ^Contributions) {
			thermal_advance_from_to_world_committer_snapshot((^Thermal)(data), t0, t1, world, committer, snapshot, outbox)
		},
	}
}

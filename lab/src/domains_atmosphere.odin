package lab

// BGAtmosphere — the air (DOMAIN_SIMULATION.md Scenario 1, "The unattended
// stove"). It owns, while anything moves, the gas of each region of air
// (content/air/air.tri: oxygen and carbon dioxide in whole millimoles, the heat
// the gas carries in whole joules) and the fuel of a lit stove; their
// records mirror its values after each step, and it checks them in when it
// sleeps.
//
// Per step, in whole quanta, with carries for what is fractional:
//
//   - each link mixes a region with the region it opens to, or with the
//     outdoors, a reservoir at 275 K of fixed composition: a doorway at its
//     room's side (TERRAIN.md step 3), passing the doorway's draught, or
//     its door's width while ajar and nothing while shut; the region's leak
//     to the outdoors (its gap); or, its room opened to the outdoors, its
//     airing out, a hundredth of it a second. Links are found from the
//     terrain each time the domain reads the world, and carry gas and heat
//     in proportion, measured from the smaller side;
//   - a lit stove burns up to its rate (mg a second) of wood; each gram
//     consumes 33 mmol of oxygen, produces 33 of carbon dioxide and 15 kJ of
//     heat. Damper open, the firebox draws from the outdoors and vents up
//     the flue, and a tenth of the heat warms the room; damper closed, it
//     draws from the room and vents into it, smouldering as the oxygen
//     falls below 21% and going out by 10%.
//
// A respirator (content/air/air.tri) breathes the air over it: oxygen at its
// rate, at rest or at work, for four fifths as much carbon dioxide, and the
// heat to its body, as a contribution.
//
// Coupled to the thermal domain (BGCoupledDomain): a stove's iron takes
// three tenths of its fire's heat, and every solid with a surface to the air
// (`toAir`, W/K) exchanges heat with it. The atmosphere computes that
// exchange, from the solids' temperatures in the step-start snapshot, takes
// it from the gas, and sends it as contributions; below half a kelvin it
// rests. The exchange lags a step, so it bounds the step: an eighth of the
// smaller side's capacity over the conductance, so a step moves no more than
// an eighth of the way to equal.
//
// Regions sleep and wake one by one (§5). A link rests while what it
// carries is within the settle tolerances (a thousandth of the region in
// oxygen, 100 mmol of carbon dioxide, half a kelvin); a region is awake while
// a link to it is moving, or a fire, a breather, a solid's surface, a
// contribution, or a crossed watch is in it. A door opening or shutting
// wakes the two regions it joins. A moving link is explicit, and bounds the
// step: no more than an eighth of the smaller side's air through it. The domain sleeps when every region
// does.
//
// The firebox is quasi-steady: it holds nothing. Every quantity balances
// exactly: the region's gas plus what combustion consumed less what it
// produced, less what came in from outdoors, plus what it sent the solids,
// less what it received, is what there was (the ledger). Fuel run out is a predicted event: the stove goes out then, by
// proposal. A rest's watch on a region's air is another: its carbon dioxide
// rising past a level, at the rate the sources give now (never late), or its
// temperature leaving a band, predicted at twice the rate the heat flows now
// give and again from closer in. The domain reports it at the boundary it
// crosses, within a second. A region settled near the
// outdoors, with no fire, lets the domain sleep: an infinite horizon.
//
// (ported from the Objective-C lab's domains/BGAtmosphere.m)

import "core:fmt"
import "core:mem"
import tri "../../triangle/odin/triangle"


Air_Region :: struct {
	entity:    Entity_ID,
	oxygen:    i64,          // mmol
	dioxide:   i64,
	heat:      i64,          // J
	total:     i64,          // mmol
	carryBurn: [3]i64,       // combustion into the region, in mmol·mg, J·mg
	pending:   i64,          // heat in transit to it, J
	steps:     uint,         // steps it was awake for
}


// A way air moves between a region and what it opens to: kept by the two
// sides and the doorway, from read to read, for its carries.
Air_Link :: struct {
	from:     Entity_ID,     // the smaller side, whose air it is measured by
	to:       Entity_ID,     // the other, or NO_ENTITY: the outdoors
	at:       Location,      // the doorway; none: a leak, or airing out
	a:        i32,           // their regions, as read; b -1: the outdoors
	b:        i32,
	door:     Entity_ID,     // the door in it, or none
	flow:     i64,           // mmol of air a second, each way
	doorSeen: i32,           // its door, ajar or not, at the last step; -1 not yet seen
	carryAir: i64,           // mmol·ms
	carryIn:  [3]i64,        // what comes in from the other side, numerators
	carryOut: [3]i64,        // what goes out, numerators over the total
	found:    bool,
}


Stove_State :: struct {
	entity:     Entity_ID,
	region:     i32,         // the region it stands in, or -1
	fuel:       i64,         // mg
	carry:      i64,         // mg·ms
	carryShare: i64,         // its iron's share of the heat, J·10⁻¹
	out:        bool,        // its fire went out this step
}


// A solid's surface to a region's air.
Air_Surface :: struct {
	entity:      Entity_ID,
	region:      i32,
	conductance: i64,        // W/K
	carry:       i64,        // J·10⁻⁶
}


// What breathes, over a region's air.
Breather :: struct {
	entity:       Entity_ID,
	region:       i32,
	carry:        i64,       // oxygen, mmol·10⁻⁶
	carryDioxide: i64,       // fifths of a mmol
}


// What balances: per quantity, the totals a ledger adds up.
Air_Ledger :: struct {
	initial:   [3]i64,       // oxygen, dioxide, heat, in the regions
	inflow:    [3]i64,       // net in from outdoors
	produced:  [3]i64,       // by combustion, into the regions
	consumed:  [3]i64,       // by combustion, from the regions
	fuel:      i64,          // initial, mg
	burned:    i64,          // mg
	exchanged: i64,          // heat from the gas to the solids, J
	toSolids:  i64,          // combustion's heat sent to the solids
	received:  i64,          // heat contributions applied to the gas
}


Atmosphere :: struct {
	using object: Object,
	world:        ^World,
	active:       bool,
	ledgered:     bool,
	// each kept in entity order, as many as the world has
	regions:      [^]Air_Region,
	nregions:     i32,
	regioncap:    i32,
	links:        [^]Air_Link,
	nlinks:       i32,
	linkcap:      i32,
	stoves:       [^]Stove_State,
	nstoves:      i32,
	stovecap:     i32,
	surfaces:     [^]Air_Surface,
	nsurfaces:    i32,
	surfacecap:   i32,
	breathers:    [^]Breather,
	nbreathers:   i32,
	breathercap:  i32,
	ledger:       Air_Ledger,
	rise:         i64,           // the last step's carbon dioxide rise, per second, in the first region
	steps:        uint,
	fired:        [^]Entity_ID,  // watches reported, while they still watch
	nfired:       i32,
	firedcap:     i32,
}


// the outdoors, a reservoir: per mille oxygen, per ten thousand carbon
// dioxide, and the heat a millimole of its air carries at 275 K, in mJ
@(private = "file") BG_OUT_OXYGEN :: 210
@(private = "file") BG_OUT_DIOXIDE :: 4
@(private = "file") BG_OUT_HEAT :: 7975
@(private = "file") BG_GAS_CAPACITY :: 29          // mJ per mmol per kelvin

// combustion, per gram of wood
@(private = "file") BG_BURN_OXYGEN :: 33           // mmol consumed
@(private = "file") BG_BURN_DIOXIDE :: 33          // mmol produced
@(private = "file") BG_BURN_HEAT :: 15             // J per mg
@(private = "file") BG_BURN_SHARE :: 3             // tenths of it to the stove's iron

// breathing, per mmol of oxygen
@(private = "file") BG_BREATH_DIOXIDE :: 4         // fifths of a mmol produced
@(private = "file") BG_BREATH_HEAT :: 448          // J, to the body


// C's realloc of an array of T, from old_cap elements to new_cap.
@(private = "file")
grow :: proc(p: [^]$T, old_cap, new_cap: i32) -> [^]T {
	q, _ := mem.resize(rawptr(p), int(old_cap) * size_of(T), int(new_cap) * size_of(T))
	return ([^]T)(q)
}


atmosphere_init_with_world :: proc(world: ^World) -> ^Atmosphere {
	self := object_new(Atmosphere, atmosphere_dealloc)
	self.world = retain(world)
	return self
}


atmosphere_dealloc :: proc(self: ^Atmosphere) {
	free(self.regions)
	free(self.links)
	free(self.stoves)
	free(self.surfaces)
	free(self.breathers)
	free(self.fired)
	release(self.world)
}


atmosphere_name :: proc(self: ^Atmosphere) -> string {
	return "atmosphere"
}


// Steps it has taken.
atmosphere_steps :: proc(self: ^Atmosphere) -> uint {
	return self.steps
}


// Heat sent to the solids, J: exchanged and combustion's share.
atmosphere_sent :: proc(self: ^Atmosphere) -> i64 {
	return self.ledger.exchanged + self.ledger.toSolids
}


// --- reading the world ------------------------------------------------------------

// In a growing array of records, each beginning with its entity and kept
// in entity order: the index of an entity's record, found by halving, or,
// if `make`, made zeroed in its place (moving those after it up one), else
// -1. Indices held into the array are good until a record is made.
@(private = "file")
entry_of :: proc(array: ^[^]$T, n: ^i32, cap_: ^i32, entity: Entity_ID, make_: bool) -> i32 {
	a:   [^]T
	lo:  i32
	hi:  i32
	mid: i32

	a  = array^
	lo = 0
	hi = n^
	for lo < hi {
		mid = (lo + hi) / 2
		if a[mid].entity < entity {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo < n^ && a[lo].entity == entity {
		return lo
	}
	if !make_ {
		return -1
	}
	if n^ == cap_^ {
		old := cap_^
		cap_^  = cap_^ * 2 if cap_^ != 0 else 8
		a      = grow(a, old, cap_^)
		array^ = a
	}
	mem.copy(&a[lo + 1], &a[lo], int(n^ - lo) * size_of(T))
	a[lo]        = {}
	a[lo].entity = entity
	n^ += 1
	return lo
}


@(private = "file")
atmosphere_region_of :: proc(self: ^Atmosphere, entity: Entity_ID) -> i32 {
	k: i32

	k = entry_of(&self.regions, &self.nregions, &self.regioncap, entity, false)
	if k >= 0 {
		return k
	}
	if entity == 0 || world_record(self.world, world_kind_named(self.world, "GasStore"), entity) == nil {
		return -1
	}
	return entry_of(&self.regions, &self.nregions, &self.regioncap, entity, true)
}


@(private = "file")
atmosphere_stove_of :: proc(self: ^Atmosphere, entity: Entity_ID) -> i32 {
	k: i32

	k = entry_of(&self.stoves, &self.nstoves, &self.stovecap, entity, false)
	if k >= 0 {
		return k
	}
	k = entry_of(&self.stoves, &self.nstoves, &self.stovecap, entity, true)
	self.stoves[k].fuel = -1
	return k
}


@(private = "file")
atmosphere_surface_of :: proc(self: ^Atmosphere, entity: Entity_ID) -> i32 {
	return entry_of(&self.surfaces, &self.nsurfaces, &self.surfacecap, entity, true)
}


@(private = "file")
atmosphere_breather_of :: proc(self: ^Atmosphere, entity: Entity_ID) -> i32 {
	return entry_of(&self.breathers, &self.nbreathers, &self.breathercap, entity, true)
}


// A watch reported: kept until its activity stops watching.
@(private = "file")
atmosphere_fired :: proc(self: ^Atmosphere, activity: Entity_ID) {
	if self.nfired == self.firedcap {
		old := self.firedcap
		self.firedcap = self.firedcap * 2 if self.firedcap != 0 else 8
		self.fired    = grow(self.fired, old, self.firedcap)
	}
	self.fired[self.nfired] = activity
	self.nfired += 1
}


// The regions' and stoves' values from their records, which mirror ours;
// a stove not burning takes its fuel from its record. A solid's surface is
// to the air over it, or, with no place, the air it bounds.
// A link found reading the world, measured from its smaller side: its
// carries are kept if it was there before; found again from the other side,
// it is the same link.
@(private = "file")
atmosphere_link :: proc(self: ^Atmosphere, a: i32, b: i32, at: Location, door: Entity_ID, flow: i64) {
	l:    ^Air_Link
	from: Entity_ID
	to:   Entity_ID
	i:    i32
	a, b := a, b

	if b >= 0 && (self.regions[b].total < self.regions[a].total ||
	              (self.regions[b].total == self.regions[a].total && self.regions[b].entity < self.regions[a].entity)) {
		i = a
		a = b
		b = i
	}
	from = self.regions[a].entity
	to   = self.regions[b].entity if b >= 0 else NO_ENTITY
	for i = 0; i < self.nlinks; i += 1 {
		l = &self.links[i]
		if l.from == from && l.to == to && l.at.form == at.form &&
		   (at.form == .None || (l.at.x == at.x && l.at.y == at.y && l.at.level == at.level)) {
			break
		}
	}
	if i == self.nlinks {
		if self.nlinks == self.linkcap {
			old := self.linkcap
			self.linkcap = self.linkcap * 2 if self.linkcap != 0 else 16
			self.links   = grow(self.links, old, self.linkcap)
		}
		l = &self.links[self.nlinks]
		self.nlinks += 1
		l^          = {}
		l.from      = from
		l.to        = to
		l.at        = at
		l.doorSeen  = -1
	} else if l.found {
		return
	}
	l.a     = a
	l.b     = b
	l.door  = door
	l.flow  = flow
	l.found = true
}


// The links, from the terrain and the regions as they are now.
@(private = "file")
atmosphere_load_links :: proc(self: ^Atmosphere) {
	air:      ^Gas_Store
	door:     ^Door
	openings: [^]Air_Opening
	n:        uint
	i:        uint
	k:        i32
	j:        i32

	for j = 0; j < self.nlinks; j += 1 {
		self.links[j].found = false
	}
	for k = 0; k < self.nregions; k += 1 {
		air = (^Gas_Store)(world_record(self.world, world_kind_named(self.world, "GasStore"), self.regions[k].entity))
		if air == nil {
			continue
		}
		if world_room_of_air(self.world, self.regions[k].entity) == 0 {
			// its room opened to the outdoors: it airs out
			atmosphere_link(self, k, -1, location_make_none(), NO_ENTITY, air.gap if air.gap > air.total / 100 else air.total / 100)
			continue
		}
		if air.gap != 0 {
			atmosphere_link(self, k, -1, location_make_none(), NO_ENTITY, air.gap)
		}
		n        = world_air_openings_of(self.world, self.regions[k].entity, nil, 0)
		openings = make([^]Air_Opening, n if n != 0 else 1)
		world_air_openings_of(self.world, self.regions[k].entity, openings, n)
		for i = 0; i < n; i += 1 {
			j = atmosphere_region_of(self, openings[i].beyond) if openings[i].beyond != 0 else -1
			if openings[i].beyond != 0 && j < 0 {
				continue
			}
			atmosphere_link(self, k, j, openings[i].at, openings[i].door, openings[i].flow)
		}
		free(openings)
	}
	n = 0
	for j = 0; j < self.nlinks; j += 1 {
		if self.links[j].found {
			self.links[n] = self.links[j]
			n += 1
		}
	}
	self.nlinks = i32(n)
	for j = 0; j < self.nlinks; j += 1 {
		if self.links[j].doorSeen < 0 {
			door = (^Door)(world_record(self.world, world_kind_named(self.world, "Door"), self.links[j].door)) if self.links[j].door != 0 else nil
			self.links[j].doorSeen = i32(door.ajar) if door != nil else 0
		}
	}
}


@(private = "file")
atmosphere_load :: proc(self: ^Atmosphere) {
	air:       ^Gas_Store
	combustor: ^Combustor
	fuel:      ^Fuel_Container
	body:      ^Thermal_Body
	stores:    ^Store
	gone:      [^]Entity_ID
	goneHeat:  [^]i64
	i:         uint
	ngone:     i32
	n:         i32
	k:         i32

	// a region ended, joined into another: its heat in transit goes on to
	// the air it joined
	gone     = make([^]Entity_ID, int(self.nregions + 1))
	goneHeat = make([^]i64, int(self.nregions + 1))
	ngone    = 0
	n        = 0
	for k = 0; k < self.nregions; k += 1 {
		if world_record(self.world, world_kind_named(self.world, "GasStore"), self.regions[k].entity) != nil {
			self.regions[n] = self.regions[k]
			n += 1
		} else if self.regions[k].pending != 0 {
			gone[ngone]     = world_resolve(self.world, self.regions[k].entity)
			goneHeat[ngone] = self.regions[k].pending
			ngone += 1
		}
	}
	self.nregions = n

	stores = world_store_for_kind(self.world, world_kind_named(self.world, "GasStore"))
	for i = 0; i < store_count(stores); i += 1 {
		air = (^Gas_Store)(store_record_at_index(stores, i))
		k   = atmosphere_region_of(self, store_entity_at_index(stores, i))
		if k < 0 {
			continue
		}
		self.regions[k].oxygen  = air.oxygen
		self.regions[k].dioxide = air.dioxide
		self.regions[k].heat    = air.gasHeat
		self.regions[k].total   = air.total
	}
	for k = 0; k < ngone; k += 1 {
		if gone[k] != 0 {
			n = atmosphere_region_of(self, gone[k])
			if n >= 0 {
				self.regions[n].pending += goneHeat[k]
			}
		}
	}
	free(gone)
	free(goneHeat)
	atmosphere_load_links(self)
	stores = world_store_for_kind(self.world, world_kind_named(self.world, "Combustor"))
	for i = 0; i < store_count(stores); i += 1 {
		combustor = (^Combustor)(store_record_at_index(stores, i))
		fuel      = (^Fuel_Container)(world_record(self.world, world_kind_named(self.world, "FuelContainer"), store_entity_at_index(stores, i)))
		if fuel == nil {
			continue
		}
		k = atmosphere_stove_of(self, store_entity_at_index(stores, i))
		if k < 0 {
			continue
		}
		if !combustor.lit || self.stoves[k].fuel < 0 {
			self.stoves[k].fuel = fuel.fuel * 1000
		}
		self.stoves[k].region = atmosphere_region_of(self, air_over(self.world, store_entity_at_index(stores, i)))
	}
	stores = world_store_for_kind(self.world, world_kind_named(self.world, "ThermalBody"))
	for i = 0; i < store_count(stores); i += 1 {
		body = (^Thermal_Body)(store_record_at_index(stores, i))
		if body.toAir == 0 {
			continue
		}
		k = atmosphere_surface_of(self, store_entity_at_index(stores, i))
		if k < 0 {
			continue
		}
		self.surfaces[k].conductance = body.toAir
		self.surfaces[k].region      = atmosphere_region_of(self, world_resolve(self.world, Entity_ID(body.bounds)) if body.bounds != 0 else air_over(self.world, store_entity_at_index(stores, i)))
	}
	stores = world_store_for_kind(self.world, world_kind_named(self.world, "Respirator"))
	for i = 0; i < store_count(stores); i += 1 {
		k = atmosphere_breather_of(self, store_entity_at_index(stores, i))
		if k >= 0 {
			self.breathers[k].region = atmosphere_region_of(self, air_over(self.world, store_entity_at_index(stores, i)))
		}
	}
}


// What a breather takes now, mmol of oxygen a thousand seconds: at rest
// while it is the actor of a running rest, else at work.
@(private = "file")
atmosphere_breath_of :: proc(self: ^Atmosphere, b: i32) -> i64 {
	respirator: ^Respirator
	record:     ^Activity
	mine:       [^]Entity_ID
	n:          uint
	i:          uint
	resting:    bool

	respirator = (^Respirator)(world_record(self.world, world_kind_named(self.world, "Respirator"), self.breathers[b].entity))
	if respirator == nil || self.breathers[b].region < 0 {
		return 0
	}
	mine    = world_copy_activities_of(self.world, self.breathers[b].entity, &n)
	resting = false
	for i = 0; i < n && !resting; i += 1 {
		record  = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), mine[i]))
		resting = record != nil && record.status == u32(tri.type_named(world_tri(self.world), "\"running\"")) &&
		          operation_effect(self.world, world_text_field(self.world, "Activity.operation", mine[i])) == "rest"
	}
	free(mine)
	return respirator.atRest if resting else respirator.atWork
}


@(private = "file")
atmosphere_lit :: proc(self: ^Atmosphere, s: i32) -> bool {
	combustor: ^Combustor

	combustor = (^Combustor)(world_record(self.world, world_kind_named(self.world, "Combustor"), self.stoves[s].entity))
	return combustor != nil && combustor.lit && self.stoves[s].fuel > 0
}


// What the stove burns now, mg a second: its rate, or, damper closed, what
// the room's oxygen allows: all of it at 21%, nothing at 10%.
@(private = "file")
atmosphere_rate_of :: proc(self: ^Atmosphere, s: i32) -> i64 {
	combustor: ^Combustor
	r:         ^Air_Region
	permille:  i64

	combustor = (^Combustor)(world_record(self.world, world_kind_named(self.world, "Combustor"), self.stoves[s].entity))
	if combustor == nil || !atmosphere_lit(self, s) {
		return 0
	}
	if combustor.damper || self.stoves[s].region < 0 {
		return combustor.burnRate
	}
	r        = &self.regions[self.stoves[s].region]
	permille = r.oxygen * 1000 / r.total - 100
	if permille <= 0 {
		return 0
	}
	if permille > 110 {
		permille = 110
	}
	return combustor.burnRate * permille / 110
}


@(private = "file")
gasTemperature :: proc(r: ^Air_Region) -> i64 {
	return r.heat * 1000000 / (r.total * BG_GAS_CAPACITY)
}


// How far a surface's air is above the solid, mK, from their records; 0
// below half a kelvin, where the exchange rests.
@(private = "file")
atmosphere_surface_delta :: proc(self: ^Atmosphere, i: i32, capacity: ^i64) -> i64 {
	body: ^Thermal_Body
	r:    ^Air_Region
	d:    i64

	body = (^Thermal_Body)(world_record(self.world, world_kind_named(self.world, "ThermalBody"), self.surfaces[i].entity))
	if body == nil || self.surfaces[i].region < 0 {
		return 0
	}
	r = &self.regions[self.surfaces[i].region]
	d = gasTemperature(r) - body.heat * 1000 / body.heatCapacity
	if capacity != nil {
		capacity^ = r.total * BG_GAS_CAPACITY / 1000 if r.total * BG_GAS_CAPACITY / 1000 < body.heatCapacity else body.heatCapacity
	}
	return 0 if abs(d) < 500 else d
}


@(private = "file")
quantity :: proc(r: ^Air_Region, q: i32) -> i64 {
	return r.oxygen if q == 0 else (r.dioxide if q == 1 else r.heat)
}


// What a mmol of air from a link's far side carries, as a fraction: the
// outdoors' fixed air, or the other region's.
@(private = "file")
across :: proc(regions: [^]Air_Region, l: ^Air_Link, q: i32, num: ^i64, den: ^i64) {
	@(static, rodata) outNum := [3]i64{BG_OUT_OXYGEN, BG_OUT_DIOXIDE, BG_OUT_HEAT}
	@(static, rodata) outDen := [3]i64{1000, 10000, 1000}

	if l.b < 0 {
		num^ = outNum[q]
		den^ = outDen[q]
		return
	}
	num^ = quantity(&regions[l.b], q)
	den^ = regions[l.b].total
}


// Whether a link rests: nothing flows, or what it would carry is within the
// settle tolerances of its smaller side, and its door is as it was.
@(private = "file")
atmosphere_link_quiet :: proc(self: ^Atmosphere, l: i32, v: [^]Air_Region) -> bool {
	link:      ^Air_Link
	door:      ^Door
	num:       i64
	den:       i64
	tolerance: [3]i64
	q:         i32
	k:         i32

	link = &self.links[l]
	door = (^Door)(world_record(self.world, world_kind_named(self.world, "Door"), link.door)) if link.door != 0 else nil
	if door != nil && i32(door.ajar) != link.doorSeen {
		return false
	}
	if link.flow == 0 {
		return true
	}
	k = link.a
	tolerance[0] = v[k].total / 1000
	tolerance[1] = 100
	tolerance[2] = v[k].total * BG_GAS_CAPACITY / 2000
	for q = 0; q < 3; q += 1 {
		across(v, link, q, &num, &den)
		if abs(quantity(&v[k], q) - v[k].total * num / den) > tolerance[q] {
			return false
		}
	}
	return true
}


// Whether a region is awake: a link to it moving, or something in it.
@(private = "file")
atmosphere_awake :: proc(self: ^Atmosphere, k: i32, v: [^]Air_Region) -> bool {
	crossed: Entity_ID
	j:       i32

	if v[k].pending != 0 {
		return true
	}
	for j = 0; j < self.nlinks; j += 1 {
		if (self.links[j].a == k || self.links[j].b == k) && !atmosphere_link_quiet(self, j, v) {
			return true
		}
	}
	for j = 0; j < self.nstoves; j += 1 {
		if self.stoves[j].region == k && atmosphere_lit(self, j) {
			return true
		}
	}
	for j = 0; j < self.nbreathers; j += 1 {
		if self.breathers[j].region == k && atmosphere_breath_of(self, j) != 0 {
			return true
		}
	}
	for j = 0; j < self.nsurfaces; j += 1 {
		if self.surfaces[j].region == k && atmosphere_surface_delta(self, j, nil) != 0 {
			return true
		}
	}
	crossed = atmosphere_crossed_watch(self)
	return crossed != 0 &&
	       atmosphere_region_watched_by(self, (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), crossed))) == k
}


// What the links into a region carry now, per second, in units of `unit`
// a mmol of whatever `q` is: each moving link's flow times the difference.
@(private = "file")
atmosphere_link_flow_into :: proc(self: ^Atmosphere, k: i32, q: i32, unit: i64) -> i64 {
	l:   ^Air_Link
	num: i64
	den: i64
	sum: i64
	j:   i32

	sum = 0
	for j = 0; j < self.nlinks; j += 1 {
		l = &self.links[j]
		if (l.a != k && l.b != k) || atmosphere_link_quiet(self, j, self.regions) {
			continue
		}
		across(self.regions, l, q, &num, &den)
		if l.a == k {
			sum += l.flow * (num * unit / den - quantity(&self.regions[k], q) * unit / self.regions[k].total)
		} else {
			sum += l.flow * (quantity(&self.regions[l.a], q) * unit / self.regions[l.a].total - num * unit / den)
		}
	}
	return sum
}


// The steps a region was awake for.
atmosphere_steps_of :: proc(self: ^Atmosphere, region: Entity_ID) -> uint {
	i: i32

	for i = 0; i < self.nregions; i += 1 {
		if self.regions[i].entity == region {
			return self.regions[i].steps
		}
	}
	return 0
}


// A region's temperature now, in millikelvin.
atmosphere_temperature_of :: proc(self: ^Atmosphere, region: Entity_ID) -> i64 {
	i: i32

	atmosphere_load(self)
	for i = 0; i < self.nregions; i += 1 {
		if self.regions[i].entity == region {
			return self.regions[i].heat * 1000000 / (self.regions[i].total * BG_GAS_CAPACITY)
		}
	}
	return 0
}


// --- the domain -----------------------------------------------------------------

atmosphere_is_active :: proc(self: ^Atmosphere) -> bool {
	i: i32

	atmosphere_load(self)
	for i = 0; i < self.nregions; i += 1 {
		if atmosphere_awake(self, i, self.regions) {
			return true
		}
	}
	return false
}


// The activities watching a region's air, running.
@(private = "file")
atmosphere_air_watches :: proc(self: ^Atmosphere, out: ^[^]Entity_ID) -> uint {
	record:  ^Activity
	list:    [^]Entity_ID
	count:   uint
	i:       uint
	n:       uint
	running: u32

	running = u32(tri.type_named(world_tri(self.world), "\"running\""))
	list    = world_copy_watching_activities(self.world, &count)       // the world's index of watches
	n       = 0
	for i = 0; i < count; i += 1 {
		record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), list[i]))
		if record != nil && (record.watchDioxide > 0 || record.watchCool > 0 || record.watchWarm > 0) && record.watchHolder != 0 &&
		   record.status == running {
			list[n] = list[i]
			n += 1
		}
	}
	out^ = list
	return n
}


@(private = "file")
atmosphere_region_watched_by :: proc(self: ^Atmosphere, record: ^Activity) -> i32 {
	holder: Entity_ID
	k:      i32

	holder = world_resolve(self.world, Entity_ID(record.watchHolder))
	for k = 0; k < self.nregions && self.regions[k].entity != holder; k += 1 {
	}
	return -1 if k == self.nregions else k
}


// Why a running watch has fired, now: "" (nil) while its region's air is
// within what it watches.
@(private = "file")
atmosphere_crossing_of :: proc(self: ^Atmosphere, record: ^Activity) -> string {
	r: ^Air_Region
	k: i32

	k = atmosphere_region_watched_by(self, record)
	if k < 0 {
		return ""
	}
	r = &self.regions[k]
	if record.watchDioxide != 0 && r.dioxide >= record.watchDioxide {
		return fmt.tprintf("reaches %d mmol of carbon dioxide", r.dioxide)
	}
	if record.watchCool != 0 && gasTemperature(r) < record.watchCool {
		return fmt.tprintf("cools to %d mK", gasTemperature(r))
	}
	if record.watchWarm != 0 && gasTemperature(r) > record.watchWarm {
		return fmt.tprintf("warms to %d mK", gasTemperature(r))
	}
	return ""
}


// A running watch already crossed and not yet reported: it wakes the domain.
@(private = "file")
atmosphere_crossed_watch :: proc(self: ^Atmosphere) -> Entity_ID {
	watched: [^]Entity_ID
	crossed: Entity_ID
	n:       uint
	i:       uint
	s:       i32

	n       = atmosphere_air_watches(self, &watched)
	crossed = NO_ENTITY
	for i = 0; i < n && crossed == 0; i += 1 {
		for s = 0; s < self.nfired && self.fired[s] != watched[i]; s += 1 {
		}
		if s == self.nfired &&
		   atmosphere_crossing_of(self, (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), watched[i]))) != "" {
			crossed = watched[i]
		}
	}
	free(watched)
	return crossed
}


// The heat flowing into a region's gas now, mW: the door, the solids'
// surfaces, and a fire venting into it.
@(private = "file")
atmosphere_heat_flow_into :: proc(self: ^Atmosphere, k: i32) -> i64 {
	flow: i64
	i:    i32

	flow = atmosphere_link_flow_into(self, k, 2, 1000)
	for i = 0; i < self.nsurfaces; i += 1 {
		if self.surfaces[i].region == k {
			flow -= self.surfaces[i].conductance * atmosphere_surface_delta(self, i, nil)
		}
	}
	for i = 0; i < self.nstoves; i += 1 {
		if self.stoves[i].region == k && atmosphere_lit(self, i) &&
		   !(^Combustor)(world_record(self.world, world_kind_named(self.world, "Combustor"), self.stoves[i].entity)).damper {
			flow += atmosphere_rate_of(self, i) * BG_BURN_HEAT * (10 - BG_BURN_SHARE) * 100
		}
	}
	return flow
}


atmosphere_horizon_at :: proc(self: ^Atmosphere, t: Time) -> Horizon {
	record:  ^Activity
	watched: [^]Entity_ID
	h:       Horizon
	n:       uint
	i:       uint
	rate:    i64
	when_:   i64
	s:       i32
	k:       i32
	burning: bool

	atmosphere_load(self)
	burning = false
	h.nextEvent = TIME_NEVER
	for s = 0; s < self.nstoves; s += 1 {
		if !atmosphere_lit(self, s) {
			continue
		}
		burning = true
		// the fuel runs out: at this rate, less the part of a milligram
		// already burning, or later, as a smoulder slows
		rate = atmosphere_rate_of(self, s)
		if rate > 0 {
			when_ = t.ms + (self.stoves[s].fuel * 1000 - self.stoves[s].carry + rate - 1) / rate
			if when_ > t.ms && when_ < h.nextEvent.ms {
				h.nextEvent = time_make(when_)
			}
		}
	}
	// a watch crossing. Carbon dioxide at the rise the rates give now (mmol
	// per 1000 s): the fires venting into the region, the breathers, and the
	// door; the rise only slows as the oxygen falls, so this is never late. A
	// temperature at twice the rate the heat flows give now, and again from
	// closer in. No sooner than a second, the event tolerance; a watch
	// already crossed, at once
	if atmosphere_crossed_watch(self) != NO_ENTITY {
		h.nextEvent = time_make(t.ms + 1)
	}
	n = atmosphere_air_watches(self, &watched)
	for i = 0; i < n; i += 1 {
		rise:        i64
		flow:        i64
		capacity:    i64
		temperature: i64

		record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), watched[i]))
		k = atmosphere_region_watched_by(self, record)
		if k < 0 || atmosphere_crossing_of(self, record) != "" {
			continue
		}
		when_ = TIME_NEVER.ms
		if record.watchDioxide != 0 {
			rise = atmosphere_link_flow_into(self, k, 1, 1000)
			for s = 0; s < self.nstoves; s += 1 {
				if self.stoves[s].region == k && atmosphere_lit(self, s) &&
				   !(^Combustor)(world_record(self.world, world_kind_named(self.world, "Combustor"), self.stoves[s].entity)).damper {
					rise += atmosphere_rate_of(self, s) * BG_BURN_DIOXIDE
				}
			}
			for s = 0; s < self.nbreathers; s += 1 {
				if self.breathers[s].region == k {
					rise += atmosphere_breath_of(self, s) * BG_BREATH_DIOXIDE / 5
				}
			}
			if rise > 0 {
				when_ = t.ms + (record.watchDioxide - self.regions[k].dioxide) * 1000000 / rise
			}
		}
		flow        = atmosphere_heat_flow_into(self, k)
		capacity    = self.regions[k].total * BG_GAS_CAPACITY / 1000
		temperature = gasTemperature(&self.regions[k])
		if record.watchCool != 0 && flow < 0 &&
		   t.ms + (temperature - record.watchCool) * capacity * 1000 / (-2 * flow) < when_ {
			when_ = t.ms + (temperature - record.watchCool) * capacity * 1000 / (-2 * flow)
		}
		if record.watchWarm != 0 && flow > 0 &&
		   t.ms + (record.watchWarm - temperature) * capacity * 1000 / (2 * flow) < when_ {
			when_ = t.ms + (record.watchWarm - temperature) * capacity * 1000 / (2 * flow)
		}
		if when_ == TIME_NEVER.ms {
			continue
		}
		if when_ < t.ms + 1000 {
			when_ = t.ms + 1000
		}
		if when_ < h.nextEvent.ms {
			h.nextEvent = time_make(when_)
		}
	}
	free(watched)
	h.safeStep = time_make(600000 if burning else 3600000)

	// an agent's body, warmed or cooled by what this domain sends it (the
	// exchange with the air, its breath's heat), crossing its next whole
	// kelvin, which it feels as cold: predicted at twice the rate those give
	// now, and again from closer in
	for k = 0; k < self.nsurfaces; k += 1 {
		body:   ^Thermal_Body
		kelvin: i64
		bound:  i64

		// (the C declared a `rate` of its own here; the outer one serves)
		body = (^Thermal_Body)(world_record(self.world, world_kind_named(self.world, "ThermalBody"), self.surfaces[k].entity))
		if body == nil || self.surfaces[k].region < 0 ||
		   world_record(self.world, world_kind_named(self.world, "Agent"), self.surfaces[k].entity) == nil {
			continue
		}
		kelvin = body.heat * 1000 / body.heatCapacity
		rate   = self.surfaces[k].conductance * (gasTemperature(&self.regions[self.surfaces[k].region]) - kelvin)   // mW
		for s = 0; s < self.nbreathers; s += 1 {
			if self.breathers[s].entity == self.surfaces[k].entity {
				rate += atmosphere_breath_of(self, s) * BG_BREATH_HEAT
			}
		}
		if rate == 0 {
			continue
		}
		bound = (kelvin - kelvin % 1000 - (0 if kelvin % 1000 != 0 else 1000)) if rate < 0 else (kelvin - kelvin % 1000 + 1000)
		when_ = t.ms + abs(kelvin - bound) * body.heatCapacity * 1000 / (2 * abs(rate))   // mJ over mW
		if when_ < t.ms + 1000 {
			when_ = t.ms + 1000
		}
		if when_ < h.nextEvent.ms {
			h.nextEvent = time_make(when_)
		}
	}

	// a moving link is explicit: a step carries no more than an eighth of
	// the smaller side's air
	for k = 0; k < self.nlinks; k += 1 {
		total: i64

		if self.links[k].flow == 0 || atmosphere_link_quiet(self, k, self.regions) {
			continue
		}
		total = self.regions[self.links[k].a].total
		if self.links[k].b >= 0 && self.regions[self.links[k].b].total < total {
			total = self.regions[self.links[k].b].total
		}
		when_ = total * 1000 / (8 * self.links[k].flow)
		if when_ < h.safeStep.ms {
			h.safeStep = time_make(1 if when_ < 1 else when_)
		}
	}

	// the exchange with the solids lags a step: no more than an eighth of
	// the way to equal in one
	for i = 0; i < uint(self.nsurfaces); i += 1 {
		capacity: i64

		if atmosphere_surface_delta(self, i32(i), &capacity) == 0 {
			continue
		}
		when_ = capacity * 1000 / (8 * self.surfaces[i].conductance)
		if when_ < h.safeStep.ms {
			h.safeStep = time_make(1 if when_ < 1 else when_)
		}
	}
	return h
}


// --- coupling -------------------------------------------------------------------

atmosphere_publish_into :: proc(self: ^Atmosphere, snapshot: ^Snapshot) {
	k: i32

	atmosphere_load(self)
	for k = 0; k < self.nregions; k += 1 {
		snapshot_set_quantity(snapshot, .Temperature, self.regions[k].entity, gasTemperature(&self.regions[k]))
	}
}


atmosphere_takes_contribution :: proc(self: ^Atmosphere, contribution: Contribution) -> bool {
	return contribution.quantity == .Heat &&
	       world_record(self.world, world_kind_named(self.world, "GasStore"), contribution.target) != nil
}


atmosphere_receive_contribution :: proc(self: ^Atmosphere, contribution: Contribution) {
	k: i32

	atmosphere_load(self)
	k = atmosphere_region_of(self, contribution.target)
	if k >= 0 {
		self.regions[k].pending += contribution.amount
	}
}


@(private = "file")
atmosphere_send :: proc(self: ^Atmosphere, heat: i64, target: Entity_ID, source: Entity_ID, outbox: ^Contributions) {
	c: Contribution

	c.target   = target
	c.source   = source
	c.quantity = .Heat
	c.amount   = heat
	if outbox != nil {
		contributions_add_contribution(outbox, c)
	}
}


// What comes in through the door from outdoors, and goes out, for one
// quantity of a region: in whole quanta, the fraction carried.
@(private = "file")
exchange :: proc(air: i64, mine: i64, total: i64, outNum: i64, outDen: i64, carryIn: ^i64, carryOut: ^i64) -> i64 {
	in_: i64
	out: i64

	carryIn^  += air * outNum
	in_        = carryIn^ / outDen
	carryIn^  %= outDen
	carryOut^ += air * mine
	out        = carryOut^ / total
	carryOut^ %= total
	return in_ - out
}


// -advanceFrom:to:world:committer:
atmosphere_advance_from_to_world_committer :: proc(self: ^Atmosphere, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	atmosphere_advance_from_to_world_committer_snapshot(self, t0, t1, world, committer, nil, nil)
}


// -advanceFrom:to:world:committer:snapshot:outbox:
// With no outbox, nothing goes to the solids: the fire's share stays in
// the iron's flue gas, and there is no exchange.
atmosphere_advance_from_to_world_committer_snapshot :: proc(self: ^Atmosphere, t0: Time, t1: Time, world: ^World, committer: ^Committer,
                                                            snapshot: ^Snapshot, outbox: ^Contributions) {
	record:  ^Activity
	g:       ^Proposal_Group
	r:       ^Air_Region
	before:  [^]Air_Region
	watched: [^]Entity_ID
	n:       uint
	i:       uint
	dt:      i64
	air:     i64
	d:       [3]i64
	burned:  i64
	rate:    i64
	used:    i64
	made:    i64
	heat:    i64
	share:   i64
	solid:   i64
	delta:   i64
	breath:  i64
	num:     i64
	den:     i64
	door:    ^Door
	l:       ^Air_Link
	quiet:   [^]bool
	c:       i32
	why:     string
	q:       i64
	rates:   [^]i64
	k:       i32
	s:       i32
	open:    bool

	dt = t1.ms - t0.ms
	atmosphere_load(self)
	if dt <= 0 {
		return
	}
	if !self.ledgered {
		self.ledger = {}
		for k = 0; k < self.nregions; k += 1 {
			self.ledger.initial[0] += self.regions[k].oxygen
			self.ledger.initial[1] += self.regions[k].dioxide
			self.ledger.initial[2] += self.regions[k].heat
		}
		for s = 0; s < self.nstoves; s += 1 {
			self.ledger.fuel += self.stoves[s].fuel
		}
		self.ledgered = true
	}
	before = make([^]Air_Region, int(self.nregions + 1))
	quiet  = make([^]bool, int(self.nlinks + 1))
	rates  = make([^]i64, int(self.nstoves + 1))
	if self.nregions > 0 {
		mem.copy(before, self.regions, int(self.nregions) * size_of(Air_Region))
	}
	for s = 0; s < self.nstoves; s += 1 {
		rates[s] = atmosphere_rate_of(self, s)          // from step-start values
	}
	for k = 0; k < self.nlinks; k += 1 {
		quiet[k] = atmosphere_link_quiet(self, k, before)
	}
	for k = 0; k < self.nregions; k += 1 {
		if atmosphere_awake(self, k, before) {
			self.regions[k].steps += 1
		}
	}

	// what was in transit to the gas
	for k = 0; k < self.nregions; k += 1 {
		self.regions[k].heat     += self.regions[k].pending
		self.ledger.received     += self.regions[k].pending
		self.regions[k].pending   = 0
	}

	// the solids' surfaces, from the step-start snapshot: the gas gives what
	// it gives now, and the solid receives it next step
	for k = 0; outbox != nil && k < self.nsurfaces; k += 1 {
		if self.surfaces[k].region < 0 || snapshot == nil ||
		   !snapshot_quantity(snapshot, .Temperature, self.surfaces[k].entity, &solid) {
			continue
		}
		delta = gasTemperature(&before[self.surfaces[k].region]) - solid
		if abs(delta) < 500 {
			continue
		}
		self.surfaces[k].carry += self.surfaces[k].conductance * delta * dt
		q                       = self.surfaces[k].carry / 1000000
		self.surfaces[k].carry %= 1000000
		self.regions[self.surfaces[k].region].heat -= q
		self.ledger.exchanged                      += q
		atmosphere_send(self, q, self.surfaces[k].entity, self.regions[self.surfaces[k].region].entity, outbox)
	}

	// the links: each moving one mixes its region with what it opens to,
	// from step-start values; between regions, what one gains the other
	// loses
	for k = 0; k < self.nlinks; k += 1 {
		if quiet[k] {
			continue
		}
		l           = &self.links[k]
		r           = &self.regions[l.a]
		l.carryAir += l.flow * dt
		air         = l.carryAir / 1000
		l.carryAir %= 1000
		for c = 0; c < 3; c += 1 {
			across(before, l, c, &num, &den)
			d[c] = exchange(air, quantity(&before[l.a], c), r.total, num, den, &l.carryIn[c], &l.carryOut[c])
		}
		r.oxygen  += d[0]
		r.dioxide += d[1]
		r.heat    += d[2]
		if l.b < 0 {
			self.ledger.inflow[0] += d[0]
			self.ledger.inflow[1] += d[1]
			self.ledger.inflow[2] += d[2]
		} else {
			self.regions[l.b].oxygen  -= d[0]
			self.regions[l.b].dioxide -= d[1]
			self.regions[l.b].heat    -= d[2]
		}
	}

	// the stoves: from step-start values
	for s = 0; s < self.nstoves; s += 1 {
		self.stoves[s].out = false
		if !atmosphere_lit(self, s) {
			continue
		}
		rate                  = rates[s]
		self.stoves[s].carry += rate * dt
		burned                = self.stoves[s].carry / 1000
		self.stoves[s].carry %= 1000
		if burned > self.stoves[s].fuel {
			burned = self.stoves[s].fuel
		}
		self.stoves[s].fuel -= burned
		self.ledger.burned  += burned
		open = (^Combustor)(world_record(self.world, world_kind_named(self.world, "Combustor"), self.stoves[s].entity)).damper

		// its iron's share
		share = 0
		if outbox != nil && world_record(self.world, world_kind_named(self.world, "ThermalBody"), self.stoves[s].entity) != nil {
			self.stoves[s].carryShare += burned * BG_BURN_HEAT * BG_BURN_SHARE
			share                      = self.stoves[s].carryShare / 10
			self.stoves[s].carryShare %= 10
			self.ledger.toSolids      += share
			atmosphere_send(self, share, self.stoves[s].entity, self.stoves[s].entity, outbox)
		}
		if self.stoves[s].region >= 0 {
			r = &self.regions[self.stoves[s].region]
			if open {
				// drawn from outdoors, and the rest of the heat up the flue
			} else {
				// from the room and into it
				r.carryBurn[0] += burned * BG_BURN_OXYGEN
				used            = r.carryBurn[0] / 1000
				r.carryBurn[0] %= 1000
				if used > r.oxygen {
					used = r.oxygen
				}
				r.carryBurn[1] += burned * BG_BURN_DIOXIDE
				made            = r.carryBurn[1] / 1000
				r.carryBurn[1] %= 1000
				heat       = burned * BG_BURN_HEAT - share
				r.oxygen  -= used
				r.dioxide += made
				r.heat    += heat
				self.ledger.consumed[0] += used
				self.ledger.produced[1] += made
				self.ledger.produced[2] += heat
			}
		}
		if self.stoves[s].fuel == 0 {
			self.stoves[s].out = true
		}
	}

	// the breathers: from the air over them, their heat to their bodies
	for s = 0; s < self.nbreathers; s += 1 {
		breath = atmosphere_breath_of(self, s)
		if breath <= 0 {
			continue
		}
		r                       = &self.regions[self.breathers[s].region]
		self.breathers[s].carry += breath * dt
		used                     = self.breathers[s].carry / 1000000
		self.breathers[s].carry %= 1000000
		if used > r.oxygen {
			used = r.oxygen
		}
		self.breathers[s].carryDioxide += used * BG_BREATH_DIOXIDE
		made                            = self.breathers[s].carryDioxide / 5
		self.breathers[s].carryDioxide %= 5
		r.oxygen  -= used
		r.dioxide += made
		self.ledger.consumed[0] += used
		self.ledger.produced[1] += made
		heat = used * BG_BREATH_HEAT
		if outbox != nil && world_record(self.world, world_kind_named(self.world, "ThermalBody"), self.breathers[s].entity) != nil {
			self.ledger.toSolids += heat
			atmosphere_send(self, heat, self.breathers[s].entity, self.breathers[s].entity, outbox)
		} else {
			r.heat                  += heat
			self.ledger.produced[2] += heat
		}
	}

	// the doors as they are now
	for k = 0; k < self.nlinks; k += 1 {
		door = (^Door)(world_record(self.world, world_kind_named(self.world, "Door"), self.links[k].door)) if self.links[k].door != 0 else nil
		self.links[k].doorSeen = i32(door.ajar) if door != nil else 0
	}

	// the records mirror the domain
	for k = 0; k < self.nregions; k += 1 {
		world_set_field_of_value(self.world, "GasStore.oxygen", self.regions[k].entity, self.regions[k].oxygen)
		world_set_field_of_value(self.world, "GasStore.dioxide", self.regions[k].entity, self.regions[k].dioxide)
		world_set_field_of_value(self.world, "GasStore.gasHeat", self.regions[k].entity, self.regions[k].heat)
	}
	for s = 0; s < self.nstoves; s += 1 {
		world_set_field_of_value(self.world, "FuelContainer.fuel", self.stoves[s].entity, (self.stoves[s].fuel + 999) / 1000)
	}
	self.rise = (self.regions[0].dioxide - before[0].dioxide) * 1000 / dt if self.nregions != 0 && dt != 0 else 0
	self.steps += 1

	// a fire out, at the boundary: by proposal
	for s = 0; s < self.nstoves; s += 1 {
		if self.stoves[s].out {
			g = proposal_group_group_with_phase(.Process, fmt.tprintf("atmosphere: stove %d goes out", u64(self.stoves[s].entity)))
			proposal_group_set_of_to(g, "Combustor.lit", whole(self.stoves[s].entity), 0)
			proposal_group_set_of_to(g, "FuelContainer.fuel", whole(self.stoves[s].entity), 0)
			committer_submit(committer, g)
		}
	}

	// watches crossed
	free(before)
	free(quiet)
	free(rates)
	n = atmosphere_air_watches(self, &watched)
	// a watch reported stays so while its activity watches
	c = 0
	for s = 0; s < self.nfired; s += 1 {
		for i = 0; i < n && watched[i] != self.fired[s]; i += 1 {
		}
		if i < n {
			self.fired[c] = self.fired[s]
			c += 1
		}
	}
	self.nfired = c
	for i = 0; i < n; i += 1 {
		record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), watched[i]))
		why = atmosphere_crossing_of(self, record)
		if why == "" {
			continue
		}
		for s = 0; s < self.nfired && self.fired[s] != watched[i]; s += 1 {
		}
		if s < self.nfired {
			continue
		}
		atmosphere_fired(self, watched[i])
		k = atmosphere_region_watched_by(self, record)
		g = proposal_group_group_with_phase(.Process, fmt.tprintf("atmosphere: the air at %d %s", u64(self.regions[k].entity), why))
		proposal_group_emit_subject_other(g, "watched", whole(watched[i]), whole(self.regions[k].entity))
		committer_submit(committer, g)
	}
	free(watched)
}


// The conservation identity, exactly, for oxygen, dioxide, heat, and fuel.
atmosphere_balanced :: proc(self: ^Atmosphere) -> bool {
	sum:  [3]i64
	fuel: i64
	k:    i32

	if !self.ledgered {
		return true                    // nothing has moved yet
	}
	sum = {}
	for k = 0; k < self.nregions; k += 1 {
		sum[0] += self.regions[k].oxygen
		sum[1] += self.regions[k].dioxide
		sum[2] += self.regions[k].heat
	}
	fuel = 0
	for k = 0; k < self.nstoves; k += 1 {
		fuel += self.stoves[k].fuel
	}
	for k = 0; k < 3; k += 1 {
		if sum[k] != self.ledger.initial[k] + self.ledger.inflow[k] + self.ledger.produced[k] - self.ledger.consumed[k] +
		             (self.ledger.received - self.ledger.exchanged if k == 2 else 0) {
			return false
		}
	}
	return fuel + self.ledger.burned == self.ledger.fuel
}


// --- saves -----------------------------------------------------------------------

atmosphere_check_in_all :: proc(self: ^Atmosphere) {
}


atmosphere_saved_state :: proc(self: ^Atmosphere) -> []string {
	lines: [dynamic]string
	r:     ^Air_Region
	l:     ^Air_Link
	k:     i32

	lines = make([dynamic]string, context.temp_allocator)
	append(&lines, fmt.tprintf("air %d %d %d", 1 if self.ledgered else 0, u64(self.steps), self.rise))
	append(&lines, fmt.tprintf("ledger %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
	                           self.ledger.initial[0], self.ledger.initial[1], self.ledger.initial[2],
	                           self.ledger.inflow[0], self.ledger.inflow[1], self.ledger.inflow[2],
	                           self.ledger.produced[0], self.ledger.produced[1], self.ledger.produced[2],
	                           self.ledger.consumed[0], self.ledger.consumed[1], self.ledger.consumed[2],
	                           self.ledger.fuel, self.ledger.burned, self.ledger.exchanged, self.ledger.toSolids,
	                           self.ledger.received))
	for k = 0; k < self.nregions; k += 1 {
		r = &self.regions[k]
		append(&lines, fmt.tprintf("region %d %d %d %d %d %d", u64(r.entity), r.carryBurn[0], r.carryBurn[1], r.carryBurn[2],
		                           r.pending, i64(r.steps)))
	}
	for k = 0; k < self.nlinks; k += 1 {
		l = &self.links[k]
		append(&lines, fmt.tprintf("link %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
		                           u64(l.from), u64(l.to), 1 if l.at.form == .On_Tile else 0, l.at.x, l.at.y, l.at.level,
		                           l.carryAir, l.carryIn[0], l.carryIn[1], l.carryIn[2],
		                           l.carryOut[0], l.carryOut[1], l.carryOut[2], l.doorSeen))
	}
	for k = 0; k < self.nstoves; k += 1 {
		append(&lines, fmt.tprintf("stove %d %d %d %d", u64(self.stoves[k].entity), self.stoves[k].fuel, self.stoves[k].carry,
		                           self.stoves[k].carryShare))
	}
	for k = 0; k < self.nsurfaces; k += 1 {
		append(&lines, fmt.tprintf("surface %d %d", u64(self.surfaces[k].entity), self.surfaces[k].carry))
	}
	for k = 0; k < self.nbreathers; k += 1 {
		append(&lines, fmt.tprintf("breather %d %d %d", u64(self.breathers[k].entity), self.breathers[k].carry,
		                           self.breathers[k].carryDioxide))
	}
	for k = 0; k < self.nfired; k += 1 {
		append(&lines, fmt.tprintf("fired %d", u64(self.fired[k])))
	}
	return lines[:]
}


atmosphere_restore_saved_state :: proc(self: ^Atmosphere, lines: []string) {
	e:     i64
	to:    i64
	steps: i64
	l:     ^Air_Link
	x:     i64
	y:     i64
	level: i64
	seen:  i64
	v:     [17]i64
	i:     int
	r:     ^Air_Region
	text:  string
	flag:  i64
	k:     i32

	self.nregions   = 0
	self.nlinks     = 0
	self.nstoves    = 0
	self.nfired     = 0
	self.nsurfaces  = 0
	self.nbreathers = 0
	for i = 0; i < len(lines); i += 1 {
		text = lines[i]
		if sscanf(text, "air %d %llu %lld", &flag, &steps, &v[0]) == 3 {
			self.ledgered = i32(flag) != 0
			self.steps    = uint(u64(steps))
			self.rise     = v[0]
		} else if sscanf(text, "ledger %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld",
		                 &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7], &v[8], &v[9], &v[10],
		                 &v[11], &v[12], &v[13], &v[14], &v[15], &v[16]) == 17 {
			for k = 0; k < 3; k += 1 {
				self.ledger.initial[k]  = v[k]
				self.ledger.inflow[k]   = v[3 + k]
				self.ledger.produced[k] = v[6 + k]
				self.ledger.consumed[k] = v[9 + k]
			}
			self.ledger.fuel      = v[12]
			self.ledger.burned    = v[13]
			self.ledger.exchanged = v[14]
			self.ledger.toSolids  = v[15]
			self.ledger.received  = v[16]
		} else if sscanf(text, "region %llu %lld %lld %lld %lld %lld", &e, &v[0], &v[1], &v[2], &v[3], &v[4]) == 6 {
			k = atmosphere_region_of(self, Entity_ID(u64(e)))
			if k < 0 {
				continue
			}
			r              = &self.regions[k]
			r.carryBurn[0] = v[0]
			r.carryBurn[1] = v[1]
			r.carryBurn[2] = v[2]
			r.pending      = v[3]
			r.steps        = uint(u64(v[4]))
		} else if sscanf(text, "link %llu %llu %d %d %d %d %lld %lld %lld %lld %lld %lld %lld %d", &e, &to, &flag, &x, &y,
		                 &level, &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &seen) == 14 {
			if self.nlinks == self.linkcap {
				old := self.linkcap
				self.linkcap = self.linkcap * 2 if self.linkcap != 0 else 16
				self.links   = grow(self.links, old, self.linkcap)
			}
			l = &self.links[self.nlinks]
			self.nlinks += 1
			l^             = {}
			l.from         = Entity_ID(u64(e))
			l.to           = Entity_ID(u64(to))
			l.at           = on_tile(i32(x), i32(y), i32(level)) if i32(flag) != 0 else location_make_none()
			l.carryAir     = v[0]
			l.carryIn[0]   = v[1]
			l.carryIn[1]   = v[2]
			l.carryIn[2]   = v[3]
			l.carryOut[0]  = v[4]
			l.carryOut[1]  = v[5]
			l.carryOut[2]  = v[6]
			l.doorSeen     = i32(seen)
			l.a            = -1
			l.b            = -1
		} else if sscanf(text, "stove %llu %lld %lld %lld", &e, &v[0], &v[1], &v[2]) == 4 {
			k = atmosphere_stove_of(self, Entity_ID(u64(e)))
			if k < 0 {
				continue
			}
			self.stoves[k].fuel       = v[0]
			self.stoves[k].carry      = v[1]
			self.stoves[k].carryShare = v[2]
		} else if sscanf(text, "surface %llu %lld", &e, &v[0]) == 2 {
			k = atmosphere_surface_of(self, Entity_ID(u64(e)))
			if k < 0 {
				continue
			}
			self.surfaces[k].carry = v[0]
		} else if sscanf(text, "breather %llu %lld %lld", &e, &v[0], &v[1]) == 3 {
			k = atmosphere_breather_of(self, Entity_ID(u64(e)))
			if k < 0 {
				continue
			}
			self.breathers[k].carry        = v[0]
			self.breathers[k].carryDioxide = v[1]
		} else if sscanf(text, "fired %llu", &e) == 1 {
			atmosphere_fired(self, Entity_ID(u64(e)))
		}
	}
	atmosphere_load(self)
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


atmosphere_as_domain :: proc(self: ^Atmosphere) -> Domain {
	return Domain{
		data                 = self,
		name                 = proc(data: rawptr) -> string {return atmosphere_name((^Atmosphere)(data))},
		check_in_all         = proc(data: rawptr) {atmosphere_check_in_all((^Atmosphere)(data))},
		saved_state          = proc(data: rawptr) -> []string {return atmosphere_saved_state((^Atmosphere)(data))},
		restore_saved_state  = proc(data: rawptr, lines: []string) {atmosphere_restore_saved_state((^Atmosphere)(data), lines)},
		is_active            = proc(data: rawptr) -> bool {return atmosphere_is_active((^Atmosphere)(data))},
		horizon_at           = proc(data: rawptr, t: Time) -> Horizon {return atmosphere_horizon_at((^Atmosphere)(data), t)},
		advance_from         = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
			atmosphere_advance_from_to_world_committer((^Atmosphere)(data), t0, t1, world, committer)
		},
		publish_into         = proc(data: rawptr, snapshot: ^Snapshot) {atmosphere_publish_into((^Atmosphere)(data), snapshot)},
		takes_contribution   = proc(data: rawptr, contribution: Contribution) -> bool {
			return atmosphere_takes_contribution((^Atmosphere)(data), contribution)
		},
		receive_contribution = proc(data: rawptr, contribution: Contribution) {
			atmosphere_receive_contribution((^Atmosphere)(data), contribution)
		},
		advance_coupled      = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer,
		                            snapshot: ^Snapshot, outbox: ^Contributions) {
			atmosphere_advance_from_to_world_committer_snapshot((^Atmosphere)(data), t0, t1, world, committer, snapshot, outbox)
		},
	}
}

package lab

/*
 * The village (VILLAGE.md, slices 3 and 4; content/village/village.tri): four
 * households, twelve people, on a map of 160 by 100, living out the day's
 * commitments (content/home/home.tri): to work from 07:00 to 15:00, home
 * from 15:00 to 22:00, and a night's sleep in one's own bed from 22:00.
 * What the work is comes with later slices; for now each works by being at
 * the household's worksite. Between, they eat (content/cooking/): from the
 * household's larder, a sack of grain, cooked at its stove; a meal taken
 * to work, packed from 06:00, and supper from 18:00.
 *
 * Each has seen its worksite and its home before the first morning:
 * set down by its worksite for the first boundary, by its woodpile, its
 * larder and its stove for the next three, then by its bed, so all are in
 * what it knows when its commitments are undertaken, bound to them. Its sight is four tiles: the rest of the way it
 * finds as it walks.
 *
 * The run goes boundary by boundary up to each check's time, putting none
 * in of its own (as the watcher runs it), so `lab run village` and a
 * watched village are the same run. The checks, for three days and nights:
 * everyone taking a meal to work at 07:30, at work at 11:00 (about its
 * worksite, or about its work: a woodcutter in the woods, or on its way
 * home with firewood), the meal
 * eaten there by 14:30, home by 21:00, asleep in their own bed at 02:00;
 * and at the end, each household's larder emptied by what it ate, and
 * nobody's reserves fallen.
 */

import "core:fmt"
import "core:strings"
import tri "../../triangle/odin/triangle"


VILLAGE_DAY :: i64(86400000)
VILLAGE_HOUR :: i64(3600000)
VILLAGE_DAYS :: 3
VILLAGE_GRAIN :: i64(60)               // portions in each larder's sack (village.tri's grain_sack)

Village_Household :: struct {
	name:      string,
	trade:     cstring,              // the people's blueprint
	people:    int,
	beds:      [4][2]i32,            // where each one's bed stands
	stove:     [2]i32,
	larder:    [2]i32,
	woodpile:  [2]i32,               // outside, by the door
	worksite: cstring,              // its blueprint
	works:     [2]i32,               // where it stands
}

@(private = "file", rodata)
households := [4]Village_Household {
	{"the Ashes", "farmer", 3, {{39, 39}, {41, 39}, {43, 39}, {}}, {46, 43}, {39, 44}, {44, 46}, "scarecrow", {36, 84}},
	{"the Brooks", "farmer", 4, {{69, 38}, {71, 38}, {73, 38}, {75, 38}}, {78, 43}, {69, 44}, {74, 46}, "scarecrow", {79, 84}},
	{"the Fells", "woodcutter", 2, {{41, 60}, {43, 60}, {}, {}}, {46, 57}, {41, 57}, {44, 54}, "chopping_block", {61, 22}},
	{"the Hunts", "hunter", 3, {{71, 61}, {73, 61}, {75, 61}, {}}, {77, 57}, {71, 57}, {75, 54}, "hunting_blind", {135, 50}},
}

Villager :: struct {
	id:        Entity_ID,
	household: int,
	bed:       Entity_ID,
	worksite: Entity_ID,
}

Village :: struct {
	using object: Object,
	world:        ^World,
	committer:    ^Committer,
	scheduler:    ^Scheduler,
	activities:   ^Activities,
	knowledge:    ^Knowledge,
	agency:       ^Agency,
	bodies:       ^Bodies,
	air:          ^Atmosphere,       // burns what is in the stoves
	people:       [dynamic]Villager,
	larders:      [4]Entity_ID,      // each household's, by its index
	stoves:       [4]Entity_ID,
	woodpiles:    [4]Entity_ID,
	results:      [dynamic]string,   // each cloned
	error:        string,            // cloned; "" if it was set up
}


// The village set up in `world` (a new one, on the content's village map):
// its people have seen their homes and worksites, and have their
// commitments. Its count 1; village_error says if it couldn't be.
village_init_with_world :: proc(world: ^World, committer: ^Committer) -> ^Village {
	self := object_new(Village, village_dealloc)
	self.world      = retain(world)
	self.committer  = retain(committer)
	self.people     = make([dynamic]Villager)
	self.results    = make([dynamic]string)
	why: string
	if !world_set_terrain_map(world, "village_map", &why) {
		self.error = fmt.aprintf("no village map: %s", why)
		return self
	}
	committer_set_tracing(committer, false)             /* days of it: no trace kept */
	self.activities = retain(activities_with_world(world, committer))
	self.knowledge  = knowledge_init_with_world(world)
	self.agency     = agency_init_with_world(world, committer, self.knowledge)
	self.bodies     = bodies_init_with_world(world)
	self.air        = atmosphere_init_with_world(world)
	self.scheduler  = scheduler_init_with_world(world, committer)
	/* a diagnostic event is kept a day, then counted (KNOWLEDGE.md decision 21) */
	world_set_history_window(world, 86400000)
	agency_set_activities(self.agency, self.activities)
	scheduler_add_domain(self.scheduler, bodies_as_domain(self.bodies))
	scheduler_add_domain(self.scheduler, atmosphere_as_domain(self.air))
	scheduler_set_activities(self.scheduler, activities_as_activity_clock(self.activities))
	scheduler_set_perception(self.scheduler, knowledge_as_perception_phase(self.knowledge))
	scheduler_set_decision(self.scheduler, agency_as_decision_phase(self.agency))
	village_setup(self)
	return self
}


village_dealloc :: proc(self: ^Village) {
	release(self.world)
	release(self.committer)
	release(self.scheduler)
	release(self.activities)
	release(self.knowledge)
	release(self.agency)
	release(self.bodies)
	release(self.air)
	delete(self.people)
	for r in self.results do delete(r)
	delete(self.results)
	delete(self.error)
}


@(private = "file")
village_setup :: proc(self: ^Village) {
	c := self.committer
	g := proposal_group_group_with_phase(.System, "setup: the village")
	handles := make([dynamic]Villager, context.temp_allocator)
	works, larders, stoves, woodpiles: [4]Entity_ID
	for &h, k in households {
		works[k] = proposal_group_create(g, h.worksite, ns_utf8(fmt.tprintf("%s' worksite", h.name)),
		                                 on_tile(h.works.x, h.works.y, 0))
		stove := proposal_group_create(g, "stove", ns_utf8(fmt.tprintf("%s' stove", h.name)), on_tile(h.stove.x, h.stove.y, 0))
		stoves[k] = stove
		larder := proposal_group_create(g, "larder", ns_utf8(fmt.tprintf("%s' larder", h.name)),
		                                on_tile(h.larder.x, h.larder.y, 0))
		larders[k] = larder
		sack := proposal_group_create(g, "grain_sack", ns_utf8(fmt.tprintf("%s' grain", h.name)), in_(larder))
		woodpile := proposal_group_create(g, "woodpile", ns_utf8(fmt.tprintf("%s' woodpile", h.name)),
		                                  on_tile(h.woodpile.x, h.woodpile.y, 0))
		woodpiles[k] = woodpile
		/* firewood on it: the woodcutters' own a little, the rest what they
		 * have had of them before (bought, when there is a market) */
		wood := proposal_group_create(g, "woodcutters_firewood" if h.worksite == "chopping_block" else "household_firewood",
		                              ns_utf8(fmt.tprintf("%s' firewood", h.name)), in_(woodpile))
		first := len(handles)
		for i in 0 ..< h.people {
			bed := proposal_group_create(g, "bed", ns_utf8(fmt.tprintf("%s' bed %d", h.name, i)),
			                             on_tile(h.beds[i].x, h.beds[i].y, 0))
			/* first, by the worksite, a tile apart from each other */
			person := proposal_group_create(g, h.trade, ns_utf8(fmt.tprintf("%s, %d", h.name, i)),
			                                on_tile(h.works.x - 1 + i32(i), h.works.y + 1, 0))
			append(&handles, Villager{person, k, bed, works[k]})
			village_own(g, person, bed, "a bed of one's own")
		}
		/* the household's things, each of its people's */
		for v in handles[first:] {
			village_own(g, v.id, stove, "the household's stove")
			village_own(g, v.id, larder, "the household's larder")
			village_own(g, v.id, sack, "the household's grain")
			village_own(g, v.id, woodpile, "the household's woodpile")
			village_own(g, v.id, wood, "the household's firewood")
		}
		/* at the woods' edge, the woodcutters' trees, and an axe each by the block */
		if h.worksite == "chopping_block" {
			/* a wood north of the block, a tree every third tile, one in four
			 * a birch */
			n := 0
			for y := h.works.y - 3; y >= h.works.y - 15; y -= 3 {
				for x := h.works.x - 9; x <= h.works.x + 9; x += 3 {
					proposal_group_create(g, "birch" if n % 4 == 3 else "oak", "a tree", on_tile(x, y, 0))
					n += 1
				}
			}
			proposal_group_create(g, "axe", "an axe", on_tile(h.works.x - 1, h.works.y, 0))
			proposal_group_create(g, "axe", "an axe", on_tile(h.works.x + 1, h.works.y, 0))
		}
	}
	committer_submit(c, g)
	scheduler_run_until(self.scheduler, time_make(1))     /* each sees its worksite */
	for l, k in larders do self.larders[k] = proposal_group_id_for(g, l)
	for e, k in stoves do self.stoves[k] = proposal_group_id_for(g, e)
	for e, k in woodpiles do self.woodpiles[k] = proposal_group_id_for(g, e)
	for v in handles {
		append(&self.people, Villager{proposal_group_id_for(g, v.id), v.household, proposal_group_id_for(g, v.bed),
		                              proposal_group_id_for(g, v.worksite)})
	}

	/* then round its house: beside the larder (against the west wall), then
	 * the stove (the east), two to a tile's breadth */
	for stop, k in ([3]string{"woodpile", "larder", "stove"}) {
		tour := proposal_group_group_with_phase(.System, fmt.tprintf("setup: by the %s", stop))
		for v, i in self.people {
			h := households[v.household]
			switch k {
			case 0:
				/* on the side of it away from the house */
				y := h.woodpile.y + 1 if terrain_solid(world_terrain(self.world), h.woodpile.x, h.woodpile.y - 1, 0) else h.woodpile.y - 1
				proposal_group_move_to(tour, whole(v.id), on_tile(h.woodpile.x - 1 + i32(i % 2), y, 0))
			case 1: proposal_group_move_to(tour, whole(v.id), on_tile(h.larder.x + 1, h.larder.y - 1 + i32(i % 2), 0))
			case 2: proposal_group_move_to(tour, whole(v.id), on_tile(h.stove.x - 1, h.stove.y - 1 + i32(i % 2), 0))
			}
		}
		committer_submit(c, tour)
		scheduler_run_until(self.scheduler, time_make(2 + i64(k)))
	}

	/* then home, by its bed; and kin, each to each in a household */
	home := proposal_group_group_with_phase(.System, "setup: home for the night")
	for v in self.people {
		bed := world_location_of(self.world, v.bed)
		by  := bed.y + 1 if !terrain_solid(world_terrain(self.world), bed.x, bed.y + 1, 0) else bed.y - 1
		proposal_group_move_to(home, whole(v.id), on_tile(bed.x, by, 0))
		for w in self.people {
			if w.household != v.household || w.id == v.id do continue
			bond := proposal_group_create(home, "kin_bond", "kin", location_make_none())
			proposal_group_set_of_to(home, "Bond.bondOf", whole(bond), i64(v.id))
			proposal_group_set_of_to(home, "Bond.toward", whole(bond), i64(w.id))
		}
	}
	committer_submit(c, home)
	scheduler_run_until(self.scheduler, time_make(5))     /* and sees its bed */

	/* the day's commitments, every day, bound to its own bed and its work */
	for v in self.people {
		store := knowledge_store_of(self.knowledge, v.id)
		bed   := village_referent_of(store, v.bed)
		work  := village_referent_of(store, v.worksite)
		stove := village_referent_of(store, self.stoves[v.household])
		pile  := village_referent_of(store, self.woodpiles[v.household])
		if bed == 0 || work == 0 || stove == 0 || pile == 0 {
			self.error = fmt.aprintf("%d hasn't seen its %s", v.id,
			                         "bed" if bed == 0 else ("worksite" if work == 0 else ("stove" if stove == 0 else "woodpile")))
			return
		}
		ok := agency_undertake_every_with(self.agency, v.id, "be_at_work", 7 * VILLAGE_HOUR, 15 * VILLAGE_HOUR, "work",
		                                  VILLAGE_DAY, {{"worksite", work}}) &&
		      agency_undertake_every_with(self.agency, v.id, "be_home", 15 * VILLAGE_HOUR, 22 * VILLAGE_HOUR, "home",
		                                  VILLAGE_DAY, {{"bed", bed}}) &&
		      agency_undertake_every_with(self.agency, v.id, "sleep_in_bed", 22 * VILLAGE_HOUR, 30 * VILLAGE_HOUR, "home",
		                                  VILLAGE_DAY, {{"bed", bed}}) &&
		      agency_undertake_every_with(self.agency, v.id, "food_along", 6 * VILLAGE_HOUR, 7 * VILLAGE_HOUR, "work",
		                                  VILLAGE_DAY, {}) &&
		      agency_undertake_every_with(self.agency, v.id, "eat_supper", 18 * VILLAGE_HOUR, 21 * VILLAGE_HOUR, "home",
		                                  VILLAGE_DAY, {}) &&
		      agency_undertake_every_with(self.agency, v.id, "stove_stoked", 19 * VILLAGE_HOUR, 21 * VILLAGE_HOUR, "home",
		                                  VILLAGE_DAY, {{"stove", stove}}) &&
		      (households[v.household].worksite != "chopping_block" ||
		       agency_undertake_every_with(self.agency, v.id, "woodpile_stocked", 7 * VILLAGE_HOUR, 15 * VILLAGE_HOUR, "work",
		                                   VILLAGE_DAY, {{"woodpile", pile}}))
		if !ok {
			self.error = fmt.aprintf("%d couldn't take on its day", v.id)
			return
		}
	}
}


// An ownership claim of `owner`'s on `thing`.
@(private = "file")
village_own :: proc(g: ^Proposal_Group, owner: Entity_ID, thing: Entity_ID, why: cstring) {
	claim := proposal_group_create(g, "ownership", why, location_make_none())
	proposal_group_set_of_to(g, "Claim.quantity", whole(claim), 1)
	proposal_group_relate(g, .Claimant, whole(claim), whole(owner))
	proposal_group_relate(g, .Claim_Subject, whole(claim), whole(thing))
}


// The referent an agent has of an entity it has seen, or 0.
@(private = "file")
village_referent_of :: proc(store: ^Knowledge_Store, truth: Entity_ID) -> u32 {
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		if knowledge_store_referent_at(store, i).truth == truth do return knowledge_store_referent_at(store, i).id
	}
	return 0
}


village_world :: proc(self: ^Village) -> ^World {return self.world}
village_error :: proc(self: ^Village) -> string {return self.error}
village_results :: proc(self: ^Village) -> []string {return self.results[:]}


/* What the run cost (PERFORMANCE.md decision 6): the scheduler's counters,
 * and its minds' and walks'. Wall times differ run to run; the counts don't. */
village_counters :: proc(self: ^Village) -> []string {
	ms :: proc(ns: u64) -> f64 {return f64(ns) / 1e6}

	st    := scheduler_stats(self.scheduler)
	lines := make([dynamic]string, context.temp_allocator)
	append(&lines, fmt.tprintf("boundaries     %d", st.boundaries))
	append(&lines, fmt.tprintf("events         %d", world_event_count(self.world)))
	{
		digested: u64
		for d in world_digests(self.world) do digested += d.count
		append(&lines, fmt.tprintf("  kept         %d (digested %d, in %d digests)", len(world_history(self.world)), digested,
		                           len(world_digests(self.world))))
	}
	append(&lines, fmt.tprintf("perceptions    %d", knowledge_perceptions(self.knowledge)))
	append(&lines, fmt.tprintf("decisions      %d (minds woken)", self.agency.decisions))
	append(&lines, fmt.tprintf("deliberations  %d (not busy: choosing a way)", self.agency.deliberations))
	append(&lines, fmt.tprintf("path searches  %d", self.agency.pathSearches))
	append(&lines, fmt.tprintf("horizon        %.0f ms", ms(st.horizonNs)))
	append(&lines, fmt.tprintf("domains        %.0f ms", ms(st.domainsNs)))
	append(&lines, fmt.tprintf("commit         %.0f ms", ms(st.commitNs)))
	append(&lines, fmt.tprintf("perception     %.0f ms", ms(st.perceptionNs)))
	append(&lines, fmt.tprintf("  interpreting %.0f ms", ms(self.knowledge.interpretationNs)))
	append(&lines, fmt.tprintf("decision       %.0f ms", ms(st.decisionNs)))
	return lines[:]
}


village_failure_count :: proc(self: ^Village) -> uint {
	n: uint
	for r in self.results do if ns_has_prefix(r, "FAIL") do n += 1
	return n
}


/* Boundaries up to t, none put in: as a watcher runs it. */
village_step_until :: proc(self: ^Village, t: i64) {
	for scheduler_step_until(self.scheduler, time_make(t)) {}
}


/* Three days and nights, checked as they go. */
village_run :: proc(self: ^Village) {
	if self.error != "" {
		village_check(self, false, "set up", self.error)
		return
	}
	woodcutters := -1
	for h, k in households do if h.worksite == "chopping_block" do woodcutters = k
	stocked := village_firewood_in(self.world, self.woodpiles[woodcutters])
	for d in 0 ..< i64(VILLAGE_DAYS) {
		village_step_until(self, d * VILLAGE_DAY + 7 * VILLAGE_HOUR + VILLAGE_HOUR / 2)
		village_check_each(self, fmt.tprintf("day %d, 07:30: everyone takes a meal to work", d + 1), .Packed)
		village_step_until(self, d * VILLAGE_DAY + 11 * VILLAGE_HOUR)
		village_check_each(self, fmt.tprintf("day %d, 11:00: everyone at work", d + 1), .Work)
		village_step_until(self, d * VILLAGE_DAY + 14 * VILLAGE_HOUR + VILLAGE_HOUR / 2)
		village_check_each(self, fmt.tprintf("day %d, 14:30: everyone has eaten it there", d + 1), .Lunched)
		village_step_until(self, d * VILLAGE_DAY + 15 * VILLAGE_HOUR)
		now := village_firewood_in(self.world, self.woodpiles[woodcutters])
		village_check(self, now > stocked, fmt.tprintf("day %d, 15:00: the woodcutters' woodpile rose with their work", d + 1),
		              fmt.tprintf("%d pieces, %d before", now, stocked))
		stocked = now
		village_step_until(self, d * VILLAGE_DAY + 21 * VILLAGE_HOUR)
		village_check_each(self, fmt.tprintf("day %d, 21:00: everyone home", d + 1), .Home)
		village_step_until(self, (d + 1) * VILLAGE_DAY + 2 * VILLAGE_HOUR)
		village_check_each(self, fmt.tprintf("night %d, 02:00: everyone asleep in their own bed", d + 1), .Asleep)
		cold := make([dynamic]string, context.temp_allocator)
		for e, k in self.stoves {
			fuel: i64
			if !world_get_field(self.world, "FuelContainer.fuel", e, &fuel) || fuel <= 0 do append(&cold, households[k].name)
		}
		village_check(self, len(cold) == 0, fmt.tprintf("night %d, 02:00: every stove has fuel in it", d + 1),
		              fmt.tprintf("not: %s", strings.join(cold[:], ", ", context.temp_allocator)))
	}
	village_check_larders(self)
	hungry := make([dynamic]string, context.temp_allocator)
	for v in self.people {
		if reserves(hungry_of(self.world, v.id), world_time(self.world).ms) < 100 do append(&hungry, fmt.tprintf("%d", v.id))
	}
	village_check(self, len(hungry) == 0, "nobody went without: everyone's reserves are full",
	              fmt.tprintf("not: %s", strings.join(hungry[:], ", ", context.temp_allocator)))
}


/* What each household has taken from its larder, a portion at a time:
 * three to five portions a person a day, as many meals as it ate, and none
 * from another's. */
@(private = "file")
village_check_larders :: proc(self: ^Village) {
	people: [4]i64
	for v in self.people do people[v.household] += 1
	wrong := make([dynamic]string, context.temp_allocator)
	for l, k in self.larders {
		taken := VILLAGE_GRAIN - village_portions_in(self.world, l)
		if taken < 3 * people[k] * VILLAGE_DAYS || taken > 5 * people[k] * VILLAGE_DAYS {
			append(&wrong, fmt.tprintf("%s took %d", households[k].name, taken))
		}
	}
	village_check(self, len(wrong) == 0, "each household ate from its own larder, which emptied as it did",
	              strings.join(wrong[:], ", ", context.temp_allocator))
}


/* The pieces of firewood in a container. */
village_firewood_in :: proc(world: ^World, container: Entity_ID) -> i64 {
	inside: [16]Entity_ID
	total: i64
	n := world_entities_at(world, container, .In, raw_data(inside[:]), 16)
	for e in inside[:n] do if world_unit_of(world, e) == "firewood" do total += world_units_of(world, e)
	return total
}


/* The portions of grain in a container. */
village_portions_in :: proc(world: ^World, container: Entity_ID) -> i64 {
	inside: [16]Entity_ID
	count, total: i64
	n := world_entities_at(world, container, .In, raw_data(inside[:]), 16)
	for e in inside[:n] {
		if world_get_field(world, "Stack.count", e, &count) do total += count
	}
	return total
}


@(private = "file")
Where :: enum {
	Packed,
	Work,
	Lunched,
	Home,
	Asleep,
}

@(private = "file")
village_check_each :: proc(self: ^Village, name: string, where_: Where) {
	missing := make([dynamic]string, context.temp_allocator)
	for v in self.people {
		ok := false
		switch where_ {
		case .Packed:  ok = village_holds_meal(self.world, v.id) == 1
		case .Work:    ok = village_at_work(self, v)
		case .Lunched: ok = village_at_work(self, v) && village_holds_meal(self.world, v.id) == 0
		case .Home:    ok = village_within_reach(self.world, v.id, v.bed)
		case .Asleep:  ok = village_within_reach(self.world, v.id, v.bed) && village_asleep_in(self.world, v.id, v.bed)
		}
		if !ok do append(&missing, fmt.tprintf("%d", v.id))
	}
	why := "not: "
	for m, i in missing do why = fmt.tprintf("%s%s%s", why, ", " if i > 0 else "", m)
	village_check(self, len(missing) == 0, name, why)
}


// Whether a villager is at its work: about its worksite (within six
// tiles), or about its work: a woodcutter stocking its woodpile, in the
// woods or on its way home with firewood.
@(private = "file")
village_at_work :: proc(self: ^Village, v: Villager) -> bool {
	la := world_location_of(self.world, v.id)
	lw := world_location_of(self.world, v.worksite)
	if la.form == .On_Tile && lw.form == .On_Tile && la.level == lw.level && abs(la.x - lw.x) <= 6 && abs(la.y - lw.y) <= 6 {
		return true
	}
	return agency_intends(self.agency, v.id, "woodpile_stocked")
}


// How many meals (food, not raw) an agent holds.
@(private = "file")
village_holds_meal :: proc(world: ^World, agent: Entity_ID) -> int {
	held: [8]Entity_ID
	raw: i64
	meals := 0
	n := world_entities_at(world, agent, .Held_By, raw_data(held[:]), 8)
	for e in held[:n] {
		if world_get_field(world, "Food.raw", e, &raw) && raw == 0 do meals += 1
	}
	return meals
}


// Whether a's on the ground within reach of b's tile (beside it, corners
// too, or on it).
@(private = "file")
village_within_reach :: proc(world: ^World, a: Entity_ID, b: Entity_ID) -> bool {
	la := world_location_of(world, a)
	lb := world_location_of(world, b)
	return la.form == .On_Tile && lb.form == .On_Tile && la.level == lb.level && abs(la.x - lb.x) <= 1 &&
	       abs(la.y - lb.y) <= 1
}


// Whether an agent is sleeping now, in that bed: a sleep of its, running.
@(private = "file")
village_asleep_in :: proc(world: ^World, agent: Entity_ID, bed: Entity_ID) -> bool {
	n: uint
	ids := world_copy_activities_of(world, agent, &n)
	defer free(ids)
	kind := world_kind_named(world, "Activity")
	for i: uint = 0; i < n; i += 1 {
		a := (^Activity)(world_record(world, kind, ids[i]))
		if a != nil && string(a.operation) == "sleep" && Entity_ID(a.itemRef) == bed &&
		   string(tri.type_name(world_tri(world), tri.Type(a.status))) == "\"running\"" {
			return true
		}
	}
	return false
}


@(private = "file")
village_check :: proc(self: ^Village, ok: bool, name: string, why: string) {
	if ok {
		append(&self.results, fmt.aprintf("ok   %s", name))
	} else {
		append(&self.results, fmt.aprintf("FAIL %s: %s", name, why))
	}
}

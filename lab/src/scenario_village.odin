package lab

/*
 * The village (VILLAGE.md, slice 3; content/village/village.tri): four
 * households, twelve people, on a map of 160 by 100, living out the day's
 * commitments (content/home/home.tri): to work from 07:00 to 15:00, home
 * from 15:00 to 22:00, and a night's sleep in one's own bed from 22:00.
 * What the work is comes with later slices; for now each works by being at
 * the household's worksite.
 *
 * Each has seen its worksite and its home before the first morning:
 * set down by its worksite for the first boundary, then by its bed for
 * the second, so both are in what it knows when its commitments are
 * undertaken, bound to them. Its sight is four tiles: the rest of the way it
 * finds as it walks.
 *
 * The run goes boundary by boundary up to each check's time, putting none
 * in of its own (as the watcher runs it), so `lab run village` and a
 * watched village are the same run. The checks, for three days and nights:
 * everyone at work at 11:00, home by 21:00, asleep in their own bed at
 * 02:00.
 */

import "core:fmt"
import tri "../../triangle/odin/triangle"


VILLAGE_DAY :: i64(86400000)
VILLAGE_HOUR :: i64(3600000)
VILLAGE_DAYS :: 3

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

@(private = "file", rodata)
BLANKETS := [12]string{"red", "yellow", "blue", "green", "purple", "orange", "black", "grey", "brown", "navy", "white", "beige"}

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
	people:       [dynamic]Villager,
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
	self.scheduler  = scheduler_init_with_world(world, committer)
	agency_set_activities(self.agency, self.activities)
	scheduler_add_domain(self.scheduler, bodies_as_domain(self.bodies))
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
	works: [4]Entity_ID
	for &h, k in households {
		works[k] = proposal_group_create(g, h.worksite, ns_utf8(fmt.tprintf("%s' worksite", h.name)),
		                                 on_tile(h.works.x, h.works.y, 0))
		proposal_group_create(g, "stove", ns_utf8(fmt.tprintf("%s' stove", h.name)), on_tile(h.stove.x, h.stove.y, 0))
		larder := proposal_group_create(g, "larder", ns_utf8(fmt.tprintf("%s' larder", h.name)),
		                                on_tile(h.larder.x, h.larder.y, 0))
		woodpile := proposal_group_create(g, "woodpile", ns_utf8(fmt.tprintf("%s' woodpile", h.name)),
		                                  on_tile(h.woodpile.x, h.woodpile.y, 0))
		first := len(handles)
		for i in 0 ..< h.people {
			bed := proposal_group_create(g, "bed", ns_utf8(fmt.tprintf("%s' bed %d", h.name, i)),
			                             on_tile(h.beds[i].x, h.beds[i].y, 0))
			/* each blanket a colour of its own, in the whole village */
			blanket := tri.type_named(world_tri(self.world), ns_utf8(fmt.tprintf("\"%s\"", BLANKETS[len(handles)])))
			proposal_group_set_of_to(g, "Bed.blanket", whole(bed), i64(blanket))
			/* first, by the worksite, a tile apart from each other */
			person := proposal_group_create(g, h.trade, ns_utf8(fmt.tprintf("%s, %d", h.name, i)),
			                                on_tile(h.works.x - 1 + i32(i), h.works.y + 1, 0))
			append(&handles, Villager{person, k, bed, works[k]})
			village_own(g, person, bed, "a bed of one's own")
		}
		/* the household's things, its eldest's */
		village_own(g, handles[first].id, larder, "the household's larder")
		village_own(g, handles[first].id, woodpile, "the household's woodpile")
	}
	committer_submit(c, g)
	scheduler_run_until(self.scheduler, time_make(1))     /* each sees its worksite */
	for v in handles {
		append(&self.people, Villager{proposal_group_id_for(g, v.id), v.household, proposal_group_id_for(g, v.bed),
		                              proposal_group_id_for(g, v.worksite)})
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
	scheduler_run_until(self.scheduler, time_make(2))     /* and sees its home */

	/* the day's commitments, every day, bound to its own bed and its work */
	for v in self.people {
		store := knowledge_store_of(self.knowledge, v.id)
		bed   := village_referent_of(store, v.bed)
		work  := village_referent_of(store, v.worksite)
		if bed == 0 || work == 0 {
			self.error = fmt.aprintf("%d hasn't seen its %s", v.id, "bed" if bed == 0 else "worksite")
			return
		}
		ok := agency_undertake_every_with(self.agency, v.id, "be_at_work", 7 * VILLAGE_HOUR, 15 * VILLAGE_HOUR, "work",
		                                  VILLAGE_DAY, {{"worksite", work}}) &&
		      agency_undertake_every_with(self.agency, v.id, "be_home", 15 * VILLAGE_HOUR, 22 * VILLAGE_HOUR, "home",
		                                  VILLAGE_DAY, {{"bed", bed}}) &&
		      agency_undertake_every_with(self.agency, v.id, "sleep_in_bed", 22 * VILLAGE_HOUR, 30 * VILLAGE_HOUR, "home",
		                                  VILLAGE_DAY, {{"bed", bed}})
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
	for d in 0 ..< i64(VILLAGE_DAYS) {
		village_step_until(self, d * VILLAGE_DAY + 11 * VILLAGE_HOUR)
		village_check_each(self, fmt.tprintf("day %d, 11:00: everyone at work", d + 1), .Work)
		village_step_until(self, d * VILLAGE_DAY + 21 * VILLAGE_HOUR)
		village_check_each(self, fmt.tprintf("day %d, 21:00: everyone home", d + 1), .Home)
		village_step_until(self, (d + 1) * VILLAGE_DAY + 2 * VILLAGE_HOUR)
		village_check_each(self, fmt.tprintf("night %d, 02:00: everyone asleep in their own bed", d + 1), .Asleep)
	}
}


@(private = "file")
Where :: enum {
	Work,
	Home,
	Asleep,
}

@(private = "file")
village_check_each :: proc(self: ^Village, name: string, where_: Where) {
	missing := make([dynamic]string, context.temp_allocator)
	for v in self.people {
		ok := false
		switch where_ {
		case .Work:   ok = village_within_reach(self.world, v.id, v.worksite)
		case .Home:   ok = village_within_reach(self.world, v.id, v.bed)
		case .Asleep: ok = village_within_reach(self.world, v.id, v.bed) && village_asleep_in(self.world, v.id, v.bed)
		}
		if !ok do append(&missing, fmt.tprintf("%d", v.id))
	}
	why := "not: "
	for m, i in missing do why = fmt.tprintf("%s%s%s", why, ", " if i > 0 else "", m)
	village_check(self, len(missing) == 0, name, why)
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

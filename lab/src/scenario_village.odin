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
 * The farmers tend their plots (content/farming/), each household's tilled
 * block two of them, a farmer to one, with seed kept back in the larder: all
 * sown the first day, ripe a fortnight on.
 *
 * The hunters hunt the eastern woods (content/hunting/), bows in hand: lying
 * in wait, stalking what they see, butchering what they shoot, and bringing
 * the meat home, until the larder holds two deer's worth. Deer and hares
 * roam there and run from people they see; the herds are kept up from the
 * east edge, six deer and four hares at most (the game domain).
 *
 * The run goes boundary by boundary up to each check's time, putting none
 * in of its own (as the watcher runs it), so `lab run village` and a
 * watched village are the same run. The checks, for three days and nights:
 * everyone taking a meal to work at 07:30, at work at 11:00 (about its
 * worksite, or about its work: a woodcutter in the woods, or on its way
 * home with firewood; a hunter on the hunt), the meal
 * eaten there by 14:30, every plot sown by 15:00 the first day, home by
 * 21:00, asleep in their own bed at 02:00, and the game bedded down;
 * and at the end, each household's larder emptied by what it ate, meat in
 * the hunters' larder, the herds alive and within their bounds, and
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

/* The farmers' plots (VILLAGE.md: the Ashes two of grain, the Brooks
 * grain and turnips): each household's tilled block, halved east of the
 * other's west. */
@(private = "file")
Village_Plot :: struct {
	household: int,
	blueprint: cstring,
	corner:    [2]i32,
	east:      i32,
	south:     i32,
}

@(private = "file", rodata)
village_plots := [4]Village_Plot {
	{0, "grain_plot", {22, 76}, 14, 17},
	{0, "grain_plot", {36, 76}, 15, 17},
	{1, "grain_plot", {62, 76}, 17, 17},
	{1, "turnip_plot", {79, 76}, 18, 17},
}

/* The game in the eastern woods at the start (content/hunting/): deer and
 * hares about the Hunts' blind. */
@(private = "file")
Village_Game :: struct {
	blueprint: cstring,
	at:        [2]i32,
}

@(private = "file", rodata)
village_game := [7]Village_Game {
	{"deer", {142, 35}}, {"deer", {150, 52}}, {"deer", {140, 68}}, {"deer", {153, 80}},
	{"hare", {146, 42}}, {"hare", {138, 58}}, {"hare", {151, 64}},
}

/* The seed each household keeps back, by blueprint (village.tri). */
@(private = "file", rodata)
village_seed := [4][2]cstring {
	{"ashes_seed", ""},
	{"brooks_seed", "brooks_turnip_seed"},
	{"", ""},
	{"", ""},
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
	farming:      ^Farming,          // ripens the crops
	game:         ^Game,             // keeps the herds up
	people:       [dynamic]Villager,
	larders:      [4]Entity_ID,      // each household's, by its index
	stoves:       [4]Entity_ID,
	woodpiles:    [4]Entity_ID,
	plots:        [4][dynamic]Entity_ID,  // each farming household's
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
	self.farming    = farming_init_with_world(world)
	self.game       = game_init_with_world(world)
	self.scheduler  = scheduler_init_with_world(world, committer)
	/* a diagnostic event is kept a day, then counted (KNOWLEDGE.md decision 21) */
	world_set_history_window(world, 86400000)
	agency_set_activities(self.agency, self.activities)
	scheduler_add_domain(self.scheduler, bodies_as_domain(self.bodies))
	scheduler_add_domain(self.scheduler, atmosphere_as_domain(self.air))
	scheduler_add_domain(self.scheduler, farming_as_domain(self.farming))
	scheduler_add_domain(self.scheduler, game_as_domain(self.game))
	/* the herds of the eastern woods, kept up from the east edge (VILLAGE.md
	 * decision 7): six deer at most, four hares, one a quarter-day */
	edge := [][2]i32{{159, 20}, {159, 45}, {159, 70}, {159, 90}}
	game_add_herd(self.game, "deer", 6, 6 * VILLAGE_HOUR, 6 * VILLAGE_HOUR, edge)
	game_add_herd(self.game, "hare", 4, 6 * VILLAGE_HOUR, 6 * VILLAGE_HOUR, edge)
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
	release(self.farming)
	release(self.game)
	delete(self.people)
	for list in self.plots do delete(list)
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
	self_plots: [4][dynamic]Entity_ID
	for &h, k in households {
		works[k] = proposal_group_create(g, h.worksite, ns_utf8(fmt.tprintf("%s' worksite", h.name)),
		                                 on_tile(h.works.x, h.works.y, 0))
		stove := proposal_group_create(g, "stove", ns_utf8(fmt.tprintf("%s' stove", h.name)), on_tile(h.stove.x, h.stove.y, 0))
		stoves[k] = stove
		larder := proposal_group_create(g, "larder", ns_utf8(fmt.tprintf("%s' larder", h.name)),
		                                on_tile(h.larder.x, h.larder.y, 0))
		larders[k] = larder
		sack := proposal_group_create(g, "grain_sack", ns_utf8(fmt.tprintf("%s' grain", h.name)), in_(larder))
		/* the farmers' plots, their tilled block halved, and the seed kept
		 * back for them (village.tri) */
		seeds := make([dynamic]Entity_ID, context.temp_allocator)
		plots := make([dynamic]Entity_ID, context.temp_allocator)
		for pl in village_plots do if pl.household == k {
			plot := proposal_group_create(g, pl.blueprint, ns_utf8(fmt.tprintf("%s' plot at %d", h.name, pl.corner.x)),
			                              on_tile(pl.corner.x, pl.corner.y, 0))
			proposal_group_set_of_to(g, "Area.east", whole(plot), i64(pl.east))
			proposal_group_set_of_to(g, "Area.south", whole(plot), i64(pl.south))
			append(&plots, plot)
		}
		for blueprint in village_seed[k] do if blueprint != "" {
			append(&seeds, proposal_group_create(g, blueprint, ns_utf8(fmt.tprintf("%s' %s", h.name, blueprint)), in_(larder)))
		}
		for plot in plots do append(&self_plots[k], plot)
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
			/* a hunter's bow, in hand */
			if h.worksite == "hunting_blind" do proposal_group_create(g, "bow", "a bow", held_by(person, 0))
		}
		/* the household's things, each of its people's */
		for v in handles[first:] {
			village_own(g, v.id, stove, "the household's stove")
			village_own(g, v.id, larder, "the household's larder")
			village_own(g, v.id, sack, "the household's grain")
			village_own(g, v.id, woodpile, "the household's woodpile")
			village_own(g, v.id, wood, "the household's firewood")
			for seed in seeds do village_own(g, v.id, seed, "the household's seed")
			for plot in plots do village_own(g, v.id, plot, "the household's plot")
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
		/* about the hunting blind, the eastern woods' game */
		if h.worksite == "hunting_blind" {
			for at in village_game do proposal_group_create(g, at.blueprint, at.blueprint, on_tile(at.at.x, at.at.y, 0))
		}
	}
	committer_submit(c, g)
	scheduler_run_until(self.scheduler, time_make(1))     /* each sees its worksite */
	for l, k in larders do self.larders[k] = proposal_group_id_for(g, l)
	for e, k in stoves do self.stoves[k] = proposal_group_id_for(g, e)
	for e, k in woodpiles do self.woodpiles[k] = proposal_group_id_for(g, e)
	for &list, k in self_plots {
		for e in list do append(&self.plots[k], proposal_group_id_for(g, e))
		delete(list)
	}
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
	farmer_index: [4]int
	for v in self.people {
		store := knowledge_store_of(self.knowledge, v.id)
		bed   := village_referent_of(store, v.bed)
		work  := village_referent_of(store, v.worksite)
		stove := village_referent_of(store, self.stoves[v.household])
		pile  := village_referent_of(store, self.woodpiles[v.household])
		larder := village_referent_of(store, self.larders[v.household])
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
		                                   VILLAGE_DAY, {{"woodpile", pile}})) &&
		      (households[v.household].worksite != "hunting_blind" ||
		       agency_undertake_every_with(self.agency, v.id, "game_hunted", 7 * VILLAGE_HOUR, 15 * VILLAGE_HOUR, "work",
		                                   VILLAGE_DAY, {{"larder", larder}}))
		/* a farmer's plot: one of its household's, by turns (the Ashes' three
		 * over their two, two Brooks to each of theirs), so it carries one
		 * kind of seed; bound to the plot as it knows it, and the household's
		 * larder, where its seed is kept */
		if plots := self.plots[v.household][:]; len(plots) > 0 {
			known := village_referent_of(store, plots[farmer_index[v.household] % len(plots)])
			farmer_index[v.household] += 1
			ok = ok && known != 0 &&
			     agency_undertake_every_with(self.agency, v.id, "plot_tended", 7 * VILLAGE_HOUR, 15 * VILLAGE_HOUR, "work",
			                                 VILLAGE_DAY, {{"plot", known}, {"larder", larder}})
		}
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
	woodcutters, hunters := -1, -1
	for h, k in households do if h.worksite == "chopping_block" do woodcutters = k
	for h, k in households do if h.worksite == "hunting_blind" do hunters = k
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
		if d == 0 {
			/* the farmers' work: every plot sown the first day, growing */
			bare := make([dynamic]string, context.temp_allocator)
			for list, k in self.plots {
				for plot in list do if plot_of(self.world, plot).stands != plot_stands(self.world, "sown") {
					append(&bare, fmt.tprintf("%s' at %d", households[k].name, world_location_of(self.world, plot).x))
				}
			}
			village_check(self, len(bare) == 0, "day 1, 15:00: the farmers sowed every plot",
			              fmt.tprintf("not: %s", strings.join(bare[:], ", ", context.temp_allocator)))
		}
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
		awake := village_game_awake(self)
		village_check(self, len(awake) == 0, fmt.tprintf("night %d, 02:00: the game bedded down", d + 1),
		              fmt.tprintf("not: %s", strings.join(awake[:], ", ", context.temp_allocator)))
	}
	village_check_larders(self)
	/* the hunters' work: meat brought home; the game kept up (VILLAGE.md
	 * decision 7) */
	meat: i64
	inside: [16]Entity_ID
	for e in inside[:world_entities_at(self.world, self.larders[hunters], .In, raw_data(inside[:]), 16)] {
		if u := world_unit_of(self.world, e); u != nil && (u == "venison" || u == "hare meat") do meat += world_units_of(self.world, e)
	}
	village_check(self, meat > 0, "the hunters brought meat home", "none in their larder")
	deer, hares := game_count(self.world, "deer"), game_count(self.world, "hare")
	village_check(self, deer >= 1 && deer <= 6 && hares >= 1 && hares <= 4, "the herds neither vanished nor outgrew the woods",
	              fmt.tprintf("%d deer, %d hares", deer, hares))
	hungry := make([dynamic]string, context.temp_allocator)
	for v in self.people {
		if reserves(hungry_of(self.world, v.id), world_time(self.world).ms) < 100 do append(&hungry, fmt.tprintf("%d", v.id))
	}
	village_check(self, len(hungry) == 0, "nobody went without: everyone's reserves are full",
	              fmt.tprintf("not: %s", strings.join(hungry[:], ", ", context.temp_allocator)))
}


/* The deer and hares not lying up (content/hunting/animals.tri's bed_down
 * under way), by ID. */
@(private = "file")
village_game_awake :: proc(self: ^Village) -> [dynamic]string {
	awake := make([dynamic]string, context.temp_allocator)
	lying := make(map[Entity_ID]bool, context.temp_allocator)
	running := u32(tri.type_named(world_tri(self.world), "\"running\""))
	activities := world_store_for_kind(self.world, world_kind_named(self.world, "Activity"))
	for i: uint = 0; i < store_count(activities); i += 1 {
		a := (^Activity)(store_record_at_index(activities, i))
		op := world_text_field(self.world, "Activity.operation", store_entity_at_index(activities, i))
		if a.status == running && op != nil && op == "bed_down" do lying[Entity_ID(a.actorRef)] = true
	}
	agents := world_store_for_kind(self.world, world_kind_named(self.world, "Agent"))
	for i: uint = 0; i < store_count(agents); i += 1 {
		e := store_entity_at_index(agents, i)
		info := world_info(self.world, e)
		if info == nil || (info.blueprint != "deer" && info.blueprint != "hare") || e in lying do continue
		append(&awake, fmt.tprintf("%d", e))
	}
	return awake
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


/* The portions of grain in a container (not the seed grain kept there). */
village_portions_in :: proc(world: ^World, container: Entity_ID) -> i64 {
	inside: [16]Entity_ID
	total: i64
	n := world_entities_at(world, container, .In, raw_data(inside[:]), 16)
	for e in inside[:n] do if world_unit_of(world, e) == "grain" do total += world_units_of(world, e)
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
	return agency_intends(self.agency, v.id, "woodpile_stocked") || agency_intends(self.agency, v.id, "plot_tended") ||
	       agency_intends(self.agency, v.id, "game_hunted")
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

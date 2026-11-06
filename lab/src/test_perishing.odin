package lab

/*
 * Perishing (VILLAGE.md decision 8, slice 8; content/perishing/): meat
 * keeps three days from when it is made, then is spoiled food, as heavy,
 * where it was, across a gap of days with nothing stepped; grain keeps. Put
 * with fresher meat, the two spoil at their times averaged by mass. A meal keeps two
 * days from when it is cooked, whatever it was made of. Spoiled food can't
 * be eaten, and rots away ten days on. A carcass left lying two days is
 * carrion.
 */

import "core:fmt"


test_perishing :: proc() {
	DAY :: i64(86400000)
	error: string

	w := test_world(114)
	c := test_committer(w)
	activities := activities_with_world(w, c)
	s          := autorelease(scheduler_init_with_world(w, c))
	perishing  := autorelease(perishing_init_with_world(w))
	scheduler_add_domain(s, perishing_as_domain(perishing))
	scheduler_set_activities(s, activities_as_activity_clock(activities))

	g := proposal_group_group_with_phase(.System, "setup: a cook, a larder with meat and a sack of grain, a stove")
	cook   := proposal_group_create(g, "farmer", "the cook", on_tile(5, 5, 0))
	larder := proposal_group_create(g, "larder", "the larder", on_tile(6, 5, 0))
	stove  := proposal_group_create(g, "stove", "the stove", on_tile(5, 6, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1))
	cook, larder, stove = proposal_group_id_for(g, cook), proposal_group_id_for(g, larder), proposal_group_id_for(g, stove)
	g = proposal_group_group_with_phase(.System, "setup: meat and grain in the larder")
	meat := proposal_group_create(g, "venison", "the meat", in_(larder))
	sack := proposal_group_create(g, "grain_sack", "the sack", in_(larder))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(1000))
	meat, sack = proposal_group_id_for(g, meat), proposal_group_id_for(g, sack)

	/* a gap of days: the meat keeps three from when it was made, and
	 * nothing is stepped */
	boundaries := world_boundary(w)
	spoils: i64
	bg_check(world_get_field(w, "Perishable.spoilsAt", meat, &spoils) && spoils > 3 * DAY && spoils <= 3 * DAY + 1000)
	scheduler_run_until(s, time_make(spoils - 1))
	bg_check(world_is_live(w, meat))
	scheduler_run_until(s, time_make(spoils))
	bg_check(!world_is_live(w, meat))
	spoiled := test_perishing_spoiled_in(w, larder)
	bg_check(spoiled != NO_ENTITY && world_mass_of(w, spoiled) == 500)
	scheduler_run_until(s, time_make(10 * DAY))
	bg_check(world_is_live(w, sack) && world_get_field(w, "Perishable.spoilsAt", sack, &spoils) && spoils == 0)
	if world_boundary(w) - boundaries > 4 do fmt.printf("    %d boundaries over ten days\n", world_boundary(w) - boundaries)
	bg_check(world_boundary(w) - boundaries <= 4)

	/* spoiled, it isn't food: it can't be eaten */
	g = proposal_group_group_with_phase(.System, "setup: the spoiled meat in hand")
	proposal_group_move_to(g, whole(spoiled), held_by(cook, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(world_time(w).ms + 1))
	bg_check(perform(w, c, action_make("eat", cook, spoiled, NO_ENTITY), 0, &error) == nil)
	g = proposal_group_group_with_phase(.System, "setup: the spoiled meat thrown out")
	proposal_group_move_to(g, whole(spoiled), on_tile(9, 9, 0))
	committer_submit(c, g)
	rots: i64     /* ten days after it spoiled */
	bg_check(world_get_field(w, "Perishable.spoilsAt", spoiled, &rots) && rots > 13 * DAY && rots <= 13 * DAY + 2000)

	/* older meat put with as much fresher: both spoil halfway between */
	g = proposal_group_group_with_phase(.System, "setup: a cut of meat on the floor, at day 10")
	older := proposal_group_create(g, "venison", "a cut", on_tile(6, 6, 0))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(10 * DAY + 100))
	older = proposal_group_id_for(g, older)
	olderSpoils: i64
	bg_check(world_get_field(w, "Perishable.spoilsAt", older, &olderSpoils) && olderSpoils > 13 * DAY && olderSpoils <= 13 * DAY + 100)
	scheduler_run_until(s, time_make(11 * DAY))
	g = proposal_group_group_with_phase(.System, "setup: fresh meat in the larder, a day on")
	fresh := proposal_group_create(g, "venison", "the fresh meat", in_(larder))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(11 * DAY + 100))
	fresh = proposal_group_id_for(g, fresh)
	freshSpoils: i64
	bg_check(world_get_field(w, "Perishable.spoilsAt", fresh, &freshSpoils) && freshSpoils > olderSpoils + DAY - 200)
	g = proposal_group_group_with_phase(.System, "setup: the older cut put in with it")
	proposal_group_move_to(g, whole(older), in_(larder))
	committer_submit(c, g)
	scheduler_run_until(s, time_make(11 * DAY + 200))
	bg_check(!world_is_live(w, older) && world_units_of(w, fresh) == 2)
	both := (olderSpoils + freshSpoils) / 2
	bg_check(world_get_field(w, "Perishable.spoilsAt", fresh, &spoils) && spoils == both)
	scheduler_run_until(s, time_make(both - 1))
	bg_check(world_is_live(w, fresh))
	scheduler_run_until(s, time_make(both))
	bg_check(!world_is_live(w, fresh))

	/* a meal: grain keeps, but cooked it keeps two days from then */
	g = perform(w, c, action_make("take_some", cook, sack, NO_ENTITY), 1, &error)
	bg_check(g != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	held: [2]Entity_ID
	portion := NO_ENTITY
	for e in held[:world_entities_at(w, cook, .Held_By, raw_data(held[:]), 2)] do portion = e
	bg_check(portion != NO_ENTITY && world_get_field(w, "Perishable.spoilsAt", portion, &spoils) && spoils == 0)
	bg_check(perform(w, c, action_make("light", cook, stove, NO_ENTITY), 0, &error) != nil)
	scheduler_run_until(s, time_make(world_time(w).ms + 1000))
	error = ""
	if perform(w, c, action_make("cook", cook, portion, stove), 0, &error) == nil do fmt.printf("    cook: %s\n", error)
	scheduler_run_until(s, time_make(world_time(w).ms + 1200 * 1000 + 1))
	raw: i64
	cooked := world_time(w).ms
	bg_check(world_get_field(w, "Food.raw", portion, &raw) && raw == 0)
	bg_check(world_get_field(w, "Perishable.spoilsAt", portion, &spoils) && spoils > cooked - 1000 && spoils <= cooked + 2 * DAY)
	scheduler_run_until(s, time_make(spoils - 1))
	bg_check(world_is_live(w, portion))
	scheduler_run_until(s, time_make(spoils))
	bg_check(!world_is_live(w, portion) && world_is_live(w, sack))

	/* the spoiled meat thrown out has rotted away, ten days after it spoiled */
	bg_check(world_time(w).ms > rots && !world_is_live(w, spoiled))

	/* a carcass left two days is carrion, as heavy */
	g = proposal_group_group_with_phase(.System, "setup: a carcass left lying")
	carcass := proposal_group_create(g, "deer_carcass", "the carcass", on_tile(8, 8, 0))
	committer_submit(c, g)
	left := world_time(w).ms + 1
	scheduler_run_until(s, time_make(left))
	carcass = proposal_group_id_for(g, carcass)
	scheduler_run_until(s, time_make(left + 2 * DAY - 2))
	bg_check(world_is_live(w, carcass))
	scheduler_run_until(s, time_make(left + 2 * DAY))
	bg_check(!world_is_live(w, carcass))
	found := false
	bodies := world_store_for_kind(w, world_kind_named(w, "Body"))
	for i: uint = 0; i < store_count(bodies); i += 1 {
		e := store_entity_at_index(bodies, i)
		if info := world_info(w, e); info != nil && info.blueprint == "carrion" && world_is_live(w, e) {
			at := world_location_of(w, e)
			found = at.x == 8 && at.y == 8 && world_mass_of(w, e) == 60000
		}
	}
	bg_check(found)
}


/* Spoiled food in the container, the lowest ID; NO_ENTITY if none. */
@(private = "file")
test_perishing_spoiled_in :: proc(w: ^World, container: Entity_ID) -> Entity_ID {
	inside: [16]Entity_ID
	for e in inside[:world_entities_at(w, container, .In, raw_data(inside[:]), len(inside))] {
		if info := world_info(w, e); info != nil && info.blueprint == "spoiled_food" do return e
	}
	return NO_ENTITY
}

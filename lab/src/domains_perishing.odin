package lab

// BGPerishing — what becomes something else when its time comes, in closed
// form (VILLAGE.md decision 8; content/perishing/'s #Becoming): a thing
// that keeps so long (`Becoming.keepsFor` more than 0: meat, a carcass,
// spoiled food) spoils at `Becoming.becomesAt`, a time set as it is made,
// never stepped. One made at the last boundary is stamped here, as the
// domain next advances: it was made at t0, so its time is t0 + keepsFor.
// A time may be set by what starts it instead: a meal's by cooking. A
// thing may have another course in a kind of place (`within`: a hide in a
// tan pit, content/tanning/): come to lie there, or out of it again, its
// time starts over, with how long it keeps there, noticed as a thing made
// is: as the domain next advances, it was moved at t0. The horizon is the
// next thing whose time comes; at it, the thing becomes what it becomes
// where it lies (`become`: as heavy, where it was), its end recorded as
// its ending there, or with none rots away to nothing. Nothing happens
// between.


Perishing :: struct {
	using object: Object,
	world:        ^World,
}


perishing_init_with_world :: proc(world: ^World) -> ^Perishing {
	self := object_new(Perishing, perishing_dealloc)
	self.world = retain(world)
	return self
}


perishing_dealloc :: proc(self: ^Perishing) {
	release(self.world)
}


@(private = "file")
perishing_foods :: proc(self: ^Perishing) -> ^Store {
	return world_store_for_kind(self.world, world_kind_named(self.world, "Becoming"))
}


// Whether a thing lies in the kind of place its other course is in
// (`within`: a kind of container, by its type's name): directly in one.
perishing_lies_within :: proc(world: ^World, e: Entity_ID, food: ^Becoming) -> bool {
	if food.within == nil || len(food.within) == 0 do return false
	at := world_location_of(world, e)
	if at.form != .In do return false
	return world_is_a(world, at.place, food.within)
}


// When a thing's time comes, read at t: its time; or t and how long it
// keeps (where it lies), for one not yet stamped (made at t), and for one
// that has come to lie in the place of its other course, or out of it
// (moved at t): its time starts over. 0 for one that keeps.
perishing_time_of :: proc(world: ^World, e: Entity_ID, food: ^Becoming, t: i64) -> i64 {
	inside := perishing_lies_within(world, e, food)
	if inside != food.liesWithin || food.becomesAt == 0 {
		keeps := food.keepsWithin if inside else food.keepsFor
		return t + keeps if keeps > 0 else 0
	}
	return food.becomesAt
}


// The next thing whose time comes.
perishing_horizon_at :: proc(self: ^Perishing, t: Time) -> Horizon {
	h: Horizon

	h.safeStep  = TIME_NEVER
	h.nextEvent = TIME_NEVER
	foods := perishing_foods(self)
	for i: uint = 0; i < store_count(foods); i += 1 {
		at := perishing_time_of(self.world, store_entity_at_index(foods, i), (^Becoming)(store_record_at_index(foods, i)), t.ms)
		if at > t.ms && at < h.nextEvent.ms do h.nextEvent = time_make(at)
	}
	return h
}


// What was made at t0 stamped with its time, and what was moved into the
// place of its other course, or out of it, with its time there; what has
// come to its time by t1 become what it becomes where it lies, or rotted
// away. In ID order.
perishing_advance_from :: proc(self: ^Perishing, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	group: ^Proposal_Group

	foods := perishing_foods(self)
	for i: uint = 0; i < store_count(foods); i += 1 {
		food := (^Becoming)(store_record_at_index(foods, i))
		e    := store_entity_at_index(foods, i)
		if !world_is_live(world, e) || !world_is_physical(world, e) do continue
		inside := perishing_lies_within(world, e, food)
		at     := perishing_time_of(world, e, food, t0.ms)
		if at == food.becomesAt && inside == food.liesWithin && (at == 0 || at > t1.ms) do continue
		if group == nil do group = proposal_group_group_with_phase(.Process, "perishing: made, moved, and become")
		becomes := food.becomesWithin if inside else food.becomes
		ending  := food.endingWithin if inside else food.ending
		if at != 0 && at <= t1.ms && (becomes == nil || len(becomes) == 0) {
			proposal_group_destroy(group, whole(e), "rotted away")   /* its mass gone with it */
		} else if at != 0 && at <= t1.ms {
			become(world, group, e, becomes, ending if ending != nil && len(ending) > 0 else "spoiled")
		} else {
			if at != food.becomesAt do proposal_group_set_of_to(group, "Becoming.becomesAt", whole(e), at)
			if inside != food.liesWithin do proposal_group_set_of_to(group, "Becoming.liesWithin", whole(e), 1 if inside else 0)
		}
	}
	if group != nil do committer_submit(committer, group)
}


perishing_as_domain :: proc(self: ^Perishing) -> Domain {
	return Domain{
		data                = self,
		name                = proc(data: rawptr) -> string {return "perishing"},
		check_in_all        = proc(data: rawptr) {},
		saved_state         = proc(data: rawptr) -> []string {return make([]string, 0, context.temp_allocator)},
		restore_saved_state = proc(data: rawptr, lines: []string) {},
		is_active           = proc(data: rawptr) -> bool {return store_count(perishing_foods((^Perishing)(data))) > 0},
		horizon_at          = proc(data: rawptr, t: Time) -> Horizon {return perishing_horizon_at((^Perishing)(data), t)},
		advance_from        = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
			perishing_advance_from((^Perishing)(data), t0, t1, world, committer)
		},
	}
}

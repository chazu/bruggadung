package lab

// BGPerishing — what becomes something else when its time comes, in closed
// form (VILLAGE.md decision 8; content/perishing/'s #Becoming): a thing
// that keeps so long (`Becoming.keepsFor` more than 0: meat, a carcass,
// spoiled food) spoils at `Becoming.becomesAt`, a time set as it is made,
// never stepped. One made at the last boundary is stamped here, as the
// domain next advances: it was made at t0, so its time is t0 + keepsFor.
// A time may be set by what starts it instead: a meal's by cooking, a
// hide's by laying it in the tan (content/tanning/). The horizon is the
// next thing whose time comes; at it, the thing becomes its `becomes`
// (`become`: as heavy, where it was), its end recorded as its `ending`, or
// with none rots away to nothing. Nothing happens between.


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


// When a thing spoils, read at t: its time, or for a perishable one not yet
// stamped (made at t), t + keepsFor; 0 for one that keeps.
perishing_spoils_at :: proc(food: ^Becoming, t: i64) -> i64 {
	if food.becomesAt > 0 do return food.becomesAt
	if food.keepsFor > 0 do return t + food.keepsFor
	return 0
}


// The next food to spoil.
perishing_horizon_at :: proc(self: ^Perishing, t: Time) -> Horizon {
	h: Horizon

	h.safeStep  = TIME_NEVER
	h.nextEvent = TIME_NEVER
	foods := perishing_foods(self)
	for i: uint = 0; i < store_count(foods); i += 1 {
		at := perishing_spoils_at((^Becoming)(store_record_at_index(foods, i)), t.ms)
		if at > t.ms && at < h.nextEvent.ms do h.nextEvent = time_make(at)
	}
	return h
}


// What was made at t0 stamped with when it spoils; what has come to its
// time by t1, spoiled, or rotted away. In ID order.
perishing_advance_from :: proc(self: ^Perishing, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	group: ^Proposal_Group

	foods := perishing_foods(self)
	for i: uint = 0; i < store_count(foods); i += 1 {
		food := (^Becoming)(store_record_at_index(foods, i))
		e    := store_entity_at_index(foods, i)
		at   := perishing_spoils_at(food, t0.ms)
		if at == 0 || (at > t1.ms && food.becomesAt != 0) || !world_is_live(world, e) || !world_is_physical(world, e) do continue
		if group == nil do group = proposal_group_group_with_phase(.Process, "perishing: made, and become")
		if at <= t1.ms && (food.becomes == nil || len(food.becomes) == 0) {
			proposal_group_destroy(group, whole(e), "rotted away")   /* its mass gone with it */
		} else if at <= t1.ms {
			become(world, group, e, food.becomes, food.ending if food.ending != nil && len(food.ending) > 0 else "spoiled")
		} else {
			proposal_group_set_of_to(group, "Becoming.becomesAt", whole(e), at)
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

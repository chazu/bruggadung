package lab

// Foraging — patches as a domain (VILLAGE.md decision 12): a patch holding
// fewer than its most grows a handful back every `regrowsIn` from `grewAt`
// (content/foraging/), in closed form as crops ripen (domains_farming.odin):
// nothing is stepped; its wake is when the next handful is due, and then it
// holds one more. The horizon is the next patch to grow one.


Foraging :: struct {
	using object: Object,
	world:        ^World,
}


foraging_init_with_world :: proc(world: ^World) -> ^Foraging {
	self := object_new(Foraging, foraging_dealloc)
	self.world = retain(world)
	return self
}


foraging_dealloc :: proc(self: ^Foraging) {
	release(self.world)
}


@(private = "file")
foraging_patches :: proc(self: ^Foraging) -> ^Store {
	return world_store_for_kind(self.world, world_kind_named(self.world, "Patch"))
}


foraging_is_active :: proc(self: ^Foraging) -> bool {
	return store_count(foraging_patches(self)) > 0
}


// When a patch holding fewer than its most grows its next handful; 0 for
// one full.
patch_next_growth :: proc(patch: ^Patch) -> i64 {
	if patch == nil || patch.handfuls >= patch.most || patch.regrowsIn <= 0 do return 0
	return patch.grewAt + patch.regrowsIn
}


// The next patch to grow a handful.
foraging_horizon_at :: proc(self: ^Foraging, t: Time) -> Horizon {
	h: Horizon

	h.safeStep  = TIME_NEVER
	h.nextEvent = TIME_NEVER
	patches := foraging_patches(self)
	for i: uint = 0; i < store_count(patches); i += 1 {
		if at := patch_next_growth((^Patch)(store_record_at_index(patches, i))); at > t.ms && at < h.nextEvent.ms do h.nextEvent = time_make(at)
	}
	return h
}


// Each patch due by t1 holds as many more as have grown, to its most.
foraging_advance_from :: proc(self: ^Foraging, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	group: ^Proposal_Group

	patches := foraging_patches(self)
	for i: uint = 0; i < store_count(patches); i += 1 {
		patch := (^Patch)(store_record_at_index(patches, i))
		at := patch_next_growth(patch)
		if at == 0 || at > t1.ms do continue
		grown := min((t1.ms - patch.grewAt) / patch.regrowsIn, patch.most - patch.handfuls)
		if group == nil do group = proposal_group_group_with_phase(.Process, "foraging: patches regrow")
		e := store_entity_at_index(patches, i)
		proposal_group_set_of_to_expecting(group, "Patch.handfuls", whole(e), patch.handfuls + grown, patch.handfuls)
		proposal_group_set_of_to(group, "Patch.grewAt", whole(e), patch.grewAt + grown * patch.regrowsIn)
	}
	if group != nil do committer_submit(committer, group)
}


foraging_as_domain :: proc(self: ^Foraging) -> Domain {
	return Domain{
		data                = self,
		name                = proc(data: rawptr) -> string {return "foraging"},
		check_in_all        = proc(data: rawptr) {},
		saved_state         = proc(data: rawptr) -> []string {return make([]string, 0, context.temp_allocator)},
		restore_saved_state = proc(data: rawptr, lines: []string) {},
		is_active           = proc(data: rawptr) -> bool {return foraging_is_active((^Foraging)(data))},
		horizon_at          = proc(data: rawptr, t: Time) -> Horizon {return foraging_horizon_at((^Foraging)(data), t)},
		advance_from        = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
			foraging_advance_from((^Foraging)(data), t0, t1, world, committer)
		},
	}
}

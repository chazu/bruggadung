package lab

/*
 * BGBodyKind — behaviour of the Body component. On the reactions channel:
 * a unit put (or split off) into a container that holds a stack of the
 * same unit (food: raw with raw, cooked with cooked) proposes to merge
 * into it, and, food, to spoil at the two's
 * times averaged by mass. Whether the units are indistinguishable is commitment's to
 * decide; a refusal is traced with its reason. And what is nobody's, that
 * someone gets into its own hand (taken up, split off into it, made
 * there), is its own, and its household's: an ownership claim of the
 * holder's, and of each it has a kin bond toward.
 *
 * (ported from the Objective-C lab's kinds/BGBodyKind.m)
 */

import "core:fmt"


Body_Kind :: struct {
	using object: Object,
}


// [BGBodyKind new]
body_kind_new :: proc() -> ^Body_Kind {
	return object_new(Body_Kind, nil)
}


body_kind_as_reactor :: proc(self: ^Body_Kind) -> Reactor {
	return Reactor{
		data = self,
		react_to_event = proc(data: rawptr, committer: ^Committer, event: ^Event, world: ^World) {
			body_kind_react_to_event((^Body_Kind)(data), committer, event, world)
		},
	}
}


body_kind_react_to_event :: proc(self: ^Body_Kind, committer: ^Committer, event: ^Event, world: ^World) {
	group: ^Proposal_Group
	here:  [256]Entity_ID
	unit:  cstring
	i:     uint
	n:     uint

	/* into its own hand, and nobody's: the holder's own from then on, and
	 * its household's (made, caught, gathered, found) */
	if (event.kind == "moved" || event.kind == "split" || event.kind == "created") && event.location.form == .Held_By {
		holder := event.location.place
		/* by its own doing: what is put in its hand is another's to pass */
		if event.actor != holder do return
		if !world_is_live(world, event.subject) || world_record(world, world_kind_named(world, "Agent"), holder) == nil do return
		if world_record(world, world_kind_named(world, "Body"), event.subject) == nil do return
		if len(owners_of(world, event.subject)) != 0 do return
		group = proposal_group_group_with_phase(.System, fmt.tprintf("Body reaction: %d is %d's, who took it up", event.subject, holder))
		proposal_group_set_cause(group, event.index)
		for owner in household_of(world, holder) {
			claim := proposal_group_create(group, "ownership", "taken up", location_make_none())
			proposal_group_set_of_to(group, "Claim.quantity", whole(claim), 1)
			proposal_group_relate(group, .Claimant, whole(claim), whole(owner))
			proposal_group_relate(group, .Claim_Subject, whole(claim), whole(event.subject))
		}
		committer_submit(committer, group)
		return
	}
	/* moved in whole, or split off into it */
	if (event.kind != "moved" && event.kind != "split") || event.location.form != .In do return
	if !world_is_live(world, event.subject) do return
	unit = world_unit_of(world, event.subject)
	if unit == nil do return
	/* the lowest-numbered stack of the same unit already there */
	n = world_entities_at(world, event.location.place, .In, raw_data(here[:]), 256)
	for i = 0; i < n && i < 256; i += 1 {
		if here[i] == event.subject || !world_is_stack(world, here[i]) || world_unit_of(world, here[i]) != unit do continue
		if !food_alike(world, event.subject, here[i]) do continue
		group = proposal_group_group_with_phase(.System,
		                                        fmt.tprintf("Body reaction: merge %d into %d", event.subject, here[i]))
		proposal_group_set_cause(group, event.index)
		proposal_group_merge(group, whole(event.subject), whole(here[i]))
		/* food: the two spoil at their times averaged, weighed by mass
		 * (content/perishing/); food made since the last boundary, not yet
		 * stamped, as perishing will stamp it */
		food := world_kind_named(world, "Becoming")
		mf := (^Becoming)(world_record(world, food, event.subject))
		tf := (^Becoming)(world_record(world, food, here[i]))
		if mf != nil && tf != nil {
			now := world_time(world).ms
			mine, theirs := perishing_time_of(world, event.subject, mf, now), perishing_time_of(world, here[i], tf, now)
			a, b := max(world_mass_of(world, event.subject), 0), max(world_mass_of(world, here[i]), 0)
			if mine > 0 && theirs > 0 && a + b > 0 {
				at := (mine * a + theirs * b) / (a + b)
				if at != tf.becomesAt do proposal_group_set_of_to(group, "Becoming.becomesAt", whole(here[i]), at)
			}
		}
		committer_submit(committer, group)
		return
	}
}

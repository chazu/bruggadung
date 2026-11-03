package lab

/*
 * BGBodyKind — behaviour of the Body component. On the reactions channel:
 * a unit put into a container that holds a stack of the same unit proposes
 * to merge into it. Whether the units are indistinguishable is commitment's
 * to decide; a refusal is traced with its reason.
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

	if event.kind != "moved" || event.location.form != .In do return
	if !world_is_live(world, event.subject) do return
	unit = world_unit_of(world, event.subject)
	if unit == nil do return
	/* the lowest-numbered stack of the same unit already there */
	n = world_entities_at(world, event.location.place, .In, raw_data(here[:]), 256)
	for i = 0; i < n && i < 256; i += 1 {
		if here[i] == event.subject || !world_is_stack(world, here[i]) || world_unit_of(world, here[i]) != unit do continue
		group = proposal_group_group_with_phase(.System,
		                                        fmt.tprintf("Body reaction: merge %d into %d", event.subject, here[i]))
		proposal_group_set_cause(group, event.index)
		proposal_group_merge(group, whole(event.subject), whole(here[i]))
		committer_submit(committer, group)
		return
	}
}

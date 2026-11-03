package lab

/*
 * BGValveKind — how a valve answers (ACTIONS.md Scenario 1): an effect
 * commits the torque applied to it, with no success flag, and the valve, by
 * its hidden breakaway, turns or holds. A blow loosens what has seized.
 * Every attempt is recorded for the developer: the torque, the breakaway,
 * what the turner expected, and what happened.
 *
 * (ported from the Objective-C lab's kinds/BGValveKind.m)
 */

import "core:fmt"


Valve_Kind :: struct {
	using object: Object,
}


// [BGValveKind new]
valve_kind_new :: proc() -> ^Valve_Kind {
	return object_new(Valve_Kind, nil)
}


valve_kind_as_reactor :: proc(self: ^Valve_Kind) -> Reactor {
	return Reactor{
		data = self,
		react_to_event = proc(data: rawptr, committer: ^Committer, event: ^Event, world: ^World) {
			valve_kind_react_to_event((^Valve_Kind)(data), committer, event, world)
		},
	}
}


valve_kind_react_to_event :: proc(self: ^Valve_Kind, committer: ^Committer, event: ^Event, world: ^World) {
	valve:    ^Valve
	g:        ^Proposal_Group
	loosened: i64

	valve = (^Valve)(world_record(world, world_kind_named(world, "Valve"), event.subject))
	if valve == nil do return
	if event.kind == "torqued" {
		g = proposal_group_group_with_phase(.System,
		                                    fmt.tprintf("valve %d: %d Nm against %d Nm: %s (%s)",
		                                                event.subject,
		                                                event.amount / 1000,
		                                                valve.breakaway / 1000,
		                                                "turns" if event.amount >= valve.breakaway else "holds",
		                                                event.detail if event.detail != nil else "no expectation"))
		proposal_group_set_cause(g, event.index)
		if event.amount >= valve.breakaway && !valve.turned {
			/* it breaks free, with a creak */
			proposal_group_set_of_to(g, "Valve.turned", whole(event.subject), 1)
			make_trace(world, g, "creak", event.subject, location_make_none(), 60, "a valve breaking free")
		} else {
			proposal_group_emit_subject_other(g, "held", whole(event.subject), whole(event.other))
		}
		committer_submit(committer, g)
		return
	}
	if event.kind == "struck" && !valve.turned {
		loosened = valve.breakaway - event.amount
		if loosened < valve.rating do loosened = valve.rating
		g = proposal_group_group_with_phase(.System,
		                                    fmt.tprintf("valve %d: struck, breaks free at %d Nm now",
		                                                event.subject,
		                                                loosened / 1000))
		proposal_group_set_cause(g, event.index)
		proposal_group_set_of_to(g, "Valve.breakaway", whole(event.subject), loosened)
		committer_submit(committer, g)
	}
}

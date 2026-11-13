package lab

// BGPlotKind — how a plot stands follows its rows (VILLAGE.md decision 5),
// on the reactions channel: its last row reaped, it is bare; its last row
// sown, it stands sown, growing from then, and the seed kept back for it
// is used. Sowing and harvesting only count rows
// (content/farming/farming.tri). That a sown plot ripens is a progression
// (`ripening`, there; domains_progressions.odin).

import "core:fmt"

import tri "../../triangle/odin/triangle"


// Its #Plot record, or nil.
plot_of :: proc(world: ^World, e: Entity_ID) -> ^Plot {
	return (^Plot)(world_record(world, world_kind_named(world, "Plot"), e))
}


// How a plot stands, as its type ID: "bare", "sown", "ripe".
plot_stands :: proc(world: ^World, stands: string) -> u32 {
	return u32(tri.type_named(world_tri(world), fmt_quoted(stands)))
}


@(private = "file")
fmt_quoted :: proc(s: string) -> cstring {
	b := make([]u8, len(s) + 3, context.temp_allocator)
	b[0] = '"'
	copy(b[1:], s)
	b[len(s) + 1] = '"'
	return cstring(raw_data(b))
}


Plot_Kind :: struct {
	using object: Object,
}


plot_kind_new :: proc() -> ^Plot_Kind {
	return object_new(Plot_Kind, nil)
}


plot_kind_as_reactor :: proc(self: ^Plot_Kind) -> Reactor {
	return Reactor{
		data = self,
		react_to_event = proc(data: rawptr, committer: ^Committer, event: ^Event, world: ^World) {
			plot_kind_react_to_event((^Plot_Kind)(data), committer, event, world)
		},
	}
}


// A plot whose rows are all reaped is bare; all sown, it stands sown.
plot_kind_react_to_event :: proc(self: ^Plot_Kind, committer: ^Committer, event: ^Event, world: ^World) {
	if event.kind != "changed" || event.detail == nil do return
	plot := plot_of(world, event.subject)
	if plot == nil do return
	east, south := world_area_extent(world, event.subject)
	tiles := i64(east) * i64(south)
	switch string(event.detail) {
	case "Plot.reaped":
		if plot.stands != plot_stands(world, "ripe") || plot.reaped < tiles do return
		group := proposal_group_group_with_phase(.System, fmt.tprintf("Plot reaction: %d is reaped, and bare", event.subject))
		proposal_group_set_cause(group, event.index)
		proposal_group_set_of_to(group, "Plot.reaped", whole(event.subject), 0)
		proposal_group_set_of_to(group, "Plot.stands", whole(event.subject), i64(plot_stands(world, "bare")))
		committer_submit(committer, group)
	case "Plot.sown":
		if plot.stands != plot_stands(world, "bare") || plot.sown < tiles do return
		group := proposal_group_group_with_phase(.System, fmt.tprintf("Plot reaction: %d is sown", event.subject))
		proposal_group_set_cause(group, event.index)
		proposal_group_set_of_to(group, "Plot.sown", whole(event.subject), 0)
		proposal_group_set_of_to(group, "Plot.stands", whole(event.subject), i64(plot_stands(world, "sown")))
		proposal_group_set_of_to(group, "Plot.sownAt", whole(event.subject), world_time(world).ms)
		if plot.kept do proposal_group_set_of_to(group, "Plot.kept", whole(event.subject), 0)   /* seed kept from the next harvest */
		committer_submit(committer, group)
	}
}

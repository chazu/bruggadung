package lab

// BGFarming — plots as a domain (VILLAGE.md decision 5): a plot's crop
// grows from when its last row was sown (content/farming/farming.tri's
// `sownAt` and `ripensIn`), a function of time read when needed, never
// stepped. Grown, the plot stands ripe, set at that moment: its one wake.
// The horizon is the next plot to ripen; nothing happens between.
//
// How a plot stands follows its rows too (BGPlotKind, on the reactions
// channel): its last row reaped, it is bare; its last row sown, it stands
// sown, growing from then, and the seed kept back for it is used. Sowing
// and harvesting only count rows (content/farming/farming.tri).

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


// How far a sown plot's crop has grown at t, 0 to 100 (100 grown, ripe from
// then on); 0 for one not sown, 100 for one ripe.
plot_growth :: proc(world: ^World, plot: ^Plot, t: i64) -> i64 {
	if plot == nil do return 0
	if plot.stands == plot_stands(world, "ripe") do return 100
	if plot.stands != plot_stands(world, "sown") || t <= plot.sownAt do return 0
	if plot.ripensIn <= 0 || t - plot.sownAt >= plot.ripensIn do return 100
	return (t - plot.sownAt) * 100 / plot.ripensIn
}


Farming :: struct {
	using object: Object,
	world:        ^World,
}


farming_init_with_world :: proc(world: ^World) -> ^Farming {
	self := object_new(Farming, farming_dealloc)
	self.world = retain(world)
	return self
}


farming_dealloc :: proc(self: ^Farming) {
	release(self.world)
}


@(private = "file")
farming_plots :: proc(self: ^Farming) -> ^Store {
	return world_store_for_kind(self.world, world_kind_named(self.world, "Plot"))
}


farming_is_active :: proc(self: ^Farming) -> bool {
	return store_count(farming_plots(self)) > 0
}


// The next sown plot to ripen.
farming_horizon_at :: proc(self: ^Farming, t: Time) -> Horizon {
	h: Horizon

	h.safeStep  = TIME_NEVER
	h.nextEvent = TIME_NEVER
	sown  := plot_stands(self.world, "sown")
	plots := farming_plots(self)
	for i: uint = 0; i < store_count(plots); i += 1 {
		plot := (^Plot)(store_record_at_index(plots, i))
		if plot.stands != sown do continue
		if at := plot.sownAt + plot.ripensIn; at > t.ms && at < h.nextEvent.ms do h.nextEvent = time_make(at)
	}
	return h
}


// A sown plot grown by t1 stands ripe.
farming_advance_from :: proc(self: ^Farming, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	group: ^Proposal_Group

	sown  := plot_stands(world, "sown")
	plots := farming_plots(self)
	for i: uint = 0; i < store_count(plots); i += 1 {
		plot := (^Plot)(store_record_at_index(plots, i))
		if plot.stands != sown || plot_growth(world, plot, t1.ms) < 100 do continue
		if group == nil do group = proposal_group_group_with_phase(.Process, "farming: plots ripen")
		proposal_group_set_of_to(group, "Plot.stands", whole(store_entity_at_index(plots, i)), i64(plot_stands(world, "ripe")))
	}
	if group != nil do committer_submit(committer, group)
}


farming_as_domain :: proc(self: ^Farming) -> Domain {
	return Domain{
		data                = self,
		name                = proc(data: rawptr) -> string {return "farming"},
		check_in_all        = proc(data: rawptr) {},
		saved_state         = proc(data: rawptr) -> []string {return make([]string, 0, context.temp_allocator)},
		restore_saved_state = proc(data: rawptr, lines: []string) {},
		is_active           = proc(data: rawptr) -> bool {return farming_is_active((^Farming)(data))},
		horizon_at          = proc(data: rawptr, t: Time) -> Horizon {return farming_horizon_at((^Farming)(data), t)},
		advance_from        = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
			farming_advance_from((^Farming)(data), t0, t1, world, committer)
		},
	}
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

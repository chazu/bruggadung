package lab

/*
 * BGLatentKind — what extracting a part does to its assembly
 * (DOMAIN_SIMULATION.md Scenario 2, provisional with
 * content/machines/latent.tri):
 * when the part whose role the descriptor names (`pathWhenOut`) is out of
 * the assembly, a path opens from the store the assembly holds back (its
 * `riser`) to its floor, through the part `pathThrough` names; it passes in
 * proportion to that part's wear past half. A leak, a tap installed in the
 * store, is the path: the fluid domain drains it, a topology change.
 *
 * (kinds/BGLatentKind.h and .m)
 */

import "core:fmt"
import "core:mem"
import tri "../../triangle/odin/triangle"


Latent_Kind :: struct {
	using object: Object,
}


// [BGLatentKind new]
latent_kind_new :: proc() -> ^Latent_Kind {
	return object_new(Latent_Kind, nil)
}


latent_kind_as_reactor :: proc(self: ^Latent_Kind) -> Reactor {
	return Reactor{
		data = self,
		react_to_event = proc(data: rawptr, committer: ^Committer, event: ^Event, world: ^World) {
			latent_kind_react_to_event((^Latent_Kind)(data), committer, event, world)
		},
	}
}


// The text at `path`, unquoted, into buf (a C string there); NO if it isn't
// text, or doesn't fit.
@(private = "file")
text_of :: proc(content: ^tri.Content, node: ^tri.Node, path: cstring, buf: []u8) -> bool {
	n: uint

	n = uint(tri.print(content, tri.at(content, node, path), raw_data(buf), uint(len(buf)))) if node != nil else 0
	if n < 2 || n >= uint(len(buf)) || buf[0] != '"' do return false
	mem.copy(raw_data(buf), &buf[1], int(n - 2))
	buf[n - 2] = 0
	return true
}


/* The part in the role inside the assembly, or BGNoEntity. */
@(private = "file")
part_in :: proc(world: ^World, assembly: Entity_ID, role: cstring) -> Entity_ID {
	parts: ^Store
	at:    Location
	i:     uint

	parts = world_store_for_kind(world, world_kind_named(world, "Part"))
	for i = 0; i < store_count(parts); i += 1 {
		at = world_location_of(world, store_entity_at_index(parts, i))
		if at.form == .Part_Of && at.place == assembly && location_role(&at) == string(role) {
			return store_entity_at_index(parts, i)
		}
	}
	return NO_ENTITY
}


/* A part out of its assembly for the first time takes its share of the
 * assembly's heat, by heat capacity (DOMAIN_SIMULATION.md Scenario 2, check
 * 3): the heat and the capacity both move, so neither the total nor either
 * one's temperature changes. */
@(private = "file")
latent_kind_split_heat_of :: proc(self: ^Latent_Kind, part: Entity_ID, committer: ^Committer, world: ^World, cause: u64) {
	p:        ^Part
	mine:     ^Thermal_Body
	whole_:   ^Thermal_Body
	g:        ^Proposal_Group
	at:       Location
	assembly: Entity_ID
	share:    i64

	p = (^Part)(world_record(world, world_kind_named(world, "Part"), part))
	if p == nil || p.detached || p.cameFrom == 0 do return
	assembly = Entity_ID(p.cameFrom)
	at       = world_location_of(world, part)
	if at.form == .Part_Of && at.place == assembly do return
	g = proposal_group_group_with_phase(.System, fmt.tprintf("part %d leaves assembly %d", part, assembly))
	proposal_group_set_cause(g, cause)
	proposal_group_set_of_to(g, "Part.detached", whole(part), 1)
	mine   = (^Thermal_Body)(world_record(world, world_kind_named(world, "ThermalBody"), part))
	whole_ = (^Thermal_Body)(world_record(world, world_kind_named(world, "ThermalBody"), assembly))
	if mine != nil && whole_ != nil && whole_.heatCapacity > mine.heatCapacity {
		share = whole_.heat * mine.heatCapacity / whole_.heatCapacity
		proposal_group_set_of_to(g, "ThermalBody.heat", whole(part), mine.heat + share)
		proposal_group_set_of_to(g, "ThermalBody.heat", whole(assembly), whole_.heat - share)
		proposal_group_set_of_to(g, "ThermalBody.heatCapacity", whole(assembly), whole_.heatCapacity - mine.heatCapacity)
	}
	committer_submit(committer, g)
}


latent_kind_react_to_event :: proc(self: ^Latent_Kind, committer: ^Committer, event: ^Event, world: ^World) {
	latent:     ^Latent
	schema:     ^tri.Node
	g:          ^Proposal_Group
	assemblies: ^Store
	assembly:   Entity_ID
	through:    Entity_ID
	leak:       Entity_ID
	content:    ^tri.Content
	i:          uint
	wear:       i64
	rate:       i64
	out:        [64]u8
	via:        [64]u8

	if event.kind != "moved" do return
	latent_kind_split_heat_of(self, event.subject, committer, world, event.index)
	content    = world_tri(world)
	assemblies = world_store_for_kind(world, world_kind_named(world, "Latent"))
	for i = 0; i < store_count(assemblies); i += 1 {
		assembly = store_entity_at_index(assemblies, i)
		latent   = (^Latent)(store_record_at_index(assemblies, i))
		if latent.leaking || latent.riser == 0 || !world_is_live(world, Entity_ID(latent.riser)) do continue
		schema = tri.at(content, tri.pattern(content, world_info(world, assembly).blueprint), "latent")
		if !text_of(content, schema, "pathWhenOut", out[:]) || !text_of(content, schema, "pathThrough", via[:]) do continue
		/* revealed, and the part that closed the path out of it */
		through = part_in(world, assembly, cstring(&via[0]))
		if through == NO_ENTITY || part_in(world, assembly, cstring(&out[0])) != NO_ENTITY do continue
		wear = 0
		world_get_field(world, "Part.wear", through, &wear)
		rate = (wear - 50) * 200 if wear > 50 else 0          /* mL a minute */
		g    = proposal_group_group_with_phase(.System,
		                                       fmt.tprintf("assembly %d: its %s out, a path through its %s " +
		                                                   "(wear %d): %d mL a minute",
		                                                   assembly, cstring(&out[0]), cstring(&via[0]),
		                                                   wear, rate))
		proposal_group_set_cause(g, event.index)
		proposal_group_set_of_to(g, "Latent.leaking", whole(assembly), 1)
		if rate > 0 {
			leak = proposal_group_create(g, "leak", "the path back", part_of(Entity_ID(latent.riser), "leak", 0))
			proposal_group_set_of_to(g, "Tap.rate", whole(leak), rate)
		}
		committer_submit(committer, g)
	}
}

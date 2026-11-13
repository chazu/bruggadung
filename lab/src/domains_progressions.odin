package lab

// Progressions — what a thing does by itself as time passes, as content
// says it (content/reality.tri's #Rate and #Turn, the `progressions`
// family; DETAIL_REGIMES.md decisions 4 and 5), applied by the one domain
// here, at every level of detail. Nothing is stepped: the horizon is the
// next progression due, its wake then.
//
// A rate: a field that is so much more each period, up to its bound, from
// a time (a patch's handfuls, content/foraging/). At its bound it rests,
// its time 0. One found below its bound with no time left it at the last
// boundary: its time is t0 (what took it below needn't say so).
//
// A turn: a field that stands one way stands another, one period after a
// time (a sown plot ripe, content/farming/).
//
// Which component, and which of its fields, a progression names; they
// are found once, as the world is made, and a progression that names
// what isn't there is refused then (progressions_check).

import "core:fmt"
import "core:strings"

import tri "../../triangle/odin/triangle"


Progression :: struct {
	name:   string,          // its instance's, cloned
	kind:   uint,            // the component it progresses
	asOf:   ^Field_Info,
	period: ^Field_Info,
	// a rate
	rises:  ^Field_Info,     // nil for a turn
	upTo:   ^Field_Info,
	by:     i64,
	// a turn
	turned: ^Field_Info,     // nil for a rate
	from:   i64,
	to:     i64,
	// the fields it sets, as proposals name them: interned
	asOfPath:  cstring,
	valuePath: cstring,
}


Progressions :: struct {
	using object: Object,
	world:        ^World,
	list:         [dynamic]Progression,
}


@(private = "file")
component_named :: proc(name: string) -> uint {
	for k: uint = 0; k < COMPONENT_COUNT; k += 1 {
		if string(COMPONENTS[k].name) == name do return k
	}
	return NOT_FOUND
}


@(private = "file")
field_named :: proc(kind: uint, name: string) -> ^Field_Info {
	for i: uint = 0; i < COMPONENTS[kind].nfields; i += 1 {
		if string(COMPONENTS[kind].fields[i].name) == name do return &COMPONENTS[kind].fields[i]
	}
	return nil
}


@(private = "file")
said :: proc(tc: ^tri.Content, node: ^tri.Node, path: cstring) -> string {
	buf: [256]u8

	v := tri.at(tc, node, path)
	if v == nil do return ""
	n := tri.print(tc, v, raw_data(buf[:]), len(buf))
	if n < 2 || n >= len(buf) || buf[0] != '"' || buf[n - 1] != '"' do return ""
	return strings.clone(string(buf[1:n - 1]), context.temp_allocator)
}


@(private = "file")
proposable :: proc(f: ^Field_Info) -> bool {
	return strings.contains(string(f.flags), "proposable")
}


// A field of a component that holds a quantity, by its name; or why not.
@(private = "file")
quantity_field :: proc(tag: cstring, kind: uint, what: string, name: string, out: ^^Field_Info) -> string {
	f := field_named(kind, name)
	if f == nil do return fmt.tprintf("the progression %s: its %s, %q, is no field of %s", tag, what, name, COMPONENTS[kind].name)
	if f.value != VALUE_QUANTITY do return fmt.tprintf("the progression %s: its %s, %s.%s, holds no quantity", tag, what, COMPONENTS[kind].name, name)
	out^ = f
	return ""
}


// One progression as content says it, its component and fields found; or
// the reason it can't be applied.
@(private = "file")
progression_resolve :: proc(tc: ^tri.Content, tag: cstring) -> (p: Progression, why: string) {
	node := node_of(tc, tag)
	if node == nil do return p, fmt.tprintf("the progression %s has no value", tag)
	of := said(tc, node, "progresses")
	p.kind = component_named(of)
	if p.kind == NOT_FOUND do return p, fmt.tprintf("the progression %s progresses %q, which is no component", tag, of)

	if why = quantity_field(tag, p.kind, "time", said(tc, node, "asOf"), &p.asOf); why != "" do return
	if why = quantity_field(tag, p.kind, "period", said(tc, node, "period"), &p.period); why != "" do return
	if !proposable(p.asOf) do return p, fmt.tprintf("the progression %s: %s.%s is not proposable", tag, COMPONENTS[p.kind].name, p.asOf.name)

	rises, turned := said(tc, node, "rises"), said(tc, node, "turned")
	switch {
	case rises != "":
		lo, hi: i64
		if why = quantity_field(tag, p.kind, "rising field", rises, &p.rises); why != "" do return
		if why = quantity_field(tag, p.kind, "bound", said(tc, node, "upTo"), &p.upTo); why != "" do return
		p.by = 1
		if tri.node_interval(tri.at(tc, node, "risesBy"), &lo, &hi) != 0 && lo == hi && lo >= 1 do p.by = lo
		if !proposable(p.rises) do return p, fmt.tprintf("the progression %s: %s.%s is not proposable", tag, COMPONENTS[p.kind].name, rises)
	case turned != "":
		p.turned = field_named(p.kind, turned)
		if p.turned == nil do return p, fmt.tprintf("the progression %s turns %q, which is no field of %s", tag, turned, COMPONENTS[p.kind].name)
		if p.turned.value != VALUE_TYPE do return p, fmt.tprintf("the progression %s turns %s.%s, which holds no choice of texts", tag, COMPONENTS[p.kind].name, turned)
		if !proposable(p.turned) do return p, fmt.tprintf("the progression %s: %s.%s is not proposable", tag, COMPONENTS[p.kind].name, turned)
		from, to := said(tc, node, "turnedFrom"), said(tc, node, "turnedTo")
		p.from = i64(tri.type_named(tc, ns_utf8(fmt.tprintf("%q", from))))
		p.to = i64(tri.type_named(tc, ns_utf8(fmt.tprintf("%q", to))))
		if from == "" || to == "" || p.from == 0 || p.to == 0 {
			return p, fmt.tprintf("the progression %s turns %s.%s from %q to %q, and one of them is nothing it can stand", tag, COMPONENTS[p.kind].name, turned, from, to)
		}
	case:
		return p, fmt.tprintf("the progression %s is neither a rate nor a turn", tag)
	}
	return p, ""
}


// "" if every progression in the content can be applied; else the first
// reason one can't. Asked as a world is made (world_with_content).
progressions_check :: proc(tc: ^tri.Content) -> string {
	family := tri.family_index(tc, "progressions")
	for i: uint = 0; family != nil && i < tri.index_count(family); i += 1 {
		if _, why := progression_resolve(tc, cstring(tri.index_tag(family, i))); why != "" do return why
	}
	return ""
}


progressions_init_with_world :: proc(world: ^World) -> ^Progressions {
	self := object_new(Progressions, progressions_dealloc)
	self.world = retain(world)
	tc := world_tri(world)
	family := tri.family_index(tc, "progressions")
	for i: uint = 0; family != nil && i < tri.index_count(family); i += 1 {
		tag := cstring(tri.index_tag(family, i))
		p, why := progression_resolve(tc, tag)
		if why != "" do continue      /* refused as the world was made */
		p.name = strings.clone(string(tag))
		value := p.rises if p.rises != nil else p.turned
		p.asOfPath = world_intern(world, ns_utf8(fmt.tprintf("%s.%s", COMPONENTS[p.kind].name, p.asOf.name)))
		p.valuePath = world_intern(world, ns_utf8(fmt.tprintf("%s.%s", COMPONENTS[p.kind].name, value.name)))
		append(&self.list, p)
	}
	return self
}


progressions_dealloc :: proc(self: ^Progressions) {
	for p in self.list do delete(p.name)
	delete(self.list)
	release(self.world)
}


progressions_is_active :: proc(self: ^Progressions) -> bool {
	for p in self.list {
		if store_count(world_store_for_kind(self.world, p.kind)) > 0 do return true
	}
	return false
}


// When a record is next due, read at t: 0 for one that isn't (a rate at
// its bound, a turn not standing so). A rate below its bound with no time
// left it at t.
@(private = "file")
progression_due :: proc(p: ^Progression, record: rawptr, t: i64) -> i64 {
	period := max(field_get(p.period, record), 0)
	asOf := field_get(p.asOf, record)
	if p.rises != nil {
		if period == 0 || field_get(p.rises, record) >= field_get(p.upTo, record) do return 0
		return (asOf if asOf != 0 else t) + period
	}
	if field_get(p.turned, record) != p.from do return 0
	return asOf + period
}


// The next progression due.
progressions_horizon_at :: proc(self: ^Progressions, t: Time) -> Horizon {
	h: Horizon

	h.safeStep  = TIME_NEVER
	h.nextEvent = TIME_NEVER
	for &p in self.list {
		store := world_store_for_kind(self.world, p.kind)
		for i: uint = 0; i < store_count(store); i += 1 {
			if at := progression_due(&p, store_record_at_index(store, i), t.ms); at > t.ms && at < h.nextEvent.ms do h.nextEvent = time_make(at)
		}
	}
	return h
}


// Each record due by t1 is as far along as the time makes it: a rate so
// many periods more, to its bound; a turn turned. A rate at its bound
// rests, and one that left its bound has its time.
progressions_advance_from :: proc(self: ^Progressions, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
	for &p in self.list {
		group: ^Proposal_Group

		store := world_store_for_kind(world, p.kind)
		for i: uint = 0; i < store_count(store); i += 1 {
			record := store_record_at_index(store, i)
			e      := whole(store_entity_at_index(store, i))
			asOf   := field_get(p.asOf, record)
			at     := progression_due(&p, record, t0.ms)
			if p.turned != nil {
				if at == 0 || at > t1.ms do continue
				if group == nil do group = proposal_group_group_with_phase(.Process, fmt.tprintf("progression: %s", p.name))
				proposal_group_set_of_to(group, p.valuePath, e, p.to)
				continue
			}
			value, bound := field_get(p.rises, record), field_get(p.upTo, record)
			time := asOf
			switch {
			case at == 0:
				if value >= bound do time = 0      /* at its bound: it rests */
			case at > t1.ms:
				time = at - field_get(p.period, record)      /* t0, for one that left its bound then */
			case:
				period  := field_get(p.period, record)
				periods := min((t1.ms - (at - period)) / period, (bound - value + p.by - 1) / p.by)
				grown   := min(value + periods * p.by, bound)
				if group == nil do group = proposal_group_group_with_phase(.Process, fmt.tprintf("progression: %s", p.name))
				proposal_group_set_of_to_expecting(group, p.valuePath, e, grown, value)
				time = 0 if grown >= bound else at - period + periods * period
			}
			if time != asOf {
				if group == nil do group = proposal_group_group_with_phase(.Process, fmt.tprintf("progression: %s", p.name))
				proposal_group_set_of_to(group, p.asOfPath, e, time)
			}
		}
		if group != nil do committer_submit(committer, group)
	}
}


progressions_as_domain :: proc(self: ^Progressions) -> Domain {
	return Domain{
		data                = self,
		name                = proc(data: rawptr) -> string {return "progressions"},
		check_in_all        = proc(data: rawptr) {},
		saved_state         = proc(data: rawptr) -> []string {return make([]string, 0, context.temp_allocator)},
		restore_saved_state = proc(data: rawptr, lines: []string) {},
		is_active           = proc(data: rawptr) -> bool {return progressions_is_active((^Progressions)(data))},
		horizon_at          = proc(data: rawptr, t: Time) -> Horizon {return progressions_horizon_at((^Progressions)(data), t)},
		advance_from        = proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer) {
			progressions_advance_from((^Progressions)(data), t0, t1, world, committer)
		},
	}
}

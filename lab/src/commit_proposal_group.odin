package lab

// Proposals and proposal groups (ACTIONS.md §8). Every change to world state
// is a proposal; a group of proposals commits atomically, all or nothing.
//
// A group names the entities it creates by handles (BGHandle), which become
// IDs when it applies. A proposal can address one unit of a stack, as
// {stack, n}: commitment splits that unit off first (automatic
// individuation), and every proposal in the group with the same {stack, n}
// means that same unit.
//
// (ported from the Objective-C lab's commit/BGProposalGroup.m)

import "core:strings"

Phase :: enum i32 {
	Process = 0,          // domains, processes
	Action,               // activities, inputs
	System,               // system operations, reactions
	Count,
}

Ref :: struct {
	entity: Entity_ID,    // an ID or a handle
	unit:   u32,          // 0: the whole entity; n: the group's n-th unit of a stack
}

whole :: #force_inline proc "contextless" (entity: Entity_ID) -> Ref {
	r: Ref

	r.entity = entity
	r.unit   = 0
	return r
}

unit :: #force_inline proc "contextless" (stack: Entity_ID, n: u32) -> Ref {
	r: Ref

	r.entity = stack
	r.unit   = n
	return r
}

Proposal_Kind :: enum i32 {
	Create,
	Destroy,
	Set_Field,
	Move,
	Split,
	Merge,
	Add_Edge,
	Remove_Edge,
	Event,
	Set_Terrain,          // a cell's terrain kind (TERRAIN.md): name is the kind, location the cell
}

Proposal :: struct {
	kind:     Proposal_Kind,
	target:   Ref,
	other:    Ref,        // merge: the stack to merge into; edges: the far end; events: the other role
	location: Location,   // create, move, split; place may be a handle
	value:    i64,        // set field: the value; split: the count
	edge:     Edge_Kind,
	name:     cstring,    // create: blueprint; set field: "Kind.field"; event: its kind; destroy: reason
	key:      cstring,    // create: the stable key the seed derives from
	handle:   Entity_ID,  // create, split: the new entity
	expected: Location,   // move: where the target must still be, if `expects`
	expects:  bool,
}

// Each phase's name.
PHASE_NAMES := [int(Phase.Count)]cstring{
	"process",
	"action",
	"system",
}


Proposal_Group :: struct {
	using object: Object,
	phase:     Phase,
	source:    string,
	actor:     Entity_ID,
	weight:    u64,
	cause:     u64,
	proposals: [dynamic]Proposal,        // _proposals, _count and _capacity
	handles:   u64,
	strings:   [dynamic]cstring,         // _strings and _nstrings

	// results, set by commitment
	applied:   bool,
	rejection: string,
	position:  u64,
	ids:       [dynamic]Entity_ID,       // handle n → ID; _ids and _nids
}

proposal_group_group_with_phase :: proc(phase: Phase, source: string) -> ^Proposal_Group {
	group: ^Proposal_Group

	group        = autorelease(object_new(Proposal_Group, proposal_group_dealloc))
	group.phase  = phase
	group.source = strings.clone(source)
	return group
}


proposal_group_dealloc :: proc(self: ^Proposal_Group) {
	for i := 0; i < len(self.strings); i += 1 do delete(self.strings[i])
	delete(self.strings)
	delete(self.proposals)
	delete(self.ids)
	delete(self.source)
	delete(self.rejection)
}


proposal_group_phase :: proc(self: ^Proposal_Group) -> Phase {
	return self.phase
}


proposal_group_source :: proc(self: ^Proposal_Group) -> string {
	return self.source
}


proposal_group_cause :: proc(self: ^Proposal_Group) -> u64 {
	return self.cause
}


proposal_group_set_cause :: proc(self: ^Proposal_Group, cause: u64) {
	self.cause = cause
}


proposal_group_actor :: proc(self: ^Proposal_Group) -> Entity_ID {
	return self.actor
}


proposal_group_set_actor :: proc(self: ^Proposal_Group, actor: Entity_ID) {
	self.actor = actor
}


proposal_group_weight :: proc(self: ^Proposal_Group) -> u64 {
	return self.weight
}


proposal_group_set_weight :: proc(self: ^Proposal_Group, weight: u64) {
	self.weight = weight
}


proposal_group_count :: proc(self: ^Proposal_Group) -> uint {
	return uint(len(self.proposals))
}


// The proposals: proposal_group_count of them.
proposal_group_proposals :: proc(self: ^Proposal_Group) -> [^]Proposal {
	return raw_data(self.proposals)
}


proposal_group_new_handle :: proc(self: ^Proposal_Group) -> Entity_ID {
	self.handles += 1
	return handle(self.handles)
}


proposal_group_handle_count :: proc(self: ^Proposal_Group) -> u64 {
	return self.handles
}


proposal_group_set_handle_count :: proc(self: ^Proposal_Group, count: u64) {
	self.handles = count
}


// The group keeps its own copies of the strings its proposals name.
@(private = "file")
keep :: proc(self: ^Proposal_Group, s: cstring) -> cstring {
	if s == nil do return nil
	append(&self.strings, strings.clone_to_cstring(string(s)))
	return self.strings[len(self.strings) - 1]
}


proposal_group_add_proposal :: proc(self: ^Proposal_Group, proposal: Proposal) {
	proposal := proposal

	proposal.name = keep(self, proposal.name)
	proposal.key  = keep(self, proposal.key)
	append(&self.proposals, proposal)
}


@(private = "file")
proposal :: proc(kind: Proposal_Kind, target: Ref) -> Proposal {
	p: Proposal

	p.kind   = kind
	p.target = target
	return p
}


proposal_group_create :: proc(self: ^Proposal_Group, blueprint: cstring, key: cstring, location: Location) -> Entity_ID {
	p: Proposal

	p          = proposal(.Create, whole(NO_ENTITY))
	p.name     = blueprint
	p.key      = key
	p.location = location
	p.handle   = proposal_group_new_handle(self)
	proposal_group_add_proposal(self, p)
	return p.handle
}


proposal_group_destroy :: proc(self: ^Proposal_Group, target: Ref, reason: cstring) {
	p: Proposal

	p      = proposal(.Destroy, target)
	p.name = reason
	proposal_group_add_proposal(self, p)
}


proposal_group_set_of_to :: proc(self: ^Proposal_Group, field: cstring, target: Ref, value: i64) {
	p: Proposal

	p       = proposal(.Set_Field, target)
	p.name  = field
	p.value = value
	proposal_group_add_proposal(self, p)
}


proposal_group_set_of_to_text :: proc(self: ^Proposal_Group, field: cstring, target: Ref, text: cstring) {
	p: Proposal

	p      = proposal(.Set_Field, target)
	p.name = field
	p.key  = text if text != nil else ""
	proposal_group_add_proposal(self, p)
}


proposal_group_set_terrain :: proc(self: ^Proposal_Group, kind: cstring, tile: Location) {
	p: Proposal

	p          = proposal(.Set_Terrain, whole(NO_ENTITY))
	p.name     = kind
	p.location = tile
	proposal_group_add_proposal(self, p)
}


proposal_group_move_to :: proc(self: ^Proposal_Group, target: Ref, location: Location) {
	p: Proposal

	p          = proposal(.Move, target)
	p.location = location
	proposal_group_add_proposal(self, p)
}


proposal_group_move_to_expecting :: proc(self: ^Proposal_Group, target: Ref, location: Location, from: Location) {
	p: Proposal

	p          = proposal(.Move, target)
	p.location = location
	p.expected = from
	p.expects  = true
	proposal_group_add_proposal(self, p)
}


proposal_group_split :: proc(self: ^Proposal_Group, stack: Ref, count: i64, location: Location) -> Entity_ID {
	p: Proposal

	p          = proposal(.Split, stack)
	p.value    = count
	p.location = location
	p.handle   = proposal_group_new_handle(self)
	proposal_group_add_proposal(self, p)
	return p.handle
}


proposal_group_merge :: proc(self: ^Proposal_Group, target: Ref, stack: Ref) {
	p: Proposal

	p       = proposal(.Merge, target)
	p.other = stack
	proposal_group_add_proposal(self, p)
}


proposal_group_relate :: proc(self: ^Proposal_Group, edge: Edge_Kind, from: Ref, to: Ref) {
	p: Proposal

	p       = proposal(.Add_Edge, from)
	p.other = to
	p.edge  = edge
	proposal_group_add_proposal(self, p)
}


proposal_group_unrelate :: proc(self: ^Proposal_Group, edge: Edge_Kind, from: Ref, to: Ref) {
	p: Proposal

	p       = proposal(.Remove_Edge, from)
	p.other = to
	p.edge  = edge
	proposal_group_add_proposal(self, p)
}


proposal_group_emit_subject_other :: proc(self: ^Proposal_Group, kind: cstring, subject: Ref, other: Ref) {
	p: Proposal

	p       = proposal(.Event, subject)
	p.other = other
	p.name  = kind
	proposal_group_add_proposal(self, p)
}


proposal_group_emit_subject_other_amount :: proc(self: ^Proposal_Group, kind: cstring, subject: Ref, other: Ref, amount: i64, detail: cstring) {
	p: Proposal

	p       = proposal(.Event, subject)
	p.other = other
	p.name  = kind
	p.value = amount
	p.key   = detail
	proposal_group_add_proposal(self, p)
}


proposal_group_emit_subject_other_detail :: proc(self: ^Proposal_Group, kind: cstring, subject: Ref, other: Ref, detail: cstring) {
	p: Proposal

	p       = proposal(.Event, subject)
	p.other = other
	p.name  = kind
	p.key   = detail          // an event has no key: its detail rides there, and saves keep it
	proposal_group_add_proposal(self, p)
}


proposal_group_applied :: proc(self: ^Proposal_Group) -> bool {
	return self.applied
}


// "" when it was not rejected (nil in Objective-C).
proposal_group_rejection :: proc(self: ^Proposal_Group) -> string {
	return self.rejection
}


proposal_group_position :: proc(self: ^Proposal_Group) -> u64 {
	return self.position
}


proposal_group_id_for :: proc(self: ^Proposal_Group, handle: Entity_ID) -> Entity_ID {
	n: u64

	if !is_handle(handle) do return handle
	n = u64(handle) & ~HANDLE_BIT
	if n == 0 || n > u64(len(self.ids)) do return NO_ENTITY
	return self.ids[n - 1]
}


// rejection "" is none (nil).
proposal_group_set_applied :: proc(self: ^Proposal_Group, applied: bool, rejection: string, position: u64) {
	self.applied  = applied
	self.position = position
	// [_rejection autorelease]; _rejection = [rejection copy]: the copy is
	// made first, so a rejection passed back in survives
	copy := strings.clone(rejection)
	delete(self.rejection)
	self.rejection = copy
}


proposal_group_set_id :: proc(self: ^Proposal_Group, entity: Entity_ID, handle: Entity_ID) {
	n: u64
	i: uint

	n = u64(handle) & ~HANDLE_BIT
	if !is_handle(handle) || n == 0 do return
	if n > u64(len(self.ids)) {
		i = uint(len(self.ids))
		resize(&self.ids, int(n))
		for ; i < uint(n); i += 1 do self.ids[i] = NO_ENTITY
	}
	self.ids[n - 1] = entity
}

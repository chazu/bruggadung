package lab

// The lab's Objective-C protocols, as Odin types: a struct holding the
// conformer (`data`) and a procedure for each method, each taking `data`
// first. A conforming type gives a constructor, `<type>_as_<protocol>`,
// filling them in (scheduler_as_..., atmosphere_as_domain, ...). A nil
// procedure is a method the conformer doesn't have: where the Objective-C
// asked respondsToSelector: or conformsToProtocol:, the port asks whether the
// procedure is nil. A protocol value whose data is nil is no conformer (nil
// in Objective-C).

// Told when a record of a kind it watches is set or removed.
Record_Observer :: struct {
	data:           rawptr,
	changed_record: proc(data: rawptr, world: ^World, entity: Entity_ID, kind: uint),
}

// A component kind's behaviour on the reactions channel: it is told of each
// committed event whose subject has its component, and may submit groups.
Reactor :: struct {
	data:           rawptr,
	react_to_event: proc(data: rawptr, committer: ^Committer, event: ^Event, world: ^World),
}

// Engine machinery told after each round, before the reactions run: the
// activity system rechecks the activities bound to what changed. It may
// submit groups, which join the next round.
Round_Listener :: struct {
	data:             rawptr,
	did_commit_round: proc(data: rawptr, committer: ^Committer, round: u32, first: uint, last: uint),
}

// A system that keeps state of its own in saves, outside the world: a
// domain's carries, the agents' knowledge stores. A save asks each to check
// in, then writes its lines as "domain <name> ..."; restoring hands them
// back. savedState's lines are in the temporary allocator.
Saved_System :: struct {
	data:                rawptr,
	name:                proc(data: rawptr) -> string,
	check_in_all:        proc(data: rawptr),
	saved_state:         proc(data: rawptr) -> []string,
	restore_saved_state: proc(data: rawptr, lines: []string),
}

// A domain at the scheduler's boundary (BGDomain), and, when the coupled
// procedures are set, a coupled one (BGCoupledDomain): the scheduler's
// conformsToProtocol:@protocol(BGCoupledDomain) is `publish_into != nil`.
// The saved-system procedures are its BGSavedSystem side.
Domain :: struct {
	data:                rawptr,
	// BGSavedSystem
	name:                proc(data: rawptr) -> string,
	check_in_all:        proc(data: rawptr),
	saved_state:         proc(data: rawptr) -> []string,
	restore_saved_state: proc(data: rawptr, lines: []string),
	// BGDomain
	is_active:           proc(data: rawptr) -> bool,
	horizon_at:          proc(data: rawptr, t: Time) -> Horizon,
	// -advanceFrom:to:world:committer:
	advance_from:        proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer),
	// BGCoupledDomain, or nil
	publish_into:         proc(data: rawptr, snapshot: ^Snapshot),
	takes_contribution:   proc(data: rawptr, contribution: Contribution) -> bool,
	receive_contribution: proc(data: rawptr, contribution: Contribution),
	// -advanceFrom:to:world:committer:snapshot:outbox:
	advance_coupled:      proc(data: rawptr, t0: Time, t1: Time, world: ^World, committer: ^Committer,
	                           snapshot: ^Snapshot, outbox: ^Contributions),
}

// A domain's saved-system side, for a save.
domain_as_saved_system :: proc(d: Domain) -> Saved_System {
	return Saved_System{d.data, d.name, d.check_in_all, d.saved_state, d.restore_saved_state}
}

// Where inputs come from: scripted scenarios now, the player later. The
// input log is the replay log.
Input_Source :: struct {
	data:              rawptr,
	next_input_time:   proc(data: rawptr) -> Time,      // TIME_NEVER when there are none
	deliver_inputs_at: proc(data: rawptr, t: Time, world: ^World, committer: ^Committer),
}

// Activities with a due time: they bound steps, and their completions are
// submitted at the boundary they fall on.
Activity_Clock :: struct {
	data:            rawptr,
	next_completion: proc(data: rawptr) -> Time,        // TIME_NEVER when none is due
	complete_due_at: proc(data: rawptr, t: Time),
}

// The perception phase: after a boundary's commit rounds, before anyone
// decides. next_forgetting is optional (nil).
Perception_Phase :: struct {
	data:              rawptr,
	perceive_boundary: proc(data: rawptr, boundary: u64),
	next_forgetting:   proc(data: rawptr) -> Time,
}

// The decision phase: after perception, agents decide.
Decision_Phase :: struct {
	data:               rawptr,
	decide_boundary:    proc(data: rawptr, boundary: u64),
	next_decision_time: proc(data: rawptr) -> Time,
}

Scheduler_Observer :: struct {
	data:                rawptr,
	did_commit_boundary: proc(data: rawptr, scheduler: ^Scheduler, boundary: u64, groups: []^Proposal_Group),
}

// What an agent's goals make salient: Triangle patterns, printed (in the
// temporary allocator).
Concerns :: struct {
	data:        rawptr,
	concerns_of: proc(data: rawptr, agent: Entity_ID) -> []string,
}

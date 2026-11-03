package lab

// BGScheduler — the boundary loop of ARCHITECTURE.md ("The life of one
// boundary") and DOMAIN_SIMULATION.md §9. Each step is bounded by the run
// policy's stop time, the next input, and every active domain's horizon;
// domains advance to the bound, the coupled ones reading each other from a
// snapshot taken at step start, their contributions held in transit for the
// next step (BGCoupling.h); inputs due then are delivered; change
// commitment runs; the clock moves to the bound. A quiet world jumps.
//
// (ported from the Objective-C lab's sched/BGScheduler.m. The protocols it declares, BGSavedSystem,
// BGDomain, BGCoupledDomain, BGInputSource, BGActivityClock,
// BGPerceptionPhase, BGDecisionPhase and BGSchedulerObserver, are in
// protocols.odin.)

import "core:time"

// How far a domain may advance: a safe step (a duration) and the time of its
// next possible discrete event.
Horizon :: struct {
	safeStep:  Time,
	nextEvent: Time,
}


// Where a scheduler's time went: boundaries run, and the wall time (ns) of
// each phase of them. For measuring, not for the simulation.
Scheduler_Stats :: struct {
	boundaries:   u64,
	horizonNs:    u64,      // finding the next boundary
	domainsNs:    u64,
	commitNs:     u64,      // activities, inputs, commitment
	perceptionNs: u64,
	decisionNs:   u64,
}


Scheduler :: struct {
	using object: Object,
	stats:      Scheduler_Stats,
	world:      ^World,
	committer:  ^Committer,
	domains:    [dynamic]Domain,         // each one's data retained
	inputs:     Input_Source,
	activities: Activity_Clock,
	perception: Perception_Phase,
	decision:   Decision_Phase,
	observer:   Scheduler_Observer,
}


@(private = "file")
earlier :: proc(a: Time, b: Time) -> Time {
	return a if a.ms < b.ms else b
}


// A new scheduler, its count 1.
scheduler_init_with_world :: proc(world: ^World, committer: ^Committer) -> ^Scheduler {
	self := object_new(Scheduler, scheduler_dealloc)
	self.world     = retain(world)
	self.committer = retain(committer)
	self.domains   = make([dynamic]Domain)
	return self
}


scheduler_dealloc :: proc(self: ^Scheduler) {
	release(self.world)
	release(self.committer)
	for i := 0; i < len(self.domains); i += 1 do object_release(self.domains[i].data)
	delete(self.domains)
}


// A contribution no domain takes is lost: a content error, which a ledger
// shows.
scheduler_add_domain :: proc(self: ^Scheduler, domain: Domain) {
	object_retain(domain.data)
	append(&self.domains, domain)
}


// not retained
scheduler_set_inputs :: proc(self: ^Scheduler, inputs: Input_Source) {
	self.inputs = inputs
}


// not retained
scheduler_set_decision :: proc(self: ^Scheduler, decision: Decision_Phase) {
	self.decision = decision
}


// not retained
scheduler_set_perception :: proc(self: ^Scheduler, perception: Perception_Phase) {
	self.perception = perception
}


// not retained
scheduler_set_activities :: proc(self: ^Scheduler, activities: Activity_Clock) {
	self.activities = activities
}


// not retained
scheduler_set_observer :: proc(self: ^Scheduler, observer: Scheduler_Observer) {
	self.observer = observer
}


// clock_gettime( CLOCK_MONOTONIC): the monotonic clock, in ns.
@(private = "file")
now_ns :: proc() -> u64 {
	return u64(time.tick_now()._nsec)
}


scheduler_stats :: proc(self: ^Scheduler) -> Scheduler_Stats {
	return self.stats
}


// The time the next boundary would be at, if nothing stops it first.
scheduler_next_boundary_time :: proc(self: ^Scheduler) -> Time {
	d:     Domain
	h:     Horizon
	bound: Time
	t:     Time

	t     = world_time(self.world)
	bound = TIME_NEVER
	if self.inputs.data != nil do bound = earlier(bound, self.inputs.next_input_time(self.inputs.data))
	if self.activities.data != nil do bound = earlier(bound, self.activities.next_completion(self.activities.data))
	if self.decision.data != nil do bound = earlier(bound, self.decision.next_decision_time(self.decision.data))
	if self.perception.data != nil && self.perception.next_forgetting != nil {
		bound = earlier(bound, self.perception.next_forgetting(self.perception.data))
	}
	for i := 0; i < len(self.domains); i += 1 {
		d = self.domains[i]
		if !d.is_active(d.data) do continue
		h = d.horizon_at(d.data, t)
		if h.safeStep.ms < TIME_NEVER.ms - t.ms do bound = earlier(bound, time_make(t.ms + h.safeStep.ms))
		bound = earlier(bound, h.nextEvent)
	}
	// groups deferred from the last boundary commit at the next one, which comes soon
	if committer_has_pending(self.committer) do bound = earlier(bound, time_make(t.ms + 1))
	// time moves forward: only the first boundary, or an input, may be at the current time
	if bound.ms <= t.ms {
		bound = t
		if world_boundary(self.world) > 0 && !(self.inputs.data != nil && self.inputs.next_input_time(self.inputs.data).ms <= t.ms) {
			bound = time_make(t.ms + 1)
		}
	}
	return bound
}


// One boundary at `bound`: domains advance to it, then commitment runs there.
@(private = "file")
scheduler_boundary_at :: proc(self: ^Scheduler, bound: Time) {
	d:        Domain
	snapshot: ^Snapshot
	outbox:   ^Contributions
	c:        Contribution
	groups:   []^Proposal_Group
	t:        Time
	mark:     u64

	t    = world_time(self.world)
	mark = now_ns()

	// the coupled domains' values at step start
	snapshot = autorelease(snapshot_new())
	outbox   = autorelease(contributions_new())
	for i := 0; i < len(self.domains); i += 1 {
		d = self.domains[i]
		if d.publish_into != nil do d.publish_into(d.data, snapshot)
	}

	// advance every active domain to the bound
	for i := 0; i < len(self.domains); i += 1 {
		d = self.domains[i]
		if !d.is_active(d.data) do continue
		if d.publish_into != nil {
			d.advance_coupled(d.data, t, bound, self.world, self.committer, snapshot, outbox)
		} else {
			d.advance_from(d.data, t, bound, self.world, self.committer)
		}
	}

	// contributions into transit, for their targets' next steps
	for k: uint = 0; k < contributions_count(outbox); k += 1 {
		c = contributions_contribution_at_index(outbox, k)
		for j := 0; j < len(self.domains); j += 1 {
			d = self.domains[j]
			if d.publish_into != nil && d.takes_contribution(d.data, c) {
				d.receive_contribution(d.data, c)
				break
			}
		}
	}

	self.stats.domainsNs += now_ns() - mark
	mark                  = now_ns()

	// commit at the bound, with the inputs due then
	world_set_time(self.world, bound)
	world_set_boundary(self.world, world_boundary(self.world) + 1)
	if self.activities.data != nil do self.activities.complete_due_at(self.activities.data, bound)
	if self.inputs.data != nil && self.inputs.next_input_time(self.inputs.data).ms <= bound.ms {
		self.inputs.deliver_inputs_at(self.inputs.data, bound, self.world, self.committer)
	}
	groups = committer_commit_boundary(self.committer)
	world_settle_anchors(self.world)
	self.stats.commitNs += now_ns() - mark
	mark                 = now_ns()
	if self.perception.data != nil do self.perception.perceive_boundary(self.perception.data, world_boundary(self.world))
	self.stats.perceptionNs += now_ns() - mark
	mark                     = now_ns()
	if self.decision.data != nil do self.decision.decide_boundary(self.decision.data, world_boundary(self.world))
	self.stats.decisionNs += now_ns() - mark
	// what changed, read by perception if it ran: let go
	{
		n: uint

		free(world_take_touched(self.world, &n))
		free(world_take_vacated(self.world, &n))
		free(world_take_risen(self.world, &n))
	}
	self.stats.boundaries += 1
	if self.observer.data != nil do self.observer.did_commit_boundary(self.observer.data, self, world_boundary(self.world), groups)
}


// Runs one boundary, at most at `stop`. false when there is nothing to do
// before `stop`.
scheduler_step_until :: proc(self: ^Scheduler, stop: Time) -> bool {
	bound: Time
	mark:  u64

	mark  = now_ns()
	bound = scheduler_next_boundary_time(self)
	self.stats.horizonNs += now_ns() - mark
	if bound.ms > stop.ms || bound.ms == TIME_NEVER.ms do return false
	scheduler_boundary_at(self, bound)
	return true
}


// The run policy for now: run boundaries until `stop`, and one at `stop`
// itself, as a stop request inserts (the replay log records stops). Returns
// the number of boundaries run.
//
// A stop is a boundary too (ARCHITECTURE.md): the domains advance to it, so
// no time passes without them.
scheduler_run_until :: proc(self: ^Scheduler, stop: Time) -> uint {
	n: uint

	n = 0
	for scheduler_step_until(self, stop) do n += 1
	if world_time(self.world).ms < stop.ms {
		scheduler_boundary_at(self, stop)
		n += 1
	}
	return n
}

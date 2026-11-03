package lab

/*
 * BGActivities — activities under way (ACTIONS.md §5). An activity is an
 * entity with an Activity component, started by BGPerform. This is the
 * engine machinery that ends them:
 *
 *   - a timed activity completes a stage at its due time: the stage's effect
 *     commits then, and the next stage starts; if commitment rejects it, the
 *     activity fails
 *   - a running timed activity whose bound entities are gone or out of the
 *     actor's reach, or whose operation's pattern no longer holds, is
 *     suspended, or fails, as its stage declares (a hard interruption,
 *     ACTIONS.md §5)
 *   - an activity with a watch completes when its domain reports the watch
 *     ("watched", from the fluid domain)
 *   - a fill ends, "exhausted", when its tap reports its source ran dry
 *   - a stage whose progress shows in the world (ACTIONS.md §5's partial
 *     effects) commits it in proportion at its checkpoints, which bound
 *     steps, and when it is suspended, aborted, or fails
 *
 * It follows each commit round (a round listener) and bounds the
 * scheduler's steps by the next completion (an activity clock).
 *
 * (act/BGActivities.h and .m)
 */

import "core:fmt"
import "core:mem"
import "core:slice"
import tri "../../triangle/odin/triangle"

// PORT: act/BGActions isn't ported yet; its procedures are called here as
// the header reads: NSString results and parameters as string ("" for nil),
// const char * as cstring, BGOperationPartial's `int *role` as ^i32 (compared
// with i32(Role.Item)), Action.roles indexed by Role (as [Role.Count]
// Entity_ID allows), BGMatchAction returning tri.Match. Follow whatever
// act_actions.odin settles.

/* An activity's next time due: a stage ending, or a checkpoint. */
Activity_Timer :: struct {
	at:       i64,
	activity: Entity_ID,
}


// One of _completions' pairs: the group (retained), the activity.
@(private = "file")
Completion :: struct {
	group:    ^Proposal_Group,
	activity: Entity_ID,
}


Activities :: struct {
	using object: Object,
	world:        ^World,
	committer:    ^Committer,               /* not retained: the committer retains us */
	completions:  [dynamic]Completion,      /* pairs: the group, the activity */
	/* when each running activity is next due, a heap, earliest first; an
	 * entry may be stale, and is checked against the record when it comes
	 * up. Built from the store when first wanted, kept by the world's word
	 * of every change: not saved */
	timers:       [^]Activity_Timer,
	ntimers:      uint,
	timercap:     uint,
	timed:        bool,
}


/* Creates the activity system and registers it with the committer. */
activities_with_world :: proc(world: ^World, committer: ^Committer) -> ^Activities {
	activities: ^Activities

	activities             = autorelease(object_new(Activities, activities_dealloc))
	activities.world       = retain(world)
	activities.committer   = committer
	activities.completions = make([dynamic]Completion)
	committer_add_listener(committer, activities_as_round_listener(activities))
	world_set_activity_observer(world, activities_as_record_observer(activities))
	return activities
}


activities_dealloc :: proc(self: ^Activities) {
	if world_activity_observer(self.world).data == rawptr(self) {
		world_set_activity_observer(self.world, Record_Observer{})
	}
	free(self.timers)
	release(self.world)
	for c in self.completions do release(c.group)
	delete(self.completions)
}


activities_as_activity_clock :: proc(self: ^Activities) -> Activity_Clock {
	return Activity_Clock{
		data = self,
		next_completion = proc(data: rawptr) -> Time {
			return activities_next_completion((^Activities)(data))
		},
		complete_due_at = proc(data: rawptr, t: Time) {
			activities_complete_due_at((^Activities)(data), t)
		},
	}
}


activities_as_round_listener :: proc(self: ^Activities) -> Round_Listener {
	return Round_Listener{
		data = self,
		did_commit_round = proc(data: rawptr, committer: ^Committer, round: u32, first: uint, last: uint) {
			activities_did_commit_round((^Activities)(data), committer, round, first, last)
		},
	}
}


activities_as_record_observer :: proc(self: ^Activities) -> Record_Observer {
	return Record_Observer{
		data = self,
		changed_record = proc(data: rawptr, world: ^World, entity: Entity_ID, kind: uint) {
			activities_changed_record((^Activities)(data), world, entity, kind)
		},
	}
}


@(private = "file")
running :: proc(world: ^World, a: Entity_ID, record: ^Activity) -> bool {
	return record != nil && record.status == u32(tri.type_named(world_tri(world), "\"running\""))
}


@(private = "file")
action_of :: proc(world: ^World, a: Entity_ID, record: ^Activity) -> Action {
	action: Action
	words:  cstring

	action = action_make(world_text_field(world, "Activity.operation", a), Entity_ID(record.actorRef),
	                     Entity_ID(record.itemRef), Entity_ID(record.destinationRef))
	words  = world_text_field(world, "Activity.words", a)
	if words != nil && (^u8)(words)^ != 0 do action.content = words
	return action
}


/* --- partial effects ---------------------------------------------------------- */

/* The stage's progress at `t`: kept, plus its running since it started. */
@(private = "file")
progress_at :: proc(record: ^Activity, t: i64) -> i64 {
	rate: i64

	rate = record.pace if record.pace > 0 else 100
	return record.progress + ((t - record.started) * rate / 100 if record.due != 0 else 0)
}


/* When the stage's next checkpoint falls, after `t`; or BGTimeNever. */
@(private = "file")
next_checkpoint :: proc(world: ^World, a: Entity_ID, record: ^Activity, t: i64) -> i64 {
	operation: cstring
	field:     cstring
	effect:    string
	duration:  i64
	whole_:    i64
	n:         i64
	k:         i64
	at:        i64
	role:      i32

	operation = world_text_field(world, "Activity.operation", a)
	if record.due == 0 || !operation_stage(world, operation, record.stage, &duration, &effect) ||
	   !operation_partial(world, operation, record.stage, &field, &role, &whole_, &n) {
		return TIME_NEVER.ms
	}
	for k = 1; k <= n; k += 1 {
		at = record.started + at_rate(duration * k / (n + 1) - record.progress, record.pace)
		if at > t do return at
	}
	return TIME_NEVER.ms
}


/* The stage's partial effect at `progress`, into the group: its field set
 * in proportion. */
@(private = "file")
activities_partial_of :: proc(self: ^Activities, a: Entity_ID, record: ^Activity, progress: i64, group: ^Proposal_Group) {
	progress := progress
	operation: cstring
	field:     cstring
	effect:    string
	target:    Entity_ID
	duration:  i64
	whole_:    i64
	n:         i64
	role:      i32

	operation = world_text_field(self.world, "Activity.operation", a)
	if !operation_stage(self.world, operation, record.stage, &duration, &effect) ||
	   !operation_partial(self.world, operation, record.stage, &field, &role, &whole_, &n) {
		return
	}
	target = Entity_ID(record.itemRef if role == i32(Role.Item) else record.destinationRef)
	if target == NO_ENTITY || !world_is_live(self.world, target) do return
	if progress > duration do progress = duration
	proposal_group_set_of_to(group, field, whole(target), whole_ * (0 if progress < 0 else progress) / duration)
}


/* --- the clock ----------------------------------------------------------------- */

@(private = "file")
has_ended :: proc(record: ^Activity) -> bool {
	return record.status != ACTIVITYSTATUS_RUNNING && record.status != ACTIVITYSTATUS_SUSPENDED
}


/* Whether an ended activity is still asked of: its actor's latest, or, per
 * operation, the completed one that started last (an agent asks whether it
 * did a thing since a time, which only that one can answer). */
@(private = "file")
activities_keeps :: proc(self: ^Activities, b: Entity_ID, mine: [^]Entity_ID, n: uint) -> bool {
	record:  ^Activity
	other:   ^Activity
	op:      cstring
	otherOp: cstring
	i:       uint

	if b == mine[n - 1] do return true
	record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), b))
	if record.status != ACTIVITYSTATUS_COMPLETED do return false
	op = world_text_field(self.world, "Activity.operation", b)
	for i = 0; i < n; i += 1 {
		if mine[i] == b do continue
		other = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), mine[i]))
		if other == nil || other.status != ACTIVITYSTATUS_COMPLETED do continue
		otherOp = world_text_field(self.world, "Activity.operation", mine[i])
		if op != nil && otherOp != nil && op == otherOp &&
		   (other.started > record.started || (other.started == record.started && mine[i] > b)) {
			return false
		}
	}
	return true
}


/* Lets go of an actor's activities that have ended and that nothing asks
 * of any more, in a group of its own: the Activity store holds what is
 * under way, and what is still asked of, not all that ever was. Done in the
 * round its activities ended, read from the world then; the group, if not
 * yet committed, is saved with the deferred, so a game saved and resumed
 * lets go of the same. */
@(private = "file")
activities_let_go_of :: proc(self: ^Activities, actor: Entity_ID) {
	record: ^Activity
	group:  ^Proposal_Group
	mine:   [^]Entity_ID
	n:      uint
	j:      uint

	group = nil
	mine  = world_copy_activities_of(self.world, actor, &n)
	for j = 0; j < n; j += 1 {
		record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), mine[j]))
		if !has_ended(record) || activities_keeps(self, mine[j], mine, n) do continue
		if group == nil {
			group = proposal_group_group_with_phase(.System, fmt.tprintf("activities: %d's ended let go", actor))
		}
		proposal_group_destroy(group, whole(mine[j]), "ended")
	}
	free(mine)
	if group != nil do committer_submit(self.committer, group)
}


/* The actors whose activities ended in a round's events, each once. */
@(private = "file")
activities_let_go_after :: proc(self: ^Activities, first: uint, last: uint) {
	record:  ^Activity
	ev:      ^Event
	actors:  [^]Entity_ID
	nactors: uint
	i:       uint

	actors  = make([^]Entity_ID, last - first + 1)
	nactors = 0
	for i = first; i < last; i += 1 {
		ev = world_event_at(self.world, i)
		if ev.kind != "changed" || ev.detail == nil || ev.detail != "Activity.status" do continue
		record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), ev.subject))
		if record == nil || !has_ended(record) do continue
		actors[nactors] = Entity_ID(record.actorRef)
		nactors += 1
	}
	slice.sort(actors[:nactors])          // qsort by cmp_actor: ties are equal IDs
	for i = 0; i < nactors; i += 1 {
		if i == 0 || actors[i] != actors[i - 1] do activities_let_go_of(self, actors[i])
	}
	free(actors)
}


/* --- the timers ------------------------------------------------------------- */

/* When a running activity is next due, as of `t`: its stage's end, or a
 * checkpoint before; never, not running. */
@(private = "file")
activities_due_of :: proc(self: ^Activities, a: Entity_ID, t: i64) -> i64 {
	record: ^Activity
	at:     i64
	check:  i64

	record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), a))
	if !running(self.world, a, record) do return TIME_NEVER.ms
	/* its actor frozen (REALITY.md step 4): it waits, and is told when it rises */
	if world_detail_of(self.world, Entity_ID(record.actorRef)) == i32(Detail.Frozen) do return TIME_NEVER.ms
	at    = record.due if record.due > 0 else TIME_NEVER.ms
	check = next_checkpoint(self.world, a, record, t)
	return check if check < at else at
}


@(private = "file")
timer_before :: proc(x: ^Activity_Timer, y: ^Activity_Timer) -> bool {
	return x.at < y.at || (x.at == y.at && x.activity < y.activity)
}


@(private = "file")
activities_push :: proc(self: ^Activities, a: Entity_ID, at: i64) {
	t: Activity_Timer
	i: uint

	if at == TIME_NEVER.ms do return
	if self.ntimers == self.timercap {
		old := self.timercap
		self.timercap = self.timercap * 2 if self.timercap != 0 else 64
		p, _ := mem.resize(self.timers, int(old * size_of(Activity_Timer)), int(self.timercap * size_of(Activity_Timer)))
		self.timers = ([^]Activity_Timer)(p)
	}
	self.timers[self.ntimers].at       = at
	self.timers[self.ntimers].activity = a
	i = self.ntimers
	self.ntimers += 1
	for ; i != 0 && timer_before(&self.timers[i], &self.timers[(i - 1) / 2]); i = (i - 1) / 2 {
		t                           = self.timers[i]
		self.timers[i]              = self.timers[(i - 1) / 2]
		self.timers[(i - 1) / 2]    = t
	}
}


@(private = "file")
activities_pop :: proc(self: ^Activities) -> Activity_Timer {
	top: Activity_Timer
	t:   Activity_Timer
	i:   uint
	c:   uint

	top = self.timers[0]
	self.ntimers -= 1
	self.timers[0] = self.timers[self.ntimers]
	for i = 0;; i = c {
		c = 2 * i + 1
		if c >= self.ntimers do break
		if c + 1 < self.ntimers && timer_before(&self.timers[c + 1], &self.timers[c]) do c += 1
		if !timer_before(&self.timers[c], &self.timers[i]) do break
		t              = self.timers[i]
		self.timers[i] = self.timers[c]
		self.timers[c] = t
	}
	return top
}


/* The timers, from the store, the first time they are wanted. */
@(private = "file")
activities_time :: proc(self: ^Activities) {
	store: ^Store
	i:     uint

	if self.timed do return
	self.timed = true
	store      = world_store_for_kind(self.world, world_kind_named(self.world, "Activity"))
	for i = 0; i < store_count(store); i += 1 {
		activities_push(self, store_entity_at_index(store, i),
		                activities_due_of(self, store_entity_at_index(store, i), world_time(self.world).ms))
	}
}


/* The world's word: an activity changed, so when it is due may have. */
activities_changed_record :: proc(self: ^Activities, world: ^World, entity: Entity_ID, kind: uint) {
	if self.timed {
		activities_push(self, entity, activities_due_of(self, entity, world_time(self.world).ms))
	}
}


/* The earliest timer that is still so: a stale one (the activity ended, or
 * due another time now) let go, its due time pushed again. */
activities_next_completion :: proc(self: ^Activities) -> Time {
	top: Activity_Timer
	at:  i64

	activities_time(self)
	for self.ntimers != 0 {
		top = self.timers[0]
		at  = activities_due_of(self, top.activity, world_time(self.world).ms)
		if at == top.at do return time_make(at)
		activities_pop(self)
		activities_push(self, top.activity, at)      /* again, if it is due at all */
	}
	return TIME_NEVER
}


activities_complete_due_at :: proc(self: ^Activities, t: Time) {
	record:    ^Activity
	group:     ^Proposal_Group
	due:       [^]Entity_ID
	a:         Entity_ID
	reason:    string
	effect:    string
	operation: cstring
	ndue:      uint
	i:         uint
	duration:  i64
	rate:      i64
	more:      bool

	/* what is due by now, from the timers, in entity order; each pushed
	 * again for its next */
	activities_time(self)
	due  = make([^]Entity_ID, self.ntimers + 1)
	ndue = 0
	for self.ntimers != 0 && self.timers[0].at <= t.ms {
		due[ndue] = activities_pop(self).activity
		ndue += 1
	}
	slice.sort(due[:ndue])                // qsort by cmp_actor: ties are equal IDs
	for i = 0; i < ndue; i += 1 {
		if i != 0 && due[i] == due[i - 1] do continue
		a      = due[i]
		record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), a))
		activities_push(self, a, activities_due_of(self, a, t.ms))
		if record == nil || record.due == 0 || !running(self.world, a, record) do continue
		/* a checkpoint: the stage's progress shows */
		if record.due > t.ms {
			if next_checkpoint(self.world, a, record, t.ms - 1) == t.ms {
				group = proposal_group_group_with_phase(.Action, fmt.tprintf("activity %d: checkpoint", a))
				proposal_group_set_cause(group, activities_start_of(self, a))
				activities_partial_of(self, a, record, progress_at(record, t.ms), group)
				committer_submit(self.committer, group)
			}
			continue
		}
		operation = world_text_field(self.world, "Activity.operation", a)
		more      = operation_stage(self.world, operation, record.stage + 1, &duration, &effect)
		group     = proposal_group_group_with_phase(.Action,
		                                            fmt.tprintf("activity %d: %s %s",
		                                                        a, operation,
		                                                        fmt.tprintf("stage %d done", record.stage) if more else "completes"))
		proposal_group_set_cause(group, activities_start_of(self, a))
		proposal_group_set_actor(group, Entity_ID(record.actorRef))
		proposal_group_set_weight(group, contest_weight(self.world, Entity_ID(record.actorRef), operation))
		if !operation_stage(self.world, operation, record.stage, &duration, &effect) do effect = ""
		/* what it needs must still hold when its effect commits: taken from
		 * the bench by someone else meanwhile, the seal is not to be taken
		 * from their hand */
		reason = activities_requirements_of(self, a, record)
		if reason == "" {
			reason = apply_named_effect(self.world, effect, action_of(self.world, a, record), record.amount, group)
		}
		/* the effort tells on the actor */
		if reason == "" && operation_exertion(self.world, operation, record.stage) != 0 {
			fatigue: i64

			fatigue = 0
			world_get_field(self.world, "Agent.fatigue", Entity_ID(record.actorRef), &fatigue)
			fatigue += operation_exertion(self.world, operation, record.stage)
			proposal_group_set_of_to(group, "Agent.fatigue", whole(Entity_ID(record.actorRef)), 100 if fatigue > 100 else fatigue)
		}
		if reason != "" {
			activities_end(self, a, "failed", reason, activities_start_of(self, a))
			continue
		}
		/* the stage's own traces, with its effect */
		leave_stage_traces(self.world, action_of(self.world, a, record), record.stage, group)
		if operation_stage(self.world, operation, record.stage + 1, &duration, &effect) {
			/* the next stage starts now */
			proposal_group_set_of_to(group, "Activity.stage", whole(a), record.stage + 1)
			proposal_group_set_of_to(group, "Activity.progress", whole(a), 0)
			proposal_group_set_of_to(group, "Activity.started", whole(a), t.ms)
			rate = graded_rate(self.world, action_of(self.world, a, record),
			                   work_rate(self.world, Entity_ID(record.actorRef), operation, record.stage + 1))
			proposal_group_set_of_to(group, "Activity.pace", whole(a), rate)
			proposal_group_set_of_to(group, "Activity.due", whole(a), t.ms + at_rate(duration, rate))
		} else {
			leave_traces(self.world, action_of(self.world, a, record), group)
			proposal_group_set_of_to(group, "Activity.status", whole(a), i64(tri.type_named(world_tri(self.world), "\"completed\"")))
			/* ended: its watches with it */
			if record.watchHolder != 0 do proposal_group_set_of_to(group, "Activity.watchHolder", whole(a), 0)
			if record.watchFloor != 0 do proposal_group_set_of_to(group, "Activity.watchFloor", whole(a), 0)
		}
		committer_submit(self.committer, group)
		append(&self.completions, Completion{retain(group), a})
	}
	free(due)
}


/* The event that created the activity: what its completion follows from. */
@(private = "file")
activities_start_of :: proc(self: ^Activities, a: Entity_ID) -> u64 {
	return world_creation_of(self.world, a)
}


/* --- ending ------------------------------------------------------------------- */

/* Ends an activity: its operation's own clean-up (a fill closes its tap), the
 * status, and the watch removed. */
@(private = "file")
activities_end :: proc(self: ^Activities, a: Entity_ID, status: cstring, why: string, cause: u64) -> ^Proposal_Group {
	record: ^Activity
	group:  ^Proposal_Group
	atom:   cstring

	record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), a))
	if record == nil do return nil
	group = proposal_group_group_with_phase(.System, fmt.tprintf("activity %d: %s (%s)", a, status, why))
	proposal_group_set_cause(group, cause)
	if operation_effect(self.world, world_text_field(self.world, "Activity.operation", a)) == "fill" {
		proposal_group_set_of_to(group, "Tap.open", whole(Entity_ID(record.itemRef)), 0)
	}
	atom = ns_utf8(fmt.tprintf("\"%s\"", status))      // snprintf into 32 bytes: the statuses are short
	proposal_group_set_of_to(group, "Activity.status", whole(a), i64(tri.type_named(world_tri(self.world), atom)))
	if record.watchHolder != 0 do proposal_group_set_of_to(group, "Activity.watchHolder", whole(a), 0)
	if record.watchFloor != 0 do proposal_group_set_of_to(group, "Activity.watchFloor", whole(a), 0)
	/* stopped short: what its progress shows stays in the world */
	if status != "completed" {
		activities_partial_of(self, a, record, progress_at(record, world_time(self.world).ms), group)
	}
	committer_submit(self.committer, group)
	return group
}


/* The actor's choice to give it up: its progress is discarded, what it
 * showed of it stays. */
activities_abort :: proc(self: ^Activities, a: Entity_ID, why: string, error: ^string) -> ^Proposal_Group {
	record: ^Activity

	record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), a))
	if record == nil || !(running(self.world, a, record) ||
	                      record.status == u32(tri.type_named(world_tri(self.world), "\"suspended\""))) {
		if error != nil do error^ = fmt.tprintf("%d is not under way", a)
		return nil
	}
	return activities_end(self, a, "aborted", why, activities_start_of(self, a))
}


/* --- suspending and resuming ---------------------------------------------------- */

/* Why the activity can't go on: a bound entity gone, or out of the actor's
 * reach. "" for none (nil). */
@(private = "file")
activities_obstacle_to :: proc(self: ^Activities, a: Entity_ID, record: ^Activity) -> string {
	bound: [3]Entity_ID
	view:  ^View
	i:     i32

	bound[0] = Entity_ID(record.actorRef)
	bound[1] = Entity_ID(record.itemRef)
	bound[2] = Entity_ID(record.destinationRef)
	if !world_is_live(self.world, bound[0]) do return "its actor is gone"
	view = view_of(bound[0], self.world)
	for i = 1; i < 3; i += 1 {
		if bound[i] == NO_ENTITY do continue
		if !world_is_live(self.world, bound[i]) do return fmt.tprintf("%d is gone", bound[i])
		if !view_can_reach(view, bound[i]) do return fmt.tprintf("%d is out of reach", bound[i])
	}
	return ""
}


/* The actor's choice, through commitment: suspending keeps the stage's
 * progress; resuming rechecks that everything bound is still there and in
 * reach, and runs what is left of the stage. nil, with the reason, if it
 * can't. */
activities_suspend :: proc(self: ^Activities, a: Entity_ID, why: string, error: ^string) -> ^Proposal_Group {
	record: ^Activity
	group:  ^Proposal_Group
	now:    i64

	record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), a))
	if !running(self.world, a, record) || record.due == 0 {
		if error != nil do error^ = fmt.tprintf("%d is not a timed activity under way", a)
		return nil
	}
	now   = world_time(self.world).ms
	group = proposal_group_group_with_phase(.Action, fmt.tprintf("activity %d: suspended (%s)", a, why))
	proposal_group_set_of_to(group, "Activity.progress", whole(a), progress_at(record, now))
	proposal_group_set_of_to(group, "Activity.due", whole(a), 0)
	activities_partial_of(self, a, record, progress_at(record, now), group)
	proposal_group_set_of_to(group, "Activity.status", whole(a), i64(tri.type_named(world_tri(self.world), "\"suspended\"")))
	committer_submit(self.committer, group)
	return group
}


/* What the operation needs, rechecked on resume (ACTIONS.md Scenario 3):
 * its pattern against what is so now; the reason if it no longer holds,
 * else nil. Unknown doesn't block. ("" for nil.) */
@(private = "file")
activities_requirements_of :: proc(self: ^Activities, a: Entity_ID, record: ^Activity) -> string {
	result: tri.Match_Result
	why:    string

	why = ""
	if match_action(self.world, action_of(self.world, a, record), &result, &why) != .Incompatible do return ""
	return fmt.tprintf("what it needs no longer holds, at %s", cstring(&result.failure.path[0]))
}


activities_resume :: proc(self: ^Activities, a: Entity_ID, error: ^string) -> ^Proposal_Group {
	record:    ^Activity
	group:     ^Proposal_Group
	reason:    string
	effect:    string
	duration:  i64
	remaining: i64
	rate:      i64
	now:       i64

	record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), a))
	if record == nil || record.status != u32(tri.type_named(world_tri(self.world), "\"suspended\"")) {
		if error != nil do error^ = fmt.tprintf("%d is not suspended", a)
		return nil
	}
	// C's chain of (reason = ...) || ...: each tried only while none gave a reason
	reason = activities_obstacle_to(self, a, record)
	if reason == "" {
		reason = providers_busy(self.world, Entity_ID(record.actorRef), world_text_field(self.world, "Activity.operation", a), a)
	}
	if reason == "" do reason = activities_requirements_of(self, a, record)
	if reason != "" ||
	   !operation_stage(self.world, world_text_field(self.world, "Activity.operation", a), record.stage, &duration, &effect) {
		if error != nil do error^ = reason if reason != "" else "it has no stage to resume"
		return nil
	}
	now   = world_time(self.world).ms
	group = proposal_group_group_with_phase(.Action, fmt.tprintf("activity %d: resumed", a))
	proposal_group_set_of_to(group, "Activity.started", whole(a), now)
	/* what it owes: the stage, and bringing its instruments to bear as
	 * they lie now, less what it did before */
	rate      = graded_rate(self.world, action_of(self.world, a, record),
	                        work_rate(self.world, Entity_ID(record.actorRef),
	                                  world_text_field(self.world, "Activity.operation", a), record.stage))
	remaining = at_rate(duration - record.progress, rate)
	if record.stage == 0 do remaining += access_delay(self.world, action_of(self.world, a, record))
	proposal_group_set_of_to(group, "Activity.pace", whole(a), rate)
	proposal_group_set_of_to(group, "Activity.due", whole(a), now + (remaining if remaining > 0 else 0))
	proposal_group_set_of_to(group, "Activity.status", whole(a), i64(tri.type_named(world_tri(self.world), "\"running\"")))
	committer_submit(self.committer, group)
	return group
}


/* Resuming with another instrument in the item role (ACTIONS.md Scenario 3:
 * the wrench gone, the player improvises): the operation's pattern is
 * rechecked with it, and the activity binds it from now on. */
activities_improvise :: proc(self: ^Activities, a: Entity_ID, instrument: Entity_ID, error: ^string) -> ^Proposal_Group {
	record: ^Activity
	group:  ^Proposal_Group
	result: tri.Match_Result
	action: Action
	why:    string

	record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), a))
	if record == nil || record.status != u32(tri.type_named(world_tri(self.world), "\"suspended\"")) {
		if error != nil do error^ = fmt.tprintf("%d is not suspended", a)
		return nil
	}
	action                  = action_of(self.world, a, record)
	action.roles[Role.Item] = instrument
	why                     = ""
	if match_action(self.world, action, &result, &why) == .Incompatible {
		if error != nil {
			error^ = fmt.tprintf("%d won't do for it: %s", instrument,
			                     why if why != "" else string(cstring(&result.failure.path[0])))
		}
		return nil
	}
	group = proposal_group_group_with_phase(.Action, fmt.tprintf("activity %d: improvised with %d", a, instrument))
	proposal_group_set_of_to(group, "Activity.itemRef", whole(a), i64(instrument))
	committer_submit(self.committer, group)
	return group
}


/* A rate input changed (ACTIONS.md §5: "A change to any rate input ...
 * recomputes it"): the stage under way keeps what it has done, and goes on
 * from now at the actor's pace now. */
@(private = "file")
activities_repace :: proc(self: ^Activities, a: Entity_ID, record: ^Activity, cause: u64) {
	group:     ^Proposal_Group
	effect:    string
	operation: cstring
	duration:  i64
	pace:      i64
	done:      i64
	now:       i64

	operation = world_text_field(self.world, "Activity.operation", a)
	if !operation_stage(self.world, operation, record.stage, &duration, &effect) do return
	pace = graded_rate(self.world, action_of(self.world, a, record),
	                   work_rate(self.world, Entity_ID(record.actorRef), operation, record.stage))
	if pace == (record.pace if record.pace > 0 else 100) do return
	now   = world_time(self.world).ms
	done  = progress_at(record, now)
	group = proposal_group_group_with_phase(.Action, fmt.tprintf("activity %d: its pace now %d%%", a, pace))
	proposal_group_set_cause(group, cause)
	proposal_group_set_of_to(group, "Activity.progress", whole(a), done)
	proposal_group_set_of_to(group, "Activity.started", whole(a), now)
	proposal_group_set_of_to(group, "Activity.pace", whole(a), pace)
	proposal_group_set_of_to(group, "Activity.due", whole(a), now + at_rate(duration - done if duration > done else 0, pace))
	committer_submit(self.committer, group)
}


@(private = "file")
contains_id :: proc(list: [^]Entity_ID, n: uint, e: Entity_ID) -> bool {
	i: uint

	for i = 0; i < n; i += 1 {
		if list[i] == e do return true
	}
	return false
}


/* An activity ended this round, kept to be told of once. */
@(private = "file")
remember_ended :: proc(ended: [^]Entity_ID, n: ^uint, cap_: ^uint, a: Entity_ID) -> [^]Entity_ID {
	ended := ended

	if n^ == cap_^ {
		old := cap_^
		cap_^ = cap_^ * 2 if cap_^ != 0 else 64
		p, _ := mem.resize(ended, int(old * size_of(Entity_ID)), int(cap_^ * size_of(Entity_ID)))
		ended = ([^]Entity_ID)(p)
	}
	ended[n^] = a
	n^ += 1
	return ended
}


activities_did_commit_round :: proc(self: ^Activities, committer: ^Committer, round: u32, first: uint, last: uint) {
	record:    ^Activity
	ev:        ^Event
	group:     ^Proposal_Group
	ended:     [^]Entity_ID
	touching:  [^]Entity_ID
	ntouching: uint
	endedcap:  uint
	a:         Entity_ID
	effect:    string
	why:       string
	nended:    uint
	i:         uint
	j:         uint
	k:         uint
	done:      bool

	ended     = nil
	endedcap  = 0
	touching  = nil
	ntouching = 0

	/* a completion commitment rejected: the activity failed */
	for i = 0; i < uint(len(self.completions)); {
		group = self.completions[i].group
		a     = self.completions[i].activity
		if proposal_group_position(group) == 0 {
			i += 1
			continue
		}
		if !proposal_group_applied(group) {
			activities_end(self, a, "failed", proposal_group_rejection(group), proposal_group_cause(group))
		}
		ordered_remove(&self.completions, int(i))
		release(group)
	}

	/* what this round's events mean for the activities bound to their
	 * subjects: those it takes part in (the world's index), in entity
	 * order, then the subject itself, if it is an activity */
	nended = 0
	for i = first; i < last; i += 1 {
		ev       = world_event_at(self.world, i)
		touching = world_copy_activities_touching(self.world, ev.subject, &ntouching) if ev.subject != 0 else nil
		for j = 0; j <= ntouching; j += 1 {
			/* then the subject itself, if it is an activity */
			if j == ntouching {
				a = ev.subject if world_record(self.world, world_kind_named(self.world, "Activity"), ev.subject) != nil &&
				                  !contains_id(touching, ntouching, ev.subject) else NO_ENTITY
			} else {
				a = touching[j]
			}
			if a == NO_ENTITY do continue
			record = (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), a))
			if record == nil || !running(self.world, a, record) do continue
			for done, k = false, 0; k < nended && !done; k += 1 {
				done = ended[k] == a
			}
			if done do continue
			effect = operation_effect(self.world, world_text_field(self.world, "Activity.operation", a))
			if ev.kind == "watched" && ev.subject == a && record.watchFloor != 0 {
				/* water rising at its feet: an interruption, its watch removed */
				group = activities_suspend(self, a, "water is rising at its feet", nil)
				if group != nil {          // a message to nil did nothing
					proposal_group_set_of_to(group, "Activity.watchFloor", whole(a), 0)
					proposal_group_set_cause(group, ev.index)
				}
				ended = remember_ended(ended, &nended, &endedcap, a)
			} else if ev.kind == "watched" && ev.subject == a {
				activities_end(self, a, "completed", "its watch fired", ev.index)
				ended = remember_ended(ended, &nended, &endedcap, a)
			} else if ev.kind == "exhausted" && ev.subject == Entity_ID(record.itemRef) && effect == "fill" {
				activities_end(self, a, "exhausted", "the source ran dry", ev.index)
				ended = remember_ended(ended, &nended, &endedcap, a)
			} else if record.due != 0 && ev.subject == Entity_ID(record.actorRef) && ev.kind == "changed" &&
			          ev.detail != nil && (ev.detail == "Agent.fatigue" || ev.detail == "Agent.injury") {
				activities_repace(self, a, record, ev.index)
			} else if record.due != 0 && (ev.subject == Entity_ID(record.actorRef) || ev.subject == Entity_ID(record.itemRef) ||
			                              ev.subject == Entity_ID(record.destinationRef)) {
				// C's (why = obstacle) || (why = requirements), the last condition of the chain
				why = activities_obstacle_to(self, a, record)
				if why == "" do why = activities_requirements_of(self, a, record)
				if why != "" {
					/* a hard interruption: what it binds is gone or out of reach, or
					 * what it needs no longer holds (the saw out of its hand): it is
					 * suspended, or fails, as its stage declares */
					if operation_fails_hard(self.world, world_text_field(self.world, "Activity.operation", a), record.stage) {
						activities_end(self, a, "failed", why, ev.index)
					} else {
						group = activities_suspend(self, a, why, nil)
						if group != nil do proposal_group_set_cause(group, ev.index)      // a message to nil did nothing
					}
					ended = remember_ended(ended, &nended, &endedcap, a)
				}
			}
		}
		free(touching)
		touching  = nil
		ntouching = 0
	}
	free(ended)
	/* what ended in the round, let go of */
	activities_let_go_after(self, first, last)
}

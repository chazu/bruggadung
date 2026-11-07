package lab

/*
 * BGAgency — agents that choose for themselves (AGENCY.md). In the decision
 * phase after perception, each agent agency controls, and that has no
 * activity under way, decides one step from its intention, reading only its
 * own knowledge store (the knowledge view). Everything it does is an action,
 * through the menu's machinery.
 *
 * Goals and methods are content (content/agency.tri, and each topic's
 * directory; AGENCY.md §5). A goal is done when its `done` condition holds; a
 * condition binds slots to referents the agent believes present and matches
 * the frame they describe, so nothing reads world state or truth. A method is
 * followed when its `pre` holds, its steps re-read at each decision: a
 * subgoal not yet done is adopted above the goal, which stays the intention
 * beneath it; an operation is performed once the agent has walked within
 * reach of what it names. A goal no method can serve is impossible for now:
 * it is dropped, with the reason, and the method that needed it has failed,
 * so the goal beneath tries its next.
 *
 * A step can say something (content/talk/talk.tri): after a question, the
 * agent waits for the one it asked to answer, a while at most, and a search
 * slot passes over whoever it has asked since adopting the goal.
 *
 * Being asked is a candidate goal (AGENCY.md §4's social generator, §11),
 * considered at every decision point: answering is worth the agent's trust
 * in the asker, plus its `helpful` disposition, less BG_BUSY_COST for each
 * point of attention its running activity demands, less BG_COMMITTED if it
 * holds a goal of its own. Worth more than nothing, it answers, from what it
 * knows: where it believes something like it is, and how it knows, or that
 * it doesn't know; asked who told it, the claim again, with its source.
 * Worth nothing only because it is busy, it answers once it isn't, if the
 * asker can still be waiting. Otherwise it says it won't. A request for
 * something it holds (comply or refuse) costs what lending it costs: its
 * worth to the agent (AGENCY.md decision 16), less by the agent's trust in
 * the asker. Granted, the agent gives what it holds like it, and says so;
 * with nothing like it in hand, it says it has none.
 *
 * Goals have worth (AGENCY.md §3): their considerations, added in dB, among
 * them the credence that something is so. A goal that `arises` from a kind
 * of finding (§4's reactive generator) is a candidate for each such finding
 * the agent holds, and is weighed against what the agent is doing at every
 * decision point, mid-activity too: it wins only if it is worth more than
 * the current intention plus BG_MARGIN plus, while an activity runs,
 * BG_INTERRUPT, so the agent doesn't dither. Winning, it suspends what the
 * agent was doing and goes on top; done, the agent goes back to it, and
 * resumes the activity it suspended. A goal that arose about something is
 * settled with it, and doesn't arise about it again.
 *
 * Commitments (AGENCY.md §7, §8): an agent undertakes a goal for a window,
 * from a source (employment, a promise). While the window is open, the
 * goal is a candidate (the routine generator), worth BG_DUTY plus an
 * urgency that rises to BG_URGENCY by the deadline, weighed like any other;
 * done, or impossible, it is settled for the window; when the window closes
 * it is dropped. The scheduler wakes the agent when a window opens or
 * closes.
 *
 * Needs (AGENCY.md §6): a goal `pressed` by a need is a candidate while the
 * agent feels the need above the goal's threshold (the needs generator),
 * worth the pressure of what it feels. Done or given up, it doesn't press
 * again until the need is felt 20 more.
 *
 * Habits (AGENCY.md §8): each time the agent performs a method's operation,
 * the method grows habitual for the goal, and each referent it acted on
 * for a slot grows habitual for that slot, BG_HABIT_GAIN a time, up to 100,
 * fading BG_HABIT_FADE a day, computed when read. Habitual methods win ties
 * (a tenth of the strength adds to the score), and a slot ordered by
 * "habit" tries its habitual referents first.
 *
 * Autopilot (AGENCY.md §14): the player hands their character to agency
 * with a goal and an interruption threshold. Agency decides for it from its
 * knowledge view, as for anyone, but takes up no goal of its own: when one
 * arises worth more than the threshold, or the goal is done or can't be,
 * control returns to the player, with a notice saying why.
 *
 * Walks (PERFORMANCE.md decision 1): to go to a place, the agent finds its
 * way once, over the ground as it believes it, and sets out on a walk: one
 * activity, a stage a tile. While it walks it decides only what any busy
 * agent does (questions, and what else might matter more); and at each
 * perception it checks the walk still makes sense: the way ahead still
 * believed open, what it goes to still where it was, still present, its
 * intention still the same, an unseen tile it explores toward still
 * unseen. If not, it gives the walk up, and decides afresh once it has
 * stopped. Put down for something else, a walk is given up, not
 * suspended: there is nothing to resume, only a way to find again.
 *
 * Each agent's motivation store (its intentions, with their bindings and
 * failed methods, what it waits for, and the decision count) is private and
 * saved, and every decision is logged for the developer.
 *
 * (ported from the Objective-C lab's agency/BGAgency.m)
 */

import "core:fmt"
import "core:slice"
import "core:strings"

import tri "../../triangle/odin/triangle"


BG_MAX_INTENTIONS  :: 8
BG_MAX_SLOTS       :: 8
BG_MAX_QUESTIONS   :: 8

BG_BUSY_COST       :: 3      /* per point of attention the running activity demands */
BG_COMMITTED       :: 5      /* for holding a goal of its own */
BG_WORTH           :: 10     /* what a thing is worth, with no value authored for it */
BG_VETO            :: 1000   /* what a veto counts: more than anything else can weigh */
BG_MARGIN          :: 5      /* what another goal must beat the current one by */
BG_INTERRUPT       :: 5      /* and more, to interrupt an activity under way */
BG_MAX_SETTLED     :: 16
BG_MAX_COMMITMENTS :: 16
BG_KEPT_RETRY :: i64(600000)     /* ms: a kept goal found impossible is tried again ten minutes later */
BG_NEED_RETRY :: i64(7200000)    /* ms: a need's goal found impossible is weighed again two hours later (rationing:
                                    the meal packed at dawn is eaten at work, not at once) */
@(private = "file") BG_AGAIN_WITHIN :: i64(1000)     /* ms: an act done again so soon is done again to no end... */
@(private = "file") BG_AGAIN_TIMES  :: 10            /* ...once it has been, so many times running */
BG_MAX_HABITS      :: 16
BG_HABIT_GAIN      :: 10     /* each repetition */
BG_HABIT_FADE      :: 1      /* a day */
BG_DUTY            :: 20     /* what a commitment is worth */
BG_URGENCY         :: 20     /* and more, rising toward its deadline */
BG_LOAN_TERM       :: i64(7 * 86400000)   /* a loan between friends is owed back within a week, */
BG_LOAN_SHORT      :: i64(86400000)       /* to anyone else, a day (AGENCY.md decision 18); */
BG_LOAN_DUE        :: 7                   /* repaid in the last seventh of its term */


Slot_Binding :: struct {
	slot:     cstring,       /* interned */
	referent: u32,
}


/* A goal adopted: the commitment at the bottom of the stack, a subgoal above
 * the goal whose method needed it. */
Intention :: struct {
	goal:       cstring,     /* interned: the goal's instance name */
	adopted:    i64,         /* ms */
	failed:     u32,         /* the goal's methods that failed since, by rank order */
	pending:    i32,         /* the method whose subgoal is above, or -1 */
	following:  i32,         /* the method last followed, or -1 */
	params:     [BG_MAX_SLOTS]Slot_Binding,
	nparams:    i32,
	arose:      u32,         /* the referent it arose about, or 0 */
	commitment: i32,         /* the commitment it keeps, + 1, or 0 */
	pressed:    i32,         /* a need raised it */
	stepsDone:  u32,         /* a sequence's instant steps done, by index */
}


/* A habit (AGENCY.md §8): a context, a choice, a strength. */
Habit :: struct {
	context_: cstring,       /* interned: "goal:method", "method.slot" (`context` is Odin's keyword) */
	choice:   u32,           /* the referent chosen for a slot; 0 for a method */
	strength: i32,           /* as of `at` */
	at:       i64,           /* ms */
}


/* A goal undertaken for a window (AGENCY.md §7). */
Commitment :: struct {
	goal:    cstring,        /* interned */
	from:    i64,            /* ms */
	until:   i64,            /* ms: its deadline */
	source:  cstring,        /* interned: "employment", "promise", "self" */
	every:   i64,            /* ms: it recurs, a window each period (a daily shift); 0, once */
	settled: bool,           /* done, or given up, for this window */
	resume:  i64,            /* ms: a kept goal found impossible is tried again from then; 0, now */
	params:  [BG_MAX_SLOTS]Slot_Binding,
	nparams: i32,
}


/* A method step's act, as last done, and how many times running it was done
 * again within BG_AGAIN_WITHIN of the last: an act that changes nothing it
 * knows of (a look into what it has looked into, its hands full) would be
 * chosen again at once, for ever. */
Repeated_Act :: struct {
	op:     cstring,         /* interned */
	item:   u32,
	target: u32,
	at:     i64,             /* ms */
	times:  i32,
}


/* A goal that arose about something: settled, or last weighed. */
Arisen :: struct {
	goal:    cstring,        /* interned */
	about:   u32,            /* referent */
	verdict: i32,            /* weighed: 1 switch, 0 stay; settled, a goal pressed: what was felt; one
	                            that arose: when, in seconds */
	retry:   i64,            /* settled, a goal pressed found impossible: when it is weighed again,
	                            felt more or not (ms); 0, once felt more */
	held:    u64,            /* and what it held then (agency_held_signature): it is weighed again once that
	                            changes (NEGOTIATION.md decision 11) */
}


/* A question put to the agent, not yet answered. */
Question :: struct {
	asker:    u32,           /* referent */
	content:  cstring,       /* interned */
	heard:    i64,           /* ms */
	deferred: bool,          /* "not now" is logged */
}


/* What a walk was set out on for (PERFORMANCE.md decision 1), to tell
 * when it no longer makes sense. */
Walk_Purpose :: struct {
	set:    bool,
	toward: u32,             /* the referent it goes to; 0, exploring, or wandering */
	wander: bool,            /* to a tile it chose (#Wander): seeing it is no reason to stop */
	x:      i32,             /* where that was believed to be; exploring, the unseen tile */
	y:      i32,
	level:  i32,
	goal:   cstring,         /* interned: the intention it serves; nil, none */
}


Motivation :: struct {
	using object: Object,
	agent:        Entity_ID,
	decidedAt:    i64,                 /* when it last decided (ms); -1 never (REALITY.md decision 7) */
	intentions:   [BG_MAX_INTENTIONS]Intention,     /* the commitment first, the current intention last */
	nintentions:  i32,
	decisions:    u64,
	waiting:      bool,
	awaiting:     u32,                 /* the referent a question was put to, while it waits for the answer */
	awaitSince:   i64,                 /* ms */
	awaitUntil:   i64,                 /* ms: then it stops waiting */
	heard:        u64,                 /* the serial of the first observation it has not yet considered for questions */
	questions:    [BG_MAX_QUESTIONS]Question,
	nquestions:   i32,
	settled:      [BG_MAX_SETTLED]Arisen,
	nsettled:     i32,
	weighed:      [BG_MAX_SETTLED]Arisen,  /* the last verdict, so it is logged when it changes */
	nweighed:     i32,
	commitments:  [BG_MAX_COMMITMENTS]Commitment,
	ncommitments: i32,
	habits:       [BG_MAX_HABITS]Habit,
	nhabits:      i32,
	wake:         i64,                 /* a decision is due then (ms), or 0 */
	autopilot:    bool,                /* the player's character, handed over */
	routine:      bool,                /* to carry on with its commitments */
	explore:      bool,                /* to go where it hasn't seen */
	recipe:       cstring,             /* interned: the method to carry out its goal by, or nil */
	threshold:    i32,                 /* worth above which control returns */
	handedBack:   bool,
	walking:      Walk_Purpose,        /* what the walk under way is for, if it set out on one */
	again:        Repeated_Act,        /* its last method step's act, and how often in a row */
	postedUnit:   cstring,             /* interned: the goods it last posted a price for (content/market/) */
	postedCoins:  i32,                 /* and that price: a sale at it is struck, its stock since as it may */
	talks:        [BG_MAX_TALKS]Talk,  /* its negotiations (NEGOTIATION.md) */
	ntalks:       i32,
	owed:         [BG_MAX_OWED]Owed,   /* what it owes, is owed, and has agreed to hand over */
	nowed:        i32,
	log:          [dynamic]string,     /* each line in context.allocator */
}


// _former's pairs: an agent let go, its log (which it now owns).
Agency_Former :: struct {
	agent: Entity_ID,
	log:   [dynamic]string,
}


Agency :: struct {
	using object: Object,
	world:        ^World,
	committer:    ^Committer,          /* not retained */
	knowledge:    ^Knowledge,
	activities:   ^Activities,         /* not retained: to suspend and resume the agents' own */
	minds:        [dynamic]^Motivation,     /* sorted by agent; each retained */
	notices:      [dynamic]string,     /* control returned, for the player */
	former:       [dynamic]Agency_Former,   /* pairs: an agent let go, its log */
	deciding:     ^Motivation,         /* whose decision this is, for its habits */
	decisions:    u64,                 /* a mind's deciding, counted, for measuring */
	deliberations: u64,                /* of those, the ones not busy, which choose a way: counted */
	pathSearches: u64,                 /* ways found, for walks and exploring: counted */
	wakes:        ^Wakes,              /* each mind's next time due with nothing happening */
	nudged:       [dynamic]Entity_ID,  /* minds looked up since the last boundary: checked at it (the
	                                      realloc'd _nudged, _nnudged, _nudgedcap) */
	fallThroughs: map[string]u64,      /* a way followed after another of the same goal's failed, in one
	                                      intention: "goal: failed → next", counted (METHODS.md decision 6) */
	kindTypes:    map[string]tri.Type,     /* a believed kind's type (a referent's `kind`, a type
	                                      expression), worked out once: content doesn't change */
	unknown:      [BG_MAX_SLOTS]Slot_Binding,   /* the last condition's first unknown match: its bindings */
	nunknown:     i32,
	ownSearched:  i64,                 /* searching for a commitment: its own places looked into since then are
	                                      passed over (AGENCY.md decision 29); 0, not */
	residual:     [128]u8,             /* and the first path left unknown */
	lastResidual: [128]u8,             /* the last match's */
}


@(private = "file") BG_MAX_VARIANTS :: 16
@(private = "file") BG_MAX_METHODS  :: 32
@(private = "file") BG_MAX_TRIES    :: 4096     /* the matches one condition may take */
@(private = "file") BG_REPLY_WAIT   :: 5000     /* ms an agent waits for an answer */


/* BGMotivation */

motivation_new :: proc() -> ^Motivation {
	self := object_new(Motivation, motivation_dealloc)
	self.log = make([dynamic]string)
	return self
}


motivation_dealloc :: proc(self: ^Motivation) {
	for s in self.log do delete(s)
	delete(self.log)
}


/* --- C buffers ----------------------------------------------------------------------- */

/* snprintf( buf, sizeof( buf), "%s", s): cut to fit, NUL-terminated. */
@(private = "file")
put :: proc(buf: []u8, s: string) {
	n := min(len(s), len(buf) - 1)
	copy(buf[:n], s[:n])
	buf[n] = 0
}


/* A NUL-terminated buffer as a C string, and as a string (up to its NUL). */
@(private = "file")
cstr :: proc(buf: []u8) -> cstring {
	return cstring(raw_data(buf))
}


@(private = "file")
str :: proc(buf: []u8) -> string {
	return string(cstring(raw_data(buf)))
}


/* strncpy( dst, src, n): up to n bytes of src, the rest of the n zeroed. */
@(private = "file")
strncpy :: proc(dst: []u8, src: cstring, n: int) {
	s := ([^]u8)(src)
	i := 0
	for ; i < n && s[i] != 0; i += 1 do dst[i] = s[i]
	for ; i < n; i += 1 do dst[i] = 0
}


/* --- reading content ------------------------------------------------------------- */

/* The text at `path` (the node itself for nil), without its quotes. false when
 * there is none, or it is left open. */
@(private = "file")
text_at :: proc(tc: ^tri.Content, node: ^tri.Node, path: cstring, buf: []u8) -> bool {
	tmp: [256]u8

	v := tri.at(tc, node, path) if node != nil && path != nil else node
	if v == nil do return false
	tri.print(tc, v, raw_data(tmp[:]), size_of(tmp))
	n := len(str(tmp[:]))
	if n < 2 || tmp[0] != '"' || tmp[n - 1] != '"' do return false
	put(buf, string(tmp[1:n - 1]))
	return true
}


/* The texts of the list at `path`, in order. */
@(private = "file")
texts_at :: proc(tc: ^tri.Content, node: ^tri.Node, path: cstring, out: [^][32]u8, max_: uint) -> uint {
	n: uint = 0
	for list := tri.at(tc, node, path) if node != nil else nil; list != nil && n < max_; list = tri.at(tc, list, "rest") {
		if tri.at(tc, list, "first") == nil do break
		if text_at(tc, tri.at(tc, list, "first"), nil, out[n][:]) do n += 1
	}
	return n
}


/* An int at `path`, or `otherwise` when it is left open. */
/* A curve's worth at `x` (AGENCY.md §3's lookup tables): straight between
 * its points, level beyond its ends. NO if it has no points. (The .m's
 * curve_at wrapped BGCurveAt; the port calls curve_at, BGCurveAt's name,
 * directly.) */


@(private = "file")
int_at :: proc(tc: ^tri.Content, node: ^tri.Node, path: cstring, otherwise: i64) -> i64 {
	lo, hi: i64

	v := tri.at(tc, node, path) if node != nil else nil
	if v == nil || tri.node_interval(v, &lo, &hi) == 0 || lo != hi do return otherwise
	return lo
}


/* An instance's patterns, one per variant. */
@(private = "file")
variants_of :: proc(tc: ^tri.Content, instance: cstring, out: [^]^tri.Node, max_: uint) -> uint {
	n := uint(tri.pattern_variant_count(tc, instance))
	if n == 0 {
		out[0] = tri.pattern(tc, instance)
		return 1 if out[0] != nil else 0
	}
	i: uint
	for i = 0; i < n && i < max_; i += 1 do out[i] = tri.pattern_variant(tc, instance, i)
	return i
}


@(private = "file")
bound :: proc(b: [^]Slot_Binding, n: i32, slot: string) -> u32 {
	for i: i32 = 0; i < n; i += 1 {
		if string(b[i].slot) == slot do return b[i].referent
	}
	return 0
}


/* --- what the agent believes ------------------------------------------------------- */

@(private)
in_reach :: proc(me: ^Referent, r: ^Referent) -> bool {
	return referent_in_reach(me, r)
}


/* Walking over the ground as an agent believes it (TERRAIN.md decision 7):
 * a tile of the world, not solid as it last saw it; a tile never seen, it
 * guesses open. */
@(private = "file")
Walk_Context :: struct {
	world: ^World,
	store: ^Knowledge_Store,
	level: i32,
	over:  Terrain_Kind,     /* exploring beside ground of this kind it has seen; 0, any */
}


@(private = "file")
walkable :: proc(context_: rawptr, x: i32, y: i32) -> bool {
	c := (^Walk_Context)(context_)
	if !world_is_tile_x(c.world, x, y, c.level) || world_terrain(c.world) == nil {
		return world_is_tile_x(c.world, x, y, c.level)
	}
	kind := terrain_kind_info(world_terrain(c.world), knowledge_store_believed_terrain_at_x(c.store, x, y, c.level))
	return kind == nil || !kind.solid
}


@(private = "file")
unseen :: proc(context_: rawptr, x: i32, y: i32) -> bool {
	c := (^Walk_Context)(context_)
	if knowledge_store_has_seen_x(c.store, x, y, c.level) do return false
	if c.over == 0 do return true
	/* beside ground of the kind, as it saw it */
	for dy: i32 = -1; dy <= 1; dy += 1 {
		for dx: i32 = -1; dx <= 1; dx += 1 {
			if (dx != 0 || dy != 0) && knowledge_store_has_seen_x(c.store, x + dx, y + dy, c.level) &&
			   knowledge_store_believed_terrain_at_x(c.store, x + dx, y + dy, c.level) == c.over {
				return true
			}
		}
	}
	return false
}


@(private = "file")
distance :: proc(me: ^Referent, r: ^Referent) -> i32 {
	dx := abs(me.x - r.x)
	dy := abs(me.y - r.y)
	return dx if dx > dy else dy
}


/* A condition (a goal's `done`, a method's `pre`), ready to bind. */
@(private = "file")
Condition :: struct {
	match:     [BG_MAX_VARIANTS]^tri.Node,    /* per variant */
	nvariants: uint,
	frame:     cstring,                       /* the frame's type: "#Wedging" */
	find:      [BG_MAX_SLOTS][32]u8,
	nfind:     uint,
	order:     [4][32]u8,
	norder:    uint,
	search:    [32]u8,                        /* the slot to search, or "" */
	places:    i64,                           /* how many to search, curiosity included; 0, no end */
	threshold: i64,                           /* the credence mass, in thousandths, that must entail */
	since:     i64,                           /* searched means its inside was seen since */
	instance:  cstring,                       /* the method or goal */
	seeks:     ^tri.Node,                     /* what a search is for, or nil */
	asks:      [64]u8,                        /* what a search says, by type: one asked it is passed over; "" any */
	tri:       ^tri.Content,
	slot:      cstring,                       /* the slot being bound */
	mind:      ^Motivation,                   /* whose habits order it, or nil */
	now:       i64,
	store:     ^Knowledge_Store,
	me:        ^Referent,
	tries:     uint,
}


/* How strong the habit is at `now`: faded a point a day since. */
habit_strength :: proc(m: ^Motivation, context_: cstring, choice: u32, now: i64) -> i32 {
	for k: i32 = 0; m != nil && k < m.nhabits; k += 1 {
		if string(m.habits[k].context_) == string(context_) && m.habits[k].choice == choice {
			s := m.habits[k].strength - i32(BG_HABIT_FADE * ((now - m.habits[k].at) / 86400000))
			return s if s > 0 else 0
		}
	}
	return 0
}


/* How much the agent believes something like what the search seeks is in
 * the place (dB): the most credible claim it holds of one there, believed
 * or not; BG_PRIOR with none. */
@(private = "file")
likely_in :: proc(c: ^Condition, place: u32) -> i32 {
	result: tri.Match_Result

	best := i32(BG_PRIOR)
	if c.seeks == nil do return best
	tc    := c.tri
	arena := tri.arena_new()
	for i: uint = 0; i < knowledge_store_testimony_count(c.store); i += 1 {
		t := knowledge_store_testimony_at(c.store, i)
		if t.container != place || t.settled != 0 || t.attribution == .Pledged do continue
		description := tri.value(tc, ns_utf8(knowledge_store_describe_referent(c.store, t.thing)), arena, nil, 0)
		if description == nil || tri.match(tc, c.seeks, description, &result) == .Incompatible do continue
		credence := knowledge_store_credence_that(c.store, t.thing, place)
		if credence > best do best = credence
	}
	tri.arena_free(arena)
	return best
}


/* A candidate for a slot, and where the store has it, to keep equals in
 * the store's order. */
@(private = "file")
Ranked :: struct {
	referent: ^Referent,
	order:    uint,
}

@(private = "file")
ranking: ^Condition      /* the condition the sort ranks by; set only while it sorts */

@(private = "file")
cmp_ranked :: proc(x: Ranked, y: Ranked) -> int {
	if d := compare_candidates(ranking, x.referent, y.referent); d != 0 do return d
	return -1 if x.order < y.order else (1 if x.order > y.order else 0)
}


/* qsort's comparator as slice.sort_by's: the order is total (ties by the
 * store's order), so any sort gives qsort's result. */
@(private = "file")
ranked_less :: proc(x: Ranked, y: Ranked) -> bool {
	return cmp_ranked(x, y) < 0
}


@(private = "file")
compare_candidates :: proc(c: ^Condition, a: ^Referent, b: ^Referent) -> int {
	ctx: [128]u8

	for k: uint = 0; k < c.norder; k += 1 {
		if str(c.order[k][:]) == "habit" && c.mind != nil && c.instance != nil && c.slot != nil {
			put(ctx[:], fmt.tprintf("%s.%s", c.instance, c.slot))
			da := habit_strength(c.mind, cstr(ctx[:]), a.id, c.now)
			db := habit_strength(c.mind, cstr(ctx[:]), b.id, c.now)
			if da != db do return -1 if da > db else 1
		} else if str(c.order[k][:]) == "near" {
			da := distance(c.me, a)
			db := distance(c.me, b)
			if da != db do return -1 if da < db else 1
		} else if str(c.order[k][:]) == "recent" && a.seen != b.seen {
			return -1 if a.seen > b.seen else 1
		} else if str(c.order[k][:]) == "hiring" {
			da := knowledge_store_finding(c.store, "#Hires", a.id) != nil
			db := knowledge_store_finding(c.store, "#Hires", b.id) != nil
			if da != db do return -1 if da else 1
		} else if str(c.order[k][:]) == "loyal" {
			da := knowledge_store_loyalty_to(c.store, a.id)
			db := knowledge_store_loyalty_to(c.store, b.id)
			if da != db do return -1 if da > db else 1
		} else if str(c.order[k][:]) == "own" {
			/* what it believes its own first (KNOWLEDGE.md decision 18) */
			me := knowledge_store_self_referent(c.store)
			fa := knowledge_store_finding(c.store, "#Owned", a.id)
			fb := knowledge_store_finding(c.store, "#Owned", b.id)
			da := fa != nil && fa.choice == me
			db := fb != nil && fb.choice == me
			if da != db do return -1 if da else 1
		} else if str(c.order[k][:]) == "likely" {
			da := likely_in(c, a.id)
			db := likely_in(c, b.id)
			if da != db do return -1 if da > db else 1
		}
	}
	return -1 if a.id < b.id else (1 if a.id > b.id else 0)
}


@(private)
goal_title :: proc(tc: ^tri.Content, goal: cstring, buf: []u8) -> cstring {
	if !text_at(tc, tri.pattern(tc, goal), "title", buf) do put(buf, string(goal))
	return cstr(buf)
}


/* --- BGAgency ------------------------------------------------------------------------ */

// returns the new agency, its count 1, and sets itself as the
// knowledge's concerns.
agency_init_with_world :: proc(world: ^World, committer: ^Committer, knowledge: ^Knowledge) -> ^Agency {
	self := object_new(Agency, agency_dealloc)
	self.world     = retain(world)
	self.committer = committer
	self.knowledge = retain(knowledge)
	self.minds     = make([dynamic]^Motivation)
	self.notices   = make([dynamic]string)
	self.former    = make([dynamic]Agency_Former)
	self.nudged    = make([dynamic]Entity_ID)
	knowledge_set_concerns(self.knowledge, agency_as_concerns(self))
	return self
}


agency_dealloc :: proc(self: ^Agency) {
	if knowledge_concerns(self.knowledge).data == rawptr(self) do knowledge_set_concerns(self.knowledge, Concerns{})
	release(self.world)
	release(self.knowledge)
	for m in self.minds do release(m)
	delete(self.minds)
	for s in self.notices do delete(s)
	delete(self.notices)
	for f in self.former {
		for s in f.log do delete(s)
		delete(f.log)
	}
	delete(self.former)
	wakes_free(self.wakes)
	delete(self.nudged)
	for k in self.kindTypes do delete(k)
	delete(self.kindTypes)
	for k in self.fallThroughs do delete(k)
	delete(self.fallThroughs)
}


agency_as_decision_phase :: proc(self: ^Agency) -> Decision_Phase {
	return Decision_Phase{
		data               = self,
		decide_boundary    = proc(data: rawptr, boundary: u64) {agency_decide_boundary((^Agency)(data), boundary)},
		next_decision_time = proc(data: rawptr) -> Time {return agency_next_decision_time((^Agency)(data))},
	}
}


agency_as_saved_system :: proc(self: ^Agency) -> Saved_System {
	return Saved_System{
		data                = self,
		name                = proc(data: rawptr) -> string {return agency_name((^Agency)(data))},
		check_in_all        = proc(data: rawptr) {agency_check_in_all((^Agency)(data))},
		saved_state         = proc(data: rawptr) -> []string {return agency_saved_state((^Agency)(data))},
		restore_saved_state = proc(data: rawptr, lines: []string) {agency_restore_saved_state((^Agency)(data), lines)},
	}
}


agency_as_concerns :: proc(self: ^Agency) -> Concerns {
	return Concerns{
		data        = self,
		concerns_of = proc(data: rawptr, agent: Entity_ID) -> []string {return agency_concerns_of((^Agency)(data), agent)},
		holds       = proc(data: rawptr, agent: Entity_ID, referent: u32) -> bool {return agency_names_referent((^Agency)(data), agent, referent)},
	}
}


/* Whether the agent's mind names the referent: an intention's binding or
 * what it arose about, a commitment's, one it awaits or that asked it, what
 * it settled or weighed about. Not a habit's choice: a habit of something
 * forgotten is moot, and gives way to others (AGENCY.md §8). Without a
 * mind, nothing. */
agency_names_referent :: proc(self: ^Agency, agent: Entity_ID, referent: u32) -> bool {
	m: ^Motivation
	for mind in self.minds do if mind.agent == agent do m = mind
	if m == nil do return false
	if m.awaiting == referent do return true
	for i in 0 ..< m.nintentions {
		if m.intentions[i].arose == referent do return true
		for k in 0 ..< m.intentions[i].nparams do if m.intentions[i].params[k].referent == referent do return true
	}
	for i in 0 ..< m.ncommitments {
		for k in 0 ..< m.commitments[i].nparams do if m.commitments[i].params[k].referent == referent do return true
	}
	for i in 0 ..< m.nquestions do if m.questions[i].asker == referent do return true
	for i in 0 ..< m.nsettled do if m.settled[i].about == referent do return true
	for i in 0 ..< m.nweighed do if m.weighed[i].about == referent do return true
	return false
}


agency_name :: proc(self: ^Agency) -> string {
	return "agency"
}


agency_mind_of :: proc(self: ^Agency, agent: Entity_ID) -> ^Motivation {
	m: ^Motivation
	i: uint

	lo: uint
	hi: uint

	/* by halving: the minds are in agent order */
	lo = 0
	hi = uint(len(self.minds))
	for lo < hi {
		i = (lo + hi) / 2
		if self.minds[i].agent < agent {
			lo = i + 1
		} else {
			hi = i
		}
	}
	/* looked up: something may have changed it; checked at the next boundary */
	append(&self.nudged, agent)
	if lo < uint(len(self.minds)) {
		m = self.minds[lo]
		if m.agent == agent do return m
	}
	m           = autorelease(motivation_new())
	m.agent     = agent
	m.decidedAt = -1
	inject_at(&self.minds, int(lo), retain(m))
	return m
}


// the log as it is now (nil for none).
agency_log_of :: proc(self: ^Agency, agent: Entity_ID) -> []string {
	for i := 0; i < len(self.minds); i += 1 {
		m := self.minds[i]
		if m.agent == agent do return m.log[:]
	}
	for i := len(self.former); i >= 1; i -= 1 {
		if self.former[i - 1].agent == agent do return self.former[i - 1].log[:]
	}
	return nil
}


/* Whether the agent has a mind (for checks; it makes none). */
agency_has_mind :: proc(self: ^Agency, agent: Entity_ID) -> bool {
	for m in self.minds do if m.agent == agent do return true
	return false
}


/* Whether the agent has the goal among its intentions now (for checks and
 * the developer; it makes no mind). */
agency_intends :: proc(self: ^Agency, agent: Entity_ID, goal: string) -> bool {
	for m in self.minds {
		if m.agent != agent do continue
		for k: i32 = 0; k < m.nintentions; k += 1 do if string(m.intentions[k].goal) == goal do return true
	}
	return false
}


/* The mind at i goes; its log stays, for the developer. */
@(private = "file")
agency_retire_mind_at :: proc(self: ^Agency, i: uint) {
	m := self.minds[i]
	append(&self.former, Agency_Former{m.agent, m.log})
	m.log = {}            /* _former has it now */
	ordered_remove(&self.minds, int(i))
	release(m)
}


@(private = "file")
agency_adopt :: proc(self: ^Agency, goal: cstring, m: ^Motivation, params: [^]Slot_Binding, n: i32) {
	intention := &m.intentions[m.nintentions]
	m.nintentions += 1
	intention^           = {}
	intention.goal      = world_intern(self.world, goal)
	intention.adopted   = world_time(self.world).ms
	intention.pending   = -1
	intention.following = -1
	for ; intention.nparams < n && intention.nparams < BG_MAX_SLOTS; intention.nparams += 1 {
		intention.params[intention.nparams] = params[intention.nparams]
	}
}


agency_control :: proc(self: ^Agency, agent: Entity_ID) {
	for i := 0; i < len(self.minds); i += 1 {
		if self.minds[i].agent == agent do return        /* already */
	}
	m      := agency_mind_of(self, agent)
	m.heard = knowledge_store_next_serial(knowledge_store_of(self.knowledge, agent))
	m.wake  = world_time(self.world).ms + 1     /* it decides soon, whatever else happens */
}


agency_set_activities :: proc(self: ^Agency, activities: ^Activities) {
	self.activities = activities
}


agency_relinquish :: proc(self: ^Agency, agent: Entity_ID) {
	for i := 0; i < len(self.minds); i += 1 {
		if self.minds[i].agent == agent {
			agency_retire_mind_at(self, uint(i))
			return
		}
	}
}


agency_undertake_goal_from_until_source :: proc(self: ^Agency, agent: Entity_ID, goal: cstring, from: i64, until: i64,
                                                source: cstring) -> bool {
	tc := world_tri(self.world)
	if tri.at(tc, tri.pattern(tc, goal), "done") == nil do return false
	agency_control(self, agent)
	m := agency_mind_of(self, agent)
	if m.ncommitments == BG_MAX_COMMITMENTS do return false
	c := &m.commitments[m.ncommitments]
	m.ncommitments += 1
	c^       = {}
	c.goal   = world_intern(self.world, goal)
	c.from   = from
	c.until  = until
	c.source = world_intern(self.world, source)
	return true
}


agency_undertake_goal_from_until_source_every :: proc(self: ^Agency, agent: Entity_ID, goal: cstring, from: i64,
                                                      until: i64, source: cstring, every: i64) -> bool {
	if every <= 0 || until - from > every ||
	   !agency_undertake_goal_from_until_source(self, agent, goal, from, until, source) {
		return false
	}
	m := agency_mind_of(self, agent)
	m.commitments[m.ncommitments - 1].every = every
	return true
}


/* A commitment recurring every period, its slots bound already (a bed of
 * the agent's own, its household's worksite): referents of the
 * agent's. */
agency_undertake_every_with :: proc(self: ^Agency, agent: Entity_ID, goal: cstring, from: i64, until: i64,
                                    source: cstring, every: i64, slots: []Slot_Binding) -> bool {
	if len(slots) > BG_MAX_SLOTS || !agency_undertake_goal_from_until_source_every(self, agent, goal, from, until, source, every) {
		return false
	}
	m := agency_mind_of(self, agent)
	c := &m.commitments[m.ncommitments - 1]
	for b, i in slots do c.params[i] = {world_intern(self.world, b.slot), b.referent}
	c.nparams = i32(len(slots))
	return true
}


/* A recurring commitment whose window has closed opens its next one. */
@(private = "file")
agency_renew_commitments :: proc(self: ^Agency, m: ^Motivation) {
	now := world_time(self.world).ms
	for k: i32 = 0; k < m.ncommitments; k += 1 {
		c := &m.commitments[k]
		if c.every == 0 || now < c.until do continue
		for now >= c.until {
			c.from  += c.every
			c.until += c.every
		}
		c.settled = false
		c.resume  = 0
	}
}


agency_promise :: proc(self: ^Agency, agent: Entity_ID, hearer: u32, goods: u32, container: u32, deadline: i64) -> bool {
	agency_control(self, agent)
	m       := agency_mind_of(self, agent)
	store   := knowledge_store_of(self.knowledge, agent)
	content := knowledge_store_promise_that_is_in(store, goods, container, deadline)
	if content == "" || m.ncommitments == BG_MAX_COMMITMENTS ||
	   !agency_act(self, m, "promising", store, "say", hearer, 0, 0, ns_utf8(content)) {
		return false
	}
	if !agency_undertake_goal_from_until_source(self, agent, "deliver", world_time(self.world).ms, deadline, "promise") {
		return false
	}
	c                   := &m.commitments[m.ncommitments - 1]
	c.params[0].slot     = world_intern(self.world, "goods")
	c.params[0].referent = goods
	c.params[1].slot     = world_intern(self.world, "dest")
	c.params[1].referent = container
	c.nparams            = 2
	return true
}


agency_controls :: proc(self: ^Agency, agent: Entity_ID) -> bool {
	for i := 0; i < len(self.minds); i += 1 {
		if self.minds[i].agent == agent do return true
	}
	return false
}


agency_autopilot_to_goal :: proc(self: ^Agency, agent: Entity_ID, goal: cstring, threshold: i32) -> bool {
	agency_control(self, agent)
	if !agency_commit(self, agent, goal) {
		agency_relinquish(self, agent)
		return false
	}
	m           := agency_mind_of(self, agent)
	m.autopilot  = true
	m.threshold  = threshold
	m.handedBack = false
	return true
}


agency_autopilot_routine :: proc(self: ^Agency, agent: Entity_ID, threshold: i32) -> bool {
	agency_control(self, agent)
	m           := agency_mind_of(self, agent)
	m.autopilot  = true
	m.routine    = true
	m.threshold  = threshold
	m.handedBack = false
	m.wake       = world_time(self.world).ms + 1
	return true
}


agency_autopilot_recipe :: proc(self: ^Agency, agent: Entity_ID, recipe: cstring, threshold: i32) -> bool {
	goal: [64]u8

	tc      := world_tri(self.world)
	pattern := tri.pattern(tc, recipe) if recipe != nil else nil
	v       := tri.at(tc, pattern, "sequence") if pattern != nil else nil
	if v == nil || tri.node_type(v) != tri.type_named(tc, "true") ||
	   !knowledge_store_knows_recipe(knowledge_store_of(self.knowledge, agent), recipe) ||
	   !text_at(tc, pattern, "goal", goal[:]) ||
	   !agency_autopilot_to_goal(self, agent, cstr(goal[:]), threshold) {
		return false
	}
	agency_mind_of(self, agent).recipe = world_intern(self.world, recipe)
	return true
}


agency_autopilot_explore :: proc(self: ^Agency, agent: Entity_ID, threshold: i32) -> bool {
	agency_control(self, agent)
	m           := agency_mind_of(self, agent)
	m.autopilot  = true
	m.explore    = true
	m.threshold  = threshold
	m.handedBack = false
	m.wake       = world_time(self.world).ms + 1
	return true
}


/* Exploring: a step on the shortest way, over the ground as it believes
 * it, to the nearest tile on its level it has never seen; false if there is
 * none within a search's reach (BG_PATH_BUDGET tiles). */
@(private = "file")
agency_explore :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store, over: Terrain_Kind = 0) -> bool {
	c: Walk_Context
	q: Path_Query

	me := knowledge_store_referent(store, knowledge_store_self_referent(store))
	if me == nil do return false
	q          = {}
	c.world    = self.world
	c.store    = store
	c.level    = me.level
	c.over     = over
	q.x        = me.x
	q.y        = me.y
	q.context_ = &c
	q.passable = walkable
	q.goal     = unseen
	way       := make([dynamic]Step, context.temp_allocator)
	q.way      = &way
	self.pathSearches += 1
	r := path_find(&q)
	if !r.found || r.step == .None do return false
	agency_set_out(self, m, way[:], 0, r.x, r.y, me.level, "exploring", fmt.tprintf("toward (%d, %d)", r.x, r.y))
	return true
}


/* Wandering (#Wander, hunting/'s animals): to a tile no more than `within`
 * away, on ground of the kind `on` as it believes it (0, any), walkable; of
 * those, one chosen from the agent and the time, so each wanders its own
 * way, the same in every run. true when it set out. */
agency_wander :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store, within: i32, on: Terrain_Kind) -> bool {
	c: Walk_Context
	q: Path_Query

	me := knowledge_store_referent(store, knowledge_store_self_referent(store))
	if me == nil || within < 1 do return false
	c.world = self.world
	c.store = store
	c.level = me.level
	h := mix(u64(m.agent) ~ u64(world_time(self.world).ms) * 0x9e3779b97f4a7c15)
	span := u64(2 * within + 1)
	for try := 0; try < 24; try += 1 {
		h = mix(h + u64(try))
		x := me.x + i32(h % span) - within
		y := me.y + i32((h / span) % span) - within
		if x == me.x && y == me.y do continue
		if !walkable(&c, x, y) do continue
		if on != 0 && knowledge_store_believed_terrain_at_x(store, x, y, me.level) != on do continue
		way := make([dynamic]Step, context.temp_allocator)
		q          = {}
		q.x        = me.x
		q.y        = me.y
		q.targeted = true
		q.tx       = x
		q.ty       = y
		q.context_ = &c
		q.passable = walkable
		q.way      = &way
		self.pathSearches += 1
		r := path_find(&q)
		if !r.found || r.step == .None do continue
		agency_set_out(self, m, way[:], 0, x, y, me.level, "wandering", fmt.tprintf("toward (%d, %d)", x, y))
		m.walking.wander = true
		return true
	}
	/* none of that ground near (a hunter in the village): toward the
	 * nearest it knows of, ring by ring, up to eight times as far */
	for d := within + 1; on != 0 && d <= 8 * within; d += 1 {
		for k := -d; k <= d; k += 1 {
			for side in 0 ..< 4 {
				x, y: i32
				switch side {
				case 0: x, y = me.x + k, me.y - d
				case 1: x, y = me.x + k, me.y + d
				case 2: x, y = me.x - d, me.y + k
				case 3: x, y = me.x + d, me.y + k
				}
				if !walkable(&c, x, y) || knowledge_store_believed_terrain_at_x(store, x, y, me.level) != on do continue
				way := make([dynamic]Step, context.temp_allocator)
				q          = {}
				q.x        = me.x
				q.y        = me.y
				q.targeted = true
				q.tx       = x
				q.ty       = y
				q.context_ = &c
				q.passable = walkable
				q.way      = &way
				self.pathSearches += 1
				r := path_find(&q)
				if !r.found || r.step == .None do continue
				agency_set_out(self, m, way[:], 0, x, y, me.level, "wandering", fmt.tprintf("toward (%d, %d), the nearest", x, y))
				m.walking.wander = true
				return true
			}
		}
	}
	return false
}


/* true while a commitment of its is still to keep: not settled, its window
 * not yet closed. */
@(private = "file")
agency_has_routine :: proc(self: ^Agency, m: ^Motivation) -> bool {
	for k: i32 = 0; k < m.ncommitments; k += 1 {
		if !m.commitments[k].settled && m.commitments[k].until > world_time(self.world).ms do return true
	}
	return false
}


// the notices in the temporary allocator.
agency_take_notices :: proc(self: ^Agency) -> []string {
	notices := make([]string, len(self.notices), context.temp_allocator)
	for s, i in self.notices {
		notices[i] = strings.clone(s, context.temp_allocator)
		delete(s)
	}
	clear(&self.notices)
	return notices
}


/* Control returns to the player, with why; the mind goes after this
 * boundary's decisions. */
@(private = "file")
agency_hand_back :: proc(self: ^Agency, m: ^Motivation, why: string) {
	agency_note(self, m, fmt.tprintf("control returns: %s", why))
	append(&self.notices, fmt.aprintf("Control returns to you: %s.", why))
	m.handedBack = true
}


/* What the agent's goals concern, all the way down its intentions. */
agency_concerns_of :: proc(self: ^Agency, agent: Entity_ID) -> []string {
	printed: [1024]u8

	tc       := world_tri(self.world)
	patterns := make([dynamic]string, context.temp_allocator)
	for i := 0; i < len(self.minds); i += 1 {
		m := self.minds[i]
		if m.agent != agent do continue
		for k: i32 = 0; k < m.nintentions; k += 1 {
			for list := tri.at(tc, tri.pattern(tc, m.intentions[k].goal), "concerns");
			    list != nil && tri.at(tc, list, "first") != nil;
			    list = tri.at(tc, list, "rest") {
				tri.print(tc, tri.at(tc, list, "first"), raw_data(printed[:]), size_of(printed))
				append(&patterns, strings.clone(str(printed[:]), context.temp_allocator))
			}
		}
	}
	return patterns[:]
}


agency_commit :: proc(self: ^Agency, agent: Entity_ID, goal: cstring) -> bool {
	tc := world_tri(self.world)
	if tri.at(tc, tri.pattern(tc, goal), "done") == nil do return false
	m            := agency_mind_of(self, agent)
	m.nintentions = 0
	m.waiting     = false
	m.wake        = world_time(self.world).ms + 1     /* it decides soon, whatever else happens */
	agency_adopt(self, goal, m, nil, 0)
	return true
}


/* --- conditions ---------------------------------------------------------------------- */

/* `path` is "done" for a goal, "pre" for a method. */
@(private = "file")
agency_load :: proc(self: ^Agency, c: ^Condition, instance: cstring, path: cstring, store: ^Knowledge_Store) -> bool {
	variants: [BG_MAX_VARIANTS]^tri.Node
	sub:      [32]u8

	tc := world_tri(self.world)
	c^          = {}
	c.store    = store
	c.me       = knowledge_store_referent(store, knowledge_store_self_referent(store))
	c.instance = instance
	c.mind     = self.deciding if self.deciding != nil && self.deciding.agent == knowledge_store_agent(store) else nil
	c.now      = world_time(self.world).ms
	for v: uint = 0; v < variants_of(tc, instance, raw_data(variants[:]), BG_MAX_VARIANTS); v += 1 {
		put(sub[:], fmt.tprintf("%s.match", path))
		c.match[c.nvariants] = tri.at(tc, variants[v], cstr(sub[:]))
		if c.match[c.nvariants] != nil do c.nvariants += 1
	}
	if c.nvariants == 0 || c.me == nil do return false
	c.frame  = tri.type_name(tc, tri.node_type(c.match[0]))
	put(sub[:], fmt.tprintf("%s.find", path))
	c.nfind  = texts_at(tc, variants[0], cstr(sub[:]), raw_data(c.find[:]), BG_MAX_SLOTS)
	c.norder = texts_at(tc, variants[0], "order", raw_data(c.order[:]), 4)
	c.seeks  = tri.at(tc, variants[0], "seeks")
	c.tri    = tc
	if !text_at(tc, variants[0], "search", c.search[:]) do c.search[0] = 0
	/* asking: the kind of thing it asks, the first step's that says one */
	c.asks[0] = 0
	for list := tri.at(tc, variants[0], "steps"); list != nil; list = tri.at(tc, list, "rest") {
		step := tri.at(tc, list, "first")
		if step == nil || c.asks[0] != 0 do break
		if tri.at(tc, step, "says") != nil {
			put(c.asks[:], ns_string(tri.type_name(tc, tri.node_type(tri.at(tc, step, "says")))))
		}
	}
	c.threshold = int_at(tc, variants[0], "threshold", 1000)
	/* a search looks into so many places; curiosity widens it */
	c.places = int_at(tc, variants[0], "places", 0)
	if c.places > 0 {
		agent := (^Agent)(world_record(self.world, world_kind_named(self.world, "Agent"), knowledge_store_agent(store)))
		if agent != nil do c.places += agent.curious / 25
	}
	return true
}


/* The match of the condition's frame, with `me` and the slots of `find`
 * bound so far: entailed if any variant entails it, incompatible if all rule
 * it out. */
/* The match of the frame as described, with `supposing`'s competing
 * hypothesis `h` in place of its belief (0: none); `path` gets the residual
 * of an unknown match, or where an incompatible one failed. */
@(private = "file")
agency_match_supposing :: proc(self: ^Agency, c: ^Condition, b: [^]Slot_Binding, n: i32, supposing: u32, h: uint,
                               path: []u8) -> tri.Match {
	result: tri.Match_Result

	tc   := world_tri(self.world)
	expr := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&expr, "%s & {{ me: %s", c.frame, knowledge_store_describe_referent(c.store, c.me.id))
	for k: uint = 0; k < c.nfind; k += 1 {
		r := bound(b, n, str(c.find[k][:]))
		if r != 0 {
			fmt.sbprintf(&expr, ", %s: %s", str(c.find[k][:]),
			             knowledge_store_describe_supposed(c.store, r, h) if r == supposing else knowledge_store_describe_referent(c.store, r))
		}
	}
	strings.write_string(&expr, " }")
	/* worked out before, for the same condition and description: the
	 * condition named by its variants' patterns, the content's own nodes */
	key := strings.builder_make(context.temp_allocator)
	strings.write_string(&key, "supposing")
	for v: uint = 0; v < c.nvariants; v += 1 do fmt.sbprintf(&key, "\x00%p", c.match[v])
	fmt.sbprintf(&key, "\x00%s", strings.to_string(expr))
	if m, ok := world_matched(self.world, strings.to_string(key)); ok {
		strncpy(path, cstring(&m.result.failure.path[0]), 255)
		path[255] = 0
		return m.match
	}
	arena       := tri.arena_new()
	description := tri.value(tc, ns_utf8(strings.to_string(expr)), arena, nil, 0)
	best        := tri.Match.Incompatible
	path[0]      = 0
	for v: uint = 0; description != nil && v < c.nvariants && best != .Entailed; v += 1 {
		match := tri.match(tc, c.match[v], description, &result)
		if match != .Incompatible do best = match
		if match == .Unknown && result.nresidual != 0 do strncpy(path, cstring(&result.residual[0][0]), 255)
		if match == .Incompatible && best == .Incompatible && result.failure.path[0] != 0 {
			strncpy(path, cstring(&result.failure.path[0]), 255)
		}
	}
	path[255] = 0
	tri.arena_free(arena)
	kept: Matched
	kept.match = best
	strncpy(kept.result.failure.path[:], cstring(raw_data(path)), 255)
	world_remember_match(self.world, strings.to_string(key), kept)
	return best
}


/* The match of the condition: per hypothesis (CONTENT_LANGUAGE.md §9), when
 * a bound referent has competing ones. Entailed when the credence mass that
 * entails reaches the condition's threshold; incompatible when every
 * hypothesis is; otherwise unknown, at the path where they part. */
@(private = "file")
agency_match :: proc(self: ^Agency, c: ^Condition, b: [^]Slot_Binding, n: i32) -> tri.Match {
	path:  [256]u8
	other: [256]u8

	doubted: u32 = 0
	slot := ""
	for k: uint = 0; k < c.nfind && doubted == 0; k += 1 {
		r := bound(b, n, str(c.find[k][:]))
		if r != 0 && knowledge_store_supposed_mass_of(c.store, r) > 0 {
			doubted = r
			slot    = str(c.find[k][:])
		}
	}
	believed := agency_match_supposing(self, c, b, n, 0, 0, path[:])
	if doubted == 0 {
		if believed == .Unknown do strncpy(self.lastResidual[:], cstr(path[:]), len(self.lastResidual) - 1)
		return believed
	}
	mass       := i64(knowledge_store_supposed_mass_of(c.store, doubted))
	entailed   := 1000 - mass if believed == .Entailed else 0
	compatible := believed != .Incompatible
	for h: uint = 0; h < knowledge_store_hypotheses_of(c.store, doubted); h += 1 {
		supposed   := agency_match_supposing(self, c, b, n, doubted, h, other[:])
		entailed   += i64(knowledge_store_mass_of(c.store, doubted, h)) if supposed == .Entailed else 0
		compatible  = compatible || supposed != .Incompatible
	}
	if entailed >= c.threshold do return .Entailed
	if !compatible do return .Incompatible
	/* where they part: the doubted slot's feature the hypotheses override */
	strncpy(other[:], knowledge_store_overrides_of(c.store, doubted, 0), len(other) - 1)
	other[len(other) - 1] = 0
	if colon := strings.index_byte(str(other[:]), ':'); colon >= 0 do other[colon] = 0
	put(self.lastResidual[:], fmt.tprintf("%s.%s (%d in 1000 entails, under %d)", slot, str(other[:]), entailed,
	                                      c.threshold))
	return .Unknown
}


/* The type of a believed kind (a referent's `kind`, a type expression);
 * 0 if it has none. Worked out once for each: content doesn't change. */
@(private = "file")
agency_kind_type :: proc(self: ^Agency, kind: cstring) -> tri.Type {
	if kind == nil do return 0
	t, known := self.kindTypes[string(kind)]
	if !known {
		arena := tri.arena_new()
		k     := tri.value(world_tri(self.world), kind, arena, nil, 0)
		t      = tri.node_type(k) if k != nil else 0
		tri.arena_free(arena)
		self.kindTypes[strings.clone(string(kind))] = t
	}
	return t
}


/* A believed kind more general than the slot's isn't one (as for an
 * operation's roles). */
@(private = "file")
agency_kind_fits_slot :: proc(self: ^Agency, kind: cstring, slot: cstring, c: ^Condition) -> bool {
	tc := world_tri(self.world)
	t  := agency_kind_type(self, kind)
	fits := false
	for v: uint = 0; t != 0 && v < c.nvariants && !fits; v += 1 {
		filler := tri.at(tc, c.match[v], slot)
		fits    = filler != nil && tri.subtype(tc, t, tri.node_type(filler)) != 0
	}
	return fits
}


/* Binds the slots of `find` from slot `k` on, depth first, each slot's
 * candidates in the condition's order; a partial binding the match rules out
 * is not followed. true with the bindings when the condition holds. */
@(private = "file")
agency_bind :: proc(self: ^Agency, c: ^Condition, k: uint, b: [^]Slot_Binding, n: ^i32) -> bool {
	if k == c.nfind {
		m := agency_match(self, c, b, n^)
		if m == .Unknown && self.nunknown == 0 {
			copy(self.unknown[:n^], b[:n^])
			self.nunknown = n^
			self.residual = self.lastResidual
		}
		return m == .Entailed
	}
	slot := cstr(c.find[k][:])
	if r := bound(b, n^, string(slot)); r != 0 {
		/* somewhere to look, bound already (a commitment's larder): searched
		 * since, it is passed over, as one found would be */
		if c.search[0] != 0 && string(slot) == str(c.search[:]) {
			ref := knowledge_store_referent(c.store, r)
			if ref != nil && (ref.insideSeen >= agency_searched_since(self, c, r) ||
			                  knowledge_store_last_said_to_like(c.store, r, cstr(c.asks[:]) if c.asks[0] != 0 else nil) >= c.since) {
				return false
			}
		}
		return agency_bind(self, c, k + 1, b, n)
	}
	if n^ >= BG_MAX_SLOTS do return false

	ncandidates: uint = 0
	c.slot = slot

	/* searched enough: as many places looked into, or asked, as it has in it */
	if c.search[0] != 0 && string(slot) == str(c.search[:]) && c.places > 0 {
		searched: i64 = 0
		for i: uint = 0; i < knowledge_store_count(c.store); i += 1 {
			r := knowledge_store_referent_at(c.store, i)
			if r.present && r.id != c.me.id && agency_kind_fits_slot(self, r.kind, slot, c) &&
			   (r.insideSeen >= agency_searched_since(self, c, r.id) ||
			    knowledge_store_last_said_to_like(c.store, r.id, cstr(c.asks[:]) if c.asks[0] != 0 else nil) >= c.since) {
				searched += 1
			}
		}
		if searched >= c.places do return false
	}

	/* every referent that fits, however many, best first */
	candidates := make([]Ranked, knowledge_store_count(c.store) + 1)
	for i: uint = 0; i < knowledge_store_count(c.store); i += 1 {
		r := knowledge_store_referent_at(c.store, i)
		if !r.present || r.id == c.me.id do continue
		j: uint
		for j = 0; j < uint(n^) && b[j].referent != r.id; j += 1 {}
		if j < uint(n^) do continue      /* one referent fills one slot */
		if c.search[0] != 0 && string(slot) == str(c.search[:]) &&
		   (r.insideSeen >= agency_searched_since(self, c, r.id) ||
		    knowledge_store_last_said_to_like(c.store, r.id, cstr(c.asks[:]) if c.asks[0] != 0 else nil) >= c.since) {
			continue      /* searched already: looked into, or asked the same */
		}
		if !agency_kind_fits_slot(self, r.kind, slot, c) do continue
		candidates[ncandidates].referent = r
		candidates[ncandidates].order    = i
		ncandidates += 1
	}
	/* in the condition's order; equals as the store has them */
	ranking = c
	slice.sort_by(candidates[:ncandidates], ranked_less)
	ranking = nil

	held := false
	for i: uint = 0; i < ncandidates && !held; i += 1 {
		c.tries += 1
		if c.tries > BG_MAX_TRIES do break
		t             := candidates[i].referent
		before        := n^
		b[n^].slot     = world_intern(self.world, slot)
		b[n^].referent = t.id
		n^ += 1
		if agency_match(self, c, b, n^) != .Incompatible && agency_bind(self, c, k + 1, b, n) {
			held = true
		} else {
			n^ = before
		}
	}
	delete(candidates)
	return held
}


/* Whether the instance's condition holds in the agent's view. `b` starts as
 * the slots already bound, and gains those it binds. */
@(private = "file")
agency_holds :: proc(self: ^Agency, instance: cstring, path: cstring, since: i64, b: [^]Slot_Binding, n: ^i32,
                     store: ^Knowledge_Store) -> bool {
	c:    Condition
	text: [64]u8

	/* what the agent did: looked into the slot's referent since; an activity
	 * of the operation it started since has completed */
	tc   := world_tri(self.world)
	done := tri.at(tc, tri.pattern(tc, instance), "done") if string(path) == "done" else nil
	if done != nil && text_at(tc, done, "looked", text[:]) {
		return bound(b, n^, str(text[:])) != 0 && knowledge_store_referent(store, bound(b, n^, str(text[:]))) != nil &&
		       knowledge_store_referent(store, bound(b, n^, str(text[:]))).insideSeen >= since
	}
	if done != nil && text_at(tc, done, "reached", text[:]) {
		return bound(b, n^, str(text[:])) != 0 &&
		       in_reach(knowledge_store_referent(store, knowledge_store_self_referent(store)),
		                knowledge_store_referent(store, bound(b, n^, str(text[:]))))
	}
	if done != nil && text_at(tc, done, "buying", text[:]) do return agency_buying(self, done, str(text[:]), b, n^, store)
	if done != nil && text_at(tc, done, "did", text[:]) {
		/* lately: one begun no longer ago than that (a kept goal, done
		 * again and again) */
		lately := int_at(tc, done, "lately", 0)
		after  := max(since, world_time(self.world).ms - lately) if lately > 0 else since
		return agency_activity(self, cstr(text[:]), knowledge_store_agent(store), "completed", after) != NO_ENTITY
	}

	/* a precondition within reach of a slot's referent (unpacking at the
	 * larder, not in the woods): that, and its slots found as any are */
	pre := tri.at(tc, tri.pattern(tc, instance), "pre") if string(path) == "pre" else nil
	if pre != nil && text_at(tc, pre, "reached", text[:]) {
		if bound(b, n^, str(text[:])) == 0 ||
		   !in_reach(knowledge_store_referent(store, knowledge_store_self_referent(store)),
		             knowledge_store_referent(store, bound(b, n^, str(text[:])))) {
			return false
		}
	}

	if !agency_load(self, &c, instance, path, store) do return false
	c.since = since
	start  := n^
	if agency_bind(self, &c, 0, b, n) do return true
	n^ = start
	return false
}


/* The agent's own activity of the operation in that status, started at or
 * after `since`; its own doings it knows. */
@(private)
agency_activity :: proc(self: ^Agency, operation: cstring, agent: Entity_ID, status: cstring, since: i64) -> Entity_ID {
	quoted: [32]u8
	n:      uint

	put(quoted[:], fmt.tprintf("\"%s\"", status))
	wanted := u32(tri.type_named(world_tri(self.world), cstr(quoted[:])))
	mine   := world_copy_activities_of(self.world, agent, &n)
	found  := NO_ENTITY
	for i: uint = 0; i < n && found == NO_ENTITY; i += 1 {
		record := (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), mine[i]))
		op     := world_text_field(self.world, "Activity.operation", mine[i])
		if record != nil && op != nil && string(op) == string(operation) && record.status == wanted && record.started >= since {
			found = mine[i]
		}
	}
	free(mine)
	return found
}


/* The goal's methods, for this mind: carrying out a recipe, its goal has
 * that method alone. */
@(private)
agency_methods_for_mind :: proc(self: ^Agency, goal: cstring, m: ^Motivation, out: [^]cstring, max_: uint) -> uint {
	buf: [64]u8

	tc := world_tri(self.world)
	if m.recipe != nil && max_ != 0 && text_at(tc, tri.pattern(tc, m.recipe), "goal", buf[:]) && str(buf[:]) == string(goal) {
		out[0] = m.recipe
		return 1
	}
	/* a recipe it doesn't know, it can't choose (ACTIONS.md decision 12) */
	n     := agency_methods_for(self, goal, out, max_)
	store := knowledge_store_of(self.knowledge, m.agent)
	k: uint = 0
	for i: uint = 0; i < n; i += 1 {
		if knowledge_store_knows_recipe(store, out[i]) {
			out[k] = out[i]
			k += 1
		}
	}
	return k
}


/* A goal's methods: by rank, then by name. */
@(private = "file")
agency_methods_for :: proc(self: ^Agency, goal: cstring, out: [^]cstring, max_: uint) -> uint {
	buf: [64]u8
	j:   uint

	tc     := world_tri(self.world)
	family := tri.family_index(tc, "methods")
	n: uint = 0
	for i: uint = 0; family != nil && i < uint(tri.index_count(family)) && n < max_; i += 1 {
		name := cstring(tri.index_tag(family, i))
		if !text_at(tc, tri.pattern(tc, name), "goal", buf[:]) || str(buf[:]) != string(goal) do continue
		for j = 0; j < n && string(out[j]) != string(name); j += 1 {}
		if j < n do continue      /* an entry per variant */
		name = world_intern(self.world, name)
		for j = n; j > 0; j -= 1 {
			t := out[j - 1]
			if int_at(tc, tri.pattern(tc, t), "rank", 0) < int_at(tc, tri.pattern(tc, name), "rank", 0) ||
			   (int_at(tc, tri.pattern(tc, t), "rank", 0) == int_at(tc, tri.pattern(tc, name), "rank", 0) &&
			    ns_compare(string(t), string(name)) < 0) {
				break
			}
			out[j] = t
		}
		out[j] = name
		n += 1
	}
	return n
}


/* --- acting ------------------------------------------------------------------------- */

/* Not variadic: in mulle-objc a method's variadic arguments don't arrive
 * through va_start; the callers format. */
@(private)
agency_note :: proc(self: ^Agency, m: ^Motivation, line: string) {
	title: [64]u8

	current: cstring = "-"
	if m.nintentions != 0 do current = goal_title(world_tri(self.world), m.intentions[m.nintentions - 1].goal, title[:])
	append(&m.log, fmt.aprintf("d%d t=%dms [%s] %s", m.decisions, world_time(self.world).ms, current, line))
}


/* The type of what is said: "#IsIn". */
@(private)
agency_kind_of_content :: proc(self: ^Agency, content: cstring) -> cstring {
	arena := tri.arena_new()
	node  := tri.value(world_tri(self.world), content, arena, nil, 0) if content != nil else nil
	kind  := tri.type_name(world_tri(self.world), tri.node_type(node)) if node != nil else "?"
	tri.arena_free(arena)
	return kind
}


/* true if it was attempted. `content` is what is said, or nil. */
@(private)
agency_act :: proc(self: ^Agency, m: ^Motivation, why: string, store: ^Knowledge_Store, operation: cstring,
                   object: u32, target: u32, units: i64, content: cstring) -> bool {
	error: string

	action := action_make(world_intern(self.world, operation), Entity_ID(knowledge_store_self_referent(store)),
	                      Entity_ID(object), Entity_ID(target))
	action.content = world_intern(self.world, content) if content != nil else nil
	if perform_believed(self.world, self.committer, store, action, units, &error) == nil {
		agency_note(self, m, fmt.tprintf("%s: could not %s: %s", why, operation, error))
		return false
	}
	agency_note(self, m, fmt.tprintf("%s: %s R%d%s%s", why, operation, object,
	                                 fmt.tprintf(" into R%d", target) if target != 0 else "",
	                                 fmt.tprintf(": %s", agency_kind_of_content(self, content)) if content != nil else ""))
	return true
}


@(private = "file")
way_letters := [4]u8{'n', 's', 'e', 'w'}


/* Sets out on a walk by `way` (PERFORMANCE.md decision 1), for the
 * current intention: toward referent `toward` believed at (x, y, level), or,
 * exploring (toward 0), to the unseen tile there. */
@(private = "file")
agency_set_out :: proc(self: ^Agency, m: ^Motivation, way: []Step, toward: u32, x: i32, y: i32, level: i32,
                       why: string, note: string) {
	error: string

	letters := make([]u8, len(way) + 1, context.temp_allocator)
	for step, i in way do letters[i] = way_letters[int(step)]
	action    := action_make(world_intern(self.world, "walk"), m.agent, NO_ENTITY, NO_ENTITY)
	action.way = world_intern(self.world, cstring(raw_data(letters)))
	if perform(self.world, self.committer, action, 0, &error) == nil {
		agency_note(self, m, fmt.tprintf("%s: could not set out: %s", why, error))
		return
	}
	m.walking = Walk_Purpose{set = true, toward = toward, x = x, y = y, level = level,
	                    goal = m.intentions[m.nintentions - 1].goal if m.nintentions != 0 else nil}
	agency_note(self, m, fmt.tprintf("%s: a walk of %d tiles, %s", why, len(way), note))
}


/* The agent's walk under way, if any (a walk by a way, not of one tile). */
@(private = "file")
agency_walk_under_way :: proc(self: ^Agency, agent: Entity_ID) -> Entity_ID {
	n: uint

	walk    := world_intern(self.world, "walk")
	mine    := world_copy_activities_of(self.world, agent, &n)
	defer free(mine)
	for i: uint = 0; i < n; i += 1 {
		record := (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), mine[i]))
		if record != nil && record.status == ACTIVITYSTATUS_RUNNING &&
		   world_text_field(self.world, "Activity.operation", mine[i]) == walk {
			return mine[i]
		}
	}
	return NO_ENTITY
}


/* Why the walk under way no longer makes sense, or "" (PERFORMANCE.md
 * decision 1): its intention changed, what it goes to moved or is gone, the
 * tile it explores toward was seen, or the way ahead is believed solid. */
@(private = "file")
agency_walk_stale :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store, me: ^Referent, a: Entity_ID) -> string {
	c: Walk_Context

	j    := &m.walking
	goal := m.intentions[m.nintentions - 1].goal if m.nintentions != 0 else nil
	if !j.set do return "it doesn't know what for"
	if goal != j.goal do return "it is doing something else now"
	if j.toward != 0 {
		r := knowledge_store_referent(store, j.toward)
		if r == nil || !r.present do return fmt.tprintf("R%d is gone from where it was", j.toward)
		if r.x != j.x || r.y != j.y || r.level != j.level do return fmt.tprintf("R%d has moved", j.toward)
	} else if !j.wander && knowledge_store_has_seen_x(store, j.x, j.y, j.level) {
		return "it has seen where it was going"
	}
	record := (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), a))
	if record == nil || !has_text(record.way) do return ""
	c.world = self.world
	c.store = store
	c.level = me.level
	x, y   := me.x, me.y
	way    := string(record.way)
	for i := int(record.stage); i < len(way); i += 1 {
		switch way[i] {
		case 'n': y -= 1
		case 's': y += 1
		case 'e': x += 1
		case 'w': x -= 1
		}
		if !walkable(&c, x, y) do return fmt.tprintf("the way is blocked at (%d, %d)", x, y)
	}
	return ""
}


/* What it does with an activity it puts down: a walk is given up, there
 * being nothing to resume; anything else suspended. */
@(private = "file")
agency_put_aside :: proc(self: ^Agency, a: Entity_ID, why: string, error: ^string) -> ^Proposal_Group {
	if world_text_field(self.world, "Activity.operation", a) == world_intern(self.world, "walk") {
		return activities_abort(self.activities, a, why, error)
	}
	return activities_suspend(self.activities, a, why, error)
}


/* A walk toward a believed place, on the shortest way over the ground
 * as it believes it (BGPath: a tile never seen it guesses open), to within
 * reach of it; with no way within a search's reach, toward the nearest it
 * came. */
@(private)
agency_walk :: proc(self: ^Agency, m: ^Motivation, why: string, me: ^Referent, target: ^Referent,
                    store: ^Knowledge_Store, range: i32 = 1) {
	c:   Walk_Context
	q:   Path_Query
	way: [dynamic]Step

	way        = make([dynamic]Step, context.temp_allocator)
	q          = {}
	c.world    = self.world
	c.store    = store
	c.level    = me.level
	q.x        = me.x
	q.y        = me.y
	/* toward the nearest of an area's tiles (content/things.tri) */
	east, south := referent_extent(target)
	near       := area_nearest(Location{form = .On_Tile, x = target.x, y = target.y, level = target.level}, east, south,
	                           Location{form = .On_Tile, x = me.x, y = me.y, level = me.level})
	q.targeted = true
	q.tx       = near.x
	q.ty       = near.y
	q.context_ = &c
	q.passable = walkable
	q.way      = &way
	self.pathSearches += 1
	r := path_find(&q)
	if r.step == .None {
		agency_note(self, m, fmt.tprintf("%s: no way toward R%d at (%d, %d)", why, target.id, target.x, target.y))
		return
	}
	/* for something done from further off (a shot), only as far as that */
	if range > 1 {
		x, y := me.x, me.y
		for step, i in way {
			if abs(near.x - x) <= range && abs(near.y - y) <= range {
				resize(&way, i)
				break
			}
			switch step {
			case .North: y -= 1
			case .South: y += 1
			case .East:  x += 1
			case .West:  x -= 1
			case .None:
			}
		}
	}
	agency_set_out(self, m, way[:], target.id, target.x, target.y, target.level, why,
	               fmt.tprintf("toward R%d at (%d, %d)", target.id, target.x, target.y))
}


/* Whether the operation uses the voice and nothing else. */
@(private = "file")
voice_only :: proc(tc: ^tri.Content, operation: cstring) -> bool {
	text: [32]u8

	voice := false
	for list := tri.at(tc, tri.pattern(tc, operation), "uses") if operation != nil else nil;
	    list != nil && tri.at(tc, list, "first") != nil;
	    list = tri.at(tc, list, "rest") {
		tri.print(tc, tri.at(tc, list, "first"), raw_data(text[:]), size_of(text))
		if str(text[:]) != "\"voice\"" do return false
		voice = true
	}
	return voice
}


@(private)
agency_busy :: proc(self: ^Agency, agent: Entity_ID) -> bool {
	n: uint

	running := tri.type_named(world_tri(self.world), "\"running\"")
	mine    := world_copy_activities_of(self.world, agent, &n)
	busy    := false
	for i: uint = 0; i < n && !busy; i += 1 {
		record := (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), mine[i]))
		/* talking occupies the voice, not the mind (ACTIONS.md §5: walking
		 * while talking works) */
		busy = record != nil && record.status == u32(running) && !voice_only(world_tri(self.world), record.operation)
	}
	free(mine)
	return busy
}


/* --- deciding ----------------------------------------------------------------------- */

/* A repetition: the habit grows, from what is left of it. */
agency_practise :: proc(self: ^Agency, m: ^Motivation, context_in: cstring, choice: u32) {
	k: i32

	context_ := world_intern(self.world, context_in)
	s := habit_strength(m, context_, choice, world_time(self.world).ms)
	for k = 0; k < m.nhabits && !(m.habits[k].context_ == context_ && m.habits[k].choice == choice); k += 1 {}
	if k == m.nhabits && m.nhabits == BG_MAX_HABITS {
		/* full: the weakest goes, the oldest of the weakest (AGENCY.md §8) */
		now := world_time(self.world).ms
		k = 0
		for q: i32 = 1; q < m.nhabits; q += 1 {
			sq := habit_strength(m, m.habits[q].context_, m.habits[q].choice, now)
			sk := habit_strength(m, m.habits[k].context_, m.habits[k].choice, now)
			if sq < sk || (sq == sk && m.habits[q].at < m.habits[k].at) do k = q
		}
	} else if k == m.nhabits {
		m.nhabits += 1
	}
	h         := &m.habits[k]
	h.context_ = context_
	h.choice   = choice
	h.strength = 100 if s + BG_HABIT_GAIN > 100 else s + BG_HABIT_GAIN
	h.at       = world_time(self.world).ms
}


/* The agent puts down what it is doing: its running activities suspended. */
@(private = "file")
agency_put_down :: proc(self: ^Agency, m: ^Motivation, why: string) {
	n: uint

	mine := world_copy_activities_of(self.world, m.agent, &n)
	for i: uint = 0; self.activities != nil && i < n; i += 1 {
		record := (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), mine[i]))
		if record == nil || record.status != u32(tri.type_named(world_tri(self.world), "\"running\"")) do continue
		error: string
		if agency_put_aside(self, mine[i], why, &error) != nil {
			agency_note(self, m, fmt.tprintf("%s: putting %s down", why,
			                                 world_text_field(self.world, "Activity.operation", mine[i])))
		}
	}
	free(mine)
}


/* What the agent believes it holds, as one number (the referents, mixed):
 * changed, something came into its hands or left them. */
@(private)
agency_held_signature :: proc(store: ^Knowledge_Store) -> u64 {
	sig: u64 = 0
	me := knowledge_store_self_referent(store)
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if r.present && r.form == .Held_By && r.container == me do sig += (u64(r.id) + 1) * 0x9E3779B97F4A7C15
	}
	return sig
}


/* Since when a place looked into counts as searched: since the goal was
 * adopted; one of the agent's own, for a commitment, since its window
 * opened. */
@(private = "file")
agency_searched_since :: proc(self: ^Agency, c: ^Condition, place: u32) -> i64 {
	if self.ownSearched == 0 || self.ownSearched >= c.since do return c.since
	owned := knowledge_store_finding(c.store, "#Owned", place)
	return self.ownSearched if owned != nil && owned.choice == knowledge_store_self_referent(c.store) else c.since
}


/* `since`, or, when what the agent is doing is a commitment, when its
 * window opened if that is earlier. */
@(private = "file")
agency_since_window :: proc(m: ^Motivation, since: i64) -> i64 {
	if m.nintentions == 0 do return since
	if root := &m.intentions[0]; root.commitment > 0 && root.commitment <= m.ncommitments {
		return min(since, m.commitments[root.commitment - 1].from)
	}
	return since
}


/* A commitment's window closed: what it was doing for it, begun in the
 * window and running still or put down (an operation of the goal's own
 * methods: a night's sleep), is given up, not taken up again another day
 * (a sleep cut short by the morning, resumed the next night, ended at once,
 * and the agent was up all night). */
@(private = "file")
agency_give_up_window :: proc(self: ^Agency, m: ^Motivation, c: ^Commitment) {
	methods: [BG_MAX_METHODS]cstring
	op:      [64]u8
	n:       uint

	if self.activities == nil do return
	tc       := world_tri(self.world)
	running  := u32(tri.type_named(tc, "\"running\""))
	starting := u32(tri.type_named(tc, "\"starting\""))
	put_down := u32(tri.type_named(tc, "\"suspended\""))
	nm := agency_methods_for_mind(self, c.goal, m, raw_data(methods[:]), BG_MAX_METHODS)
	mine := world_copy_activities_of(self.world, m.agent, &n)
	defer free(mine)
	for i: uint = 0; i < n; i += 1 {
		record := (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), mine[i]))
		if record == nil || record.started < c.from || (record.status != running && record.status != starting && record.status != put_down) {
			continue
		}
		name := world_text_field(self.world, "Activity.operation", mine[i])
		ours := false
		for j: uint = 0; j < nm && !ours; j += 1 {
			for steps := tri.at(tc, tri.pattern(tc, methods[j]), "steps"); steps != nil && !ours; steps = tri.at(tc, steps, "rest") {
				step := tri.at(tc, steps, "first")
				if step == nil do break
				ours = text_at(tc, step, "op", op[:]) && name != nil && string(name) == str(op[:])
			}
		}
		if ours && activities_abort(self.activities, mine[i], "its window is over", nil) != nil {
			agency_note(self, m, fmt.tprintf("giving up the %s: its window is over", name))
		}
	}
}


/* Whether the act is the same as the agent's last, done again at once
 * so many times running (AGENCY.md decision 24): it gets nowhere. */
@(private)
agency_again :: proc(self: ^Agency, m: ^Motivation, op: cstring, item: u32, target: u32) -> bool {
	again := &m.again
	now   := world_time(self.world).ms
	opi   := world_intern(self.world, op)
	if again.op == opi && again.item == item && again.target == target && now - again.at <= BG_AGAIN_WITHIN {
		again.times += 1
	} else {
		again^ = Repeated_Act{op = opi, item = item, target = target, times = 0}
	}
	again.at = now
	if again.times >= BG_AGAIN_TIMES {
		again^ = {}
		return true
	}
	return false
}


/* Whether the agent has a suspended activity of one of the method's
 * operations. */
@(private = "file")
agency_suspended_step_of :: proc(self: ^Agency, method: cstring, m: ^Motivation) -> bool {
	op: [64]u8

	tc := world_tri(self.world)
	for steps := tri.at(tc, tri.pattern(tc, method), "steps"); steps != nil; steps = tri.at(tc, steps, "rest") {
		step := tri.at(tc, steps, "first")
		if step == nil do break
		if text_at(tc, step, "op", op[:]) &&
		   agency_activity(self, cstr(op[:]), m.agent, "suspended", 0) != NO_ENTITY {
			return true
		}
	}
	return false
}


/* The method's failure: the goal tries its next. */
@(private)
agency_fail :: proc(self: ^Agency, m: ^Motivation, index: i32, why: string) {
	top        := &m.intentions[m.nintentions - 1]
	top.failed |= u32(1) << u32(index)
	top.pending = -1
	agency_note(self, m, why)
}


/* Follows a method whose `pre` holds, with its bindings: passes over the
 * subgoals already done, adopts the first that isn't, or performs the
 * operation. true when it acted. */
@(private = "file")
agency_follow :: proc(self: ^Agency, m: ^Motivation, method: cstring, index: i32, b: [^]Slot_Binding, n: i32,
                      store: ^Knowledge_Store) -> bool {
	roles: [2]u32
	title: [64]u8
	goal:  [64]u8
	op:    [64]u8
	slot:  [32]u8
	names := [2]cstring{"object", "target"}
	text:  [2048]u8
	r:     ^Referent

	n := n
	tc        := world_tri(self.world)
	utterance := tri.type_named(tc, "#Utterance")
	pattern   := tri.pattern(tc, method)
	me        := knowledge_store_referent(store, knowledge_store_self_referent(store))
	achieve   := tri.type_named(tc, "#Achieve")
	if !text_at(tc, pattern, "title", title[:]) do put(title[:], string(method))

	sequence := tri.at(tc, pattern, "sequence") != nil && tri.node_type(tri.at(tc, pattern, "sequence")) == tri.type_named(tc, "true")
	k: i32 = 0
	for steps := tri.at(tc, pattern, "steps"); steps != nil; steps, k = tri.at(tc, steps, "rest"), k + 1 {
		step := tri.at(tc, steps, "first")
		if step == nil do break
		/* a recipe's operation done already: an instant one performed, a timed
		 * one completed since the goal was adopted */
		if sequence && text_at(tc, step, "op", op[:]) {
			d: i64
			e: string

			if k < 32 && (m.intentions[m.nintentions - 1].stepsDone & (u32(1) << u32(k))) != 0 do continue
			if operation_stage(self.world, cstr(op[:]), 0, &d, &e) && d > 0 &&
			   agency_activity(self, cstr(op[:]), m.agent, "completed", m.intentions[m.nintentions - 1].adopted) != NO_ENTITY {
				continue
			}
		}
		if tri.node_type(step) == achieve {
			if !text_at(tc, step, "subgoal", goal[:]) || tri.at(tc, tri.pattern(tc, cstr(goal[:])), "done") == nil {
				agency_fail(self, m, index, fmt.tprintf("%s: there is no goal %s", str(title[:]), str(goal[:])))
				return false
			}
			if agency_holds(self, cstr(goal[:]), "done", 0, b, &n, store) do continue
			if m.nintentions == BG_MAX_INTENTIONS {
				agency_fail(self, m, index, fmt.tprintf("%s: too many goals deep", str(title[:])))
				return false
			}
			agency_note(self, m, fmt.tprintf("%s: %s first", str(title[:]), goal_title(tc, cstr(goal[:]), op[:])))
			m.intentions[m.nintentions - 1].pending = index
			agency_adopt(self, cstr(goal[:]), m, b, n)
			return false
		}

		/* going where it hasn't been, beside ground of a kind (#Explore) */
		if tri.node_type(step) == tri.type_named(tc, "#Explore") {
			over: Terrain_Kind
			if text_at(tc, step, "beside", slot[:]) && world_terrain(self.world) != nil {
				over = terrain_kind_named(world_terrain(self.world), cstr(slot[:]))
			}
			if agency_explore(self, m, store, over) do return true
			agency_fail(self, m, index, fmt.tprintf("%s: nowhere left to look", str(title[:])))
			return false
		}
		/* wandering: to a tile of the kind of ground, near (#Wander); in a
		 * sequence, done once it sets out */
		if tri.node_type(step) == tri.type_named(tc, "#Wander") {
			if sequence && k < 32 && (m.intentions[m.nintentions - 1].stepsDone & (u32(1) << u32(k))) != 0 do continue
			on: Terrain_Kind
			if text_at(tc, step, "over", slot[:]) && world_terrain(self.world) != nil {
				on = terrain_kind_named(world_terrain(self.world), cstr(slot[:]))
			}
			if agency_wander(self, m, store, i32(int_at(tc, step, "radius", 8)), on) {
				if sequence && k < 32 do m.intentions[m.nintentions - 1].stepsDone |= u32(1) << u32(k)
				return true
			}
			agency_fail(self, m, index, fmt.tprintf("%s: nowhere to wander", str(title[:])))
			return false
		}
		/* handing over what is owed (content/deals/'s #HandOver) */
		if tri.type_named(tc, "#HandOver") != 0 && tri.node_type(step) == tri.type_named(tc, "#HandOver") {
			why := agency_hand_over(self, m, store, me, str(title[:]), b, n)
			if why == "" do return true
			agency_fail(self, m, index, fmt.tprintf("%s: %s", str(title[:]), why))
			return false
		}
		/* buying a lot (content/market/'s #Purchase): asked, or on the way */
		if tri.type_named(tc, "#Purchase") != 0 && tri.node_type(step) == tri.type_named(tc, "#Purchase") {
			why := agency_purchase(self, m, store, me, step, str(title[:]), b, n)
			if why == "" do return true
			agency_fail(self, m, index, fmt.tprintf("%s: %s", str(title[:]), why))
			return false
		}
		/* the operation, within reach of what it names */
		if !text_at(tc, step, "op", op[:]) do continue
		/* an activity of it the agent suspended: resumed, not begun again;
		 * put down out of reach (the bed, from the larder), walked back to
		 * first */
		resume_failed: string
		suspended: Entity_ID
		if self.activities != nil {
			suspended = agency_activity(self, cstr(op[:]), m.agent, "suspended", 0)
			if suspended != NO_ENTITY {
				if activities_resume(self.activities, suspended, &resume_failed) != nil {
					agency_note(self, m, fmt.tprintf("%s: resuming %s", str(title[:]), str(op[:])))
					return true
				}
				if resume_failed == "" do resume_failed = "it can't be"
			}
		}
		for q := 0; q < 2; q += 1 {
			roles[q] = 0
			if !text_at(tc, step, names[q], slot[:]) do continue
			roles[q] = bound(b, n, str(slot[:]))
			if roles[q] == 0 && resume_failed != "" do break
			if roles[q] == 0 {
				agency_fail(self, m, index, fmt.tprintf("%s: %s names %s, which nothing fills", str(title[:]), str(op[:]),
				                                        str(slot[:])))
				return false
			}
		}
		/* what it names is gone from where it was believed: the method fails */
		for q := 0; q < 2; q += 1 {
			if roles[q] == 0 do continue
			r = knowledge_store_referent(store, roles[q])
			if r != nil && !r.present && resume_failed == "" {
				agency_fail(self, m, index, fmt.tprintf("%s: R%d is gone from where it was", str(title[:]), r.id))
				return false
			}
		}
		for q := 0; q < 2; q += 1 {
			if roles[q] == 0 do continue
			r = knowledge_store_referent(store, roles[q])
			if !referent_in_reach(me, r, operation_range(self.world, cstr(op[:]))) && r != nil && r.present {
				agency_walk(self, m, str(title[:]), me, r, store, operation_range(self.world, cstr(op[:])))
				return true
			}
		}
		/* within reach of what it names, and the one put down binds what is
		 * gone or out of reach (yesterday's half-sawn trunk): given up, and
		 * begun again on this */
		if resume_failed != "" && (strings.contains(resume_failed, "out of reach") || strings.contains(resume_failed, "is gone")) {
			agency_note(self, m, fmt.tprintf("%s: giving up the %s put down: %s", str(title[:]), str(op[:]), resume_failed))
			activities_abort(self.activities, suspended, "given up", nil)
			resume_failed = ""
		}
		if resume_failed != "" {
			agency_note(self, m, fmt.tprintf("%s: could not resume %s: %s", str(title[:]), str(op[:]), resume_failed))
			return true
		}
		/* what it says, if anything: after a question, it waits for the answer */
		says := tri.at(tc, step, "says")
		content: cstring = nil
		if says != nil && tri.subtype(tc, tri.node_type(says), tri.type_named(tc, "#Grievance")) != 0 &&
		   text_at(tc, step, "regarding", slot[:]) {
			/* a grievance: what it believes of the thing, whose it is, who took it */
			grievance := knowledge_store_grievance_about(store, bound(b, n, str(slot[:])))
			if grievance == "" {
				agency_fail(self, m, index, fmt.tprintf("%s: it can't say what was taken", str(title[:])))
				return false
			}
			put(text[:], grievance)
			content = cstr(text[:])
		} else if string(cstr(op[:])) == "post" && text_at(tc, step, "regarding", slot[:]) {
			/* a price posted (content/market/): what it holds a unit of the
			 * goods worth, written on the stall's board */
			posted := agency_price_writing(self, m, store, bound(b, n, str(slot[:])), roles[0])
			if posted == "" {
				agency_fail(self, m, index, fmt.tprintf("%s: it can't price what is set out", str(title[:])))
				return false
			}
			put(text[:], posted)
			content = cstr(text[:])
		} else if says != nil && tri.node_type(says) != utterance {
			tri.print(tc, says, raw_data(text[:]), size_of(text))
			content = cstr(text[:])
		}
		/* the same act again and again, at once: it gets nowhere, so the
		 * method fails (and with no other, the goal is impossible for now) */
		if agency_again(self, m, cstr(op[:]), roles[0], roles[1]) {
			agency_fail(self, m, index, fmt.tprintf("%s: %s R%d again, to no end", str(title[:]), str(op[:]), roles[0]))
			return false
		}
		if agency_act(self, m, str(title[:]), store, cstr(op[:]), roles[0], roles[1], int_at(tc, step, "units", 0), content) {
			ctx: [128]u8

			if sequence && k < 32 {
				d: i64
				e: string

				if !(operation_stage(self.world, cstr(op[:]), 0, &d, &e) && d > 0) {
					m.intentions[m.nintentions - 1].stepsDone |= u32(1) << u32(k)
				}
			}

			/* a repetition of the method, and of what it chose for each slot */
			put(ctx[:], fmt.tprintf("%s:%s", m.intentions[m.nintentions - 1].goal, method))
			agency_practise(self, m, cstr(ctx[:]), 0)
			for q := 0; q < 2; q += 1 {
				if roles[q] != 0 && text_at(tc, step, names[q], slot[:]) {
					put(ctx[:], fmt.tprintf("%s.%s", method, str(slot[:])))
					agency_practise(self, m, cstr(ctx[:]), roles[q])
				}
			}
		} else {
			content = nil
		}
		if content != nil && tri.subtype(tc, tri.node_type(says), tri.type_named(tc, "#Question")) != 0 {
			m.awaiting   = roles[0]
			m.awaitSince = world_time(self.world).ms
			m.awaitUntil = m.awaitSince + BG_REPLY_WAIT
		}
		return true
	}
	/* a way that ends its goal: followed through, the goal is done, whatever
	 * `done` says (its last resort, METHODS.md) */
	if ends := tri.at(tc, pattern, "ends"); ends != nil && tri.node_type(ends) == tri.type_named(tc, "true") {
		top := &m.intentions[m.nintentions - 1]
		agency_note(self, m, fmt.tprintf("done, as %s does", str(title[:])))
		agency_settle(self, m, top, done = true)
		m.nintentions -= 1
		if m.nintentions != 0 {
			m.intentions[m.nintentions - 1].pending = -1
			agency_note(self, m, fmt.tprintf("back to it: %s is done", goal_title(tc, top.goal, goal[:])))
		}
		return false
	}
	agency_fail(self, m, index, fmt.tprintf("%s: every step is done, and the goal is not", str(title[:])))
	return false
}


/* The titles of the methods before `count` that haven't failed, so their
 * precondition doesn't hold: "fetch nails", or "" if none. */
@(private = "file")
agency_passed_over :: proc(self: ^Agency, methods: [^]cstring, count: uint, failed: u32) -> string {
	title: [64]u8

	titles := make([dynamic]string, context.temp_allocator)
	for i: uint = 0; i < count; i += 1 {
		if (failed & (u32(1) << u32(i))) == 0 {
			if !text_at(world_tri(self.world), tri.pattern(world_tri(self.world), methods[i]), "title", title[:]) {
				put(title[:], string(methods[i]))
			}
			append(&titles, strings.clone(str(title[:]), context.temp_allocator))
		}
	}
	return strings.join(titles[:], ", ", context.temp_allocator) if len(titles) != 0 else ""
}


/* An answer to a #WhereIs, from what the agent knows: where it believes the
 * thing like `what` it saw last is, inside something on the ground, and how
 * it knows: it saw it, or heard it, from whoever its strongest testimony
 * says saw it, or from no one it can name; or that it doesn't know. A
 * #WhoToldYou asks the same of the container like `within`: the answer is
 * the claim again, with its source. */
@(private = "file")
agency_answer_to :: proc(self: ^Agency, question: ^tri.Node, store: ^Knowledge_Store) -> string {
	result:  tri.Match_Result
	printed: [2048]u8

	tc     := world_tri(self.world)
	what   := tri.at(tc, question, "what")
	within := tri.at(tc, question, "within") if tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#Placing")) != 0 else nil
	arena  := tri.arena_new()
	best: ^Referent = nil
	for i: uint = 0; what != nil && i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if !r.present || (r.form != .In && r.form != .Held_By) || r.id == knowledge_store_self_referent(store) ||
		   r.kind == nil {
			continue
		}
		c := knowledge_store_referent(store, r.container)
		if c == nil || (c.form != .On_Tile if r.form == .In else (c.kind == nil || string(c.kind) != "#Agent")) do continue
		if within != nil && r.form != .In do continue
		kind        := tri.value(tc, r.kind, arena, nil, 0)
		description := tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, r.id)), arena, nil, 0)
		if kind == nil || tri.subtype(tc, tri.node_type(kind), tri.node_type(what)) == 0 ||
		   description == nil || tri.match(tc, what, description, &result) == .Incompatible {
			continue
		}
		if within != nil {
			description = tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, c.id)), arena, nil, 0)
			if description == nil || tri.match(tc, within, description, &result) == .Incompatible do continue
		}
		if best == nil || r.seen > best.seen do best = r
	}
	tri.arena_free(arena)
	if best != nil do return knowledge_store_claim_about(store, best.id)
	tri.print(tc, what, raw_data(printed[:]), size_of(printed))
	return fmt.tprintf("#DontKnow & {{ what: %s }}", str(printed[:]))
}


/* Questions put to the agent since it last looked become candidates. */
@(private = "file")
agency_hear_questions :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store) {
	tc := world_tri(self.world)
	me := knowledge_store_self_referent(store)
	for i: uint = 0; i < knowledge_store_observation_count(store); i += 1 {
		o := knowledge_store_observation_at(store, i)
		if o.serial < m.heard || string(o.kind) != "said" || o.other != me || o.actor == 0 || o.actor == me ||
		   o.content == nil || m.nquestions == BG_MAX_QUESTIONS {
			continue
		}
		arena    := tri.arena_new()
		question := tri.value(tc, o.content, arena, nil, 0)
		if question != nil && (tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#WhereIs")) != 0 ||
		                       tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#WhoToldYou")) != 0 ||
		                       tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#Request")) != 0 ||
		                       tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#AskWork")) != 0 ||
		                       tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#Call")) != 0 ||
		                       (tri.type_named(tc, "#Proposing") != 0 &&
		                        (tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#Proposing")) != 0 ||
		                         tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#Refuse")) != 0 ||
		                         tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#Repaid")) != 0)) ||
		                       (tri.type_named(tc, "#Buy") != 0 && tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#Buy")) != 0)) {
			m.questions[m.nquestions]         = {}
			m.questions[m.nquestions].asker   = o.actor
			m.questions[m.nquestions].content = world_intern(self.world, o.content)
			m.questions[m.nquestions].heard   = o.time
			m.nquestions += 1
		}
		tri.arena_free(arena)
	}
	m.heard = knowledge_store_next_serial(store)
}


@(private)
agency_drop_question :: proc(self: ^Agency, m: ^Motivation, k: i32) {
	copy(m.questions[k:m.nquestions - 1], m.questions[k + 1:m.nquestions])
	m.nquestions -= 1
}


/* Something the agent holds like the description, or 0. */
@(private)
agency_held_like :: proc(self: ^Agency, what: ^tri.Node, store: ^Knowledge_Store) -> u32 {
	result: tri.Match_Result

	tc    := world_tri(self.world)
	arena := tri.arena_new()
	found: u32 = 0
	for i: uint = 0; what != nil && i < knowledge_store_count(store) && found == 0; i += 1 {
		r := knowledge_store_referent_at(store, i)
		if !r.present || r.form != .Held_By || r.container != knowledge_store_self_referent(store) do continue
		description := tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, r.id)), arena, nil, 0)
		if description != nil && tri.match(tc, what, description, &result) == .Entailed do found = r.id
	}
	tri.arena_free(arena)
	return found
}


/* What a unit of something like the description is worth to the agent in
 * coins (content/money/coins.tri's #Pricing): the most of the `prices`
 * whose `valued` it entails, raised by what it feels of the need the price
 * names, `per` tenths of a coin a point, unless what it prices is spare
 * (`needed` false: a seller's, kept back from); -1 if none: it isn't
 * goods. A seller's `stock` of it (grams; -1, not known) moves what it
 * asks: the price's `asks`, over the stock as a percent of its `plenty`,
 * a percent of its `coins`, never less than a coin. */
@(private)
agency_pricing :: proc(self: ^Agency, description: ^tri.Node, store: ^Knowledge_Store, needed := true, stock: i64 = -1) -> i32 {
	result: tri.Match_Result
	need:   [32]u8

	tc     := world_tri(self.world)
	family := tri.family_index(tc, "prices")
	best: i32 = -1
	for i: uint = 0; description != nil && family != nil && i < uint(tri.index_count(family)); i += 1 {
		pattern := tri.pattern(tc, cstring(tri.index_tag(family, i)))
		of      := tri.at(tc, pattern, "valued") if pattern != nil else nil
		if of == nil || tri.match(tc, of, description, &result) != .Entailed do continue
		v := i32(int_at(tc, pattern, "coins", 0))
		if needed && text_at(tc, pattern, "pressure", need[:]) {
			v += i32(i64(knowledge_store_feels(store, cstr(need[:]))) * int_at(tc, pattern, "per", 0) / 10)
		}
		pct: i32 = 100
		if plenty := int_at(tc, pattern, "plenty", 0); !needed && stock >= 0 && plenty > 0 &&
		   curve_at(tc, tri.at(tc, pattern, "asks"), stock * 100 / plenty, &pct) {
			v = max(1, i32(i64(v) * i64(pct) / 100))
		}
		best = max(best, v)
	}
	return best
}


/* The agent's pricing of a thing it knows of (agency_pricing, of what it
 * believes the thing to be). */
@(private = "file")
agency_pricing_of :: proc(self: ^Agency, thing: u32, store: ^Knowledge_Store, needed := true, stock: i64 = -1) -> i32 {
	tc    := world_tri(self.world)
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	if knowledge_store_referent(store, thing) == nil do return -1
	return agency_pricing(self, tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, thing)), arena, nil, 0), store, needed, stock)
}


/* How many units a stack it knows of holds: its mass as it recalls it, by
 * its unit's (the unit's blueprint's); 0 if it can't tell. */
@(private)
agency_units_of :: proc(self: ^Agency, thing: u32, store: ^Knowledge_Store) -> i64 {
	unit: [64]u8

	tc    := world_tri(self.world)
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	if knowledge_store_referent(store, thing) == nil do return 0
	d := tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, thing)), arena, nil, 0)
	if d == nil || !text_at(tc, d, "unit", unit[:]) do return 0
	blueprint := tri.pattern(tc, cstr(unit[:]))
	each := int_at(tc, blueprint, "unitMass", 0)
	if each <= 0 do each = int_at(tc, blueprint, "mass", 0)
	return int_at(tc, d, "mass", 0) / each if each > 0 else 0
}


/* Whoever it sees minding the stall (content/market/): the seller whose
 * price it read there (`seller`), if it sees it beside it; else an agent,
 * not itself, beside it, the lowest. nil if none. */
@(private = "file")
agency_minding :: proc(self: ^Agency, stall: ^Referent, store: ^Knowledge_Store, seller: u32 = 0) -> ^Referent {
	if o := knowledge_store_referent(store, seller); stall != nil && o != nil && seller != knowledge_store_self_referent(store) &&
	   o.present && o.form == .On_Tile && o.level == stall.level && abs(o.x - stall.x) <= 1 && abs(o.y - stall.y) <= 1 {
		return o
	}
	for i: uint = 0; stall != nil && i < knowledge_store_count(store); i += 1 {
		o := knowledge_store_referent_at(store, i)
		if o.present && o.id != knowledge_store_self_referent(store) && o.kind != nil && string(o.kind) == "#Agent" &&
		   o.form == .On_Tile && o.level == stall.level && abs(o.x - stall.x) <= 1 && abs(o.y - stall.y) <= 1 {
			return o
		}
	}
	return nil
}


/* The stall nearest someone it knows of: a #Stall, within two tiles of
 * them; 0 if none. */
@(private = "file")
agency_stall_by :: proc(self: ^Agency, who: u32, store: ^Knowledge_Store) -> u32 {
	person := knowledge_store_referent(store, who)
	best: u32 = 0
	bestAt: i32 = 3
	for i: uint = 0; person != nil && i < knowledge_store_count(store); i += 1 {
		o := knowledge_store_referent_at(store, i)
		if !o.present || o.form != .On_Tile || o.level != person.level do continue
		d := max(abs(o.x - person.x), abs(o.y - person.y))
		if d >= bestAt || !agency_is_a(self, o, "#Stall") do continue
		best, bestAt = o.id, d
	}
	return best
}


/* Whether the referent is believed of the type named. */
@(private)
agency_is_a :: proc(self: ^Agency, r: ^Referent, name: cstring) -> bool {
	tc := world_tri(self.world)
	t  := tri.type_named(tc, name)
	if r == nil || r.kind == nil || t == 0 do return false
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	k := tri.value(tc, r.kind, arena, nil, 0)
	return k != nil && tri.subtype(tc, tri.node_type(k), t) != 0
}


/* Something like `what` set out on a stall within its reach (content/
 * market/): what a seller sells from. 0 if none. */
@(private = "file")
agency_on_stall_like :: proc(self: ^Agency, what: ^tri.Node, me: ^Referent, store: ^Knowledge_Store) -> u32 {
	result: tri.Match_Result

	tc    := world_tri(self.world)
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	for i: uint = 0; what != nil && i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if !r.present || r.form != .In do continue
		c := knowledge_store_referent(store, r.container)
		if c == nil || !referent_in_reach(me, c, 1) || !agency_is_a(self, c, "#Stall") do continue
		description := tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, r.id)), arena, nil, 0)
		if description != nil && tri.match(tc, what, description, &result) == .Entailed do return r.id
	}
	return 0
}


/* A sale asked of it (content/market/'s #Buy): from what it has set out
 * on its stall, at the price offered if that is no less than its own
 * pricing now; the goods handed over, and what is owed said. Else it has
 * none, or won't. Its answer. */
@(private = "file")
agency_sell :: proc(self: ^Agency, m: ^Motivation, question: ^tri.Node, asker: u32, store: ^Knowledge_Store) -> string {
	printed: [512]u8

	tc      := world_tri(self.world)
	what    := tri.at(tc, question, "what")
	count   := int_at(tc, question, "count", 1)
	offered := i32(int_at(tc, question, "coins", 0))
	printed[0] = 0
	if what != nil do tri.print(tc, what, raw_data(printed[:]), size_of(printed))
	said := str(printed[:]) if printed[0] != 0 else "#Body"
	me   := knowledge_store_referent(store, knowledge_store_self_referent(store))
	goods := agency_on_stall_like(self, what, me, store)
	if goods == 0 {
		agency_note(self, m, fmt.tprintf("asked by R%d to sell %s: none set out", asker, said))
		return fmt.tprintf("#HaveNone & {{ what: %s }}", said)
	}
	/* spare: it keeps enough back; by its stock at home; and the price it
	 * posted holds, though its stock has moved since */
	mine := agency_pricing_of(self, goods, store, false, agency_stock_of(self, m, goods, store))
	if g := knowledge_store_referent(store, goods); g != nil && mine >= 0 && m.postedUnit != nil &&
	   agency_unit_of_referent(self, store, goods) == m.postedUnit {
		mine = min(mine, m.postedCoins)
	}
	if mine < 0 || offered < mine {
		agency_note(self, m, fmt.tprintf("asked by R%d to sell R%d at %d: it holds it worth %d", asker, goods, offered, mine))
		return fmt.tprintf("#WontSay & {{ what: %s }}", said)
	}
	if have := agency_units_of(self, goods, store); have > 0 && count > have do count = have
	if !agency_act(self, m, "selling", store, "hand_over", goods, asker, count, nil) {
		return fmt.tprintf("#WontSay & {{ what: %s }}", said)
	}
	agency_note(self, m, fmt.tprintf("sold R%d %d of R%d at %d", asker, count, goods, offered))
	return fmt.tprintf("#Sold & {{ what: %s, count: %d, coins: %d }}", said, count, count * i64(offered))
}


/* A seller's stock of goods like `goods` (a referent; content/money/coins.tri):
 * what it believes it has of their unit in the supply its stall is kept
 * from (its commitments' `supply`), in hand, or in its pack, in grams; -1
 * if it keeps none it knows of, or they have no unit. */
@(private = "file")
agency_stock_of :: proc(self: ^Agency, m: ^Motivation, goods: u32, store: ^Knowledge_Store) -> i64 {
	supply: u32
	for k: i32 = 0; k < m.ncommitments && supply == 0; k += 1 {
		c := &m.commitments[k]
		for p in c.params[:c.nparams] do if string(p.slot) == "supply" do supply = p.referent
	}
	u := agency_unit_of_referent(self, store, goods)
	if supply == 0 || u == nil do return -1
	tc    := world_tri(self.world)
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	what := tri.value(tc, ns_utf8(fmt.tprintf("#Stack & {{ unit: \"%s\" }}", u)), arena, nil, 0)
	return agency_mass_toward(self, what, supply, store) if what != nil else -1
}


/* The unit a referent is believed a stack of: interned; nil if none. */
@(private = "file")
agency_unit_of_referent :: proc(self: ^Agency, store: ^Knowledge_Store, r: u32) -> cstring {
	unit: [64]u8

	tc    := world_tri(self.world)
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	if knowledge_store_referent(store, r) == nil do return nil
	d := tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, r)), arena, nil, 0)
	if d == nil || !text_at(tc, d, "unit", unit[:]) do return nil
	return world_intern(self.world, cstr(unit[:]))
}


/* A posted price (content/market/): a #Writing, by the agent, of a #Priced
 * claim: it sells goods of the unit of `goods` at the stall `board` stands
 * on, at what it holds a unit worth. "" if it can't say. */
@(private = "file")
agency_price_writing :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store, goods: u32, board: u32) -> string {
	unit: [64]u8

	tc    := world_tri(self.world)
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	g := knowledge_store_referent(store, goods)
	s := knowledge_store_referent(store, board)
	if g == nil || s == nil do return ""
	d := tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, goods)), arena, nil, 0)
	if d == nil || !text_at(tc, d, "unit", unit[:]) do return ""
	coins := agency_pricing(self, d, store, false, agency_stock_of(self, m, goods, store))   /* spare, by its stock */
	if coins < 0 do return ""
	m.postedUnit, m.postedCoins = world_intern(self.world, cstr(unit[:])), coins
	me := knowledge_store_describe_looks(store, knowledge_store_self_referent(store))
	return fmt.tprintf("#Writing & {{ author: %s, entries: [#Priced & {{ what: #Stack & {{ unit: \"%s\" }}, holder: %s, " +
	                   "site: #OnTile & {{ x: %d, y: %d, level: %d }}, coins: %d, when: %dms, attribution: #Saw & {{ sure: 30 }} }}] }}",
	                   me, str(unit[:]), me, s.x, s.y, s.level, coins, world_time(self.world).ms)
}


/* The lot a #Purchase (or a #Buying, content/market/) is for: the unit of
 * `what`, and `units` of it, no more than will bring the `stocking` slot's
 * referent up to `level` with what it has there, in hand and in its pack;
 * 0 units when that much is coming already. */
@(private = "file")
agency_lot :: proc(self: ^Agency, node: ^tri.Node, b: [^]Slot_Binding, n: i32, store: ^Knowledge_Store) -> (u: cstring, units: i64, ok: bool) {
	unit: [64]u8
	slot: [32]u8

	tc   := world_tri(self.world)
	what := tri.at(tc, node, "what")
	if what == nil || !text_at(tc, what, "unit", unit[:]) do return nil, 0, false
	u     = world_intern(self.world, cstr(unit[:]))
	units = int_at(tc, node, "units", 1)
	if level := int_at(tc, node, "level", 0); level > 0 && text_at(tc, node, "stocking", slot[:]) {
		have := agency_mass_toward(self, what, bound(b, n, str(slot[:])), store)
		if have >= level do return u, 0, true
		units = min(units, (level - have + agency_unit_mass(self, u) - 1) / agency_unit_mass(self, u))
	}
	return u, units, true
}


/* A unit's mass, of its blueprint: a stack's unit, else the whole. */
@(private = "file")
agency_unit_mass :: proc(self: ^Agency, u: cstring) -> i64 {
	tc   := world_tri(self.world)
	each := int_at(tc, tri.pattern(tc, u), "unitMass", 0)
	if each <= 0 do each = int_at(tc, tri.pattern(tc, u), "mass", 1)
	return max(each, 1)
}


/* The cheapest price it knows for the unit, read this market (one read at
 * an earlier market, it may not sell this one), its stall there; of those,
 * the nearest, then the lowest board. -1 if none. */
@(private = "file")
agency_cheapest :: proc(self: ^Agency, store: ^Knowledge_Store, me: ^Referent, u: cstring) -> int {
	best  := -1
	bestAt: i32
	for p, i in store.prices {
		if rawptr(p.unit) != rawptr(u) || world_time(self.world).ms - p.time > BG_PRICE_LAPSE do continue
		r := knowledge_store_referent(store, p.board)
		if r == nil || !r.present do continue
		d := max(abs(r.x - me.x), abs(r.y - me.y)) + (0 if r.level == me.level else 1000)
		if best < 0 || p.coins < store.prices[best].coins ||
		   (p.coins == store.prices[best].coins && (d < bestAt || (d == bestAt && p.board < store.prices[best].board))) {
			best, bestAt = i, d
		}
	}
	return best
}


/* The coins it holds, as it believes. */
@(private = "file")
agency_coins_held :: proc(self: ^Agency, store: ^Knowledge_Store) -> i64 {
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	purse := agency_held_like(self, tri.value(world_tri(self.world), "#Stack & { unit: \"coin\" }", arena, nil, 0), store)
	return agency_units_of(self, purse, store) if purse != 0 else 0
}


/* When the errand the mind's current intention serves began: the adoption
 * of the outermost goal of its chain of subgoals. 0 with none. */
@(private = "file")
agency_errand_since :: proc(m: ^Motivation) -> i64 {
	if m == nil || m.nintentions == 0 do return 0
	base := m.nintentions - 1
	for base > 0 && m.intentions[base - 1].pending >= 0 do base -= 1
	return m.intentions[base].adopted
}


/* What buying needs (content/market/'s #Buying, METHODS.md decision 3):
 * `which` of "coming", "priced", "affords", for the lot. Nothing
 * left to buy, each holds. */
@(private = "file")
agency_buying :: proc(self: ^Agency, cond: ^tri.Node, which: string, b: [^]Slot_Binding, n: i32, store: ^Knowledge_Store) -> bool {
	slot: [32]u8

	tc := world_tri(self.world)
	me := knowledge_store_referent(store, knowledge_store_self_referent(store))
	u, units, ok := agency_lot(self, cond, b, n, store)
	if !ok || me == nil do return false
	if units == 0 do return true
	switch which {
	case "priced":
		return agency_cheapest(self, store, me, u) >= 0
	case "affords":
		/* knowing no price yet, any coins will do to go and look; knowing
		 * one, enough for the lot (it is asked again once it does) */
		best := agency_cheapest(self, store, me, u)
		held := agency_coins_held(self, store)
		if best >= 0 && units * i64(store.prices[best].coins) <= held do return true
		if best < 0 && held > 0 do return true
		/* or no more at home: the coffer looked into on this errand (one
		 * seen empty before may have been filled since), and no coins in it */
		if !text_at(tc, cond, "coinsIn", slot[:]) do return false
		k := bound(b, n, str(slot[:]))
		coffer := knowledge_store_referent(store, k) if k != 0 else nil
		if coffer == nil || coffer.insideSeen < 0 || coffer.insideSeen < agency_errand_since(self.deciding) do return false
		arena := tri.arena_new()
		defer tri.arena_free(arena)
		coin := tri.value(tc, "#Stack & { unit: \"coin\" }", arena, nil, 0)
		for i: uint = 0; i < knowledge_store_count(store); i += 1 {
			r := knowledge_store_referent_at(store, i)
			if r.present && r.form == .In && r.container == k && agency_referent_is_of(self, r, coin) do return false
		}
		return true
	}
	/* "coming": a lot of it in hand is as much as it carries home this
	 * time (its pack full, or none): home with it, before buying more */
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	return agency_held_like(self, tri.value(tc, ns_utf8(fmt.tprintf("#Stack & {{ unit: \"%s\" }}", u)), arena, nil, 0), store) != 0
}


/* Buying (content/market/'s #Purchase): the lot (agency_lot) at the
 * cheapest price it knows (agency_cheapest), if no dearer than its own
 * pricing; as many as its coins pay for. To whoever minds the stall, walked
 * to first. "" once it asks, or sets out; else why it can't. */
@(private = "file")
agency_purchase :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store, me: ^Referent, step: ^tri.Node,
                        title: string, b: [^]Slot_Binding, n: i32) -> string {
	tc := world_tri(self.world)
	u, units, ok := agency_lot(self, step, b, n, store)
	if !ok do return "buy what?"
	if units == 0 do return fmt.tprintf("it has enough %s coming", u)
	what := tri.at(tc, step, "what")
	best := agency_cheapest(self, store, me, u)
	if best < 0 do return fmt.tprintf("it knows no stall selling %s", u)
	price := store.prices[best]
	mine  := agency_pricing(self, what, store)
	if price.coins > mine do return fmt.tprintf("%s at %d is dearer than it holds it worth, %d", u, price.coins, mine)
	have := agency_coins_held(self, store)
	if price.coins > 0 && units * i64(price.coins) > have do units = have / i64(price.coins)
	if units < 1 do return "it hasn't the coins"
	/* somewhere to take the lot: a free hand, or room in its pack (its own
	 * hands and pack, as it feels them) */
	if _, room := receiving(self.world, m.agent, agency_unit_mass(self, u) * units, true); !room {
		return "it has no hand free for it, nor room in its pack"
	}
	stall  := knowledge_store_referent(store, price.board)      /* the board stands on it */
	seller := agency_minding(self, stall, store, price.seller)
	if seller == nil {
		if !referent_in_reach(me, stall, 1) {
			agency_walk(self, m, title, me, stall, store, 1)
			return ""
		}
		return "nobody minds the stall"
	}
	if !referent_in_reach(me, seller, 1) {
		agency_walk(self, m, title, me, seller, store, 1)
		return ""
	}
	content := fmt.tprintf("#Buy & {{ what: #Stack & {{ unit: \"%s\" }}, count: %d, coins: %d }}", u, units, price.coins)
	if !agency_act(self, m, title, store, "say", seller.id, 0, 0, ns_utf8(content)) do return "it couldn't ask"
	m.awaiting   = seller.id
	m.awaitSince = world_time(self.world).ms
	m.awaitUntil = m.awaitSince + BG_REPLY_WAIT
	return ""
}


/* What it knows of things like `what` in the supply, in its hands, or in a
 * pack it carries, in grams: what stocks the supply, or is on its way. */
@(private)
agency_mass_toward :: proc(self: ^Agency, what: ^tri.Node, supply: u32, store: ^Knowledge_Store) -> i64 {
	result: tri.Match_Result

	tc    := world_tri(self.world)
	me    := knowledge_store_self_referent(store)
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	total: i64
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if !r.present do continue
		toward := (r.form == .In && r.container == supply && supply != 0) || (r.form == .Held_By && r.container == me)
		if !toward && r.form == .In {
			c := knowledge_store_referent(store, r.container)
			toward = c != nil && c.form == .Held_By && c.container == me
		}
		if !toward do continue
		d := tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, r.id)), arena, nil, 0)
		if d == nil || tri.match(tc, what, d, &result) != .Entailed do continue
		total += int_at(tc, d, "mass", 0)
	}
	return total
}


/* The mass of the things like `what` the agent believes are in something
 * like `keptIn` that it knows is its own (an #Owned finding): what it has
 * at home. -1 if it has seen inside none: not knowing isn't having none. */
@(private)
agency_at_home :: proc(self: ^Agency, what: ^tri.Node, keptIn: ^tri.Node, store: ^Knowledge_Store) -> i64 {
	result: tri.Match_Result

	tc    := world_tri(self.world)
	me    := knowledge_store_self_referent(store)
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	total: i64
	known := false
	for i: uint = 0; i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		owned := knowledge_store_finding(store, "#Owned", r.id)
		if r.insideSeen >= 0 && owned != nil && owned.choice == me && agency_referent_is_of(self, r, keptIn) do known = true
	}
	if !known do return -1
	for i: uint = 0; what != nil && i < knowledge_store_count(store); i += 1 {
		r := knowledge_store_referent_at(store, i)
		if !r.present || r.form != .In do continue
		owned := knowledge_store_finding(store, "#Owned", r.container)
		if owned == nil || owned.choice != me || !agency_referent_is_of(self, knowledge_store_referent(store, r.container), keptIn) do continue
		d := tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, r.id)), arena, nil, 0)
		if d == nil || tri.match(tc, what, d, &result) != .Entailed do continue
		total += int_at(tc, d, "mass", 0)
	}
	return total
}


/* Answered about a purchase (content/market/): sold, it pays what is owed
 * into the stall by the seller; refused, or none set out, it forgets the
 * price it knew there. */
@(private = "file")
agency_settle_purchase :: proc(self: ^Agency, m: ^Motivation, answer: cstring, seller: u32, store: ^Knowledge_Store) {
	unit: [64]u8

	tc := world_tri(self.world)
	if tri.type_named(tc, "#Sold") == 0 do return
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	said := tri.value(tc, answer, arena, nil, 0) if answer != nil else nil
	if said == nil do return
	stall := agency_stall_by(self, seller, store)
	if tri.subtype(tc, tri.node_type(said), tri.type_named(tc, "#Sold")) != 0 {
		owed  := int_at(tc, said, "coins", 0)
		purse := agency_held_like(self, tri.value(tc, "#Stack & { unit: \"coin\" }", arena, nil, 0), store)
		if owed > 0 && purse != 0 && stall != 0 {
			agency_act(self, m, "paying", store, "pay", purse, stall, owed, nil)
		} else if owed > 0 {
			agency_note(self, m, fmt.tprintf("owes R%d %d coins, and can't pay", seller, owed))
		}
		return
	}
	if (tri.subtype(tc, tri.node_type(said), tri.type_named(tc, "#HaveNone")) != 0 ||
	    tri.subtype(tc, tri.node_type(said), tri.type_named(tc, "#WontSay")) != 0) && text_at(tc, said, "what.unit", unit[:]) {
		/* the price on the board by the seller's stall */
		u := world_intern(self.world, cstr(unit[:]))
		s := knowledge_store_referent(store, stall)
		for i := len(store.prices) - 1; i >= 0; i -= 1 {
			b := knowledge_store_referent(store, store.prices[i].board)
			if s != nil && b != nil && b.level == s.level && abs(b.x - s.x) <= 1 && abs(b.y - s.y) <= 1 &&
			   rawptr(store.prices[i].unit) == rawptr(u) {
				agency_note(self, m, fmt.tprintf("no %s to be had at R%d", u, stall))
				ordered_remove(&store.prices, i)
			}
		}
	}
}


/* What a thing is worth to the agent (AGENCY.md decision 16): the most of
 * the authored values (`values`) whose `valued` what it believes of the
 * thing entails, BG_WORTH if none; raised by what it feels of the need a
 * value names, `per` tenths of a point a point. */
@(private)
agency_worth :: proc(self: ^Agency, thing: u32, store: ^Knowledge_Store) -> i32 {
	tc    := world_tri(self.world)
	arena := tri.arena_new()
	defer tri.arena_free(arena)
	if knowledge_store_referent(store, thing) == nil do return BG_WORTH
	return agency_worth_desc(self, tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, thing)), arena, nil, 0), store)
}


/* The same, of something like the description; without its needs' raise
 * (`needs` false), what it is worth to the agent at ease (NEGOTIATION.md:
 * what repaying it will cost, once the need has passed). */
@(private)
agency_worth_desc :: proc(self: ^Agency, description: ^tri.Node, store: ^Knowledge_Store, needs := true) -> i32 {
	result: tri.Match_Result
	need:   [32]u8

	tc     := world_tri(self.world)
	family := tri.family_index(tc, "values")
	best: i32 = -1
	for i: uint = 0; description != nil && family != nil && i < uint(tri.index_count(family)); i += 1 {
		pattern := tri.pattern(tc, cstring(tri.index_tag(family, i)))
		of      := tri.at(tc, pattern, "valued") if pattern != nil else nil
		if of == nil || tri.match(tc, of, description, &result) != .Entailed do continue
		v := i32(int_at(tc, pattern, "value", 0))
		if needs && text_at(tc, pattern, "pressure", need[:]) {
			v += i32(i64(knowledge_store_feels(store, cstr(need[:]))) * int_at(tc, pattern, "per", 0) / 10)
		}
		best = v if v > best else best
	}
	return BG_WORTH if best < 0 else best
}


agency_worth_of :: proc(self: ^Agency, thing: u32, agent: Entity_ID) -> i32 {
	return agency_worth(self, thing, knowledge_store_of(self.knowledge, agent))
}


/* What lending a thing costs (AGENCY.md decision 16): its worth, less by
 * the agent's trust that it comes back: all of it at the least trust,
 * nothing at the most. */
@(private = "file")
agency_lending :: proc(self: ^Agency, thing: u32, borrower: u32, store: ^Knowledge_Store) -> i32 {
	return agency_worth(self, thing, store) * (BG_TRUST_LIMIT - knowledge_store_trust_in(store, borrower)) / (2 * BG_TRUST_LIMIT)
}


/* Asked where something is (AGENCY.md decision 11): the best lie it knows
 * (`lies`), with `what` bound to what it holds like it, if one scores more
 * than nothing: what it says, that it doesn't know. Otherwise "": it
 * answers truly. */
@(private = "file")
agency_lie_to :: proc(self: ^Agency, m: ^Motivation, question: ^tri.Node, store: ^Knowledge_Store) -> string {
	b:       [1]Slot_Binding
	title:   [64]u8
	printed: [2048]u8

	tc := world_tri(self.world)
	if tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#WhereIs")) == 0 do return ""
	b[0].referent = agency_held_like(self, tri.at(tc, question, "what"), store)
	if b[0].referent == 0 do return ""
	b[0].slot = world_intern(self.world, "what")
	family   := tri.family_index(tc, "lies")
	lie: cstring = nil
	best: [dynamic]string
	most: i32 = 0
	for i: uint = 0; family != nil && i < uint(tri.index_count(family)); i += 1 {
		parts := make([dynamic]string, context.temp_allocator)
		score := agency_sum(self, cstring(tri.index_tag(family, i)), "score", raw_data(b[:]), 1, store, &parts)
		if lie == nil || score > most {
			lie  = cstring(tri.index_tag(family, i))
			most = score
			best = parts
		}
	}
	if lie == nil do return ""
	if !text_at(tc, tri.pattern(tc, lie), "title", title[:]) do put(title[:], string(lie))
	agency_note(self, m, fmt.tprintf("%s %+d (%s): %s", str(title[:]), most, strings.join(best[:], ", ", context.temp_allocator),
	                                 "lying" if most > 0 else "telling the truth"))
	if most <= 0 do return ""
	tri.print(tc, tri.at(tc, question, "what"), raw_data(printed[:]), size_of(printed))
	return fmt.tprintf("#DontKnow & {{ what: %s }}", str(printed[:]))
}


/* Something the agent believes is here like the description, not itself:
 * the lowest such referent, or 0. */
@(private = "file")
agency_believed_like :: proc(self: ^Agency, what: ^tri.Node, store: ^Knowledge_Store) -> u32 {
	result: tri.Match_Result

	tc    := world_tri(self.world)
	arena := tri.arena_new()
	found: u32 = 0
	for i: uint = 0; what != nil && i < knowledge_store_count(store) && found == 0; i += 1 {
		r := knowledge_store_referent_at(store, i)
		if !r.present || r.id == knowledge_store_self_referent(store) do continue
		description := tri.value(tc, ns_utf8(knowledge_store_describe_referent(store, r.id)), arena, nil, 0)
		if description != nil && tri.match(tc, what, description, &result) == .Entailed do found = r.id
	}
	tri.arena_free(arena)
	return found
}


/* A job's task's slots, bound to what the agent believes is like the job's
 * `what` and `within`, in the order the task's goal finds them; their
 * count, or -1 if it knows of nothing like one of them. */
@(private = "file")
agency_bind_job :: proc(self: ^Agency, job: ^tri.Node, params: [^]Slot_Binding, store: ^Knowledge_Store) -> i32 {
	task:  [64]u8
	slots: [2][32]u8

	tc := world_tri(self.world)
	count: i32 = 0
	if !text_at(tc, job, "task", task[:]) do return 0
	n := texts_at(tc, tri.pattern(tc, cstr(task[:])), "done.find", raw_data(slots[:]), 2)
	for q: uint = 0; q < n; q += 1 {
		params[count].slot     = world_intern(self.world, cstr(slots[q][:]))
		params[count].referent = agency_believed_like(self, tri.at(tc, job, "within" if q != 0 else "what"), store)
		if params[count].referent == 0 do return -1
		count += 1
	}
	return count
}


/* Hiring the asker for the job (AGENCY.md decision 15): it is bound to the
 * agent, and the agent undertakes to pay it as the shift ends, if the job is
 * done, a promise. What it says: the job ("" if it can't hire). */
@(private = "file")
agency_hire :: proc(self: ^Agency, m: ^Motivation, worker: u32, name: cstring, wage: u32, store: ^Knowledge_Store) -> string {
	printed: [2048]u8

	tc    := world_tri(self.world)
	job   := tri.pattern(tc, name)
	now   := world_time(self.world).ms
	shift := int_at(tc, job, "shift", 3600000)
	if !agency_act(self, m, "hiring", store, "hire", worker, 0, 0, nil) do return ""
	if agency_undertake_goal_from_until_source(self, m.agent, "pay_wage", now + shift - shift / BG_LOAN_DUE, now + shift,
	                                           "promise") {
		c                   := &m.commitments[m.ncommitments - 1]
		c.params[0].slot     = world_intern(self.world, "wage")
		c.params[0].referent = wage
		c.params[1].slot     = world_intern(self.world, "worker")
		c.params[1].referent = worker
		n                   := agency_bind_job(self, job, raw_data(c.params[2:]), store)
		c.nparams            = 2 + (n if n > 0 else 0)
	}
	tri.print(tc, job, raw_data(printed[:]), size_of(printed))
	return strings.clone(str(printed[:]), context.temp_allocator)
}


/* Hired (`answer` a #Job), the agent undertakes the job's task, for the
 * shift, an employment; and holds the pay the employer said as a promise:
 * in its hand by the shift's end. */
@(private = "file")
agency_take_job_in :: proc(self: ^Agency, m: ^Motivation, answer: cstring, employer: u32, store: ^Knowledge_Store) {
	params: [BG_MAX_SLOTS]Slot_Binding
	task:   [64]u8
	pay:    [1024]u8

	tc    := world_tri(self.world)
	arena := tri.arena_new()
	job   := tri.value(tc, answer, arena, nil, 0) if answer != nil else nil
	if job == nil || tri.subtype(tc, tri.node_type(job), tri.type_named(tc, "#Job")) == 0 ||
	   !text_at(tc, job, "task", task[:]) || tri.at(tc, job, "pay") == nil {
		tri.arena_free(arena)
		return
	}
	now   := world_time(self.world).ms
	shift := int_at(tc, job, "shift", 3600000)
	n     := agency_bind_job(self, job, raw_data(params[:]), store)
	if n < 0 {
		agency_note(self, m, fmt.tprintf("hired by R%d: %s, but it can't tell what of", employer, str(task[:])))
	} else if agency_undertake_goal_from_until_source(self, m.agent, cstr(task[:]), now, now + shift, "employment") {
		c        := &m.commitments[m.ncommitments - 1]
		c.params  = params
		c.nparams = n
		agency_note(self, m, fmt.tprintf("hired by R%d: %s, by %dms", employer, str(task[:]), now + shift))
	}
	tri.print(tc, tri.at(tc, job, "pay"), raw_data(pay[:]), size_of(pay))
	tri.arena_free(arena)
	pledge := fmt.tprintf("#IsHeld & {{ what: %s, holder: %s, when: %dms, attribution: #Pledged }}", str(pay[:]),
	                      knowledge_store_describe_looks(store, knowledge_store_self_referent(store)), now + shift)
	knowledge_hear(self.knowledge, ns_utf8(pledge), employer, m.agent)
}


/* Each question asked, weighed (AGENCY.md §11): answered, put off while the
 * agent is busy, refused, or, waited on too long, let go. */
@(private = "file")
agency_consider_questions :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store) {
	question: ^tri.Node
	what:     ^tri.Node
	arena:    ^tri.Arena
	answer:   string
	worth:    i32
	given:    u32
	wage:     u32
	job:      ^tri.Node
	request:  bool
	call:     bool
	work:     bool
	printed:  [2048]u8

	tc    := world_tri(self.world)
	agent := (^Agent)(world_record(self.world, world_kind_named(self.world, "Agent"), m.agent))
	busy  := i32(BG_BUSY_COST * knowledge_attention_of(self.knowledge, m.agent))
	for k: i32 = 0; k < m.nquestions; {
		q := &m.questions[k]
		if world_time(self.world).ms - q.heard > BG_REPLY_WAIT {
			agency_note(self, m, fmt.tprintf("asked by R%d: it has waited too long; let go", q.asker))
			agency_drop_question(self, m, k)
			continue
		}
		arena    = tri.arena_new()
		question = tri.value(tc, q.content, arena, nil, 0)
		/* a sale asked (content/market/): a deal on the spot, at its stall */
		if question != nil && tri.type_named(tc, "#Buy") != 0 && tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#Buy")) != 0 {
			answer = agency_sell(self, m, question, q.asker, store)
			tri.arena_free(arena)
			agency_act(self, m, "answering", store, "say", q.asker, 0, 0, ns_utf8(answer))
			agency_drop_question(self, m, k)
			continue
		}
		/* a negotiation (NEGOTIATION.md): an ask or an offer answered, as it is
		 * worth answering at all; an agreement, a refusal, a debt repaid */
		{
			w := knowledge_store_trust_in(store, q.asker) + (i32(agent.helpful) if agent != nil else 0) - busy -
			     (BG_COMMITTED if m.nintentions != 0 else 0)
			if h := agency_deal_heard(self, m, q, question, store, w, busy); h != .Not_Mine {
				tri.arena_free(arena)
				if h == .Later {
					if !q.deferred do agency_note(self, m, fmt.tprintf("asked by R%d: worth %+d, busy: not now", q.asker, w))
					q.deferred = true
					k += 1
					continue
				}
				agency_drop_question(self, m, k)
				continue
			}
		}
		request  = question != nil && tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#Request")) != 0
		call     = question != nil && tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#Call")) != 0
		given    = agency_held_like(self, tri.at(tc, question, "what"), store) if request else 0
		/* asked for work (AGENCY.md decision 15): the job it offers, if any,
		 * and the pay for it in hand; worth what having it done is, less the
		 * pay's worth to it */
		work     = question != nil && tri.subtype(tc, tri.node_type(question), tri.type_named(tc, "#AskWork")) != 0
		job      = tri.pattern(tc, agent.hires) if work && agent != nil && agent.hires != nil else nil
		wage     = agency_held_like(self, tri.at(tc, job, "pay"), store) if job != nil else 0
		tri.arena_free(arena)
		worth = knowledge_store_trust_in(store, q.asker) + (i32(agent.helpful) if agent != nil else 0) - busy -
		        (BG_COMMITTED if m.nintentions != 0 else 0) - (agency_lending(self, given, q.asker, store) if given != 0 else 0) +
		        (i32(int_at(tc, job, "gain", 0)) - agency_worth(self, wage, store) if wage != 0 else 0)
		if call {
			/* a soft interruption: worth putting down what it is doing, if more
			 * than the interruption costs */
			worth = knowledge_store_trust_in(store, q.asker) + (i32(agent.helpful) if agent != nil else 0) -
			        (BG_COMMITTED if m.nintentions != 0 else 0)
			if agency_busy(self, m.agent) && worth > BG_INTERRUPT {
				agency_put_down(self, m, fmt.tprintf("called by R%d: worth %+d", q.asker, worth))
			} else if agency_busy(self, m.agent) {
				agency_note(self, m, fmt.tprintf("called by R%d: worth %+d, not now", q.asker, worth))
				agency_drop_question(self, m, k)
				continue
			}
			agency_act(self, m, "answering", store, "say", q.asker, 0, 0,
			           ns_utf8(fmt.tprintf("#Here & {{ what: %s }}",
			                               knowledge_store_describe_looks(store, knowledge_store_self_referent(store)))))
			agency_drop_question(self, m, k)
			continue
		}
		if worth <= 0 && worth + busy > 0 {
			if !q.deferred do agency_note(self, m, fmt.tprintf("asked by R%d: worth %+d, busy: not now", q.asker, worth))
			q.deferred = true
			k += 1
			continue
		}
		arena    = tri.arena_new()
		question = tri.value(tc, q.content, arena, nil, 0)
		answer   = ""
		if question != nil && request {
			/* comply or refuse: give what it holds like it */
			what       = tri.at(tc, question, "what")
			printed[0] = 0
			if what != nil do tri.print(tc, what, raw_data(printed[:]), size_of(printed))
			if given == 0 {
				agency_note(self, m, fmt.tprintf("asked by R%d for something it hasn't", q.asker))
				answer = fmt.tprintf("#HaveNone & {{ what: %s }}", str(printed[:]) if printed[0] != 0 else "#Body")
				worth  = 1
			} else if worth > 0 {
				agency_note(self, m, fmt.tprintf("asked by R%d for R%d, worth %d to it: lending it costs %d",
				                                 q.asker, given, agency_worth(self, given, store),
				                                 agency_lending(self, given, q.asker, store)))
				agency_note(self, m, fmt.tprintf("asked by R%d: worth %+d, granting", q.asker, worth))
				/* on terms (AGENCY.md decision 18): to a friend, none said, the
				 * default between them; to anyone else, a day */
				if agency_act(self, m, "granting", store, "give", given, q.asker, 0, nil) {
					if knowledge_store_loyalty_to(store, q.asker) > 0 {
						answer = fmt.tprintf("#Granted & {{ what: %s }}", knowledge_store_describe_looks(store, given))
					} else {
						answer = fmt.tprintf("#Granted & {{ what: %s, owedIn: %dms }}",
						                     knowledge_store_describe_looks(store, given), BG_LOAN_SHORT)
					}
				}
			} else {
				agency_note(self, m, fmt.tprintf("asked by R%d for R%d, worth %d to it: lending it costs %d",
				                                 q.asker, given, agency_worth(self, given, store),
				                                 agency_lending(self, given, q.asker, store)))
				agency_note(self, m, fmt.tprintf("asked by R%d: worth %+d, refusing", q.asker, worth))
				answer = fmt.tprintf("#WontSay & {{ what: %s }}", str(printed[:]) if printed[0] != 0 else "#Body")
			}
		} else if question != nil && work {
			what       = tri.at(tc, question, "what")
			printed[0] = 0
			if what != nil do tri.print(tc, what, raw_data(printed[:]), size_of(printed))
			if wage == 0 {
				agency_note(self, m, fmt.tprintf("asked by R%d for work it hasn't", q.asker))
				answer = fmt.tprintf("#HaveNone & {{ what: %s }}", str(printed[:]) if printed[0] != 0 else "#Body")
				worth  = 1
			} else if worth > 0 {
				agency_note(self, m, fmt.tprintf("asked by R%d for work: worth %+d, hiring", q.asker, worth))
				answer = agency_hire(self, m, q.asker, agent.hires, wage, store)
			} else {
				agency_note(self, m, fmt.tprintf("asked by R%d for work: worth %+d, refusing", q.asker, worth))
				answer = fmt.tprintf("#WontSay & {{ what: %s }}", str(printed[:]) if printed[0] != 0 else "#Body")
			}
		} else if question != nil && worth > 0 {
			agency_note(self, m, fmt.tprintf("asked by R%d: worth %+d, answering", q.asker, worth))
			answer = agency_lie_to(self, m, question, store)
			if answer == "" do answer = agency_answer_to(self, question, store)
		} else if question != nil {
			agency_note(self, m, fmt.tprintf("asked by R%d: worth %+d, refusing", q.asker, worth))
			what       = tri.at(tc, question, "what")
			printed[0] = 0
			if what != nil do tri.print(tc, what, raw_data(printed[:]), size_of(printed))
			answer = fmt.tprintf("#WontSay & {{ what: %s }}", str(printed[:]) if printed[0] != 0 else "#Body")
		}
		tri.arena_free(arena)
		if answer != "" {
			agency_act(self, m, "answering" if worth > 0 else "refusing", store, "say", q.asker, 0, 0, ns_utf8(answer))
		}
		agency_drop_question(self, m, k)
	}
}


/* Granted what it asked for (`answer` a #Granted), the agent owes it back
 * (AGENCY.md §7, a debt): a commitment to repay the lender what it now
 * holds like it, on the loan's last day; and it promises so. */
@(private = "file")
agency_owe :: proc(self: ^Agency, m: ^Motivation, answer: cstring, lender: u32, store: ^Knowledge_Store) {
	tc      := world_tri(self.world)
	arena   := tri.arena_new()
	granted := tri.value(tc, answer, arena, nil, 0) if answer != nil else nil
	loan: u32 = 0
	/* the terms said; none, the default between them (AGENCY.md decision 18) */
	term := BG_LOAN_TERM if knowledge_store_loyalty_to(store, lender) > 0 else BG_LOAN_SHORT
	if granted != nil && tri.subtype(tc, tri.node_type(granted), tri.type_named(tc, "#Granted")) != 0 {
		loan = agency_held_like(self, tri.at(tc, granted, "what"), store)
		if tri.at(tc, granted, "owedIn") != nil do term = int_at(tc, granted, "owedIn", term)
	}
	tri.arena_free(arena)
	if loan == 0 do return
	now     := world_time(self.world).ms
	promise := knowledge_store_promise_that_is_held_by(store, loan, lender, now + term)
	if !agency_undertake_goal_from_until_source(self, m.agent, "repay", now + term - term / BG_LOAN_DUE, now + term, "debt") {
		return
	}
	/* and says so, a promise the lender holds as a claim (§7) */
	if promise != "" do agency_act(self, m, "promising", store, "say", lender, 0, 0, ns_utf8(promise))
	c                   := &m.commitments[m.ncommitments - 1]
	c.params[0].slot     = world_intern(self.world, "loan")
	c.params[0].referent = loan
	c.params[1].slot     = world_intern(self.world, "lender")
	c.params[1].referent = lender
	c.nparams            = 2
	agency_note(self, m, fmt.tprintf("owes R%d R%d back by %dms", lender, loan, now + term))
}


/* true while the agent waits for an answer: none yet from the one it asked,
 * and the while not over. */
@(private = "file")
agency_awaits :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store) -> bool {
	if m.awaiting == 0 do return false
	for i := knowledge_store_observation_count(store); i > 0; i -= 1 {
		o := knowledge_store_observation_at(store, i - 1)
		/* said at the asking or before: not an answer (saying takes time) */
		if o.time <= m.awaitSince do break
		if string(o.kind) == "said" && o.actor == m.awaiting && o.other == knowledge_store_self_referent(store) {
			agency_note(self, m, fmt.tprintf("R%d answered: %s", m.awaiting, agency_kind_of_content(self, o.content)))
			from := m.awaiting
			m.awaiting = 0
			/* a negotiation goes on: offered again, it waits again */
			if agency_deal_answer(self, m, o.content, from, store) do return m.awaiting != 0
			m.awaiting = from
			agency_owe(self, m, o.content, m.awaiting, store)
			agency_take_job_in(self, m, o.content, m.awaiting, store)
			agency_settle_purchase(self, m, o.content, m.awaiting, store)
			m.awaiting = 0
			return false
		}
	}
	if world_time(self.world).ms < m.awaitUntil do return true
	agency_note(self, m, fmt.tprintf("R%d did not answer", m.awaiting))
	agency_deal_unanswered(self, m, m.awaiting)
	m.awaiting = 0
	return false
}


/* --- weighing goals (AGENCY.md §3) --------------------------------------------------- */

/* How strongly the agent believes something like the consideration's
 * suspect is in the place: the credence of what it was told, the strongest
 * claim, with its findings of the evidence about the place as a group of
 * their own. */
@(private = "file")
agency_suspicion :: proc(self: ^Agency, consideration: ^tri.Node, place: u32, store: ^Knowledge_Store) -> i32 {
	text: [64]u8

	tc      := world_tri(self.world)
	suspect := tri.at(tc, consideration, "suspect")
	best    := i32(BG_PRIOR)
	arena   := tri.arena_new()
	for i: uint = 0; suspect != nil && i < knowledge_store_testimony_count(store); i += 1 {
		t := knowledge_store_testimony_at(store, i)
		r := knowledge_store_referent(store, t.thing)
		if t.container != place || t.settled < 0 || r == nil || r.kind == nil do continue
		kind := tri.value(tc, r.kind, arena, nil, 0)
		if kind == nil || tri.subtype(tc, tri.node_type(kind), tri.node_type(suspect)) == 0 do continue
		credence := knowledge_store_credence_that(store, t.thing, place)
		if credence > best do best = credence
	}
	tri.arena_free(arena)
	evidence: i32 = 0
	if text_at(tc, consideration, "evidence", text[:]) {
		for i: uint = 0; i < knowledge_store_finding_count(store); i += 1 {
			f := knowledge_store_finding_at(store, i)
			if f.about == place && string(f.kind) == str(text[:]) && f.credence > evidence do evidence = f.credence
		}
	}
	return best + evidence
}


/* Whether the referent is believed of the kind (any, without one). */
@(private = "file")
agency_referent_is_of :: proc(self: ^Agency, r: ^Referent, kind: ^tri.Node) -> bool {
	if kind == nil do return true
	if r == nil || r.kind == nil do return false
	t := agency_kind_type(self, r.kind)
	return t != 0 && tri.subtype(world_tri(self.world), t, tri.node_type(kind)) != 0
}


/* Whether the agent believes someone, not itself, is where they could see
 * the referent. */
@(private = "file")
agency_watched :: proc(self: ^Agency, referent: u32, store: ^Knowledge_Store) -> bool {
	r := knowledge_store_referent(store, referent)
	for i: uint = 0; r != nil && i < knowledge_store_count(store); i += 1 {
		o := knowledge_store_referent_at(store, i)
		if o.present && o.id != knowledge_store_self_referent(store) && o.kind != nil && string(o.kind) == "#Agent" &&
		   o.level == r.level && abs(o.x - r.x) <= BG_SIGHT && abs(o.y - r.y) <= BG_SIGHT {
			return true
		}
	}
	return false
}


/* How urgent a commitment is now: its goal's urgency curve over how much
 * of its window has passed (thousandths), or straight up to BG_URGENCY. */
@(private)
agency_urgency_of :: proc(self: ^Agency, c: ^Commitment) -> i32 {
	v: i32

	tc     := world_tri(self.world)
	passed := (world_time(self.world).ms - c.from) * 1000 / (c.until - c.from)
	if curve_at(tc, tri.at(tc, tri.pattern(tc, c.goal), "urgency"), passed, &v) do return v
	/* a kept goal has no deadline to rise to: its duty is the same all through */
	if goal_kept(tc, c.goal) do return 0
	return i32(BG_URGENCY * (world_time(self.world).ms - c.from) / (c.until - c.from))
}


/* What the goal is worth with these bindings: its considerations, added. */
@(private)
agency_worth_of_goal :: proc(self: ^Agency, goal: cstring, b: [^]Slot_Binding, n: i32, store: ^Knowledge_Store,
                             parts: ^[dynamic]string) -> i32 {
	return agency_sum(self, goal, "worth", b, n, store, parts)
}


/* An instance's considerations at `path` ("worth", "score"), added. */
@(private = "file")
agency_sum :: proc(self: ^Agency, instance: cstring, path: cstring, b: [^]Slot_Binding, n: i32, store: ^Knowledge_Store,
                   parts: ^[dynamic]string) -> i32 {
	trait: i64
	v:     i32
	slot:  [32]u8
	field: [64]u8
	act:   [32]u8

	tc := world_tri(self.world)
	worth: i32 = 0
	for list := tri.at(tc, tri.pattern(tc, instance), path); list != nil; list = tri.at(tc, list, "rest") {
		c := tri.at(tc, list, "first")
		if c == nil do break
		if tri.at(tc, c, "value") != nil {
			v = i32(int_at(tc, c, "value", 0))
			append(parts, fmt.tprintf("%+d", v))
		} else if tri.at(tc, c, "cost") != nil {
			/* in full at the middling tolerance, double at none, nothing at all */
			agent := (^Agent)(world_record(self.world, world_kind_named(self.world, "Agent"), knowledge_store_agent(store)))
			v = -i32(int_at(tc, c, "cost", 0) * (100 - (agent.riskTolerance if agent != nil else 50)) / 50)
			append(parts, fmt.tprintf("risk %+d", v))
		} else if text_at(tc, c, "inside", slot[:]) {
			v = agency_suspicion(self, c, bound(b, n, str(slot[:])), store)
			append(parts, fmt.tprintf("credence %+d", v))
		} else if text_at(tc, c, "pressure", slot[:]) {
			/* what it feels, not what its body is */
			if !curve_at(tc, tri.at(tc, c, "curve"), i64(knowledge_store_feels(store, cstr(slot[:]))), &v) {
				v = i32(i64(knowledge_store_feels(store, cstr(slot[:]))) * int_at(tc, c, "per", 0) / 10)
			}
			append(parts, fmt.tprintf("%s %+d", str(slot[:]), v))
		} else if text_at(tc, c, "reserved", slot[:]) {
			/* believed reserved for someone else: what its respect makes of that */
			f := knowledge_store_finding(store, "#Reserved", bound(b, n, str(slot[:]))) if bound(b, n, str(slot[:])) != 0 else nil
			trait = 0
			world_get_field(self.world, "Agent.respectful", knowledge_store_agent(store), &trait)
			v = i32(trait * int_at(tc, c, "per", 0) / 10) if f != nil && f.choice != knowledge_store_self_referent(store) else 0
			append(parts, fmt.tprintf("%s %+d", "reserved" if f != nil else "unreserved", v))
		} else if text_at(tc, c, "trait", slot[:]) {
			/* its own disposition or norm, which it knows */
			put(field[:], fmt.tprintf("Agent.%s", str(slot[:])))
			trait = 0
			world_get_field(self.world, cstr(field[:]), knowledge_store_agent(store), &trait)
			if !curve_at(tc, tri.at(tc, c, "curve"), trait, &v) do v = i32(trait * int_at(tc, c, "per", 0) / 10)
			append(parts, fmt.tprintf("%s %+d", str(slot[:]), v))
		} else if text_at(tc, c, "loyal", slot[:]) {
			/* its loyalty to the slot's referent, or to whom it believes owns
			 * it (AGENCY.md §12) */
			who   := bound(b, n, str(slot[:]))
			owned := knowledge_store_finding(store, "#Owned", who) if who != 0 else nil
			if owned != nil do who = owned.choice
			if !curve_at(tc, tri.at(tc, c, "curve"), i64(knowledge_store_loyalty_to(store, who)) if who != 0 else 0, &v) {
				v = i32(i64(knowledge_store_loyalty_to(store, who)) * int_at(tc, c, "per", 0) / 10) if who != 0 else 0
			}
			append(parts, fmt.tprintf("loyal %+d", v))
		} else if text_at(tc, c, "exposing", slot[:]) && text_at(tc, c, "act", act[:]) {
			/* what the truth would expose (AGENCY.md decision 11): holding what
			 * it believes another's, the law it knows against taking it */
			thing := bound(b, n, str(slot[:]))
			r     := knowledge_store_referent(store, thing) if thing != 0 else nil
			owned := knowledge_store_finding(store, "#Owned", thing) if thing != 0 else nil
			v = 0
			for k: uint = 0; r != nil && r.form == .Held_By && r.container == knowledge_store_self_referent(store) && owned != nil &&
			                 owned.choice != knowledge_store_self_referent(store) && k < knowledge_store_law_count(store); k += 1 {
				law := knowledge_store_law_at(store, k)
				if string(law.forbids) == str(act[:]) && string(law.wrong) == "\"anothers\"" && law.weighs > v do v = law.weighs
			}
			append(parts, fmt.tprintf("%s %+d", "exposing" if v != 0 else "nothing to hide", v))
		} else if tri.at(tc, c, "outdoors") != nil {
			/* the daylight out of doors, as anyone sees it (light/) */
			lit := daylight(self.world, world_time(self.world).ms)
			if !curve_at(tc, tri.at(tc, c, "curve"), i64(lit), &v) do v = 0
			names := [3]string{"night", "dusk", "day"}
			append(parts, fmt.tprintf("%s %+d", names[clamp(lit, 0, 2)], v))
		} else if keptIn := tri.at(tc, c, "keptIn"); keptIn != nil {
			/* what it believes it has at home (cooking/'s rationing): a curve
			 * over the mass, in grams */
			at := agency_at_home(self, tri.at(tc, c, "stocked"), keptIn, store)
			if at < 0 || !curve_at(tc, tri.at(tc, c, "curve"), at, &v) do v = 0
			append(parts, fmt.tprintf("%dg at home %+d", at, v) if at >= 0 else fmt.tprintf("not knowing what is at home %+d", v))
		} else if text_at(tc, c, "watched", slot[:]) {
			v = -i32(int_at(tc, c, "penalty", 0)) if agency_watched(self, bound(b, n, str(slot[:])), store) else 0
			append(parts, fmt.tprintf("%s %+d", "watched" if v != 0 else "unwatched", v))
		} else if text_at(tc, c, "unlawful", slot[:]) && text_at(tc, c, "act", act[:]) {
			/* a law it knows against the act, on what it believes is another's
			 * (INSTITUTIONS.md decision 5): what the law weighs, if it believes
			 * itself seen; unseen, nothing */
			thing  := bound(b, n, str(slot[:]))
			owned  := knowledge_store_finding(store, "#Owned", thing) if thing != 0 else nil
			known  := false
			weighs: i32 = 0
			for k: uint = 0; owned != nil && owned.choice != knowledge_store_self_referent(store) && k < knowledge_store_law_count(store); k += 1 {
				law := knowledge_store_law_at(store, k)
				if string(law.forbids) != str(act[:]) || string(law.wrong) != "\"anothers\"" do continue
				known  = true
				weighs = law.weighs if law.weighs > weighs else weighs
			}
			v = -weighs if known && agency_watched(self, thing, store) else 0
			append(parts, fmt.tprintf("%s %+d", "lawful" if !known else ("unlawful, watched" if v != 0 else "unlawful, unwatched"),
			                          v))
		} else {
			continue
		}
		/* a veto (AGENCY.md decision 14): counting against it at all, it rules
		 * the option out, whatever else scores */
		if v < 0 {
			veto := tri.at(tc, c, "veto")
			if veto != nil && tri.node_type(veto) == tri.type_named(tc, "true") {
				if len(parts^) != 0 {
					parts^[len(parts^) - 1] = strings.concatenate({parts^[len(parts^) - 1], ", a veto"}, context.temp_allocator)
				}
				v = -BG_VETO
			}
		}
		worth += v
	}
	return worth
}


@(private = "file")
agency_has :: proc(self: ^Agency, list: [^]Arisen, n: i32, goal: cstring, about: u32, verdict: ^i32) -> bool {
	for k: i32 = 0; k < n; k += 1 {
		if list[k].goal == goal && list[k].about == about {
			if verdict != nil do verdict^ = list[k].verdict
			return true
		}
	}
	return false
}


/* Whether a goal is kept (content/agency.tri): an ongoing condition. */
goal_kept :: proc(tc: ^tri.Content, goal: cstring) -> bool {
	kept := tri.at(tc, tri.pattern(tc, goal), "kept") if goal != nil else nil
	return kept != nil && tri.node_type(kept) == tri.type_named(tc, "true")
}


/* A goal that arose about something, done or dropped, is settled with it. */
@(private = "file")
agency_settle :: proc(self: ^Agency, m: ^Motivation, intention: ^Intention, done := false) {
	k: i32

	/* a kept goal is still to keep while the window is open: done, until it
	 * no longer holds; impossible for now, tried again a while later */
	if intention.commitment > 0 && intention.commitment <= m.ncommitments {
		c := &m.commitments[intention.commitment - 1]
		if !goal_kept(world_tri(self.world), intention.goal) {
			c.settled = true
		} else if !done {
			c.resume = world_time(self.world).ms + int_at(world_tri(self.world), tri.pattern(world_tri(self.world), intention.goal),
			                                              "retry", BG_KEPT_RETRY)
		} else {
			/* done lately (#Did's `lately`): due again once it no longer is */
			tc   := world_tri(self.world)
			cond := tri.at(tc, tri.pattern(tc, intention.goal), "done")
			text: [64]u8
			if lately := int_at(tc, cond, "lately", 0); lately > 0 && text_at(tc, cond, "did", text[:]) {
				a := agency_activity(self, cstr(text[:]), m.agent, "completed", intention.adopted)
				if record := (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), a)); record != nil {
					c.resume = record.started + lately + 1
				}
			}
		}
	}
	if intention.pressed != 0 {
		need: [32]u8

		if !text_at(world_tri(self.world), tri.pattern(world_tri(self.world), intention.goal), "pressed.need", need[:]) do return
		for k = 0; k < m.nsettled && !(m.settled[k].goal == intention.goal && m.settled[k].about == 0); k += 1 {}
		if k == m.nsettled && m.nsettled < BG_MAX_SETTLED do m.nsettled += 1
		if k < m.nsettled {
			m.settled[k].goal    = intention.goal
			m.settled[k].about   = 0
			m.settled[k].verdict = knowledge_store_feels(knowledge_store_of(self.knowledge, m.agent), cstr(need[:]))
			/* impossible for now: tried again a while later, as a kept goal is
			 * (what was in the way may not be: a meal in hand since), when it
			 * next decides */
			m.settled[k].retry   = 0 if done else world_time(self.world).ms + BG_NEED_RETRY
			m.settled[k].held    = agency_held_signature(knowledge_store_of(self.knowledge, m.agent))
		}
		return
	}
	if intention.arose == 0 do return
	/* settled again (it arose again, from a finding drawn since): as of now */
	for k = 0; k < m.nsettled; k += 1 {
		if m.settled[k].goal == intention.goal && m.settled[k].about == intention.arose {
			m.settled[k].verdict = i32(world_time(self.world).ms / 1000)
			return
		}
	}
	if m.nsettled == BG_MAX_SETTLED do return
	m.settled[m.nsettled].goal    = intention.goal
	m.settled[m.nsettled].about   = intention.arose
	m.settled[m.nsettled].verdict = i32(world_time(self.world).ms / 1000)
	m.nsettled += 1
}


/* The goals that arise from the agent's findings, weighed against what it is
 * doing: the best, if it beats the current intention by the margin, and the
 * interruption while an activity runs, wins; what the agent was doing is
 * suspended, and stays beneath. true when it switched. */
@(private = "file")
agency_weigh :: proc(self: ^Agency, m: ^Motivation, store: ^Knowledge_Store, busy: bool) -> bool {
	current:        ^Intention
	b:              Slot_Binding
	parts:          [dynamic]string
	bestParts:      [dynamic]string
	currentParts:   [dynamic]string
	nmine:          uint
	goal:           cstring
	best:           cstring
	bestAbout:      u32
	worth:          i32
	bestWorth:      i32
	against:        i32
	k:              i32
	verdict:        i32
	last:           i32
	finding:        [64]u8
	slot:           [32]u8
	title:          [64]u8
	currentTitle:   [64]u8
	bestSlot:       cstring
	bestCommitment: i32
	bestPressed:    bool

	tc       := world_tri(self.world)
	family   := tri.family_index(tc, "goals")
	best      = nil
	bestAbout = 0
	bestWorth = 0
	bestParts = nil
	bestSlot  = nil
	for i: uint = 0; family != nil && i < uint(tri.index_count(family)); i += 1 {
		goal = world_intern(self.world, cstring(tri.index_tag(family, i)))
		pattern := tri.pattern(tc, goal)
		held    := tri.at(tc, pattern, "arises.held")
		byHeld  := held != nil && tri.node_type(held) == tri.type_named(tc, "true")
		if (!byHeld && !text_at(tc, pattern, "arises.finding", finding[:])) || !text_at(tc, pattern, "arises.slot", slot[:]) {
			continue
		}
		/* an office's duty: only for one who holds it, which it knows */
		if text_at(tc, pattern, "arises.duty", title[:]) {
			badge := world_text_field(self.world, "OfficeHolder.badge", m.agent)
			if badge == nil || string(badge) != str(title[:]) do continue
		}
		/* and not for one who does: its office has a goal of its own */
		if text_at(tc, pattern, "arises.exempt", title[:]) {
			badge := world_text_field(self.world, "OfficeHolder.badge", m.agent)
			if badge != nil && string(badge) == str(title[:]) do continue
		}
		/* what it arises about: what findings of its kind are about, or
		 * (`held`) what the agent believes it holds */
		abouts := make([dynamic]u32, context.temp_allocator)
		if byHeld {
			me := knowledge_store_self_referent(store)
			for j: uint = 0; j < knowledge_store_count(store); j += 1 {
				r := knowledge_store_referent_at(store, j)
				if r.present && r.form == .Held_By && r.container == me do append(&abouts, r.id)
			}
		} else {
			for j: uint = 0; j < knowledge_store_finding_count(store); j += 1 {
				when_: i32

				/* settled about it, unless the finding was drawn again since (a
				 * part serviced, seen wearing again) */
				f := knowledge_store_finding_at(store, j)
				if string(f.kind) != str(finding[:]) ||
				   (agency_has(self, raw_data(m.settled[:]), m.nsettled, goal, f.about, &when_) && f.time / 1000 <= i64(when_)) {
					continue
				}
				if tri.at(tc, pattern, "arises.lapse") != nil &&
				   world_time(self.world).ms - f.time > int_at(tc, pattern, "arises.lapse", 0) {
					continue      /* no longer salient */
				}
				append(&abouts, f.about)
			}
		}
		for about in abouts {
			if !agency_referent_is_of(self, knowledge_store_referent(store, about), tri.at(tc, pattern, "arises.of")) {
				continue
			}
			for k = 0; k < m.nintentions; k += 1 {
				if m.intentions[k].goal == goal && m.intentions[k].arose == about do break
			}
			if k < m.nintentions do continue      /* already pursued */
			b.slot     = world_intern(self.world, cstr(slot[:]))
			b.referent = about
			parts      = make([dynamic]string, context.temp_allocator)
			worth      = agency_worth_of_goal(self, goal, &b, 1, store, &parts)
			if best == nil || worth > bestWorth {
				best        = goal
				bestAbout   = about
				bestWorth   = worth
				bestParts   = parts
				bestSlot    = b.slot
				bestPressed = false
			}
		}
	}
	/* the routine: commitments whose window is open */
	bestCommitment = -1
	for k = 0; k < m.ncommitments; k += 1 {
		j2: i32

		c := &m.commitments[k]
		if c.settled || world_time(self.world).ms < c.from || world_time(self.world).ms >= c.until do continue
		if world_time(self.world).ms < c.resume do continue      /* impossible a while ago: not yet */
		for j2 = 0; j2 < m.nintentions && m.intentions[j2].commitment != k + 1; j2 += 1 {}
		if j2 < m.nintentions do continue      /* under way already */
		/* a kept goal that holds: nothing to do for it, for now */
		if goal_kept(world_tri(self.world), c.goal) {
			kb: [BG_MAX_SLOTS]Slot_Binding
			kn := c.nparams
			copy(kb[:kn], c.params[:kn])
			if agency_holds(self, c.goal, "done", 0, raw_data(kb[:]), &kn, store) do continue
		}
		worth = BG_DUTY + agency_urgency_of(self, c)
		if best == nil || worth > bestWorth {
			best           = c.goal
			bestAbout      = 0
			bestWorth      = worth
			bestParts      = make([dynamic]string, context.temp_allocator)
			append(&bestParts, fmt.tprintf("%s, duty %+d", c.source, BG_DUTY), fmt.tprintf("urgency %+d", worth - BG_DUTY))
			bestSlot       = nil
			bestCommitment = k
			bestPressed    = false
		}
	}
	/* needs: goals pressed by what the agent feels */
	bestPressed = false
	for i: uint = 0; family != nil && i < uint(tri.index_count(family)); i += 1 {
		was: i32

		goal = world_intern(self.world, cstring(tri.index_tag(family, i)))
		if !text_at(tc, tri.pattern(tc, goal), "pressed.need", finding[:]) do continue
		felt := knowledge_store_feels(store, cstr(finding[:]))
		if i64(felt) <= int_at(tc, tri.pattern(tc, goal), "pressed.above", 100) do continue
		for k = 0; k < m.nsettled && !(m.settled[k].goal == goal && m.settled[k].about == 0); k += 1 {}
		if k < m.nsettled {
			was = m.settled[k].verdict
			if m.settled[k].retry != 0 && (world_time(self.world).ms >= m.settled[k].retry ||
			                               agency_held_signature(store) != m.settled[k].held) {
				m.settled[k].retry = 0      /* impossible a while ago, or before it held what it holds: weighed again */
			} else if felt < was {
				/* eased since (met some other way: supper): settled as of now */
				m.settled[k].verdict = felt
				continue
			} else if felt < was + 20 {
				continue      /* settled, until it is felt more */
			}
		}
		for k = 0; k < m.nintentions && m.intentions[k].goal != goal; k += 1 {}
		if k < m.nintentions do continue
		parts = make([dynamic]string, context.temp_allocator)
		worth = agency_worth_of_goal(self, goal, nil, 0, store, &parts)
		if best == nil || worth > bestWorth {
			best           = goal
			bestAbout      = 0
			bestWorth      = worth
			bestParts      = parts
			bestSlot       = nil
			bestCommitment = -1
			bestPressed    = true
		}
	}
	if best == nil do return false

	/* against what it is doing: the topmost intention that has a worth, or keeps a commitment */
	current      = nil
	against      = 0
	currentParts = make([dynamic]string, context.temp_allocator)
	for k = m.nintentions - 1; k >= 0 && current == nil; k -= 1 {
		if tri.at(tc, tri.pattern(tc, m.intentions[k].goal), "worth.first") != nil || m.intentions[k].commitment != 0 {
			current = &m.intentions[k]
			against = agency_worth_of_goal(self, current.goal, raw_data(current.params[:]), current.nparams, store,
			                               &currentParts)
			if current.commitment > 0 && current.commitment <= m.ncommitments {
				c       := &m.commitments[current.commitment - 1]
				urgency := agency_urgency_of(self, c)
				against += BG_DUTY + urgency
				append(&currentParts, fmt.tprintf("%s, duty %+d", c.source, BG_DUTY))
				append(&currentParts, fmt.tprintf("urgency %+d", urgency))
			}
		}
	}
	if m.nintentions != 0 do against += BG_MARGIN
	if busy do against += BG_INTERRUPT
	verdict = 1 if bestWorth > against else 0
	if m.autopilot && !(m.routine && bestCommitment >= 0) {
		/* the player's character takes up nothing of its own, but its routine
		 * if it is to carry on with that: past the player's threshold, the
		 * player decides */
		if bestWorth > m.threshold && !m.handedBack {
			goal_title(tc, best, title[:])
			agency_hand_back(self, m, fmt.tprintf("%s (R%d) is worth %+d, more than your %+d", str(title[:]), bestAbout,
			                                      bestWorth, m.threshold))
			return true
		}
		return false
	}

	/* logged when the verdict changes */
	last = -1
	if !agency_has(self, raw_data(m.weighed[:]), m.nweighed, best, bestAbout, &last) && m.nweighed < BG_MAX_SETTLED {
		m.weighed[m.nweighed].goal  = best
		m.weighed[m.nweighed].about = bestAbout
		m.nweighed += 1
	}
	for k = 0; k < m.nweighed; k += 1 {
		if m.weighed[k].goal == best && m.weighed[k].about == bestAbout do m.weighed[k].verdict = verdict
	}
	if verdict != last {
		goal_title(tc, best, title[:])
		if current != nil do goal_title(tc, current.goal, currentTitle[:])
		currentWorth := ""
		if current != nil {
			currentWorth = fmt.tprintf(" %+d (%s)", against - (BG_MARGIN if m.nintentions != 0 else 0) - (BG_INTERRUPT if busy else 0),
			                           strings.join(currentParts[:], ", ", context.temp_allocator))
		}
		agency_note(self, m, fmt.tprintf("weighing %s%s: %+d (%s) against %s%s%s%s: %s", str(title[:]),
		                                 fmt.tprintf(" (R%d)", bestAbout) if bestAbout != 0 else "",
		                                 bestWorth, strings.join(bestParts[:], ", ", context.temp_allocator),
		                                 str(currentTitle[:]) if current != nil else "nothing",
		                                 currentWorth,
		                                 fmt.tprintf(" + margin %d", BG_MARGIN) if m.nintentions != 0 else "",
		                                 fmt.tprintf(" + interruption %d", BG_INTERRUPT) if busy else "",
		                                 "switching" if verdict != 0 else "staying"))
	}
	if verdict == 0 || m.nintentions == BG_MAX_INTENTIONS do return false

	/* what it was doing, suspended */
	mine := world_copy_activities_of(self.world, m.agent, &nmine)
	for i: uint = 0; busy && self.activities != nil && i < nmine; i += 1 {
		record := (^Activity)(world_record(self.world, world_kind_named(self.world, "Activity"), mine[i]))
		if record == nil || record.status != u32(tri.type_named(tc, "\"running\"")) do continue
		error: string
		if agency_put_aside(self, mine[i], "something else matters more", &error) != nil {
			agency_note(self, m, fmt.tprintf("suspending %s", world_text_field(self.world, "Activity.operation", mine[i])))
		}
	}
	free(mine)
	b.slot     = bestSlot
	b.referent = bestAbout
	if bestCommitment >= 0 {
		agency_adopt(self, best, m, raw_data(m.commitments[bestCommitment].params[:]), m.commitments[bestCommitment].nparams)
	} else {
		agency_adopt(self, best, m, &b, 1 if bestSlot != nil else 0)
	}
	m.intentions[m.nintentions - 1].arose      = bestAbout
	m.intentions[m.nintentions - 1].commitment = bestCommitment + 1
	m.intentions[m.nintentions - 1].pressed    = 1 if bestPressed else 0
	m.waiting = false     /* a new goal: whatever it waited on news for is behind it */
	return true
}


/* One decision, for the current intention. true when it acted or settled into
 * waiting; false when it only changed its intentions, so it decides again. */
agency_decisions :: proc(self: ^Agency) -> u64 {
	return self.decisions
}


@(private = "file")
agency_decide :: proc(self: ^Agency, m: ^Motivation) -> bool {
	b:             [BG_MAX_SLOTS]Slot_Binding
	methods:       [BG_MAX_METHODS]cstring
	title:         [64]u8
	method:        [64]u8
	chosenB:       [BG_MAX_SLOTS]Slot_Binding
	score:         i32
	best:          i32
	chosen:        i32
	unknownMethod: i32
	unknownN:      i32
	unknownB:      [BG_MAX_SLOTS]Slot_Binding
	unknownPath:   [128]u8
	subgoal:       [64]u8
	chosenN:       i32
	n:             i32

	self.decisions += 1

	store        := knowledge_store_of(self.knowledge, m.agent)
	me           := knowledge_store_referent(store, knowledge_store_self_referent(store))
	self.deciding = m
	if m.wake != 0 && m.wake <= world_time(self.world).ms do m.wake = 0
	if me == nil || m.handedBack do return true
	agency_hear_questions(self, m, store)
	agency_consider_questions(self, m, store)
	agency_deals_tick(self, m, store)
	if agency_awaits(self, m, store) do return true     /* waiting for an answer */
	/* a commitment whose window has closed is over */
	for k := m.nintentions - 1; k >= 0; k -= 1 {
		it := &m.intentions[k]
		if it.commitment > 0 && it.commitment <= m.ncommitments &&
		   world_time(self.world).ms >= m.commitments[it.commitment - 1].until {
			agency_note(self, m, fmt.tprintf("%s is over: its window has closed%s",
			                                 goal_title(world_tri(self.world), it.goal, title[:]),
			                                 "; the promise is broken" if string(m.commitments[it.commitment - 1].source) == "promise" else ""))
			m.commitments[it.commitment - 1].settled = true
			agency_give_up_window(self, m, &m.commitments[it.commitment - 1])
			m.nintentions = k      /* it, and what it needed */
			m.waiting     = false
		}
	}
	agency_renew_commitments(self, m)
	busy := agency_busy(self, m.agent)
	if agency_weigh(self, m, store, busy) do return false      /* something else won: decide again, for it */
	/* on a walk: given up if it no longer makes sense, and decided afresh
	 * once it has stopped (its ending is perceived) */
	if walk := agency_walk_under_way(self, m.agent); walk != NO_ENTITY && self.activities != nil {
		if why := agency_walk_stale(self, m, store, me, walk); why != "" {
			if activities_abort(self.activities, walk, why, nil) != nil {
				agency_note(self, m, fmt.tprintf("giving up the walk: %s", why))
			}
			m.walking = {}
			return true
		}
	} else {
		m.walking = {}
	}
	if m.autopilot && m.nintentions == 0 {
		if m.routine && agency_has_routine(self, m) do return true      /* waiting for its routine */
		if m.explore {
			if busy || agency_explore(self, m, store) do return true   /* under way, or a step taken */
			agency_hand_back(self, m, "there is nothing left to explore")
			return true
		}
		agency_hand_back(self, m, "its routine is done" if m.routine else "there is nothing left to do")
		return true
	}
	if m.nintentions == 0 || busy do return true     /* mid-activity, or nothing to do: no cost */
	if m.waiting && len(knowledge_store_news(store)) == 0 do return true
	m.waiting = false
	m.decisions += 1
	self.deliberations += 1
	top    := &m.intentions[m.nintentions - 1]
	scores := make([dynamic]string, context.temp_allocator)
	best    = 0
	chosenN = 0
	bestRank:  i64
	bestHabit: i32

	/* a goal beneath, achieved meanwhile (METHODS.md decision 5): it is done,
	 * and the subgoals posted for it go with it, outermost first. Only the
	 * subgoals' chain: a goal suspended beneath another that won (its
	 * `pending` -1) isn't what the one above it is for. */
	base := m.nintentions - 1
	for base > 0 && m.intentions[base - 1].pending >= 0 do base -= 1
	for k := base; k < m.nintentions - 1; k += 1 {
		beneath := &m.intentions[k]
		n = beneath.nparams
		copy(b[:n], beneath.params[:n])
		if !agency_holds(self, beneath.goal, "done", beneath.adopted, raw_data(b[:]), &n, store) do continue
		agency_note(self, m, fmt.tprintf("%s is done meanwhile: giving up %s",
		                                 goal_title(world_tri(self.world), beneath.goal, title[:]),
		                                 goal_title(world_tri(self.world), m.intentions[k + 1].goal, method[:])))
		agency_settle(self, m, beneath, done = true)
		m.nintentions = k
		if k != 0 {
			m.intentions[k - 1].pending = -1
			agency_note(self, m, fmt.tprintf("back to it: %s is done", str(title[:])))
		}
		return false
	}

	n = top.nparams
	copy(b[:n], top.params[:n])
	if agency_holds(self, top.goal, "done", top.adopted, raw_data(b[:]), &n, store) {
		agency_note(self, m, "done")
		agency_settle(self, m, top, done = true)
		m.nintentions -= 1
		if m.nintentions != 0 {
			m.intentions[m.nintentions - 1].pending = -1
			agency_note(self, m, fmt.tprintf("back to it: %s is done", goal_title(world_tri(self.world), top.goal, title[:])))
			return false
		}
		return false      /* free now: weigh what has arisen meanwhile */
	}

	/* the method that scores best (AGENCY.md §5), then by rank, that hasn't
	 * failed and whose precondition holds; one that scores below nothing is
	 * unthinkable */
	nmethods     := agency_methods_for_mind(self, top.goal, m, raw_data(methods[:]), BG_MAX_METHODS)
	chosen        = -1
	unknownMethod = -1
	/* searched: looked into since the goal was adopted; a place of its own,
	 * for a commitment, since its window opened (tried again, a kept goal
	 * doesn't look again into the larder it knows too low to sell from;
	 * another's stall, whose board may change, it reads again) */
	/* a subgoal searches as the errand it serves does: what was looked into
	 * (a stall read, a coffer looked in) since the outermost goal of its
	 * chain was adopted is passed over, not looked into again each time the
	 * subgoal is adopted afresh (METHODS.md) */
	searchedSince := m.intentions[base].adopted
	self.ownSearched = agency_since_window(m, searchedSince)
	for i: uint = 0; i < nmethods; i += 1 {
		if (top.failed & (u32(1) << u32(i))) != 0 do continue
		n = top.nparams
		copy(b[:n], top.params[:n])
		self.nunknown    = 0
		self.residual[0] = 0
		if i32(i) == top.following && agency_suspended_step_of(self, methods[i], m) {
			/* back to what it put down: resuming rechecks what it needs */
			chosen  = i32(i)
			chosenN = n
			copy(chosenB[:n], b[:n])
			break
		}
		if !agency_holds(self, methods[i], "pre", searchedSince, raw_data(b[:]), &n, store) {
			/* unknown, not false: a method may find out first (AGENCY.md §5, onUnknown) */
			if self.nunknown != 0 && unknownMethod < 0 &&
			   text_at(world_tri(self.world), tri.pattern(world_tri(self.world), methods[i]), "onUnknown", subgoal[:]) {
				unknownMethod = i32(i)
				unknownN      = self.nunknown
				copy(unknownB[:self.nunknown], self.unknown[:self.nunknown])
				strncpy(unknownPath[:], cstr(self.residual[:]), len(unknownPath) - 1)
			}
			continue
		}
		parts := make([dynamic]string, context.temp_allocator)
		score = agency_sum(self, methods[i], "score", raw_data(b[:]), n, store, &parts)
		habit: i32
		{
			ctx: [128]u8

			put(ctx[:], fmt.tprintf("%s:%s", top.goal, methods[i]))
			habit = habit_strength(m, cstr(ctx[:]), 0, world_time(self.world).ms) / 10
			if habit != 0 do append(&parts, fmt.tprintf("habit %+d", habit))
		}
		if len(parts) != 0 {
			append(&scores, fmt.tprintf("%s %+d (%s)",
			                            str(method[:]) if text_at(world_tri(self.world), tri.pattern(world_tri(self.world), methods[i]), "title",
			                                                      method[:]) else string(methods[i]),
			                            score + habit, strings.join(parts[:], ", ", context.temp_allocator)))
		}
		/* best first, then by rank; habit breaks a tie between ways of the
		 * same rank (AGENCY.md §5: "habitual ways win ties"), and never puts
		 * a later way before an earlier one */
		rank := int_at(world_tri(self.world), tri.pattern(world_tri(self.world), methods[i]), "rank", 0)
		if score < 0 do continue
		if chosen >= 0 && !(score > best || (score == best && rank == bestRank && habit > bestHabit)) do continue
		chosen    = i32(i)
		best      = score
		bestRank  = rank
		bestHabit = habit
		chosenN = n
		copy(chosenB[:n], b[:n])
	}
	self.ownSearched = 0
	/* a better way, unknown, is found out before a worse one is settled for */
	if chosen >= 0 && unknownMethod >= 0 && unknownMethod < chosen do chosen = -1
	if chosen >= 0 {
		if top.following != chosen && len(scores) != 0 {
			agency_note(self, m, fmt.tprintf("scoring %s", strings.join(scores[:], "; ", context.temp_allocator)))
		}
		/* the way last followed failed, and another is taken: counted */
		if top.following >= 0 && top.following != chosen && top.following < i32(nmethods) &&
		   (top.failed & (u32(1) << u32(top.following))) != 0 {
			key := fmt.tprintf("%s: %s → %s", top.goal, methods[top.following], methods[chosen])
			if key in self.fallThroughs {
				self.fallThroughs[key] += 1
			} else {
				self.fallThroughs[strings.clone(key)] = 1
			}
		}
		if top.following != chosen {
			if passed := agency_passed_over(self, raw_data(methods[:]), uint(chosen), top.failed); passed != "" {
				agency_note(self, m, fmt.tprintf("%s no longer holds", passed))
			}
		}
		top.following = chosen
		return agency_follow(self, m, methods[chosen], chosen, raw_data(chosenB[:]), chosenN, store)
	}
	if unknownMethod >= 0 && m.nintentions < BG_MAX_INTENTIONS {
		agency_note(self, m, fmt.tprintf("%s: unknown at %s: %s first",
		                                 str(method[:]) if text_at(world_tri(self.world), tri.pattern(world_tri(self.world), methods[unknownMethod]),
		                                                           "title", method[:]) else string(methods[unknownMethod]),
		                                 str(unknownPath[:]), goal_title(world_tri(self.world), cstr(subgoal[:]), title[:])))
		top.pending   = unknownMethod
		top.following = unknownMethod
		agency_adopt(self, world_intern(self.world, cstr(subgoal[:])), m, raw_data(unknownB[:]), unknownN)
		return false
	}
	if len(scores) != 0 {
		agency_note(self, m, fmt.tprintf("scoring %s: unthinkable", strings.join(scores[:], "; ", context.temp_allocator)))
	}
	/* no way of its own: it may ask someone for what a way wants in hand
	 * (NEGOTIATION.md decision 1) */
	if acted, asking := agency_ask(self, m, top, store, me); asking do return acted

	/* no way left: impossible for now, and the method that needed it has failed */
	agency_note(self, m, "nothing I know of will do: impossible for now")
	agency_settle(self, m, top)
	goal_title(world_tri(self.world), top.goal, title[:])
	m.nintentions -= 1
	if m.nintentions != 0 {
		top = &m.intentions[m.nintentions - 1]
		if top.pending >= 0 {
			agency_methods_for_mind(self, top.goal, m, raw_data(methods[:]), BG_MAX_METHODS)
			if !text_at(world_tri(self.world), tri.pattern(world_tri(self.world), methods[top.pending]), "title", method[:]) {
				put(method[:], string(methods[top.pending]))
			}
			agency_fail(self, m, top.pending, fmt.tprintf("%s has failed: it needed %s", str(method[:]), str(title[:])))
		}
		return false
	}
	m.waiting = true
	return true
}


/* When a mind is next due with nothing happening (REALITY.md decision 7):
 * a wake it set; the answer it waits for late; a commitment's window
 * opening or closing since it last decided. max(i64): not of itself (a
 * need's goal found impossible is weighed again when it next decides, not
 * woken for: asleep, hungry and rationing, it sleeps on). */
@(private = "file")
due_of_ :: proc(m: ^Motivation) -> i64 {
	at := max(i64)
	if m.decidedAt < 0 do return 0
	if m.wake != 0 && m.wake < at do at = m.wake
	if m.awaiting != 0 && m.awaitUntil < at do at = m.awaitUntil
	for k: i32 = 0; k < m.ncommitments; k += 1 {
		if m.commitments[k].from > m.decidedAt && m.commitments[k].from < at do at = m.commitments[k].from
		if m.commitments[k].until > m.decidedAt && m.commitments[k].until < at do at = m.commitments[k].until
		if m.commitments[k].resume > m.decidedAt && m.commitments[k].resume < at do at = m.commitments[k].resume
	}
	return at
}


/* The same, below full detail on the cadence's beat (REALITY.md step 3). */
@(private = "file")
due_on_beat :: proc(world: ^World, m: ^Motivation) -> i64 {
	return reality_beat(world_reality(world), Detail(world_detail_of(world, m.agent)), due_of_(m))
}

/* #define due_of( m)   due_on_beat( _world, (m)) */
@(private = "file")
due_of :: proc(self: ^Agency, m: ^Motivation) -> i64 {
	return due_on_beat(self.world, m)
}


@(private = "file")
mind_due_now :: proc(context_: rawptr, agent: Entity_ID) -> i64 {
	self := (^Agency)(context_)
	m    := agency_existing_mind_of(self, agent)
	if m == nil || world_detail_of(self.world, agent) == i32(Detail.Frozen) do return max(i64)
	return due_on_beat(self.world, m)
}


/* An animal's mind (content/hunting/): made as it first perceives, its
 * instinct (`Agent.instinct`, an #Instinct) undertaken: each goal it keeps
 * over its hours, every day. Each window is undertaken a day early, so the
 * one under way now (a night begun yesterday) is kept, and the rest open
 * as their hours come. nil for an agent with none: a person's days are its
 * commitments. */
@(private = "file")
agency_take_on_instinct :: proc(self: ^Agency, agent: Entity_ID) -> ^Motivation {
	DAY :: i64(86400000)
	goal: [64]u8
	name := world_text_field(self.world, "Agent.instinct", agent)
	if name == nil || len(name) == 0 || !world_is_live(self.world, agent) do return nil
	tc := world_tri(self.world)
	took := false
	for keeps := tri.at(tc, tri.pattern(tc, name), "keeps"); keeps != nil; keeps = tri.at(tc, keeps, "rest") {
		kept := tri.at(tc, keeps, "first")
		if kept == nil || !text_at(tc, kept, "goal", goal[:]) do break
		from  := int_at(tc, kept, "from", 0)
		until := int_at(tc, kept, "until", DAY)
		if !agency_undertake_every_with(self, agent, cstr(goal[:]), from - DAY, until - DAY, "instinct", DAY, {}) do return nil
		took = true
	}
	return agency_existing_mind_of(self, agent) if took else nil
}


/* The mind of an agent, if it has one; none is made, nothing nudged. */
@(private = "file")
agency_existing_mind_of :: proc(self: ^Agency, agent: Entity_ID) -> ^Motivation {
	lo: uint = 0
	hi := uint(len(self.minds))
	for lo < hi {
		i := (lo + hi) / 2
		if self.minds[i].agent < agent {
			lo = i + 1
		} else {
			hi = i
		}
	}
	if lo < uint(len(self.minds)) && self.minds[lo].agent == agent do return self.minds[lo]
	return nil
}


/* Whether a mind decides at this boundary: its agent perceived something,
 * or it is due of itself. */
@(private = "file")
agency_is_due :: proc(self: ^Agency, m: ^Motivation) -> bool {
	if world_detail_of(self.world, m.agent) == i32(Detail.Frozen) {
		return false                         /* frozen: it decides when it rises */
	}
	return knowledge_perceived_now(self.knowledge, m.agent) || due_of(self, m) <= world_time(self.world).ms
}


@(private = "file")
agency_wake_minds :: proc(self: ^Agency) {
	if self.wakes != nil do return
	self.wakes = wakes_new()
	for i := 0; i < len(self.minds); i += 1 {
		wakes_push(self.wakes, self.minds[i].agent, due_of(self, self.minds[i]))
	}
}


agency_decide_boundary :: proc(self: ^Agency, boundary: u64) {
	nperceived: uint
	nwoken:     uint

	/* the dead's minds go with them (VILLAGE.md decision 7) */
	for i := len(self.minds); i > 0; i -= 1 {
		if !world_is_live(self.world, self.minds[i - 1].agent) do agency_retire_mind_at(self, uint(i - 1))
	}
	/* which minds: those whose agents perceived; those due of themselves;
	 * those looked up since the last boundary. Else they rest, unread */
	agency_wake_minds(self)
	perceived := ([^]Entity_ID)(knowledge_agents_perceived_now(self.knowledge, &nperceived))
	woken     := wakes_take(self.wakes, world_time(self.world).ms, mind_due_now, self, &nwoken)
	due       := make([]Entity_ID, nperceived + nwoken + uint(len(self.nudged)) + 1)
	ndue: uint = 0
	if nperceived != 0 do copy(due[ndue:], perceived[:nperceived])
	ndue += nperceived
	copy(due[ndue:], woken[:nwoken])
	ndue += nwoken
	if len(self.nudged) != 0 do copy(due[ndue:], self.nudged[:])
	ndue += uint(len(self.nudged))
	clear(&self.nudged)
	free(woken)
	slice.sort(due[:ndue])

	/* in stable ID order; each reads only its own stores and committed state */
	for i: uint = 0; i < ndue; i += 1 {
		if i != 0 && due[i] == due[i - 1] do continue
		m := agency_existing_mind_of(self, due[i])
		if m == nil do m = agency_take_on_instinct(self, due[i])
		if m == nil do continue
		if agency_is_due(self, m) {
			for k := 0; k < 2 * BG_MAX_INTENTIONS && !agency_decide(self, m); k += 1 {}
			m.decidedAt = world_time(self.world).ms
		}
		wakes_push(self.wakes, m.agent, due_of(self, m))
	}
	delete(due)
	/* minds looked up while deciding (another's deal, a promise made to it)
	 * stay nudged: checked at the next boundary */

	/* the player's: with nothing left to do, or handed back */
	for i := 0; i < len(self.minds); i += 1 {
		m := self.minds[i]
		if m.autopilot && m.nintentions == 0 && !m.handedBack && !(m.routine && agency_has_routine(self, m)) && !m.explore {
			agency_hand_back(self, m, "its routine is done" if m.routine else "there is nothing left to do")
		}
	}
	for i := len(self.minds); i > 0; i -= 1 {
		if self.minds[i - 1].handedBack do agency_retire_mind_at(self, uint(i - 1))
	}
}


agency_next_decision_time :: proc(self: ^Agency) -> Time {
	agency_wake_minds(self)
	next := wakes_next(self.wakes, mind_due_now, self)
	/* a mind looked up since: checked at the next boundary, which comes now */
	if len(self.nudged) != 0 && world_time(self.world).ms < next do next = world_time(self.world).ms
	/* due already, a mind is decided at the next boundary: none sooner */
	if next != max(i64) && next <= world_time(self.world).ms do next = world_time(self.world).ms + 1
	return TIME_NEVER if next == max(i64) else time_make(next)
}


/* --- saves ------------------------------------------------------------------------- */

agency_check_in_all :: proc(self: ^Agency) {
}


agency_saved_state :: proc(self: ^Agency) -> []string {
	lines := make([dynamic]string, context.temp_allocator)
	for i := 0; i < len(self.minds); i += 1 {
		m := self.minds[i]
		append(&lines, fmt.tprintf("decided %d %d", m.agent, m.decidedAt))
		line := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&line, "mind %d %d %d %d %d %d %d %d", m.agent, m.decisions, 1 if m.waiting else 0, m.heard, m.awaiting,
		             m.awaitSince, m.awaitUntil, m.nintentions)
		for k: i32 = 0; k < m.nintentions; k += 1 {
			t := &m.intentions[k]
			fmt.sbprintf(&line, " %s %d %d %d %d %d %d %d %d %d", t.goal, t.adopted, t.failed, t.pending, t.following, t.arose,
			             t.commitment, t.pressed, t.stepsDone, t.nparams)
			for p: i32 = 0; p < t.nparams; p += 1 do fmt.sbprintf(&line, " %s %d", t.params[p].slot, t.params[p].referent)
		}
		append(&lines, strings.to_string(line))
		if m.autopilot do append(&lines, fmt.tprintf("autopilot %d %d", m.agent, m.threshold))
		if m.routine do append(&lines, fmt.tprintf("routine %d", m.agent))
		if m.explore do append(&lines, fmt.tprintf("explore %d", m.agent))
		if m.recipe != nil do append(&lines, fmt.tprintf("recipe %d %s", m.agent, m.recipe))
		if m.wake != 0 do append(&lines, fmt.tprintf("wake %d %d", m.agent, m.wake))
		if m.walking.set {
			j := m.walking
			append(&lines, fmt.tprintf("walking %d %d %d %d %d %s", m.agent, j.toward, j.x, j.y, j.level,
			                           j.goal if j.goal != nil else "-"))
		}
		for k: i32 = 0; k < m.nhabits; k += 1 {
			append(&lines, fmt.tprintf("habit %d %s %d %d %d", m.agent, m.habits[k].context_, m.habits[k].choice,
			                           m.habits[k].strength, m.habits[k].at))
		}
		for k: i32 = 0; k < m.ncommitments; k += 1 {
			cl := strings.builder_make(context.temp_allocator)
			fmt.sbprintf(&cl, "commitment %d %s %d %d %s %d %d", m.agent, m.commitments[k].goal, m.commitments[k].from,
			             m.commitments[k].until, m.commitments[k].source, 1 if m.commitments[k].settled else 0,
			             m.commitments[k].nparams)
			for q: i32 = 0; q < m.commitments[k].nparams; q += 1 {
				fmt.sbprintf(&cl, " %s %d", m.commitments[k].params[q].slot, m.commitments[k].params[q].referent)
			}
			append(&lines, strings.to_string(cl))
			if m.commitments[k].every != 0 {
				append(&lines, fmt.tprintf("recurs %d %d %d", m.agent, k, m.commitments[k].every))
			}
			if m.commitments[k].resume != 0 {
				append(&lines, fmt.tprintf("resume %d %d %d", m.agent, k, m.commitments[k].resume))
			}
		}
		for k: i32 = 0; k < m.nsettled; k += 1 {
			if m.settled[k].about == 0 {
				/* a goal pressed: what was felt, and when it is tried again */
				append(&lines, fmt.tprintf("settled %d %s 0 %d %d %d", m.agent, m.settled[k].goal, m.settled[k].verdict,
				                           m.settled[k].retry, m.settled[k].held))
			} else {
				append(&lines, fmt.tprintf("settled %d %s %d", m.agent, m.settled[k].goal, m.settled[k].about))
			}
		}
		for k: i32 = 0; k < m.nweighed; k += 1 {
			append(&lines, fmt.tprintf("weighed %d %s %d %d", m.agent, m.weighed[k].goal, m.weighed[k].about,
			                           m.weighed[k].verdict))
		}
		for k: i32 = 0; k < m.nquestions; k += 1 {
			append(&lines, fmt.tprintf("question %d %d %d %d %s", m.agent, m.questions[k].asker, m.questions[k].heard,
			                           1 if m.questions[k].deferred else 0, encode_word(m.questions[k].content)))
		}
		agency_deals_saved(m, &lines)
	}
	return lines[:]
}


agency_restore_saved_state :: proc(self: ^Agency, lines: []string) {
	m: ^Motivation
	t: ^Intention
	w: int
	n: i32
	k: i32
	p: i32

	for mind in self.minds do release(mind)
	clear(&self.minds)
	for i := 0; i < len(lines); i += 1 {
		words := ns_components_separated(lines[i], " ")
		if len(words) >= 8 && words[0] == "commitment" {
			m = agency_mind_of(self, Entity_ID(ns_long_long_value(words[1])))
			if m.ncommitments == BG_MAX_COMMITMENTS do continue
			c := &m.commitments[m.ncommitments]
			m.ncommitments += 1
			c.goal    = world_intern(self.world, ns_utf8(words[2]))
			c.from    = ns_long_long_value(words[3])
			c.until   = ns_long_long_value(words[4])
			c.source  = world_intern(self.world, ns_utf8(words[5]))
			c.settled = ns_int_value(words[6]) != 0
			c.nparams = 0
			for q := 8; q + 1 < len(words) && c.nparams < BG_MAX_SLOTS; q += 2 {
				c.params[c.nparams].slot     = world_intern(self.world, ns_utf8(words[q]))
				c.params[c.nparams].referent = u32(ns_long_long_value(words[q + 1]))
				c.nparams += 1
			}
			continue
		}
		if len(words) == 6 && words[0] == "habit" {
			m = agency_mind_of(self, Entity_ID(ns_long_long_value(words[1])))
			if m.nhabits == BG_MAX_HABITS do continue
			h := &m.habits[m.nhabits]
			m.nhabits += 1
			h.context_ = world_intern(self.world, ns_utf8(words[2]))
			h.choice   = u32(ns_long_long_value(words[3]))
			h.strength = ns_int_value(words[4])
			h.at       = ns_long_long_value(words[5])
			continue
		}
		if len(words) == 3 && words[0] == "wake" {
			agency_mind_of(self, Entity_ID(ns_long_long_value(words[1]))).wake = ns_long_long_value(words[2])
			continue
		}
		if len(words) == 4 && words[0] == "recurs" {
			m = agency_mind_of(self, Entity_ID(ns_long_long_value(words[1])))
			if ns_int_value(words[2]) < m.ncommitments {
				m.commitments[ns_int_value(words[2])].every = ns_long_long_value(words[3])
			}
			continue
		}
		if len(words) == 4 && words[0] == "resume" {
			m = agency_mind_of(self, Entity_ID(ns_long_long_value(words[1])))
			if ns_int_value(words[2]) < m.ncommitments {
				m.commitments[ns_int_value(words[2])].resume = ns_long_long_value(words[3])
			}
			continue
		}
		if len(words) == 7 && words[0] == "walking" {
			agency_mind_of(self, Entity_ID(ns_long_long_value(words[1]))).walking = Walk_Purpose{
				set    = true,
				toward = u32(ns_long_long_value(words[2])),
				x      = i32(ns_long_long_value(words[3])),
				y      = i32(ns_long_long_value(words[4])),
				level  = i32(ns_long_long_value(words[5])),
				goal   = nil if words[6] == "-" else world_intern(self.world, ns_utf8(words[6])),
			}
			continue
		}
		if len(words) == 3 && words[0] == "recipe" {
			agency_mind_of(self, Entity_ID(ns_long_long_value(words[1]))).recipe = world_intern(self.world, ns_utf8(words[2]))
			continue
		}
		if len(words) == 2 && words[0] == "explore" {
			agency_mind_of(self, Entity_ID(ns_long_long_value(words[1]))).explore = true
			continue
		}
		if len(words) == 2 && words[0] == "routine" {
			agency_mind_of(self, Entity_ID(ns_long_long_value(words[1]))).routine = true
			continue
		}
		if len(words) == 3 && words[0] == "autopilot" {
			m            = agency_mind_of(self, Entity_ID(ns_long_long_value(words[1])))
			m.autopilot  = true
			m.threshold  = ns_int_value(words[2])
			continue
		}
		if ((len(words) == 4 || len(words) == 7) && words[0] == "settled") || (len(words) == 5 && words[0] == "weighed") {
			m = agency_mind_of(self, Entity_ID(ns_long_long_value(words[1])))
			full := (m.nsettled == BG_MAX_SETTLED) if words[0] == "settled" else (m.nweighed == BG_MAX_SETTLED)
			if full do continue
			a: ^Arisen
			if words[0] == "settled" {
				a = &m.settled[m.nsettled]
				m.nsettled += 1
			} else {
				a = &m.weighed[m.nweighed]
				m.nweighed += 1
			}
			a.goal    = world_intern(self.world, ns_utf8(words[2]))
			a.about   = u32(ns_long_long_value(words[3]))
			a.verdict = ns_int_value(words[4]) if len(words) >= 5 else 0
			a.retry   = ns_long_long_value(words[5]) if len(words) == 7 else 0
			a.held    = u64(ns_long_long_value(words[6])) if len(words) == 7 else 0
			continue
		}
		if agency_deals_restore(self, words) do continue
		if len(words) == 6 && words[0] == "question" {
			m = agency_mind_of(self, Entity_ID(ns_long_long_value(words[1])))
			if m.nquestions == BG_MAX_QUESTIONS do continue
			// decode_word's text is the caller's to free.
			text := decode_word(ns_utf8(words[5]))
			m.questions[m.nquestions].asker    = u32(ns_long_long_value(words[2]))
			m.questions[m.nquestions].heard    = ns_long_long_value(words[3])
			m.questions[m.nquestions].deferred = ns_int_value(words[4]) != 0
			m.questions[m.nquestions].content  = world_intern(self.world, text)
			m.nquestions += 1
			free(rawptr(text))
			continue
		}
		if len(words) == 3 && words[0] == "decided" {
			agency_mind_of(self, Entity_ID(ns_long_long_value(words[1]))).decidedAt = ns_long_long_value(words[2])
			continue
		}
		if len(words) < 9 || words[0] != "mind" do continue
		m            = agency_mind_of(self, Entity_ID(ns_long_long_value(words[1])))
		m.decisions  = u64(ns_long_long_value(words[2]))
		m.waiting    = ns_int_value(words[3]) != 0
		m.heard      = u64(ns_long_long_value(words[4]))
		m.awaiting   = u32(ns_long_long_value(words[5]))
		m.awaitSince = ns_long_long_value(words[6])
		m.awaitUntil = ns_long_long_value(words[7])
		n            = ns_int_value(words[8])
		w            = 9
		for k = 0; k < n && k < BG_MAX_INTENTIONS && w + 10 <= len(words); k += 1 {
			t = &m.intentions[m.nintentions]
			m.nintentions += 1
			t^           = {}
			t.goal       = world_intern(self.world, ns_utf8(words[w]))
			w += 1
			t.adopted    = ns_long_long_value(words[w])
			w += 1
			t.failed     = u32(ns_long_long_value(words[w]))
			w += 1
			t.pending    = ns_int_value(words[w])
			w += 1
			t.following  = ns_int_value(words[w])
			w += 1
			t.arose      = u32(ns_long_long_value(words[w]))
			w += 1
			t.commitment = ns_int_value(words[w])
			w += 1
			t.pressed    = ns_int_value(words[w])
			w += 1
			t.stepsDone  = u32(ns_long_long_value(words[w]))
			w += 1
			t.nparams    = ns_int_value(words[w])
			w += 1
			for p = 0; p < t.nparams && p < BG_MAX_SLOTS && w + 2 <= len(words); p += 1 {
				t.params[p].slot     = world_intern(self.world, ns_utf8(words[w]))
				w += 1
				t.params[p].referent = u32(ns_int_value(words[w]))
				w += 1
			}
			t.nparams = p
		}
	}
	/* restored, not looked up: nothing is nudged, and the wakes are built
	 * again from the minds when wanted */
	clear(&self.nudged)
	wakes_free(self.wakes)
	self.wakes = nil
}

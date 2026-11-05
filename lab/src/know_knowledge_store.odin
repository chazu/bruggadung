package lab

/*
 * BGKnowledge — what agents know (KNOWLEDGE.md), first slice. Each agent has
 * a private knowledge store, written only by the perception phase after a
 * boundary's commit rounds; it never goes through commitment, and agents
 * never read world state or history directly.
 *
 * A store holds referents: agent-local handles (R1, R2, ...) for things the
 * agent thinks exist, each with its kind, the features last perceived (a
 * Triangle description, without ids), where it was, and when. Places name
 * other referents, never entity IDs. Each referent also keeps a truth link,
 * the entity it actually tracks, which only the developer and the world's
 * side of an attempt may read; recognition never consults it.
 *
 * Perception (state perception, for now): an agent perceives the physical
 * things within sight (BG_SIGHT tiles), through their perceivable fields.
 * What is inside a container is seen only when the agent looks in: when
 * something it did this boundary put a thing in it, took from it, looked
 * into it, or reached into it.
 * Recognition binds a percept to a referent of the same kind, preferring one
 * believed at that very place, then the nearest. A referent believed at a
 * place the agent can see, and not seen there, is marked absent.
 *
 * Event perception: an agent perceives what happens where it can see, by an
 * actor in sight. A thing it sees put somewhere is perceived there, inside a
 * container too, though nothing else inside is. What it perceives happen is
 * kept as observations, in its referents: who moved what where, who said what
 * to whom. A claim it hears (content/talk/talk.tri's #IsIn) is kept as
 * testimony: the things described are bound to its referents by recognition,
 * or become new ones, and the speaker, and the one the claim says saw it, are
 * its source and its perceived root.
 *
 * Credence (KNOWLEDGE.md §11) is fixed-point log-odds, in whole decibans
 * (dB): a claim of where something is starts at BG_PRIOR, and each group of
 * testimony with the same perceived root adds its strongest item's weight,
 * from the agent's trust in the source and the root, less for hearsay, and
 * less again for a claim with no source named. Testimony with no known root
 * is a group of its own, so a rumour heard twice counts twice until a
 * question ("who told you?") brings its root to light. Once its credence
 * reaches BG_BELIEVE, the thing is believed where the claim puts it. Trust
 * grows when the agent sees a claim confirmed, and falls more when it finds
 * one false.
 *
 * Memory decays (KNOWLEDGE.md §12), computed from the world's time when it
 * is read: for each BG_MEMORY_STEP since a referent was last seen, each
 * feature it keeps generalizes one step along its primary parent ("oak"
 * becomes "wood"), and one generalized as far as it goes is forgotten. The
 * strength of a belief of where a thing is, BG_SEEN for one seen, its
 * credence for one told, fades by BG_FADE a step, and below BG_BELIEVE the
 * agent forgets where it is, at its next perception phase. It fades slower
 * for what was sighted again and again (twice as slow at three sightings,
 * up to four times at seven) and for what took part in something salient
 * (BG_NOTICE over its peak salience: a third as fast for an anomaly). Seeing it again
 * restores both. A claim of what the speaker saw says how sure it is, its
 * memory's strength, and weighs no more than that.
 *
 * Forgetting a referent (KNOWLEDGE.md decision 19): a thing it perceived
 * end where it believed it (a destroyed or merged event, by an actor in
 * sight), found gone, ended. A referent not believed anywhere, ended or
 * faded below belief, is forgotten, its findings with it, unless something
 * holds it: an observation, testimony or identity hypothesis about it, a
 * referent in or on it, the agent's agency (Concerns.holds), or its being
 * someone.
 *
 * Perception reads appearance (KNOWLEDGE.md §4): a plated fitting looks
 * brass. What an analysis the agent did found beneath it is kept with the
 * referent and overrides its looks, however often it is seen again.
 *
 * Traces (KNOWLEDGE.md §3) are perceived by their kind's sense: by sight on
 * what the agent sees, or on the floor in sight; by smell within
 * BG_SMELL tiles; by hearing within BG_HEARING, out of sight too. What it perceives is the trace's kind, where, and how
 * strong it seems now (its age fades it), never what made it; a trace it
 * perceived at a site it perceives again, and no longer finds, is gone. A
 * trace fainter than BG_TRACE_FLOOR goes unnoticed, except at the close
 * look an investigation ends in (KNOWLEDGE.md §9, deliberate), which also
 * smells a tile further, and draws the rules that take thought.
 *
 * Interpretation (KNOWLEDGE.md §9), immediate: after each perception phase,
 * the interpretation rules (content/knowledge.tri, and each topic's) run over
 * the agent's referents, those whose expertise it has; a rule whose premises
 * hold (traces perceived on the thing now, or perceived before and gone) adds
 * its finding, with the rule as its provenance.
 *
 * A promise heard is testimony about a time to come: not believed of now,
 * and settled only when it is due: kept, if the agent sees the thing in
 * the container, and trusts the promiser more; broken, if it looks and the
 * thing isn't there, and trusts the promiser less. Looking early settles
 * nothing.
 *
 * Reading a record (KNOWLEDGE.md §15) is how claims are heard from someone
 * absent: each entry the agent reads is testimony whose source is the
 * author, recognized by the looks the writing gives, and whose medium is
 * the record.
 *
 * Interoception (AGENCY.md §6) is a sense like any other: each perception
 * phase the agent feels its hunger, from its body's stock, to the nearest
 * band of ten below, and dulled by what its running activity demands of
 * its attention. It acts on what it feels, not on what its body is.
 *
 * Habits seen in others (AGENCY.md §8): a rule over repeated observations
 * concludes someone usually puts things in the same place; seeing them put
 * something elsewhere is an anomaly, and salient.
 *
 * Recognition by unification (CONTENT_LANGUAGE.md Scenario 3): a percept
 * that fails to unify with a referent only on short-lived features
 * (content/knowledge.tri: a coat) may still be that one, changed: the
 * agent makes a new referent and an identity hypothesis, "it may be that
 * one", with a credence from the paths that agree and those that conflict,
 * all of them reported. A percept that later fits both is evidence they are
 * one, and the hypothesis gains. Conditions stub: at dusk, what is beyond
 * arm's reach is seen a step less precisely (grey looks dark); a match keeps
 * the more specific description.
 *
 * Salience (KNOWLEDGE.md §7, AGENCY.md §10): what an agent perceives happen
 * is kept as an observation only if it is salient enough: being addressed
 * most, its own deeds next, then what its goals concern (agency says what
 * they are), and the rest, routine, not at all. What it must reach is
 * BG_NOTICE, raised by the attention its running activity demands, so a busy
 * agent notices less. What it does not notice it does not believe, if it was
 * a claim. A store keeps at most the agent's `memory` observations, evicting
 * the least salient first, the oldest of those first.
 *
 * True ancestry is developer-only: each claim said is traced, through what
 * its speaker knew when it spoke, to whoever saw it first, or to the one who
 * made it up (a fabrication root). Speakers know their own lies: their
 * observation of saying it is marked not believed.
 */

/*
 * Port: know/BGKnowledge.h (all of it, but the BGConcerns protocol, which is
 * in protocols.odin) and know/BGKnowledge.m lines 1-1719: the file's
 * preamble and the BGKnowledgeStore class. BGKnowledge's methods are in the
 * other know_knowledge_*.odin files. The .m's static functions are
 * package-private here, named know_<name>, since the .m is split across
 * files.
 *
 * Memory: a referent's kind, features, deeper and supposed texts, and an
 * observation's content, are C strings in the context allocator (as the
 * Objective-C's were malloc'd): strings.clone_to_cstring in, delete out. The
 * news strings are the store's: cloned in when added, deleted when removed.
 */

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import tri "../../triangle/odin/triangle"


BG_SIGHT :: 4
BG_SMELL :: 1
BG_HEARING :: 10

BG_TRACE_FLOOR :: 30         /* a trace fainter than this goes unnoticed */
BG_TRACE_FLOOR_CLOSE :: 5    /* ... unless the agent is looking closely: investigating */

/* credence and trust, in dB */
BG_PRIOR :: -10              /* a claim of where something is, before any testimony */
BG_TRUST :: 20               /* trust in an agent the agent has not yet tested */
BG_TRUST_LIMIT :: 30         /* trust stays within +- this */
BG_HEARSAY :: 5              /* less, for a claim heard from someone named */
BG_RUMOUR :: 10              /* less, for a claim heard from no one named */
BG_BELIEVE :: 0              /* credence at which a claim is believed */
BG_CONFIRMED :: 5            /* trust gained when a claim is seen to be true */
BG_REFUTED :: 15             /* trust lost when a claim is found false */
BG_WRONGED :: 10             /* trust lost in one who harms it, or is seen to wrong another (KNOWLEDGE.md decision 15) */
BG_SEEN :: 30                /* the strength of a belief of where a thing is, seen just now */
BG_FOUND :: 20               /* dB that a thing found gone is the one like it seen elsewhere since, if only one is */
BG_FADE :: 2                 /* strength lost each memory step */
BG_UNSTATED :: max(i32)      /* a claim that says nothing of how sure */

BG_MEMORY_STEP :: i64(86400000)  /* ms: a day */

/* salience */
BG_ADDRESSED :: 30           /* said to the agent */
BG_OWN_DEED :: 20            /* done by the agent */
BG_CONCERN :: 15             /* about something its goals concern */
BG_ANOMALY :: 25             /* against what it believes someone usually does */
BG_NOTICE :: 10              /* what an observation must reach to be kept, at rest */
BG_ATTENTION :: 100          /* attention a boundary, at rest (KNOWLEDGE.md §5) */
BG_PERCEPT_COST :: 10        /* what attending to one event takes of it */

BG_HYPOTHESES :: 3           /* competing hypotheses a referent holds at most */
BG_DOUBT :: 300              /* the mass, in thousandths, of what was half taken in (KNOWLEDGE.md decision 12) */
BG_IMPAIRED :: 100           /* fatigue and injury that impair perceiving; half as much adrenaline does */

Referent :: struct {
	id:           u32,
	kind:         cstring,                   /* a type expression: "#Stack" */
	features:     cstring,                   /* "mass: 90g, material: \"iron\", ..." */
	deeper:       cstring,                   /* what an analysis found beneath its looks: "material: \"steel\"", or NULL */
	supposed:     [BG_HYPOTHESES]cstring,    /* competing hypotheses (CONTENT_LANGUAGE.md §9): features in place of what it believes; packed, NULL after the last */
	supposedMass: [BG_HYPOTHESES]i32,        /* their credence masses, in thousandths; the belief has the rest */
	form:         Location_Form,             /* how it was placed when last seen */
	container:    u32,                       /* the referent it was in, held by, or part of */
	x:            i32,                       /* the tile it was on, or its holder's */
	y:            i32,
	level:        i32,
	slot:         i32,
	role:         [16]u8,
	seen:         i64,                       /* ms */
	first:        i64,                       /* when it was first seen (ms), or -1 */
	insideSeen:   i64,                       /* when it last saw inside it (ms), or -1 */
	toldBy:       u32,                       /* the referent who said it is where it is believed; 0 if seen */
	trust:        i32,                       /* dB: in what it says, if it is someone, from its conduct */
	loyalty:      i32,                       /* 0 to 100: the agent's to it, if someone it is bound to (AGENCY.md §12) */
	present:      bool,                      /* still believed where it was last seen */
	ended:        bool,                      /* it perceived the thing end (KNOWLEDGE.md decision 19): gone for good */
	sightings:    i32,                       /* how often it was sighted (not seen for a minute before) */
	salience:     i32,                       /* the most salient thing it was kept in an observation for */
	truth:        Entity_ID,                 /* developer-only */
}


/* The tiles a referent covers east and south from where it is believed,
 * as the agent saw them: an area's (content/things.tri's #Area), else one. */
referent_extent :: proc(r: ^Referent) -> (east: i32, south: i32) {
	v: i64

	east, south = 1, 1
	if r == nil || r.features == nil || !strings.contains(string(r.features), "south: ") do return
	if know_int_feature(r.features, "east", &v) do east = i32(v)
	if know_int_feature(r.features, "south", &v) do south = i32(v)
	return
}


/* Whether `me` is believed within reach of a referent: on its tile or
 * beside it, or an area's, any of them. */
referent_in_reach :: proc(me: ^Referent, r: ^Referent, range: i32 = 1) -> bool {
	if r == nil || me == nil || me.level != r.level do return false
	east, south := referent_extent(r)
	return me.x >= r.x - range && me.x <= r.x + east - 1 + range && me.y >= r.y - range && me.y <= r.y + south - 1 + range
}


/* What the agent perceived happen (KNOWLEDGE.md §7), in its referents. */
Observation :: struct {
	time:       i64,           /* ms */
	kind:       cstring,       /* "moved", "said" */
	actor:      u32,           /* who did it; 0 if no referent */
	subject:    u32,           /* moved: what */
	other:      u32,           /* moved: what it went into, or who took it; said: to whom */
	content:    cstring,       /* said: what */
	unbelieved: bool,          /* said by the agent itself, which didn't believe it: a lie */
	salience:   i32,
	serial:     u64,           /* in the order observed, never reused */
}


/* A trace perceived: on a referent, or on the floor. */
Trace_Seen :: struct {
	bearer:   u32,             /* referent; 0 for the floor */
	x:        i32,             /* the floor's tile */
	y:        i32,
	level:    i32,
	kind:     cstring,         /* interned: "fresh_paint" */
	strength: i32,             /* as it seemed, 1..100 */
	seen:     i64,             /* ms */
	present:  bool,            /* still there, as far as it knows */
	truth:    Entity_ID,       /* developer-only: the trace */
}


Attribution :: enum i32 {
	Saw = 0,                   /* "I saw it" */
	Heard_From,                /* "I heard it from ..." */
	Heard,                     /* "I heard it", from no one named */
	Pledged,                   /* "I promise it", by `when` */
}


/* An identity hypothesis: referent `a` may be referent `b`. */
Identity :: struct {
	a:        u32,             /* the newer */
	b:        u32,
	credence: i32,             /* dB that they are one */
	paths:    [64]u8,          /* where they differed: "coat" */
	time:     i64,             /* ms: last weighed */
}


/* A law the agent knows (INSTITUTIONS.md decision 8): what it forbids,
 * what makes that a wrong, what breaking it brings and weighs. Known as
 * what it says, never by entity. */
Known_Law :: struct {
	forbids: cstring,          /* interned: an operation's effect */
	wrong:   cstring,          /* interned: "\"anothers\"" */
	brings:  cstring,          /* interned: "\"arrest\"" */
	weighs:  i32,              /* dB */
}


/* A price the agent knows, read on a stall's board (content/market/): who
 * sells goods of the unit there, at so many coins a unit, as of when it
 * read it. One to a board and unit, the latest: sellers who look alike are
 * told apart by their stalls' boards. */
Known_Price :: struct {
	seller: u32,               /* referent */
	board:  u32,               /* referent: the board it read it on, standing on the stall */
	unit:   cstring,           /* interned: the goods' unit, "grain" */
	coins:  i32,
	time:   i64,               /* ms */
}


/* What a rule concluded (KNOWLEDGE.md §9): something about a referent. */
Finding :: struct {
	kind:     cstring,         /* interned: a #Finding type, "#Tampered" */
	about:    u32,             /* referent */
	choice:   u32,             /* for a #Habit: the referent it usually chooses; else 0 */
	credence: i32,             /* dB */
	rule:     cstring,         /* interned: its provenance */
	time:     i64,             /* ms */
}


/* A claim heard (KNOWLEDGE.md §11's provenance item): `source` said that
 * `thing` is inside `container`, as of `when`. */
Testimony :: struct {
	thing:       u32,
	container:   u32,
	when_:       i64,          /* ms */
	heard:       i64,          /* ms */
	source:      u32,          /* who said it */
	root:        u32,          /* who it says saw it, the perceived root; 0 if unknown */
	via:         u32,          /* the record it was read in; 0 if said */
	attribution: Attribution,
	settled:     i32,          /* 1 seen true, -1 found false, 0 open */
	sure:        i32,          /* dB: how sure "saw" says it is, or BG_UNSTATED */
	utterance:   u64,          /* developer-only: the said event, for its true ancestry */
}


/* Developer-only: where a claim said truly came from. */
Ancestry :: struct {
	utterance:  u64,           /* the said event */
	speaker:    Entity_ID,
	origin:     Entity_ID,     /* who saw it first, or made it up */
	parent:     u64,           /* the said event the speaker had it from, if `relayed` */
	relayed:    bool,
	fabricated: bool,          /* nobody saw it: `origin` made it up */
}


/* What an agent has seen of the terrain (TERRAIN.md decision 7): per chunk
 * it has seen any of, a bit per tile, and when it last saw the chunk. */
Seen_Chunk :: struct {
	cx:   i32,
	cy:   i32,
	z:    i32,
	used: bool,
	seen: i64,                 /* ms it last saw any of it */
	bits: [BG_CHUNK * BG_CHUNK / 32]u32,
}

/* A tile it saw that has changed since, unseen: the kind it last saw. */
Terrain_Recall :: struct {
	x:    i32,
	y:    i32,
	z:    i32,
	kind: Terrain_Kind,
}


Knowledge_Store :: struct {
	using object: Object,
	/* public */
	/* when it perceives (REALITY.md decision 7): not saved, a game resumed
	 * perceives everything once */
	perceivedAt:   i64,              /* the time it last perceived; -1 never */
	perceiveBy:    i64,              /* it perceives again by then, nothing happening: a trace fading */
	daylightSeen:  i32,              /* the daylight it last perceived in */
	forgetBy:      i64,              /* the next time it forgets something; -2 not known */
	agent:         Entity_ID,
	/* protected */
	world:         ^World,           /* not retained: for the time memory decays by */
	self:          u32,
	referents:     [^]Referent,
	count:         uint,
	capacity:      uint,
	next:          u32,
	seenChunks:    [^]Seen_Chunk,    /* open addressing, by chunk */
	nseenChunks:   uint,
	seenCap:       uint,             /* a power of two, or 0 */
	recalls:       [^]Terrain_Recall,
	nrecalls:      uint,
	news:          [dynamic]string,  /* what perception changed, this boundary */
	observations:  [^]Observation,
	nobservations: uint,
	ocapacity:     uint,
	serial:        u64,              /* the next observation's */
	testimony:     [^]Testimony,
	ntestimony:    uint,
	tcapacity:     uint,
	traces:        [^]Trace_Seen,
	ntraces:       uint,
	trcapacity:    uint,
	findings:      [^]Finding,
	nfindings:     uint,
	fcapacity:     uint,
	laws:          [^]Known_Law,
	nlaws:         uint,
	prices:        [dynamic]Known_Price,
	recipes:       [^]cstring,       /* interned: recipes it learned (ACTIONS.md decision 12) */
	nrecipes:      uint,
	hunger:        i32,              /* as felt */
	cold:          i32,
	stuffy:        i32,
	tired:         i32,
	pain:          i32,
	feltAt:        i64,              /* ms, or -1 */
	identities:    [^]Identity,
	nidentities:   uint,
	icapacity:     uint,
	arena:         ^tri.Arena,       /* its knowledge arena (CONTENT_LANGUAGE.md §12): descriptions parsed */
	parsed:        map[string]^tri.Node,  /* their text, to the node (keys the map's own) */
	used:          map[string]struct{},   /* the texts parsed or used since the last compaction: what is live (keys the set's own) */
	liveBytes:     uint,             /* the arena's bytes after the last compaction */
	compactions:   uint,
	/* incremental interpretation (PERFORMANCE.md decision 2): not saved; a
	 * store restored weighs everything once */
	weighed:       map[u32]Weighing,  /* each referent, as it was when its rules were last weighed */
	stale:         map[u32]struct{},  /* referents whose traces, observations or findings changed since */
	staleAll:      bool,             /* every referent: one merged, or forgotten */
	floorChanged:  bool,             /* a trace on the floor came or went: `near` premises, everywhere */
	eligible:      [dynamic]bool,    /* each rule: whether the agent had the expertise when last weighed */
}


/* A referent as interpretation last weighed it (PERFORMANCE.md decision 2). */
Weighing :: struct {
	looks: u64,                      /* a hash of what premises read of it: kind, features, place */
	kind:  u64,                      /* of its kind alone: another's usual place reads it */
	retry: bool,                     /* a finding about it waited for attention */
}


Knowledge :: struct {
	using object: Object,
	concerns:         Concerns,                 /* not retained */
	world:            ^World,
	stores:           [dynamic]^Knowledge_Store, /* sorted by agent */
	eventsSeen:       uint,
	perceptions:      u64,                      /* an agent's perceiving, counted, for measuring */
	interpretationNs: u64,                      /* the wall time of their interpretation, for measuring */
	touched:          [^]Entity_ID,             /* what changed by this boundary, sorted */
	short:            bool,                     /* the agent perceiving ran out of attention */
	blurred:          map[string]string,        /* blur's answers, by kind, distance and features: content is fixed (keys and values the map's own) */
	features:         map[u64]string,           /* what each entity looks like, until it changes (values the map's own) */
	perceiveWakes:    ^Wakes,                   /* each agent's next perception with nothing happening */
	forgetWakes:      ^Wakes,                   /* each agent's next forgetting */
	woken:            bool,                     /* the wakes built, from the stores */
	boundaryDaylight: i32,                      /* the daylight at the last boundary */
	perceived:        [^]Entity_ID,             /* the agents that perceived at this boundary, in order */
	nperceived:       uint,
	ntouched:         uint,
	omniscient:       bool,
	ambient:          i32,                      /* the light where no lamp shines: 2 day, 1 dusk, 0 night */
	light:            rawptr,                   /* the light domain, if light is simulated (KNOWLEDGE.md decision 14); retained */
	compactAlways:    bool,
	rules:            [dynamic]Read_Rule,       /* the interpretation rules, read once (PERFORMANCE.md decision 2) */
	rulesRead:        bool,
	verifyInterpretation: bool,                 /* weigh what incremental interpretation skips, and count misses (tests) */
	interpretationMisses: u64,
	ancestry:         [^]Ancestry,              /* developer-only, by utterance */
	nancestry:        uint,
	acapacity:        uint,
}


/* --- C's memory, as the Objective-C used it ------------------------------------- */

// C's realloc of an array of T, from old_cap elements to new_cap.
@(private = "file")
grow :: proc(p: [^]$T, old_cap, new_cap: uint) -> [^]T {
	q, _ := mem.resize(rawptr(p), int(old_cap * size_of(T)), int(new_cap * size_of(T)))
	return ([^]T)(q)
}

// calloc: n of T, zeroed.
@(private = "file")
calloc :: proc($T: typeid, n: uint) -> [^]T {
	q, _ := mem.alloc(int(n * size_of(T)))
	return ([^]T)(q)
}

// strdup.
@(private = "file")
strdup :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s)
}

// A NUL-terminated buffer's text, up to its NUL.
@(private = "file")
buf_text :: proc(b: []u8) -> string {
	return string(cstring(raw_data(b)))
}


/* --- the file's statics ---------------------------------------------------------- */

@(private)
know_max64 :: #force_inline proc(a: i64, b: i64) -> i64 {
	return a if a > b else b
}


@(private)
know_ground_tile :: proc(world: ^World, e: Entity_ID, tile: ^Location) -> bool {
	loc: Location
	e := e

	for guard := 0; guard < 64; guard += 1 {
		loc = world_location_of(world, e)
		if loc.form == .On_Tile {
			tile^ = loc
			return true
		}
		if loc.form == .None || loc.place == 0 do return false
		e = loc.place
	}
	return false
}


@(private)
know_depth_of :: proc(world: ^World, e: Entity_ID) -> i32 {
	loc: Location
	d: i32
	e := e

	for d = 0; d < 64; d += 1 {
		loc = world_location_of(world, e)
		if loc.form == .On_Tile || loc.form == .None || loc.place == 0 do return d
		e = loc.place
	}
	return d
}


@(private)
know_append_quoted :: proc(s: ^strings.Builder, text: cstring) {
	strings.write_string(s, "\"")
	if text != nil {
		p := ([^]u8)(text)
		for i := 0; p[i] != 0; i += 1 {
			if p[i] != '"' && p[i] != '\n' do strings.write_byte(s, p[i])
		}
	}
	strings.write_string(s, "\"")
}


/* static char *concrete_features( const char *printed) and static void
 * settle( ...) are declared here in the .m and defined further on:
 * know_concrete_features and know_settle, in BGKnowledge's part. */


/* The top-level keys of a features text: "mass: 90g, unit: ..." */
@(private)
know_feature_keys :: proc(features: cstring, keys: [^][32]u8, max_: uint) -> uint {
	p: [^]u8 = ([^]u8)(features)
	s := string(features)
	field: int
	n: uint
	depth: i32
	quoted: bool

	n = 0
	depth = 0
	quoted = false
	field = 0
	for i := 0; n < max_; i += 1 {
		if p[i] == '"' && (i == 0 || p[i - 1] != '\\') do quoted = !quoted
		if quoted && p[i] != 0 do continue
		if p[i] == '{' || p[i] == '[' || p[i] == '(' {
			depth += 1
		} else if (p[i] == '}' || p[i] == ']' || p[i] == ')') && depth > 0 {
			depth -= 1
		} else if (p[i] == ',' && depth == 0) || p[i] == 0 {
			for p[field] == ' ' do field += 1
			colon := strings.index(s[field:], ": ")     /* strstr: from field on */
			if colon >= 0 && field + colon < i && colon < 32 {
				/* snprintf( keys[ n], 32, "%.*s", ...) */
				for j := 0; j < colon; j += 1 do keys[n][j] = p[field + j]
				keys[n][colon] = 0
				n += 1
			}
			field = i + 1
		}
		if p[i] == 0 do break
	}
	return n
}


/* --- a store ------------------------------------------------------------------- */

/* BGKnowledgeStore */

// -initWithAgent:world:, which makes the store with a count of 1.
knowledge_store_init_with_agent :: proc(agent: Entity_ID, world: ^World) -> ^Knowledge_Store {
	self := object_new(Knowledge_Store, knowledge_store_dealloc)
	self.world = world
	self.agent = agent
	self.feltAt = -1
	self.perceivedAt = -1
	self.perceiveBy = max(i64)
	self.daylightSeen = -1
	self.forgetBy = -2
	self.next = 1
	self.news = make([dynamic]string)
	knowledge_store_learn_common_laws(self)
	return self
}


/* Its society's common laws (INSTITUTIONS.md decision 8): known from the
 * start, by what they say. */
knowledge_store_learn_common_laws :: proc(self: ^Knowledge_Store) {
	law: ^Law
	laws: ^Store
	k: Known_Law
	i: uint

	laws = world_store_for_kind(self.world, world_kind_named(self.world, "Law")) if self.world != nil else nil
	for i = 0; laws != nil && i < store_count(laws); i += 1 {
		law = (^Law)(store_record_at_index(laws, i))
		if !law.common || law.forbids == nil do continue
		k.forbids = world_intern(self.world, law.forbids)
		k.wrong = world_intern(self.world, tri.type_name(world_tri(self.world), tri.Type(law.wrong)))
		k.brings = world_intern(self.world, tri.type_name(world_tri(self.world), tri.Type(law.brings)))
		k.weighs = i32(law.weighs)
		knowledge_store_learn_law(self, k)
	}
}


knowledge_store_law_count :: proc(self: ^Knowledge_Store) -> uint {
	return self.nlaws
}


knowledge_store_law_at :: proc(self: ^Knowledge_Store, i: uint) -> ^Known_Law {
	return &self.laws[i] if i < self.nlaws else nil
}


knowledge_store_knows_recipe :: proc(self: ^Knowledge_Store, method: cstring) -> bool {
	pattern: ^tri.Node
	v: ^tri.Node
	trade: cstring
	content: ^tri.Content
	i: uint
	printed: [64]u8
	n: uint

	content = world_tri(self.world)
	pattern = tri.pattern(content, method) if method != nil else nil
	v = tri.at(content, pattern, "sequence") if pattern != nil else nil
	if v == nil || tri.node_type(v) != tri.type_named(content, "true") do return true
	v = tri.at(content, pattern, "ofTrade")
	n = uint(tri.print(content, v, raw_data(printed[:]), size_of(printed))) if v != nil else 0
	if n < 3 || printed[0] != '"' do return true
	printed[n - 1] = 0
	trade = world_text_field(self.world, "Agent.trade", self.agent)
	if trade != nil && string(trade) == buf_text(printed[1:]) do return true
	for i = 0; i < self.nrecipes; i += 1 {
		if string(self.recipes[i]) == string(method) do return true
	}
	return false
}


knowledge_store_learn_recipe :: proc(self: ^Knowledge_Store, method: cstring) {
	i: uint

	for i = 0; i < self.nrecipes; i += 1 {
		if string(self.recipes[i]) == string(method) do return
	}
	self.recipes = grow(self.recipes, self.nrecipes, self.nrecipes + 1)
	self.recipes[self.nrecipes] = world_intern(self.world, method)
	self.nrecipes += 1
}


knowledge_store_recipe_count :: proc(self: ^Knowledge_Store) -> uint {
	return self.nrecipes
}


knowledge_store_recipe_at :: proc(self: ^Knowledge_Store, i: uint) -> cstring {
	return self.recipes[i] if i < self.nrecipes else nil
}


/* A price read (content/market/): in place of what it knew of the board's
 * price for the unit. */
knowledge_store_learn_price :: proc(self: ^Knowledge_Store, price: Known_Price) {
	for &p in self.prices {
		if p.board == price.board && rawptr(p.unit) == rawptr(price.unit) {
			p = price
			return
		}
	}
	append(&self.prices, price)
}


knowledge_store_learn_law :: proc(self: ^Knowledge_Store, law: Known_Law) {
	i: uint

	/* interned: the same text is the same pointer */
	for i = 0; i < self.nlaws; i += 1 {
		if rawptr(self.laws[i].forbids) == rawptr(law.forbids) && rawptr(self.laws[i].wrong) == rawptr(law.wrong) do return
	}
	self.laws = grow(self.laws, self.nlaws, self.nlaws + 1)
	self.laws[self.nlaws] = law
	self.nlaws += 1
}


knowledge_store_dealloc :: proc(self: ^Knowledge_Store) {
	i: uint
	j: uint

	for i = 0; i < self.count; i += 1 {
		delete(self.referents[i].kind)
		delete(self.referents[i].features)
		delete(self.referents[i].deeper)
		for j = 0; j < BG_HYPOTHESES; j += 1 do delete(self.referents[i].supposed[j])
	}
	free(self.referents)
	for i = 0; i < self.nobservations; i += 1 do delete(self.observations[i].content)
	free(self.observations)
	free(self.testimony)
	free(self.traces)
	free(self.findings)
	free(self.laws)
	delete(self.prices)
	free(self.recipes)
	free(self.identities)
	free(self.seenChunks)
	free(self.recalls)
	if self.arena != nil do tri.arena_free(self.arena)
	for text in self.parsed do delete(text)
	delete(self.parsed)
	for text in self.used do delete(text)
	delete(self.used)
	for line in self.news do delete(line)
	delete(self.news)
	delete(self.weighed)
	delete(self.stale)
	delete(self.eligible)
}


/* Its traces, observations or findings changed: its rules are weighed
 * again (PERFORMANCE.md decision 2). */
knowledge_store_evidence_changed :: proc(self: ^Knowledge_Store, referentID: u32) {
	if referentID != 0 do self.stale[referentID] = {}
}


knowledge_store_agent :: proc(self: ^Knowledge_Store) -> Entity_ID {
	return self.agent
}


knowledge_store_self_referent :: proc(self: ^Knowledge_Store) -> u32 {
	return self.self
}


knowledge_store_count :: proc(self: ^Knowledge_Store) -> uint {
	return self.count
}


/* Forgets a referent (KNOWLEDGE.md decision 19), and its findings: what it
 * concluded about it, or that something usually chooses it. Nothing else
 * of the store may still name it. */
knowledge_store_forget_referent :: proc(self: ^Knowledge_Store, referentID: u32) {
	k: uint
	n: uint

	for k = 0; k < self.count && self.referents[k].id != referentID; k += 1 {
	}
	if k == self.count || referentID == self.self do return
	for i: uint = 0; i < self.nfindings; i += 1 {
		if self.findings[i].about != referentID && self.findings[i].choice != referentID {
			self.findings[n] = self.findings[i]
			n += 1
		}
	}
	self.nfindings = n
	self.staleAll = true      /* what named it, its findings, others' usual places */
	delete_key(&self.weighed, referentID)
	a := &self.referents[k]
	delete(a.kind)
	delete(a.features)
	delete(a.deeper)
	for h := 0; h < BG_HYPOTHESES; h += 1 do delete(a.supposed[h])
	mem.copy(&self.referents[k], &self.referents[k + 1], size_of(Referent) * int(self.count - k - 1))
	self.count -= 1
}


knowledge_store_referent_at :: proc(self: ^Knowledge_Store, i: uint) -> ^Referent {
	return &self.referents[i]
}


knowledge_store_mutable_referent :: proc(self: ^Knowledge_Store, referentID: u32) -> ^Referent {
	i: uint

	for i = 0; i < self.count; i += 1 {
		if self.referents[i].id == referentID do return &self.referents[i]
	}
	return nil
}


knowledge_store_referent :: proc(self: ^Knowledge_Store, referentID: u32) -> ^Referent {
	return knowledge_store_mutable_referent(self, referentID)
}


/* --- terrain seen (TERRAIN.md decision 7) --------------------------------------- */

@(private)
know_seen_slot :: proc(cx: i32, cy: i32, z: i32, cap_: uint) -> uint {
	return uint(mix((u64(u32(cx)) << 32) ~ (u64(u32(cy)) << 8) ~ u64(u32(z)))) & (cap_ - 1)
}


@(private)
know_chunk_of :: proc(v: i32) -> i32 {
	return v / BG_CHUNK if v >= 0 else -((-v + BG_CHUNK - 1) / BG_CHUNK)
}


// -seenChunkX:y:level:make:
knowledge_store_seen_chunk_x :: proc(self: ^Knowledge_Store, x: i32, y: i32, z: i32, make_: bool) -> ^Seen_Chunk {
	old: [^]Seen_Chunk
	c: ^Seen_Chunk
	oldcap: uint
	i: uint
	k: uint
	cx: i32
	cy: i32

	cx = know_chunk_of(x)
	cy = know_chunk_of(y)
	for i = know_seen_slot(cx, cy, z, self.seenCap) if self.seenCap != 0 else 0; self.seenCap != 0; i = (i + 1) & (self.seenCap - 1) {
		c = &self.seenChunks[i]
		if !c.used do break
		if c.cx == cx && c.cy == cy && c.z == z do return c
	}
	if !make_ do return nil
	if (self.nseenChunks + 1) * 2 > self.seenCap {
		old = self.seenChunks
		oldcap = self.seenCap
		self.seenCap = oldcap * 2 if oldcap != 0 else 8
		self.seenChunks = calloc(Seen_Chunk, self.seenCap)
		for k = 0; k < oldcap; k += 1 {
			if old[k].used {
				for i = know_seen_slot(old[k].cx, old[k].cy, old[k].z, self.seenCap); self.seenChunks[i].used; i = (i + 1) & (self.seenCap - 1) {
				}
				self.seenChunks[i] = old[k]
			}
		}
		free(old)
	}
	for i = know_seen_slot(cx, cy, z, self.seenCap); self.seenChunks[i].used; i = (i + 1) & (self.seenCap - 1) {
	}
	c = &self.seenChunks[i]
	c.cx = cx
	c.cy = cy
	c.z = z
	c.used = true
	c.seen = -1
	self.nseenChunks += 1
	return c
}


@(private)
know_bit_of :: proc(x: i32, y: i32) -> uint {
	return uint((y - know_chunk_of(y) * BG_CHUNK) * BG_CHUNK + (x - know_chunk_of(x) * BG_CHUNK))
}


knowledge_store_has_seen_x :: proc(self: ^Knowledge_Store, x: i32, y: i32, level: i32) -> bool {
	c: ^Seen_Chunk
	b: uint

	c = knowledge_store_seen_chunk_x(self, x, y, level, false)
	b = know_bit_of(x, y)
	return c != nil && ((c.bits[b / 32] >> (b % 32)) & 1) != 0
}


knowledge_store_chunk_seen_at_x :: proc(self: ^Knowledge_Store, x: i32, y: i32, level: i32) -> i64 {
	c: ^Seen_Chunk

	c = knowledge_store_seen_chunk_x(self, x, y, level, false)
	return c.seen if c != nil else -1
}


knowledge_store_believed_terrain_at_x :: proc(self: ^Knowledge_Store, x: i32, y: i32, level: i32) -> Terrain_Kind {
	i: uint

	if world_terrain(self.world) == nil || !knowledge_store_has_seen_x(self, x, y, level) do return 0
	for i = 0; i < self.nrecalls; i += 1 {
		if self.recalls[i].x == x && self.recalls[i].y == y && self.recalls[i].z == level do return self.recalls[i].kind
	}
	return terrain_at(world_terrain(self.world), x, y, level)
}


knowledge_store_see :: proc(self: ^Knowledge_Store, now: i64, x: i32, y: i32, level: i32) {
	c: ^Seen_Chunk
	b: uint
	i: uint

	c = knowledge_store_seen_chunk_x(self, x, y, level, true)
	b = know_bit_of(x, y)
	c.bits[b / 32] |= u32(1) << (b % 32)
	if now > c.seen do c.seen = now
	for i = 0; i < self.nrecalls; i += 1 {
		if self.recalls[i].x == x && self.recalls[i].y == y && self.recalls[i].z == level {
			self.nrecalls -= 1
			self.recalls[i] = self.recalls[self.nrecalls]
			break
		}
	}
}


knowledge_store_miss_change_from :: proc(self: ^Knowledge_Store, was: Terrain_Kind, x: i32, y: i32, level: i32) {
	i: uint

	if was == 0 || !knowledge_store_has_seen_x(self, x, y, level) do return
	for i = 0; i < self.nrecalls; i += 1 {
		if self.recalls[i].x == x && self.recalls[i].y == y && self.recalls[i].z == level {
			return          /* it recalls what it saw before the first change */
		}
	}
	self.recalls = grow(self.recalls, self.nrecalls, self.nrecalls + 1)
	self.recalls[self.nrecalls].x = x
	self.recalls[self.nrecalls].y = y
	self.recalls[self.nrecalls].z = level
	self.recalls[self.nrecalls].kind = was
	self.nrecalls += 1
}


@(private)
know_cmp_seen_chunk :: proc(p: ^Seen_Chunk, q: ^Seen_Chunk) -> int {
	if p.z != q.z do return -1 if p.z < q.z else 1
	if p.cy != q.cy do return -1 if p.cy < q.cy else 1
	return -1 if p.cx < q.cx else (1 if p.cx > q.cx else 0)
}


// -seenChunks: *out is a malloc'd copy, which the caller frees with free().
knowledge_store_seen_chunks :: proc(self: ^Knowledge_Store, out: ^[^]Seen_Chunk) -> uint {
	i: uint
	n: uint

	p, _ := mem.alloc(int((self.nseenChunks if self.nseenChunks != 0 else 1) * size_of(Seen_Chunk)))
	out^ = ([^]Seen_Chunk)(p)
	n = 0
	for i = 0; i < self.seenCap; i += 1 {
		if self.seenChunks[i].used {
			out^[n] = self.seenChunks[i]
			n += 1
		}
	}
	/* qsort: no two chunks are at the same place, so the order is total */
	slice.sort_by(out^[:n], proc(a, b: Seen_Chunk) -> bool {
		a, b := a, b
		return know_cmp_seen_chunk(&a, &b) < 0
	})
	return n
}


knowledge_store_restore_seen_chunk :: proc(self: ^Knowledge_Store, chunk: ^Seen_Chunk) {
	c: ^Seen_Chunk

	c = knowledge_store_seen_chunk_x(self, chunk.cx * BG_CHUNK, chunk.cy * BG_CHUNK, chunk.z, true)
	c.bits = chunk.bits
	c.seen = chunk.seen
}


knowledge_store_recall_count :: proc(self: ^Knowledge_Store) -> uint {
	return self.nrecalls
}


knowledge_store_recall_at :: proc(self: ^Knowledge_Store, i: uint) -> ^Terrain_Recall {
	return &self.recalls[i] if i < self.nrecalls else nil
}


// -news: the lines as they are now.
knowledge_store_news :: proc(self: ^Knowledge_Store) -> []string {
	return self.news[:]
}


// -mutableNews: a line added is cloned (strings.clone), and one removed
// deleted: the store's dealloc deletes those it still holds.
knowledge_store_mutable_news :: proc(self: ^Knowledge_Store) -> ^[dynamic]string {
	return &self.news
}


/* A new referent, with the given id (restoring) or the next one (0). */
knowledge_store_add_referent :: proc(self: ^Knowledge_Store, referentID: u32) -> ^Referent {
	r: ^Referent

	if self.count == self.capacity {
		old := self.capacity
		self.capacity = self.capacity * 2 if self.capacity != 0 else 16
		self.referents = grow(self.referents, old, self.capacity)
	}
	r = &self.referents[self.count]
	self.count += 1
	r^ = {}
	r.insideSeen = -1
	r.first = -1
	r.trust = BG_TRUST
	r.id = referentID if referentID != 0 else self.next
	if r.id >= self.next do self.next = r.id + 1
	return r
}


knowledge_store_observation_count :: proc(self: ^Knowledge_Store) -> uint {
	return self.nobservations
}


knowledge_store_observation_at :: proc(self: ^Knowledge_Store, i: uint) -> ^Observation {
	return &self.observations[i]
}


knowledge_store_next_serial :: proc(self: ^Knowledge_Store) -> u64 {
	return self.serial
}


/* `o`'s content is copied; it gets the next serial, unless restoring one */
knowledge_store_add_observation :: proc(self: ^Knowledge_Store, o: Observation, restored: bool) {
	o := o

	if self.nobservations == self.ocapacity {
		old := self.ocapacity
		self.ocapacity = self.ocapacity * 2 if self.ocapacity != 0 else 16
		self.observations = grow(self.observations, old, self.ocapacity)
	}
	if !restored do o.serial = self.serial
	if o.serial >= self.serial do self.serial = o.serial + 1
	o.content = strdup(string(o.content)) if o.content != nil else nil
	self.observations[self.nobservations] = o
	self.nobservations += 1
	knowledge_store_evidence_changed(self, o.actor)
	knowledge_store_evidence_changed(self, o.subject)
}


/* Over capacity, the least salient go, the oldest of them first. */
knowledge_store_keep_at_most :: proc(self: ^Knowledge_Store, capacity: uint) {
	i: uint
	least: uint

	for self.nobservations > capacity && self.nobservations != 0 {
		least = 0
		for i = 1; i < self.nobservations; i += 1 {
			if self.observations[i].salience < self.observations[least].salience do least = i
		}
		knowledge_store_evidence_changed(self, self.observations[least].actor)
		knowledge_store_evidence_changed(self, self.observations[least].subject)
		delete(self.observations[least].content)
		mem.copy(&self.observations[least], &self.observations[least + 1],
		         size_of(Observation) * int(self.nobservations - least - 1))
		self.nobservations -= 1
	}
}


knowledge_store_last_said_to :: proc(self: ^Knowledge_Store, referentID: u32) -> i64 {
	return knowledge_store_last_said_to_like(self, referentID, nil)
}


knowledge_store_last_said_to_like :: proc(self: ^Knowledge_Store, referentID: u32, kind: cstring) -> i64 {
	o: ^Observation
	i: uint
	n: int

	n = len(kind) if kind != nil else 0
	for i = self.nobservations; i > 0; i -= 1 {
		o = &self.observations[i - 1]
		if string(o.kind) != "said" || o.actor != self.self || o.other != referentID do continue
		if kind != nil {
			content := string(o.content)
			/* strncmp( content, kind, n), then the byte after it: none, or a space */
			if o.content == nil || !strings.has_prefix(content, string(kind)) || (len(content) > n && content[n] != ' ') do continue
		}
		return o.time
	}
	return -1
}


knowledge_store_trace_count :: proc(self: ^Knowledge_Store) -> uint {
	return self.ntraces
}


knowledge_store_trace_at :: proc(self: ^Knowledge_Store, i: uint) -> ^Trace_Seen {
	return &self.traces[i]
}


/* A trace to change: its bearer's rules are weighed again, or, on the
 * floor, every `near` premise. */
knowledge_store_mutable_trace_at :: proc(self: ^Knowledge_Store, i: uint) -> ^Trace_Seen {
	knowledge_store_trace_changed(self, self.traces[i])
	return &self.traces[i]
}


@(private = "file")
knowledge_store_trace_changed :: proc(self: ^Knowledge_Store, t: Trace_Seen) {
	if t.bearer != 0 {
		knowledge_store_evidence_changed(self, t.bearer)
	} else {
		self.floorChanged = true
	}
}


/* The trace of that kind at that site, updated, or added; YES if added. */
knowledge_store_knows_trace :: proc(self: ^Knowledge_Store, t: Trace_Seen) -> bool {
	i: uint

	/* kinds are interned: compared as pointers */
	for i = 0; i < self.ntraces; i += 1 {
		if rawptr(self.traces[i].kind) == rawptr(t.kind) && self.traces[i].bearer == t.bearer &&
		   (t.bearer != 0 || (self.traces[i].x == t.x && self.traces[i].y == t.y && self.traces[i].level == t.level)) {
			return true
		}
	}
	return false
}


knowledge_store_note_trace :: proc(self: ^Knowledge_Store, t: Trace_Seen) -> bool {
	i: uint

	for i = 0; i < self.ntraces; i += 1 {
		if rawptr(self.traces[i].kind) == rawptr(t.kind) && self.traces[i].bearer == t.bearer &&
		   (t.bearer != 0 || (self.traces[i].x == t.x && self.traces[i].y == t.y && self.traces[i].level == t.level)) {
			/* seen again: only its coming or going is evidence; its strength isn't */
			if self.traces[i].present != t.present do knowledge_store_trace_changed(self, t)
			self.traces[i] = t
			return false
		}
	}
	knowledge_store_trace_changed(self, t)
	if self.ntraces == self.trcapacity {
		old := self.trcapacity
		self.trcapacity = self.trcapacity * 2 if self.trcapacity != 0 else 16
		self.traces = grow(self.traces, old, self.trcapacity)
	}
	self.traces[self.ntraces] = t
	self.ntraces += 1
	return true
}


knowledge_store_feels :: proc(self: ^Knowledge_Store, need: cstring) -> i32 {
	n := string(need)
	return self.hunger if n == "hunger" else self.cold if n == "cold" else self.stuffy if n == "stuffy" else self.tired if n == "tired" else self.pain if n == "pain" else 0
}


knowledge_store_felt_at :: proc(self: ^Knowledge_Store) -> i64 {
	return self.feltAt
}


/* YES if it feels differently now */
knowledge_store_feel_hunger :: proc(self: ^Knowledge_Store, hunger: i32, t: i64) -> bool {
	changed: bool

	changed = self.feltAt < 0 || hunger != self.hunger
	self.hunger = hunger
	self.feltAt = t
	return changed
}


knowledge_store_feel_cold :: proc(self: ^Knowledge_Store, cold: i32) -> bool {
	changed: bool

	changed = cold != self.cold
	self.cold = cold
	return changed
}


knowledge_store_feel_pain :: proc(self: ^Knowledge_Store, pain: i32) -> bool {
	changed: bool

	changed = pain != self.pain
	self.pain = pain
	return changed
}


knowledge_store_feel_tired :: proc(self: ^Knowledge_Store, tired: i32) -> bool {
	changed: bool

	changed = tired != self.tired
	self.tired = tired
	return changed
}


knowledge_store_feel_stuffy :: proc(self: ^Knowledge_Store, stuffy: i32) -> bool {
	changed: bool

	changed = stuffy != self.stuffy
	self.stuffy = stuffy
	return changed
}


knowledge_store_merge_referent :: proc(self: ^Knowledge_Store, from: u32, into: u32) {
	a: ^Referent
	b: ^Referent
	keep: Referent
	i: uint
	k: uint
	n: uint
	h: int

	self.staleAll = true      /* its traces, observations and findings, now another's */
	a = knowledge_store_mutable_referent(self, from)
	b = knowledge_store_mutable_referent(self, into)
	if a == nil || b == nil || from == into || from == self.self || into == self.self do return
	/* what was seen last is how it looks, and where */
	if a.seen > b.seen {
		keep = b^
		delete(b.kind)
		delete(b.features)
		delete(b.deeper)
		b.kind = a.kind
		b.features = a.features
		b.deeper = a.deeper
		a.kind = nil
		a.features = nil
		a.deeper = nil
		b.form = a.form
		b.container = a.container
		b.x = a.x
		b.y = a.y
		b.level = a.level
		b.slot = a.slot
		b.role = a.role
		b.seen = a.seen
		b.toldBy = a.toldBy
		b.present = a.present
		b.ended = a.ended
		b.truth = a.truth
		b.insideSeen = a.insideSeen if a.insideSeen > keep.insideSeen else keep.insideSeen
	}
	if a.first >= 0 && (b.first < 0 || a.first < b.first) do b.first = a.first
	b.sightings += a.sightings
	b.salience = a.salience if a.salience > b.salience else b.salience
	b.loyalty = a.loyalty if a.loyalty > b.loyalty else b.loyalty
	b.trust += a.trust - BG_TRUST
	if b.trust > BG_TRUST_LIMIT do b.trust = BG_TRUST_LIMIT
	if b.trust < -BG_TRUST_LIMIT do b.trust = -BG_TRUST_LIMIT

	/* everything of `from`'s is `into`'s */
	for i = 0; i < self.count; i += 1 {
		if self.referents[i].container == from do self.referents[i].container = into
	}
	for i = 0; i < self.ntestimony; i += 1 {
		if self.testimony[i].thing == from do self.testimony[i].thing = into
		if self.testimony[i].container == from do self.testimony[i].container = into
		if self.testimony[i].source == from do self.testimony[i].source = into
		if self.testimony[i].root == from do self.testimony[i].root = into
		if self.testimony[i].via == from do self.testimony[i].via = into
	}
	for i = 0; i < self.nfindings; i += 1 {
		if self.findings[i].about == from do self.findings[i].about = into
		if self.findings[i].choice == from do self.findings[i].choice = into
	}
	for i = 0; i < self.nobservations; i += 1 {
		if self.observations[i].actor == from do self.observations[i].actor = into
		if self.observations[i].subject == from do self.observations[i].subject = into
		if self.observations[i].other == from do self.observations[i].other = into
	}
	for i = 0; i < self.ntraces; i += 1 {
		if self.traces[i].bearer == from do self.traces[i].bearer = into
	}
	for i, n = 0, 0; i < self.nidentities; i += 1 {
		if self.identities[i].a == from do self.identities[i].a = into
		if self.identities[i].b == from do self.identities[i].b = into
		if self.identities[i].a != self.identities[i].b {
			self.identities[n] = self.identities[i]
			n += 1
		}
	}
	self.nidentities = n

	/* and `from` is gone */
	for k = 0; k < self.count && self.referents[k].id != from; k += 1 {
	}
	a = &self.referents[k]
	delete(a.kind)
	delete(a.features)
	delete(a.deeper)
	for h = 0; h < BG_HYPOTHESES; h += 1 do delete(a.supposed[h])
	mem.copy(&self.referents[k], &self.referents[k + 1], size_of(Referent) * int(self.count - k - 1))
	self.count -= 1
}


knowledge_store_identity_count :: proc(self: ^Knowledge_Store) -> uint {
	return self.nidentities
}


knowledge_store_identity_at :: proc(self: ^Knowledge_Store, i: uint) -> ^Identity {
	return &self.identities[i]
}


knowledge_store_mutable_identity_at :: proc(self: ^Knowledge_Store, i: uint) -> ^Identity {
	return &self.identities[i]
}


knowledge_store_add_identity :: proc(self: ^Knowledge_Store, h: Identity) {
	if self.nidentities == self.icapacity {
		old := self.icapacity
		self.icapacity = self.icapacity * 2 if self.icapacity != 0 else 8
		self.identities = grow(self.identities, old, self.icapacity)
	}
	self.identities[self.nidentities] = h
	self.nidentities += 1
}


knowledge_store_finding_count :: proc(self: ^Knowledge_Store) -> uint {
	return self.nfindings
}


knowledge_store_finding_at :: proc(self: ^Knowledge_Store, i: uint) -> ^Finding {
	return &self.findings[i]
}


knowledge_store_finding :: proc(self: ^Knowledge_Store, kind: cstring, referentID: u32) -> ^Finding {
	i: uint

	for i = 0; i < self.nfindings; i += 1 {
		if self.findings[i].about == referentID && string(self.findings[i].kind) == string(kind) do return &self.findings[i]
	}
	return nil
}


knowledge_store_add_finding :: proc(self: ^Knowledge_Store, f: Finding) {
	if self.nfindings == self.fcapacity {
		old := self.fcapacity
		self.fcapacity = self.fcapacity * 2 if self.fcapacity != 0 else 16
		self.findings = grow(self.findings, old, self.fcapacity)
	}
	self.findings[self.nfindings] = f
	self.nfindings += 1
	knowledge_store_evidence_changed(self, f.about)
}


knowledge_store_retract_finding :: proc(self: ^Knowledge_Store, kind: cstring, referentID: u32) {
	i: uint

	for i = 0; i < self.nfindings; i += 1 {
		if string(self.findings[i].kind) == string(kind) && self.findings[i].about == referentID {
			knowledge_store_evidence_changed(self, referentID)
			mem.copy(&self.findings[i], &self.findings[i + 1], size_of(Finding) * int(self.nfindings - i - 1))
			self.nfindings -= 1
			return
		}
	}
}


knowledge_store_testimony_count :: proc(self: ^Knowledge_Store) -> uint {
	return self.ntestimony
}


knowledge_store_testimony_at :: proc(self: ^Knowledge_Store, i: uint) -> ^Testimony {
	return &self.testimony[i]
}


knowledge_store_mutable_testimony_at :: proc(self: ^Knowledge_Store, i: uint) -> ^Testimony {
	return &self.testimony[i]
}


knowledge_store_append_testimony :: proc(self: ^Knowledge_Store, t: Testimony) {
	if self.ntestimony == self.tcapacity {
		old := self.tcapacity
		self.tcapacity = self.tcapacity * 2 if self.tcapacity != 0 else 16
		self.testimony = grow(self.testimony, old, self.tcapacity)
	}
	self.testimony[self.ntestimony] = t
	self.ntestimony += 1
}


/* A source saying the same again replaces what it said before, open: one
 * source is one item, however often it repeats itself. */
knowledge_store_add_testimony :: proc(self: ^Knowledge_Store, t: Testimony) {
	i: uint

	for i = 0; i < self.ntestimony; i += 1 {
		if self.testimony[i].thing == t.thing && self.testimony[i].container == t.container &&
		   self.testimony[i].source == t.source && self.testimony[i].settled == 0 {
			self.testimony[i] = t
			return
		}
	}
	knowledge_store_append_testimony(self, t)
}


knowledge_store_trust_in :: proc(self: ^Knowledge_Store, referentID: u32) -> i32 {
	r: ^Referent
	trusting: i64
	trust: i32

	r = knowledge_store_referent(self, referentID)
	trusting = 0
	if self.world != nil do world_get_field(self.world, "Agent.trusting", self.agent, &trusting)   /* nil answered nothing */
	trust = (r.trust + r.loyalty / 10 if r != nil else BG_TRUST) + i32(trusting)
	return BG_TRUST_LIMIT if trust > BG_TRUST_LIMIT else (-BG_TRUST_LIMIT if trust < -BG_TRUST_LIMIT else trust)
}


knowledge_store_loyalty_to :: proc(self: ^Knowledge_Store, referentID: u32) -> i32 {
	r: ^Referent

	r = knowledge_store_referent(self, referentID)
	return r.loyalty if r != nil else 0
}


knowledge_store_adjust_trust_in :: proc(self: ^Knowledge_Store, referentID: u32, delta: i32) {
	r: ^Referent

	r = knowledge_store_mutable_referent(self, referentID)
	if r == nil do return
	r.trust += delta
	if r.trust > BG_TRUST_LIMIT do r.trust = BG_TRUST_LIMIT
	if r.trust < -BG_TRUST_LIMIT do r.trust = -BG_TRUST_LIMIT
}


knowledge_store_weight_of :: proc(self: ^Knowledge_Store, t: ^Testimony) -> i32 {
	source: i32
	root: i32

	source = knowledge_store_trust_in(self, t.source)
	#partial switch t.attribution {
	case .Heard_From:
		root = knowledge_store_trust_in(self, t.root)
		return (source if source < root else root) - BG_HEARSAY
	case .Heard:
		return source - BG_RUMOUR
	case .Pledged:
		return source
	case:
		return t.sure if t.sure < source else source
	}
}


/* What counts toward credence now: open or seen true, and not a promise. */
@(private)
know_counts :: proc(t: ^Testimony, thing: u32, container: u32) -> bool {
	return t.thing == thing && t.container == container && t.settled >= 0 && t.attribution != .Pledged
}


/* Grouped by perceived root, the strongest of each group counts; testimony
 * whose root is unknown is a group of its own. */
knowledge_store_credence_that :: proc(self: ^Knowledge_Store, thing: u32, container: u32) -> i32 {
	t: ^Testimony
	i: uint
	j: uint
	credence: i32
	best: i32
	w: i32

	credence = BG_PRIOR
	for i = 0; i < self.ntestimony; i += 1 {
		t = &self.testimony[i]
		if !know_counts(t, thing, container) do continue
		if t.root != 0 {
			for j = 0; j < i; j += 1 {
				if know_counts(&self.testimony[j], thing, container) && self.testimony[j].root == t.root do break
			}
			if j < i do continue      /* its group is counted already */
		}
		best = knowledge_store_weight_of(self, t)
		for j = i + 1; t.root != 0 && j < self.ntestimony; j += 1 {
			if know_counts(&self.testimony[j], thing, container) && self.testimony[j].root == t.root {
				w = knowledge_store_weight_of(self, &self.testimony[j])
				if w > best do best = w
			}
		}
		credence += best
	}
	return credence
}


knowledge_store_strongest_that :: proc(self: ^Knowledge_Store, thing: u32, container: u32) -> ^Testimony {
	best: ^Testimony
	i: uint

	best = nil
	for i = 0; i < self.ntestimony; i += 1 {
		if know_counts(&self.testimony[i], thing, container) &&
		   (best == nil || knowledge_store_weight_of(self, &self.testimony[i]) > knowledge_store_weight_of(self, best)) {
			best = &self.testimony[i]
		}
	}
	return best
}


// -describeLooks: false where the Objective-C returned nil.
knowledge_store_describe_looks :: proc(self: ^Knowledge_Store, referentID: u32) -> (string, bool) #optional_ok {
	r: ^Referent
	features: string
	kept: [dynamic]string
	pairs: []string
	i: int

	r = knowledge_store_referent(self, referentID)
	if r == nil || r.kind == nil do return "", false
	/* how it looks, not what it is doing: free hands come and go */
	features = knowledge_store_recall(self, r)
	pairs = split_top_level(features) if len(features) != 0 else []string{}
	kept = make([dynamic]string, context.temp_allocator)
	for i = 0; i < len(pairs); i += 1 {
		if !ns_has_prefix(pairs[i], "freeHands:") do append(&kept, pairs[i])
	}
	if len(kept) == 0 do return strings.clone(string(r.kind), context.temp_allocator), true
	return fmt.tprintf("%s & {{ %s }}", r.kind, strings.join(kept[:], ", ", context.temp_allocator)), true
}


/* --- what it can say ------------------------------------------------------------- */

knowledge_store_describe_here :: proc(self: ^Knowledge_Store, c: ^Referent) -> string {
	features: string

	features = knowledge_store_recall(self, c)
	return fmt.tprintf("%s & {{ place: #OnTile & {{ x: %d, y: %d, level: %d }}%s }}", c.kind, c.x, c.y,
	                   c.level, fmt.tprintf(", %s", features) if len(features) != 0 else "")
}


// -claimThat:isIn:attribution:when: (the referents themselves; never nil,
// its callers having checked both have a kind).
knowledge_store_claim_that_is_in_attribution :: proc(self: ^Knowledge_Store, r: ^Referent, c: ^Referent, attribution: string, when_: i64) -> string {
	return fmt.tprintf("#IsIn & {{ what: %s, within: %s, when: %dms, attribution: %s }}",
	                   knowledge_store_describe_looks(self, r.id), knowledge_store_describe_here(self, c), when_, attribution)
}


/* how it knows the thing is where it believes: saw it, as sure as its memory
 * is strong, or heard it, from whoever its strongest testimony names */
knowledge_store_attribution_of :: proc(self: ^Knowledge_Store, r: ^Referent) -> string {
	t: ^Testimony
	from: string
	has_from: bool

	if r.toldBy == 0 do return fmt.tprintf("#Saw & {{ sure: %d }}", knowledge_store_strength_of(self, r.id))
	t = knowledge_store_strongest_that(self, r.id, r.container)
	if t != nil && t.root != 0 do from, has_from = knowledge_store_describe_looks(self, t.root)
	return fmt.tprintf("#Heard & {{ from: %s }}", from) if has_from else "#Heard"
}


knowledge_store_claim_about :: proc(self: ^Knowledge_Store, thing: u32) -> (string, bool) #optional_ok {
	r: ^Referent
	c: ^Referent

	r = knowledge_store_referent(self, thing)
	c = knowledge_store_referent(self, r.container) if r != nil && r.present && r.form == .Held_By else nil
	if c != nil && c.kind != nil && string(c.kind) == "#Agent" && r.kind != nil {
		return fmt.tprintf("#IsHeld & {{ what: %s, holder: %s, when: %dms, attribution: %s }}",
		                   knowledge_store_describe_looks(self, r.id), knowledge_store_describe_looks(self, c.id), r.seen,
		                   knowledge_store_attribution_of(self, r)), true
	}
	c = knowledge_store_referent(self, r.container) if r != nil && r.present && r.form == .In else nil
	if c == nil || c.form != .On_Tile || r.kind == nil || c.kind == nil do return "", false
	return knowledge_store_claim_that_is_in_attribution(self, r, c, knowledge_store_attribution_of(self, r), r.seen), true
}


knowledge_store_claim_that :: proc(self: ^Knowledge_Store, thing: u32, container: u32) -> (string, bool) #optional_ok {
	r: ^Referent
	c: ^Referent

	r = knowledge_store_referent(self, thing)
	c = knowledge_store_referent(self, container)
	if r == nil || c == nil || r.kind == nil || c.kind == nil || c.form != .On_Tile do return "", false
	if r.present && r.form == .In && r.container == container do return knowledge_store_claim_about(self, thing)
	return knowledge_store_claim_that_is_in_attribution(self, r, c, fmt.tprintf("#Saw & {{ sure: %d }}", BG_SEEN),
	                                                    world_time(self.world).ms if self.world != nil else 0), true
}


knowledge_store_writing_about :: proc(self: ^Knowledge_Store, thing: u32) -> (string, bool) #optional_ok {
	claim, ok := knowledge_store_claim_about(self, thing)
	if _, looks := knowledge_store_describe_looks(self, self.self); !ok || !looks do return "", false
	return fmt.tprintf("#Writing & {{ author: %s, entries: [%s] }}", knowledge_store_describe_looks(self, self.self), claim), true
}


knowledge_store_ownership_of :: proc(self: ^Knowledge_Store, thing: u32, owner: u32) -> (string, bool) #optional_ok {
	if _, ok := knowledge_store_describe_looks(self, thing); !ok do return "", false
	if _, ok := knowledge_store_describe_looks(self, owner); !ok do return "", false
	return fmt.tprintf("#OwnedBy & {{ what: %s, holder: %s, when: %dms, attribution: #Saw & {{ sure: %d }} }}",
	                   knowledge_store_describe_looks(self, thing), knowledge_store_describe_looks(self, owner),
	                   world_time(self.world).ms if self.world != nil else 0, BG_SEEN), true
}


knowledge_store_statement_of_law :: proc(self: ^Knowledge_Store, i: uint) -> (string, bool) #optional_ok {
	law: ^Known_Law

	law = knowledge_store_law_at(self, i)
	if law == nil do return "", false
	return fmt.tprintf("#LawSays & {{ law: #Law & {{ forbids: \"%s\", wrong: %s, brings: %s, weighs: %d }} }}",
	                   law.forbids, law.wrong, law.brings, law.weighs), true
}


knowledge_store_grievance_about :: proc(self: ^Knowledge_Store, thing: u32) -> (string, bool) #optional_ok {
	owned: ^Finding
	taken: ^Finding

	owned = knowledge_store_finding(self, "#Owned", thing)
	taken = knowledge_store_finding(self, "#Taken", thing)
	if owned == nil || taken == nil do return "", false
	if _, ok := knowledge_store_describe_looks(self, thing); !ok do return "", false
	if _, ok := knowledge_store_describe_looks(self, owned.choice); !ok do return "", false
	if _, ok := knowledge_store_describe_looks(self, taken.choice); !ok do return "", false
	return fmt.tprintf("#Grievance & {{ what: %s, holder: %s, taker: %s, when: %dms, attribution: #Saw & {{ sure: %d }} }}",
	                   knowledge_store_describe_looks(self, thing), knowledge_store_describe_looks(self, owned.choice),
	                   knowledge_store_describe_looks(self, taken.choice), taken.time, BG_SEEN), true
}


knowledge_store_reservation_of :: proc(self: ^Knowledge_Store, thing: u32, holder: u32) -> (string, bool) #optional_ok {
	if _, ok := knowledge_store_describe_looks(self, thing); !ok do return "", false
	if _, ok := knowledge_store_describe_looks(self, holder); !ok do return "", false
	return fmt.tprintf("#ReservedFor & {{ what: %s, holder: %s, when: %dms, attribution: #Saw & {{ sure: %d }} }}",
	                   knowledge_store_describe_looks(self, thing), knowledge_store_describe_looks(self, holder),
	                   world_time(self.world).ms if self.world != nil else 0, BG_SEEN), true
}


knowledge_store_promise_that_is_in :: proc(self: ^Knowledge_Store, thing: u32, container: u32, deadline: i64) -> (string, bool) #optional_ok {
	r: ^Referent
	c: ^Referent

	r = knowledge_store_referent(self, thing)
	c = knowledge_store_referent(self, container)
	if r == nil || c == nil || r.kind == nil || c.kind == nil || c.form != .On_Tile do return "", false
	return knowledge_store_claim_that_is_in_attribution(self, r, c, "#Pledged", deadline), true
}


knowledge_store_promise_that_is_held_by :: proc(self: ^Knowledge_Store, thing: u32, holder: u32, deadline: i64) -> (string, bool) #optional_ok {
	r: ^Referent
	c: ^Referent

	r = knowledge_store_referent(self, thing)
	c = knowledge_store_referent(self, holder)
	if r == nil || c == nil || r.kind == nil || c.kind == nil || string(c.kind) != "#Agent" do return "", false
	return fmt.tprintf("#IsHeld & {{ what: %s, holder: %s, when: %dms, attribution: #Pledged }}",
	                   knowledge_store_describe_looks(self, thing), knowledge_store_describe_looks(self, holder), deadline), true
}


knowledge_store_ask_where_is :: proc(self: ^Knowledge_Store, thing: u32) -> (string, bool) #optional_ok {
	looks, ok := knowledge_store_describe_looks(self, thing)
	if !ok do return "", false
	return fmt.tprintf("#WhereIs & {{ what: %s }}", looks), true
}


knowledge_store_ask_who_told_of :: proc(self: ^Knowledge_Store, thing: u32) -> (string, bool) #optional_ok {
	r: ^Referent
	c: ^Referent

	r = knowledge_store_referent(self, thing)
	c = knowledge_store_referent(self, r.container) if r != nil && r.present && r.form == .In else nil
	if c == nil || c.form != .On_Tile || c.kind == nil do return "", false
	looks, ok := knowledge_store_describe_looks(self, thing)
	if !ok do looks = "(null)"      /* %@ of nil: a thing of no kind */
	return fmt.tprintf("#WhoToldYou & {{ what: %s, within: %s }}", looks, knowledge_store_describe_here(self, c)), true
}


knowledge_store_steps_since :: proc(self: ^Knowledge_Store, t: i64) -> i32 {
	now: i64
	steps: i64

	now = world_time(self.world).ms if self.world != nil else t
	if now <= t do return 0
	steps = (now - t) / BG_MEMORY_STEP
	return 1000 if steps > 1000 else i32(steps)
}


/* The referent's features, with what an analysis found beneath them in
 * place of what they looked like. */
@(private)
know_known_features :: proc(r: ^Referent) -> string {
	out: strings.Builder
	value: string
	p: [^]u8
	pi: int
	keys: [32][32]u8
	deep: [32][32]u8
	n: uint
	m: uint
	k: uint
	j: uint
	depth: i32
	quoted: bool
	overridden: bool

	if r.deeper == nil || ([^]u8)(r.deeper)[0] == 0 {
		return strings.clone(string(r.features) if r.features != nil else "", context.temp_allocator)
	}
	n = know_feature_keys(r.features, raw_data(keys[:]), 32) if r.features != nil else 0
	m = know_feature_keys(r.deeper, raw_data(deep[:]), 32)
	out = strings.builder_make(context.temp_allocator)
	p = ([^]u8)(r.features)
	pi = 0
	for k = 0; p != nil && p[pi] != 0 && k < n; k += 1 {
		/* the pair at p, up to the next top-level comma */
		start: int

		for p[pi] == ' ' || p[pi] == ',' do pi += 1
		start = pi
		depth = 0
		quoted = false
		for ; p[pi] != 0; pi += 1 {
			if p[pi] == '"' && (pi == start || p[pi - 1] != '\\') do quoted = !quoted
			if quoted do continue
			if p[pi] == '{' || p[pi] == '[' || p[pi] == '(' {
				depth += 1
			} else if (p[pi] == '}' || p[pi] == ']' || p[pi] == ')') && depth > 0 {
				depth -= 1
			} else if p[pi] == ',' && depth == 0 {
				break
			}
		}
		for overridden, j = false, 0; j < m && !overridden; j += 1 {
			overridden = buf_text(keys[k][:]) == buf_text(deep[j][:])
		}
		if overridden do continue
		value = string(p[start:pi])
		fmt.sbprintf(&out, "%s%s", ", " if strings.builder_len(out) != 0 else "", value)
	}
	fmt.sbprintf(&out, "%s%s", ", " if strings.builder_len(out) != 0 else "", r.deeper)
	return strings.to_string(out)
}


/* Each feature generalized a step along its primary parent for each memory
 * step since the referent was seen, as strength fades (KNOWLEDGE.md decision
 * 16): slower for what was seen again and again, or salient; one
 * generalized as far as it goes is forgotten. */
knowledge_store_recall :: proc(self: ^Knowledge_Store, r: ^Referent) -> string {
	known: string
	sightings: i32
	salience: i32
	steps: i32

	if r.features == nil do return ""
	known = know_known_features(r)
	sightings = 1 if r.sightings < 1 else (7 if r.sightings > 7 else r.sightings)
	salience = r.salience if r.salience > BG_NOTICE else BG_NOTICE
	steps = i32(i64(knowledge_store_steps_since(self, r.seen)) * 2 * BG_NOTICE / i64((1 + sightings) * salience))
	if steps == 0 || len(known) == 0 || r.kind == nil do return known
	return knowledge_store_generalize(self, known, r.kind, steps)
}


knowledge_store_generalize :: proc(self: ^Knowledge_Store, known: string, kind: cstring, steps: i32) -> string {
	node: ^tri.Node
	part: ^tri.Node
	full: ^tri.Node
	out: strings.Builder
	content: ^tri.Content
	arena: ^tri.Arena
	nkeys: uint
	k: uint
	keys: [32][32]u8
	a: [512]u8
	b: [512]u8

	content = world_tri(self.world)
	arena = tri.arena_new()
	node = tri.value(content, ns_utf8(fmt.tprintf("%s & {{ %s }}", kind, known)), arena, nil, 0)
	if node == nil {
		tri.arena_free(arena)
		return known
	}
	out = strings.builder_make(context.temp_allocator)
	nkeys = know_feature_keys(ns_utf8(known), raw_data(keys[:]), 32)
	for k = 0; k < nkeys; k += 1 {
		key := cstring(raw_data(keys[k][:]))
		part = tri.generalize(content, node, key, steps, arena)
		full = tri.generalize(content, node, key, 1000, arena)
		if part == nil || full == nil || tri.at(content, part, key) == nil || tri.at(content, full, key) == nil do continue
		tri.print(content, tri.at(content, part, key), raw_data(a[:]), size_of(a))
		tri.print(content, tri.at(content, full, key), raw_data(b[:]), size_of(b))
		if buf_text(a[:]) == buf_text(b[:]) do continue      /* forgotten */
		fmt.sbprintf(&out, "%s%s: %s", ", " if strings.builder_len(out) != 0 else "", key, buf_text(a[:]))
	}
	tri.arena_free(arena)
	return strings.to_string(out)
}


knowledge_store_strength_of :: proc(self: ^Knowledge_Store, referentID: u32) -> i32 {
	r := knowledge_store_referent(self, referentID)
	if r == nil do return BG_PRIOR
	return knowledge_store_strength_of_referent(self, r)
}


/* As strengthOf, for a referent in hand: no lookup. */
knowledge_store_strength_of_referent :: proc(self: ^Knowledge_Store, r: ^Referent) -> i32 {
	base: i32
	sightings: i32
	salience: i32

	base = BG_SEEN
	if r.toldBy != 0 && r.form == .In do base = knowledge_store_credence_that(self, r.id, r.container)
	/* seen once, nothing salient: BG_FADE a step; slower for repetition and salience */
	sightings = 1 if r.sightings < 1 else (7 if r.sightings > 7 else r.sightings)
	salience = r.salience if r.salience > BG_NOTICE else BG_NOTICE
	return base - i32(i64(BG_FADE) * i64(knowledge_store_steps_since(self, r.seen)) * 2 * BG_NOTICE / i64((1 + sightings) * salience))
}


knowledge_store_forgetting_of :: proc(self: ^Knowledge_Store, referentID: u32) -> i64 {
	r: ^Referent
	base: i64
	rate: i64
	over: i64
	steps: i64
	sightings: i32
	salience: i32

	r = knowledge_store_referent(self, referentID)
	if r == nil || !r.present || r.id == self.self do return max(i64)
	base = BG_SEEN
	if r.toldBy != 0 && r.form == .In do base = i64(knowledge_store_credence_that(self, r.id, r.container))
	/* the strength after n steps is base - floor(n * rate / over) (strengthOf):
	 * below BG_BELIEVE from the first n with n * rate >= (base - BG_BELIEVE + 1) * over */
	sightings = 1 if r.sightings < 1 else (7 if r.sightings > 7 else r.sightings)
	salience = r.salience if r.salience > BG_NOTICE else BG_NOTICE
	rate = i64(BG_FADE) * 2 * BG_NOTICE
	over = i64(1 + sightings) * i64(salience)
	if base < BG_BELIEVE do return r.seen
	steps = ((base - BG_BELIEVE + 1) * over + rate - 1) / rate
	return r.seen + steps * BG_MEMORY_STEP
}


knowledge_store_next_id :: proc(self: ^Knowledge_Store) -> u32 {
	return self.next
}


// -setNextID:self:
knowledge_store_set_next_id :: proc(self: ^Knowledge_Store, next: u32, selfReferent: u32) {
	self.next = next
	self.self = selfReferent
}


knowledge_store_set_next_serial :: proc(self: ^Knowledge_Store, serial: u64) {
	self.serial = serial
}


knowledge_store_set_self :: proc(self: ^Knowledge_Store, selfReferent: u32) {
	self.self = selfReferent
}


knowledge_store_parsed :: proc(self: ^Knowledge_Store, text: string) -> ^tri.Node {
	node: ^tri.Node

	if self.arena == nil {
		self.arena = tri.arena_new()
		self.parsed = make(map[string]^tri.Node)
		self.used = make(map[string]struct{})
	}
	if text not_in self.used do self.used[strings.clone(text)] = {}
	if v, ok := self.parsed[text]; ok do return v
	node = tri.value(world_tri(self.world), ns_utf8(text), self.arena, nil, 0)
	if node != nil do self.parsed[strings.clone(text)] = node
	return node
}


knowledge_store_compact :: proc(self: ^Knowledge_Store, always: bool) -> bool {
	parsed: map[string]^tri.Node
	texts: [dynamic]string
	arena: ^tri.Arena
	node: ^tri.Node

	if self.arena == nil || (!always && uint(tri.arena_bytes(self.arena)) <= 2 * (self.liveBytes if self.liveBytes > 4096 else 4096)) do return false
	arena = tri.arena_new()
	parsed = make(map[string]^tri.Node)
	texts = make([dynamic]string, 0, len(self.used), context.temp_allocator)
	for text in self.used do append(&texts, text)
	slice.sort_by(texts[:], proc(a, b: string) -> bool { return ns_compare(a, b) < 0 })
	for text in texts {
		node = self.parsed[text]
		if node != nil do parsed[strings.clone(text)] = tri.copy_node(world_tri(self.world), node, arena)
	}
	tri.arena_free(self.arena)
	for text in self.parsed do delete(text)
	delete(self.parsed)
	self.arena = arena
	self.parsed = parsed
	self.liveBytes = uint(tri.arena_bytes(arena))
	for text in self.used do delete(text)
	clear(&self.used)
	self.compactions += 1
	return true
}


knowledge_store_compactions :: proc(self: ^Knowledge_Store) -> uint {
	return self.compactions
}


// -suppose:about:mass: (its callers never pass nil overrides)
knowledge_store_suppose :: proc(self: ^Knowledge_Store, overrides: string, referentID: u32, permille: i32) {
	r: ^Referent
	h: int

	r = knowledge_store_mutable_referent(self, referentID)
	if r == nil do return
	for h = 0; h < BG_HYPOTHESES && r.supposed[h] != nil && string(r.supposed[h]) != overrides; h += 1 {
	}
	if h == BG_HYPOTHESES do return
	if r.supposed[h] == nil do r.supposed[h] = strdup(overrides)
	r.supposedMass[h] = permille
}


knowledge_store_drop_supposed :: proc(self: ^Knowledge_Store, referentID: u32) {
	r: ^Referent
	h: int

	r = knowledge_store_mutable_referent(self, referentID)
	if r == nil do return
	for h = 0; h < BG_HYPOTHESES; h += 1 {
		delete(r.supposed[h])
		r.supposed[h] = nil
		r.supposedMass[h] = 0
	}
}


knowledge_store_hypotheses_of :: proc(self: ^Knowledge_Store, referentID: u32) -> uint {
	r: ^Referent
	h: uint

	r = knowledge_store_referent(self, referentID)
	for h = 0; r != nil && h < BG_HYPOTHESES && r.supposed[h] != nil; h += 1 {
	}
	return h if r != nil else 0
}


knowledge_store_overrides_of :: proc(self: ^Knowledge_Store, referentID: u32, h: uint) -> cstring {
	return knowledge_store_referent(self, referentID).supposed[h] if h < knowledge_store_hypotheses_of(self, referentID) else nil
}


knowledge_store_mass_of :: proc(self: ^Knowledge_Store, referentID: u32, h: uint) -> i32 {
	return knowledge_store_referent(self, referentID).supposedMass[h] if h < knowledge_store_hypotheses_of(self, referentID) else 0
}


knowledge_store_supposed_mass_of :: proc(self: ^Knowledge_Store, referentID: u32) -> i32 {
	h: uint
	sum: i32

	for sum, h = 0, 0; h < knowledge_store_hypotheses_of(self, referentID); h += 1 {
		sum += knowledge_store_mass_of(self, referentID, h)
	}
	return sum
}


/* Described as the hypothesis has it: its overrides laid over what it
 * believes, as an analysis's findings are over looks. */
knowledge_store_describe_supposed :: proc(self: ^Knowledge_Store, referentID: u32, h: uint) -> (string, bool) #optional_ok {
	r: ^Referent
	s: string
	features: cstring
	deeper: cstring

	r = knowledge_store_mutable_referent(self, referentID)
	if r == nil || h >= knowledge_store_hypotheses_of(self, referentID) do return "", false
	features = r.features
	deeper = r.deeper
	r.features = strdup(know_known_features(r))
	r.deeper = r.supposed[h]
	s = knowledge_store_describe_referent(self, referentID)
	delete(r.features)
	r.features = features
	r.deeper = deeper
	return s, true
}


knowledge_store_describe_referent :: proc(self: ^Knowledge_Store, referentID: u32) -> (string, bool) #optional_ok {
	r: ^Referent
	s: strings.Builder

	r = knowledge_store_referent(self, referentID)
	if r == nil do return "", false
	s = strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&s, "%s & {{ id: ref(%d)", r.kind, r.id)
	#partial switch r.form {
	case .In:
		fmt.sbprintf(&s, ", place: #Inside & {{ container: ref(%d) }}", r.container)
	case .Held_By:
		fmt.sbprintf(&s, ", place: #Held & {{ by: ref(%d), hand: %d }}", r.container, r.slot)
	case .Part_Of:
		fmt.sbprintf(&s, ", place: #Installed & {{ assembly: ref(%d), role: ", r.container)
		know_append_quoted(&s, cstring(raw_data(r.role[:])))
		fmt.sbprintf(&s, ", index: %d }}", r.slot)
	case:
		fmt.sbprintf(&s, ", place: #OnTile & {{ x: %d, y: %d, level: %d }}", r.x, r.y, r.level)
	}
	if len(knowledge_store_recall(self, r)) != 0 do fmt.sbprintf(&s, ", %s", knowledge_store_recall(self, r))
	strings.write_string(&s, " }")
	return strings.to_string(s), true
}

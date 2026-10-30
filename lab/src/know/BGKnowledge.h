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
 * kept as observations, in its referents: who moved what where, who said
 * what to whom. A claim it hears (talk.tri's #IsIn) is kept as testimony:
 * the things described are bound to its referents by recognition, or become
 * new ones, and the speaker, and the one the claim says saw it, are its
 * source and its perceived root.
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
 * the rules of content/interpret.tri run over the agent's referents, those
 * whose expertise it has; a rule whose premises hold (traces perceived on
 * the thing now, or perceived before and gone) adds its finding, with the
 * rule as its provenance.
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
 * (content/persistence.tri: a coat) may still be that one, changed: the
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
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGScheduler.h"


#define BG_SIGHT   4
#define BG_SMELL   1
#define BG_HEARING 10

#define BG_TRACE_FLOOR        30   /* a trace fainter than this goes unnoticed */
#define BG_TRACE_FLOOR_CLOSE   5   /* ... unless the agent is looking closely: investigating */

/* credence and trust, in dB */
#define BG_PRIOR         -10      /* a claim of where something is, before any testimony */
#define BG_TRUST          20      /* trust in an agent the agent has not yet tested */
#define BG_TRUST_LIMIT    30      /* trust stays within +- this */
#define BG_HEARSAY         5      /* less, for a claim heard from someone named */
#define BG_RUMOUR         10      /* less, for a claim heard from no one named */
#define BG_BELIEVE         0      /* credence at which a claim is believed */
#define BG_CONFIRMED       5      /* trust gained when a claim is seen to be true */
#define BG_REFUTED        15      /* trust lost when a claim is found false */
#define BG_SEEN           30      /* the strength of a belief of where a thing is, seen just now */
#define BG_FADE            2      /* strength lost each memory step */
#define BG_UNSTATED       INT32_MAX   /* a claim that says nothing of how sure */

#define BG_MEMORY_STEP    86400000LL  /* ms: a day */

/* salience */
#define BG_ADDRESSED      30      /* said to the agent */
#define BG_OWN_DEED       20      /* done by the agent */
#define BG_CONCERN        15      /* about something its goals concern */
#define BG_ANOMALY        25      /* against what it believes someone usually does */
#define BG_NOTICE         10      /* what an observation must reach to be kept, at rest */

#define BG_HYPOTHESES     3       /* competing hypotheses a referent holds at most */

typedef struct
{
   uint32_t         id;
   char             *kind;         /* a type expression: "#Stack" */
   char             *features;     /* "mass: 90g, material: \"iron\", ..." */
   char             *deeper;       /* what an analysis found beneath its looks: "material: \"steel\"", or NULL */
   char             *supposed[ BG_HYPOTHESES];     /* competing hypotheses (CONTENT_LANGUAGE.md §9): features in place of what it believes; packed, NULL after the last */
   int32_t          supposedMass[ BG_HYPOTHESES];  /* their credence masses, in thousandths; the belief has the rest */
   BGLocationForm   form;          /* how it was placed when last seen */
   uint32_t         container;     /* the referent it was in, held by, or part of */
   int32_t          x;             /* the tile it was on, or its holder's */
   int32_t          y;
   int32_t          level;
   int32_t          slot;
   char             role[ 16];
   int64_t          seen;          /* ms */
   int64_t          insideSeen;    /* when it last saw inside it (ms), or -1 */
   uint32_t         toldBy;        /* the referent who said it is where it is believed; 0 if seen */
   int32_t          trust;         /* dB: in what it says, if it is someone */
   BOOL             present;       /* still believed where it was last seen */
   int32_t          sightings;     /* how often it was sighted (not seen for a minute before) */
   int32_t          salience;      /* the most salient thing it was kept in an observation for */
   BGEntityID       truth;         /* developer-only */
} BGReferent;


/* What the agent perceived happen (KNOWLEDGE.md §7), in its referents. */
typedef struct
{
   int64_t          time;          /* ms */
   const char       *kind;         /* "moved", "said" */
   uint32_t         actor;         /* who did it; 0 if no referent */
   uint32_t         subject;       /* moved: what */
   uint32_t         other;         /* moved: what it went into, or who took it; said: to whom */
   char             *content;      /* said: what */
   BOOL             unbelieved;    /* said by the agent itself, which didn't believe it: a lie */
   int              salience;
   uint64_t         serial;        /* in the order observed, never reused */
} BGObservation;


/* A trace perceived: on a referent, or on the floor. */
typedef struct
{
   uint32_t         bearer;        /* referent; 0 for the floor */
   int32_t          x;             /* the floor's tile */
   int32_t          y;
   int32_t          level;
   const char       *kind;         /* interned: "fresh_paint" */
   int32_t          strength;      /* as it seemed, 1..100 */
   int64_t          seen;          /* ms */
   BOOL             present;       /* still there, as far as it knows */
   BGEntityID       truth;         /* developer-only: the trace */
} BGTraceSeen;


typedef enum
{
   BGSaw = 0,                      /* "I saw it" */
   BGHeardFrom,                    /* "I heard it from ..." */
   BGHeard,                        /* "I heard it", from no one named */
   BGPledged                       /* "I promise it", by `when` */
} BGAttribution;


/* An identity hypothesis: referent `a` may be referent `b`. */
typedef struct
{
   uint32_t         a;             /* the newer */
   uint32_t         b;
   int32_t          credence;      /* dB that they are one */
   char             paths[ 64];    /* where they differed: "coat" */
   int64_t          time;          /* ms: last weighed */
} BGIdentity;


/* What a rule concluded (KNOWLEDGE.md §9): something about a referent. */
typedef struct
{
   const char       *kind;         /* interned: a #Finding type, "#Tampered" */
   uint32_t         about;         /* referent */
   uint32_t         choice;        /* for a #Habit: the referent it usually chooses; else 0 */
   int32_t          credence;      /* dB */
   const char       *rule;         /* interned: its provenance */
   int64_t          time;          /* ms */
} BGFinding;


/* A claim heard (KNOWLEDGE.md §11's provenance item): `source` said that
 * `thing` is inside `container`, as of `when`. */
typedef struct
{
   uint32_t         thing;
   uint32_t         container;
   int64_t          when;          /* ms */
   int64_t          heard;         /* ms */
   uint32_t         source;        /* who said it */
   uint32_t         root;          /* who it says saw it, the perceived root; 0 if unknown */
   uint32_t         via;           /* the record it was read in; 0 if said */
   BGAttribution    attribution;
   int              settled;       /* 1 seen true, -1 found false, 0 open */
   int32_t          sure;          /* dB: how sure "saw" says it is, or BG_UNSTATED */
   uint64_t         utterance;     /* developer-only: the said event, for its true ancestry */
} BGTestimony;


/* Developer-only: where a claim said truly came from. */
typedef struct
{
   uint64_t         utterance;     /* the said event */
   BGEntityID       speaker;
   BGEntityID       origin;        /* who saw it first, or made it up */
   uint64_t         parent;        /* the said event the speaker had it from, if `relayed` */
   BOOL             relayed;
   BOOL             fabricated;    /* nobody saw it: `origin` made it up */
} BGAncestry;


@interface BGKnowledgeStore : NSObject
{
   BGWorld          *_world;         /* not retained: for the time memory decays by */
   BGEntityID       _agent;
   uint32_t         _self;
   BGReferent       *_referents;
   NSUInteger       _count;
   NSUInteger       _capacity;
   uint32_t         _next;
   int64_t          _seenAt[ 32 * 32];
   NSMutableArray   *_news;          /* what perception changed, this boundary */
   BGObservation    *_observations;
   NSUInteger       _nobservations;
   NSUInteger       _ocapacity;
   uint64_t         _serial;         /* the next observation's */
   BGTestimony      *_testimony;
   NSUInteger       _ntestimony;
   NSUInteger       _tcapacity;
   BGTraceSeen      *_traces;
   NSUInteger       _ntraces;
   NSUInteger       _trcapacity;
   BGFinding        *_findings;
   NSUInteger       _nfindings;
   NSUInteger       _fcapacity;
   int32_t          _hunger;         /* as felt */
   int32_t          _cold;
   int32_t          _stuffy;
   int32_t          _tired;
   int32_t          _pain;
   int64_t          _feltAt;         /* ms, or -1 */
   BGIdentity       *_identities;
   NSUInteger       _nidentities;
   NSUInteger       _icapacity;
   TriArena         *_arena;         /* its knowledge arena (CONTENT_LANGUAGE.md §12): descriptions parsed */
   NSMutableDictionary *_parsed;     /* their text, to the node */
   NSMutableSet     *_used;          /* the texts parsed or used since the last compaction: what is live */
   size_t           _liveBytes;      /* the arena's bytes after the last compaction */
   NSUInteger       _compactions;
}

/* A description parsed into the store's knowledge arena, kept while it is
 * used: the same text, the same node. NULL if it doesn't parse. */
- (const TriNode *) parsed:(NSString *) text;
/* Housekeeping (CONTENT_LANGUAGE.md §12): copies the descriptions used since
 * the last compaction into a fresh arena, and frees the old; `always`, or
 * when live data is under half the arena. YES if it compacted. */
- (BOOL) compact:(BOOL) always;
- (NSUInteger) compactions;

- (BGEntityID) agent;
- (uint32_t) selfReferent;
- (NSUInteger) count;
- (const BGReferent *) referentAt:(NSUInteger) i;
- (const BGReferent *) referent:(uint32_t) referentID;
/* when the agent last saw a tile, or -1 */
- (int64_t) tileSeenAtX:(int32_t) x
                      y:(int32_t) y;
/* lines saying what the last perception phase changed */
- (NSArray *) news;
/* What the agent can say (talk.tri), from what it knows, naming no
 * referents. A claim that the thing is in the container, as the agent
 * believes: where, as of when, and how it knows; nil if it believes the thing
 * nowhere inside something on the ground. */
- (NSString *) claimAbout:(uint32_t) thing;
/* A claim that the thing is in the container: the agent's own if it believes
 * so, otherwise one it makes up, saying it saw it. nil if the container is
 * not believed on the ground. */
- (NSString *) claimThat:(uint32_t) thing
                    isIn:(uint32_t) container;
/* That the thing is reserved for someone (ACTIONS.md §7). */
- (NSString *) reservationOf:(uint32_t) thing
                         for:(uint32_t) holder;
/* A promise (AGENCY.md §7): the thing will be in the container by then. */
- (NSString *) promiseThat:(uint32_t) thing
                      isIn:(uint32_t) container
                        by:(int64_t) deadline;
/* the same, that the thing will be in someone's hand: a loan to be repaid */
- (NSString *) promiseThat:(uint32_t) thing
                  isHeldBy:(uint32_t) holder
                        by:(int64_t) deadline;
/* "where is something like it?"; "who told you it is where you believe it?"
 * (nil if it believes it nowhere inside something) */
- (NSString *) askWhereIs:(uint32_t) thing;
- (NSString *) askWhoToldOf:(uint32_t) thing;
/* the claim about the thing, as writing for a record: a #Writing by the
 * agent, by its looks; nil if it can't say where the thing is */
- (NSString *) writingAbout:(uint32_t) thing;

/* the referent as a Triangle description, for the knowledge view, with the
 * detail memory has kept */
- (NSString *) describeReferent:(uint32_t) referentID;
/* A competing hypothesis about the referent (KNOWLEDGE.md §11): `overrides`
 * ("size: 22mm") in place of what it believes, with credence mass `permille`;
 * the belief keeps the rest. The same overrides again replace their mass;
 * past BG_HYPOTHESES, it is ignored. Seen plainly again, the doubt is gone. */
- (void) suppose:(NSString *) overrides
           about:(uint32_t) referentID
            mass:(int32_t) permille;
- (NSUInteger) hypothesesOf:(uint32_t) referentID;
/* the referent described as hypothesis `h` has it, or nil */
- (NSString *) describeSupposed:(uint32_t) referentID
                     hypothesis:(NSUInteger) h;
- (const char *) overridesOf:(uint32_t) referentID
                  hypothesis:(NSUInteger) h;
- (int32_t) massOf:(uint32_t) referentID
        hypothesis:(NSUInteger) h;
/* all its hypotheses' mass */
- (int32_t) supposedMassOf:(uint32_t) referentID;
- (void) dropSupposed:(uint32_t) referentID;
/* the features the referent keeps, as memory has them now */
- (NSString *) recall:(const BGReferent *) r;
/* memory steps since the time */
- (int) stepsSince:(int64_t) t;
/* how strongly it believes the referent is where it is believed, in dB */
- (int32_t) strengthOf:(uint32_t) referentID;
/* when the strength of where the referent is believed will fall below
 * BG_BELIEVE, as it fades now (ms); INT64_MAX if never */
- (int64_t) forgettingOf:(uint32_t) referentID;

/* what it perceived happen and kept, oldest first */
- (NSUInteger) observationCount;
- (const BGObservation *) observationAt:(NSUInteger) i;
/* the serial the next observation will have */
- (uint64_t) nextSerial;
/* when the agent last said something to the referent, or -1 */
- (int64_t) lastSaidTo:(uint32_t) referentID;

/* the traces it has perceived, first perceived first */
- (NSUInteger) traceCount;
- (const BGTraceSeen *) traceAt:(NSUInteger) i;

/* how much it feels the need, 0 to 100, as of its last perception phase:
 * "hunger", "cold", "stuffy", "tired", "pain" */
- (int32_t) feels:(const char *) need;
/* YES if it feels differently now */
- (BOOL) feelHunger:(int32_t) hunger
                 at:(int64_t) t;
- (BOOL) feelCold:(int32_t) cold;
- (BOOL) feelStuffy:(int32_t) stuffy;
- (BOOL) feelTired:(int32_t) tired;
- (BOOL) feelPain:(int32_t) pain;

/* its identity hypotheses, first made first */
- (NSUInteger) identityCount;
- (const BGIdentity *) identityAt:(NSUInteger) i;

/* the features generalized `steps` along their primary parents; those that
 * go as far as they can, dropped */
- (NSString *) generalize:(NSString *) features
                     kind:(const char *) kind
                    steps:(int) steps;

/* what it has concluded, first concluded first */
- (NSUInteger) findingCount;
- (const BGFinding *) findingAt:(NSUInteger) i;
/* the finding of that kind about the referent, or NULL */
- (const BGFinding *) finding:(const char *) kind
                        about:(uint32_t) referentID;

/* the claims it has heard, oldest first */
- (NSUInteger) testimonyCount;
- (const BGTestimony *) testimonyAt:(NSUInteger) i;
/* trust in what the referent says, in dB */
- (int32_t) trustIn:(uint32_t) referentID;
/* what the testimony adds to its group's credence, in dB, by the trust the
 * agent has in its source and root now */
- (int32_t) weightOf:(const BGTestimony *) t;
/* credence that the thing is inside the container, in dB, from what it was
 * told: BG_PRIOR if nothing */
- (int32_t) credenceThat:(uint32_t) thing
                    isIn:(uint32_t) container;
/* the open testimony that weighs most for it, or NULL */
- (const BGTestimony *) strongestThat:(uint32_t) thing
                                 isIn:(uint32_t) container;
/* the referent as a description of how it looks: "#Agent & { coat: ... }" */
- (NSString *) describeLooks:(uint32_t) referentID;

@end


/* What an agent's goals make salient (AGENCY.md §10): Triangle patterns. */
@protocol BGConcerns
- (NSArray *) concernsOf:(BGEntityID) agent;
@end


@interface BGKnowledge : NSObject <BGPerceptionPhase, BGSavedSystem>
{
   id <BGConcerns>  _concerns;         /* not retained */
   BGWorld          *_world;
   NSMutableArray   *_stores;          /* sorted by agent */
   NSUInteger       _eventsSeen;
   BOOL             _omniscient;
   int              _ambient;          /* the light where no lamp shines: 2 day, 1 dusk, 0 night */
   BOOL             _compactAlways;
   BGAncestry       *_ancestry;        /* developer-only, by utterance */
   NSUInteger       _nancestry;
   NSUInteger       _acapacity;
}

- (id) initWithWorld:(BGWorld *) world;

/* The omniscient stub (AGENCY.md §3): perception without limits, everything
 * everywhere, inside containers too. Agency run on it must behave visibly
 * differently from agency run on what agents can know. */
- (void) setOmniscient:(BOOL) flag;

/* Conditions (KNOWLEDGE.md §5), stubbed with authored values: the ambient
 * light, 2 day, 1 dusk, 0 night; a shining lamp (`#Lamp`, workshop.tri)
 * makes day within its reach. At dusk what is beyond arm's
 * reach is seen a step less precisely; at night it isn't seen, and what is
 * within it is felt a step less precisely, unless the agent just handled it. */
- (void) setAmbient:(int) light;
- (int) lightAt:(BGLocation) tile;
/* dusk, or day */
- (void) setDusk:(BOOL) flag;
/* Compact every store's knowledge arena at every boundary, not only when it
 * is half garbage: which must change nothing observable. */
- (void) setCompactAlways:(BOOL) flag;

/* what the agent's running activities demand of its attention */
- (int) attentionOf:(BGEntityID) agent;

/* who says what each agent's goals concern: agency */
- (void) setConcerns:(id <BGConcerns>) concerns;
- (id <BGConcerns>) concerns;

/* the agent's store, made when first asked for */
- (BGKnowledgeStore *) storeOf:(BGEntityID) agent;

/* everything an agent's store holds, with truth links, the true ancestry of
 * what it was told, and false corroboration flagged: the developer's view */
- (NSString *) dump:(BGEntityID) agent;

/* developer-only: the true ancestry of a claim said, or NULL */
- (const BGAncestry *) ancestryOf:(uint64_t) utterance;
/* developer-only: the claim's true root, following what it was relayed from */
- (const BGAncestry *) rootOf:(uint64_t) utterance;

@end


/* The parts of a text split at its top-level commas (outside quotes,
 * brackets, braces, and parentheses), trimmed. */
NSArray    *BGSplitTopLevel( NSString *text);
/* A #Writing's author and entries, as written. nil if it isn't one. */
NSArray    *BGWritingEntries( const char *writing, NSString **author);

/* A text as one word for a save line, and back (the result is malloced). */
NSString   *BGEncodeWord( const char *s);
char       *BGDecodeWord( const char *s);

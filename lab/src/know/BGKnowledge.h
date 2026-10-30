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
 * True ancestry is developer-only: each claim said is traced, through what
 * its speaker knew when it spoke, to whoever saw it first, or to the one who
 * made it up (a fabrication root). Speakers know their own lies: their
 * observation of saying it is marked not believed.
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGScheduler.h"


#define BG_SIGHT   4

/* credence and trust, in dB */
#define BG_PRIOR         -10      /* a claim of where something is, before any testimony */
#define BG_TRUST          20      /* trust in an agent the agent has not yet tested */
#define BG_TRUST_LIMIT    30      /* trust stays within +- this */
#define BG_HEARSAY         5      /* less, for a claim heard from someone named */
#define BG_RUMOUR         10      /* less, for a claim heard from no one named */
#define BG_BELIEVE         0      /* credence at which a claim is believed */
#define BG_CONFIRMED       5      /* trust gained when a claim is seen to be true */
#define BG_REFUTED        15      /* trust lost when a claim is found false */

typedef struct
{
   uint32_t         id;
   char             *kind;         /* a type expression: "#Stack" */
   char             *features;     /* "mass: 90g, material: \"iron\", ..." */
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
} BGObservation;


typedef enum
{
   BGSaw = 0,                      /* "I saw it" */
   BGHeardFrom,                    /* "I heard it from ..." */
   BGHeard                         /* "I heard it", from no one named */
} BGAttribution;


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
   BGAttribution    attribution;
   int              settled;       /* 1 seen true, -1 found false, 0 open */
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
   BGTestimony      *_testimony;
   NSUInteger       _ntestimony;
   NSUInteger       _tcapacity;
}

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
/* the referent as a Triangle description, for the knowledge view */
- (NSString *) describeReferent:(uint32_t) referentID;

/* what it perceived happen, oldest first */
- (NSUInteger) observationCount;
- (const BGObservation *) observationAt:(NSUInteger) i;
/* when the agent last said something to the referent, or -1 */
- (int64_t) lastSaidTo:(uint32_t) referentID;

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


@interface BGKnowledge : NSObject <BGPerceptionPhase, BGSavedSystem>
{
   BGWorld          *_world;
   NSMutableArray   *_stores;          /* sorted by agent */
   NSUInteger       _eventsSeen;
   BOOL             _omniscient;
   BGAncestry       *_ancestry;        /* developer-only, by utterance */
   NSUInteger       _nancestry;
   NSUInteger       _acapacity;
}

- (id) initWithWorld:(BGWorld *) world;

/* The omniscient stub (AGENCY.md §3): perception without limits, everything
 * everywhere, inside containers too. Agency run on it must behave visibly
 * differently from agency run on what agents can know. */
- (void) setOmniscient:(BOOL) flag;

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

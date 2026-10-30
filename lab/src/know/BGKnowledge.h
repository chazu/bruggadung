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
 * what to whom. A claim it hears (talk.tri's #IsIn) becomes a belief: the
 * things described are bound to its referents by recognition, or become new
 * ones, believed where the claim puts them, told by the speaker. Every claim
 * is believed, for now: trust and credence come later.
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGScheduler.h"


#define BG_SIGHT   4

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
} BGObservation;


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

@end


@interface BGKnowledge : NSObject <BGPerceptionPhase, BGSavedSystem>
{
   BGWorld          *_world;
   NSMutableArray   *_stores;          /* sorted by agent */
   NSUInteger       _eventsSeen;
   BOOL             _omniscient;
}

- (id) initWithWorld:(BGWorld *) world;

/* The omniscient stub (AGENCY.md §3): perception without limits, everything
 * everywhere, inside containers too. Agency run on it must behave visibly
 * differently from agency run on what agents can know. */
- (void) setOmniscient:(BOOL) flag;

/* the agent's store, made when first asked for */
- (BGKnowledgeStore *) storeOf:(BGEntityID) agent;

/* everything an agent's store holds, with truth links: the developer's view */
- (NSString *) dump:(BGEntityID) agent;

@end

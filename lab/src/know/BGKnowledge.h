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
   BOOL             present;       /* still believed where it was last seen */
   BGEntityID       truth;         /* developer-only */
} BGReferent;


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

@end


@interface BGKnowledge : NSObject <BGPerceptionPhase, BGSavedSystem>
{
   BGWorld          *_world;
   NSMutableArray   *_stores;          /* sorted by agent */
   NSUInteger       _eventsSeen;
}

- (id) initWithWorld:(BGWorld *) world;

/* the agent's store, made when first asked for */
- (BGKnowledgeStore *) storeOf:(BGEntityID) agent;

/* everything an agent's store holds, with truth links: the developer's view */
- (NSString *) dump:(BGEntityID) agent;

@end

/*
 * Proposals and proposal groups (ACTIONS.md §8). Every change to world state
 * is a proposal; a group of proposals commits atomically, all or nothing.
 *
 * A group names the entities it creates by handles (BGHandle), which become
 * IDs when it applies. A proposal can address one unit of a stack, as
 * {stack, n}: commitment splits that unit off first (automatic
 * individuation), and every proposal in the group with the same {stack, n}
 * means that same unit.
 */
#import "BGTypes.h"

#import "BGWorld.h"


typedef enum
{
   BGPhaseProcess = 0,          /* domains, processes */
   BGPhaseAction,               /* activities, inputs */
   BGPhaseSystem,               /* system operations, reactions */
   BGPhaseCount
} BGPhase;

typedef struct
{
   BGEntityID   entity;         /* an ID or a handle */
   uint32_t     unit;           /* 0: the whole entity; n: the group's n-th unit of a stack */
} BGRef;

static inline BGRef   BGWhole( BGEntityID entity)
{
   BGRef   r;

   r.entity = entity;
   r.unit   = 0;
   return( r);
}

static inline BGRef   BGUnit( BGEntityID stack, uint32_t n)
{
   BGRef   r;

   r.entity = stack;
   r.unit   = n;
   return( r);
}

typedef enum
{
   BGProposeCreate,
   BGProposeDestroy,
   BGProposeSetField,
   BGProposeMove,
   BGProposeSplit,
   BGProposeMerge,
   BGProposeAddEdge,
   BGProposeRemoveEdge,
   BGProposeEvent
} BGProposalKind;

typedef struct
{
   BGProposalKind   kind;
   BGRef            target;
   BGRef            other;      /* merge: the stack to merge into; edges: the far end; events: the other role */
   BGLocation       location;   /* create, move, split; place may be a handle */
   int64_t          value;      /* set field: the value; split: the count */
   BGEdgeKind       edge;
   const char       *name;      /* create: blueprint; set field: "Kind.field"; event: its kind; destroy: reason */
   const char       *key;       /* create: the stable key the seed derives from */
   BGEntityID       handle;     /* create, split: the new entity */
   BGLocation       expected;   /* move: where the target must still be, if `expects` */
   BOOL             expects;
} BGProposal;

extern const char   *BGPhaseNames[ BGPhaseCount];


@interface BGProposalGroup : NSObject
{
   BGPhase      _phase;
   NSString     *_source;
   BGEntityID   _actor;
   uint64_t     _weight;
   uint64_t     _cause;
   BGProposal   *_proposals;
   NSUInteger   _count;
   NSUInteger   _capacity;
   uint64_t     _handles;
   char         **_strings;
   NSUInteger   _nstrings;

   /* results, set by commitment */
   BOOL         _applied;
   NSString     *_rejection;
   uint64_t     _position;
   BGEntityID   *_ids;          /* handle n → ID */
   NSUInteger   _nids;
}

+ (instancetype) groupWithPhase:(BGPhase) phase
                         source:(NSString *) source;

- (BGPhase) phase;
- (NSString *) source;
- (uint64_t) cause;
- (void) setCause:(uint64_t) cause;
/* the agent whose action this is; its events record it */
- (BGEntityID) actor;
- (void) setActor:(BGEntityID) actor;
/* what weights it when it conflicts (ACTIONS.md decision 13): its actor's
 * value of what its operation declares; 0, unweighted */
- (uint64_t) weight;
- (void) setWeight:(uint64_t) weight;
- (NSUInteger) count;
- (const BGProposal *) proposals;
- (BGEntityID) newHandle;
/* how many handles it has given out; saves record it */
- (uint64_t) handleCount;
- (void) setHandleCount:(uint64_t) count;
- (void) addProposal:(BGProposal) proposal;

/* Creates an entity from a blueprint; its seed derives from the world seed
 * and `key`. Returns its handle. */
- (BGEntityID) create:(const char *) blueprint
                  key:(const char *) key
                   at:(BGLocation) location;
- (void) destroy:(BGRef) target
          reason:(const char *) reason;
- (void) set:(const char *) field
          of:(BGRef) target
          to:(int64_t) value;
/* a text field: the text travels as the proposal's key */
- (void) set:(const char *) field
          of:(BGRef) target
      toText:(const char *) text;
- (void) move:(BGRef) target
           to:(BGLocation) location;
/* A move that holds only if the target is still where it was: taking it
 * from there (ACTIONS.md Scenario 2, two hands, one seal). */
- (void) move:(BGRef) target
           to:(BGLocation) location
    expecting:(BGLocation) from;
/* Splits `count` units off a stack; returns the new entity's handle. */
- (BGEntityID) split:(BGRef) stack
               count:(int64_t) count
                  to:(BGLocation) location;
- (void) merge:(BGRef) target
          into:(BGRef) stack;
- (void) relate:(BGEdgeKind) edge
           from:(BGRef) from
             to:(BGRef) to;
- (void) unrelate:(BGEdgeKind) edge
             from:(BGRef) from
               to:(BGRef) to;
- (void) emit:(const char *) kind
      subject:(BGRef) subject
        other:(BGRef) other;
/* An event with an amount: the torque applied. `detail` may be NULL. */
- (void) emit:(const char *) kind
      subject:(BGRef) subject
        other:(BGRef) other
       amount:(int64_t) amount
       detail:(const char *) detail;
/* An event with a detail: what was said, for "said". `detail` must stay
 * valid (interned). */
- (void) emit:(const char *) kind
      subject:(BGRef) subject
        other:(BGRef) other
       detail:(const char *) detail;

/* --- results ------------------------------------------------------------- */

- (BOOL) applied;
- (NSString *) rejection;
- (uint64_t) position;
/* The ID a handle became, or BGNoEntity. IDs pass through unchanged. */
- (BGEntityID) idFor:(BGEntityID) handle;

/* for BGCommitter */
- (void) setApplied:(BOOL) applied
          rejection:(NSString *) rejection
           position:(uint64_t) position;
- (void) setID:(BGEntityID) entity
     forHandle:(BGEntityID) handle;

@end

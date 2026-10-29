/*
 * BGWorld — authoritative world state: the entity table and ID counter, one
 * store per component kind, locations, edges, tombstones, and the history of
 * committed events. Every mutation is journaled while a group is open, so
 * change commitment can apply a group and roll it back whole.
 *
 * Only change commitment mutates a world. Everything else reads it.
 */
#import "BGTypes.h"

#import "BGStore.h"
#import "BGContent.h"
#import "BGComponents.h"


/* What the entity table records for each live entity. */
typedef struct
{
   const char   *blueprint;     /* interned */
   uint64_t     seed;
} BGEntityInfo;

/* What remains of an entity that was destroyed, merged, or consumed. */
typedef struct
{
   const char   *blueprint;
   BGEntityID   successor;      /* merged into, or BGNoEntity */
   uint64_t     cause;          /* the event that ended it */
   char         reason[ 24];
} BGTombstone;

/* Binary relations other than location. */
typedef enum
{
   BGEdgeSplitFrom = 0,         /* new → source; many-to-one */
   BGEdgeClaimant,              /* claim → agent; many-to-one */
   BGEdgeClaimSubject,          /* claim → entity; many-to-many */
   BGEdgeKindCount
} BGEdgeKind;

typedef struct
{
   BGEdgeKind   kind;
   BGEntityID   from;
   BGEntityID   to;
} BGEdge;

/* A committed event: history, and what reactions respond to. */
typedef struct
{
   uint64_t     index;
   uint64_t     boundary;
   uint32_t     round;
   const char   *kind;          /* a static string: "created", "moved", "split", ... */
   BGEntityID   subject;
   BGEntityID   other;
   BGLocation   location;       /* for "moved" and "created": where to */
   int64_t      amount;
   const char   *detail;        /* interned: a field path, an edge kind, a reason; or NULL */
   uint64_t     cause;          /* the event this one follows from, or 0 */
   uint64_t     group;          /* the commit position of its group */
} BGEvent;

extern const char   *BGEdgeKindNames[ BGEdgeKindCount];


@interface BGWorld : NSObject
{
   BGContent      *_content;
   uint64_t       _seed;
   BGTime         _time;
   uint64_t       _boundary;
   BGEntityID     _nextID;

   NSUInteger     _nkinds;
   BGStore        **_kinds;          /* one per generated component kind */
   TriType        *_kindTypes;
   TriType        _trueType;
   BGStore        *_entities;        /* BGEntityInfo */
   BGStore        *_locations;       /* BGLocation */
   BGStore        *_tombstones;      /* BGTombstone */

   BGEdge         *_edges;           /* sorted by kind, from, to */
   NSUInteger     _nedges;
   NSUInteger     _edgeCapacity;

   BGEvent        *_events;
   NSUInteger     _nevents;
   NSUInteger     _eventCapacity;

   char           **_strings;        /* interned, sorted */
   NSUInteger     _nstrings;
   NSUInteger     _stringCapacity;

   void           *_journal;
   NSUInteger     _njournal;
   NSUInteger     _journalCapacity;
   BOOL           _open;

   TriArena       *_arena;
}

/* nil, with the reason, if the content's hash differs from the generated header's */
+ (instancetype) worldWithContent:(BGContent *) content
                             seed:(uint64_t) seed
                            error:(NSString **) error;

- (BGContent *) contentBuild;       /* not -content: in mulle-objc a selector has one signature */
- (TriContent *) tri;
- (uint64_t) seed;
- (BGTime) time;
- (void) setTime:(BGTime) time;
- (uint64_t) boundary;
- (void) setBoundary:(uint64_t) boundary;
- (BGEntityID) nextID;
/* for restoring a save: the counter, and tombstones as they were */
- (void) setNextID:(BGEntityID) nextID;
- (void) restoreTombstone:(BGTombstone) stone
                      for:(BGEntityID) entity;
- (BGStore *) entities;
- (BGStore *) tombstones;
- (NSUInteger) edgeCount;
- (const BGEdge *) edgeAt:(NSUInteger) i;

/* --- component kinds and fields ------------------------------------------- */

- (NSUInteger) kindCount;
- (NSUInteger) kindNamed:(const char *) name;            /* NSNotFound if none */
- (const BGComponentInfo *) kindInfo:(NSUInteger) kind;
- (BGStore *) storeForKind:(NSUInteger) kind;
- (const void *) record:(NSUInteger) kind
                    for:(BGEntityID) entity;
- (void) setRecord:(const void *) record
              kind:(NSUInteger) kind
               for:(BGEntityID) entity;
- (void) removeRecord:(NSUInteger) kind
                  for:(BGEntityID) entity;

/* Fields by "Kind.field", such as "Body.mass". Numbers, type IDs, booleans
 * and referents read and write as int64_t. */
- (BOOL) lookupField:(const char *) path
                kind:(NSUInteger *) kind
               field:(const BGFieldInfo **) field;
- (BOOL) getField:(const char *) path
               of:(BGEntityID) entity
            value:(int64_t *) value;
- (BOOL) setField:(const char *) path
               of:(BGEntityID) entity
            value:(int64_t) value;

/* --- entities ------------------------------------------------------------- */

- (BGEntityID) allocateID;
- (BOOL) isLive:(BGEntityID) entity;
- (const BGEntityInfo *) info:(BGEntityID) entity;
- (void) addEntity:(BGEntityID) entity
         blueprint:(const char *) blueprint
              seed:(uint64_t) seed;
/* Builds the entity's components from its blueprint, drawn from its seed.
 * NO, with the reason, if the blueprint is unknown or can't be built. */
- (BOOL) construct:(BGEntityID) entity
             error:(NSString **) error;
/* Removes every record and the location, and leaves a tombstone. */
- (void) destroy:(BGEntityID) entity
       successor:(BGEntityID) successor
           cause:(uint64_t) cause
          reason:(const char *) reason;
- (const BGTombstone *) tombstone:(BGEntityID) entity;
/* The live entity a reference stands for now: itself, or the end of its
 * tombstones' successors. BGNoEntity if it ended with no successor. */
- (BGEntityID) resolve:(BGEntityID) entity;

/* Physical entities have a Body. A stack's units are its count, and its unit
 * is its unit blueprint; an individual is one unit of its own blueprint. */
- (BOOL) isPhysical:(BGEntityID) entity;
- (BOOL) isStack:(BGEntityID) entity;
- (const char *) unitOf:(BGEntityID) entity;
- (int64_t) unitsOf:(BGEntityID) entity;
- (int64_t) massOf:(BGEntityID) entity;

/* --- locations ------------------------------------------------------------ */

- (BGLocation) locationOf:(BGEntityID) entity;
/* BGLocationNone removes it. */
- (void) setLocation:(BGLocation) location
                  of:(BGEntityID) entity;
/* Entities located at `place` in the given form, in ID order. */
- (NSUInteger) entitiesAt:(BGEntityID) place
                     form:(BGLocationForm) form
                     into:(BGEntityID *) out
                      max:(NSUInteger) max;
- (BGStore *) locations;

/* --- edges ---------------------------------------------------------------- */

- (BOOL) hasEdge:(BGEdgeKind) kind
            from:(BGEntityID) from
              to:(BGEntityID) to;
- (void) addEdge:(BGEdgeKind) kind
            from:(BGEntityID) from
              to:(BGEntityID) to;
- (void) removeEdge:(BGEdgeKind) kind
               from:(BGEntityID) from
                 to:(BGEntityID) to;
/* in ID order */
- (NSUInteger) edges:(BGEdgeKind) kind
                from:(BGEntityID) from
                into:(BGEntityID *) out
                 max:(NSUInteger) max;
- (NSUInteger) edges:(BGEdgeKind) kind
                  to:(BGEntityID) to
                into:(BGEntityID *) out
                 max:(NSUInteger) max;

/* --- claims --------------------------------------------------------------- */

/* The sum of the quantities of the claims on an entity. */
- (int64_t) claimedUnitsOf:(BGEntityID) entity;
/* Whether it is settled which units a claim covers: it has one subject, or
 * it is the only claim on its subjects and its quantity covers all their
 * units. After a split of mixed goods it is not, and that stays explicit
 * until an institution decides (§6). */
- (BOOL) claimAllocationResolved:(BGEntityID) claim;

/* --- history -------------------------------------------------------------- */

/* Appends the event, giving it the next index, which it returns. */
- (uint64_t) emit:(BGEvent) event;
- (NSUInteger) eventCount;
- (const BGEvent *) eventAt:(NSUInteger) i;

/* --- groups --------------------------------------------------------------- */

- (void) beginGroup;
- (void) commitGroup;
- (void) rollbackGroup;
/* While a group is open: the entities it has touched, in ID order, and the
 * record a kind had for an entity before the group began. */
- (NSUInteger) touched:(BGEntityID *) out
                   max:(NSUInteger) max;
- (const void *) recordBeforeGroup:(NSUInteger) kind
                               for:(BGEntityID) entity
                           existed:(BOOL *) existed;
- (const BGEntityInfo *) infoBeforeGroup:(BGEntityID) entity;

/* --- the rest ------------------------------------------------------------- */

- (const char *) intern:(const char *) string;
/* A hash of all authoritative state, in ID order: replays compare it. */
- (uint64_t) stateHash;
/* "Body.mass=3g Stack.count=5 ..." for traces and the inspector */
- (NSString *) describeEntity:(BGEntityID) entity;

@end

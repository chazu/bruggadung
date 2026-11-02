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
#import "BGTerrain.h"


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
   BGEdgeDerivedFrom,           /* content → the content it was altered from; many-to-one */
   BGEdgeAuthorizes,            /* authorization → the content that states it */
   BGEdgeLists,                 /* a register's content → content it lists */
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
   BGEntityID   actor;          /* who did it: the agent whose action the group is, or none */
   BGLocation   location;       /* for "moved" and "created": where to */
   int64_t      amount;
   const char   *detail;        /* interned: a field path, an edge kind, a reason; or NULL */
   uint64_t     cause;          /* the event this one follows from, or 0 */
   uint64_t     group;          /* the commit position of its group */
} BGEvent;

extern const char   *BGEdgeKindNames[ BGEdgeKindCount];


/* Told when a record of a kind it watches is set or removed. */
@protocol BGRecordObserver
- (void) world:(id) world
 changedRecord:(BGEntityID) entity
          kind:(NSUInteger) kind;
@end


/* A way a region of air opens: a doorway at its room's side, the region
 * beyond (none: the outdoors), the door standing in it, if any, and the air
 * it passes now, mmol a second each way: the door's width while it is ajar,
 * nothing while it is shut, the doorway's draught with no door. */
typedef struct
{
   BGLocation   at;
   BGEntityID   beyond;
   BGEntityID   door;
   int64_t      flow;
   BOOL         open;            /* no door, or its door ajar */
} BGAirOpening;


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

   int32_t        _tilesWide;
   int32_t        _tilesHigh;
   int32_t        _levels;
   struct BGTileStocks *_stocks;     /* tile stocks (water, mL), by chunk, only where ever wet */
   BGTerrain      *_terrain;         /* what each tile is (TERRAIN.md); NULL: content has no kinds, all open */
   BGEntityID     *_roomAir;         /* each room's air, by room number; a cache */
   uint32_t       _nroomAir;
   uint64_t       _roomAirChanges;   /* the GasStore store's members and anchors moved, when it was made */
   uint64_t       _airAnchors;       /* GasStore tiles set, or undone */
   uint64_t       _roomAirDropped;   /* the terrain's rooms dropped, then */
   BOOL           _roomAirKnown;

   struct BGIndex *_onGround;        /* what stands on a tile, by its chunk; derived from the locations */
   struct BGIndex *_inPlace;         /* what is in, on, held by or part of a thing, by the thing */
   struct BGIndex *_tracesOnGround;  /* traces on the floor, by chunk */
   struct BGIndex *_tracesBorne;     /* traces on a thing, by the thing */
   struct BGIndex *_activitiesOf;    /* activities, by actor */
   struct BGIndex *_watching;        /* activities with a watch, under one key */
   struct BGIndex *_touching;        /* activities, by actor, item and destination */
   struct BGIndex *_creations;       /* the "created" events' indices, by what they created */
   struct BGReality *_reality;       /* anchors, levels of detail, leases (REALITY.md) */
   struct BGAnchorsKept *_settled;   /* the anchors as last settled, to tell what rose */
   BGEntityID     *_risen;           /* what rose from frozen since it was last taken */
   NSUInteger     _nrisen;
   NSUInteger     _risencap;
   id <BGRecordObserver> _activityObserver;   /* not retained */
   BGEntityID     *_touched;         /* entities changed since the mark, unsorted, maybe twice */
   BGLocation     *_vacated;         /* ground tiles left since the mark */
   NSUInteger     _nvacated;
   NSUInteger     _vacatedcap;
   NSUInteger     _ntouched;
   NSUInteger     _touchedcap;
   struct { const char *name; NSUInteger kind; } _kindCache[ 64];   /* kindNamed's, by the name's address */
   NSUInteger     _kindTrace;
   NSUInteger     _kindGas;
   NSUInteger     _kindActivity;
   NSUInteger     _kindAgent;
   BGEntityID     *_checkedOut;      /* sorted; not saved: saves check everything in */
   NSUInteger     _ncheckedOut;
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
/* a text field; the text is interned */
- (BOOL) setField:(const char *) path
               of:(BGEntityID) entity
             text:(const char *) text;
- (const char *) textField:(const char *) path
                        of:(BGEntityID) entity;

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
/* What stands on the ground at a tile, in entity order: returns how many,
 * filling up to max. */
- (NSUInteger) entitiesOnTile:(BGLocation) tile
                         into:(BGEntityID *) out
                          max:(NSUInteger) max;
/* What stands on the ground within `radius` tiles of a tile (corners too),
 * on its level, in entity order. A spatial query: it reads the chunks the
 * square touches, nothing else. */
- (NSUInteger) entitiesNear:(BGLocation) tile
                     radius:(int32_t) radius
                       into:(BGEntityID *) out
                        max:(NSUInteger) max;
/* What is within `radius` of a tile, all of it: on the ground there, and
 * what is in, on, held by or part of that, all the way down. Malloc'd into
 * *out, in no set order; returns how many. */
- (NSUInteger) thingsNear:(BGLocation) tile
                   radius:(int32_t) radius
                     into:(BGEntityID **) out;
/* The traces within `radius` of a tile: on the floor there, or borne by
 * what is there (thingsNear). Malloc'd into *out, in entity order. */
- (NSUInteger) tracesNear:(BGLocation) tile
                   radius:(int32_t) radius
                     into:(BGEntityID **) out;
/* An actor's activities, of every status, in entity order: returns how
 * many, filling up to max. */
- (NSUInteger) activitiesOf:(BGEntityID) actor
                       into:(BGEntityID *) out
                        max:(NSUInteger) max;
/* The same, malloc'd: *n of them; the caller frees it. */
- (BGEntityID *) copyActivitiesOf:(BGEntityID) actor
                            count:(NSUInteger *) n;
/* The activities an entity takes part in, as actor, item or destination,
 * in entity order, malloc'd: *n of them. */
- (BGEntityID *) copyActivitiesTouching:(BGEntityID) entity
                                  count:(NSUInteger *) n;
/* The activities with a watch (a holder's stock, a tile, the air), of
 * every status, in entity order. */
- (NSUInteger) watchingActivities:(BGEntityID *) out
                              max:(NSUInteger) max;
- (BGEntityID *) copyWatchingActivities:(NSUInteger *) n;
/* --- the reality bubble (REALITY.md) ---------------------------------------- */

/* The bubble's anchors, levels, and leases. */
- (struct BGReality *) reality;
/* An entity anchors the bubble, of a kind from content (the `anchors`
 * family); NO if there is none of that name. Its centre is where it stands
 * at the next boundary (settleAnchors). */
- (BOOL) setAnchor:(BGEntityID) entity
              kind:(const char *) kind;
- (void) removeAnchor:(BGEntityID) entity;
/* Each anchor's centre moved to where it stands, past its margin; leases
 * ended let go. Once a boundary. */
- (void) settleAnchors;
/* The level of detail (a BGDetail) at a tile; of an entity, where it
 * stands, or full while a lease runs, or with no place on the ground. */
- (int) detailAt:(BGLocation) tile;
- (int) detailOf:(BGEntityID) entity;
/* Contact (content's `contact`): each event from `first` between something
 * at full detail and something not leases the other to full. */
- (void) leaseContactsFrom:(NSUInteger) first;
/* What rose from frozen since the last call (the anchors moved, a lease
 * began), and what it holds: malloc'd, in entity order, each once. Its
 * activities have been told (the activity observer). */
- (BGEntityID *) takeRisen:(NSUInteger *) n;
/* The anchors as they are, taken as settled: a save restored. */
- (void) markAnchorsSettled;

/* One observer of the Activity records, told of every change (activities'
 * timers); not retained, so it unsets itself as it goes. */
- (void) setActivityObserver:(id <BGRecordObserver>) observer;
- (id <BGRecordObserver>) activityObserver;
/* The entities whose records or location changed since the last call, in
 * entity order, each once (REALITY.md decision 7: work when something
 * happens): malloc'd, *n of them; the record starts again. */
- (BGEntityID *) takeTouched:(NSUInteger *) n;
/* The ground tiles things left since the last call (moved off, or out of
 * what stood there), each as often as left: malloc'd, *n of them. */
- (BGLocation *) takeVacated:(NSUInteger *) n;
/* What is in, on, held by or part of a thing, any way, in entity order. */
- (NSUInteger) entitiesIn:(BGEntityID) place
                     into:(BGEntityID *) out
                      max:(NSUInteger) max;
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

/* --- tiles ---------------------------------------------------------------- */

/* The map: 32 × 32 tiles on one level, unless a terrain map says otherwise.
 * Tiles hold stocks; water is the first, kept per chunk only where a tile
 * was ever wet. A tile outside the map holds nothing and takes nothing. */
- (BOOL) isTileX:(int32_t) x
               y:(int32_t) y
           level:(int32_t) level;
- (int64_t) waterAtX:(int32_t) x
                   y:(int32_t) y
               level:(int32_t) level;
/* Only a domain checking in, or a save being restored, writes a tile stock
 * directly; at rest, stocks change through commitment. */
- (void) setWater:(int64_t) water
              atX:(int32_t) x
                y:(int32_t) y
            level:(int32_t) level;
/* the water in tiles whose stock is at rest */
- (int64_t) totalTileWater;
/* The tiles holding water, by level, then row, then column: returns how
 * many, filling up to max. Costs what is wet, not the map. */
- (NSUInteger) wetTiles:(int32_t (*)[ 3]) out
                    max:(NSUInteger) max;
- (BOOL) isTileCheckedOutX:(int32_t) x
                         y:(int32_t) y
                     level:(int32_t) level;
- (void) setTileCheckedOut:(BOOL) flag
                         x:(int32_t) x
                         y:(int32_t) y
                     level:(int32_t) level;

/* --- terrain (TERRAIN.md) ---------------------------------------------------- */

/* What each tile is: open floor, unless a map was set. NULL if content
 * declares no terrain kinds. */
- (BGTerrain *) terrain;
/* Draws the world from a map in content: its terrain, and the world's extent
 * from the drawing. Only before any tile holds a stock (at setup, or
 * restoring); NO with the reason otherwise, or if the map is malformed. */
- (BOOL) setTerrainMap:(const char *) map
                 error:(NSString **) error;
/* A cell's kind by name, journaled like any change while a group is open:
 * change commitment's, or a save restoring. NO for an unknown kind or a
 * cell outside the map. */
- (BOOL) setTerrain:(const char *) kind
                atX:(int32_t) x
                  y:(int32_t) y
              level:(int32_t) level;
- (int32_t) tilesWide;
- (int32_t) tilesHigh;
- (int32_t) levels;
/* The region of air over a tile (air.tri, TERRAIN.md step 3): the GasStore
 * whose tile is in the tile's room; none outdoors, or on a wall or doorway. */
- (BGEntityID) airRegionAt:(BGLocation) tile;
/* A room's air, by its number (BGTerrainRoomAt); none if it has none. */
- (BGEntityID) airOfRoom:(uint32_t) room;
/* The room a region of air fills: its tile's; 0 if that is in none (a
 * room opened to the outdoors). */
- (uint32_t) roomOfAir:(BGEntityID) region;
/* The ways a region of air opens (TERRAIN.md step 3): one for each doorway
 * at its room's side and each room beyond it. Returns how many; fills up to
 * max. */
- (NSUInteger) airOpeningsOf:(BGEntityID) region
                        into:(BGAirOpening *) out
                         max:(NSUInteger) max;
/* Whether a region of air is shut in: none of its doorways open (no door,
 * or the door ajar). */
- (BOOL) airIsShutIn:(BGEntityID) region;
/* Whether one region (none: the outdoors) opens to the other through a
 * doorway standing open. */
- (BOOL) airRegion:(BGEntityID) a
      opensOpenTo:(BGEntityID) b;

/* --- checkout --------------------------------------------------------------- */

/* A holder whose stock a domain has checked out: the domain's value is
 * authoritative, and commitment refuses to change the holder's. */
- (BOOL) isCheckedOut:(BGEntityID) entity;
- (void) setCheckedOut:(BOOL) flag
                   for:(BGEntityID) entity;

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
/* The index of the event that created an entity, or 0: found without
 * reading the history. */
- (uint64_t) creationOf:(BGEntityID) entity;
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

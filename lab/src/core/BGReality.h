/*
 * BGReality — the reality bubble (REALITY.md, step 2): anchors, the levels
 * of detail they give the chunks around them, and the leases contact
 * gives. Plain C: the world owns one, and asks it.
 */
#import "BGTypes.h"

#include "triangle.h"


typedef enum
{
   BGDetailFrozen   = 0,
   BGDetailAbstract = 1,
   BGDetailReduced  = 2,
   BGDetailFull     = 3
} BGDetail;

typedef struct
{
   int32_t   across;            /* chunks, any direction on its level */
   int32_t   up;                /* levels */
   int32_t   down;
} BGReach;

typedef struct BGReality   BGReality;

/* From content: the `anchors` family's kinds, and the `contact` rule. */
BGReality    *BGRealityNew( TriContent *tri);
void          BGRealityFree( BGReality *r);

const char   *BGDetailName( BGDetail detail);

/* Kinds of anchor: -1 if none is named so. */
int           BGRealityKindNamed( const BGReality *r, const char *name);
const char   *BGRealityKindName( const BGReality *r, int kind);
BGReach       BGRealityReach( const BGReality *r, int kind, BGDetail level);

/* Anchors, in entity order. Setting one again changes its kind; its centre
 * is set when it is next centred. */
BOOL          BGRealitySetAnchor( BGReality *r, BGEntityID entity, int kind);
void          BGRealityRemoveAnchor( BGReality *r, BGEntityID entity);
NSUInteger    BGRealityAnchorCount( const BGReality *r);
BGEntityID    BGRealityAnchorAt( const BGReality *r, NSUInteger i, int *kind, int32_t *cx, int32_t *cy, int32_t *z,
                                 BOOL *centred);
/* Restoring: an anchor as saved, centre and all. */
void          BGRealityRestoreAnchor( BGReality *r, BGEntityID entity, int kind, int32_t cx, int32_t cy, int32_t z,
                                      BOOL centred);
/* An anchor standing on (x, y, z): its centre moved there, if it hasn't
 * one, or has gone its kind's margin past its centre's chunk. YES if the
 * centre moved. */
BOOL          BGRealityCentre( BGReality *r, BGEntityID entity, int32_t x, int32_t y, int32_t z);

/* The level of detail of a tile: the highest any anchor's centre gives it;
 * full with no anchors at all. */
BGDetail      BGRealityDetailAt( const BGReality *r, int32_t x, int32_t y, int32_t z);

/* The anchors as they are, kept to compare with later (what rose from
 * frozen when they moved, REALITY.md step 4): malloc'd; free() it. */
typedef struct BGAnchorsKept   BGAnchorsKept;
BGAnchorsKept *BGRealityKeepAnchors( const BGReality *r);
/* The level of a chunk's tiles by the anchors kept. */
BGDetail      BGRealityDetailKept( const BGReality *r, const BGAnchorsKept *kept, int32_t x, int32_t y, int32_t z);
NSUInteger    BGRealityKeptCount( const BGAnchorsKept *kept);
/* The box of chunks an anchor's abstract reach covers (kept, or now): its
 * corners; NO if it is not centred. */
BOOL          BGRealityKeptBox( const BGReality *r, const BGAnchorsKept *kept, NSUInteger i, BGEntityID *entity,
                                int32_t *lo, int32_t *hi, BOOL *same);
/* Whether anchor i, as it is now, is as it was kept. */
BOOL          BGRealityKeptSame( const BGReality *r, const BGAnchorsKept *kept, NSUInteger i);

/* Leases: full detail until a time. A lease again keeps the later end. */
void          BGRealityLease( BGReality *r, BGEntityID entity, int64_t until);
int64_t       BGRealityLeaseOf( const BGReality *r, BGEntityID entity);
/* Lets go of the leases ended by `now`. */
void          BGRealityPrune( BGReality *r, int64_t now);
NSUInteger    BGRealityLeaseCount( const BGReality *r);
BGEntityID    BGRealityLeaseAt( const BGReality *r, NSUInteger i, int64_t *until);

/* What runs at a level (content's `levels`, REALITY.md step 3): whether its
 * agents sense only what they take part in, and the cadence their own
 * wakes are put off to (0: none). Below reduced, as reduced; full, all
 * senses and no cadence. */
BOOL          BGRealityOwnSensesAt( const BGReality *r, BGDetail level);
int64_t       BGRealityCadenceAt( const BGReality *r, BGDetail level);
/* A wake at `at`, at a level: put off to the cadence's next beat, if any. */
int64_t       BGRealityBeat( const BGReality *r, BGDetail level, int64_t at);

/* Contact: whether an event's kind counts, and how long its lease runs. */
BOOL          BGRealityIsContact( const BGReality *r, const char *kind);
int64_t       BGRealityContactLease( const BGReality *r);

uint64_t      BGRealityHash( const BGReality *r, uint64_t h);

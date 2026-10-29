/*
 * BGFluidDomain — water flowing out of stores through open taps
 * (DOMAIN_SIMULATION.md §3–9, Scenario 3). While any open tap can draw, the
 * domain forms a structure: it checks out the water of the stores it draws
 * from and delivers into (buckets, and the tiles water spills onto), and its
 * values are authoritative until it checks them back in.
 *
 * Flows are a tap's rate, in whole millilitres; the fraction of a millilitre
 * is a carry on the tap, never stock. When a store can't meet the step's
 * requests, it is shared pro rata, and the millilitres left over go one each
 * in tap-ID order, rotated by the boundary index. The horizon's next event is
 * the first step at which a store runs dry, so the scheduler puts a boundary
 * exactly there, and every tap on that store reports "exhausted" in it.
 *
 * While a store is checked out, its record mirrors the domain's value after
 * each step, for readers; commitment still refuses to change it, and the
 * conservation sum counts it once, through the domain.
 *
 * Watches are activities' (DOMAIN_SIMULATION.md §5, ACTIONS.md §5): a running
 * activity with a watchHolder is told, by a "watched" event, in the step its
 * holder's water reaches watchAtLeast; that step is part of the horizon too.
 */
#import "BGScheduler.h"


#define BG_FLUID_MAX   64

typedef struct
{
   BGEntityID   entity;         /* a WaterStore; BGNoEntity for a tile */
   int32_t      x;
   int32_t      y;
   int32_t      level;
   int64_t      water;
} BGFluidHolder;

typedef struct
{
   BGEntityID   tap;
   int          source;         /* holder indices */
   int          destination;
   int64_t      rate;           /* mL per minute */
   int64_t      carry;          /* in 1/60000 mL */
   BOOL         exhausted;
} BGFluidOutlet;


@interface BGFluidDomain : NSObject <BGDomain>
{
   BGWorld          *_world;
   BOOL             _active;
   BOOL             _reversed;
   uint64_t         _signature;
   BGFluidHolder    _holders[ BG_FLUID_MAX];
   int              _nholders;
   BGFluidOutlet    _outlets[ BG_FLUID_MAX];
   int              _noutlets;
   NSMutableArray   *_log;
   BGTime           _predicted;

   /* watches that have fired, until their activities stop watching */
   BGEntityID       _fired[ BG_FLUID_MAX];
   int              _nfired;

   /* carries of open taps, kept across check-in and forming again */
   BGEntityID       _carryTaps[ BG_FLUID_MAX];
   int64_t          _carries[ BG_FLUID_MAX];
   int              _ncarries;
}

- (id) initWithWorld:(BGWorld *) world;

/* Variant 3d: the same participants, held in the reverse order inside. */
- (void) setReversedOrder:(BOOL) flag;

/* The water it has checked out (0 at rest): the conservation identity's
 * "Σ structures" term. */
- (int64_t) checkedOutWater;
/* The exhaustion it last predicted, as a time. */
- (BGTime) predictedExhaustion;
/* Requested and granted amounts per tap per step, for the developer. */
- (NSArray *) log;

@end

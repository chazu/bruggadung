/*
 * BGThermal — the heat of solids (DOMAIN_SIMULATION.md Scenario 1): a
 * stove's iron, a room's shell (content/heat/heat.tri, ThermalBody), in whole
 * joules. Its records mirror its values after each step.
 *
 * Coupled (BGCoupledDomain): it publishes its bodies' temperatures at step
 * start, and takes heat contributions for its bodies, which it applies over
 * its next step: the atmosphere's exchange between the air and what it
 * touches, and a fire's share for its stove. A shell exchanges with the
 * outdoors, at 275 K, itself. It sleeps when nothing is in transit to it and
 * every body with an outside is within half a kelvin of it: so it wakes when
 * its contributions arrive.
 */
#import "BGScheduler.h"


typedef struct
{
   BGEntityID   entity;
   int64_t      heat;            /* J */
   int64_t      capacity;        /* J/K */
   int64_t      toOutdoors;      /* W/K */
   int64_t      carry;           /* the outdoors' exchange, J·10⁻⁶ */
   int64_t      pending;         /* contributions in transit to it, J */
} BGThermalState;


@interface BGThermal : NSObject <BGCoupledDomain>
{
   BGWorld          *_world;
   BGThermalState   *_bodies;       /* in entity order, as many as the world has */
   int              _nbodies;
   int              _bodycap;
   BOOL             _ledgered;
   int64_t          _initial;      /* J, in the bodies */
   int64_t          _inflow;       /* from the outdoors */
   int64_t          _received;     /* contributions applied */
   NSUInteger       _steps;
}

- (id) initWithWorld:(BGWorld *) world;

/* Heat in the bodies is what there was, plus what came from outdoors, plus
 * the contributions applied, exactly. */
- (BOOL) balanced;
/* Contributions applied, and held in transit, J. */
- (int64_t) received;
- (int64_t) pending;
- (NSUInteger) steps;
/* Whether a body takes part in it: not while it is part of an assembly. */
- (BOOL) participates:(BGEntityID) body;
/* A body's temperature now, in millikelvin. */
- (int64_t) temperatureOf:(BGEntityID) body;

@end

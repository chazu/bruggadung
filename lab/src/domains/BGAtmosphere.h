/*
 * BGAtmosphere — the air (DOMAIN_SIMULATION.md Scenario 1, "The unattended
 * stove"). It owns, while anything moves, the gas of each region of air
 * (content/air.tri: oxygen and carbon dioxide in whole millimoles, the heat
 * the gas carries in whole joules) and the fuel of a lit stove; their
 * records mirror its values after each step, and it checks them in when it
 * sleeps.
 *
 * Per step, in whole quanta, with carries for what is fractional:
 *
 *   - each link mixes a region with the region it opens to, or with the
 *     outdoors, a reservoir at 275 K of fixed composition: a doorway at its
 *     room's side (TERRAIN.md step 3), passing the doorway's draught, or
 *     its door's width while ajar and nothing while shut; the region's leak
 *     to the outdoors (its gap); or, its room opened to the outdoors, its
 *     airing out, a hundredth of it a second. Links are found from the
 *     terrain each time the domain reads the world, and carry gas and heat
 *     in proportion, measured from the smaller side;
 *   - a lit stove burns up to its rate (mg a second) of wood; each gram
 *     consumes 33 mmol of oxygen, produces 33 of carbon dioxide and 15 kJ of
 *     heat. Damper open, the firebox draws from the outdoors and vents up
 *     the flue, and a tenth of the heat warms the room; damper closed, it
 *     draws from the room and vents into it, smouldering as the oxygen
 *     falls below 21% and going out by 10%.
 *
 * A respirator (content/air.tri) breathes the air over it: oxygen at its
 * rate, at rest or at work, for four fifths as much carbon dioxide, and the
 * heat to its body, as a contribution.
 *
 * Coupled to the thermal domain (BGCoupledDomain): a stove's iron takes
 * three tenths of its fire's heat, and every solid with a surface to the air
 * (`toAir`, W/K) exchanges heat with it. The atmosphere computes that
 * exchange, from the solids' temperatures in the step-start snapshot, takes
 * it from the gas, and sends it as contributions; below half a kelvin it
 * rests. The exchange lags a step, so it bounds the step: an eighth of the
 * smaller side's capacity over the conductance, so a step moves no more than
 * an eighth of the way to equal.
 *
 * Regions sleep and wake one by one (§5). A link rests while what it
 * carries is within the settle tolerances (a thousandth of the region in
 * oxygen, 100 mmol of carbon dioxide, half a kelvin); a region is awake while
 * a link to it is moving, or a fire, a breather, a solid's surface, a
 * contribution, or a crossed watch is in it. A door opening or shutting
 * wakes the two regions it joins. A moving link is explicit, and bounds the
 * step: no more than an eighth of the smaller side's air through it. The domain sleeps when every region
 * does.
 *
 * The firebox is quasi-steady: it holds nothing. Every quantity balances
 * exactly: the region's gas plus what combustion consumed less what it
 * produced, less what came in from outdoors, plus what it sent the solids,
 * less what it received, is what there was (the ledger). Fuel run out is a predicted event: the stove goes out then, by
 * proposal. A rest's watch on a region's air is another: its carbon dioxide
 * rising past a level, at the rate the sources give now (never late), or its
 * temperature leaving a band, predicted at twice the rate the heat flows now
 * give and again from closer in. The domain reports it at the boundary it
 * crosses, within a second. A region settled near the
 * outdoors, with no fire, lets the domain sleep: an infinite horizon.
 */
#import "BGScheduler.h"




typedef struct
{
   BGEntityID   entity;
   int64_t      oxygen;          /* mmol */
   int64_t      dioxide;
   int64_t      heat;            /* J */
   int64_t      total;           /* mmol */
   int64_t      carryBurn[ 3];   /* combustion into the region, in mmol·mg, J·mg */
   int64_t      pending;         /* heat in transit to it, J */
   NSUInteger   steps;           /* steps it was awake for */
} BGAirRegion;


/* A way air moves between a region and what it opens to: kept by the two
 * sides and the doorway, from read to read, for its carries. */
typedef struct
{
   BGEntityID   from;            /* the smaller side, whose air it is measured by */
   BGEntityID   to;              /* the other, or BGNoEntity: the outdoors */
   BGLocation   at;              /* the doorway; none: a leak, or airing out */
   int          a;               /* their regions, as read; b -1: the outdoors */
   int          b;
   BGEntityID   door;            /* the door in it, or none */
   int64_t      flow;            /* mmol of air a second, each way */
   int          doorSeen;        /* its door, ajar or not, at the last step; -1 not yet seen */
   int64_t      carryAir;        /* mmol·ms */
   int64_t      carryIn[ 3];     /* what comes in from the other side, numerators */
   int64_t      carryOut[ 3];    /* what goes out, numerators over the total */
   BOOL         found;
} BGAirLink;


typedef struct
{
   BGEntityID   entity;
   int          region;          /* the region it stands in, or -1 */
   int64_t      fuel;            /* mg */
   int64_t      carry;           /* mg·ms */
   int64_t      carryShare;      /* its iron's share of the heat, J·10⁻¹ */
   BOOL         out;             /* its fire went out this step */
} BGStoveState;


/* A solid's surface to a region's air. */
typedef struct
{
   BGEntityID   entity;
   int          region;
   int64_t      conductance;     /* W/K */
   int64_t      carry;           /* J·10⁻⁶ */
} BGAirSurface;


/* What breathes, over a region's air. */
typedef struct
{
   BGEntityID   entity;
   int          region;
   int64_t      carry;           /* oxygen, mmol·10⁻⁶ */
   int64_t      carryDioxide;    /* fifths of a mmol */
} BGBreather;


/* What balances: per quantity, the totals a ledger adds up. */
typedef struct
{
   int64_t      initial[ 3];     /* oxygen, dioxide, heat, in the regions */
   int64_t      inflow[ 3];      /* net in from outdoors */
   int64_t      produced[ 3];    /* by combustion, into the regions */
   int64_t      consumed[ 3];    /* by combustion, from the regions */
   int64_t      fuel;            /* initial, mg */
   int64_t      burned;          /* mg */
   int64_t      exchanged;       /* heat from the gas to the solids, J */
   int64_t      toSolids;        /* combustion's heat sent to the solids */
   int64_t      received;        /* heat contributions applied to the gas */
} BGAirLedger;


@interface BGAtmosphere : NSObject <BGCoupledDomain>
{
   BGWorld        *_world;
   BOOL           _active;
   BOOL           _ledgered;
   /* each kept in entity order, as many as the world has */
   BGAirRegion    *_regions;
   int            _nregions;
   int            _regioncap;
   BGAirLink      *_links;
   int            _nlinks;
   int            _linkcap;
   BGStoveState   *_stoves;
   int            _nstoves;
   int            _stovecap;
   BGAirSurface   *_surfaces;
   int            _nsurfaces;
   int            _surfacecap;
   BGBreather     *_breathers;
   int            _nbreathers;
   int            _breathercap;
   BGAirLedger    _ledger;
   int64_t        _rise;          /* the last step's carbon dioxide rise, per second, in the first region */
   NSUInteger     _steps;
   BGEntityID     *_fired;         /* watches reported, while they still watch */
   int            _nfired;
   int            _firedcap;
}

- (id) initWithWorld:(BGWorld *) world;

/* The conservation identity, exactly, for oxygen, dioxide, heat, and fuel. */
- (BOOL) balanced;
/* Heat sent to the solids, J: exchanged and combustion's share. */
- (int64_t) sent;
/* Steps it has taken. */
- (NSUInteger) steps;
/* A region's temperature now, in millikelvin. */
- (int64_t) temperatureOf:(BGEntityID) region;
/* The steps a region was awake for. */
- (NSUInteger) stepsOf:(BGEntityID) region;

@end

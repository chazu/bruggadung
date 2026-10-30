#import "BGAtmosphere.h"

#import "BGActions.h"


/* the outdoors, a reservoir: per mille oxygen, per ten thousand carbon
 * dioxide, and the heat a millimole of its air carries at 275 K, in mJ */
#define BG_OUT_OXYGEN       210
#define BG_OUT_DIOXIDE      4
#define BG_OUT_HEAT         7975
#define BG_GAS_CAPACITY     29          /* mJ per mmol per kelvin */

/* combustion, per gram of wood */
#define BG_BURN_OXYGEN      33          /* mmol consumed */
#define BG_BURN_DIOXIDE     33          /* mmol produced */
#define BG_BURN_HEAT        15          /* J per mg */
#define BG_BURN_SHARE       3           /* tenths of it to the stove's iron */

/* breathing, per mmol of oxygen */
#define BG_BREATH_DIOXIDE   4           /* fifths of a mmol produced */
#define BG_BREATH_HEAT      448         /* J, to the body */


@implementation BGAtmosphere

- (id) initWithWorld:(BGWorld *) world
{
   if( ! (self = [super init]))
      return( nil);
   _world = [world retain];
   return( self);
}


- (void) dealloc
{
   [_world release];
   [super dealloc];
}


- (NSString *) name
{
   return( @"atmosphere");
}


- (NSUInteger) steps
{
   return( _steps);
}


- (int64_t) sent
{
   return( _ledger.exchanged + _ledger.toSolids);
}


/* --- reading the world ------------------------------------------------------------ */

- (int) regionOf:(BGEntityID) entity
{
   int   i;

   for( i = 0; i < _nregions; i++)
      if( _regions[ i].entity == entity)
         return( i);
   if( _nregions == BG_ATMOS_REGIONS || ! [_world record:[_world kindNamed:"GasStore"] for:entity])
      return( -1);
   memset( &_regions[ _nregions], 0, sizeof( BGAirRegion));
   _regions[ _nregions].entity   = entity;
   _regions[ _nregions].link     = -1;
   _regions[ _nregions].doorSeen = -1;
   return( _nregions++);
}


- (int) stoveOf:(BGEntityID) entity
{
   int   i;

   for( i = 0; i < _nstoves; i++)
      if( _stoves[ i].entity == entity)
         return( i);
   if( _nstoves == BG_ATMOS_STOVES)
      return( -1);
   memset( &_stoves[ _nstoves], 0, sizeof( BGStoveState));
   _stoves[ _nstoves].entity = entity;
   _stoves[ _nstoves].fuel   = -1;
   return( _nstoves++);
}


- (int) surfaceOf:(BGEntityID) entity
{
   int   i;

   for( i = 0; i < _nsurfaces; i++)
      if( _surfaces[ i].entity == entity)
         return( i);
   if( _nsurfaces == BG_ATMOS_SURFACES)
      return( -1);
   memset( &_surfaces[ _nsurfaces], 0, sizeof( BGAirSurface));
   _surfaces[ _nsurfaces].entity = entity;
   return( _nsurfaces++);
}


- (int) breatherOf:(BGEntityID) entity
{
   int   i;

   for( i = 0; i < _nbreathers; i++)
      if( _breathers[ i].entity == entity)
         return( i);
   if( _nbreathers == BG_ATMOS_BREATHERS)
      return( -1);
   memset( &_breathers[ _nbreathers], 0, sizeof( BGBreather));
   _breathers[ _nbreathers].entity = entity;
   return( _nbreathers++);
}


/* The regions' and stoves' values from their records, which mirror ours;
 * a stove not burning takes its fuel from its record. A solid's surface is
 * to the air over it, or, with no place, the air it bounds. */
- (void) load
{
   const BGGasStore        *air;
   const BGCombustor       *combustor;
   const BGFuelContainer   *fuel;
   const BGThermalBody     *body;
   const BGDoor            *door;
   BGStore                 *stores;
   NSUInteger              i;
   int                     k;

   stores = [_world storeForKind:[_world kindNamed:"GasStore"]];
   for( i = 0; i < [stores count]; i++)
   {
      air = [stores recordAtIndex:i];
      if( (k = [self regionOf:[stores entityAtIndex:i]]) < 0)
         continue;
      _regions[ k].oxygen  = air->oxygen;
      _regions[ k].dioxide = air->dioxide;
      _regions[ k].heat    = air->gasHeat;
      _regions[ k].total   = air->total;
   }
   /* the links: a gap, or a door's width while it is ajar */
   for( i = 0; i < [stores count]; i++)
   {
      air = [stores recordAtIndex:i];
      if( (k = [self regionOf:[stores entityAtIndex:i]]) < 0)
         continue;
      _regions[ k].link = air->opensTo ? [self regionOf:(BGEntityID) air->opensTo] : -1;
      _regions[ k].flow = air->gap;
      door              = air->door ? [_world record:[_world kindNamed:"Door"] for:(BGEntityID) air->door] : NULL;
      if( door && door->ajar)
         _regions[ k].flow = door->wide;
      if( _regions[ k].doorSeen < 0)
         _regions[ k].doorSeen = door ? door->ajar : 0;
   }
   stores = [_world storeForKind:[_world kindNamed:"Combustor"]];
   for( i = 0; i < [stores count]; i++)
   {
      combustor = [stores recordAtIndex:i];
      fuel      = [_world record:[_world kindNamed:"FuelContainer"] for:[stores entityAtIndex:i]];
      if( ! fuel || (k = [self stoveOf:[stores entityAtIndex:i]]) < 0)
         continue;
      if( ! combustor->lit || _stoves[ k].fuel < 0)
         _stoves[ k].fuel = fuel->fuel * 1000;
      _stoves[ k].region = [self regionOf:BGAirOver( _world, [stores entityAtIndex:i])];
   }
   stores = [_world storeForKind:[_world kindNamed:"ThermalBody"]];
   for( i = 0; i < [stores count]; i++)
   {
      body = [stores recordAtIndex:i];
      if( ! body->toAir || (k = [self surfaceOf:[stores entityAtIndex:i]]) < 0)
         continue;
      _surfaces[ k].conductance = body->toAir;
      _surfaces[ k].region      = [self regionOf:body->bounds ? (BGEntityID) body->bounds
                                                               : BGAirOver( _world, [stores entityAtIndex:i])];
   }
   stores = [_world storeForKind:[_world kindNamed:"Respirator"]];
   for( i = 0; i < [stores count]; i++)
      if( (k = [self breatherOf:[stores entityAtIndex:i]]) >= 0)
         _breathers[ k].region = [self regionOf:BGAirOver( _world, [stores entityAtIndex:i])];
}


/* What a breather takes now, mmol of oxygen a thousand seconds: at rest
 * while it is the actor of a running rest, else at work. */
- (int64_t) breathOf:(int) b
{
   const BGRespirator   *respirator;
   const BGActivity     *record;
   BGStore              *store;
   NSUInteger           i;

   respirator = [_world record:[_world kindNamed:"Respirator"] for:_breathers[ b].entity];
   if( ! respirator || _breathers[ b].region < 0)
      return( 0);
   store = [_world storeForKind:[_world kindNamed:"Activity"]];
   for( i = 0; i < [store count]; i++)
   {
      record = [store recordAtIndex:i];
      if( (BGEntityID) record->actorRef == _breathers[ b].entity &&
          record->status == (uint32_t) tri_type_named( [_world tri], "\"running\"") &&
          [BGOperationEffect( _world, [_world textField:"Activity.operation" of:[store entityAtIndex:i]])
             isEqualToString:@"rest"])
         return( respirator->atRest);
   }
   return( respirator->atWork);
}


- (BOOL) lit:(int) s
{
   const BGCombustor   *combustor;

   combustor = [_world record:[_world kindNamed:"Combustor"] for:_stoves[ s].entity];
   return( combustor && combustor->lit && _stoves[ s].fuel > 0);
}


/* What the stove burns now, mg a second: its rate, or, damper closed, what
 * the room's oxygen allows: all of it at 21%, nothing at 10%. */
- (int64_t) rateOf:(int) s
{
   const BGCombustor   *combustor;
   BGAirRegion         *r;
   int64_t             permille;

   combustor = [_world record:[_world kindNamed:"Combustor"] for:_stoves[ s].entity];
   if( ! combustor || ! [self lit:s])
      return( 0);
   if( combustor->damper || _stoves[ s].region < 0)
      return( combustor->burnRate);
   r        = &_regions[ _stoves[ s].region];
   permille = r->oxygen * 1000 / r->total - 100;
   if( permille <= 0)
      return( 0);
   if( permille > 110)
      permille = 110;
   return( combustor->burnRate * permille / 110);
}


static int64_t   gasTemperature( const BGAirRegion *r)
{
   return( r->heat * 1000000 / (r->total * BG_GAS_CAPACITY));
}


/* How far a surface's air is above the solid, mK, from their records; 0
 * below half a kelvin, where the exchange rests. */
- (int64_t) surfaceDelta:(int) i
                capacity:(int64_t *) capacity
{
   const BGThermalBody   *body;
   const BGAirRegion     *r;
   int64_t               d;

   body = [_world record:[_world kindNamed:"ThermalBody"] for:_surfaces[ i].entity];
   if( ! body || _surfaces[ i].region < 0)
      return( 0);
   r = &_regions[ _surfaces[ i].region];
   d = gasTemperature( r) - body->heat * 1000 / body->heatCapacity;
   if( capacity)
      *capacity = r->total * BG_GAS_CAPACITY / 1000 < body->heatCapacity ? r->total * BG_GAS_CAPACITY / 1000
                                                                           : body->heatCapacity;
   return( llabs( d) < 500 ? 0 : d);
}


static int64_t   quantity( const BGAirRegion *r, int q)
{
   return( q == 0 ? r->oxygen : q == 1 ? r->dioxide : r->heat);
}


/* What a mmol of air across a region's link carries, as a fraction: the
 * outdoors' fixed air, or the other region's. */
static void   across( const BGAirRegion *regions, int k, int q, int64_t *num, int64_t *den)
{
   static const int64_t   outNum[ 3] = { BG_OUT_OXYGEN, BG_OUT_DIOXIDE, BG_OUT_HEAT };
   static const int64_t   outDen[ 3] = { 1000, 10000, 1000 };

   if( regions[ k].link < 0)
   {
      *num = outNum[ q];
      *den = outDen[ q];
      return;
   }
   *num = quantity( &regions[ regions[ k].link], q);
   *den = regions[ regions[ k].link].total;
}


/* Whether a region's link rests: nothing flows, or what it would carry is
 * within the settle tolerances, and its door is as it was. */
- (BOOL) linkQuiet:(int) k
            values:(const BGAirRegion *) v
{
   const BGGasStore   *air;
   const BGDoor       *door;
   int64_t            num;
   int64_t            den;
   int64_t            tolerance[ 3];
   int                q;

   air  = [_world record:[_world kindNamed:"GasStore"] for:v[ k].entity];
   door = air && air->door ? [_world record:[_world kindNamed:"Door"] for:(BGEntityID) air->door] : NULL;
   if( door && door->ajar != v[ k].doorSeen)
      return( NO);
   if( ! v[ k].flow)
      return( YES);
   tolerance[ 0] = v[ k].total / 1000;
   tolerance[ 1] = 100;
   tolerance[ 2] = v[ k].total * BG_GAS_CAPACITY / 2000;
   for( q = 0; q < 3; q++)
   {
      across( v, k, q, &num, &den);
      if( llabs( quantity( &v[ k], q) - v[ k].total * num / den) > tolerance[ q])
         return( NO);
   }
   return( YES);
}


/* Whether a region is awake: a link to it moving, or something in it. */
- (BOOL) awake:(int) k
        values:(const BGAirRegion *) v
{
   BGEntityID   watched[ 16];
   NSUInteger   n;
   NSUInteger   i;
   int          j;

   if( v[ k].pending || ! [self linkQuiet:k values:v])
      return( YES);
   for( j = 0; j < _nregions; j++)
      if( v[ j].link == k && ! [self linkQuiet:j values:v])
         return( YES);
   for( j = 0; j < _nstoves; j++)
      if( _stoves[ j].region == k && [self lit:j])
         return( YES);
   for( j = 0; j < _nbreathers; j++)
      if( _breathers[ j].region == k && [self breathOf:j])
         return( YES);
   for( j = 0; j < _nsurfaces; j++)
      if( _surfaces[ j].region == k && [self surfaceDelta:j capacity:NULL])
         return( YES);
   n = [self watches:watched max:16];
   for( i = 0; i < n; i++)
      if( [self crossedWatch] == watched[ i] &&
          [self regionWatchedBy:[_world record:[_world kindNamed:"Activity"] for:watched[ i]]] == k)
         return( YES);
   return( NO);
}


/* What the links into a region carry now, per second, in units of `unit`
 * a mmol of whatever `q` is: each moving link's flow times the difference. */
- (int64_t) linkFlowInto:(int) k
                quantity:(int) q
                    unit:(int64_t) unit
{
   int64_t   num;
   int64_t   den;
   int64_t   sum;
   int       j;

   sum = 0;
   for( j = 0; j < _nregions; j++)
   {
      if( (j != k && _regions[ j].link != k) || [self linkQuiet:j values:_regions])
         continue;
      across( _regions, j, q, &num, &den);
      if( j == k)
         sum += _regions[ k].flow * (num * unit / den - quantity( &_regions[ k], q) * unit / _regions[ k].total);
      else
         sum += _regions[ j].flow * (quantity( &_regions[ j], q) * unit / _regions[ j].total - num * unit / den);
   }
   return( sum);
}


- (NSUInteger) stepsOf:(BGEntityID) region
{
   int   i;

   for( i = 0; i < _nregions; i++)
      if( _regions[ i].entity == region)
         return( _regions[ i].steps);
   return( 0);
}


- (int64_t) temperatureOf:(BGEntityID) region
{
   int   i;

   [self load];
   for( i = 0; i < _nregions; i++)
      if( _regions[ i].entity == region)
         return( _regions[ i].heat * 1000000 / (_regions[ i].total * BG_GAS_CAPACITY));
   return( 0);
}


/* --- the domain ----------------------------------------------------------------- */

- (BOOL) isActive
{
   int   i;

   [self load];
   for( i = 0; i < _nregions; i++)
      if( [self awake:i values:_regions])
         return( YES);
   return( NO);
}


/* The activities watching a region's air, running. */
- (NSUInteger) watches:(BGEntityID *) out
                   max:(NSUInteger) max
{
   const BGActivity   *record;
   BGStore            *store;
   NSUInteger         i;
   NSUInteger         n;

   store = [_world storeForKind:[_world kindNamed:"Activity"]];
   n     = 0;
   for( i = 0; i < [store count] && n < max; i++)
   {
      record = [store recordAtIndex:i];
      if( (record->watchDioxide > 0 || record->watchCool > 0 || record->watchWarm > 0) && record->watchHolder &&
          record->status == (uint32_t) tri_type_named( [_world tri], "\"running\""))
         out[ n++] = [store entityAtIndex:i];
   }
   return( n);
}


- (int) regionWatchedBy:(const BGActivity *) record
{
   int   k;

   for( k = 0; k < _nregions && _regions[ k].entity != (BGEntityID) record->watchHolder; k++)
      ;
   return( k == _nregions ? -1 : k);
}


/* Why a running watch has fired, now: nil while its region's air is within
 * what it watches. */
- (NSString *) crossingOf:(const BGActivity *) record
{
   const BGAirRegion   *r;
   int                 k;

   if( (k = [self regionWatchedBy:record]) < 0)
      return( nil);
   r = &_regions[ k];
   if( record->watchDioxide && r->dioxide >= record->watchDioxide)
      return( [NSString stringWithFormat:@"reaches %lld mmol of carbon dioxide", (long long) r->dioxide]);
   if( record->watchCool && gasTemperature( r) < record->watchCool)
      return( [NSString stringWithFormat:@"cools to %lld mK", (long long) gasTemperature( r)]);
   if( record->watchWarm && gasTemperature( r) > record->watchWarm)
      return( [NSString stringWithFormat:@"warms to %lld mK", (long long) gasTemperature( r)]);
   return( nil);
}


/* A running watch already crossed and not yet reported: it wakes the domain. */
- (BGEntityID) crossedWatch
{
   BGEntityID   watched[ 16];
   NSUInteger   n;
   NSUInteger   i;
   int          s;

   n = [self watches:watched max:16];
   for( i = 0; i < n; i++)
   {
      for( s = 0; s < _nfired && _fired[ s] != watched[ i]; s++)
         ;
      if( s == _nfired && [self crossingOf:[_world record:[_world kindNamed:"Activity"] for:watched[ i]]])
         return( watched[ i]);
   }
   return( BGNoEntity);
}


/* The heat flowing into a region's gas now, mW: the door, the solids'
 * surfaces, and a fire venting into it. */
- (int64_t) heatFlowInto:(int) k
{
   int64_t             flow;
   int                 i;

   flow = [self linkFlowInto:k quantity:2 unit:1000];
   for( i = 0; i < _nsurfaces; i++)
      if( _surfaces[ i].region == k)
         flow -= _surfaces[ i].conductance * [self surfaceDelta:i capacity:NULL];
   for( i = 0; i < _nstoves; i++)
      if( _stoves[ i].region == k && [self lit:i] &&
          ! ((const BGCombustor *) [_world record:[_world kindNamed:"Combustor"] for:_stoves[ i].entity])->damper)
         flow += [self rateOf:i] * BG_BURN_HEAT * (10 - BG_BURN_SHARE) * 100;
   return( flow);
}


- (BGHorizon) horizonAt:(BGTime) t
{
   const BGActivity   *record;
   BGEntityID         watched[ 16];
   BGHorizon          h;
   NSUInteger         n;
   NSUInteger         i;
   int64_t            rate;
   int64_t            when;
   int                s;
   int                k;
   BOOL               burning;

   [self load];
   burning = NO;
   h.nextEvent = BGTimeNever;
   for( s = 0; s < _nstoves; s++)
   {
      if( ! [self lit:s])
         continue;
      burning = YES;
      /* the fuel runs out: at this rate, less the part of a milligram
       * already burning, or later, as a smoulder slows */
      if( (rate = [self rateOf:s]) > 0)
      {
         when = t.ms + (_stoves[ s].fuel * 1000 - _stoves[ s].carry + rate - 1) / rate;
         if( when > t.ms && when < h.nextEvent.ms)
            h.nextEvent = BGTimeMake( when);
      }
   }
   /* a watch crossing. Carbon dioxide at the rise the rates give now (mmol
    * per 1000 s): the fires venting into the region, the breathers, and the
    * door; the rise only slows as the oxygen falls, so this is never late. A
    * temperature at twice the rate the heat flows give now, and again from
    * closer in. No sooner than a second, the event tolerance; a watch
    * already crossed, at once */
   if( [self crossedWatch] != BGNoEntity)
      h.nextEvent = BGTimeMake( t.ms + 1);
   n = [self watches:watched max:16];
   for( i = 0; i < n; i++)
   {
      int64_t   rise;
      int64_t   flow;
      int64_t   capacity;
      int64_t   temperature;

      record = [_world record:[_world kindNamed:"Activity"] for:watched[ i]];
      if( (k = [self regionWatchedBy:record]) < 0 || [self crossingOf:record])
         continue;
      when = BGTimeNever.ms;
      if( record->watchDioxide)
      {
         rise = [self linkFlowInto:k quantity:1 unit:1000];
         for( s = 0; s < _nstoves; s++)
            if( _stoves[ s].region == k && [self lit:s] &&
                ! ((const BGCombustor *) [_world record:[_world kindNamed:"Combustor"] for:_stoves[ s].entity])->damper)
               rise += [self rateOf:s] * BG_BURN_DIOXIDE;
         for( s = 0; s < _nbreathers; s++)
            if( _breathers[ s].region == k)
               rise += [self breathOf:s] * BG_BREATH_DIOXIDE / 5;
         if( rise > 0)
            when = t.ms + (record->watchDioxide - _regions[ k].dioxide) * 1000000 / rise;
      }
      flow        = [self heatFlowInto:k];
      capacity    = _regions[ k].total * BG_GAS_CAPACITY / 1000;
      temperature = gasTemperature( &_regions[ k]);
      if( record->watchCool && flow < 0 &&
          t.ms + (temperature - record->watchCool) * capacity * 1000 / (-2 * flow) < when)
         when = t.ms + (temperature - record->watchCool) * capacity * 1000 / (-2 * flow);
      if( record->watchWarm && flow > 0 &&
          t.ms + (record->watchWarm - temperature) * capacity * 1000 / (2 * flow) < when)
         when = t.ms + (record->watchWarm - temperature) * capacity * 1000 / (2 * flow);
      if( when == BGTimeNever.ms)
         continue;
      if( when < t.ms + 1000)
         when = t.ms + 1000;
      if( when < h.nextEvent.ms)
         h.nextEvent = BGTimeMake( when);
   }
   h.safeStep = BGTimeMake( burning ? 600000 : 3600000);

   /* a moving link is explicit: a step carries no more than an eighth of
    * the smaller side's air */
   for( k = 0; k < _nregions; k++)
   {
      int64_t   total;

      if( ! _regions[ k].flow || [self linkQuiet:k values:_regions])
         continue;
      total = _regions[ k].total;
      if( _regions[ k].link >= 0 && _regions[ _regions[ k].link].total < total)
         total = _regions[ _regions[ k].link].total;
      when = total * 1000 / (8 * _regions[ k].flow);
      if( when < h.safeStep.ms)
         h.safeStep = BGTimeMake( when < 1 ? 1 : when);
   }

   /* the exchange with the solids lags a step: no more than an eighth of
    * the way to equal in one */
   for( i = 0; i < (NSUInteger) _nsurfaces; i++)
   {
      int64_t   capacity;

      if( ! [self surfaceDelta:(int) i capacity:&capacity])
         continue;
      when = capacity * 1000 / (8 * _surfaces[ i].conductance);
      if( when < h.safeStep.ms)
         h.safeStep = BGTimeMake( when < 1 ? 1 : when);
   }
   return( h);
}


/* --- coupling ------------------------------------------------------------------- */

- (void) publishInto:(BGSnapshot *) snapshot
{
   int   k;

   [self load];
   for( k = 0; k < _nregions; k++)
      [snapshot setQuantity:BGQuantityTemperature
                         of:_regions[ k].entity
                         to:gasTemperature( &_regions[ k])];
}


- (BOOL) takesContribution:(BGContribution) contribution
{
   return( contribution.quantity == BGQuantityHeat &&
           [_world record:[_world kindNamed:"GasStore"] for:contribution.target] != NULL);
}


- (void) receiveContribution:(BGContribution) contribution
{
   int   k;

   [self load];
   if( (k = [self regionOf:contribution.target]) >= 0)
      _regions[ k].pending += contribution.amount;
}


- (void) send:(int64_t) heat
           to:(BGEntityID) target
         from:(BGEntityID) source
       outbox:(BGContributions *) outbox
{
   BGContribution   c;

   c.target   = target;
   c.source   = source;
   c.quantity = BGQuantityHeat;
   c.amount   = heat;
   [outbox addContribution:c];
}


/* What comes in through the door from outdoors, and goes out, for one
 * quantity of a region: in whole quanta, the fraction carried. */
static int64_t   exchange( int64_t air, int64_t mine, int64_t total, int64_t outNum, int64_t outDen,
                           int64_t *carryIn, int64_t *carryOut)
{
   int64_t   in;
   int64_t   out;

   *carryIn  += air * outNum;
   in         = *carryIn / outDen;
   *carryIn  %= outDen;
   *carryOut += air * mine;
   out        = *carryOut / total;
   *carryOut %= total;
   return( in - out);
}


- (void) advanceFrom:(BGTime) t0
                  to:(BGTime) t1
               world:(BGWorld *) world
           committer:(BGCommitter *) committer
{
   [self advanceFrom:t0
                  to:t1
               world:world
           committer:committer
            snapshot:nil
              outbox:nil];
}


/* With no outbox, nothing goes to the solids: the fire's share stays in
 * the iron's flue gas, and there is no exchange. */
- (void) advanceFrom:(BGTime) t0
                  to:(BGTime) t1
               world:(BGWorld *) world
           committer:(BGCommitter *) committer
            snapshot:(BGSnapshot *) snapshot
              outbox:(BGContributions *) outbox
{
   const BGActivity   *record;
   BGProposalGroup    *g;
   BGAirRegion        *r;
   BGAirRegion        before[ BG_ATMOS_REGIONS];
   BGEntityID         watched[ 16];
   NSUInteger         n;
   NSUInteger         i;
   int64_t            dt;
   int64_t            air;
   int64_t            d[ 3];
   int64_t            burned;
   int64_t            rate;
   int64_t            used;
   int64_t            made;
   int64_t            heat;
   int64_t            share;
   int64_t            solid;
   int64_t            delta;
   int64_t            breath;
   int64_t            num;
   int64_t            den;
   const BGGasStore   *store;
   const BGDoor       *door;
   BOOL               quiet[ BG_ATMOS_REGIONS];
   int                c;
   NSString           *why;
   int64_t            q;
   int64_t            rates[ BG_ATMOS_STOVES];
   int                k;
   int                s;
   BOOL               open;

   dt = t1.ms - t0.ms;
   [self load];
   if( dt <= 0)
      return;
   if( ! _ledgered)
   {
      memset( &_ledger, 0, sizeof( _ledger));
      for( k = 0; k < _nregions; k++)
      {
         _ledger.initial[ 0] += _regions[ k].oxygen;
         _ledger.initial[ 1] += _regions[ k].dioxide;
         _ledger.initial[ 2] += _regions[ k].heat;
      }
      for( s = 0; s < _nstoves; s++)
         _ledger.fuel += _stoves[ s].fuel;
      _ledgered = YES;
   }
   memcpy( before, _regions, sizeof( before));
   for( s = 0; s < _nstoves; s++)
      rates[ s] = [self rateOf:s];          /* from step-start values */
   for( k = 0; k < _nregions; k++)
   {
      quiet[ k] = [self linkQuiet:k values:before];
      if( [self awake:k values:before])
         _regions[ k].steps++;
   }

   /* what was in transit to the gas */
   for( k = 0; k < _nregions; k++)
   {
      _regions[ k].heat     += _regions[ k].pending;
      _ledger.received      += _regions[ k].pending;
      _regions[ k].pending   = 0;
   }

   /* the solids' surfaces, from the step-start snapshot: the gas gives what
    * it gives now, and the solid receives it next step */
   for( k = 0; outbox && k < _nsurfaces; k++)
   {
      if( _surfaces[ k].region < 0 ||
          ! [snapshot quantity:BGQuantityTemperature of:_surfaces[ k].entity value:&solid])
         continue;
      delta = gasTemperature( &before[ _surfaces[ k].region]) - solid;
      if( llabs( delta) < 500)
         continue;
      _surfaces[ k].carry += _surfaces[ k].conductance * delta * dt;
      q                    = _surfaces[ k].carry / 1000000;
      _surfaces[ k].carry %= 1000000;
      _regions[ _surfaces[ k].region].heat -= q;
      _ledger.exchanged                    += q;
      [self send:q
              to:_surfaces[ k].entity
            from:_regions[ _surfaces[ k].region].entity
          outbox:outbox];
   }

   /* the links: each moving one mixes its region with what it opens to,
    * from step-start values; between regions, what one gains the other
    * loses */
   for( k = 0; k < _nregions; k++)
   {
      if( quiet[ k])
         continue;
      r            = &_regions[ k];
      r->carryAir += before[ k].flow * dt;
      air          = r->carryAir / 1000;
      r->carryAir %= 1000;
      for( c = 0; c < 3; c++)
      {
         across( before, k, c, &num, &den);
         d[ c] = exchange( air, quantity( &before[ k], c), r->total, num, den, &r->carryIn[ c], &r->carryOut[ c]);
      }
      r->oxygen  += d[ 0];
      r->dioxide += d[ 1];
      r->heat    += d[ 2];
      if( r->link < 0)
      {
         _ledger.inflow[ 0] += d[ 0];
         _ledger.inflow[ 1] += d[ 1];
         _ledger.inflow[ 2] += d[ 2];
      }
      else
      {
         _regions[ r->link].oxygen  -= d[ 0];
         _regions[ r->link].dioxide -= d[ 1];
         _regions[ r->link].heat    -= d[ 2];
      }
   }

   /* the stoves: from step-start values */
   for( s = 0; s < _nstoves; s++)
   {
      _stoves[ s].out = NO;
      if( ! [self lit:s])
         continue;
      rate               = rates[ s];
      _stoves[ s].carry += rate * dt;
      burned             = _stoves[ s].carry / 1000;
      _stoves[ s].carry %= 1000;
      if( burned > _stoves[ s].fuel)
         burned = _stoves[ s].fuel;
      _stoves[ s].fuel -= burned;
      _ledger.burned   += burned;
      open = ((const BGCombustor *) [_world record:[_world kindNamed:"Combustor"] for:_stoves[ s].entity])->damper;

      /* its iron's share */
      share = 0;
      if( outbox && [_world record:[_world kindNamed:"ThermalBody"] for:_stoves[ s].entity])
      {
         _stoves[ s].carryShare += burned * BG_BURN_HEAT * BG_BURN_SHARE;
         share                   = _stoves[ s].carryShare / 10;
         _stoves[ s].carryShare %= 10;
         _ledger.toSolids       += share;
         [self send:share
                 to:_stoves[ s].entity
               from:_stoves[ s].entity
             outbox:outbox];
      }
      if( _stoves[ s].region >= 0)
      {
         r = &_regions[ _stoves[ s].region];
         if( open)
         {
            /* drawn from outdoors, and the rest of the heat up the flue */
         }
         else
         {
            /* from the room and into it */
            r->carryBurn[ 0] += burned * BG_BURN_OXYGEN;
            used              = r->carryBurn[ 0] / 1000;
            r->carryBurn[ 0] %= 1000;
            if( used > r->oxygen)
               used = r->oxygen;
            r->carryBurn[ 1] += burned * BG_BURN_DIOXIDE;
            made              = r->carryBurn[ 1] / 1000;
            r->carryBurn[ 1] %= 1000;
            heat        = burned * BG_BURN_HEAT - share;
            r->oxygen  -= used;
            r->dioxide += made;
            r->heat    += heat;
            _ledger.consumed[ 0] += used;
            _ledger.produced[ 1] += made;
            _ledger.produced[ 2] += heat;
         }
      }
      if( ! _stoves[ s].fuel)
         _stoves[ s].out = YES;
   }

   /* the breathers: from the air over them, their heat to their bodies */
   for( s = 0; s < _nbreathers; s++)
   {
      if( (breath = [self breathOf:s]) <= 0)
         continue;
      r                          = &_regions[ _breathers[ s].region];
      _breathers[ s].carry      += breath * dt;
      used                       = _breathers[ s].carry / 1000000;
      _breathers[ s].carry      %= 1000000;
      if( used > r->oxygen)
         used = r->oxygen;
      _breathers[ s].carryDioxide += used * BG_BREATH_DIOXIDE;
      made                         = _breathers[ s].carryDioxide / 5;
      _breathers[ s].carryDioxide %= 5;
      r->oxygen  -= used;
      r->dioxide += made;
      _ledger.consumed[ 0] += used;
      _ledger.produced[ 1] += made;
      heat = used * BG_BREATH_HEAT;
      if( outbox && [_world record:[_world kindNamed:"ThermalBody"] for:_breathers[ s].entity])
      {
         _ledger.toSolids += heat;
         [self send:heat
                 to:_breathers[ s].entity
               from:_breathers[ s].entity
             outbox:outbox];
      }
      else
      {
         r->heat              += heat;
         _ledger.produced[ 2] += heat;
      }
   }

   /* the doors as they are now */
   for( k = 0; k < _nregions; k++)
   {
      store = [_world record:[_world kindNamed:"GasStore"] for:_regions[ k].entity];
      door  = store && store->door ? [_world record:[_world kindNamed:"Door"] for:(BGEntityID) store->door] : NULL;
      _regions[ k].doorSeen = door ? door->ajar : 0;
   }

   /* the records mirror the domain */
   for( k = 0; k < _nregions; k++)
   {
      [_world setField:"GasStore.oxygen" of:_regions[ k].entity value:_regions[ k].oxygen];
      [_world setField:"GasStore.dioxide" of:_regions[ k].entity value:_regions[ k].dioxide];
      [_world setField:"GasStore.gasHeat" of:_regions[ k].entity value:_regions[ k].heat];
   }
   for( s = 0; s < _nstoves; s++)
      [_world setField:"FuelContainer.fuel" of:_stoves[ s].entity value:(_stoves[ s].fuel + 999) / 1000];
   _rise = _nregions && dt ? (_regions[ 0].dioxide - before[ 0].dioxide) * 1000 / dt : 0;
   _steps++;

   /* a fire out, at the boundary: by proposal */
   for( s = 0; s < _nstoves; s++)
      if( _stoves[ s].out)
      {
         g = [BGProposalGroup groupWithPhase:BGPhaseProcess
                                      source:[NSString stringWithFormat:@"atmosphere: stove %llu goes out",
                                                                        (unsigned long long) _stoves[ s].entity]];
         [g set:"Combustor.lit" of:BGWhole( _stoves[ s].entity) to:0];
         [g set:"FuelContainer.fuel" of:BGWhole( _stoves[ s].entity) to:0];
         [committer submit:g];
      }

   /* watches crossed */
   n = [self watches:watched max:16];
   for( i = 0; i < n; i++)
   {
      record = [_world record:[_world kindNamed:"Activity"] for:watched[ i]];
      if( ! (why = [self crossingOf:record]))
         continue;
      for( s = 0; s < _nfired && _fired[ s] != watched[ i]; s++)
         ;
      if( s < _nfired)
         continue;
      if( _nfired < 16)
         _fired[ _nfired++] = watched[ i];
      k = [self regionWatchedBy:record];
      g = [BGProposalGroup groupWithPhase:BGPhaseProcess
                                   source:[NSString stringWithFormat:@"atmosphere: the air at %llu %@",
                                                                     (unsigned long long) _regions[ k].entity, why]];
      [g emit:"watched" subject:BGWhole( watched[ i]) other:BGWhole( _regions[ k].entity)];
      [committer submit:g];
   }
}


- (BOOL) balanced
{
   int64_t   sum[ 3];
   int64_t   fuel;
   int       k;

   memset( sum, 0, sizeof( sum));
   for( k = 0; k < _nregions; k++)
   {
      sum[ 0] += _regions[ k].oxygen;
      sum[ 1] += _regions[ k].dioxide;
      sum[ 2] += _regions[ k].heat;
   }
   for( fuel = 0, k = 0; k < _nstoves; k++)
      fuel += _stoves[ k].fuel;
   for( k = 0; k < 3; k++)
      if( sum[ k] != _ledger.initial[ k] + _ledger.inflow[ k] + _ledger.produced[ k] - _ledger.consumed[ k] +
                     (k == 2 ? _ledger.received - _ledger.exchanged : 0))
         return( NO);
   return( ! _ledgered || fuel + _ledger.burned == _ledger.fuel);
}


/* --- saves ----------------------------------------------------------------------- */

- (void) checkInAll
{
}


- (NSArray *) savedState
{
   NSMutableArray   *lines;
   BGAirRegion      *r;
   int              k;

   lines = [NSMutableArray array];
   [lines addObject:[NSString stringWithFormat:@"air %d %llu %lld", _ledgered ? 1 : 0, (unsigned long long) _steps,
                                               (long long) _rise]];
   [lines addObject:[NSString stringWithFormat:@"ledger %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld "
                                               @"%lld %lld %lld",
                                               _ledger.initial[ 0], _ledger.initial[ 1], _ledger.initial[ 2],
                                               _ledger.inflow[ 0], _ledger.inflow[ 1], _ledger.inflow[ 2],
                                               _ledger.produced[ 0], _ledger.produced[ 1], _ledger.produced[ 2],
                                               _ledger.consumed[ 0], _ledger.consumed[ 1], _ledger.consumed[ 2],
                                               _ledger.fuel, _ledger.burned,
                                               _ledger.exchanged, _ledger.toSolids, _ledger.received]];
   for( k = 0; k < _nregions; k++)
   {
      r = &_regions[ k];
      [lines addObject:[NSString stringWithFormat:@"region %llu %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld",
                                                  (unsigned long long) r->entity, r->carryAir,
                                                  r->carryIn[ 0], r->carryIn[ 1], r->carryIn[ 2],
                                                  r->carryOut[ 0], r->carryOut[ 1], r->carryOut[ 2],
                                                  r->carryBurn[ 0], r->carryBurn[ 1], r->carryBurn[ 2],
                                                  r->pending, (long long) r->doorSeen, (long long) r->steps]];
   }
   for( k = 0; k < _nstoves; k++)
      [lines addObject:[NSString stringWithFormat:@"stove %llu %lld %lld %lld", (unsigned long long) _stoves[ k].entity,
                                                  _stoves[ k].fuel, _stoves[ k].carry, _stoves[ k].carryShare]];
   for( k = 0; k < _nsurfaces; k++)
      [lines addObject:[NSString stringWithFormat:@"surface %llu %lld", (unsigned long long) _surfaces[ k].entity,
                                                  _surfaces[ k].carry]];
   for( k = 0; k < _nbreathers; k++)
      [lines addObject:[NSString stringWithFormat:@"breather %llu %lld %lld", (unsigned long long) _breathers[ k].entity,
                                                  _breathers[ k].carry, _breathers[ k].carryDioxide]];
   for( k = 0; k < _nfired; k++)
      [lines addObject:[NSString stringWithFormat:@"fired %llu", (unsigned long long) _fired[ k]]];
   return( lines);
}


- (void) restoreSavedState:(NSArray *) lines
{
   unsigned long long   e;
   unsigned long long   steps;
   long long            v[ 17];
   NSUInteger           i;
   BGAirRegion          *r;
   const char           *text;
   int                  flag;
   int                  k;

   _nregions = 0;
   _nstoves  = 0;
   _nfired   = 0;
   _nsurfaces  = 0;
   _nbreathers = 0;
   for( i = 0; i < [lines count]; i++)
   {
      text = [[lines objectAtIndex:i] UTF8String];
      if( sscanf( text, "air %d %llu %lld", &flag, &steps, &v[ 0]) == 3)
      {
         _ledgered = flag != 0;
         _steps    = (NSUInteger) steps;
         _rise     = v[ 0];
      }
      else if( sscanf( text, "ledger %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld",
                       &v[ 0], &v[ 1], &v[ 2], &v[ 3], &v[ 4], &v[ 5], &v[ 6], &v[ 7], &v[ 8], &v[ 9], &v[ 10],
                       &v[ 11], &v[ 12], &v[ 13], &v[ 14], &v[ 15], &v[ 16]) == 17)
      {
         for( k = 0; k < 3; k++)
         {
            _ledger.initial[ k]  = v[ k];
            _ledger.inflow[ k]   = v[ 3 + k];
            _ledger.produced[ k] = v[ 6 + k];
            _ledger.consumed[ k] = v[ 9 + k];
         }
         _ledger.fuel      = v[ 12];
         _ledger.burned    = v[ 13];
         _ledger.exchanged = v[ 14];
         _ledger.toSolids  = v[ 15];
         _ledger.received  = v[ 16];
      }
      else if( sscanf( text, "region %llu %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld %lld", &e, &v[ 0], &v[ 1],
                       &v[ 2], &v[ 3], &v[ 4], &v[ 5], &v[ 6], &v[ 7], &v[ 8], &v[ 9], &v[ 10], &v[ 11], &v[ 12]) == 14)
      {
         if( (k = [self regionOf:(BGEntityID) e]) < 0)
            continue;
         r           = &_regions[ k];
         r->carryAir = v[ 0];
         r->carryIn[ 0]  = v[ 1];
         r->carryIn[ 1]  = v[ 2];
         r->carryIn[ 2]  = v[ 3];
         r->carryOut[ 0] = v[ 4];
         r->carryOut[ 1] = v[ 5];
         r->carryOut[ 2] = v[ 6];
         r->carryBurn[ 0] = v[ 7];
         r->carryBurn[ 1] = v[ 8];
         r->carryBurn[ 2] = v[ 9];
         r->pending       = v[ 10];
         r->doorSeen      = (int) v[ 11];
         r->steps         = (NSUInteger) v[ 12];
      }
      else if( sscanf( text, "stove %llu %lld %lld %lld", &e, &v[ 0], &v[ 1], &v[ 2]) == 4)
      {
         if( (k = [self stoveOf:(BGEntityID) e]) < 0)
            continue;
         _stoves[ k].fuel       = v[ 0];
         _stoves[ k].carry      = v[ 1];
         _stoves[ k].carryShare = v[ 2];
      }
      else if( sscanf( text, "surface %llu %lld", &e, &v[ 0]) == 2)
      {
         if( (k = [self surfaceOf:(BGEntityID) e]) < 0)
            continue;
         _surfaces[ k].carry = v[ 0];
      }
      else if( sscanf( text, "breather %llu %lld %lld", &e, &v[ 0], &v[ 1]) == 3)
      {
         if( (k = [self breatherOf:(BGEntityID) e]) < 0)
            continue;
         _breathers[ k].carry        = v[ 0];
         _breathers[ k].carryDioxide = v[ 1];
      }
      else if( sscanf( text, "fired %llu", &e) == 1 && _nfired < 16)
         _fired[ _nfired++] = (BGEntityID) e;
   }
   [self load];
}

@end

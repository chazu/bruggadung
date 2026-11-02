#import "BGThermal.h"


#define BG_OUT_TEMPERATURE   275000      /* mK */


@implementation BGThermal

- (id) initWithWorld:(BGWorld *) world
{
   if( ! (self = [super init]))
      return( nil);
   _world = [world retain];
   return( self);
}


- (void) dealloc
{
   free( _bodies);
   [_world release];
   [super dealloc];
}


- (NSString *) name
{
   return( @"thermal");
}


- (NSUInteger) steps
{
   return( _steps);
}


- (int64_t) received
{
   return( _received);
}


- (int64_t) pending
{
   int64_t   sum;
   int       i;

   for( sum = 0, i = 0; i < _nbodies; i++)
      sum += _bodies[ i].pending;
   return( sum);
}


/* --- reading the world ------------------------------------------------------------ */

- (int) bodyOf:(BGEntityID) entity
{
   int   lo;
   int   hi;
   int   mid;

   lo = 0;
   hi = _nbodies;
   while( lo < hi)
   {
      mid = (lo + hi) / 2;
      if( _bodies[ mid].entity < entity)
         lo = mid + 1;
      else
         hi = mid;
   }
   if( lo < _nbodies && _bodies[ lo].entity == entity)
      return( lo);
   if( _nbodies == _bodycap)
   {
      _bodycap = _bodycap ? _bodycap * 2 : 16;
      _bodies  = realloc( _bodies, (size_t) _bodycap * sizeof( BGThermalState));
   }
   memmove( &_bodies[ lo + 1], &_bodies[ lo], (size_t) (_nbodies - lo) * sizeof( BGThermalState));
   memset( &_bodies[ lo], 0, sizeof( BGThermalState));
   _bodies[ lo].entity = entity;
   _nbodies++;
   return( lo);
}


/* The bodies' values from their records, which mirror ours. */
- (void) load
{
   const BGThermalBody   *body;
   BGStore               *store;
   NSUInteger            i;
   int                   k;

   store = [_world storeForKind:[_world kindNamed:"ThermalBody"]];
   for( i = 0; i < [store count]; i++)
   {
      body = [store recordAtIndex:i];
      /* a part inside an assembly joins no domain (COMPONENTS.md §7): its
       * heat is the assembly's */
      if( [_world locationOf:[store entityAtIndex:i]].form == BGLocationPartOf)
         continue;
      if( (k = [self bodyOf:[store entityAtIndex:i]]) < 0)
         continue;
      _bodies[ k].heat       = body->heat;
      _bodies[ k].capacity   = body->heatCapacity;
      _bodies[ k].toOutdoors = body->toOutdoors;
   }
}


static int64_t   temperature( const BGThermalState *b)
{
   return( b->heat * 1000 / b->capacity);
}


- (BOOL) participates:(BGEntityID) body
{
   int   i;

   [self load];
   for( i = 0; i < _nbodies; i++)
      if( _bodies[ i].entity == body && [_world locationOf:body].form != BGLocationPartOf)
         return( YES);
   return( NO);
}


- (int64_t) temperatureOf:(BGEntityID) entity
{
   int   i;

   [self load];
   for( i = 0; i < _nbodies; i++)
      if( _bodies[ i].entity == entity)
         return( temperature( &_bodies[ i]));
   return( 0);
}


/* --- the domain ----------------------------------------------------------------- */

- (BOOL) isActive
{
   int   i;

   [self load];
   for( i = 0; i < _nbodies; i++)
      if( _bodies[ i].pending ||
          (_bodies[ i].toOutdoors && llabs( temperature( &_bodies[ i]) - BG_OUT_TEMPERATURE) >= 500))
         return( YES);
   return( NO);
}


/* The outdoors' exchange is explicit: a step moves no more than an eighth
 * of the way to 275 K. The exchange with the air is the atmosphere's to
 * bound. Nothing here is a discrete event. */
- (BGHorizon) horizonAt:(BGTime) t
{
   BGHorizon   h;
   int64_t     step;
   int         i;

   [self load];
   h.nextEvent = BGTimeNever;
   h.safeStep  = BGTimeNever;
   for( i = 0; i < _nbodies; i++)
      if( _bodies[ i].toOutdoors)
      {
         step = _bodies[ i].capacity * 1000 / (8 * _bodies[ i].toOutdoors);
         if( step < h.safeStep.ms)
            h.safeStep = BGTimeMake( step);
      }
   return( h);
}


- (void) publishInto:(BGSnapshot *) snapshot
{
   int   i;

   [self load];
   for( i = 0; i < _nbodies; i++)
      [snapshot setQuantity:BGQuantityTemperature
                         of:_bodies[ i].entity
                         to:temperature( &_bodies[ i])];
}


- (BOOL) takesContribution:(BGContribution) contribution
{
   return( contribution.quantity == BGQuantityHeat &&
           [_world record:[_world kindNamed:"ThermalBody"] for:contribution.target] != NULL);
}


- (void) receiveContribution:(BGContribution) contribution
{
   int   k;

   [self load];
   if( (k = [self bodyOf:contribution.target]) >= 0)
      _bodies[ k].pending += contribution.amount;
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


- (void) advanceFrom:(BGTime) t0
                  to:(BGTime) t1
               world:(BGWorld *) world
           committer:(BGCommitter *) committer
            snapshot:(BGSnapshot *) snapshot
              outbox:(BGContributions *) outbox
{
   BGThermalState   *b;
   int64_t          dt;
   int64_t          q;
   int              i;

   dt = t1.ms - t0.ms;
   [self load];
   if( dt <= 0)
      return;
   if( ! _ledgered)
   {
      for( _initial = 0, i = 0; i < _nbodies; i++)
         _initial += _bodies[ i].heat;
      _ledgered = YES;
   }
   for( i = 0; i < _nbodies; i++)
   {
      b = &_bodies[ i];
      /* the outdoors, from the step-start temperature */
      q = 0;
      if( b->toOutdoors)
      {
         b->carry += b->toOutdoors * (BG_OUT_TEMPERATURE - temperature( b)) * dt;
         q         = b->carry / 1000000;
         b->carry %= 1000000;
      }
      /* what was in transit to it */
      b->heat   += q + b->pending;
      _inflow   += q;
      _received += b->pending;
      b->pending = 0;
      [_world setField:"ThermalBody.heat" of:b->entity value:b->heat];
   }
   _steps++;
}


- (BOOL) balanced
{
   int64_t   sum;
   int       i;

   for( sum = 0, i = 0; i < _nbodies; i++)
      sum += _bodies[ i].heat;
   return( ! _ledgered || sum == _initial + _inflow + _received);
}


/* --- saves ----------------------------------------------------------------------- */

- (void) checkInAll
{
}


- (NSArray *) savedState
{
   NSMutableArray   *lines;
   int              i;

   lines = [NSMutableArray array];
   [lines addObject:[NSString stringWithFormat:@"thermal %d %llu %lld %lld %lld", _ledgered ? 1 : 0,
                                               (unsigned long long) _steps, _initial, _inflow, _received]];
   for( i = 0; i < _nbodies; i++)
      [lines addObject:[NSString stringWithFormat:@"body %llu %lld %lld", (unsigned long long) _bodies[ i].entity,
                                                  _bodies[ i].carry, _bodies[ i].pending]];
   return( lines);
}


- (void) restoreSavedState:(NSArray *) lines
{
   unsigned long long   e;
   unsigned long long   steps;
   long long            v[ 3];
   NSUInteger           i;
   const char           *text;
   int                  flag;
   int                  k;

   _nbodies = 0;
   for( i = 0; i < [lines count]; i++)
   {
      text = [[lines objectAtIndex:i] UTF8String];
      if( sscanf( text, "thermal %d %llu %lld %lld %lld", &flag, &steps, &v[ 0], &v[ 1], &v[ 2]) == 5)
      {
         _ledgered = flag != 0;
         _steps    = (NSUInteger) steps;
         _initial  = v[ 0];
         _inflow   = v[ 1];
         _received = v[ 2];
      }
      else if( sscanf( text, "body %llu %lld %lld", &e, &v[ 0], &v[ 1]) == 3)
      {
         if( (k = [self bodyOf:(BGEntityID) e]) < 0)
            continue;
         _bodies[ k].carry   = v[ 0];
         _bodies[ k].pending = v[ 1];
      }
   }
   [self load];
}

@end

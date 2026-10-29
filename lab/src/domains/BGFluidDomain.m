#import "BGFluidDomain.h"

#import "BGProposalGroup.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>


#define BG_MS_PER_MINUTE   60000


/* An open tap as the world has it now: what forming a structure would use. */
typedef struct
{
   BGEntityID   tap;
   BGEntityID   source;
   BGEntityID   destination;     /* BGNoEntity: the tile below */
   int32_t      x;
   int32_t      y;
   int32_t      level;
   int64_t      rate;
} BGTapView;


static BOOL   ground_tile( BGWorld *world, BGEntityID e, BGLocation *tile)
{
   BGLocation   loc;
   NSUInteger   guard;

   for( guard = 0; guard < 64; guard++)
   {
      loc = [world locationOf:e];
      if( loc.form == BGLocationOnTile)
      {
         *tile = loc;
         return( YES);
      }
      if( loc.form == BGLocationNone || ! loc.place)
         return( NO);
      e = loc.place;
   }
   return( NO);
}


@implementation BGFluidDomain

- (id) initWithWorld:(BGWorld *) world
{
   if( ! (self = [super init]))
      return( nil);
   _world     = [world retain];
   _log       = [NSMutableArray new];
   _predicted = BGTimeNever;
   return( self);
}


- (void) dealloc
{
   [_world release];
   [_log release];
   [super dealloc];
}


- (NSString *) name
{
   return( @"fluid");
}


- (BOOL) isActive
{
   return( YES);        /* it decides at each horizon whether it has anything to do */
}


- (void) setReversedOrder:(BOOL) flag
{
   _reversed = flag;
}


- (NSArray *) log
{
   return( _log);
}


- (BGTime) predictedExhaustion
{
   return( _predicted);
}


/* --- participants -------------------------------------------------------------- */

/* The open taps, in ID order, with where each draws from and delivers to. */
- (int) scan:(BGTapView *) views
{
   const BGTap     *tap;
   BGStore         *taps;
   BGEntityID      inside[ 4];
   BGLocation      at;
   BGLocation      tile;
   NSUInteger      kstore;
   NSUInteger      i;
   NSUInteger      j;
   NSUInteger      m;
   int             n;

   taps   = [_world storeForKind:[_world kindNamed:"Tap"]];
   kstore = [_world kindNamed:"WaterStore"];
   n      = 0;
   for( i = 0; i < [taps count] && n < BG_FLUID_MAX; i++)
   {
      tap = [taps recordAtIndex:i];
      if( ! tap->open)
         continue;
      views[ n].tap = [taps entityAtIndex:i];
      at            = [_world locationOf:views[ n].tap];
      /* a tap draws from the store it is installed in */
      if( at.form != BGLocationPartOf || ! [_world record:kstore for:at.place])
         continue;
      views[ n].source      = at.place;
      views[ n].rate        = tap->rate;
      views[ n].destination = BGNoEntity;
      /* into what sits in it, or onto the tile below */
      m = [_world entitiesAt:views[ n].tap
                        form:BGLocationIn
                        into:inside
                         max:4];
      for( j = 0; j < m && j < 4; j++)
         if( [_world record:kstore for:inside[ j]])
         {
            views[ n].destination = inside[ j];
            break;
         }
      if( ! views[ n].destination)
      {
         if( ! ground_tile( _world, views[ n].tap, &tile))
            continue;
         views[ n].x     = tile.x;
         views[ n].y     = tile.y;
         views[ n].level = tile.level;
      }
      n++;
   }
   return( n);
}


static uint64_t   signature( BGTapView *views, int n)
{
   uint64_t   h;
   int        i;

   h = BGMix( (uint64_t) n);
   for( i = 0; i < n; i++)
   {
      h = BGMix( h ^ views[ i].tap ^ (views[ i].source << 20) ^ (views[ i].destination << 40));
      h = BGMix( h ^ (uint64_t) views[ i].rate ^ ((uint64_t) (uint32_t) views[ i].x << 24) ^
                 ((uint64_t) (uint32_t) views[ i].y << 44));
   }
   return( h);
}


/* --- the structure ------------------------------------------------------------- */

- (int) holderFor:(BGEntityID) entity
                x:(int32_t) x
                y:(int32_t) y
            level:(int32_t) level
{
   int       i;
   int64_t   water;

   for( i = 0; i < _nholders; i++)
      if( entity ? _holders[ i].entity == entity
                 : (! _holders[ i].entity && _holders[ i].x == x && _holders[ i].y == y && _holders[ i].level == level))
         return( i);
   if( _nholders == BG_FLUID_MAX)
      return( -1);
   if( entity)
   {
      [_world getField:"WaterStore.water" of:entity value:&water];
      [_world setCheckedOut:YES
                        for:entity];
   }
   else
   {
      water = [_world waterAtX:x y:y level:level];
      [_world setTileCheckedOut:YES x:x y:y level:level];
   }
   _holders[ _nholders].entity = entity;
   _holders[ _nholders].x      = x;
   _holders[ _nholders].y      = y;
   _holders[ _nholders].level  = level;
   _holders[ _nholders].water  = water;
   return( _nholders++);
}


/* Checks out the stores the open taps join, and starts flowing. */
- (void) formFrom:(BGTapView *) views
            count:(int) n
{
   BGFluidOutlet   *o;
   int             i;
   int             k;
   int             m;

   _nholders = 0;
   _noutlets = 0;
   for( k = 0; k < n; k++)
   {
      i = _reversed ? n - 1 - k : k;
      o              = &_outlets[ _noutlets];
      o->tap         = views[ i].tap;
      o->rate        = views[ i].rate;
      o->carry       = 0;
      for( m = 0; m < _ncarries; m++)
         if( _carryTaps[ m] == o->tap)
            o->carry = _carries[ m];
      o->source      = [self holderFor:views[ i].source x:0 y:0 level:0];
      o->destination = [self holderFor:views[ i].destination x:views[ i].x y:views[ i].y level:views[ i].level];
      if( o->source < 0 || o->destination < 0)
         continue;
      o->exhausted = _holders[ o->source].water == 0;
      _noutlets++;
   }
   _active = YES;
}


- (int64_t) checkedOutWater
{
   int64_t   sum;
   int       i;

   if( ! _active)
      return( 0);
   sum = 0;
   for( i = 0; i < _nholders; i++)
      sum += _holders[ i].water;
   return( sum);
}


- (void) checkInAll
{
   int   i;

   if( ! _active)
      return;
   /* the carries of the taps flowing now; a closed tap's carry is dropped, which moves nothing */
   _ncarries = 0;
   for( i = 0; i < _noutlets; i++)
      if( _outlets[ i].carry)
      {
         _carryTaps[ _ncarries] = _outlets[ i].tap;
         _carries[ _ncarries]   = _outlets[ i].carry;
         _ncarries++;
      }
   for( i = 0; i < _nholders; i++)
      if( _holders[ i].entity)
      {
         [_world setCheckedOut:NO
                           for:_holders[ i].entity];
         [_world setField:"WaterStore.water"
                       of:_holders[ i].entity
                    value:_holders[ i].water];
      }
      else
      {
         [_world setTileCheckedOut:NO x:_holders[ i].x y:_holders[ i].y level:_holders[ i].level];
         [_world setWater:_holders[ i].water
                      atX:_holders[ i].x
                        y:_holders[ i].y
                    level:_holders[ i].level];
      }
   _active   = NO;
   _nholders = 0;
   _noutlets = 0;
}


- (BOOL) flowing
{
   int   i;

   for( i = 0; i < _noutlets; i++)
      if( ! _outlets[ i].exhausted && _outlets[ i].rate > 0)
         return( YES);
   return( NO);
}


- (NSArray *) savedState
{
   NSMutableArray   *lines;
   int              i;

   [self checkInAll];
   lines = [NSMutableArray array];
   for( i = 0; i < _ncarries; i++)
      [lines addObject:[NSString stringWithFormat:@"carry %llu %lld", (unsigned long long) _carryTaps[ i],
                                                  (long long) _carries[ i]]];
   return( lines);
}


- (void) restoreSavedState:(NSArray *) lines
{
   unsigned long long   tap;
   long long            carry;
   NSUInteger           i;

   _ncarries = 0;
   for( i = 0; i < [lines count] && _ncarries < BG_FLUID_MAX; i++)
      if( sscanf( [[lines objectAtIndex:i] UTF8String], "carry %llu %lld", &tap, &carry) == 2)
      {
         _carryTaps[ _ncarries] = (BGEntityID) tap;
         _carries[ _ncarries]   = carry;
         _ncarries++;
      }
}


/* --- horizons ---------------------------------------------------------------- */

static int64_t   delivered( const BGFluidOutlet *o, int64_t dt)
{
   return( (o->rate * dt + o->carry) / BG_MS_PER_MINUTE);
}


/* The first time at which the outlets on a store would ask for all of it:
 * exactly the step in which it runs dry. Never later than the true time. */
- (BGTime) exhaustionOf:(int) source
                     at:(BGTime) t
{
   int64_t   hi;
   int64_t   lo;
   int64_t   mid;
   int64_t   rate;
   int64_t   sum;
   int64_t   water;
   int       i;
   int       n;

   rate  = 0;
   n     = 0;
   water = _holders[ source].water;
   for( i = 0; i < _noutlets; i++)
      if( _outlets[ i].source == source && ! _outlets[ i].exhausted)
      {
         rate += _outlets[ i].rate;
         n++;
      }
   /* a holder nothing draws from never runs dry */
   if( ! n || ! rate)
      return( BGTimeNever);
   if( ! water)
      return( t);
   lo = 1;
   hi = ((water + n) * BG_MS_PER_MINUTE + rate - 1) / rate;
   while( lo < hi)
   {
      mid = (lo + hi) / 2;
      sum = 0;
      for( i = 0; i < _noutlets; i++)
         if( _outlets[ i].source == source && ! _outlets[ i].exhausted)
            sum += delivered( &_outlets[ i], mid);
      if( sum >= water)
         hi = mid;
      else
         lo = mid + 1;
   }
   return( BGTimeMake( t.ms + lo));
}


- (BGHorizon) horizonAt:(BGTime) t
{
   BGTapView   views[ BG_FLUID_MAX];
   BGHorizon   h;
   BGTime      next;
   uint64_t    sig;
   int         i;
   int         n;

   h.safeStep  = BGTimeNever;      /* constant rates: any step is exact */
   h.nextEvent = BGTimeNever;
   n   = [self scan:views];
   sig = signature( views, n);
   /* a tap opened or closed, or a bucket moved: check in and form again */
   if( _active && sig != _signature)
      [self checkInAll];
   if( ! _active)
   {
      _signature = sig;
      [self formFrom:views
               count:n];
      if( ! [self flowing])
      {
         [self checkInAll];
         return( h);
      }
   }
   for( i = 0; i < _nholders; i++)
   {
      next = [self exhaustionOf:i
                             at:t];
      if( next.ms < h.nextEvent.ms)
         h.nextEvent = next;
   }
   _predicted = h.nextEvent;
   return( h);
}


/* --- a step -------------------------------------------------------------------- */

static int   cmp_tap( const void *a, const void *b, void *ctx)
{
   const BGFluidOutlet   *outlets;
   BGEntityID            x;
   BGEntityID            y;

   outlets = ctx;
   x       = outlets[ *(const int *) a].tap;
   y       = outlets[ *(const int *) b].tap;
   return( x < y ? -1 : x > y);
}


static void   sort_by_tap( int *order, int n, const BGFluidOutlet *outlets)
{
   int   i;
   int   j;
   int   t;

   for( i = 1; i < n; i++)
      for( j = i; j > 0 && cmp_tap( &order[ j - 1], &order[ j], (void *) outlets) > 0; j--)
      {
         t            = order[ j];
         order[ j]    = order[ j - 1];
         order[ j - 1] = t;
      }
}


- (void) advanceFrom:(BGTime) t0
                  to:(BGTime) t1
               world:(BGWorld *) world
           committer:(BGCommitter *) committer
{
   BGProposalGroup   *group;
   int64_t           granted[ BG_FLUID_MAX];
   int64_t           requested[ BG_FLUID_MAX];
   int64_t           carry[ BG_FLUID_MAX];
   int               order[ BG_FLUID_MAX];
   int64_t           demand;
   int64_t           dt;
   int64_t           left;
   int64_t           supply;
   int64_t           total;
   uint64_t          step;
   int               i;
   int               k;
   int               n;
   int               s;

   dt = t1.ms - t0.ms;
   if( ! _active || dt <= 0)
      return;
   step = [world boundary] + 1;
   for( s = 0; s < _nholders; s++)
   {
      /* the outlets on this store, in tap-ID order whatever the inside order */
      n = 0;
      for( i = 0; i < _noutlets; i++)
         if( _outlets[ i].source == s && ! _outlets[ i].exhausted)
            order[ n++] = i;
      if( ! n)
         continue;
      sort_by_tap( order, n, _outlets);
      demand = 0;
      for( k = 0; k < n; k++)
      {
         i             = order[ k];
         requested[ i] = delivered( &_outlets[ i], dt);
         carry[ i]     = (_outlets[ i].rate * dt + _outlets[ i].carry) % BG_MS_PER_MINUTE;
         demand       += requested[ i];
      }
      supply = _holders[ s].water;
      if( demand <= supply)
      {
         for( k = 0; k < n; k++)
         {
            i                  = order[ k];
            granted[ i]        = requested[ i];
            _outlets[ i].carry = carry[ i];
         }
      }
      else
      {
         /* pro rata; what's left goes one each in tap order, rotated by the step */
         left = supply;
         for( k = 0; k < n; k++)
         {
            i                  = order[ k];
            granted[ i]        = (int64_t) ((__int128) supply * requested[ i] / demand);
            left              -= granted[ i];
            _outlets[ i].carry = 0;
         }
         for( k = 0; left > 0; k++)
         {
            i = order[ (int) ((step + (uint64_t) k) % (uint64_t) n)];
            if( granted[ i] < requested[ i])
            {
               granted[ i]++;
               left--;
            }
         }
      }
      total = 0;
      for( k = 0; k < n; k++)
      {
         i      = order[ k];
         total += granted[ i];
         _holders[ _outlets[ i].destination].water += granted[ i];
         [_log addObject:[NSString stringWithFormat:@"t=%lld: tap %llu requested %lldmL, granted %lldmL",
                                                    (long long) t1.ms, (unsigned long long) _outlets[ i].tap,
                                                    (long long) requested[ i], (long long) granted[ i]]];
      }
      _holders[ s].water -= total;
      assert( _holders[ s].water >= 0);       /* no step drives a stock negative */

      /* run dry: every tap on it says so, in this step */
      if( _holders[ s].water == 0)
      {
         group = [BGProposalGroup groupWithPhase:BGPhaseProcess
                                          source:[NSString stringWithFormat:@"fluid: %llu ran dry",
                                                                            (unsigned long long) _holders[ s].entity]];
         for( k = 0; k < n; k++)
         {
            i                      = order[ k];
            _outlets[ i].exhausted = YES;
            [group emit:"exhausted"
                subject:BGWhole( _outlets[ i].tap)
                  other:BGWhole( _holders[ s].entity)];
         }
         [committer submit:group];
      }
   }
   if( ! [self flowing])
      [self checkInAll];
}

@end

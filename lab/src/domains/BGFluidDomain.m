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
   free( _holders);
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


static int   cmp_floor( const void *a, const void *b)
{
   const int32_t   *p;
   const int32_t   *q;
   int             k;

   p = a;
   q = b;
   for( k = 2; k >= 0; k--)
      if( p[ k] != q[ k])
         return( p[ k] < q[ k] ? -1 : 1);
   return( 0);
}


/* Whether water can lie on a tile: one of the map, not solid. */
- (BOOL) floorX:(int32_t) x
              y:(int32_t) y
          level:(int32_t) level
{
   return( [_world isTileX:x y:y level:level] &&
           ! ([_world terrain] && BGTerrainSolid( [_world terrain], x, y, level)));
}


/* The floor the domain works on: wet tiles and their neighbours (not
 * walls), and the tiles below the taps, in (level, y, x) order; read from
 * what is wet, not the map. */
- (int) region:(int32_t (**)[ 3]) result
         views:(BGTapView *) views
         count:(int) nviews
{
   int32_t            (*tiles)[ 3];
   static const int   dx[ 5] = { 0, 1, -1, 0, 0 };
   static const int   dy[ 5] = { 0, 0, 0, 1, -1 };
   int32_t            (*wet)[ 3];
   int32_t            (*all)[ 3];
   NSUInteger         nwet;
   NSUInteger         nall;
   NSUInteger         i;
   int                d;
   int                n;

   nwet = [_world wetTiles:NULL max:0];
   wet  = malloc( (nwet ? nwet : 1) * sizeof( *wet));
   [_world wetTiles:wet max:nwet];
   all  = malloc( (nwet * 5 + (NSUInteger) nviews + 1) * sizeof( *all));
   nall = 0;
   for( i = 0; i < nwet; i++)
      for( d = 0; d < 5; d++)
         if( [self floorX:wet[ i][ 0] + dx[ d] y:wet[ i][ 1] + dy[ d] level:wet[ i][ 2]])
         {
            all[ nall][ 0] = wet[ i][ 0] + dx[ d];
            all[ nall][ 1] = wet[ i][ 1] + dy[ d];
            all[ nall][ 2] = wet[ i][ 2];
            nall++;
         }
   for( i = 0; i < (NSUInteger) nviews; i++)
      if( ! views[ i].destination && [_world isTileX:views[ i].x y:views[ i].y level:views[ i].level])
      {
         all[ nall][ 0] = views[ i].x;
         all[ nall][ 1] = views[ i].y;
         all[ nall][ 2] = views[ i].level;
         nall++;
      }
   qsort( all, nall, sizeof( *all), cmp_floor);
   tiles = malloc( (nall ? nall : 1) * sizeof( *tiles));
   n     = 0;
   for( i = 0; i < nall; i++)
      if( ! i || cmp_floor( all[ i], all[ i - 1]))
      {
         tiles[ n][ 0] = all[ i][ 0];
         tiles[ n][ 1] = all[ i][ 1];
         tiles[ n][ 2] = all[ i][ 2];
         n++;
      }
   free( all);
   free( wet);
   *result = tiles;
   return( n);
}


static uint64_t   signature( BGTapView *views, int n, int32_t (*tiles)[ 3], int ntiles)
{
   uint64_t   h;
   int        i;

   h = BGMix( (uint64_t) n ^ ((uint64_t) ntiles << 32));
   for( i = 0; i < ntiles; i++)
      h = BGMix( h ^ (uint64_t) (uint32_t) tiles[ i][ 0] ^ ((uint64_t) (uint32_t) tiles[ i][ 1] << 16));
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

   /* a tile of the region, after the outlets': only the outlets' to look
    * through, for a tap's tile; the region has each tile once */
   for( i = 0; i < (entity || _firstTile < 0 ? _nholders : _firstTile); i++)
      if( entity ? _holders[ i].entity == entity
                 : (! _holders[ i].entity && _holders[ i].x == x && _holders[ i].y == y && _holders[ i].level == level))
         return( i);
   if( _nholders == _holdercap)
   {
      _holdercap = _holdercap ? _holdercap * 2 : 64;
      _holders   = realloc( _holders, (size_t) _holdercap * sizeof( BGFluidHolder));
   }
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
            tiles:(int32_t (*)[ 3]) tiles
           ntiles:(int) ntiles
{
   BGFluidOutlet   *o;
   int             i;
   int             k;
   int             m;

   _nholders  = 0;
   _noutlets  = 0;
   _firstTile = -1;
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
   _firstTile = _nholders;
   for( k = 0; k < ntiles; k++)
   {
      i = _reversed ? ntiles - 1 - k : k;
      [self holderFor:BGNoEntity x:tiles[ i][ 0] y:tiles[ i][ 1] level:tiles[ i][ 2]];
   }
   _firstTile = -1;
   _active    = YES;
}


/* The tile holders, by (level, y, x), to find a tile's neighbours. */
typedef struct
{
   int32_t   x;
   int32_t   y;
   int32_t   level;
   int       holder;
} BGFloorTile;

static int   cmp_floor_tile( const void *a, const void *b)
{
   const BGFloorTile   *p;
   const BGFloorTile   *q;

   p = a;
   q = b;
   if( p->level != q->level)
      return( p->level < q->level ? -1 : 1);
   if( p->y != q->y)
      return( p->y < q->y ? -1 : 1);
   return( p->x < q->x ? -1 : p->x > q->x);
}


- (int) tileIndex:(BGFloorTile *) at
{
   int   i;
   int   n;

   for( n = 0, i = 0; i < _nholders; i++)
      if( ! _holders[ i].entity)
      {
         at[ n].x      = _holders[ i].x;
         at[ n].y      = _holders[ i].y;
         at[ n].level  = _holders[ i].level;
         at[ n].holder = i;
         n++;
      }
   qsort( at, n, sizeof( *at), cmp_floor_tile);
   return( n);
}


/* The holder of the tile east (d 0) or south (d 1) of one, or -1. */
static int   neighbour( const BGFloorTile *at, int n, const BGFloorTile *t, int d)
{
   BGFloorTile   key;
   BGFloorTile   *found;

   key       = *t;
   key.x    += d ? 0 : 1;
   key.y    += d ? 1 : 0;
   found     = bsearch( &key, at, n, sizeof( *at), cmp_floor_tile);
   return( found ? found->holder : -1);
}


/* Whether some pair of adjacent tiles differs by enough to move water. */
- (BOOL) spreading
{
   BGFloorTile   *at;
   int64_t       diff;
   BOOL          moves;
   int           n;
   int           k;
   int           i;
   int           j;
   int           d;

   at    = malloc( (size_t) (_nholders ? _nholders : 1) * sizeof( BGFloorTile));
   n     = [self tileIndex:at];
   moves = NO;
   for( k = 0; k < n && ! moves; k++)
      for( d = 0; d < 2; d++)
      {
         i = at[ k].holder;
         if( (j = neighbour( at, n, &at[ k], d)) >= 0 &&
             ((diff = _holders[ i].water - _holders[ j].water) >= 8 || diff <= -8))
            moves = YES;
      }
   free( at);
   return( moves);
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
   return( [self spreading]);
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


/* --- watches ----------------------------------------------------------------- */

typedef struct
{
   BGEntityID   activity;
   int          holder;
   int64_t      atLeast;
} BGFluidWatch;


/* The watches of running activities on holders in the structure. */
- (int) watches:(BGFluidWatch *) out
{
   const BGActivity   *record;
   BGEntityID         *watching;
   NSUInteger         count;
   TriType            running;
   NSUInteger         i;
   int                h;
   int                n;

   watching = [_world copyWatchingActivities:&count];      /* the world's index of watches */
   running  = tri_type_named( [_world tri], "\"running\"");
   n        = 0;
   for( i = 0; i < count && n < BG_FLUID_MAX; i++)
   {
      record = [_world record:[_world kindNamed:"Activity"] for:watching[ i]];
      if( ! record || (! record->watchHolder && ! record->watchFloor) || record->status != (uint32_t) running)
         continue;
      /* a watch on a holder, or on a tile of the floor */
      for( h = 0; h < _nholders; h++)
         if( record->watchFloor ? _holders[ h].entity == BGNoEntity && _holders[ h].x == record->watchX &&
                                  _holders[ h].y == record->watchY && _holders[ h].level == record->watchLevel
                                : _holders[ h].entity == (BGEntityID) record->watchHolder)
         {
            out[ n].activity = watching[ i];
            out[ n].holder   = h;
            out[ n].atLeast  = record->watchFloor ? record->watchFloor : record->watchAtLeast;
            n++;
            break;
         }
   }
   free( watching);
   return( n);
}


- (BOOL) hasFired:(BGEntityID) activity
{
   int   i;

   for( i = 0; i < _nfired; i++)
      if( _fired[ i] == activity)
         return( YES);
   return( NO);
}


/* Forget fired watches whose activities no longer watch. */
- (void) pruneFired:(BGFluidWatch *) watches
              count:(int) n
{
   int    i;
   int    j;
   int    k;
   BOOL   live;

   for( i = k = 0; i < _nfired; i++)
   {
      for( live = NO, j = 0; j < n && ! live; j++)
         live = watches[ j].activity == _fired[ i];
      if( live)
         _fired[ k++] = _fired[ i];
   }
   _nfired = k;
}


/* The first step at which the inflow brings a holder to the threshold. Never
 * later than the true time: a source running dry first only delays it. */
- (BGTime) crossingOf:(BGFluidWatch *) w
                   at:(BGTime) t
{
   int64_t   hi;
   int64_t   lo;
   int64_t   mid;
   int64_t   need;
   int64_t   rate;
   int64_t   sum;
   int       i;
   int       n;

   need = w->atLeast - _holders[ w->holder].water;
   if( need <= 0)
      return( t);
   rate = 0;
   n    = 0;
   for( i = 0; i < _noutlets; i++)
      if( _outlets[ i].destination == w->holder && ! _outlets[ i].exhausted)
      {
         rate += _outlets[ i].rate;
         n++;
      }
   if( ! rate)
      return( BGTimeNever);
   lo = 1;
   hi = ((need + n) * BG_MS_PER_MINUTE + rate - 1) / rate;
   while( lo < hi)
   {
      mid = (lo + hi) / 2;
      sum = 0;
      for( i = 0; i < _noutlets; i++)
         if( _outlets[ i].destination == w->holder && ! _outlets[ i].exhausted)
            sum += delivered( &_outlets[ i], mid);
      if( sum >= need)
         hi = mid;
      else
         lo = mid + 1;
   }
   return( BGTimeMake( t.ms + lo));
}


- (BGHorizon) horizonAt:(BGTime) t
{
   BGFluidWatch   watches[ BG_FLUID_MAX];
   BGTapView      views[ BG_FLUID_MAX];
   int32_t        (*tiles)[ 3];
   int            ntiles;
   BGHorizon   h;
   BGTime      next;
   uint64_t    sig;
   int         i;
   int         n;

   h.safeStep  = BGTimeNever;      /* constant rates: any step is exact */
   h.nextEvent = BGTimeNever;
   n      = [self scan:views];
   ntiles = [self region:&tiles views:views count:n];
   sig    = signature( views, n, tiles, ntiles);
   /* a tap opened or closed, or a bucket moved: check in and form again */
   if( _active && sig != _signature)
      [self checkInAll];
   if( ! _active)
   {
      _signature = sig;
      [self formFrom:views
               count:n
               tiles:tiles
              ntiles:ntiles];
      free( tiles);
      tiles = NULL;
      if( ! [self flowing])
      {
         [self checkInAll];
         return( h);
      }
   }
   free( tiles);
   for( i = 0; i < _nholders; i++)
   {
      next = [self exhaustionOf:i
                             at:t];
      if( next.ms < h.nextEvent.ms)
         h.nextEvent = next;
   }
   if( h.nextEvent.ms != BGTimeNever.ms)
      _predicted = h.nextEvent;
   if( [self spreading])
      h.safeStep = BGTimeMake( BG_SPREAD_TAU);
   /* the activities' watches */
   n = [self watches:watches];
   [self pruneFired:watches
              count:n];
   for( i = 0; i < n; i++)
   {
      if( [self hasFired:watches[ i].activity])
         continue;
      next = [self crossingOf:&watches[ i]
                           at:t];
      if( next.ms < h.nextEvent.ms)
         h.nextEvent = next;
   }
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
   [self spreadFor:dt];
   /* readers (the inspector, perception) see the domain's values; the
      records stay checked out, so nothing else may change them */
   [self mirror];
   /* watches the step brought to their threshold */
   [self reportWatchesTo:committer];
   if( ! [self flowing])
      [self checkInAll];
}


/* Water levelling out across the floor: every adjacent pair from step-start
 * values, then all applied, so no order can matter. */
- (void) spreadFor:(int64_t) dt
{
   BGFloorTile   *at;
   int64_t       *delta;
   int64_t       diff;
   int64_t       q;
   int           n;
   int           k;
   int           i;
   int           j;
   int           d;

   if( dt > BG_SPREAD_TAU)
      dt = BG_SPREAD_TAU;
   at    = malloc( (size_t) (_nholders ? _nholders : 1) * sizeof( BGFloorTile));
   delta = calloc( (size_t) (_nholders ? _nholders : 1), sizeof( int64_t));
   n     = [self tileIndex:at];
   for( k = 0; k < n; k++)
      for( d = 0; d < 2; d++)          /* each pair once: east, south */
      {
         i = at[ k].holder;
         if( (j = neighbour( at, n, &at[ k], d)) < 0)
            continue;
         diff = _holders[ i].water - _holders[ j].water;
         q    = (diff < 0 ? -diff : diff) * dt / (8 * BG_SPREAD_TAU);
         if( ! q)
            continue;
         if( diff > 0)
         {
            delta[ i] -= q;
            delta[ j] += q;
         }
         else
         {
            delta[ i] += q;
            delta[ j] -= q;
         }
      }
   for( i = 0; i < _nholders; i++)
   {
      _holders[ i].water += delta[ i];
      assert( _holders[ i].water >= 0);
   }
   free( delta);
   free( at);
}


- (void) mirror
{
   int   i;

   for( i = 0; i < _nholders; i++)
      if( _holders[ i].entity)
         [_world setField:"WaterStore.water"
                       of:_holders[ i].entity
                    value:_holders[ i].water];
      else
         [_world setWater:_holders[ i].water
                      atX:_holders[ i].x
                        y:_holders[ i].y
                    level:_holders[ i].level];
}


- (void) reportWatchesTo:(BGCommitter *) committer
{
   BGFluidWatch      watches[ BG_FLUID_MAX];
   BGProposalGroup   *group;
   int               i;
   int               n;

   n     = [self watches:watches];
   group = nil;
   for( i = 0; i < n; i++)
   {
      if( [self hasFired:watches[ i].activity] || _holders[ watches[ i].holder].water < watches[ i].atLeast)
         continue;
      if( ! group)
         group = [BGProposalGroup groupWithPhase:BGPhaseProcess
                                          source:@"fluid: watches reached"];
      [group emit:"watched"
          subject:BGWhole( watches[ i].activity)
            other:BGWhole( _holders[ watches[ i].holder].entity)];
      if( _nfired < BG_FLUID_MAX)
         _fired[ _nfired++] = watches[ i].activity;
   }
   if( group)
      [committer submit:group];
}

@end

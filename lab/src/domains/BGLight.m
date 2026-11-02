#import "BGLight.h"

#import "BGActions.h"


#define BG_DAY   86400000LL


/* The tile an entity stands on, or is on through what holds it. */
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


/* The authored daylight: dawn, nightfall, and the twilight either side. */
static BOOL   authored_daylight( BGWorld *world, int64_t *dawn, int64_t *nightfall, int64_t *twilight)
{
   const TriNode   *pattern;
   const TriNode   *v;
   TriContent      *tri;
   TriIndex        *family;
   int64_t         lo;
   int64_t         hi;

   tri     = [world tri];
   family  = tri_family_index( tri, "light");
   pattern = family && tri_index_count( family) ? tri_pattern( tri, tri_index_tag( family, 0)) : NULL;
   if( ! pattern)
      return( NO);
   if( ! (v = tri_at( tri, pattern, "dawn")) || ! tri_node_interval( v, &lo, &hi) || lo != hi)
      return( NO);
   *dawn = lo;
   if( ! (v = tri_at( tri, pattern, "nightfall")) || ! tri_node_interval( v, &lo, &hi) || lo != hi)
      return( NO);
   *nightfall = lo;
   if( ! (v = tri_at( tri, pattern, "twilight")) || ! tri_node_interval( v, &lo, &hi) || lo != hi)
      return( NO);
   *twilight = lo;
   return( YES);
}


/* Daylight outdoors at t: 2 day, 1 twilight, 0 night; day if none is
 * authored. */
static int   outdoors( BGWorld *world, int64_t t)
{
   int64_t   dawn;
   int64_t   nightfall;
   int64_t   twilight;
   int64_t   h;

   if( ! authored_daylight( world, &dawn, &nightfall, &twilight))
      return( 2);
   h = t % BG_DAY;
   if( h >= dawn && h < nightfall)
      return( 2);
   if( (h >= dawn - twilight && h < dawn) || (h >= nightfall && h < nightfall + twilight))
      return( 1);
   return( 0);
}


/* The room over a tile: an air region with a door; none outdoors. */
static const BGGasStore   *room_at( BGWorld *world, BGLocation tile)
{
   const BGGasStore   *air;

   air = [world record:[world kindNamed:"GasStore"] for:[world airRegionAt:tile]];
   return( air && air->door ? air : NULL);
}


int64_t   BGLampOil( const BGLamp *lamp, int64_t t)
{
   int64_t   left;

   left = lamp->oil;
   if( lamp->shining && t > lamp->oilAt)
      left -= t - lamp->oilAt;
   return( left < 0 ? 0 : left);
}


int   BGLightAt( BGWorld *world, BGLocation tile, int64_t t)
{
   const BGGasStore   *room;
   const BGLamp       *lamp;
   const BGCombustor  *fire;
   BGStore            *store;
   BGLocation         at;
   NSUInteger         i;
   int64_t            ajar;
   int                light;

   /* the day, shaded indoors unless the door is open */
   light = outdoors( world, t);
   if( light > 0 && (room = room_at( world, tile)) &&
       ! ([world getField:"Door.ajar" of:(BGEntityID) room->door value:&ajar] && ajar))
      light--;
   /* lamps with oil left, shining */
   store = [world storeForKind:[world kindNamed:"Lamp"]];
   for( i = 0; light < 2 && i < [store count]; i++)
   {
      lamp = [store recordAtIndex:i];
      if( lamp->shining && BGLampOil( lamp, t) > 0 && ground_tile( world, [store entityAtIndex:i], &at) &&
          at.level == tile.level && abs( at.x - tile.x) <= lamp->reach && abs( at.y - tile.y) <= lamp->reach)
         light = 2;
   }
   /* fires, a tile round */
   store = [world storeForKind:[world kindNamed:"Combustor"]];
   for( i = 0; light < 2 && i < [store count]; i++)
   {
      fire = [store recordAtIndex:i];
      if( fire->lit && ground_tile( world, [store entityAtIndex:i], &at) && at.level == tile.level &&
          abs( at.x - tile.x) <= 1 && abs( at.y - tile.y) <= 1)
         light = 2;
   }
   return( light);
}


@implementation BGLight

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
   return( @"light");
}


- (BOOL) isActive
{
   return( YES);
}


/* The next change of the daylight, or the next lamp to burn out. */
- (BGHorizon) horizonAt:(BGTime) t
{
   const BGLamp   *lamp;
   BGStore        *lamps;
   BGHorizon      h;
   NSUInteger     i;
   int64_t        marks[ 4];
   int64_t        dawn;
   int64_t        nightfall;
   int64_t        twilight;
   int64_t        day;
   int64_t        when;
   int            k;

   h.safeStep  = BGTimeNever;
   h.nextEvent = BGTimeNever;
   if( authored_daylight( _world, &dawn, &nightfall, &twilight))
   {
      marks[ 0] = dawn - twilight;
      marks[ 1] = dawn;
      marks[ 2] = nightfall;
      marks[ 3] = nightfall + twilight;
      for( day = t.ms - t.ms % BG_DAY; day <= t.ms + BG_DAY; day += BG_DAY)
         for( k = 0; k < 4; k++)
            if( day + marks[ k] > t.ms && day + marks[ k] < h.nextEvent.ms)
               h.nextEvent = BGTimeMake( day + marks[ k]);
   }
   lamps = [_world storeForKind:[_world kindNamed:"Lamp"]];
   for( i = 0; i < [lamps count]; i++)
   {
      lamp = [lamps recordAtIndex:i];
      if( ! lamp->shining || lamp->oil <= 0)
         continue;
      when = lamp->oilAt + lamp->oil;
      if( when > t.ms && when < h.nextEvent.ms)
         h.nextEvent = BGTimeMake( when);
   }
   return( h);
}


/* A lamp spent by t1 goes out. */
- (void) advanceFrom:(BGTime) t0
                  to:(BGTime) t1
               world:(BGWorld *) world
           committer:(BGCommitter *) committer
{
   const BGLamp      *lamp;
   BGProposalGroup   *group;
   BGStore           *lamps;
   NSUInteger        i;

   lamps = [world storeForKind:[world kindNamed:"Lamp"]];
   group = nil;
   for( i = 0; i < [lamps count]; i++)
   {
      lamp = [lamps recordAtIndex:i];
      if( ! lamp->shining || BGLampOil( lamp, t1.ms) > 0)
         continue;
      if( ! group)
         group = [BGProposalGroup groupWithPhase:BGPhaseProcess source:@"light: a lamp burns out"];
      [group set:"Lamp.shining" of:BGWhole( [lamps entityAtIndex:i]) to:0];
      [group set:"Lamp.oil" of:BGWhole( [lamps entityAtIndex:i]) to:0];
      [group set:"Lamp.oilAt" of:BGWhole( [lamps entityAtIndex:i]) to:t1.ms];
   }
   if( group)
      [committer submit:group];
}


- (void) checkInAll
{
}


- (NSArray *) savedState
{
   return( [NSArray array]);
}


- (void) restoreSavedState:(NSArray *) lines
{
}

@end

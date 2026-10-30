#import "BGKnowledge.h"

#import "BGView.h"

#include <stdio.h>
#include <stdlib.h>


static inline int64_t   max64( int64_t a, int64_t b)
{
   return( a > b ? a : b);
}


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


static int   depth_of( BGWorld *world, BGEntityID e)
{
   BGLocation   loc;
   int          d;

   for( d = 0; d < 64; d++)
   {
      loc = [world locationOf:e];
      if( loc.form == BGLocationOnTile || loc.form == BGLocationNone || ! loc.place)
         return( d);
      e = loc.place;
   }
   return( d);
}


static void   append_quoted( NSMutableString *s, const char *text)
{
   [s appendString:@"\""];
   for( ; text && *text; text++)
      if( *text != '"' && *text != '\n')
         [s appendFormat:@"%c", *text];
   [s appendString:@"\""];
}


/* --- a store ------------------------------------------------------------------- */

@implementation BGKnowledgeStore

- (id) initWithAgent:(BGEntityID) agent
{
   int   i;

   if( ! (self = [super init]))
      return( nil);
   _agent = agent;
   _next  = 1;
   _news  = [NSMutableArray new];
   for( i = 0; i < 32 * 32; i++)
      _seenAt[ i] = -1;
   return( self);
}


- (void) dealloc
{
   NSUInteger   i;

   for( i = 0; i < _count; i++)
   {
      free( _referents[ i].kind);
      free( _referents[ i].features);
   }
   free( _referents);
   [_news release];
   [super dealloc];
}


- (BGEntityID) agent
{
   return( _agent);
}


- (uint32_t) selfReferent
{
   return( _self);
}


- (NSUInteger) count
{
   return( _count);
}


- (const BGReferent *) referentAt:(NSUInteger) i
{
   return( &_referents[ i]);
}


- (BGReferent *) mutableReferent:(uint32_t) referentID
{
   NSUInteger   i;

   for( i = 0; i < _count; i++)
      if( _referents[ i].id == referentID)
         return( &_referents[ i]);
   return( NULL);
}


- (const BGReferent *) referent:(uint32_t) referentID
{
   return( [self mutableReferent:referentID]);
}


- (int64_t) tileSeenAtX:(int32_t) x
                      y:(int32_t) y
{
   if( x < 0 || x >= 32 || y < 0 || y >= 32)
      return( -1);
   return( _seenAt[ y * 32 + x]);
}


- (void) setTileSeen:(int64_t) t
                   x:(int32_t) x
                   y:(int32_t) y
{
   if( x >= 0 && x < 32 && y >= 0 && y < 32)
      _seenAt[ y * 32 + x] = t;
}


- (NSArray *) news
{
   return( _news);
}


- (NSMutableArray *) mutableNews
{
   return( _news);
}


/* A new referent, with the given id (restoring) or the next one (0). */
- (BGReferent *) addReferent:(uint32_t) referentID
{
   BGReferent   *r;

   if( _count == _capacity)
   {
      _capacity  = _capacity ? _capacity * 2 : 16;
      _referents = realloc( _referents, sizeof( BGReferent) * _capacity);
   }
   r = &_referents[ _count++];
   memset( r, 0, sizeof( *r));
   r->insideSeen = -1;
   r->id = referentID ? referentID : _next;
   if( r->id >= _next)
      _next = r->id + 1;
   return( r);
}


- (uint32_t) nextID
{
   return( _next);
}


- (void) setNextID:(uint32_t) next
            self:(uint32_t) selfReferent
{
   _next = next;
   _self = selfReferent;
}


- (void) setSelf:(uint32_t) selfReferent
{
   _self = selfReferent;
}


- (NSString *) describeReferent:(uint32_t) referentID
{
   const BGReferent   *r;
   NSMutableString    *s;

   r = [self referent:referentID];
   if( ! r)
      return( nil);
   s = [NSMutableString stringWithFormat:@"%s & { id: ref(%u)", r->kind, r->id];
   switch( r->form)
   {
   case BGLocationIn:
      [s appendFormat:@", place: #Inside & { container: ref(%u) }", r->container];
      break;
   case BGLocationHeldBy:
      [s appendFormat:@", place: #Held & { by: ref(%u), hand: %d }", r->container, r->slot];
      break;
   case BGLocationPartOf:
      [s appendFormat:@", place: #Installed & { assembly: ref(%u), role: ", r->container];
      append_quoted( s, r->role);
      [s appendFormat:@", index: %d }", r->slot];
      break;
   default:
      [s appendFormat:@", place: #OnTile & { x: %d, y: %d, level: %d }", r->x, r->y, r->level];
      break;
   }
   if( r->features && *r->features)
      [s appendFormat:@", %s", r->features];
   [s appendString:@" }"];
   return( s);
}

@end


/* --- the system ------------------------------------------------------------------ */

@implementation BGKnowledge

- (id) initWithWorld:(BGWorld *) world
{
   if( ! (self = [super init]))
      return( nil);
   _world      = [world retain];
   _stores     = [NSMutableArray new];
   _eventsSeen = [world eventCount];
   return( self);
}


- (void) dealloc
{
   [_world release];
   [_stores release];
   [super dealloc];
}


- (NSString *) name
{
   return( @"knowledge");
}


- (void) setOmniscient:(BOOL) flag
{
   _omniscient = flag;
}


- (BGKnowledgeStore *) storeOf:(BGEntityID) agent
{
   BGKnowledgeStore   *store;
   NSUInteger         i;

   for( i = 0; i < [_stores count]; i++)
   {
      store = [_stores objectAtIndex:i];
      if( [store agent] == agent)
         return( store);
      if( [store agent] > agent)
         break;
   }
   store = [[[BGKnowledgeStore alloc] initWithAgent:agent] autorelease];
   [_stores insertObject:store atIndex:i];
   return( store);
}


/* --- perception ------------------------------------------------------------------ */

static BOOL   contains( BGEntityID *set, NSUInteger n, BGEntityID e)
{
   NSUInteger   i;

   for( i = 0; i < n; i++)
      if( set[ i] == e)
         return( YES);
   return( NO);
}


typedef struct
{
   BGEntityID   entity;
   int          depth;
} BGSeen;


static int   cmp_seen( const void *a, const void *b)
{
   const BGSeen   *x;
   const BGSeen   *y;

   x = a;
   y = b;
   if( x->depth != y->depth)
      return( x->depth < y->depth ? -1 : 1);
   return( x->entity < y->entity ? -1 : x->entity > y->entity);
}


- (void) perceive:(BGKnowledgeStore *) store
             from:(NSUInteger) first
               to:(NSUInteger) last
{
   const BGEvent      *ev;
   BGReferent         *r;
   BGStore            *bodies;
   BGView             *view;
   BGSeen             *seen;
   BGEntityID         lookedIn[ 64];
   BGEntityID         agent;
   BGLocation         here;
   BGLocation         at;
   BGLocation         tile;
   NSMutableArray     *news;
   NSString           *kind;
   NSString           *features;
   uint32_t           *assigned;      /* per visible entity: its referent */
   uint8_t            *taken;         /* per referent index: matched this phase */
   uint32_t           container;
   NSUInteger         nlooked;
   NSUInteger         nseen;
   NSUInteger         i;
   NSUInteger         j;
   NSUInteger         best;
   int64_t            now;
   int32_t            x;
   int32_t            y;
   int                pass;
   int                d;
   int                bestd;
   BOOL               exact;

   agent = [store agent];
   news  = [store mutableNews];
   [news removeAllObjects];
   if( ! [_world isLive:agent] || ! ground_tile( _world, agent, &here))
      return;
   now = [_world time].ms;

   /* what the agent looked into this boundary: where it put something, or reached */
   nlooked = 0;
   for( i = first; i < last && nlooked < 64; i++)
   {
      ev = [_world eventAt:i];
      if( ev->actor != agent)
         continue;
      if( ev->location.form == BGLocationIn && ev->location.place)
         lookedIn[ nlooked++] = ev->location.place;
      else if( (! strcmp( ev->kind, "attempted") || ! strcmp( ev->kind, "looked")) && ev->other)
         lookedIn[ nlooked++] = ev->other;
      /* reaching for something in a container: taking from a stack in the bin */
      if( nlooked < 64 && ev->other && [_world locationOf:ev->other].form == BGLocationIn)
         lookedIn[ nlooked++] = [_world locationOf:ev->other].place;
      if( nlooked < 64 && ev->subject && [_world locationOf:ev->subject].form == BGLocationIn)
         lookedIn[ nlooked++] = [_world locationOf:ev->subject].place;
   }

   /* what is in sight, holders before what they hold */
   bodies = [_world storeForKind:[_world kindNamed:"Body"]];
   seen   = malloc( sizeof( BGSeen) * ([bodies count] + 1));
   nseen  = 0;
   for( i = 0; i < [bodies count]; i++)
   {
      BGEntityID   e;

      e = [bodies entityAtIndex:i];
      if( ! ground_tile( _world, e, &tile) ||
          (! _omniscient && (tile.level != here.level ||
                             abs( tile.x - here.x) > BG_SIGHT || abs( tile.y - here.y) > BG_SIGHT)))
         continue;
      at = [_world locationOf:e];
      if( at.form == BGLocationIn && ! _omniscient && ! contains( lookedIn, nlooked, at.place))
         continue;          /* inside, unseen */
      seen[ nseen].entity = e;
      seen[ nseen].depth  = depth_of( _world, e);
      nseen++;
   }
   qsort( seen, nseen, sizeof( BGSeen), cmp_seen);
   for( y = here.y - BG_SIGHT; y <= here.y + BG_SIGHT; y++)
      for( x = here.x - BG_SIGHT; x <= here.x + BG_SIGHT; x++)
         [store setTileSeen:now x:x y:y];

   /* recognition: the same kind, at that very place first, then the nearest */
   view     = [BGView viewOf:agent inWorld:_world];
   assigned = calloc( nseen + 1, sizeof( uint32_t));
   taken    = calloc( [store count] + nseen + 1, 1);
   for( pass = 0; pass < 2; pass++)
      for( i = 0; i < nseen; i++)
      {
         if( assigned[ i])
            continue;
         kind = [view kindOf:seen[ i].entity];
         at   = [_world locationOf:seen[ i].entity];
         ground_tile( _world, seen[ i].entity, &tile);
         container = 0;
         for( j = 0; j < i; j++)
            if( seen[ j].entity == at.place)
               container = assigned[ j];
         if( seen[ i].entity == agent)
         {
            /* an agent knows itself */
            if( ! [store selfReferent])
               [store setSelf:[store addReferent:0]->id];
            r = [store mutableReferent:[store selfReferent]];
         }
         else
         {
            best  = NSNotFound;
            bestd = 1 << 30;
            for( j = 0; j < [store count]; j++)
            {
               r = (BGReferent *) [store referentAt:j];
               if( taken[ j] || r->id == [store selfReferent] || ! r->kind || strcmp( r->kind, [kind UTF8String]))
                  continue;
               exact = r->present && r->form == at.form && r->container == container &&
                       (container || (r->x == tile.x && r->y == tile.y));
               d = exact ? 0 : (r->present ? 1 : 2) + (int) max64( abs( r->x - tile.x), abs( r->y - tile.y));
               if( pass == 0 && ! exact)
                  continue;
               if( d < bestd)
               {
                  bestd = d;
                  best  = j;
               }
            }
            if( best == NSNotFound && pass == 0)
               continue;
            if( best == NSNotFound)
            {
               r = [store addReferent:0];
               [news addObject:[NSString stringWithFormat:@"R%u: %@, at (%d, %d)", r->id, kind, tile.x, tile.y]];
            }
            else
            {
               r = (BGReferent *) [store referentAt:best];
               if( ! (r->present && r->form == at.form && r->container == container &&
                      (container || (r->x == tile.x && r->y == tile.y))))
                  [news addObject:[NSString stringWithFormat:@"R%u is at (%d, %d) now", r->id, tile.x, tile.y]];
            }
         }
         /* the referent takes what was perceived */
         features = [view featuresOf:seen[ i].entity];
         free( r->kind);
         free( r->features);
         r->kind      = strdup( [kind UTF8String]);
         r->features  = strdup( [features UTF8String]);
         r->form      = at.form;
         r->container = container;
         r->x         = tile.x;
         r->y         = tile.y;
         r->level     = tile.level;
         r->slot      = at.slot;
         memcpy( r->role, at.role, sizeof( r->role));
         r->seen      = now;
         r->present   = YES;
         r->truth     = seen[ i].entity;                /* developer-only */
         if( _omniscient || contains( lookedIn, nlooked, seen[ i].entity))
            r->insideSeen = now;
         assigned[ i] = r->id;
         for( j = 0; j < [store count]; j++)
            if( [store referentAt:j]->id == r->id)
               taken[ j] = 1;
      }

   /* absence: believed at a place in sight, and not seen there */
   for( j = 0; j < [store count]; j++)
   {
      const BGReferent   *holder;

      r = (BGReferent *) [store referentAt:j];
      if( taken[ j] || ! r->present)
         continue;
      if( ! _omniscient && (r->level != here.level || abs( r->x - here.x) > BG_SIGHT || abs( r->y - here.y) > BG_SIGHT))
         continue;
      if( r->form == BGLocationIn && ! _omniscient)
      {
         holder = [store referent:r->container];
         if( ! holder || ! contains( lookedIn, nlooked, holder->truth))
            continue;       /* inside, and not looked into: nothing to contradict it */
      }
      r->present = NO;
      [news addObject:[NSString stringWithFormat:@"R%u is not where it was", r->id]];
   }
   free( seen);
   free( assigned);
   free( taken);
}


- (void) perceiveBoundary:(uint64_t) boundary
{
   BGStore      *agents;
   NSUInteger   i;
   NSUInteger   last;

   last   = [_world eventCount];
   agents = [_world storeForKind:[_world kindNamed:"Agent"]];
   /* in stable ID order; each depends only on the world and its own store */
   for( i = 0; i < [agents count]; i++)
      [self perceive:[self storeOf:[agents entityAtIndex:i]]
                from:_eventsSeen
                  to:last];
   _eventsSeen = last;
}


/* --- the developer's view ---------------------------------------------------------- */

- (NSString *) dump:(BGEntityID) agent
{
   BGKnowledgeStore   *store;
   const BGReferent   *r;
   NSMutableString    *s;
   NSUInteger         i;

   store = [self storeOf:agent];
   s     = [NSMutableString stringWithFormat:@"what %llu knows (self R%u):\n", (unsigned long long) agent,
                                             [store selfReferent]];
   for( i = 0; i < [store count]; i++)
   {
      r = [store referentAt:i];
      [s appendFormat:@"  R%u %s, seen at %lldms%s, truth %llu%@: %@\n", r->id, r->kind, (long long) r->seen,
                      r->present ? "" : ", not there any more", (unsigned long long) r->truth,
                      r->insideSeen >= 0 ? [NSString stringWithFormat:@", inside seen at %lldms", (long long) r->insideSeen]
                                         : @"",
                      [store describeReferent:r->id]];
   }
   return( s);
}


/* --- saves --------------------------------------------------------------------------- */

static NSString   *encode( const char *s)
{
   NSMutableString   *out;

   out = [NSMutableString string];
   for( ; s && *s; s++)
      if( *s == ' ' || *s == '%' || *s == '\n')
         [out appendFormat:@"%%%02x", (unsigned char) *s];
      else
         [out appendFormat:@"%c", *s];
   if( ! [out length])
      [out appendString:@"%"];
   return( out);
}


static char   *decode( const char *s)
{
   char     *out;
   char     *w;
   unsigned  c;

   out = malloc( strlen( s) + 1);
   w   = out;
   if( ! strcmp( s, "%"))
      s = "";
   while( *s)
   {
      if( *s == '%' && s[ 1] && s[ 2] && sscanf( s + 1, "%2x", &c) == 1)
      {
         *w++ = (char) c;
         s   += 3;
         continue;
      }
      *w++ = *s++;
   }
   *w = 0;
   return( out);
}


- (void) checkInAll
{
}


- (NSArray *) savedState
{
   BGKnowledgeStore   *store;
   const BGReferent   *r;
   NSMutableArray     *lines;
   NSUInteger         i;
   NSUInteger         j;
   int32_t            x;
   int32_t            y;

   lines = [NSMutableArray array];
   for( i = 0; i < [_stores count]; i++)
   {
      store = [_stores objectAtIndex:i];
      [lines addObject:[NSString stringWithFormat:@"store %llu %u %u", (unsigned long long) [store agent],
                                                  [store nextID], [store selfReferent]]];
      for( y = 0; y < 32; y++)
         for( x = 0; x < 32; x++)
            if( [store tileSeenAtX:x y:y] >= 0)
               [lines addObject:[NSString stringWithFormat:@"seen %llu %d %d %lld", (unsigned long long) [store agent],
                                                           x, y, (long long) [store tileSeenAtX:x y:y]]];
      for( j = 0; j < [store count]; j++)
      {
         r = [store referentAt:j];
         [lines addObject:[NSString stringWithFormat:@"ref %llu %u %d %u %d %d %d %d %lld %lld %d %llu %@ %@ %@",
                                                     (unsigned long long) [store agent], r->id, (int) r->form,
                                                     r->container, r->x, r->y, r->level, r->slot, (long long) r->seen,
                                                     (long long) r->insideSeen, r->present ? 1 : 0, (unsigned long long) r->truth,
                                                     encode( r->role), encode( r->kind), encode( r->features)]];
      }
   }
   return( lines);
}


- (void) restoreSavedState:(NSArray *) lines
{
   BGKnowledgeStore     *store;
   BGReferent           *r;
   unsigned long long   agent;
   unsigned long long   truth;
   long long            seen;
   long long            inside;
   unsigned             id;
   unsigned             next;
   unsigned             me;
   unsigned             container;
   int                  form;
   int                  x;
   int                  y;
   int                  level;
   int                  slot;
   int                  present;
   char                 role[ 64];
   char                 kind[ 512];
   char                 features[ 4096];
   char                 *text;
   NSUInteger           i;

   [_stores removeAllObjects];
   for( i = 0; i < [lines count]; i++)
   {
      text = (char *) [[lines objectAtIndex:i] UTF8String];
      if( sscanf( text, "store %llu %u %u", &agent, &next, &me) == 3)
         [[self storeOf:(BGEntityID) agent] setNextID:next self:me];
      else if( sscanf( text, "seen %llu %d %d %lld", &agent, &x, &y, &seen) == 4)
         [[self storeOf:(BGEntityID) agent] setTileSeen:seen x:x y:y];
      else if( sscanf( text, "ref %llu %u %d %u %d %d %d %d %lld %lld %d %llu %63s %511s %4095s", &agent, &id, &form,
                       &container, &x, &y, &level, &slot, &seen, &inside, &present, &truth, role, kind,
                       features) == 15)
      {
         store        = [self storeOf:(BGEntityID) agent];
         next         = [store nextID];
         r            = [store addReferent:id];
         r->form      = (BGLocationForm) form;
         r->container = container;
         r->x         = x;
         r->y         = y;
         r->level     = level;
         r->slot      = slot;
         r->seen       = seen;
         r->insideSeen = inside;
         r->present    = present != 0;
         r->truth     = (BGEntityID) truth;
         text         = decode( role);
         strncpy( r->role, text, sizeof( r->role) - 1);
         free( text);
         r->kind      = decode( kind);
         r->features  = decode( features);
         [store setNextID:(uint32_t) max64( next, [store nextID]) self:[store selfReferent]];
      }
   }
   _eventsSeen = [_world eventCount];
}

@end

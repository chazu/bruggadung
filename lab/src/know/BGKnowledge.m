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
   for( i = 0; i < _nobservations; i++)
      free( _observations[ i].content);
   free( _observations);
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


- (NSUInteger) observationCount
{
   return( _nobservations);
}


- (const BGObservation *) observationAt:(NSUInteger) i
{
   return( &_observations[ i]);
}


/* `o`'s content is copied */
- (void) addObservation:(BGObservation) o
{
   if( _nobservations == _ocapacity)
   {
      _ocapacity    = _ocapacity ? _ocapacity * 2 : 16;
      _observations = realloc( _observations, sizeof( BGObservation) * _ocapacity);
   }
   o.content                         = o.content ? strdup( o.content) : NULL;
   _observations[ _nobservations++] = o;
}


- (int64_t) lastSaidTo:(uint32_t) referentID
{
   const BGObservation   *o;
   NSUInteger            i;

   for( i = _nobservations; i > 0; i--)
   {
      o = &_observations[ i - 1];
      if( ! strcmp( o->kind, "said") && o->actor == _self && o->other == referentID)
         return( o->time);
   }
   return( -1);
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


static BOOL   node_int( TriContent *tri, const TriNode *node, const char *path, int64_t *value)
{
   const TriNode   *v;
   int64_t         hi;

   v = node ? tri_at( tri, node, path) : NULL;
   return( v && tri_node_interval( v, value, &hi) && *value == hi);
}


/* The features a printed description fixes, without its id and place: what
 * a claim says of a thing, as a referent keeps them. A field left open
 * prints as its bare type, and says nothing. */
static char   *concrete_features( const char *printed)
{
   static const char   *open[] = { "int", "fixed", "text", "ref", "bool", "atom", "mass", "length", "time",
                                   "force", "torque", "heat", "temperature", "volume", "amount", "_", NULL };
   NSMutableString     *out;
   const char          *start;
   const char          *end;
   const char          *p;
   const char          *field;
   NSString            *pair;
   NSString            *key;
   NSString            *value;
   NSRange             colon;
   int                 depth;
   int                 k;
   BOOL                quoted;
   BOOL                keep;

   out   = [NSMutableString string];
   start = strchr( printed, '{');
   end   = strrchr( printed, '}');
   if( ! start || ! end || end < start)
      return( strdup( ""));
   depth  = 0;
   quoted = NO;
   for( field = p = start + 1; p <= end; p++)
   {
      if( *p == '"' && p[ -1] != '\\')
         quoted = ! quoted;
      if( quoted)
         continue;
      if( *p == '{' || *p == '[')
         depth++;
      else if( (*p == '}' || *p == ']') && depth > 0)
         depth--;
      else if( (*p == ',' && ! depth) || p == end)
      {
         pair  = [[[NSString alloc] initWithBytes:(void *) field length:(NSUInteger) (p - field)
                                         encoding:NSUTF8StringEncoding] autorelease];
         pair  = [pair stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
         field = p + 1;
         colon = [pair rangeOfString:@": "];
         if( colon.location == NSNotFound)
            continue;
         key   = [pair substringToIndex:colon.location];
         value = [pair substringFromIndex:colon.location + 2];
         keep  = ! [key isEqualToString:@"id"] && ! [key isEqualToString:@"place"];
         for( k = 0; keep && open[ k]; k++)
            keep = ! [value isEqualToString:[NSString stringWithUTF8String:(char *) open[ k]]];
         if( keep && [value hasPrefix:@"#"] && [value rangeOfString:@" "].location == NSNotFound)
            keep = NO;
         if( keep)
            [out appendFormat:@"%@%@", [out length] ? @", " : @"", pair];
      }
   }
   return( strdup( [out UTF8String]));
}


/* A claim heard becomes a belief (KNOWLEDGE.md §10). For #IsIn: the
 * container, recognized by its kind on the tile the claim gives, or a new
 * referent there; the thing, recognized as one of its kind believed in it,
 * else as one not where it was believed that the claim's description fits,
 * else a new referent; believed in the container, as of the claim's `when`,
 * told by the speaker. */
- (void) believe:(const char *) content
            from:(uint32_t) speaker
              at:(int64_t) now
           store:(BGKnowledgeStore *) store
            news:(NSMutableArray *) news
{
   const TriNode      *claim;
   const TriNode      *what;
   const TriNode      *within;
   const TriNode      *description;
   const BGReferent   *r;
   BGReferent         *m;
   TriContent         *tri;
   TriArena           *arena;
   TriMatchResult     result;
   const char         *kind;
   const char         *ckind;
   const BGReferent   *c;
   int64_t            x;
   int64_t            y;
   int64_t            level;
   int64_t            when;
   uint32_t           cid;
   uint32_t           thing;
   NSUInteger         i;
   int                pass;
   char               printed[ 2048];

   tri   = [_world tri];
   arena = tri_arena_new();
   claim = tri_value( tri, content, arena, NULL, 0);
   if( ! claim || ! tri_subtype( tri, tri_node_type( claim), tri_type_named( tri, "#IsIn")) ||
       ! node_int( tri, claim, "within.place.x", &x) || ! node_int( tri, claim, "within.place.y", &y) ||
       ! node_int( tri, claim, "within.place.level", &level))
   {
      tri_arena_free( arena);
      return;
   }
   if( ! node_int( tri, claim, "when", &when))
      when = now;
   what   = tri_at( tri, claim, "what");
   within = tri_at( tri, claim, "within");
   kind   = tri_type_name( tri, tri_node_type( what));
   ckind  = tri_type_name( tri, tri_node_type( within));

   /* the container */
   cid = 0;
   for( i = 0; i < [store count] && ! cid; i++)
   {
      r = [store referentAt:i];
      if( r->kind && ! strcmp( r->kind, ckind) && r->form == BGLocationOnTile && r->x == x && r->y == y &&
          r->level == level)
         cid = r->id;
   }
   if( ! cid)
   {
      tri_print( tri, within, printed, sizeof( printed));
      m           = [store addReferent:0];
      m->kind     = strdup( ckind);
      m->features = concrete_features( printed);
      m->form     = BGLocationOnTile;
      m->x        = (int32_t) x;
      m->y        = (int32_t) y;
      m->level    = (int32_t) level;
      m->seen     = when;
      m->present  = YES;
      m->toldBy   = speaker;
      cid         = m->id;
      [news addObject:[NSString stringWithFormat:@"R%u: %s, at (%d, %d), R%u says", cid, ckind, (int) x, (int) y,
                                                 speaker]];
   }

   /* the thing */
   thing = 0;
   for( pass = 0; pass < 2 && ! thing; pass++)
      for( i = 0; i < [store count] && ! thing; i++)
      {
         r = [store referentAt:i];
         if( ! r->kind || strcmp( r->kind, kind) || r->id == cid || r->id == [store selfReferent])
            continue;
         if( pass == 0 && r->present && r->form == BGLocationIn && r->container == cid)
            thing = r->id;
         if( pass == 1 && ! r->present)
         {
            description = tri_value( tri, [[store describeReferent:r->id] UTF8String], arena, NULL, 0);
            if( description && tri_match( tri, what, description, &result) != TRI_INCOMPATIBLE)
               thing = r->id;
         }
      }
   if( ! thing)
   {
      tri_print( tri, what, printed, sizeof( printed));
      m           = [store addReferent:0];
      m->kind     = strdup( kind);
      m->features = concrete_features( printed);
      thing       = m->id;
   }
   c            = [store referent:cid];
   m            = [store mutableReferent:thing];
   m->form      = BGLocationIn;
   m->container = cid;
   m->x         = c->x;
   m->y         = c->y;
   m->level     = c->level;
   m->slot      = 0;
   m->role[ 0]  = 0;
   m->seen      = when;
   m->present   = YES;
   m->toldBy    = speaker;
   [news addObject:[NSString stringWithFormat:@"R%u is in R%u, R%u says", thing, cid, speaker]];
   tri_arena_free( arena);
}


/* Whether a percept could be the referent by its looks: the features the
 * referent keeps unify with those perceived. */
- (BOOL) looksAlike:(const BGReferent *) r
               kind:(NSString *) kind
           features:(NSString *) features
{
   const TriNode   *both;
   TriArena        *arena;
   NSString        *expr;

   expr  = [NSString stringWithFormat:@"%@ & { %s } & { %@ }", kind, r->features ? r->features : "", features];
   arena = tri_arena_new();
   both  = tri_value( [_world tri], [expr UTF8String], arena, NULL, 0);
   tri_arena_free( arena);
   return( both != NULL);
}


/* The referent a perceived entity was bound to this phase, or 0. */
static uint32_t   bound_to( BGEntityID e, BGEntityID agent, uint32_t me, const BGSeen *seen, const uint32_t *assigned,
                            NSUInteger nseen)
{
   NSUInteger   i;

   if( e == agent)
      return( me);
   for( i = 0; e && i < nseen; i++)
      if( seen[ i].entity == e)
         return( assigned[ i]);
   return( 0);
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
   BGEntityID         glimpsed[ 64];
   NSUInteger         witnessed[ 64];
   BGObservation      o;
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
   NSUInteger         nglimpsed;
   NSUInteger         nwitnessed;
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

   /* what happens in sight, by an actor it can see (event perception); a
    * thing seen put somewhere is seen there, though nothing else inside is */
   nwitnessed = 0;
   nglimpsed  = 0;
   for( i = first; i < last && nwitnessed < 64; i++)
   {
      ev = [_world eventAt:i];
      if( ! ev->actor || (strcmp( ev->kind, "moved") && strcmp( ev->kind, "said")))
         continue;
      if( ! strcmp( ev->kind, "moved") && ev->subject == ev->actor)
         continue;      /* a step: where the walker is, it is seen */
      if( ! _omniscient && (! ground_tile( _world, ev->actor, &tile) || tile.level != here.level ||
                            abs( tile.x - here.x) > BG_SIGHT || abs( tile.y - here.y) > BG_SIGHT))
         continue;
      witnessed[ nwitnessed++] = i;
      if( ! strcmp( ev->kind, "moved") && nglimpsed < 64)
         glimpsed[ nglimpsed++] = ev->subject;
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
      if( at.form == BGLocationIn && ! _omniscient && ! contains( lookedIn, nlooked, at.place) &&
          ! contains( glimpsed, nglimpsed, e))
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
         kind     = [view kindOf:seen[ i].entity];
         features = [view featuresOf:seen[ i].entity];
         at       = [_world locationOf:seen[ i].entity];
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
               /* elsewhere than believed, it must look the same: the crate isn't the chest */
               if( ! exact && ! [self looksAlike:r kind:kind features:features])
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

   /* what it saw happen, in its referents; what it heard said, believed */
   for( i = 0; i < nwitnessed; i++)
   {
      ev = [_world eventAt:witnessed[ i]];
      memset( &o, 0, sizeof( o));
      o.time  = now;
      o.kind  = ev->kind;
      o.actor = bound_to( ev->actor, agent, [store selfReferent], seen, assigned, nseen);
      if( ! strcmp( ev->kind, "moved"))
      {
         o.subject = bound_to( ev->subject, agent, [store selfReferent], seen, assigned, nseen);
         if( ev->location.form == BGLocationIn || ev->location.form == BGLocationHeldBy)
            o.other = bound_to( ev->location.place, agent, [store selfReferent], seen, assigned, nseen);
         if( o.actor != [store selfReferent])
            [news addObject:[NSString stringWithFormat:@"R%u %s R%u%@", o.actor,
                                                       ev->location.form == BGLocationIn ? "put" :
                                                       ev->location.form == BGLocationHeldBy ? "took" : "moved",
                                                       o.subject,
                                                       ev->location.form == BGLocationIn
                                                          ? [NSString stringWithFormat:@" into R%u", o.other] : @""]];
      }
      else
      {
         o.other   = bound_to( ev->other, agent, [store selfReferent], seen, assigned, nseen);
         o.content = (char *) ev->detail;
         if( o.actor != [store selfReferent])
            [news addObject:[NSString stringWithFormat:@"R%u says to R%u: %s", o.actor, o.other,
                                                       ev->detail ? ev->detail : ""]];
      }
      [store addObservation:o];
      if( ! strcmp( ev->kind, "said") && ev->detail && o.actor && o.actor != [store selfReferent])
         [self believe:ev->detail from:o.actor at:now store:store news:news];
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
   BGKnowledgeStore      *store;
   const BGReferent      *r;
   const BGObservation   *o;
   NSMutableString       *s;
   NSUInteger            i;

   store = [self storeOf:agent];
   s     = [NSMutableString stringWithFormat:@"what %llu knows (self R%u):\n", (unsigned long long) agent,
                                             [store selfReferent]];
   for( i = 0; i < [store count]; i++)
   {
      r = [store referentAt:i];
      [s appendFormat:@"  R%u %s, seen at %lldms%s, truth %llu%@%@: %@\n", r->id, r->kind, (long long) r->seen,
                      r->present ? "" : ", not there any more", (unsigned long long) r->truth,
                      r->insideSeen >= 0 ? [NSString stringWithFormat:@", inside seen at %lldms", (long long) r->insideSeen]
                                         : @"",
                      r->toldBy ? [NSString stringWithFormat:@", told by R%u", r->toldBy] : @"",
                      [store describeReferent:r->id]];
   }
   for( i = 0; i < [store observationCount]; i++)
   {
      o = [store observationAt:i];
      [s appendFormat:@"  at %lldms: R%u %s R%u%@%@\n", (long long) o->time, o->actor, o->kind,
                      ! strcmp( o->kind, "said") ? o->other : o->subject,
                      ! strcmp( o->kind, "moved") && o->other ? [NSString stringWithFormat:@" to R%u", o->other] : @"",
                      o->content ? [NSString stringWithFormat:@": %s", o->content] : @""];
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
   BGKnowledgeStore      *store;
   const BGObservation   *o;
   const BGReferent      *r;
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
         [lines addObject:[NSString stringWithFormat:@"ref %llu %u %d %u %d %d %d %d %lld %lld %u %d %llu %@ %@ %@",
                                                     (unsigned long long) [store agent], r->id, (int) r->form,
                                                     r->container, r->x, r->y, r->level, r->slot, (long long) r->seen,
                                                     (long long) r->insideSeen, r->toldBy, r->present ? 1 : 0, (unsigned long long) r->truth,
                                                     encode( r->role), encode( r->kind), encode( r->features)]];
      }
      for( j = 0; j < [store observationCount]; j++)
      {
         o = [store observationAt:j];
         [lines addObject:[NSString stringWithFormat:@"obs %llu %lld %s %u %u %u %@", (unsigned long long) [store agent],
                                                     (long long) o->time, o->kind, o->actor, o->subject, o->other,
                                                     encode( o->content)]];
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
   unsigned             told;
   BGObservation        o;
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
      else if( sscanf( text, "obs %llu %lld %15s %u %u %u %4095s", &agent, &seen, role, &id, &container, &told,
                       features) == 7)
      {
         memset( &o, 0, sizeof( o));
         o.time    = seen;
         o.kind    = [_world intern:role];
         o.actor   = id;
         o.subject = container;
         o.other   = told;
         o.content = decode( features);
         if( ! *o.content)
         {
            free( o.content);
            o.content = NULL;
         }
         [[self storeOf:(BGEntityID) agent] addObservation:o];
         free( o.content);
      }
      else if( sscanf( text, "ref %llu %u %d %u %d %d %d %d %lld %lld %u %d %llu %63s %511s %4095s", &agent, &id,
                       &form, &container, &x, &y, &level, &slot, &seen, &inside, &told, &present, &truth, role, kind,
                       features) == 16)
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
         r->toldBy     = told;
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

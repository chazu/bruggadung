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
   free( _testimony);
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
   r->trust      = BG_TRUST;
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


- (NSUInteger) testimonyCount
{
   return( _ntestimony);
}


- (const BGTestimony *) testimonyAt:(NSUInteger) i
{
   return( &_testimony[ i]);
}


- (BGTestimony *) mutableTestimonyAt:(NSUInteger) i
{
   return( &_testimony[ i]);
}


- (void) appendTestimony:(BGTestimony) t
{
   if( _ntestimony == _tcapacity)
   {
      _tcapacity = _tcapacity ? _tcapacity * 2 : 16;
      _testimony = realloc( _testimony, sizeof( BGTestimony) * _tcapacity);
   }
   _testimony[ _ntestimony++] = t;
}


/* A source saying the same again replaces what it said before, open: one
 * source is one item, however often it repeats itself. */
- (void) addTestimony:(BGTestimony) t
{
   NSUInteger   i;

   for( i = 0; i < _ntestimony; i++)
      if( _testimony[ i].thing == t.thing && _testimony[ i].container == t.container &&
          _testimony[ i].source == t.source && ! _testimony[ i].settled)
      {
         _testimony[ i] = t;
         return;
      }
   [self appendTestimony:t];
}


- (int32_t) trustIn:(uint32_t) referentID
{
   const BGReferent   *r;

   r = [self referent:referentID];
   return( r ? r->trust : BG_TRUST);
}


- (void) adjustTrustIn:(uint32_t) referentID
                    by:(int32_t) delta
{
   BGReferent   *r;

   if( ! (r = [self mutableReferent:referentID]))
      return;
   r->trust += delta;
   if( r->trust > BG_TRUST_LIMIT)
      r->trust = BG_TRUST_LIMIT;
   if( r->trust < -BG_TRUST_LIMIT)
      r->trust = -BG_TRUST_LIMIT;
}


- (int32_t) weightOf:(const BGTestimony *) t
{
   int32_t   source;
   int32_t   root;

   source = [self trustIn:t->source];
   switch( t->attribution)
   {
   case BGHeardFrom :
      root = [self trustIn:t->root];
      return( (source < root ? source : root) - BG_HEARSAY);
   case BGHeard :
      return( source - BG_RUMOUR);
   default :
      return( source);
   }
}


static BOOL   counts( const BGTestimony *t, uint32_t thing, uint32_t container)
{
   return( t->thing == thing && t->container == container && t->settled >= 0);
}


/* Grouped by perceived root, the strongest of each group counts; testimony
 * whose root is unknown is a group of its own. */
- (int32_t) credenceThat:(uint32_t) thing
                    isIn:(uint32_t) container
{
   const BGTestimony   *t;
   NSUInteger          i;
   NSUInteger          j;
   int32_t             credence;
   int32_t             best;
   int32_t             w;

   credence = BG_PRIOR;
   for( i = 0; i < _ntestimony; i++)
   {
      t = &_testimony[ i];
      if( ! counts( t, thing, container))
         continue;
      if( t->root)
      {
         for( j = 0; j < i; j++)
            if( counts( &_testimony[ j], thing, container) && _testimony[ j].root == t->root)
               break;
         if( j < i)
            continue;      /* its group is counted already */
      }
      best = [self weightOf:t];
      for( j = i + 1; t->root && j < _ntestimony; j++)
         if( counts( &_testimony[ j], thing, container) && _testimony[ j].root == t->root &&
             (w = [self weightOf:&_testimony[ j]]) > best)
            best = w;
      credence += best;
   }
   return( credence);
}


- (const BGTestimony *) strongestThat:(uint32_t) thing
                                 isIn:(uint32_t) container
{
   const BGTestimony   *best;
   NSUInteger          i;

   best = NULL;
   for( i = 0; i < _ntestimony; i++)
      if( counts( &_testimony[ i], thing, container) &&
          (! best || [self weightOf:&_testimony[ i]] > [self weightOf:best]))
         best = &_testimony[ i];
   return( best);
}


- (NSString *) describeLooks:(uint32_t) referentID
{
   const BGReferent   *r;

   r = [self referent:referentID];
   if( ! r || ! r->kind)
      return( nil);
   if( ! r->features || ! *r->features)
      return( [NSString stringWithUTF8String:r->kind]);
   return( [NSString stringWithFormat:@"%s & { %s }", r->kind, r->features]);
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
   free( _ancestry);
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


/* The referent of someone a claim names by how they look ("heard it from
 * ..."): one of that kind that looks alike, the lowest first, or a new one,
 * believed nowhere. 0 if the description says no more than its kind does. */
- (uint32_t) person:(const TriNode *) description
              store:(BGKnowledgeStore *) store
               news:(NSMutableArray *) news
{
   const BGReferent   *r;
   const TriNode      *bare;
   BGReferent         *m;
   TriContent         *tri;
   TriArena           *arena;
   NSString           *kind;
   NSString           *features;
   NSUInteger         i;
   char               printed[ 2048];
   char               *concrete;
   char               *defaults;

   tri  = [_world tri];
   kind = [NSString stringWithUTF8String:(char *) tri_type_name( tri, tri_node_type( description))];
   tri_print( tri, description, printed, sizeof( printed));
   concrete = concrete_features( printed);
   arena    = tri_arena_new();
   bare     = tri_value( tri, [kind UTF8String], arena, NULL, 0);
   printed[ 0] = 0;
   if( bare)
      tri_print( tri, bare, printed, sizeof( printed));
   tri_arena_free( arena);
   defaults = concrete_features( printed);
   if( ! strcmp( concrete, defaults))
   {
      free( concrete);
      free( defaults);
      return( 0);
   }
   free( defaults);
   features = [NSString stringWithUTF8String:concrete];
   for( i = 0; i < [store count]; i++)
   {
      r = [store referentAt:i];
      if( r->id != [store selfReferent] && r->kind && ! strcmp( r->kind, [kind UTF8String]) &&
          [self looksAlike:r kind:kind features:features])
      {
         free( concrete);
         return( r->id);
      }
   }
   m           = [store addReferent:0];
   m->kind     = strdup( [kind UTF8String]);
   m->features = concrete;
   [news addObject:[NSString stringWithFormat:@"R%u: %@, heard of", m->id, kind]];
   return( m->id);
}


/* A claim heard is testimony (KNOWLEDGE.md §10, §11). For #IsIn: the
 * container, recognized by its kind on the tile the claim gives, or a new
 * referent there; the thing, recognized as one of its kind believed in it or
 * claimed to be, else as one not where it was believed that the claim's
 * description fits, else a new referent; and its source and perceived root
 * from the attribution. Once its credence reaches BG_BELIEVE, and no other
 * claim of where it is weighs more, the thing is believed in the container,
 * as of the claim's `when`, told by the speaker. */
- (void) believe:(const char *) content
            from:(uint32_t) speaker
       utterance:(uint64_t) utterance
              at:(int64_t) now
           store:(BGKnowledgeStore *) store
            news:(NSMutableArray *) news
{
   const TriNode      *claim;
   const TriNode      *what;
   const TriNode      *within;
   const TriNode      *attribution;
   const TriNode      *description;
   const BGReferent   *r;
   BGReferent         *m;
   BGTestimony        t;
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
   int32_t            credence;
   uint32_t           cid;
   uint32_t           thing;
   NSUInteger         i;
   NSUInteger         j;
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

   /* who it says saw it */
   memset( &t, 0, sizeof( t));
   t.source      = speaker;
   t.root        = speaker;
   t.attribution = BGSaw;
   attribution   = tri_at( tri, claim, "attribution");
   if( attribution && tri_subtype( tri, tri_node_type( attribution), tri_type_named( tri, "#Heard")))
   {
      description   = tri_at( tri, attribution, "from");
      t.root        = description ? [self person:description store:store news:news] : 0;
      t.attribution = t.root ? BGHeardFrom : BGHeard;
   }

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
         for( j = 0; pass == 0 && ! thing && j < [store testimonyCount]; j++)
            if( [store testimonyAt:j]->thing == r->id && [store testimonyAt:j]->container == cid)
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

   t.thing     = thing;
   t.container = cid;
   t.when      = when;
   t.heard     = now;
   t.utterance = utterance;
   [store addTestimony:t];
   credence = [store credenceThat:thing isIn:cid];

   m = [store mutableReferent:thing];
   if( m->present && m->form == BGLocationIn && m->container == cid)
   {
      [news addObject:[NSString stringWithFormat:@"R%u is in R%u, R%u says too (%+d dB)", thing, cid, speaker,
                                                 credence]];
      tri_arena_free( arena);
      return;
   }
   if( credence < BG_BELIEVE ||
       (m->present && m->toldBy && m->form == BGLocationIn &&
        [store credenceThat:thing isIn:m->container] > credence))
   {
      [news addObject:[NSString stringWithFormat:@"R%u says R%u is in R%u: not believed (%+d dB)", speaker, thing,
                                                 cid, credence]];
      tri_arena_free( arena);
      return;
   }
   c            = [store referent:cid];
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
   [news addObject:[NSString stringWithFormat:@"R%u is in R%u, R%u says (%+d dB)", thing, cid, speaker, credence]];
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


/* Testimony that the thing is inside the container is settled: seen true,
 * and its source and root are trusted more, or found false, and they are
 * trusted less. */
static void   settle( BGKnowledgeStore *store, uint32_t thing, uint32_t container, BOOL true_, NSMutableArray *news)
{
   BGTestimony   *t;
   NSUInteger    i;
   int32_t       delta;

   delta = true_ ? BG_CONFIRMED : -BG_REFUTED;
   for( i = 0; i < [store testimonyCount]; i++)
   {
      t = [store mutableTestimonyAt:i];
      if( t->settled || t->thing != thing || t->container != container)
         continue;
      t->settled = true_ ? 1 : -1;
      [store adjustTrustIn:t->source by:delta];
      if( t->root && t->root != t->source)
         [store adjustTrustIn:t->root by:delta];
      [news addObject:[NSString stringWithFormat:@"R%u said R%u was in R%u: %s", t->source, thing, container,
                                                 true_ ? "so it is" : "it isn't"]];
   }
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
         r->toldBy    = 0;
         if( _omniscient || contains( lookedIn, nlooked, seen[ i].entity))
            r->insideSeen = now;
         if( r->form == BGLocationIn)
            settle( store, r->id, r->container, YES, news);
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

   /* what it was told is inside something it looked into: so it is, or it isn't */
   for( j = 0; j < [store testimonyCount]; j++)
   {
      const BGTestimony   *t;
      const BGReferent    *holder;

      t      = [store testimonyAt:j];
      holder = [store referent:t->container];
      if( t->settled || ! holder || ! holder->truth || ! contains( lookedIn, nlooked, holder->truth))
         continue;
      r = [store mutableReferent:t->thing];
      settle( store, t->thing, t->container, r && r->present && r->form == BGLocationIn && r->container == t->container,
              news);
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
         const BGAncestry   *ancestry;

         o.other   = bound_to( ev->other, agent, [store selfReferent], seen, assigned, nseen);
         o.content = (char *) ev->detail;
         ancestry  = [self ancestryOf:ev->index];
         if( ev->actor == agent && ancestry && ancestry->fabricated && ! ancestry->relayed)
            o.unbelieved = YES;      /* it knows it didn't see that */
         if( o.actor != [store selfReferent])
            [news addObject:[NSString stringWithFormat:@"R%u says to R%u: %s", o.actor, o.other,
                                                       ev->detail ? ev->detail : ""]];
      }
      [store addObservation:o];
      if( ! strcmp( ev->kind, "said") && ev->detail && o.actor && o.actor != [store selfReferent])
         [self believe:ev->detail from:o.actor utterance:ev->index at:now store:store news:news];
   }
   free( seen);
   free( assigned);
   free( taken);
}


/* --- true ancestry (developer-only) ------------------------------------------------ */

- (const BGAncestry *) ancestryOf:(uint64_t) utterance
{
   NSUInteger   i;

   for( i = 0; i < _nancestry; i++)
      if( _ancestry[ i].utterance == utterance)
         return( &_ancestry[ i]);
   return( NULL);
}


- (const BGAncestry *) rootOf:(uint64_t) utterance
{
   const BGAncestry   *a;
   NSUInteger         guard;

   a = [self ancestryOf:utterance];
   for( guard = 0; a && a->relayed && guard < 64; guard++)
   {
      if( ! [self ancestryOf:a->parent])
         break;
      a = [self ancestryOf:a->parent];
   }
   return( a);
}


- (void) addAncestry:(BGAncestry) a
{
   if( _nancestry == _acapacity)
   {
      _acapacity = _acapacity ? _acapacity * 2 : 16;
      _ancestry  = realloc( _ancestry, sizeof( BGAncestry) * _acapacity);
   }
   _ancestry[ _nancestry++] = a;
}


/* Where a claim said came from, by what its speaker knew when it spoke:
 * something like `what` it believed inside a container of the kind on that
 * tile. Seen, the speaker is the root; told, it relays the testimony that
 * weighs most; believed nowhere, it made the claim up. */
- (void) trace:(const BGEvent *) ev
{
   const TriNode      *claim;
   const BGReferent   *r;
   const BGReferent   *c;
   const BGTestimony  *t;
   const BGAncestry   *parent;
   BGKnowledgeStore   *store;
   BGAncestry         a;
   TriContent         *tri;
   TriArena           *arena;
   const char         *kind;
   const char         *ckind;
   int64_t            x;
   int64_t            y;
   int64_t            level;
   NSUInteger         i;

   tri   = [_world tri];
   arena = tri_arena_new();
   claim = tri_value( tri, ev->detail, arena, NULL, 0);
   if( ! claim || ! tri_subtype( tri, tri_node_type( claim), tri_type_named( tri, "#IsIn")) ||
       ! node_int( tri, claim, "within.place.x", &x) || ! node_int( tri, claim, "within.place.y", &y) ||
       ! node_int( tri, claim, "within.place.level", &level))
   {
      tri_arena_free( arena);
      return;
   }
   kind  = tri_type_name( tri, tri_node_type( tri_at( tri, claim, "what")));
   ckind = tri_type_name( tri, tri_node_type( tri_at( tri, claim, "within")));
   tri_arena_free( arena);

   memset( &a, 0, sizeof( a));
   a.utterance  = ev->index;
   a.speaker    = ev->actor;
   a.origin     = ev->actor;
   a.fabricated = YES;
   store        = [self storeOf:ev->actor];
   for( i = 0; i < [store count]; i++)
   {
      r = [store referentAt:i];
      c = r->form == BGLocationIn ? [store referent:r->container] : NULL;
      if( ! r->present || ! r->kind || strcmp( r->kind, kind) || ! c || ! c->kind || strcmp( c->kind, ckind) ||
          c->form != BGLocationOnTile || c->x != x || c->y != y || c->level != level)
         continue;
      a.fabricated = NO;
      if( r->toldBy && (t = [store strongestThat:r->id isIn:c->id]))
      {
         a.relayed = YES;
         a.parent  = t->utterance;
         if( (parent = [self ancestryOf:t->utterance]))
         {
            a.origin     = parent->origin;
            a.fabricated = parent->fabricated;
         }
      }
      break;
   }
   [self addAncestry:a];
}


- (void) perceiveBoundary:(uint64_t) boundary
{
   const BGEvent   *ev;
   BGStore         *agents;
   NSUInteger      i;
   NSUInteger      last;

   last   = [_world eventCount];
   /* claims said, traced first, by what their speakers knew when they spoke */
   for( i = _eventsSeen; i < last; i++)
   {
      ev = [_world eventAt:i];
      if( ! strcmp( ev->kind, "said") && ev->actor && ev->detail)
         [self trace:ev];
   }
   agents = [_world storeForKind:[_world kindNamed:"Agent"]];
   /* in stable ID order; each depends only on the world and its own store */
   for( i = 0; i < [agents count]; i++)
      [self perceive:[self storeOf:[agents entityAtIndex:i]]
                from:_eventsSeen
                  to:last];
   _eventsSeen = last;
}


/* --- the developer's view ---------------------------------------------------------- */

static NSString   *attribution_text( const BGTestimony *t)
{
   switch( t->attribution)
   {
   case BGHeardFrom : return( [NSString stringWithFormat:@"heard from R%u", t->root]);
   case BGHeard     : return( @"heard");
   default          : return( @"saw");
   }
}


/* What it was told, claim by claim: credence, each item's group and weight,
 * and, for the developer, where each truly came from; groups the agent
 * counts apart that share a true root are false corroboration. */
- (NSString *) dumpTestimony:(BGKnowledgeStore *) store
{
   const BGTestimony   *t;
   const BGTestimony   *u;
   const BGAncestry    *a;
   const BGAncestry    *b;
   NSMutableString     *s;
   NSUInteger          i;
   NSUInteger          j;
   NSUInteger          k;

   s = [NSMutableString string];
   for( i = 0; i < [store testimonyCount]; i++)
   {
      t = [store testimonyAt:i];
      for( j = 0; j < i; j++)
         if( [store testimonyAt:j]->thing == t->thing && [store testimonyAt:j]->container == t->container)
            break;
      if( j < i)
         continue;      /* the claim is shown already */
      [s appendFormat:@"  claim R%u in R%u: credence %+d dB\n", t->thing, t->container,
                      [store credenceThat:t->thing isIn:t->container]];
      for( j = i; j < [store testimonyCount]; j++)
      {
         u = [store testimonyAt:j];
         if( u->thing != t->thing || u->container != t->container)
            continue;
         a = [self rootOf:u->utterance];
         [s appendFormat:@"    R%u said so at %lldms, as of %lldms: %@, %@, weight %+d dB%s; truly %@\n", u->source,
                         (long long) u->heard, (long long) u->when, attribution_text( u),
                         u->root ? [NSString stringWithFormat:@"root R%u", u->root] : @"root unknown",
                         [store weightOf:u], u->settled > 0 ? ", seen true" : u->settled < 0 ? ", found false" : "",
                         ! a ? @"untraced"
                             : [NSString stringWithFormat:@"%s by %llu", a->fabricated ? "made up" : "seen",
                                                          (unsigned long long) a->origin]];
         /* false corroboration: a later item counted apart, from the same true root */
         for( k = j + 1; k < [store testimonyCount]; k++)
         {
            const BGTestimony   *v;

            v = [store testimonyAt:k];
            if( v->thing != t->thing || v->container != t->container || u->settled < 0 || v->settled < 0 ||
                (u->root && u->root == v->root))
               continue;
            b = [self rootOf:v->utterance];
            if( a && b && a->origin == b->origin && a->fabricated == b->fabricated)
               [s appendFormat:@"    false corroboration: R%u and R%u are counted apart, and both come from %llu\n",
                               u->source, v->source, (unsigned long long) a->origin];
         }
      }
   }
   return( s);
}


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
      [s appendFormat:@"  R%u %s, seen at %lldms%s, truth %llu%@%@%@: %@\n", r->id, r->kind, (long long) r->seen,
                      r->present ? "" : ", not there any more", (unsigned long long) r->truth,
                      r->insideSeen >= 0 ? [NSString stringWithFormat:@", inside seen at %lldms", (long long) r->insideSeen]
                                         : @"",
                      r->toldBy ? [NSString stringWithFormat:@", told by R%u", r->toldBy] : @"",
                      r->kind && ! strcmp( r->kind, "#Agent") && r->id != [store selfReferent]
                         ? [NSString stringWithFormat:@", trust %+d dB", r->trust] : @"",
                      [store describeReferent:r->id]];
   }
   [s appendString:[self dumpTestimony:store]];
   for( i = 0; i < [store observationCount]; i++)
   {
      o = [store observationAt:i];
      [s appendFormat:@"  at %lldms: R%u %s R%u%@%@%s\n", (long long) o->time, o->actor, o->kind,
                      ! strcmp( o->kind, "said") ? o->other : o->subject,
                      ! strcmp( o->kind, "moved") && o->other ? [NSString stringWithFormat:@" to R%u", o->other] : @"",
                      o->content ? [NSString stringWithFormat:@": %s", o->content] : @"",
                      o->unbelieved ? " (not believed)" : ""];
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
   const BGTestimony     *t;
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
         [lines addObject:[NSString stringWithFormat:@"ref %llu %u %d %u %d %d %d %d %lld %lld %u %d %d %llu %@ %@ %@",
                                                     (unsigned long long) [store agent], r->id, (int) r->form,
                                                     r->container, r->x, r->y, r->level, r->slot, (long long) r->seen,
                                                     (long long) r->insideSeen, r->toldBy, r->trust, r->present ? 1 : 0,
                                                     (unsigned long long) r->truth,
                                                     encode( r->role), encode( r->kind), encode( r->features)]];
      }
      for( j = 0; j < [store observationCount]; j++)
      {
         o = [store observationAt:j];
         [lines addObject:[NSString stringWithFormat:@"obs %llu %lld %s %u %u %u %d %@", (unsigned long long) [store agent],
                                                     (long long) o->time, o->kind, o->actor, o->subject, o->other,
                                                     o->unbelieved ? 1 : 0, encode( o->content)]];
      }
      for( j = 0; j < [store testimonyCount]; j++)
      {
         t = [store testimonyAt:j];
         [lines addObject:[NSString stringWithFormat:@"told %llu %u %u %lld %lld %u %u %d %d %llu",
                                                     (unsigned long long) [store agent], t->thing, t->container,
                                                     (long long) t->when, (long long) t->heard, t->source, t->root,
                                                     (int) t->attribution, t->settled, (unsigned long long) t->utterance]];
      }
   }
   for( j = 0; j < _nancestry; j++)
      [lines addObject:[NSString stringWithFormat:@"ancestry %llu %llu %llu %llu %d %d",
                                                  (unsigned long long) _ancestry[ j].utterance,
                                                  (unsigned long long) _ancestry[ j].speaker,
                                                  (unsigned long long) _ancestry[ j].origin,
                                                  (unsigned long long) _ancestry[ j].parent,
                                                  _ancestry[ j].relayed ? 1 : 0, _ancestry[ j].fabricated ? 1 : 0]];
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
   unsigned long long   origin;
   unsigned long long   parent;
   int                  trust;
   BGTestimony          t;
   BGAncestry           a;
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
   _nancestry = 0;
   for( i = 0; i < [lines count]; i++)
   {
      text = (char *) [[lines objectAtIndex:i] UTF8String];
      if( sscanf( text, "store %llu %u %u", &agent, &next, &me) == 3)
         [[self storeOf:(BGEntityID) agent] setNextID:next self:me];
      else if( sscanf( text, "seen %llu %d %d %lld", &agent, &x, &y, &seen) == 4)
         [[self storeOf:(BGEntityID) agent] setTileSeen:seen x:x y:y];
      else if( sscanf( text, "obs %llu %lld %15s %u %u %u %d %4095s", &agent, &seen, role, &id, &container, &told,
                       &present, features) == 8)
      {
         memset( &o, 0, sizeof( o));
         o.time       = seen;
         o.kind       = [_world intern:role];
         o.actor      = id;
         o.subject    = container;
         o.other      = told;
         o.unbelieved = present != 0;
         o.content    = decode( features);
         if( ! *o.content)
         {
            free( o.content);
            o.content = NULL;
         }
         [[self storeOf:(BGEntityID) agent] addObservation:o];
         free( o.content);
      }
      else if( sscanf( text, "told %llu %u %u %lld %lld %u %u %d %d %llu", &agent, &id, &container, &seen, &inside,
                       &told, &me, &form, &present, &truth) == 10)
      {
         memset( &t, 0, sizeof( t));
         t.thing       = id;
         t.container   = container;
         t.when        = seen;
         t.heard       = inside;
         t.source      = told;
         t.root        = me;
         t.attribution = (BGAttribution) form;
         t.settled     = present;
         t.utterance   = truth;
         [[self storeOf:(BGEntityID) agent] appendTestimony:t];
      }
      else if( sscanf( text, "ancestry %llu %llu %llu %llu %d %d", &truth, &agent, &origin, &parent, &form,
                       &present) == 6)
      {
         memset( &a, 0, sizeof( a));
         a.utterance  = truth;
         a.speaker    = (BGEntityID) agent;
         a.origin     = (BGEntityID) origin;
         a.parent     = parent;
         a.relayed    = form != 0;
         a.fabricated = present != 0;
         [self addAncestry:a];
      }
      else if( sscanf( text, "ref %llu %u %d %u %d %d %d %d %lld %lld %u %d %d %llu %63s %511s %4095s", &agent, &id,
                       &form, &container, &x, &y, &level, &slot, &seen, &inside, &told, &trust, &present, &truth, role,
                       kind, features) == 17)
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
         r->trust      = trust;
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

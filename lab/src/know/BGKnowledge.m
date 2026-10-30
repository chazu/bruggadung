#import "BGKnowledge.h"

#import "BGView.h"
#import "BGTraces.h"
#import "BGBodies.h"
#import "BGActions.h"

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


static char   *concrete_features( const char *printed);
static void   settle( BGKnowledgeStore *store, uint32_t thing, uint32_t container, BOOL true_, int64_t now,
                      NSMutableArray *news);


/* The top-level keys of a features text: "mass: 90g, unit: ..." */
static NSUInteger   feature_keys( const char *features, char (*keys)[ 32], NSUInteger max)
{
   const char   *p;
   const char   *field;
   const char   *colon;
   NSUInteger   n;
   int          depth;
   BOOL         quoted;

   n      = 0;
   depth  = 0;
   quoted = NO;
   for( field = p = features; n < max; p++)
   {
      if( *p == '"' && (p == features || p[ -1] != '\\'))
         quoted = ! quoted;
      if( quoted && *p)
         continue;
      if( *p == '{' || *p == '[' || *p == '(')
         depth++;
      else if( (*p == '}' || *p == ']' || *p == ')') && depth > 0)
         depth--;
      else if( (*p == ',' && ! depth) || ! *p)
      {
         while( *field == ' ')
            field++;
         colon = strstr( field, ": ");
         if( colon && colon < p && colon - field < 32)
         {
            snprintf( keys[ n], 32, "%.*s", (int) (colon - field), field);
            n++;
         }
         field = p + 1;
      }
      if( ! *p)
         break;
   }
   return( n);
}


/* --- a store ------------------------------------------------------------------- */

@implementation BGKnowledgeStore

- (id) initWithAgent:(BGEntityID) agent
               world:(BGWorld *) world
{
   int   i;

   if( ! (self = [super init]))
      return( nil);
   _world  = world;
   _agent  = agent;
   _feltAt = -1;
   _next  = 1;
   _news  = [NSMutableArray new];
   for( i = 0; i < 32 * 32; i++)
      _seenAt[ i] = -1;
   return( self);
}


- (void) dealloc
{
   NSUInteger   i;
   NSUInteger   j;

   for( i = 0; i < _count; i++)
   {
      free( _referents[ i].kind);
      free( _referents[ i].features);
      free( _referents[ i].deeper);
      for( j = 0; j < BG_HYPOTHESES; j++)
         free( _referents[ i].supposed[ j]);
   }
   free( _referents);
   for( i = 0; i < _nobservations; i++)
      free( _observations[ i].content);
   free( _observations);
   free( _testimony);
   free( _traces);
   free( _findings);
   free( _identities);
   if( _arena)
      tri_arena_free( _arena);
   [_parsed release];
   [_used release];
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


- (uint64_t) nextSerial
{
   return( _serial);
}


/* `o`'s content is copied; it gets the next serial, unless restoring one */
- (void) addObservation:(BGObservation) o
               restored:(BOOL) restored
{
   if( _nobservations == _ocapacity)
   {
      _ocapacity    = _ocapacity ? _ocapacity * 2 : 16;
      _observations = realloc( _observations, sizeof( BGObservation) * _ocapacity);
   }
   if( ! restored)
      o.serial = _serial;
   if( o.serial >= _serial)
      _serial = o.serial + 1;
   o.content                         = o.content ? strdup( o.content) : NULL;
   _observations[ _nobservations++] = o;
}


/* Over capacity, the least salient go, the oldest of them first. */
- (void) keepAtMost:(NSUInteger) capacity
{
   NSUInteger   i;
   NSUInteger   least;

   while( _nobservations > capacity && _nobservations)
   {
      least = 0;
      for( i = 1; i < _nobservations; i++)
         if( _observations[ i].salience < _observations[ least].salience)
            least = i;
      free( _observations[ least].content);
      memmove( &_observations[ least], &_observations[ least + 1],
               sizeof( BGObservation) * (_nobservations - least - 1));
      _nobservations--;
   }
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


- (NSUInteger) traceCount
{
   return( _ntraces);
}


- (const BGTraceSeen *) traceAt:(NSUInteger) i
{
   return( &_traces[ i]);
}


- (BGTraceSeen *) mutableTraceAt:(NSUInteger) i
{
   return( &_traces[ i]);
}


/* The trace of that kind at that site, updated, or added; YES if added. */
- (BOOL) noteTrace:(BGTraceSeen) t
{
   NSUInteger   i;

   for( i = 0; i < _ntraces; i++)
      if( _traces[ i].kind == t.kind && _traces[ i].bearer == t.bearer &&
          (t.bearer || (_traces[ i].x == t.x && _traces[ i].y == t.y && _traces[ i].level == t.level)))
      {
         _traces[ i] = t;
         return( NO);
      }
   if( _ntraces == _trcapacity)
   {
      _trcapacity = _trcapacity ? _trcapacity * 2 : 16;
      _traces     = realloc( _traces, sizeof( BGTraceSeen) * _trcapacity);
   }
   _traces[ _ntraces++] = t;
   return( YES);
}


- (int32_t) feels:(const char *) need
{
   return( ! strcmp( need, "hunger") ? _hunger : ! strcmp( need, "cold") ? _cold : ! strcmp( need, "stuffy") ? _stuffy :
           ! strcmp( need, "tired") ? _tired : ! strcmp( need, "pain") ? _pain : 0);
}


- (int64_t) feltAt
{
   return( _feltAt);
}


/* YES if it feels differently now */
- (BOOL) feelHunger:(int32_t) hunger
                 at:(int64_t) t
{
   BOOL   changed;

   changed = _feltAt < 0 || hunger != _hunger;
   _hunger = hunger;
   _feltAt = t;
   return( changed);
}


- (BOOL) feelCold:(int32_t) cold
{
   BOOL   changed;

   changed = cold != _cold;
   _cold   = cold;
   return( changed);
}


- (BOOL) feelPain:(int32_t) pain
{
   BOOL   changed;

   changed = pain != _pain;
   _pain   = pain;
   return( changed);
}


- (BOOL) feelTired:(int32_t) tired
{
   BOOL   changed;

   changed = tired != _tired;
   _tired  = tired;
   return( changed);
}


- (BOOL) feelStuffy:(int32_t) stuffy
{
   BOOL   changed;

   changed = stuffy != _stuffy;
   _stuffy = stuffy;
   return( changed);
}


- (NSUInteger) identityCount
{
   return( _nidentities);
}


- (const BGIdentity *) identityAt:(NSUInteger) i
{
   return( &_identities[ i]);
}


- (BGIdentity *) mutableIdentityAt:(NSUInteger) i
{
   return( &_identities[ i]);
}


- (void) addIdentity:(BGIdentity) h
{
   if( _nidentities == _icapacity)
   {
      _icapacity  = _icapacity ? _icapacity * 2 : 8;
      _identities = realloc( _identities, sizeof( BGIdentity) * _icapacity);
   }
   _identities[ _nidentities++] = h;
}


- (NSUInteger) findingCount
{
   return( _nfindings);
}


- (const BGFinding *) findingAt:(NSUInteger) i
{
   return( &_findings[ i]);
}


- (const BGFinding *) finding:(const char *) kind
                        about:(uint32_t) referentID
{
   NSUInteger   i;

   for( i = 0; i < _nfindings; i++)
      if( _findings[ i].about == referentID && ! strcmp( _findings[ i].kind, kind))
         return( &_findings[ i]);
   return( NULL);
}


- (void) addFinding:(BGFinding) f
{
   if( _nfindings == _fcapacity)
   {
      _fcapacity = _fcapacity ? _fcapacity * 2 : 16;
      _findings  = realloc( _findings, sizeof( BGFinding) * _fcapacity);
   }
   _findings[ _nfindings++] = f;
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
   case BGPledged :
      return( source);
   default :
      return( t->sure < source ? t->sure : source);
   }
}


/* What counts toward credence now: open or seen true, and not a promise. */
static BOOL   counts( const BGTestimony *t, uint32_t thing, uint32_t container)
{
   return( t->thing == thing && t->container == container && t->settled >= 0 && t->attribution != BGPledged);
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
   NSString           *features;

   NSMutableArray     *kept;
   NSArray            *pairs;
   NSUInteger         i;

   r = [self referent:referentID];
   if( ! r || ! r->kind)
      return( nil);
   /* how it looks, not what it is doing: free hands come and go */
   features = [self recall:r];
   pairs    = [features length] ? BGSplitTopLevel( features) : [NSArray array];
   kept     = [NSMutableArray array];
   for( i = 0; i < [pairs count]; i++)
      if( ! [[pairs objectAtIndex:i] hasPrefix:@"freeHands:"])
         [kept addObject:[pairs objectAtIndex:i]];
   if( ! [kept count])
      return( [NSString stringWithUTF8String:r->kind]);
   return( [NSString stringWithFormat:@"%s & { %@ }", r->kind, [kept componentsJoinedByString:@", "]]);
}


/* --- what it can say ------------------------------------------------------------- */

- (NSString *) describeHere:(const BGReferent *) c
{
   NSString   *features;

   features = [self recall:c];
   return( [NSString stringWithFormat:@"%s & { place: #OnTile & { x: %d, y: %d, level: %d }%@ }", c->kind, c->x, c->y,
                                      c->level, [features length] ? [NSString stringWithFormat:@", %@", features] : @""]);
}


- (NSString *) claimThat:(const BGReferent *) r
                    isIn:(const BGReferent *) c
             attribution:(NSString *) attribution
                    when:(int64_t) when
{
   return( [NSString stringWithFormat:@"#IsIn & { what: %@, within: %@, when: %lldms, attribution: %@ }",
                                      [self describeLooks:r->id], [self describeHere:c], (long long) when, attribution]);
}


/* how it knows the thing is where it believes: saw it, as sure as its memory
 * is strong, or heard it, from whoever its strongest testimony names */
- (NSString *) attributionOf:(const BGReferent *) r
{
   const BGTestimony   *t;
   NSString            *from;

   if( ! r->toldBy)
      return( [NSString stringWithFormat:@"#Saw & { sure: %d }", [self strengthOf:r->id]]);
   t    = [self strongestThat:r->id isIn:r->container];
   from = t && t->root ? [self describeLooks:t->root] : nil;
   return( from ? [NSString stringWithFormat:@"#Heard & { from: %@ }", from] : @"#Heard");
}


- (NSString *) claimAbout:(uint32_t) thing
{
   const BGReferent   *r;
   const BGReferent   *c;

   r = [self referent:thing];
   c = r && r->present && r->form == BGLocationHeldBy ? [self referent:r->container] : NULL;
   if( c && c->kind && ! strcmp( c->kind, "#Agent") && r->kind)
      return( [NSString stringWithFormat:@"#IsHeld & { what: %@, holder: %@, when: %lldms, attribution: %@ }",
                                         [self describeLooks:r->id], [self describeLooks:c->id], (long long) r->seen,
                                         [self attributionOf:r]]);
   c = r && r->present && r->form == BGLocationIn ? [self referent:r->container] : NULL;
   if( ! c || c->form != BGLocationOnTile || ! r->kind || ! c->kind)
      return( nil);
   return( [self claimThat:r isIn:c attribution:[self attributionOf:r] when:r->seen]);
}


- (NSString *) claimThat:(uint32_t) thing
                    isIn:(uint32_t) container
{
   const BGReferent   *r;
   const BGReferent   *c;

   r = [self referent:thing];
   c = [self referent:container];
   if( ! r || ! c || ! r->kind || ! c->kind || c->form != BGLocationOnTile)
      return( nil);
   if( r->present && r->form == BGLocationIn && r->container == container)
      return( [self claimAbout:thing]);
   return( [self claimThat:r isIn:c attribution:[NSString stringWithFormat:@"#Saw & { sure: %d }", BG_SEEN]
                      when:_world ? [_world time].ms : 0]);
}


- (NSString *) writingAbout:(uint32_t) thing
{
   NSString   *claim;

   claim = [self claimAbout:thing];
   if( ! claim || ! [self describeLooks:_self])
      return( nil);
   return( [NSString stringWithFormat:@"#Writing & { author: %@, entries: [%@] }", [self describeLooks:_self], claim]);
}


- (NSString *) reservationOf:(uint32_t) thing
                         for:(uint32_t) holder
{
   if( ! [self describeLooks:thing] || ! [self describeLooks:holder])
      return( nil);
   return( [NSString stringWithFormat:@"#ReservedFor & { what: %@, holder: %@, when: %lldms, attribution: #Saw & { sure: %d } }",
                                      [self describeLooks:thing], [self describeLooks:holder],
                                      (long long) (_world ? [_world time].ms : 0), BG_SEEN]);
}


- (NSString *) promiseThat:(uint32_t) thing
                      isIn:(uint32_t) container
                        by:(int64_t) deadline
{
   const BGReferent   *r;
   const BGReferent   *c;

   r = [self referent:thing];
   c = [self referent:container];
   if( ! r || ! c || ! r->kind || ! c->kind || c->form != BGLocationOnTile)
      return( nil);
   return( [self claimThat:r isIn:c attribution:@"#Pledged" when:deadline]);
}


- (NSString *) askWhereIs:(uint32_t) thing
{
   NSString   *looks;

   looks = [self describeLooks:thing];
   return( looks ? [NSString stringWithFormat:@"#WhereIs & { what: %@ }", looks] : nil);
}


- (NSString *) askWhoToldOf:(uint32_t) thing
{
   const BGReferent   *r;
   const BGReferent   *c;

   r = [self referent:thing];
   c = r && r->present && r->form == BGLocationIn ? [self referent:r->container] : NULL;
   if( ! c || c->form != BGLocationOnTile || ! c->kind)
      return( nil);
   return( [NSString stringWithFormat:@"#WhoToldYou & { what: %@, within: %@ }", [self describeLooks:thing],
                                      [self describeHere:c]]);
}


- (int) stepsSince:(int64_t) t
{
   int64_t   now;
   int64_t   steps;

   now = _world ? [_world time].ms : t;
   if( now <= t)
      return( 0);
   steps = (now - t) / BG_MEMORY_STEP;
   return( steps > 1000 ? 1000 : (int) steps);
}


/* The referent's features, with what an analysis found beneath them in
 * place of what they looked like. */
static NSString   *known_features( const BGReferent *r)
{
   NSMutableString   *out;
   NSString          *value;
   const char        *p;
   char              keys[ 32][ 32];
   char              deep[ 32][ 32];
   NSUInteger        n;
   NSUInteger        m;
   NSUInteger        k;
   NSUInteger        j;
   int               depth;
   BOOL              quoted;
   BOOL              overridden;

   if( ! r->deeper || ! *r->deeper)
      return( [NSString stringWithUTF8String:r->features ? r->features : ""]);
   n   = r->features ? feature_keys( r->features, keys, 32) : 0;
   m   = feature_keys( r->deeper, deep, 32);
   out = [NSMutableString string];
   for( p = r->features, k = 0; p && *p && k < n; k++)
   {
      /* the pair at p, up to the next top-level comma */
      const char   *start;

      while( *p == ' ' || *p == ',')
         p++;
      start  = p;
      depth  = 0;
      quoted = NO;
      for( ; *p; p++)
      {
         if( *p == '"' && (p == start || p[ -1] != '\\'))
            quoted = ! quoted;
         if( quoted)
            continue;
         if( *p == '{' || *p == '[' || *p == '(')
            depth++;
         else if( (*p == '}' || *p == ']' || *p == ')') && depth > 0)
            depth--;
         else if( *p == ',' && ! depth)
            break;
      }
      for( overridden = NO, j = 0; j < m && ! overridden; j++)
         overridden = ! strcmp( keys[ k], deep[ j]);
      if( overridden)
         continue;
      value = [[[NSString alloc] initWithBytes:(void *) start length:(NSUInteger) (p - start)
                                      encoding:NSUTF8StringEncoding] autorelease];
      [out appendFormat:@"%@%@", [out length] ? @", " : @"", value];
   }
   [out appendFormat:@"%@%s", [out length] ? @", " : @"", r->deeper];
   return( out);
}


/* Each feature generalized a step along its primary parent for each memory
 * step since the referent was seen; one generalized as far as it goes is
 * forgotten. */
- (NSString *) recall:(const BGReferent *) r
{
   NSString   *known;
   int        steps;

   if( ! r->features)
      return( @"");
   known = known_features( r);
   steps = [self stepsSince:r->seen];
   if( ! steps || ! [known length] || ! r->kind)
      return( known);
   return( [self generalize:known kind:r->kind steps:steps]);
}


- (NSString *) generalize:(NSString *) known
                     kind:(const char *) kind
                    steps:(int) steps
{
   const TriNode     *node;
   const TriNode     *part;
   const TriNode     *full;
   NSMutableString   *out;
   TriContent        *tri;
   TriArena          *arena;
   NSUInteger        nkeys;
   NSUInteger        k;
   char              keys[ 32][ 32];
   char              a[ 512];
   char              b[ 512];

   tri   = [_world tri];
   arena = tri_arena_new();
   node  = tri_value( tri, [[NSString stringWithFormat:@"%s & { %@ }", kind, known] UTF8String], arena, NULL, 0);
   if( ! node)
   {
      tri_arena_free( arena);
      return( known);
   }
   out   = [NSMutableString string];
   nkeys = feature_keys( [known UTF8String], keys, 32);
   for( k = 0; k < nkeys; k++)
   {
      part = tri_generalize( tri, node, keys[ k], steps, arena);
      full = tri_generalize( tri, node, keys[ k], 1000, arena);
      if( ! part || ! full || ! tri_at( tri, part, keys[ k]) || ! tri_at( tri, full, keys[ k]))
         continue;
      tri_print( tri, tri_at( tri, part, keys[ k]), a, sizeof( a));
      tri_print( tri, tri_at( tri, full, keys[ k]), b, sizeof( b));
      if( ! strcmp( a, b))
         continue;      /* forgotten */
      [out appendFormat:@"%s%s: %s", [out length] ? ", " : "", keys[ k], a];
   }
   tri_arena_free( arena);
   return( out);
}


- (int32_t) strengthOf:(uint32_t) referentID
{
   const BGReferent   *r;
   int32_t            base;

   r = [self referent:referentID];
   if( ! r)
      return( BG_PRIOR);
   base = BG_SEEN;
   if( r->toldBy && r->form == BGLocationIn)
      base = [self credenceThat:r->id isIn:r->container];
   return( base - BG_FADE * [self stepsSince:r->seen]);
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


- (void) setNextSerial:(uint64_t) serial
{
   _serial = serial;
}


- (void) setSelf:(uint32_t) selfReferent
{
   _self = selfReferent;
}


- (const TriNode *) parsed:(NSString *) text
{
   const TriNode   *node;
   NSValue         *v;

   if( ! _arena)
   {
      _arena  = tri_arena_new();
      _parsed = [NSMutableDictionary new];
      _used   = [NSMutableSet new];
   }
   [_used addObject:text];
   if( (v = [_parsed objectForKey:text]))
      return( [v pointerValue]);
   node = tri_value( [_world tri], [text UTF8String], _arena, NULL, 0);
   if( node)
      [_parsed setObject:[NSValue valueWithPointer:node] forKey:text];
   return( node);
}


- (BOOL) compact:(BOOL) always
{
   NSMutableDictionary   *parsed;
   NSEnumerator          *e;
   NSString              *text;
   TriArena              *arena;
   const TriNode         *node;

   if( ! _arena || (! always && tri_arena_bytes( _arena) <= 2 * (_liveBytes > 4096 ? _liveBytes : 4096)))
      return( NO);
   arena  = tri_arena_new();
   parsed = [NSMutableDictionary new];
   e      = [[[_used allObjects] sortedArrayUsingSelector:@selector( compare:)] objectEnumerator];
   while( (text = [e nextObject]))
      if( (node = [[_parsed objectForKey:text] pointerValue]))
         [parsed setObject:[NSValue valueWithPointer:tri_copy( [_world tri], node, arena)] forKey:text];
   tri_arena_free( _arena);
   [_parsed release];
   _arena     = arena;
   _parsed    = parsed;
   _liveBytes = tri_arena_bytes( arena);
   [_used removeAllObjects];
   _compactions++;
   return( YES);
}


- (NSUInteger) compactions
{
   return( _compactions);
}


- (void) suppose:(NSString *) overrides
           about:(uint32_t) referentID
            mass:(int32_t) permille
{
   BGReferent   *r;
   NSUInteger   h;

   if( ! overrides || ! (r = [self mutableReferent:referentID]))
      return;
   for( h = 0; h < BG_HYPOTHESES && r->supposed[ h] && strcmp( r->supposed[ h], [overrides UTF8String]); h++)
      ;
   if( h == BG_HYPOTHESES)
      return;
   if( ! r->supposed[ h])
      r->supposed[ h] = strdup( [overrides UTF8String]);
   r->supposedMass[ h] = permille;
}


- (void) dropSupposed:(uint32_t) referentID
{
   BGReferent   *r;
   NSUInteger   h;

   if( ! (r = [self mutableReferent:referentID]))
      return;
   for( h = 0; h < BG_HYPOTHESES; h++)
   {
      free( r->supposed[ h]);
      r->supposed[ h]     = NULL;
      r->supposedMass[ h] = 0;
   }
}


- (NSUInteger) hypothesesOf:(uint32_t) referentID
{
   const BGReferent   *r;
   NSUInteger         h;

   r = [self referent:referentID];
   for( h = 0; r && h < BG_HYPOTHESES && r->supposed[ h]; h++)
      ;
   return( r ? h : 0);
}


- (const char *) overridesOf:(uint32_t) referentID
                  hypothesis:(NSUInteger) h
{
   return( h < [self hypothesesOf:referentID] ? [self referent:referentID]->supposed[ h] : NULL);
}


- (int32_t) massOf:(uint32_t) referentID
        hypothesis:(NSUInteger) h
{
   return( h < [self hypothesesOf:referentID] ? [self referent:referentID]->supposedMass[ h] : 0);
}


- (int32_t) supposedMassOf:(uint32_t) referentID
{
   NSUInteger   h;
   int32_t      sum;

   for( sum = 0, h = 0; h < [self hypothesesOf:referentID]; h++)
      sum += [self massOf:referentID hypothesis:h];
   return( sum);
}


/* Described as the hypothesis has it: its overrides laid over what it
 * believes, as an analysis's findings are over looks. */
- (NSString *) describeSupposed:(uint32_t) referentID
                     hypothesis:(NSUInteger) h
{
   BGReferent   *r;
   NSString     *s;
   char         *features;
   char         *deeper;

   r = [self mutableReferent:referentID];
   if( ! r || h >= [self hypothesesOf:referentID])
      return( nil);
   features    = r->features;
   deeper      = r->deeper;
   r->features = strdup( [known_features( r) UTF8String]);
   r->deeper   = r->supposed[ h];
   s           = [self describeReferent:referentID];
   free( r->features);
   r->features = features;
   r->deeper   = deeper;
   return( s);
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
   if( [[self recall:r] length])
      [s appendFormat:@", %@", [self recall:r]];
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
   _ambient    = 2;
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


- (void) setCompactAlways:(BOOL) flag
{
   _compactAlways = flag;
}


- (void) setDusk:(BOOL) flag
{
   _ambient = flag ? 1 : 2;
}


- (void) setAmbient:(int) light
{
   _ambient = light < 0 ? 0 : light > 2 ? 2 : light;
}


- (int) lightAt:(BGLocation) tile
{
   const BGLamp   *lamp;
   BGStore        *lamps;
   BGLocation     at;
   NSUInteger     i;

   if( _ambient >= 2)
      return( _ambient);
   lamps = [_world storeForKind:[_world kindNamed:"Lamp"]];
   for( i = 0; i < [lamps count]; i++)
   {
      lamp = [lamps recordAtIndex:i];
      if( lamp->shining && ground_tile( _world, [lamps entityAtIndex:i], &at) && at.level == tile.level &&
          abs( at.x - tile.x) <= lamp->reach && abs( at.y - tile.y) <= lamp->reach)
         return( 2);
   }
   return( _ambient);
}


/* Whether the agent here can see the tile: in sight, and lit, or within
 * arm's reach. */
- (BOOL) sees:(BGLocation) tile
         from:(BGLocation) here
{
   if( _omniscient)
      return( YES);
   if( tile.level != here.level || abs( tile.x - here.x) > BG_SIGHT || abs( tile.y - here.y) > BG_SIGHT)
      return( NO);
   if( abs( tile.x - here.x) <= 1 && abs( tile.y - here.y) <= 1)
      return( YES);
   return( [self lightAt:tile] > 0);
}


/* How long a feature usually lasts (content/persistence.tri): long, unless
 * said. */
- (int64_t) persistenceOf:(const char *) feature
{
   TriContent   *tri;
   TriIndex     *family;
   size_t       i;
   int64_t      lo;
   int64_t      hi;
   char         name[ 64];

   tri    = [_world tri];
   family = tri_family_index( tri, "persistence");
   for( i = 0; family && i < tri_index_count( family); i++)
   {
      const TriNode   *p;

      p = tri_pattern( tri, tri_index_tag( family, i));
      if( tri_at( tri, p, "feature") && tri_print( tri, tri_at( tri, p, "feature"), name, sizeof( name)) > 2)
      {
         name[ strlen( name) - 1] = 0;
         if( ! strcmp( name + 1, feature) && tri_node_interval( tri_at( tri, p, "persists"), &lo, &hi))
            return( lo);
      }
   }
   return( 10000LL * 86400000LL);
}


/* Where what memory keeps of the referent and the percept conflict, every
 * path, into `paths` ("coat, bent"); how many, and how many agree. */
- (int) conflictsOf:(const BGReferent *) r
                 in:(BGKnowledgeStore *) store
               kind:(NSString *) kind
           features:(NSString *) features
              paths:(char *) paths
             length:(size_t) length
              agree:(int *) agree
{
   const TriNode   *x;
   const TriNode   *y;
   char            found[ 8][ 256];
   size_t          n;
   size_t          i;

   /* both from the store's knowledge arena */
   x      = [store parsed:[NSString stringWithFormat:@"%@ & { %@ }", kind, lasting( [store recall:r])]];
   y      = [store parsed:[NSString stringWithFormat:@"%@ & { %@ }", kind, lasting( features)]];
   n      = x && y ? tri_conflicts( [_world tri], x, y, found, 8) : 0;
   paths[ 0] = 0;
   for( i = 0; i < n; i++)
      snprintf( paths + strlen( paths), length - strlen( paths), "%s%s", i ? ", " : "", found[ i]);
   *agree = (int) [BGSplitTopLevel( lasting( features)) count] - (int) n;
   return( (int) n);
}


/* Whether memory holds anything concrete of the referent to know it by: a
 * feature with one value. One told of only as "someone" has nothing, and a
 * percept matching it is a weak match (KNOWLEDGE.md §6), not a binding. */
- (BOOL) knowsAnythingOf:(const BGReferent *) r
                      in:(BGKnowledgeStore *) store
{
   NSArray      *pairs;
   NSString     *pair;
   NSUInteger   k;

   pairs = BGSplitTopLevel( [store recall:r]);
   for( k = 0; k < [pairs count]; k++)
   {
      pair = [pairs objectAtIndex:k];
      if( [pair rangeOfString:@"|"].location == NSNotFound && [pair rangeOfString:@">="].location == NSNotFound &&
          [pair rangeOfString:@"<="].location == NSNotFound && [pair rangeOfString:@": #"].location == NSNotFound &&
          ! [pair hasPrefix:@"id:"] && ! [pair hasPrefix:@"place:"])
         return( YES);
   }
   return( NO);
}


/* Whether every conflict is on a feature that changes within a week. */
- (BOOL) shortLived:(const char *) paths
{
   NSArray      *each;
   NSUInteger   i;

   each = BGSplitTopLevel( [NSString stringWithUTF8String:(char *) paths]);
   for( i = 0; i < [each count]; i++)
      if( [self persistenceOf:[[each objectAtIndex:i] UTF8String]] > 7 * 86400000LL)
         return( NO);
   return( [each count] > 0);
}


/* The percept's features, unified with what memory keeps, so a match keeps
 * the more specific; the percept's, if they don't unify. */
- (NSString *) unified:(const BGReferent *) r
                    in:(BGKnowledgeStore *) store
                  kind:(NSString *) kind
              features:(NSString *) features
{
   const TriNode     *both;
   TriArena          *arena;
   NSMutableString   *out;
   NSString          *remembered;
   char              keys[ 64][ 32];
   char              printed[ 512];
   NSUInteger        n;
   NSUInteger        k;
   NSUInteger        j;

   remembered = [store recall:r];
   arena      = tri_arena_new();
   both       = tri_value( [_world tri], [[NSString stringWithFormat:@"%@ & { %@ } & { %@ }", kind, remembered, features]
                                          UTF8String], arena, NULL, 0);
   if( ! both)
   {
      tri_arena_free( arena);
      return( features);
   }
   /* the features either had, as unified */
   n = feature_keys( [remembered UTF8String], keys, 32);
   n += feature_keys( [features UTF8String], keys + n, 32);
   out = [NSMutableString string];
   for( k = 0; k < n; k++)
   {
      for( j = 0; j < k && strcmp( keys[ j], keys[ k]); j++)
         ;
      if( j < k || ! tri_at( [_world tri], both, keys[ k]))
         continue;
      tri_print( [_world tri], tri_at( [_world tri], both, keys[ k]), printed, sizeof( printed));
      [out appendFormat:@"%@%s: %s", [out length] ? @", " : @"", keys[ k], printed];
   }
   tri_arena_free( arena);
   return( out);
}


/* The percept's features as seen from `distance` tiles: each feature with
 * an acuity (content/persistence.tri) blurred `blur` steps for each tile
 * beyond arm's reach. *blurred is set if any was. */
- (NSString *) blur:(NSString *) features
               kind:(const char *) kind
           distance:(int) distance
            blurred:(BOOL *) blurred
{
   const TriNode     *node;
   const TriNode     *p;
   const TriNode     *wide;
   TriContent        *tri;
   TriIndex          *family;
   TriArena          *arena;
   NSMutableString   *out;
   NSArray           *pairs;
   NSString          *pair;
   NSUInteger        k;
   size_t            i;
   int64_t           lo;
   int64_t           hi;
   char              name[ 64];
   char              printed[ 256];

   tri    = [_world tri];
   family = tri_family_index( tri, "acuity");
   if( distance <= 1 || ! family || ! tri_index_count( family))
      return( features);
   arena = tri_arena_new();
   node  = tri_value( tri, [[NSString stringWithFormat:@"%s & { %@ }", kind, features] UTF8String], arena, NULL, 0);
   pairs = BGSplitTopLevel( features);
   out   = [NSMutableString string];
   for( k = 0; k < [pairs count]; k++)
   {
      pair = [pairs objectAtIndex:k];
      for( i = 0; node && i < tri_index_count( family); i++)
      {
         p = tri_pattern( tri, tri_index_tag( family, i));
         if( ! tri_at( tri, p, "feature") || tri_print( tri, tri_at( tri, p, "feature"), name, sizeof( name)) < 3)
            continue;
         name[ strlen( name) - 1] = 0;
         if( ! [pair hasPrefix:[NSString stringWithFormat:@"%s: ", name + 1]] ||
             ! tri_node_interval( tri_at( tri, p, "blur"), &lo, &hi))
            continue;
         wide = tri_generalize( tri, node, name + 1, (int) lo * (distance - 1), arena);
         if( wide && tri_at( tri, wide, name + 1))
         {
            tri_print( tri, tri_at( tri, wide, name + 1), printed, sizeof( printed));
            pair     = [NSString stringWithFormat:@"%s: %s", name + 1, printed];
            *blurred = YES;
         }
      }
      [out appendFormat:@"%@%@", [out length] ? @", " : @"", pair];
   }
   tri_arena_free( arena);
   return( out);
}


- (void) setConcerns:(id <BGConcerns>) concerns
{
   _concerns = concerns;
}


- (id <BGConcerns>) concerns
{
   return( _concerns);
}


/* --- salience ------------------------------------------------------------------- */

/* What the agent's running activities demand of its attention. */
- (int) attentionOf:(BGEntityID) agent
{
   const BGActivity   *record;
   BGStore            *activities;
   TriContent         *tri;
   const TriNode      *v;
   NSUInteger         i;
   int64_t            lo;
   int64_t            hi;
   int                demand;

   tri        = [_world tri];
   activities = [_world storeForKind:[_world kindNamed:"Activity"]];
   demand     = 0;
   for( i = 0; i < [activities count]; i++)
   {
      record = [activities recordAtIndex:i];
      if( record->actorRef != agent || record->status != BG_ACTIVITYSTATUS_RUNNING || ! record->operation)
         continue;
      v = tri_at( tri, tri_pattern( tri, record->operation), "attention");
      if( v && tri_node_interval( v, &lo, &hi) && lo == hi && lo > demand)
         demand = (int) lo;
   }
   return( demand);
}


/* Whether the description is entailed by one of the patterns. */
- (BOOL) concerns:(NSArray *) patterns
      description:(NSString *) description
{
   const TriNode    *d;
   const TriNode    *p;
   TriMatchResult   result;
   TriContent       *tri;
   TriArena         *arena;
   NSUInteger       i;
   BOOL             yes;

   if( ! [patterns count] || ! description)
      return( NO);
   tri   = [_world tri];
   arena = tri_arena_new();
   d     = tri_value( tri, [description UTF8String], arena, NULL, 0);
   yes   = NO;
   for( i = 0; d && i < [patterns count] && ! yes; i++)
   {
      p   = tri_value( tri, [[patterns objectAtIndex:i] UTF8String], arena, NULL, 0);
      yes = p && tri_match( tri, p, d, &result) == TRI_ENTAILED;
   }
   tri_arena_free( arena);
   return( yes);
}


/* What something said is about: its `what`, printed. */
- (NSString *) topicOf:(const char *) content
{
   const TriNode   *said;
   TriArena        *arena;
   NSString        *topic;
   char            printed[ 2048];

   arena = tri_arena_new();
   said  = content ? tri_value( [_world tri], content, arena, NULL, 0) : NULL;
   topic = nil;
   if( said && tri_at( [_world tri], said, "what"))
   {
      tri_print( [_world tri], tri_at( [_world tri], said, "what"), printed, sizeof( printed));
      topic = [NSString stringWithUTF8String:printed];
   }
   tri_arena_free( arena);
   return( topic);
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
   store = [[[BGKnowledgeStore alloc] initWithAgent:agent world:_world] autorelease];
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


/* Told (a diagram, say) which line something serves: what it says, kept
 * with the referent beyond its looks, as an analysis's finding is; the
 * referent recognized by its kind on the tile the claim gives. */
- (void) serves:(const TriNode *) claim
           from:(uint32_t) speaker
          store:(BGKnowledgeStore *) store
           news:(NSMutableArray *) news
{
   const BGReferent   *r;
   BGReferent         *m;
   const char         *kind;
   NSUInteger         i;
   int64_t            x;
   int64_t            y;
   char               line[ 64];
   char               deeper[ 128];

   kind = tri_type_name( [_world tri], tri_node_type( tri_at( [_world tri], claim, "what")));
   if( ! node_int( [_world tri], claim, "what.place.x", &x) || ! node_int( [_world tri], claim, "what.place.y", &y) ||
       tri_print( [_world tri], tri_at( [_world tri], claim, "line"), line, sizeof( line)) < 3)
      return;
   for( i = 0; i < [store count]; i++)
   {
      r = [store referentAt:i];
      if( ! r->kind || strcmp( r->kind, kind) || r->form != BGLocationOnTile || r->x != x || r->y != y)
         continue;
      m = [store mutableReferent:r->id];
      snprintf( deeper, sizeof( deeper), "serves: %s", line);
      free( m->deeper);
      m->deeper = strdup( deeper);
      [news addObject:[NSString stringWithFormat:@"R%u serves %s, R%u says", r->id, line, speaker]];
      return;
   }
}


/* Told something is reserved for someone (ACTIONS.md §7): a #Reserved
 * finding about the thing, recognized among the referents of its kind that
 * look alike, its choice whom it is reserved for. */
- (void) reserved:(const TriNode *) claim
             from:(uint32_t) speaker
            store:(BGKnowledgeStore *) store
             news:(NSMutableArray *) news
{
   const TriNode      *what;
   const BGReferent   *r;
   BGFinding          f;
   NSString           *kind;
   NSUInteger         i;
   uint32_t           holder;
   uint32_t           thing;
   char               printed[ 2048];
   char               *features;

   holder = [self person:tri_at( [_world tri], claim, "holder") store:store news:news];
   what   = tri_at( [_world tri], claim, "what");
   if( ! holder || ! what)
      return;
   kind = [NSString stringWithUTF8String:(char *) tri_type_name( [_world tri], tri_node_type( what))];
   tri_print( [_world tri], what, printed, sizeof( printed));
   features = concrete_features( printed);
   thing    = 0;
   for( i = 0; i < [store count] && ! thing; i++)
   {
      r = [store referentAt:i];
      if( r->kind && ! strcmp( r->kind, [kind UTF8String]) && r->id != holder &&
          [self looksAlike:r in:store kind:kind features:[NSString stringWithUTF8String:features]])
         thing = r->id;
   }
   free( features);
   if( ! thing || [store finding:"#Reserved" about:thing])
      return;
   memset( &f, 0, sizeof( f));
   f.kind     = [_world intern:"#Reserved"];
   f.about    = thing;
   f.choice   = holder;
   f.credence = [store trustIn:speaker];
   f.rule     = [_world intern:"told"];
   f.time     = [_world time].ms;
   [store addFinding:f];
   [news addObject:[NSString stringWithFormat:@"R%u is reserved for R%u, R%u says", thing, holder, speaker]];
}


/* Credence (dB, -30 to 30) as a probability, in thousandths. */
static int32_t   permille_of( int32_t db)
{
   static const int32_t   table[ 61] =
   {
      1, 1, 2, 2, 3, 3, 4, 5, 6, 8, 10, 12, 16, 20, 25, 31, 38, 48, 59, 74, 91, 112, 137, 166, 201, 240, 285, 334,
      387, 443, 500, 557, 613, 666, 715, 760, 799, 834, 863, 888, 909, 926, 941, 952, 962, 969, 975, 980, 984, 988,
      990, 992, 994, 995, 996, 997, 997, 998, 998, 999, 999
   };

   db = db < -30 ? -30 : db > 30 ? 30 : db;
   return( table[ db + 30]);
}


/* A claim of what something is like (#IsLike): the thing, by its looks;
 * where the claim conflicts with what the agent believes of it, a competing
 * hypothesis (KNOWLEDGE.md §11), as credible as the speaker is to it. */
- (void) isLike:(const TriNode *) claim
           from:(uint32_t) speaker
          store:(BGKnowledgeStore *) store
           news:(NSMutableArray *) news
{
   const TriNode      *what;
   const TriNode      *as;
   const BGReferent   *r;
   NSMutableArray     *overrides;
   NSArray            *pairs;
   NSString           *kind;
   NSString           *pair;
   NSString           *key;
   NSString           *mine;
   NSUInteger         i;
   NSUInteger         k;
   uint32_t           thing;
   char               printed[ 2048];
   char               *features;

   what = tri_at( [_world tri], claim, "what");
   as   = tri_at( [_world tri], claim, "as");
   if( ! what || ! as)
      return;
   kind = [NSString stringWithUTF8String:(char *) tri_type_name( [_world tri], tri_node_type( what))];
   tri_print( [_world tri], what, printed, sizeof( printed));
   features = concrete_features( printed);
   thing    = 0;
   for( i = 0; i < [store count] && ! thing; i++)
   {
      r = [store referentAt:i];
      if( r->kind && ! strcmp( r->kind, [kind UTF8String]) && r->id != speaker &&
          [self looksAlike:r in:store kind:kind features:[NSString stringWithUTF8String:features]])
         thing = r->id;
   }
   free( features);
   if( ! thing)
      return;
   /* the claimed features that differ from what it believes */
   tri_print( [_world tri], as, printed, sizeof( printed));
   features  = concrete_features( printed);
   pairs     = BGSplitTopLevel( [NSString stringWithUTF8String:features]);
   free( features);
   overrides = [NSMutableArray array];
   for( k = 0; k < [pairs count]; k++)
   {
      pair = [pairs objectAtIndex:k];
      /* what it says: a feature with one value, not one the type leaves open */
      if( [pair rangeOfString:@": "].location == NSNotFound || [pair rangeOfString:@"|"].location != NSNotFound ||
          [pair rangeOfString:@">="].location != NSNotFound || [pair rangeOfString:@"<="].location != NSNotFound)
         continue;
      key  = [pair substringToIndex:[pair rangeOfString:@": "].location];
      mine = nil;
      {
         NSArray      *believed;
         NSUInteger   j;

         believed = BGSplitTopLevel( [store recall:[store referent:thing]]);
         for( j = 0; j < [believed count] && ! mine; j++)
            if( [[believed objectAtIndex:j] rangeOfString:[key stringByAppendingString:@": "]].location == 0)
               mine = [believed objectAtIndex:j];
      }
      if( mine && ! [mine isEqualToString:pair])
         [overrides addObject:pair];
   }
   if( ! [overrides count])
      return;
   [store suppose:[overrides componentsJoinedByString:@", "] about:thing mass:permille_of( [store trustIn:speaker])];
   [news addObject:[NSString stringWithFormat:@"R%u may be otherwise, R%u says: %@", thing, speaker,
                                              [overrides componentsJoinedByString:@", "]]];
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
      if( r->kind && ! strcmp( r->kind, [kind UTF8String]) && [self looksAlike:r in:store kind:kind features:features])
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
             via:(uint32_t) record
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
   int64_t            sure;
   int32_t            credence;
   BGLocationForm     form;
   BOOL               held;
   uint32_t           cid;
   uint32_t           thing;
   NSUInteger         i;
   NSUInteger         j;
   int                pass;
   char               printed[ 2048];

   tri   = [_world tri];
   arena = tri_arena_new();
   claim = tri_value( tri, content, arena, NULL, 0);
   if( claim && tri_subtype( tri, tri_node_type( claim), tri_type_named( tri, "#Serves")))
   {
      [self serves:claim from:speaker store:store news:news];
      tri_arena_free( arena);
      return;
   }
   if( claim && tri_subtype( tri, tri_node_type( claim), tri_type_named( tri, "#IsLike")))
   {
      [self isLike:claim from:speaker store:store news:news];
      tri_arena_free( arena);
      return;
   }
   if( claim && tri_subtype( tri, tri_node_type( claim), tri_type_named( tri, "#ReservedFor")))
   {
      [self reserved:claim from:speaker store:store news:news];
      tri_arena_free( arena);
      return;
   }
   held  = claim && tri_subtype( tri, tri_node_type( claim), tri_type_named( tri, "#IsHeld"));
   if( ! claim || (! held && (! tri_subtype( tri, tri_node_type( claim), tri_type_named( tri, "#IsIn")) ||
                              ! node_int( tri, claim, "within.place.x", &x) || ! node_int( tri, claim, "within.place.y", &y) ||
                              ! node_int( tri, claim, "within.place.level", &level))))
   {
      tri_arena_free( arena);
      return;
   }
   if( ! node_int( tri, claim, "when", &when))
      when = now;
   form   = held ? BGLocationHeldBy : BGLocationIn;
   what   = tri_at( tri, claim, "what");
   within = held ? tri_at( tri, claim, "holder") : tri_at( tri, claim, "within");
   kind   = tri_type_name( tri, tri_node_type( what));
   ckind  = tri_type_name( tri, tri_node_type( within));

   /* who it says saw it */
   memset( &t, 0, sizeof( t));
   t.source      = speaker;
   t.root        = speaker;
   t.attribution = BGSaw;
   t.sure        = BG_UNSTATED;
   attribution   = tri_at( tri, claim, "attribution");
   if( attribution && node_int( tri, attribution, "sure", &sure))
      t.sure = (int32_t) sure;
   if( attribution && tri_subtype( tri, tri_node_type( attribution), tri_type_named( tri, "#Pledged")))
      t.attribution = BGPledged;
   else if( attribution && tri_subtype( tri, tri_node_type( attribution), tri_type_named( tri, "#Heard")))
   {
      description   = tri_at( tri, attribution, "from");
      t.root        = description ? [self person:description store:store news:news] : 0;
      t.attribution = t.root ? BGHeardFrom : BGHeard;
   }

   /* the container, or who holds it */
   cid = held ? [self person:within store:store news:news] : 0;
   if( held && ! cid)
   {
      tri_arena_free( arena);
      return;
   }
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
         if( pass == 0 && r->present && r->form == form && r->container == cid)
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
   t.via       = record;
   t.when      = when;
   t.heard     = now;
   t.utterance = utterance;
   [store addTestimony:t];
   if( t.attribution == BGPledged)
   {
      /* about a time to come: held, not believed of now */
      [news addObject:[NSString stringWithFormat:@"R%u promises R%u will be in R%u by %lldms", speaker, thing, cid,
                                                 (long long) when]];
      tri_arena_free( arena);
      return;
   }
   credence = [store credenceThat:thing isIn:cid];

   m = [store mutableReferent:thing];
   if( m->present && ! m->toldBy && m->seen >= when && ! (m->form == form && m->container == cid))
   {
      /* seen elsewhere since: sight outranks it, and seen elsewhere as it was said, it is false */
      if( m->seen == when)
         settle( store, thing, cid, NO, now, news);
      else
         [news addObject:[NSString stringWithFormat:@"R%u says R%u is in R%u: seen elsewhere since", speaker, thing,
                                                    cid]];
      tri_arena_free( arena);
      return;
   }
   if( m->present && m->form == form && m->container == cid)
   {
      [news addObject:[NSString stringWithFormat:@"R%u is in R%u, R%u says too (%+d dB)", thing, cid, speaker,
                                                 credence]];
      tri_arena_free( arena);
      return;
   }
   if( credence < BG_BELIEVE ||
       (m->present && m->toldBy && (m->form == BGLocationIn || m->form == BGLocationHeldBy) &&
        [store credenceThat:thing isIn:m->container] > credence))
   {
      [news addObject:[NSString stringWithFormat:@"R%u says R%u is in R%u: not believed (%+d dB)", speaker, thing,
                                                 cid, credence]];
      tri_arena_free( arena);
      return;
   }
   c            = [store referent:cid];
   m->form      = form;
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


/* The features, without what comes and goes as a thing is used: free hands. */
static NSString   *lasting( NSString *features)
{
   NSMutableArray   *kept;
   NSArray          *pairs;
   NSUInteger       i;

   pairs = [features length] ? BGSplitTopLevel( features) : [NSArray array];
   kept  = [NSMutableArray array];
   for( i = 0; i < [pairs count]; i++)
      if( ! [[pairs objectAtIndex:i] hasPrefix:@"freeHands:"])
         [kept addObject:[pairs objectAtIndex:i]];
   return( [kept componentsJoinedByString:@", "]);
}


/* Whether a percept could be the referent by its looks: the features memory
 * keeps of it unify with those perceived, but for what comes and goes. */
- (BOOL) looksAlike:(const BGReferent *) r
                 in:(BGKnowledgeStore *) store
               kind:(NSString *) kind
           features:(NSString *) features
{
   const TriNode   *both;
   TriArena        *arena;
   NSString        *expr;

   expr  = [NSString stringWithFormat:@"%@ & { %@ } & { %@ }", kind, lasting( [store recall:r]), lasting( features)];
   arena = tri_arena_new();
   both  = tri_value( [_world tri], [expr UTF8String], arena, NULL, 0);
   tri_arena_free( arena);
   return( both != NULL);
}


/* Testimony that the thing is inside the container is settled: seen true,
 * and its source and root are trusted more, or found false, and they are
 * trusted less. */
static void   settle( BGKnowledgeStore *store, uint32_t thing, uint32_t container, BOOL true_, int64_t now,
                      NSMutableArray *news)
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
      if( t->attribution == BGPledged && ! true_ && now < t->when)
         continue;      /* not due yet */
      t->settled = true_ ? 1 : -1;
      [store adjustTrustIn:t->source by:delta];
      if( t->root && t->root != t->source)
         [store adjustTrustIn:t->root by:delta];
      if( t->attribution == BGPledged)
         [news addObject:[NSString stringWithFormat:@"R%u promised R%u would be in R%u: %s", t->source, thing, container,
                                                    true_ ? "kept" : "broken"]];
      else
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


/* Traces in reach of their sense: on what it sees, or on the floor; how
 * strong each seems now. One it perceived at a site it perceives again, and
 * doesn't find, is gone. */
- (void) perceiveTraces:(BGKnowledgeStore *) store
                     at:(BGLocation) here
                    now:(int64_t) now
                   seen:(const BGSeen *) seen
               assigned:(const uint32_t *) assigned
                  count:(NSUInteger) nseen
                closely:(BOOL) closely
                   news:(NSMutableArray *) news
{
   const BGTrace   *record;
   const TriNode   *v;
   BGTraceSeen     *old;
   BGTraceSeen     t;
   BGLocation      tile;
   BGStore         *traces;
   TriContent      *tri;
   NSUInteger      i;
   NSUInteger      j;
   uint8_t         *found;
   int64_t         strength;
   int32_t         range[ 3];
   int             sensed;
   char            sense[ 16];
   const char      *kind;

   tri      = [_world tri];
   traces   = [_world storeForKind:[_world kindNamed:"Trace"]];
   range[ 0] = BG_SIGHT;
   range[ 1] = BG_SMELL + (closely ? 1 : 0);
   range[ 2] = BG_HEARING;
   for( i = 0; i < [traces count]; i++)
   {
      record   = [traces recordAtIndex:i];
      kind     = [_world textField:"Trace.traceKind" of:[traces entityAtIndex:i]];
      strength = BGTraceStrength( record, now);
      if( ! kind || strength <= 0 || strength < (closely ? BG_TRACE_FLOOR_CLOSE : BG_TRACE_FLOOR))
         continue;      /* too faint to notice */
      v = tri_at( tri, tri_pattern( tri, kind), "sense");
      sense[ 0] = 0;
      if( v)
         tri_print( tri, v, sense, sizeof( sense));
      sensed = ! strcmp( sense, "\"smell\"") ? 1 : ! strcmp( sense, "\"hearing\"") ? 2 : 0;
      memset( &t, 0, sizeof( t));
      if( record->bearer)
      {
         for( j = 0; j < nseen && seen[ j].entity != (BGEntityID) record->bearer; j++)
            ;
         if( j == nseen || ! ground_tile( _world, (BGEntityID) record->bearer, &tile))
            continue;      /* it doesn't see what bears it */
         t.bearer = assigned[ j];
         t.x      = tile.x;
         t.y      = tile.y;
         t.level  = tile.level;
      }
      else
      {
         t.x     = (int32_t) record->tileX;
         t.y     = (int32_t) record->tileY;
         t.level = (int32_t) record->tileLevel;
      }
      if( ! _omniscient && (t.level != here.level || abs( t.x - here.x) > range[ sensed] ||
                            abs( t.y - here.y) > range[ sensed]))
         continue;
      t.kind     = [_world intern:kind];
      t.strength = (int32_t) strength;
      t.seen     = now;
      t.present  = YES;
      t.truth    = [traces entityAtIndex:i];        /* developer-only */
      if( [store noteTrace:t])
         [news addObject:t.bearer ? [NSString stringWithFormat:@"R%u bears %s (%d)", t.bearer, t.kind, t.strength]
                                  : [NSString stringWithFormat:@"%s at (%d, %d) (%d)", t.kind, t.x, t.y, t.strength]];
   }

   /* gone: perceived before, where it would be perceived now, and not found */
   found = calloc( [store traceCount] + 1, 1);
   for( i = 0; i < [store traceCount]; i++)
      found[ i] = [store traceAt:i]->seen == now;
   for( i = 0; i < [store traceCount]; i++)
   {
      old = [store mutableTraceAt:i];
      if( found[ i] || ! old->present)
         continue;
      if( ! closely && old->strength < BG_TRACE_FLOOR)
         continue;      /* caught only on a close look: a glance can't miss it */
      v = tri_at( tri, tri_pattern( tri, old->kind), "sense");
      sense[ 0] = 0;
      if( v)
         tri_print( tri, v, sense, sizeof( sense));
      sensed = ! strcmp( sense, "\"smell\"") ? 1 : ! strcmp( sense, "\"hearing\"") ? 2 : 0;
      if( old->bearer)
      {
         for( j = 0; j < nseen && assigned[ j] != old->bearer; j++)
            ;
         if( j == nseen || ! ground_tile( _world, seen[ j].entity, &tile))
            continue;      /* not looking at what bore it */
      }
      else
      {
         tile.x     = old->x;
         tile.y     = old->y;
         tile.level = old->level;
      }
      if( ! _omniscient && (tile.level != here.level || abs( tile.x - here.x) > range[ sensed] ||
                            abs( tile.y - here.y) > range[ sensed]))
         continue;
      old->present = NO;
      old->seen    = now;
      [news addObject:old->bearer ? [NSString stringWithFormat:@"the %s on R%u is gone", old->kind, old->bearer]
                                  : [NSString stringWithFormat:@"the %s at (%d, %d) is gone", old->kind, old->x, old->y]];
   }
   free( found);
}


/* Whether the agent perceives a trace of the kind on the referent: there
 * now, or (`gone`) there before and not any more. */
/* A quoted text feature of a description ("claims: \"the harbour office\""),
 * or nil. */
static NSString   *quoted_feature( NSString *description, NSString *name)
{
   NSRange    at;
   NSRange    end;
   NSString   *key;

   key = [NSString stringWithFormat:@"%@: \"", name];
   at  = [description rangeOfString:key];
   if( at.location == NSNotFound)
      return( nil);
   end = [description rangeOfString:@"\"" options:0
                              range:NSMakeRange( at.location + at.length, [description length] - at.location - at.length)];
   if( end.location == NSNotFound)
      return( nil);
   return( [description substringWithRange:NSMakeRange( at.location + at.length, end.location - at.location - at.length)]);
}


/* Whether the referent is a copy claiming an issuer whose seal the agent has
 * seen, with an impression not that seal's. */
static BOOL   misprinted( BGKnowledgeStore *store, uint32_t referent)
{
   NSString     *copy;
   NSString     *claims;
   NSString     *impression;
   NSString     *seal;
   NSUInteger   i;

   copy       = [store describeReferent:referent];
   claims     = quoted_feature( copy, @"claims");
   impression = quoted_feature( copy, @"impression");
   if( ! [claims length] || ! impression)
      return( NO);
   for( i = 0; i < [store count]; i++)
   {
      seal = [store describeReferent:[store referentAt:i]->id];
      if( [quoted_feature( seal, @"sealOf") isEqualToString:claims] && quoted_feature( seal, @"presses") &&
          ! [quoted_feature( seal, @"presses") isEqualToString:impression])
         return( YES);
   }
   return( NO);
}


/* Whether it noticed the referent lose some of `field`, wear that comes and
 * never goes. */
static BOOL   unworn( BGKnowledgeStore *store, uint32_t referent, const char *field)
{
   const BGObservation   *o;
   NSUInteger            i;

   for( i = 0; i < [store observationCount]; i++)
   {
      o = [store observationAt:i];
      if( ! strcmp( o->kind, "unworn") && o->subject == referent && o->content && ! strcmp( o->content, field))
         return( YES);
   }
   return( NO);
}


/* A whole-number feature of a description's features ("toolMarks: 40"). */
static BOOL   int_feature( const char *features, const char *field, int64_t *value)
{
   const char   *p;
   size_t       n;

   n = strlen( field);
   for( p = features; p && (p = strstr( p, field)); p += n)
      if( (p == features || p[ -1] == ' ' || p[ -1] == '{') && ! strncmp( p + n, ": ", 2) &&
          (p[ n + 2] == '-' || (p[ n + 2] >= '0' && p[ n + 2] <= '9')))
      {
         *value = atoll( p + n + 2);
         return( YES);
      }
   return( NO);
}


static BOOL   bears( BGKnowledgeStore *store, uint32_t referent, const char *kind, BOOL gone)
{
   const BGTraceSeen   *t;
   NSUInteger          i;

   for( i = 0; i < [store traceCount]; i++)
   {
      t = [store traceAt:i];
      if( t->bearer == referent && ! strcmp( t->kind, kind) && t->present == ! gone)
         return( YES);
   }
   return( NO);
}


/* Whether the agent perceives a trace of the kind on the floor at the
 * referent's tile or beside it. */
static BOOL   near( BGKnowledgeStore *store, const BGReferent *r, const char *kind)
{
   const BGTraceSeen   *t;
   NSUInteger          i;

   for( i = 0; i < [store traceCount]; i++)
   {
      t = [store traceAt:i];
      if( ! t->bearer && t->present && ! strcmp( t->kind, kind) && t->level == r->level &&
          abs( t->x - r->x) <= 1 && abs( t->y - r->y) <= 1)
         return( YES);
   }
   return( NO);
}


/* The container the agent was seen to put things into at least `times`
 * times, by that referent; the most often, the lowest first; or 0. */
/* Where the agent itself has put the thing at least `times` times, the most;
 * or 0: its habit for it (AGENCY.md §8), as it remembers doing it. */
static uint32_t   own_usual_place( BGKnowledgeStore *store, uint32_t thing, int64_t times)
{
   const BGObservation   *o;
   const BGReferent      *c;
   NSUInteger            i;
   NSUInteger            j;
   uint32_t              best;
   int64_t               n;
   int64_t               most;

   best = 0;
   most = 0;
   for( i = 0; i < [store observationCount]; i++)
   {
      o = [store observationAt:i];
      c = [store referent:o->other];
      if( strcmp( o->kind, "moved") || o->actor != [store selfReferent] || o->subject != thing || ! c || ! c->kind ||
          ! strcmp( c->kind, "#Agent"))
         continue;
      for( n = 0, j = 0; j < [store observationCount]; j++)
         if( ! strcmp( [store observationAt:j]->kind, "moved") && [store observationAt:j]->actor == [store selfReferent] &&
             [store observationAt:j]->subject == thing && [store observationAt:j]->other == o->other)
            n++;
      if( n >= times && (n > most || (n == most && o->other < best)))
      {
         most = n;
         best = o->other;
      }
   }
   return( best);
}


static uint32_t   usual_place( BGKnowledgeStore *store, uint32_t actor, int64_t times)
{
   const BGObservation   *o;
   const BGReferent      *c;
   NSUInteger            i;
   NSUInteger            j;
   uint32_t              best;
   int64_t               n;
   int64_t               most;

   best = 0;
   most = 0;
   for( i = 0; i < [store observationCount]; i++)
   {
      o = [store observationAt:i];
      c = [store referent:o->other];
      if( strcmp( o->kind, "moved") || o->actor != actor || ! c || ! c->kind || ! strcmp( c->kind, "#Agent"))
         continue;
      for( n = 0, j = 0; j < [store observationCount]; j++)
         if( ! strcmp( [store observationAt:j]->kind, "moved") && [store observationAt:j]->actor == actor &&
             [store observationAt:j]->other == o->other)
            n++;
      if( n >= times && (n > most || (n == most && o->other < best)))
      {
         most = n;
         best = o->other;
      }
   }
   return( best);
}


/* Immediate interpretation: each rule the agent has the expertise for, over
 * each referent; a rule whose premises all hold adds its finding. */
- (void) interpret:(BGKnowledgeStore *) store
      deliberately:(BOOL) deliberately
              news:(NSMutableArray *) news
{
   const TriNode      *rule;
   const TriNode      *list;
   const TriNode      *premise;
   const TriNode      *v;
   const BGReferent   *r;
   TriContent         *tri;
   TriIndex           *family;
   BGFinding          f;
   NSUInteger         i;
   NSUInteger         j;
   int64_t            lo;
   int64_t            hi;
   int64_t            skill;
   int64_t            mastery;
   char               text[ 64];
   char               path[ 96];
   char               concludes[ 64];
   size_t             n;
   uint32_t           choice;
   BOOL               holds;

   tri    = [_world tri];
   family = tri_family_index( tri, "rules");
   for( i = 0; family && i < tri_index_count( family); i++)
   {
      rule = tri_pattern( tri, tri_index_tag( family, i));
      v    = tri_at( tri, rule, "deliberate");
      if( v && ! deliberately && tri_node_type( v) == tri_type_named( tri, "true"))
         continue;      /* it takes thought: only when investigating */
      v    = tri_at( tri, rule, "concludes");
      n    = v ? tri_print( tri, v, concludes, sizeof( concludes)) : 0;
      if( n < 3)
         continue;
      memmove( concludes, concludes + 1, n - 2);
      concludes[ n - 2] = 0;
      /* expertise: the agent's own skill, which it knows */
      v       = tri_at( tri, rule, "mastery");
      mastery = v && tri_node_interval( v, &lo, &hi) && lo == hi ? lo : 0;
      v       = tri_at( tri, rule, "skill");
      if( v && tri_print( tri, v, text, sizeof( text)) > 2 && text[ 0] == '"')
      {
         text[ strlen( text) - 1] = 0;
         snprintf( path, sizeof( path), "Agent.%s", text + 1);
         skill = 0;
         if( ! [_world getField:path of:[store agent] value:&skill] || skill < mastery)
            continue;
      }
      for( j = 0; j < [store count]; j++)
      {
         r = [store referentAt:j];
         if( r->id == [store selfReferent] || [store finding:concludes about:r->id])
            continue;
         holds  = YES;
         choice = 0;
         for( list = tri_at( tri, rule, "premises"); holds && list && (premise = tri_at( tri, list, "first"));
              list = tri_at( tri, list, "rest"))
         {
            if( (v = tri_at( tri, premise, "sign")) && tri_print( tri, v, text, sizeof( text)) > 2)
            {
               text[ strlen( text) - 1] = 0;
               holds = bears( store, r->id, text + 1, NO);
            }
            else if( (v = tri_at( tri, premise, "formerly")) && tri_print( tri, v, text, sizeof( text)) > 2)
            {
               text[ strlen( text) - 1] = 0;
               holds = bears( store, r->id, text + 1, YES);
            }
            else if( (v = tri_at( tri, premise, "misprinted")))
               holds = misprinted( store, r->id);
            else if( (v = tri_at( tri, premise, "unworn")) && tri_print( tri, v, text, sizeof( text)) > 2)
            {
               text[ strlen( text) - 1] = 0;
               holds = unworn( store, r->id, text + 1);
            }
            else if( (v = tri_at( tri, premise, "repeated")) && tri_node_interval( v, &lo, &hi) && lo == hi)
               holds = (choice = usual_place( store, r->id, lo)) != 0;
            else if( (v = tri_at( tri, premise, "near")) && tri_print( tri, v, text, sizeof( text)) > 2)
            {
               text[ strlen( text) - 1] = 0;
               holds = r->present && near( store, r, text + 1);
            }
            else
               holds = NO;      /* a premise it can't read never holds */
         }
         if( ! holds)
            continue;
         memset( &f, 0, sizeof( f));
         f.kind   = [_world intern:concludes];
         f.about  = r->id;
         f.choice = choice;
         v       = tri_at( tri, rule, "weight");
         f.credence = v && tri_node_interval( v, &lo, &hi) && lo == hi ? (int32_t) lo : 0;
         f.rule  = [_world intern:tri_index_tag( family, i)];
         f.time  = [_world time].ms;
         [store addFinding:f];
         [news addObject:[NSString stringWithFormat:@"R%u: %s, by %s (%+d dB)", r->id, f.kind, f.rule, f.credence]];
      }
   }
}


/* Seen again with less of a wear the rules watch for (#Unworn) than it had
 * when last seen: noticed, an anomaly, kept as an observation for them. */
- (void) noticeWearLost:(const BGReferent *) r
               features:(NSString *) features
                  store:(BGKnowledgeStore *) store
                    now:(int64_t) now
                   news:(NSMutableArray *) news
{
   const TriNode   *rule;
   const TriNode   *list;
   const TriNode   *v;
   TriContent      *tri;
   TriIndex        *family;
   BGObservation   o;
   NSUInteger      i;
   int64_t         before;
   int64_t         after;
   char            field[ 64];

   if( ! r->features || r->id == [store selfReferent])
      return;
   tri    = [_world tri];
   family = tri_family_index( tri, "rules");
   for( i = 0; family && i < tri_index_count( family); i++)
   {
      rule = tri_pattern( tri, tri_index_tag( family, i));
      for( list = tri_at( tri, rule, "premises"); list && tri_at( tri, list, "first"); list = tri_at( tri, list, "rest"))
      {
         v = tri_at( tri, tri_at( tri, list, "first"), "unworn");
         if( ! v || tri_print( tri, v, field, sizeof( field)) < 3)
            continue;
         field[ strlen( field) - 1] = 0;
         if( ! int_feature( r->features, field + 1, &before) || ! int_feature( [features UTF8String], field + 1, &after) ||
             after >= before || unworn( store, r->id, field + 1))
            continue;
         memset( &o, 0, sizeof( o));
         o.time     = now;
         o.kind     = [_world intern:"unworn"];
         o.subject  = r->id;
         o.content  = (char *) [_world intern:field + 1];
         o.salience = BG_ANOMALY;
         [store addObservation:o restored:NO];
         [news addObject:[NSString stringWithFormat:@"R%u looks new: its %s is gone", r->id, field + 1]];
      }
   }
}


- (void) perceive:(BGKnowledgeStore *) store
             from:(NSUInteger) first
               to:(NSUInteger) last
{
   const BGEvent      *ev;
   const BGThermalBody *body;
   const BGGasStore   *gas;
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
   BOOL               closely;
   BOOL               degraded;
   NSUInteger         maybe;
   int                maybeN;
   int                maybeD;
   int                maybeA;
   char               maybePaths[ 64];
   const BGAgent      *hider;
   const BGAgent      *memory;
   NSArray            *concerns;
   int                notice;
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
   NSUInteger         glance[ 64];
   NSUInteger         nglance;

   agent   = [store agent];
   news    = [store mutableNews];
   nglance = 0;
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
      if( ! ground_tile( _world, e, &tile) || ! [self sees:tile from:here])
         continue;
      at = [_world locationOf:e];
      if( at.form == BGLocationIn && ! _omniscient && ! contains( lookedIn, nlooked, at.place) &&
          ! contains( glimpsed, nglimpsed, e))
         continue;          /* inside, unseen */
      hider = [_world record:[_world kindNamed:"Agent"] for:e];
      if( hider && hider->hiding && e != agent && ! _omniscient &&
          (abs( tile.x - here.x) > 1 || abs( tile.y - here.y) > 1))
         continue;          /* half hidden: seen only from close by */
      seen[ nseen].entity = e;
      seen[ nseen].depth  = depth_of( _world, e);
      nseen++;
   }
   qsort( seen, nseen, sizeof( BGSeen), cmp_seen);
   for( y = here.y - BG_SIGHT; y <= here.y + BG_SIGHT; y++)
      for( x = here.x - BG_SIGHT; x <= here.x + BG_SIGHT; x++)
      {
         tile       = here;
         tile.x     = x;
         tile.y     = y;
         if( [self sees:tile from:here])
            [store setTileSeen:now x:x y:y];
      }

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
         features = [view featuresOf:seen[ i].entity all:_omniscient];
         at       = [_world locationOf:seen[ i].entity];
         ground_tile( _world, seen[ i].entity, &tile);
         /* by the light: at dusk, beyond arm's reach, a step less precisely;
          * at night, within it, unless just handled */
         degraded = ! _omniscient && seen[ i].entity != agent &&
                    (([self lightAt:tile] == 1 && (abs( tile.x - here.x) > 1 || abs( tile.y - here.y) > 1)) ||
                     ([self lightAt:tile] == 0 && ! contains( lookedIn, nlooked, seen[ i].entity)));
         if( degraded)
            features = [store generalize:features kind:[kind UTF8String] steps:1];
         /* from afar, sizes only roughly */
         if( ! _omniscient && seen[ i].entity != agent)
            features = [self blur:features kind:[kind UTF8String]
                         distance:(int) max64( abs( tile.x - here.x), abs( tile.y - here.y)) blurred:&degraded];
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
            best      = NSNotFound;
            bestd     = 1 << 30;
            maybe     = NSNotFound;
            maybeN    = 1 << 30;
            maybeD    = 1 << 30;
            maybePaths[ 0] = 0;
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
               /* elsewhere, a referent known by nothing matches anyone: weakly */
               if( ! exact && ! [self knowsAnythingOf:r in:store])
                  continue;
               /* elsewhere than believed, it must look the same: the crate isn't the chest;
                * unless only what changes daily differs, when it may be the same, changed */
               if( ! exact && ! [self looksAlike:r in:store kind:kind features:features])
               {
                  int    nc;
                  int    agree;
                  char   paths[ 64];

                  nc = [self conflictsOf:r in:store kind:kind features:features paths:paths length:sizeof( paths)
                                   agree:&agree];
                  if( pass == 1 && nc && [self shortLived:paths] && (nc < maybeN || (nc == maybeN && d < maybeD)))
                  {
                     maybe  = j;
                     maybeN = nc;
                     maybeD = d;
                     maybeA = agree;
                     strncpy( maybePaths, paths, sizeof( maybePaths) - 1);
                  }
                  continue;
               }
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
               uint32_t   other;

               other = maybe != NSNotFound ? [store referentAt:maybe]->id : 0;
               r     = [store addReferent:0];
               [news addObject:[NSString stringWithFormat:@"R%u: %@, at (%d, %d)", r->id, kind, tile.x, tile.y]];
               if( other)
               {
                  BGIdentity   h;

                  /* it may be the other, changed: the agreeing paths for it, the conflicts against */
                  memset( &h, 0, sizeof( h));
                  h.a        = r->id;
                  h.b        = other;
                  h.credence = BG_PRIOR + 3 * maybeA - 5 * maybeN;
                  h.time     = now;
                  strncpy( h.paths, maybePaths, sizeof( h.paths) - 1);
                  [store addIdentity:h];
                  [news addObject:[NSString stringWithFormat:@"R%u may be R%u (%+d dB): only %s differs", r->id, other,
                                                             h.credence, h.paths]];
               }
            }
            else
            {
               r = (BGReferent *) [store referentAt:best];
               if( ! (r->present && r->form == at.form && r->container == container &&
                      (container || (r->x == tile.x && r->y == tile.y))))
                  [news addObject:[NSString stringWithFormat:@"R%u is at (%d, %d) now", r->id, tile.x, tile.y]];
            }
         }
         /* it fits the other of a hypothesis about it as well: evidence they
          * are one, once a sighting (not seen for a minute before) */
         for( j = 0; r->id != [store selfReferent] && now - r->seen > 60000 && j < [store identityCount]; j++)
         {
            BGIdentity         *h;
            const BGReferent   *o;

            h = [store mutableIdentityAt:j];
            if( (h->a != r->id && h->b != r->id) || h->time >= now)
               continue;
            o = [store referent:h->a == r->id ? h->b : h->a];
            if( ! o || ! [self looksAlike:o in:store kind:kind features:features])
               continue;
            h->credence += 10;
            h->time      = now;
            [news addObject:[NSString stringWithFormat:@"R%u may be R%u (%+d dB): it fits both", h->a, h->b, h->credence]];
         }

         /* the referent takes what was perceived: kept more specific where
          * memory was, when it was seen less well */
         if( r->features && r->id != [store selfReferent] && degraded)
            features = [self unified:r in:store kind:kind features:features];
         [self noticeWearLost:r features:features store:store now:now news:news];
         /* seen plainly, a competing hypothesis is settled */
         if( ! degraded && r->supposed[ 0])
         {
            [news addObject:[NSString stringWithFormat:@"R%u is plainly as it seems: no doubt about it now", r->id]];
            [store dropSupposed:r->id];
         }
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
         /* a label, on sighting it (not seen for a minute before), is read below */
         if( nglance < 64 && (! r->seen || now - r->seen > 60000) &&
             [_world record:[_world kindNamed:"Label"] for:seen[ i].entity])
            glance[ nglance++] = i;
         r->seen      = now;
         r->present   = YES;
         r->truth     = seen[ i].entity;                /* developer-only */
         r->toldBy    = 0;
         if( _omniscient || contains( lookedIn, nlooked, seen[ i].entity))
            r->insideSeen = now;
         if( r->form == BGLocationIn || r->form == BGLocationHeldBy)
            settle( store, r->id, r->container, YES, now, news);
         assigned[ i] = r->id;
         for( j = 0; j < [store count]; j++)
            if( [store referentAt:j]->id == r->id)
               taken[ j] = 1;
      }

   /* a close look: what its investigation ends in */
   closely = NO;
   for( i = first; i < last; i++)
      if( [_world eventAt:i]->actor == agent && ! strcmp( [_world eventAt:i]->kind, "investigated"))
         closely = YES;
   [self perceiveTraces:store at:here now:now seen:seen assigned:assigned count:nseen closely:closely news:news];

   /* what it read: each entry, from the author, in the record */
   for( i = first; i < last; i++)
   {
      const TriNode   *who;
      TriArena        *arena;
      NSArray         *entries;
      NSString        *by;
      NSUInteger      k;
      uint32_t        author;
      uint32_t        record;

      ev = [_world eventAt:i];
      if( ev->actor != agent || strcmp( ev->kind, "read") || ! ev->detail)
         continue;
      by      = nil;
      entries = BGWritingEntries( ev->detail, &by);
      arena   = tri_arena_new();
      who     = by ? tri_value( [_world tri], [by UTF8String], arena, NULL, 0) : NULL;
      author  = who ? [self person:who store:store news:news] : 0;
      tri_arena_free( arena);
      record  = bound_to( ev->other, agent, [store selfReferent], seen, assigned, nseen);
      for( k = 0; author && k < [entries count]; k++)
         [self believe:[[entries objectAtIndex:k] UTF8String] from:author via:record utterance:ev->index at:now
                 store:store news:news];
   }

   /* what a label it sighted says, read at a glance from close enough
    * (ACTIONS.md §7's tag): each entry, from the author, in the label */
   for( j = 0; j < nglance; j++)
   {
      const TriNode   *who;
      const BGLabel   *label;
      TriArena        *arena;
      NSArray         *entries;
      NSString        *by;
      const char      *written;
      NSUInteger      k;
      uint32_t        author;

      i     = glance[ j];
      label = [_world record:[_world kindNamed:"Label"] for:seen[ i].entity];
      if( ! ground_tile( _world, seen[ i].entity, &tile) || tile.level != here.level ||
          abs( tile.x - here.x) > label->legible || abs( tile.y - here.y) > label->legible)
         continue;
      written = [_world textField:"Record.writing" of:seen[ i].entity];
      if( ! written || ! *written)
         continue;
      by      = nil;
      entries = BGWritingEntries( written, &by);
      arena   = tri_arena_new();
      who     = by ? tri_value( [_world tri], [by UTF8String], arena, NULL, 0) : NULL;
      author  = who ? [self person:who store:store news:news] : 0;
      tri_arena_free( arena);
      for( k = 0; author && k < [entries count]; k++)
         [self believe:[[entries objectAtIndex:k] UTF8String] from:author via:assigned[ i] utterance:0 at:now
                 store:store news:news];
   }

   /* what its own analyses found beneath the looks of what they analysed */
   for( i = first; i < last; i++)
   {
      ev = [_world eventAt:i];
      if( ev->actor != agent || strcmp( ev->kind, "analysed") || ! ev->detail)
         continue;
      r = [store mutableReferent:bound_to( ev->other, agent, [store selfReferent], seen, assigned, nseen)];
      if( ! r)
         continue;
      free( r->deeper);
      r->deeper = strdup( ev->detail);
      [news addObject:[NSString stringWithFormat:@"R%u, beneath its looks: %s", r->id, ev->detail]];
   }

   /* absence: believed at a place in sight, and not seen there */
   for( j = 0; j < [store count]; j++)
   {
      const BGReferent   *holder;

      r = (BGReferent *) [store referentAt:j];
      if( taken[ j] || ! r->present)
         continue;
      {
         BGLocation   believed;

         believed       = here;
         believed.x     = r->x;
         believed.y     = r->y;
         believed.level = r->level;
         if( ! [self sees:believed from:here])
            continue;       /* out of sight, or dark there */
      }
      if( r->form == BGLocationIn && ! _omniscient)
      {
         holder = [store referent:r->container];
         if( ! holder || ! contains( lookedIn, nlooked, holder->truth))
            continue;       /* inside, and not looked into: nothing to contradict it */
      }
      r->present = NO;
      [news addObject:[NSString stringWithFormat:@"R%u is not where it was", r->id]];
   }

   /* what has faded too far, forgotten */
   for( j = 0; j < [store count]; j++)
   {
      uint32_t   habit;

      r = (BGReferent *) [store referentAt:j];
      if( ! r->present || r->id == [store selfReferent] || [store strengthOf:r->id] >= BG_BELIEVE)
         continue;
      /* what it always puts in the same place, it believes is there (AGENCY.md
       * Scenario 1: Oskar always hangs the wrench on the hook) */
      if( (habit = own_usual_place( store, r->id, 3)))
      {
         if( r->form != BGLocationIn || r->container != habit)
         {
            r->form      = BGLocationIn;
            r->container = habit;
            [news addObject:[NSString stringWithFormat:@"R%u: where it always goes, in R%u", r->id, habit]];
         }
         continue;
      }
      r->present = NO;
      [news addObject:[NSString stringWithFormat:@"R%u: forgotten where it was", r->id]];
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
              now, news);
   }

   /* what it saw happen, in its referents, kept if salient; what it heard
    * said, if it noticed, believed */
   memory   = [_world record:[_world kindNamed:"Agent"] for:agent];
   notice   = BG_NOTICE + [self attentionOf:agent] - (memory ? (int) memory->curious / 10 : 0);

   /* interoception: hunger, to the band, dulled by attention, blurred by
    * exhaustion */
   if( memory)
   {
      int64_t   hunger;
      int64_t   band;

      /* exhaustion blurs it (AGENCY.md §6): felt half as precisely */
      band   = memory->fatigue >= 80 ? 2 * BG_HUNGER_BAND : BG_HUNGER_BAND;
      hunger = 100 - BGSatiety( memory, now) - 2 * [self attentionOf:agent];
      hunger = hunger < 0 ? 0 : (hunger / band) * band;
      if( [store feelHunger:(int32_t) hunger at:now])
         [news addObject:[NSString stringWithFormat:@"you feel hunger (%d)", (int) hunger]];
   }

   /* and cold, from its body's heat (the thermal domain's): ten points a
    * kelvin below 310 K, to the band */
   if( (body = [_world record:[_world kindNamed:"ThermalBody"] for:agent]) && body->heatCapacity)
   {
      int64_t   cold;

      cold = (310000 - body->heat * 1000 / body->heatCapacity) / 100;
      /* numbness hides it */
      if( memory)
         cold -= memory->numbness;
      cold = cold < 0 ? 0 : cold > 100 ? 100 : (cold / BG_HUNGER_BAND) * BG_HUNGER_BAND;
      if( [store feelCold:(int32_t) cold])
         [news addObject:[NSString stringWithFormat:@"you feel cold (%d)", (int) cold]];
   }

   /* and pain, from its injury (a component field), dulled by adrenaline */
   if( memory)
   {
      int64_t   pain;

      pain = (int64_t) memory->injury - memory->adrenaline;
      pain = pain < 0 ? 0 : (pain / BG_HUNGER_BAND) * BG_HUNGER_BAND;
      if( [store feelPain:(int32_t) pain])
         [news addObject:[NSString stringWithFormat:@"you feel pain (%d)", (int) pain]];
   }

   /* and tired, from its fatigue (a component field), to the band */
   if( memory)
   {
      int64_t   tired;

      tired = (memory->fatigue / BG_HUNGER_BAND) * BG_HUNGER_BAND;
      if( [store feelTired:(int32_t) tired])
         [news addObject:[NSString stringWithFormat:@"you feel tired (%d)", (int) tired]];
   }

   /* and short of breath, for something that breathes: from the carbon
    * dioxide in the air over it (the atmosphere's; the blood's gases stand
    * in for by the air's), ten points for every 0.1% above 0.1%, to the band */
   if( [_world record:[_world kindNamed:"Respirator"] for:agent] &&
       (gas = [_world record:[_world kindNamed:"GasStore"] for:BGAirOver( _world, agent)]) && gas->total)
   {
      int64_t   stuffy;

      stuffy = (gas->dioxide * 1000000 / gas->total - 1000) / 100;
      stuffy = stuffy < 0 ? 0 : stuffy > 100 ? 100 : (stuffy / BG_HUNGER_BAND) * BG_HUNGER_BAND;
      if( [store feelStuffy:(int32_t) stuffy])
         [news addObject:[NSString stringWithFormat:@"you feel short of breath (%d)", (int) stuffy]];
   }
   concerns = _concerns ? [_concerns concernsOf:agent] : nil;
   for( i = 0; i < nwitnessed; i++)
   {
      NSUInteger   lines;

      lines = [news count];
      ev    = [_world eventAt:witnessed[ i]];
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
      o.salience = 0;
      if( o.actor == [store selfReferent])
         o.salience = BG_OWN_DEED;
      if( ! strcmp( ev->kind, "said") && o.other == [store selfReferent])
         o.salience = BG_ADDRESSED;
      if( o.salience < BG_CONCERN &&
          [self concerns:concerns
             description:! strcmp( ev->kind, "said") ? [self topicOf:ev->detail] : [store describeReferent:o.subject]])
         o.salience = BG_CONCERN;
      /* someone not doing as they usually do */
      if( ! strcmp( ev->kind, "moved") && o.other && ev->location.form == BGLocationIn)
      {
         NSUInteger   k;

         for( k = 0; k < [store findingCount]; k++)
         {
            const BGFinding   *habit;

            habit = [store findingAt:k];
            if( ! strcmp( habit->kind, "#Habit") && habit->about == o.actor && habit->choice && habit->choice != o.other)
            {
               o.salience = BG_ANOMALY > o.salience ? BG_ANOMALY : o.salience;
               [news addObject:[NSString stringWithFormat:@"R%u broke a habit: R%u, not R%u, this time", o.actor, o.other,
                                                          habit->choice]];
            }
         }
      }
      if( o.salience < notice)
      {
         [news removeObjectsInRange:NSMakeRange( lines, [news count] - lines)];
         continue;      /* unnoticed */
      }
      [store addObservation:o restored:NO];
      if( ! strcmp( ev->kind, "said") && ev->detail && o.actor && o.actor != [store selfReferent])
         [self believe:ev->detail from:o.actor via:0 utterance:ev->index at:now store:store news:news];
   }
   memory = [_world record:[_world kindNamed:"Agent"] for:agent];
   [store keepAtMost:memory && memory->memory > 0 ? (NSUInteger) memory->memory : 64];
   [self interpret:store deliberately:closely news:news];
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
   if( tri_at( tri, claim, "attribution") &&
       tri_subtype( tri, tri_node_type( tri_at( tri, claim, "attribution")), tri_type_named( tri, "#Pledged")))
   {
      tri_arena_free( arena);
      return;      /* a promise, not a claim of what is */
   }
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
   {
      [self perceive:[self storeOf:[agents entityAtIndex:i]]
                from:_eventsSeen
                  to:last];
      /* housekeeping: the knowledge arena, compacted when half garbage */
      [[self storeOf:[agents entityAtIndex:i]] compact:_compactAlways];
   }
   _eventsSeen = last;
}


/* --- the developer's view ---------------------------------------------------------- */

static NSString   *attribution_text( const BGTestimony *t)
{
   switch( t->attribution)
   {
   case BGHeardFrom : return( [NSString stringWithFormat:@"heard from R%u", t->root]);
   case BGHeard     : return( @"heard");
   case BGPledged   : return( @"promised");
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
         [s appendFormat:@"    R%u %@ at %lldms, as of %lldms: %@, %@, weight %+d dB%s; truly %@\n", u->source,
                         u->via ? [NSString stringWithFormat:@"wrote so in R%u, read", u->via] : @"said so",
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
   NSUInteger            j;

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
      for( j = 0; j < BG_HYPOTHESES && r->supposed[ j]; j++)
         [s appendFormat:@"    or, %d in 1000: %s\n", r->supposedMass[ j], r->supposed[ j]];
   }
   for( i = 0; i < [store traceCount]; i++)
   {
      const BGTraceSeen   *t;

      t = [store traceAt:i];
      [s appendFormat:@"  trace %s %@, strength %d, at %lldms%s, truth %llu\n", t->kind,
                      t->bearer ? [NSString stringWithFormat:@"on R%u", t->bearer]
                                : [NSString stringWithFormat:@"at (%d, %d)", t->x, t->y],
                      t->strength, (long long) t->seen, t->present ? "" : ", gone", (unsigned long long) t->truth];
   }
   if( [store feltAt] >= 0)
      [s appendFormat:@"  feels hunger %d, cold %d, short of breath %d, tired %d, pain %d, at %lldms\n",
                      [store feels:"hunger"], [store feels:"cold"], [store feels:"stuffy"], [store feels:"tired"],
                      [store feels:"pain"], (long long) [store feltAt]];
   for( i = 0; i < [store findingCount]; i++)
   {
      const BGFinding   *f;

      f = [store findingAt:i];
      [s appendFormat:@"  finding %s about R%u%@, %+d dB, by %s at %lldms\n", f->kind, f->about,
                      f->choice ? [NSString stringWithFormat:@", choosing R%u", f->choice] : @"", f->credence, f->rule,
                      (long long) f->time];
   }
   for( i = 0; i < [store identityCount]; i++)
   {
      const BGIdentity   *h;
      BGEntityID         ta;
      BGEntityID         tb;

      h  = [store identityAt:i];
      ta = [store referent:h->a] ? [store referent:h->a]->truth : 0;
      tb = [store referent:h->b] ? [store referent:h->b]->truth : 0;
      [s appendFormat:@"  identity R%u may be R%u: %+d dB, differing in %s; truly %s%s\n", h->a, h->b, h->credence,
                      h->paths, ! ta || ! tb ? "unknown" : ta == tb ? "the same" : "not",
                      ta && tb && ta != tb && h->credence >= 0 ? ": false merge" : ""];
   }
   [s appendString:[self dumpTestimony:store]];
   for( i = 0; i < [store observationCount]; i++)
   {
      o = [store observationAt:i];
      [s appendFormat:@"  at %lldms, salience %d: R%u %s R%u%@%@%s\n", (long long) o->time, o->salience, o->actor, o->kind,
                      ! strcmp( o->kind, "said") ? o->other : o->subject,
                      ! strcmp( o->kind, "moved") && o->other ? [NSString stringWithFormat:@" to R%u", o->other] : @"",
                      o->content ? [NSString stringWithFormat:@": %s", o->content] : @"",
                      o->unbelieved ? " (not believed)" : ""];
   }
   return( s);
}


/* --- saves --------------------------------------------------------------------------- */

NSArray   *BGSplitTopLevel( NSString *text)
{
   NSMutableArray   *parts;
   const char       *s;
   const char       *p;
   const char       *start;
   int              depth;
   BOOL             quoted;

   parts  = [NSMutableArray array];
   s      = [text UTF8String];
   depth  = 0;
   quoted = NO;
   for( start = p = s; ; p++)
   {
      if( *p == '"' && (p == s || p[ -1] != '\\'))
         quoted = ! quoted;
      if( quoted && *p)
         continue;
      if( *p == '{' || *p == '[' || *p == '(')
         depth++;
      else if( (*p == '}' || *p == ']' || *p == ')') && depth > 0)
         depth--;
      else if( (*p == ',' && ! depth) || ! *p)
      {
         const char   *end;

         while( start < p && *start == ' ')
            start++;
         for( end = p; end > start && end[ -1] == ' '; end--)
            ;
         [parts addObject:[[[NSString alloc] initWithBytes:(void *) start length:(NSUInteger) (end - start)
                                                  encoding:NSUTF8StringEncoding] autorelease]];
         start = p + 1;
      }
      if( ! *p)
         break;
   }
   return( parts);
}


NSArray   *BGWritingEntries( const char *writing, NSString **author)
{
   NSString     *text;
   NSString     *pair;
   NSString     *list;
   NSArray      *pairs;
   NSRange      open;
   NSUInteger   i;

   text = writing ? [NSString stringWithUTF8String:(char *) writing] : nil;
   if( ! [text hasPrefix:@"#Writing & {"] || ! [text hasSuffix:@"}"])
      return( nil);
   open  = [text rangeOfString:@"{"];
   pairs = BGSplitTopLevel( [text substringWithRange:NSMakeRange( open.location + 1,
                                                                   [text length] - open.location - 2)]);
   list  = nil;
   for( i = 0; i < [pairs count]; i++)
   {
      pair = [pairs objectAtIndex:i];
      if( [pair hasPrefix:@"author: "] && author)
         *author = [pair substringFromIndex:8];
      if( [pair hasPrefix:@"entries: ["] && [pair hasSuffix:@"]"])
         list = [pair substringWithRange:NSMakeRange( 10, [pair length] - 11)];
   }
   if( ! [list length])
      return( [NSArray array]);
   return( BGSplitTopLevel( list));
}


NSString   *BGEncodeWord( const char *s)
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


char   *BGDecodeWord( const char *s)
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
   NSUInteger         k;
   int32_t            x;
   int32_t            y;

   lines = [NSMutableArray array];
   for( i = 0; i < [_stores count]; i++)
   {
      store = [_stores objectAtIndex:i];
      [lines addObject:[NSString stringWithFormat:@"store %llu %u %u %llu", (unsigned long long) [store agent],
                                                  [store nextID], [store selfReferent],
                                                  (unsigned long long) [store nextSerial]]];
      for( y = 0; y < 32; y++)
         for( x = 0; x < 32; x++)
            if( [store tileSeenAtX:x y:y] >= 0)
               [lines addObject:[NSString stringWithFormat:@"seen %llu %d %d %lld", (unsigned long long) [store agent],
                                                           x, y, (long long) [store tileSeenAtX:x y:y]]];
      for( j = 0; j < [store count]; j++)
      {
         r = [store referentAt:j];
         [lines addObject:[NSString stringWithFormat:@"ref %llu %u %d %u %d %d %d %d %lld %lld %u %d %d %llu %@ %@ %@ %@",
                                                     (unsigned long long) [store agent], r->id, (int) r->form,
                                                     r->container, r->x, r->y, r->level, r->slot, (long long) r->seen,
                                                     (long long) r->insideSeen, r->toldBy, r->trust, r->present ? 1 : 0,
                                                     (unsigned long long) r->truth,
                                                     BGEncodeWord( r->role), BGEncodeWord( r->kind), BGEncodeWord( r->features),
                                                     BGEncodeWord( r->deeper)]];
      }
      for( j = 0; j < [store observationCount]; j++)
      {
         o = [store observationAt:j];
         [lines addObject:[NSString stringWithFormat:@"obs %llu %lld %s %u %u %u %d %d %llu %@",
                                                     (unsigned long long) [store agent],
                                                     (long long) o->time, o->kind, o->actor, o->subject, o->other,
                                                     o->unbelieved ? 1 : 0, o->salience, (unsigned long long) o->serial,
                                                     BGEncodeWord( o->content)]];
      }
      for( j = 0; j < [store traceCount]; j++)
      {
         const BGTraceSeen   *tr;

         tr = [store traceAt:j];
         [lines addObject:[NSString stringWithFormat:@"tracing %llu %u %d %d %d %d %lld %d %llu %s",
                                                     (unsigned long long) [store agent], tr->bearer, tr->x, tr->y,
                                                     tr->level, tr->strength, (long long) tr->seen, tr->present ? 1 : 0,
                                                     (unsigned long long) tr->truth, tr->kind]];
      }
      if( [store feltAt] >= 0)
         [lines addObject:[NSString stringWithFormat:@"feels %llu %d %lld %d %d %d %d", (unsigned long long) [store agent],
                                                     [store feels:"hunger"], (long long) [store feltAt],
                                                     [store feels:"cold"], [store feels:"stuffy"], [store feels:"tired"],
                                                     [store feels:"pain"]]];
      for( j = 0; j < [store count]; j++)
         for( k = 0; k < BG_HYPOTHESES && [store referentAt:j]->supposed[ k]; k++)
            [lines addObject:[NSString stringWithFormat:@"supposes %llu %u %d %@", (unsigned long long) [store agent],
                                                        [store referentAt:j]->id, [store referentAt:j]->supposedMass[ k],
                                                        BGEncodeWord( [store referentAt:j]->supposed[ k])]];
      for( j = 0; j < [store identityCount]; j++)
      {
         const BGIdentity   *h;

         h = [store identityAt:j];
         [lines addObject:[NSString stringWithFormat:@"identity %llu %u %u %d %lld %@", (unsigned long long) [store agent],
                                                     h->a, h->b, h->credence, (long long) h->time, BGEncodeWord( h->paths)]];
      }
      for( j = 0; j < [store findingCount]; j++)
      {
         const BGFinding   *f;

         f = [store findingAt:j];
         [lines addObject:[NSString stringWithFormat:@"finding %llu %u %d %lld %s %s %u", (unsigned long long) [store agent],
                                                     f->about, f->credence, (long long) f->time, f->kind, f->rule, f->choice]];
      }
      for( j = 0; j < [store testimonyCount]; j++)
      {
         t = [store testimonyAt:j];
         [lines addObject:[NSString stringWithFormat:@"told %llu %u %u %lld %lld %u %u %d %d %d %llu %u",
                                                     (unsigned long long) [store agent], t->thing, t->container,
                                                     (long long) t->when, (long long) t->heard, t->source, t->root,
                                                     (int) t->attribution, t->settled, t->sure,
                                                     (unsigned long long) t->utterance, t->via]];
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
   int                  cold;
   int                  stuffy;
   int                  tired;
   int                  pain;
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
   char                 deeper[ 512];
   char                 *text;
   NSUInteger           i;

   [_stores removeAllObjects];
   _nancestry = 0;
   for( i = 0; i < [lines count]; i++)
   {
      text = (char *) [[lines objectAtIndex:i] UTF8String];
      if( sscanf( text, "store %llu %u %u %llu", &agent, &next, &me, &parent) == 4)
      {
         [[self storeOf:(BGEntityID) agent] setNextID:next self:me];
         [[self storeOf:(BGEntityID) agent] setNextSerial:parent];
      }
      else if( sscanf( text, "seen %llu %d %d %lld", &agent, &x, &y, &seen) == 4)
         [[self storeOf:(BGEntityID) agent] setTileSeen:seen x:x y:y];
      else if( sscanf( text, "obs %llu %lld %15s %u %u %u %d %d %llu %4095s", &agent, &seen, role, &id, &container,
                       &told, &present, &trust, &origin, features) == 10)
      {
         memset( &o, 0, sizeof( o));
         o.time       = seen;
         o.kind       = [_world intern:role];
         o.actor      = id;
         o.subject    = container;
         o.other      = told;
         o.unbelieved = present != 0;
         o.salience   = trust;
         o.serial     = origin;
         o.content    = BGDecodeWord( features);
         if( ! *o.content)
         {
            free( o.content);
            o.content = NULL;
         }
         [[self storeOf:(BGEntityID) agent] addObservation:o restored:YES];
         free( o.content);
      }
      else if( sscanf( text, "told %llu %u %u %lld %lld %u %u %d %d %d %llu %u", &agent, &id, &container, &seen, &inside,
                       &told, &me, &form, &present, &trust, &truth, &next) == 12)
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
         t.sure        = trust;
         t.utterance   = truth;
         t.via         = next;
         [[self storeOf:(BGEntityID) agent] appendTestimony:t];
      }
      else if( sscanf( text, "tracing %llu %u %d %d %d %d %lld %d %llu %63s", &agent, &id, &x, &y, &level, &trust,
                       &seen, &present, &truth, role) == 10)
      {
         BGTraceSeen   tr;

         memset( &tr, 0, sizeof( tr));
         tr.bearer   = id;
         tr.x        = x;
         tr.y        = y;
         tr.level    = level;
         tr.strength = trust;
         tr.seen     = seen;
         tr.present  = present != 0;
         tr.truth    = (BGEntityID) truth;
         tr.kind     = [_world intern:role];
         [[self storeOf:(BGEntityID) agent] noteTrace:tr];
      }
      else if( sscanf( text, "supposes %llu %u %d %511s", &agent, &id, &trust, deeper) == 4)
      {
         char   *overrides;

         overrides = BGDecodeWord( deeper);
         [[self storeOf:(BGEntityID) agent] suppose:[NSString stringWithUTF8String:overrides] about:id mass:trust];
         free( overrides);
      }
      else if( sscanf( text, "identity %llu %u %u %d %lld %511s", &agent, &id, &container, &trust, &seen, deeper) == 6)
      {
         BGIdentity   h;
         char         *paths;

         memset( &h, 0, sizeof( h));
         h.a        = id;
         h.b        = container;
         h.credence = trust;
         h.time     = seen;
         paths      = BGDecodeWord( deeper);
         strncpy( h.paths, paths, sizeof( h.paths) - 1);
         free( paths);
         [[self storeOf:(BGEntityID) agent] addIdentity:h];
      }
      else if( sscanf( text, "feels %llu %d %lld %d %d %d %d", &agent, &trust, &seen, &cold, &stuffy, &tired, &pain) == 7)
      {
         [[self storeOf:(BGEntityID) agent] feelPain:pain];
         [[self storeOf:(BGEntityID) agent] feelTired:tired];
         [[self storeOf:(BGEntityID) agent] feelHunger:trust at:seen];
         [[self storeOf:(BGEntityID) agent] feelCold:cold];
         [[self storeOf:(BGEntityID) agent] feelStuffy:stuffy];
      }
      else if( sscanf( text, "finding %llu %u %d %lld %63s %511s %u", &agent, &id, &trust, &seen, role, kind, &next) == 7)
      {
         BGFinding   f;

         memset( &f, 0, sizeof( f));
         f.about    = id;
         f.credence = trust;
         f.time     = seen;
         f.kind     = [_world intern:role];
         f.rule     = [_world intern:kind];
         f.choice   = next;
         [[self storeOf:(BGEntityID) agent] addFinding:f];
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
      else if( sscanf( text, "ref %llu %u %d %u %d %d %d %d %lld %lld %u %d %d %llu %63s %511s %4095s %511s", &agent,
                       &id, &form, &container, &x, &y, &level, &slot, &seen, &inside, &told, &trust, &present, &truth,
                       role, kind, features, deeper) == 18)
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
         text         = BGDecodeWord( role);
         strncpy( r->role, text, sizeof( r->role) - 1);
         free( text);
         r->kind      = BGDecodeWord( kind);
         r->features  = BGDecodeWord( features);
         r->deeper    = BGDecodeWord( deeper);
         if( ! *r->deeper)
         {
            free( r->deeper);
            r->deeper = NULL;
         }
         [store setNextID:(uint32_t) max64( next, [store nextID]) self:[store selfReferent]];
      }
   }
   _eventsSeen = [_world eventCount];
}

@end

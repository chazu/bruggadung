#import "BGAgency.h"

#import "BGActions.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>


#define BG_MAX_VARIANTS   16
#define BG_MAX_METHODS    32
#define BG_MAX_TRIES      4096     /* the matches one condition may take */
#define BG_REPLY_WAIT     5000     /* ms an agent waits for an answer */


@implementation BGMotivation

- (id) init
{
   if( (self = [super init]))
      log = [NSMutableArray new];
   return( self);
}


- (void) dealloc
{
   [log release];
   [super dealloc];
}

@end


/* --- reading content ------------------------------------------------------------- */

/* The text at `path` (the node itself for NULL), without its quotes. NO when
 * there is none, or it is left open. */
static BOOL   text_at( TriContent *tri, const TriNode *node, const char *path, char *buf, size_t len)
{
   const TriNode   *v;
   char            tmp[ 256];
   size_t          n;

   v = node && path ? tri_at( tri, node, path) : node;
   if( ! v)
      return( NO);
   tri_print( tri, v, tmp, sizeof( tmp));
   n = strlen( tmp);
   if( n < 2 || tmp[ 0] != '"' || tmp[ n - 1] != '"')
      return( NO);
   snprintf( buf, len, "%.*s", (int) (n - 2), tmp + 1);
   return( YES);
}


/* The texts of the list at `path`, in order. */
static NSUInteger   texts_at( TriContent *tri, const TriNode *node, const char *path, char (*out)[ 32], NSUInteger max)
{
   const TriNode   *list;
   NSUInteger      n;

   n = 0;
   for( list = node ? tri_at( tri, node, path) : NULL; list && n < max; list = tri_at( tri, list, "rest"))
   {
      if( ! tri_at( tri, list, "first"))
         break;
      if( text_at( tri, tri_at( tri, list, "first"), NULL, out[ n], 32))
         n++;
   }
   return( n);
}


/* An int at `path`, or `otherwise` when it is left open. */
static int64_t   int_at( TriContent *tri, const TriNode *node, const char *path, int64_t otherwise)
{
   const TriNode   *v;
   int64_t         lo;
   int64_t         hi;

   v = node ? tri_at( tri, node, path) : NULL;
   if( ! v || ! tri_node_interval( v, &lo, &hi) || lo != hi)
      return( otherwise);
   return( lo);
}


/* An instance's patterns, one per variant. */
static NSUInteger   variants_of( TriContent *tri, const char *instance, const TriNode **out, NSUInteger max)
{
   size_t   n;
   size_t   i;

   n = tri_pattern_variant_count( tri, instance);
   if( ! n)
   {
      out[ 0] = tri_pattern( tri, instance);
      return( out[ 0] ? 1 : 0);
   }
   for( i = 0; i < n && i < max; i++)
      out[ i] = tri_pattern_variant( tri, instance, i);
   return( i);
}


static uint32_t   bound( const BGSlotBinding *b, int n, const char *slot)
{
   int   i;

   for( i = 0; i < n; i++)
      if( ! strcmp( b[ i].slot, slot))
         return( b[ i].referent);
   return( 0);
}


/* --- what the agent believes ------------------------------------------------------- */

static BOOL   in_reach( const BGReferent *me, const BGReferent *r)
{
   return( r && me->level == r->level && abs( me->x - r->x) <= 1 && abs( me->y - r->y) <= 1);
}


static int   distance( const BGReferent *me, const BGReferent *r)
{
   int   dx;
   int   dy;

   dx = abs( me->x - r->x);
   dy = abs( me->y - r->y);
   return( dx > dy ? dx : dy);
}


/* A condition (a goal's `done`, a method's `pre`), ready to bind. */
typedef struct
{
   const TriNode      *match[ BG_MAX_VARIANTS];    /* per variant */
   NSUInteger         nvariants;
   const char         *frame;                      /* the frame's type: "#Wedging" */
   char               find[ BG_MAX_SLOTS][ 32];
   NSUInteger         nfind;
   char               order[ 4][ 32];
   NSUInteger         norder;
   char               search[ 32];                 /* the slot to search, or "" */
   int64_t            since;                       /* searched means its inside was seen since */
   BGKnowledgeStore   *store;
   const BGReferent   *me;
   NSUInteger         tries;
} BGCondition;


static int   compare_candidates( BGCondition *c, const BGReferent *a, const BGReferent *b)
{
   NSUInteger   k;
   int          da;
   int          db;

   for( k = 0; k < c->norder; k++)
      if( ! strcmp( c->order[ k], "near"))
      {
         da = distance( c->me, a);
         db = distance( c->me, b);
         if( da != db)
            return( da < db ? -1 : 1);
      }
      else if( ! strcmp( c->order[ k], "recent") && a->seen != b->seen)
         return( a->seen > b->seen ? -1 : 1);
   return( a->id < b->id ? -1 : a->id > b->id);
}


static const char   *goal_title( TriContent *tri, const char *goal, char *buf, size_t len)
{
   if( ! text_at( tri, tri_pattern( tri, goal), "title", buf, len))
      snprintf( buf, len, "%s", goal);
   return( buf);
}


@implementation BGAgency

- (id) initWithWorld:(BGWorld *) world
           committer:(BGCommitter *) committer
           knowledge:(BGKnowledge *) knowledge
{
   if( ! (self = [super init]))
      return( nil);
   _world     = [world retain];
   _committer = committer;
   _knowledge = [knowledge retain];
   _minds     = [NSMutableArray new];
   return( self);
}


- (void) dealloc
{
   [_world release];
   [_knowledge release];
   [_minds release];
   [super dealloc];
}


- (NSString *) name
{
   return( @"agency");
}


- (BGMotivation *) mindOf:(BGEntityID) agent
{
   BGMotivation   *m;
   NSUInteger     i;

   for( i = 0; i < [_minds count]; i++)
   {
      m = [_minds objectAtIndex:i];
      if( m->agent == agent)
         return( m);
      if( m->agent > agent)
         break;
   }
   m        = [[BGMotivation new] autorelease];
   m->agent = agent;
   [_minds insertObject:m atIndex:i];
   return( m);
}


- (NSArray *) logOf:(BGEntityID) agent
{
   return( [self mindOf:agent]->log);
}


- (void) adopt:(const char *) goal
          mind:(BGMotivation *) m
        params:(const BGSlotBinding *) params
         count:(int) n
{
   BGIntention   *intention;

   intention            = &m->intentions[ m->nintentions++];
   memset( intention, 0, sizeof( *intention));
   intention->goal      = [_world intern:goal];
   intention->adopted   = [_world time].ms;
   intention->pending   = -1;
   intention->following = -1;
   for( ; intention->nparams < n && intention->nparams < BG_MAX_SLOTS; intention->nparams++)
      intention->params[ intention->nparams] = params[ intention->nparams];
}


- (void) control:(BGEntityID) agent
{
   BGMotivation   *m;

   m        = [self mindOf:agent];
   m->heard = [[_knowledge storeOf:agent] observationCount];
}


- (BOOL) commit:(BGEntityID) agent
         toGoal:(const char *) goal
{
   BGMotivation   *m;

   if( ! tri_at( [_world tri], tri_pattern( [_world tri], goal), "done"))
      return( NO);
   m              = [self mindOf:agent];
   m->nintentions = 0;
   m->waiting     = NO;
   [self adopt:goal mind:m params:NULL count:0];
   return( YES);
}


/* --- conditions ---------------------------------------------------------------------- */

/* `path` is "done" for a goal, "pre" for a method. */
- (BOOL) load:(BGCondition *) c
     instance:(const char *) instance
         path:(const char *) path
        store:(BGKnowledgeStore *) store
{
   const TriNode   *variants[ BG_MAX_VARIANTS];
   TriContent      *tri;
   NSUInteger      v;
   char            sub[ 32];

   tri = [_world tri];
   memset( c, 0, sizeof( *c));
   c->store = store;
   c->me    = [store referent:[store selfReferent]];
   for( v = 0; v < variants_of( tri, instance, variants, BG_MAX_VARIANTS); v++)
   {
      snprintf( sub, sizeof( sub), "%s.match", path);
      if( (c->match[ c->nvariants] = tri_at( tri, variants[ v], sub)))
         c->nvariants++;
   }
   if( ! c->nvariants || ! c->me)
      return( NO);
   c->frame  = tri_type_name( tri, tri_node_type( c->match[ 0]));
   snprintf( sub, sizeof( sub), "%s.find", path);
   c->nfind  = texts_at( tri, variants[ 0], sub, c->find, BG_MAX_SLOTS);
   c->norder = texts_at( tri, variants[ 0], "order", c->order, 4);
   if( ! text_at( tri, variants[ 0], "search", c->search, sizeof( c->search)))
      c->search[ 0] = 0;
   return( YES);
}


/* The match of the condition's frame, with `me` and the slots of `find`
 * bound so far: entailed if any variant entails it, incompatible if all rule
 * it out. */
- (TriMatch) match:(BGCondition *) c
          bindings:(const BGSlotBinding *) b
             count:(int) n
{
   NSMutableString   *expr;
   const TriNode     *description;
   TriMatchResult    result;
   TriContent        *tri;
   TriArena          *arena;
   TriMatch          best;
   TriMatch          match;
   NSUInteger        k;
   NSUInteger        v;
   uint32_t          r;

   tri  = [_world tri];
   expr = [NSMutableString stringWithFormat:@"%s & { me: %@", c->frame, [c->store describeReferent:c->me->id]];
   for( k = 0; k < c->nfind; k++)
      if( (r = bound( b, n, c->find[ k])))
         [expr appendFormat:@", %s: %@", c->find[ k], [c->store describeReferent:r]];
   [expr appendString:@" }"];
   arena       = tri_arena_new();
   description = tri_value( tri, [expr UTF8String], arena, NULL, 0);
   best        = TRI_INCOMPATIBLE;
   for( v = 0; description && v < c->nvariants && best != TRI_ENTAILED; v++)
   {
      match = tri_match( tri, c->match[ v], description, &result);
      if( match != TRI_INCOMPATIBLE)
         best = match;
   }
   tri_arena_free( arena);
   return( best);
}


/* A believed kind more general than the slot's isn't one (as for an
 * operation's roles). */
- (BOOL) kind:(const char *) kind
     fitsSlot:(const char *) slot
           of:(BGCondition *) c
{
   const TriNode   *k;
   const TriNode   *filler;
   TriContent      *tri;
   TriArena        *arena;
   NSUInteger      v;
   BOOL            fits;

   tri   = [_world tri];
   arena = tri_arena_new();
   k     = kind ? tri_value( tri, kind, arena, NULL, 0) : NULL;
   fits  = NO;
   for( v = 0; k && v < c->nvariants && ! fits; v++)
   {
      filler = tri_at( tri, c->match[ v], slot);
      fits   = filler && tri_subtype( tri, tri_node_type( k), tri_node_type( filler));
   }
   tri_arena_free( arena);
   return( fits);
}


/* Binds the slots of `find` from slot `k` on, depth first, each slot's
 * candidates in the condition's order; a partial binding the match rules out
 * is not followed. YES with the bindings when the condition holds. */
- (BOOL) bind:(BGCondition *) c
         slot:(NSUInteger) k
     bindings:(BGSlotBinding *) b
        count:(int *) n
{
   const BGReferent   *candidates[ 64];
   const BGReferent   *r;
   const BGReferent   *t;
   NSUInteger         ncandidates;
   NSUInteger         i;
   NSUInteger         j;
   const char         *slot;
   int                before;

   if( k == c->nfind)
      return( [self match:c bindings:b count:*n] == TRI_ENTAILED);
   slot = c->find[ k];
   if( bound( b, *n, slot))
      return( [self bind:c slot:k + 1 bindings:b count:n]);
   if( *n >= BG_MAX_SLOTS)
      return( NO);

   ncandidates = 0;
   for( i = 0; i < [c->store count] && ncandidates < 64; i++)
   {
      r = [c->store referentAt:i];
      if( ! r->present || r->id == c->me->id)
         continue;
      for( j = 0; j < (NSUInteger) *n && b[ j].referent != r->id; j++)
         ;
      if( j < (NSUInteger) *n)
         continue;      /* one referent fills one slot */
      if( c->search[ 0] && ! strcmp( slot, c->search) &&
          (r->insideSeen >= c->since || [c->store lastSaidTo:r->id] >= c->since))
         continue;      /* searched already: looked into, or asked */
      if( ! [self kind:r->kind fitsSlot:slot of:c])
         continue;
      /* in the condition's order */
      for( j = ncandidates; j > 0 && compare_candidates( c, r, candidates[ j - 1]) < 0; j--)
         candidates[ j] = candidates[ j - 1];
      candidates[ j] = r;
      ncandidates++;
   }

   for( i = 0; i < ncandidates; i++)
   {
      if( ++c->tries > BG_MAX_TRIES)
         return( NO);
      t               = candidates[ i];
      before          = *n;
      b[ *n].slot     = [_world intern:slot];
      b[ *n].referent = t->id;
      (*n)++;
      if( [self match:c bindings:b count:*n] != TRI_INCOMPATIBLE &&
          [self bind:c slot:k + 1 bindings:b count:n])
         return( YES);
      *n = before;
   }
   return( NO);
}


/* Whether the instance's condition holds in the agent's view. `b` starts as
 * the slots already bound, and gains those it binds. */
- (BOOL) holds:(const char *) instance
          path:(const char *) path
         since:(int64_t) since
      bindings:(BGSlotBinding *) b
         count:(int *) n
         store:(BGKnowledgeStore *) store
{
   BGCondition   c;
   int           start;

   if( ! [self load:&c instance:instance path:path store:store])
      return( NO);
   c.since = since;
   start   = *n;
   if( [self bind:&c slot:0 bindings:b count:n])
      return( YES);
   *n = start;
   return( NO);
}


/* A goal's methods: by rank, then by name. */
- (NSUInteger) methodsFor:(const char *) goal
                     into:(const char **) out
                      max:(NSUInteger) max
{
   TriContent   *tri;
   TriIndex     *family;
   const char   *name;
   const char   *t;
   NSUInteger   n;
   NSUInteger   j;
   size_t       i;
   char         buf[ 64];

   tri    = [_world tri];
   family = tri_family_index( tri, "methods");
   n      = 0;
   for( i = 0; family && i < tri_index_count( family) && n < max; i++)
   {
      name = tri_index_tag( family, i);
      if( ! text_at( tri, tri_pattern( tri, name), "goal", buf, sizeof( buf)) || strcmp( buf, goal))
         continue;
      for( j = 0; j < n && strcmp( out[ j], name); j++)
         ;
      if( j < n)
         continue;      /* an entry per variant */
      name = [_world intern:name];
      for( j = n; j > 0; j--)
      {
         t = out[ j - 1];
         if( int_at( tri, tri_pattern( tri, t), "rank", 0) < int_at( tri, tri_pattern( tri, name), "rank", 0) ||
             (int_at( tri, tri_pattern( tri, t), "rank", 0) == int_at( tri, tri_pattern( tri, name), "rank", 0) &&
              strcmp( t, name) < 0))
            break;
         out[ j] = t;
      }
      out[ j] = name;
      n++;
   }
   return( n);
}


/* --- acting ------------------------------------------------------------------------- */

/* Not variadic: in mulle-objc a method's variadic arguments don't arrive
 * through va_start; the callers format. */
- (void) note:(BGMotivation *) m
         line:(NSString *) line
{
   char   title[ 64];

   [m->log addObject:[NSString stringWithFormat:@"d%llu t=%lldms [%s] %@", (unsigned long long) m->decisions,
                                                (long long) [_world time].ms,
                                                m->nintentions ? goal_title( [_world tri], m->intentions[ m->nintentions - 1].goal,
                                                                             title, sizeof( title)) : "-",
                                                line]];
}


/* The type of what is said: "#IsIn". */
- (const char *) kindOfContent:(const char *) content
{
   const TriNode   *node;
   const char      *kind;
   TriArena        *arena;

   arena = tri_arena_new();
   node  = content ? tri_value( [_world tri], content, arena, NULL, 0) : NULL;
   kind  = node ? tri_type_name( [_world tri], tri_node_type( node)) : "?";
   tri_arena_free( arena);
   return( kind);
}


/* YES if it was attempted. `content` is what is said, or NULL. */
- (BOOL) act:(BGMotivation *) m
         why:(const char *) why
       store:(BGKnowledgeStore *) store
   operation:(const char *) operation
      object:(uint32_t) object
      target:(uint32_t) target
       units:(int64_t) units
     content:(const char *) content
{
   NSString   *error;
   BGAction   action;

   error          = nil;
   action         = BGActionMake( [_world intern:operation], [store selfReferent], object, target);
   action.content = content ? [_world intern:content] : NULL;
   if( ! BGPerformBelieved( _world, _committer, store, action, units, &error))
   {
      [self note:m line:[NSString stringWithFormat:@"%s: could not %s: %@", why, operation, error]];
      return( NO);
   }
   [self note:m line:[NSString stringWithFormat:@"%s: %s R%u%@%@", why, operation, object,
                       target ? [NSString stringWithFormat:@" into R%u", target] : @"",
                       content ? [NSString stringWithFormat:@": %s", [self kindOfContent:content]] : @""]];
   return( YES);
}


/* One step toward a believed place: the longer way first. */
- (void) walk:(BGMotivation *) m
          why:(const char *) why
           me:(const BGReferent *) me
       toward:(const BGReferent *) target
{
   const char   *op;
   NSString     *error;
   int          dx;
   int          dy;

   dx = target->x - me->x;
   dy = target->y - me->y;
   if( abs( dx) >= abs( dy))
      op = dx > 0 ? "walk_east" : "walk_west";
   else
      op = dy > 0 ? "walk_south" : "walk_north";
   error = nil;
   if( ! BGPerform( _world, _committer, BGActionMake( [_world intern:op], m->agent, BGNoEntity, BGNoEntity), 0, &error))
      [self note:m line:[NSString stringWithFormat:@"%s: could not %s: %@", why, op, error]];
   else
      [self note:m line:[NSString stringWithFormat:@"%s: %s, toward R%u at (%d, %d)", why, op, target->id, target->x, target->y]];
}


- (BOOL) busy:(BGEntityID) agent
{
   const BGActivity   *record;
   BGStore            *store;
   NSUInteger         i;
   TriType            running;

   store   = [_world storeForKind:[_world kindNamed:"Activity"]];
   running = tri_type_named( [_world tri], "\"running\"");
   for( i = 0; i < [store count]; i++)
   {
      record = [store recordAtIndex:i];
      if( record->actorRef == agent && record->status == (uint32_t) running)
         return( YES);
   }
   return( NO);
}


/* --- deciding ----------------------------------------------------------------------- */

/* The method's failure: the goal tries its next. */
- (void) fail:(BGMotivation *) m
       method:(int) index
          why:(NSString *) why
{
   BGIntention   *top;

   top          = &m->intentions[ m->nintentions - 1];
   top->failed |= 1u << index;
   top->pending = -1;
   [self note:m line:why];
}


/* Follows a method whose `pre` holds, with its bindings: passes over the
 * subgoals already done, adopts the first that isn't, or performs the
 * operation. YES when it acted. */
- (BOOL) follow:(BGMotivation *) m
         method:(const char *) method
          index:(int) index
       bindings:(BGSlotBinding *) b
          count:(int) n
          store:(BGKnowledgeStore *) store
{
   const TriNode      *pattern;
   const TriNode      *steps;
   const TriNode      *step;
   const BGReferent   *me;
   const BGReferent   *r;
   TriContent         *tri;
   TriType            achieve;
   uint32_t           roles[ 2];
   char               title[ 64];
   char               goal[ 64];
   char               op[ 64];
   char               slot[ 32];
   const char         *names[ 2] = { "object", "target" };
   const TriNode      *says;
   const char         *content;
   TriType            utterance;
   char               text[ 2048];
   int                k;

   tri       = [_world tri];
   utterance = tri_type_named( tri, "#Utterance");
   pattern   = tri_pattern( tri, method);
   me      = [store referent:[store selfReferent]];
   achieve = tri_type_named( tri, "#Achieve");
   if( ! text_at( tri, pattern, "title", title, sizeof( title)))
      snprintf( title, sizeof( title), "%s", method);

   for( steps = tri_at( tri, pattern, "steps"); steps && (step = tri_at( tri, steps, "first")); steps = tri_at( tri, steps, "rest"))
   {
      if( tri_node_type( step) == achieve)
      {
         if( ! text_at( tri, step, "subgoal", goal, sizeof( goal)) || ! tri_at( tri, tri_pattern( tri, goal), "done"))
         {
            [self fail:m method:index why:[NSString stringWithFormat:@"%s: there is no goal %s", title, goal]];
            return( NO);
         }
         if( [self holds:goal path:"done" since:0 bindings:b count:&n store:store])
            continue;
         if( m->nintentions == BG_MAX_INTENTIONS)
         {
            [self fail:m method:index why:[NSString stringWithFormat:@"%s: too many goals deep", title]];
            return( NO);
         }
         [self note:m line:[NSString stringWithFormat:@"%s: %s first", title, goal_title( tri, goal, op, sizeof( op))]];
         m->intentions[ m->nintentions - 1].pending = index;
         [self adopt:goal mind:m params:b count:n];
         return( NO);
      }

      /* the operation, within reach of what it names */
      if( ! text_at( tri, step, "op", op, sizeof( op)))
         continue;
      for( k = 0; k < 2; k++)
      {
         roles[ k] = 0;
         if( ! text_at( tri, step, names[ k], slot, sizeof( slot)))
            continue;
         if( ! (roles[ k] = bound( b, n, slot)))
         {
            [self fail:m method:index why:[NSString stringWithFormat:@"%s: %s names %s, which nothing fills", title, op, slot]];
            return( NO);
         }
      }
      for( k = 0; k < 2; k++)
         if( roles[ k] && ! in_reach( me, r = [store referent:roles[ k]]) && r)
         {
            [self walk:m why:title me:me toward:r];
            return( YES);
         }
      /* what it says, if anything: after a question, it waits for the answer */
      says    = tri_at( tri, step, "says");
      content = NULL;
      if( says && tri_node_type( says) != utterance)
      {
         tri_print( tri, says, text, sizeof( text));
         content = text;
      }
      if( [self act:m why:title store:store operation:op object:roles[ 0] target:roles[ 1]
              units:int_at( tri, step, "units", 0) content:content] &&
          content && tri_subtype( tri, tri_node_type( says), tri_type_named( tri, "#Question")))
      {
         m->awaiting   = roles[ 0];
         m->awaitSince = [_world time].ms;
         m->awaitUntil = m->awaitSince + BG_REPLY_WAIT;
      }
      return( YES);
   }
   [self fail:m method:index why:[NSString stringWithFormat:@"%s: every step is done, and the goal is not", title]];
   return( NO);
}


/* The titles of the methods before `count` that haven't failed, so their
 * precondition doesn't hold: "fetch nails", or nil if none. */
- (NSString *) passedOver:(const char **) methods
                    count:(NSUInteger) count
                   failed:(uint32_t) failed
{
   NSMutableArray   *titles;
   NSUInteger       i;
   char             title[ 64];

   titles = [NSMutableArray array];
   for( i = 0; i < count; i++)
      if( ! (failed & (1u << i)))
      {
         if( ! text_at( [_world tri], tri_pattern( [_world tri], methods[ i]), "title", title, sizeof( title)))
            snprintf( title, sizeof( title), "%s", methods[ i]);
         [titles addObject:[NSString stringWithUTF8String:title]];
      }
   return( [titles count] ? [titles componentsJoinedByString:@", "] : nil);
}


/* An answer to a #WhereIs, from what the agent knows: where it believes the
 * thing like `what` it saw last is, inside something on the ground, and how
 * it knows: it saw it, or heard it, from whoever its strongest testimony
 * says saw it, or from no one it can name; or that it doesn't know. A
 * #WhoToldYou asks the same of the container like `within`: the answer is
 * the claim again, with its source. */
- (NSString *) answerTo:(const TriNode *) question
                  store:(BGKnowledgeStore *) store
{
   const TriNode      *what;
   const TriNode      *within;
   const TriNode      *kind;
   const TriNode      *description;
   const BGReferent   *r;
   const BGReferent   *c;
   const BGReferent   *best;
   const BGTestimony  *t;
   TriMatchResult     result;
   TriContent         *tri;
   TriArena           *arena;
   NSString           *attribution;
   NSString           *from;
   NSUInteger         i;
   char               printed[ 2048];

   tri    = [_world tri];
   what   = tri_at( tri, question, "what");
   within = tri_subtype( tri, tri_node_type( question), tri_type_named( tri, "#Placing"))
               ? tri_at( tri, question, "within") : NULL;
   arena  = tri_arena_new();
   best   = NULL;
   for( i = 0; what && i < [store count]; i++)
   {
      r = [store referentAt:i];
      if( ! r->present || r->form != BGLocationIn || r->id == [store selfReferent] || ! r->kind)
         continue;
      c = [store referent:r->container];
      if( ! c || c->form != BGLocationOnTile)
         continue;
      kind        = tri_value( tri, r->kind, arena, NULL, 0);
      description = tri_value( tri, [[store describeReferent:r->id] UTF8String], arena, NULL, 0);
      if( ! kind || ! tri_subtype( tri, tri_node_type( kind), tri_node_type( what)) ||
          ! description || tri_match( tri, what, description, &result) == TRI_INCOMPATIBLE)
         continue;
      if( within)
      {
         description = tri_value( tri, [[store describeReferent:c->id] UTF8String], arena, NULL, 0);
         if( ! description || tri_match( tri, within, description, &result) == TRI_INCOMPATIBLE)
            continue;
      }
      if( ! best || r->seen > best->seen)
         best = r;
   }
   tri_arena_free( arena);
   if( best)
   {
      c           = [store referent:best->container];
      attribution = [NSString stringWithFormat:@"#Saw & { sure: %d }", [store strengthOf:best->id]];
      if( best->toldBy)
      {
         t           = [store strongestThat:best->id isIn:c->id];
         from        = t && t->root ? [store describeLooks:t->root] : nil;
         attribution = from ? [NSString stringWithFormat:@"#Heard & { from: %@ }", from] : @"#Heard";
      }
      return( [NSString stringWithFormat:@"#IsIn & { what: %s%@, within: %s & { place: #OnTile & { x: %d, y: %d, level: %d }%@ }, "
                                         @"when: %lldms, attribution: %@ }",
                                         best->kind,
                                         [[store recall:best] length]
                                            ? [NSString stringWithFormat:@" & { %@ }", [store recall:best]] : @"",
                                         c->kind, c->x, c->y, c->level,
                                         [[store recall:c] length] ? [NSString stringWithFormat:@", %@", [store recall:c]] : @"",
                                         (long long) best->seen, attribution]);
   }
   tri_print( tri, what, printed, sizeof( printed));
   return( [NSString stringWithFormat:@"#DontKnow & { what: %s }", printed]);
}


/* Answering when asked (AGENCY.md §11), for now a reflex: every question
 * put to the agent since it last considered what it heard is answered. */
- (void) answerQuestions:(BGMotivation *) m
                   store:(BGKnowledgeStore *) store
{
   const BGObservation   *o;
   const TriNode         *question;
   TriContent            *tri;
   TriArena              *arena;
   NSString              *answer;
   uint32_t              me;
   uint32_t              asker;

   tri = [_world tri];
   me  = [store selfReferent];
   for( ; m->heard < [store observationCount]; m->heard++)
   {
      o = [store observationAt:m->heard];
      if( strcmp( o->kind, "said") || o->other != me || ! o->actor || o->actor == me || ! o->content)
         continue;
      asker    = o->actor;
      arena    = tri_arena_new();
      question = tri_value( tri, o->content, arena, NULL, 0);
      answer   = nil;
      if( question && (tri_subtype( tri, tri_node_type( question), tri_type_named( tri, "#WhereIs")) ||
                       tri_subtype( tri, tri_node_type( question), tri_type_named( tri, "#WhoToldYou"))))
         answer = [self answerTo:question store:store];
      tri_arena_free( arena);
      if( answer)
         [self act:m why:"answering" store:store operation:"say" object:asker target:0 units:0
           content:[answer UTF8String]];
   }
}


/* YES while the agent waits for an answer: none yet from the one it asked,
 * and the while not over. */
- (BOOL) awaits:(BGMotivation *) m
          store:(BGKnowledgeStore *) store
{
   const BGObservation   *o;
   NSUInteger            i;

   if( ! m->awaiting)
      return( NO);
   for( i = [store observationCount]; i > 0; i--)
   {
      o = [store observationAt:i - 1];
      if( o->time < m->awaitSince)
         break;
      if( ! strcmp( o->kind, "said") && o->actor == m->awaiting && o->other == [store selfReferent])
      {
         [self note:m line:[NSString stringWithFormat:@"R%u answered: %s", m->awaiting, [self kindOfContent:o->content]]];
         m->awaiting = 0;
         return( NO);
      }
   }
   if( [_world time].ms < m->awaitUntil)
      return( YES);
   [self note:m line:[NSString stringWithFormat:@"R%u did not answer", m->awaiting]];
   m->awaiting = 0;
   return( NO);
}


/* One decision, for the current intention. YES when it acted or settled into
 * waiting; NO when it only changed its intentions, so it decides again. */
- (BOOL) decide:(BGMotivation *) m
{
   BGKnowledgeStore   *store;
   const BGReferent   *me;
   BGIntention        *top;
   BGSlotBinding      b[ BG_MAX_SLOTS];
   const char         *methods[ BG_MAX_METHODS];
   NSUInteger         nmethods;
   NSUInteger         i;
   char               title[ 64];
   char               method[ 64];
   NSString           *passed;
   int                n;

   store = [_knowledge storeOf:m->agent];
   me    = [store referent:[store selfReferent]];
   if( ! me)
      return( YES);
   [self answerQuestions:m store:store];
   if( [self awaits:m store:store] || ! m->nintentions || [self busy:m->agent])
      return( YES);     /* waiting for an answer, mid-activity, or nothing to do: no cost */
   if( m->waiting && ! [[store news] count])
      return( YES);
   m->waiting = NO;
   m->decisions++;
   top = &m->intentions[ m->nintentions - 1];

   n = top->nparams;
   memcpy( b, top->params, sizeof( BGSlotBinding) * n);
   if( [self holds:top->goal path:"done" since:0 bindings:b count:&n store:store])
   {
      [self note:m line:@"done"];
      if( --m->nintentions)
      {
         m->intentions[ m->nintentions - 1].pending = -1;
         [self note:m line:[NSString stringWithFormat:@"back to it: %s is done",
                                                       goal_title( [_world tri], top->goal, title, sizeof( title))]];
         return( NO);
      }
      return( YES);
   }

   /* the first method, by rank, that hasn't failed and whose precondition holds */
   nmethods = [self methodsFor:top->goal into:methods max:BG_MAX_METHODS];
   for( i = 0; i < nmethods; i++)
   {
      if( top->failed & (1u << i))
         continue;
      n = top->nparams;
      memcpy( b, top->params, sizeof( BGSlotBinding) * n);
      if( [self holds:methods[ i] path:"pre" since:top->adopted bindings:b count:&n store:store])
      {
         if( top->following != (int) i && (passed = [self passedOver:methods count:i failed:top->failed]))
            [self note:m line:[NSString stringWithFormat:@"%@ no longer holds", passed]];
         top->following = (int) i;
         return( [self follow:m method:methods[ i] index:(int) i bindings:b count:n store:store]);
      }
   }

   /* no way left: impossible for now, and the method that needed it has failed */
   [self note:m line:@"nothing I know of will do: impossible for now"];
   goal_title( [_world tri], top->goal, title, sizeof( title));
   if( --m->nintentions)
   {
      top = &m->intentions[ m->nintentions - 1];
      if( top->pending >= 0)
      {
         [self methodsFor:top->goal into:methods max:BG_MAX_METHODS];
         if( ! text_at( [_world tri], tri_pattern( [_world tri], methods[ top->pending]), "title", method, sizeof( method)))
            snprintf( method, sizeof( method), "%s", methods[ top->pending]);
         [self fail:m method:top->pending
                why:[NSString stringWithFormat:@"%s has failed: it needed %s", method, title]];
      }
      return( NO);
   }
   m->waiting = YES;
   return( YES);
}


- (void) decideBoundary:(uint64_t) boundary
{
   NSUInteger   i;
   int          k;

   /* in stable ID order; each reads only its own stores and committed state */
   for( i = 0; i < [_minds count]; i++)
      for( k = 0; k < 2 * BG_MAX_INTENTIONS && ! [self decide:[_minds objectAtIndex:i]]; k++)
         ;
}


- (BGTime) nextDecisionTime
{
   BGMotivation   *m;
   BGTime         t;
   NSUInteger     i;

   t = BGTimeNever;
   for( i = 0; i < [_minds count]; i++)
   {
      m = [_minds objectAtIndex:i];
      if( m->awaiting && m->awaitUntil < t.ms)
         t = BGTimeMake( m->awaitUntil);
   }
   return( t);
}


/* --- saves ------------------------------------------------------------------------- */

- (void) checkInAll
{
}


- (NSArray *) savedState
{
   NSMutableArray    *lines;
   NSMutableString   *line;
   BGMotivation      *m;
   BGIntention       *t;
   NSUInteger        i;
   int               k;
   int               p;

   lines = [NSMutableArray array];
   for( i = 0; i < [_minds count]; i++)
   {
      m    = [_minds objectAtIndex:i];
      line = [NSMutableString stringWithFormat:@"mind %llu %llu %d %llu %u %lld %lld %d", (unsigned long long) m->agent,
                                               (unsigned long long) m->decisions, m->waiting ? 1 : 0,
                                               (unsigned long long) m->heard, m->awaiting, (long long) m->awaitSince,
                                               (long long) m->awaitUntil, m->nintentions];
      for( k = 0; k < m->nintentions; k++)
      {
         t = &m->intentions[ k];
         [line appendFormat:@" %s %lld %u %d %d %d", t->goal, (long long) t->adopted, t->failed, t->pending,
                                                 t->following, t->nparams];
         for( p = 0; p < t->nparams; p++)
            [line appendFormat:@" %s %u", t->params[ p].slot, t->params[ p].referent];
      }
      [lines addObject:line];
   }
   return( lines);
}


- (void) restoreSavedState:(NSArray *) lines
{
   NSArray        *words;
   BGMotivation   *m;
   BGIntention    *t;
   NSUInteger     i;
   NSUInteger     w;
   int            n;
   int            k;
   int            p;

   [_minds removeAllObjects];
   for( i = 0; i < [lines count]; i++)
   {
      words = [[lines objectAtIndex:i] componentsSeparatedByString:@" "];
      if( [words count] < 9 || ! [[words objectAtIndex:0] isEqualToString:@"mind"])
         continue;
      m             = [self mindOf:(BGEntityID) [[words objectAtIndex:1] longLongValue]];
      m->decisions  = (uint64_t) [[words objectAtIndex:2] longLongValue];
      m->waiting    = [[words objectAtIndex:3] intValue] != 0;
      m->heard      = (NSUInteger) [[words objectAtIndex:4] longLongValue];
      m->awaiting   = (uint32_t) [[words objectAtIndex:5] longLongValue];
      m->awaitSince = [[words objectAtIndex:6] longLongValue];
      m->awaitUntil = [[words objectAtIndex:7] longLongValue];
      n             = [[words objectAtIndex:8] intValue];
      w             = 9;
      for( k = 0; k < n && k < BG_MAX_INTENTIONS && w + 6 <= [words count]; k++)
      {
         t          = &m->intentions[ m->nintentions++];
         memset( t, 0, sizeof( *t));
         t->goal    = [_world intern:[[words objectAtIndex:w++] UTF8String]];
         t->adopted = [[words objectAtIndex:w++] longLongValue];
         t->failed  = (uint32_t) [[words objectAtIndex:w++] longLongValue];
         t->pending   = [[words objectAtIndex:w++] intValue];
         t->following = [[words objectAtIndex:w++] intValue];
         t->nparams   = [[words objectAtIndex:w++] intValue];
         for( p = 0; p < t->nparams && p < BG_MAX_SLOTS && w + 2 <= [words count]; p++)
         {
            t->params[ p].slot     = [_world intern:[[words objectAtIndex:w++] UTF8String]];
            t->params[ p].referent = (uint32_t) [[words objectAtIndex:w++] intValue];
         }
         t->nparams = p;
      }
   }
}

@end

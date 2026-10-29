#import "BGAgency.h"

#import "BGActions.h"

#include <stdio.h>
#include <stdlib.h>


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


static const char   *goal_name( BGGoal g)
{
   switch( g)
   {
   case BGGoalWedgeLock:
      return( "wedge the lock");
   case BGGoalSeekNails:
      return( "seek nails");
   }
   return( "?");
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


- (void) commitToWedging:(BGEntityID) agent
{
   BGMotivation   *m;

   m             = [self mindOf:agent];
   m->ngoals     = 1;
   m->goals[ 0]  = BGGoalWedgeLock;
   m->nsearched  = 0;
   m->waiting    = NO;
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


static BOOL   is_nails( const BGReferent *r)
{
   return( r->kind && ! strcmp( r->kind, "#Stack") && r->features && strstr( r->features, "unit: \"iron_nail\""));
}


/* Nails the agent believes are there for it: in its hand, or somewhere not
 * held by someone else. The first by: in hand, then nearest, then id. */
- (const BGReferent *) nailsFor:(BGKnowledgeStore *) store
                             me:(const BGReferent *) me
                         inHand:(BOOL) inHand
{
   const BGReferent   *best;
   const BGReferent   *r;
   NSUInteger         i;
   BOOL               held;

   best = NULL;
   for( i = 0; i < [store count]; i++)
   {
      r = [store referentAt:i];
      if( ! r->present || ! is_nails( r))
         continue;
      held = r->form == BGLocationHeldBy && r->container == me->id;
      if( inHand != held)
         continue;
      if( ! inHand && r->form == BGLocationHeldBy)
         continue;                   /* someone else holds them */
      if( ! best || distance( me, r) < distance( me, best))
         best = r;
   }
   return( best);
}


- (const BGReferent *) lockFor:(BGKnowledgeStore *) store
{
   const BGReferent   *r;
   NSUInteger         i;

   for( i = 0; i < [store count]; i++)
   {
      r = [store referentAt:i];
      if( r->present && r->kind && ! strcmp( r->kind, "#Assembly"))
         return( r);
   }
   return( NULL);
}


- (BOOL) believesWedged:(BGKnowledgeStore *) store
                   lock:(const BGReferent *) lock
{
   const BGReferent   *r;
   NSUInteger         i;

   for( i = 0; lock && i < [store count]; i++)
   {
      r = [store referentAt:i];
      if( r->present && r->form == BGLocationPartOf && r->container == lock->id && ! strcmp( r->role, "wedge"))
         return( YES);
   }
   return( NO);
}


/* --- acting ------------------------------------------------------------------------- */

/* Not variadic: in mulle-objc a method's variadic arguments don't arrive
 * through va_start; the callers format. */
- (void) note:(BGMotivation *) m
         line:(NSString *) line
{
   [m->log addObject:[NSString stringWithFormat:@"d%llu t=%lldms [%s] %@", (unsigned long long) m->decisions,
                                                (long long) [_world time].ms,
                                                m->ngoals ? goal_name( m->goals[ m->ngoals - 1]) : "-", line]];
}


- (void) act:(BGMotivation *) m
       store:(BGKnowledgeStore *) store
   operation:(const char *) operation
        item:(uint32_t) item
 destination:(uint32_t) destination
      amount:(int64_t) amount
{
   NSString   *error;

   error = nil;
   if( ! BGPerformBelieved( _world, _committer, store,
                            BGActionMake( [_world intern:operation], [store selfReferent], item, destination),
                            amount, &error))
      [self note:m line:[NSString stringWithFormat:@"could not %s: %@", operation, error]];
   else
      [self note:m line:[NSString stringWithFormat:@"%s R%u%@", operation, item,
                          destination ? [NSString stringWithFormat:@" into R%u", destination] : @""]];
}


/* One step toward a believed place: the longer way first. */
- (void) walk:(BGMotivation *) m
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
      [self note:m line:[NSString stringWithFormat:@"could not %s: %@", op, error]];
   else
      [self note:m line:[NSString stringWithFormat:@"%s, toward R%u at (%d, %d)", op, target->id, target->x, target->y]];
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

/* One decision. YES when it acted or settled into waiting; NO when it only
 * changed the intention, so the agent decides again at once. */
- (BOOL) decide:(BGMotivation *) m
{
   BGKnowledgeStore   *store;
   const BGReferent   *me;
   const BGReferent   *lock;
   const BGReferent   *nails;
   const BGReferent   *best;
   const BGReferent   *r;
   const BGReferent   *gone;
   NSUInteger         i;
   int                k;
   int                score;
   int                bestScore;
   BOOL               searched;

   store = [_knowledge storeOf:m->agent];
   me    = [store referent:[store selfReferent]];
   if( ! me || ! m->ngoals || [self busy:m->agent])
      return( YES);     /* mid-activity, or nothing to do: no cost */
   if( m->waiting && ! [[store news] count])
      return( YES);
   m->waiting = NO;
   m->decisions++;
   lock = [self lockFor:store];

   switch( m->goals[ m->ngoals - 1])
   {
   case BGGoalWedgeLock:
      if( [self believesWedged:store lock:lock])
      {
         [self note:m line:[NSString stringWithFormat:@"the lock is wedged: done"]];
         m->ngoals--;
         return( YES);
      }
      if( ! lock)
      {
         [self note:m line:[NSString stringWithFormat:@"I know of no lock: impossible for now"]];
         m->ngoals = 0;
         return( YES);
      }
      /* the method: nails in hand, then drive one */
      if( (nails = [self nailsFor:store me:me inHand:YES]))
      {
         if( in_reach( me, lock))
            [self act:m store:store operation:"drive" item:nails->id destination:lock->id amount:0];
         else
            [self walk:m me:me toward:lock];
         return( YES);
      }
      if( (nails = [self nailsFor:store me:me inHand:NO]))
      {
         if( in_reach( me, nails))
            /* two, so they stay a stack; drive splits one off */
            [self act:m store:store operation:"take_some" item:nails->id destination:0 amount:2];
         else
            [self walk:m me:me toward:nails];
         return( YES);
      }
      /* a failed precondition: the instrumental goal (AGENCY.md §3, step 6) */
      [self note:m line:[NSString stringWithFormat:@"no nails where I believed them: seek nails (wedging stays the intention)"]];
      m->goals[ m->ngoals++] = BGGoalSeekNails;
      m->nsearched           = 0;
      /* where it last believed nails to be, it has just found none */
      for( i = 0; i < [store count]; i++)
      {
         r = [store referentAt:i];
         if( is_nails( r) && ! r->present && r->container && m->nsearched < BG_MAX_SEARCHED)
            m->searched[ m->nsearched++] = r->container;
      }
      return( NO);

   case BGGoalSeekNails:
      if( [self nailsFor:store me:me inHand:YES] || [self nailsFor:store me:me inHand:NO])
      {
         [self note:m line:[NSString stringWithFormat:@"found nails: back to wedging the lock"]];
         m->ngoals--;
         return( NO);
      }
      /* the containers it knows, in the order of its belief that the nails are there */
      best      = NULL;
      bestScore = -1;
      for( i = 0; i < [store count]; i++)
      {
         r = [store referentAt:i];
         if( ! r->present || ! r->kind || (strcmp( r->kind, "#Container") && ! strstr( r->kind, "Container")))
            continue;
         for( searched = NO, k = 0; k < m->nsearched && ! searched; k++)
            searched = m->searched[ k] == r->id;
         if( searched)
            continue;
         score = 0;
         gone  = NULL;
         for( k = 0; k < (int) [store count] && ! gone; k++)
            if( is_nails( [store referentAt:k]) && [store referentAt:k]->container == r->id)
               gone = [store referentAt:k];
         score = (gone ? 1000000 : 0) + (int) (r->seen / 1000) * 10 - distance( me, r);
         if( score > bestScore || (score == bestScore && best && r->id < best->id))
         {
            best      = r;
            bestScore = score;
         }
      }
      if( ! best)
      {
         [self note:m line:[NSString stringWithFormat:@"nowhere left to look: wedging the lock is impossible for now"]];
         m->ngoals  = 0;
         m->waiting = YES;
         return( YES);
      }
      if( in_reach( me, best))
      {
         [self act:m store:store operation:"look_in" item:best->id destination:0 amount:0];
         if( m->nsearched < BG_MAX_SEARCHED)
            m->searched[ m->nsearched++] = best->id;
      }
      else
         [self walk:m me:me toward:best];
      return( YES);
   }
}


- (void) decideBoundary:(uint64_t) boundary
{
   NSUInteger   i;
   int          k;

   /* in stable ID order; each reads only its own stores and committed state */
   for( i = 0; i < [_minds count]; i++)
      for( k = 0; k < 4 && ! [self decide:[_minds objectAtIndex:i]]; k++)
         ;
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
   NSUInteger        i;
   int               k;

   lines = [NSMutableArray array];
   for( i = 0; i < [_minds count]; i++)
   {
      m    = [_minds objectAtIndex:i];
      line = [NSMutableString stringWithFormat:@"mind %llu %llu %d %d", (unsigned long long) m->agent,
                                               (unsigned long long) m->decisions, m->waiting ? 1 : 0, m->ngoals];
      for( k = 0; k < m->ngoals; k++)
         [line appendFormat:@" %d", (int) m->goals[ k]];
      [line appendFormat:@" %d", m->nsearched];
      for( k = 0; k < m->nsearched; k++)
         [line appendFormat:@" %u", m->searched[ k]];
      [lines addObject:line];
   }
   return( lines);
}


- (void) restoreSavedState:(NSArray *) lines
{
   NSArray        *words;
   BGMotivation   *m;
   NSUInteger     i;
   NSUInteger     w;
   int            k;

   [_minds removeAllObjects];
   for( i = 0; i < [lines count]; i++)
   {
      words = [[lines objectAtIndex:i] componentsSeparatedByString:@" "];
      if( [words count] < 6 || ! [[words objectAtIndex:0] isEqualToString:@"mind"])
         continue;
      m            = [self mindOf:(BGEntityID) [[words objectAtIndex:1] longLongValue]];
      m->decisions = (uint64_t) [[words objectAtIndex:2] longLongValue];
      m->waiting   = [[words objectAtIndex:3] intValue] != 0;
      m->ngoals    = [[words objectAtIndex:4] intValue];
      w            = 5;
      for( k = 0; k < m->ngoals && k < BG_MAX_GOALS && w < [words count]; k++)
         m->goals[ k] = (BGGoal) [[words objectAtIndex:w++] intValue];
      m->nsearched = w < [words count] ? [[words objectAtIndex:w++] intValue] : 0;
      for( k = 0; k < m->nsearched && k < BG_MAX_SEARCHED && w < [words count]; k++)
         m->searched[ k] = (uint32_t) [[words objectAtIndex:w++] intValue];
   }
}

@end

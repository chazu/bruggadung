#import "BGScheduler.h"


static BGTime   earlier( BGTime a, BGTime b)
{
   return( a.ms < b.ms ? a : b);
}


@implementation BGScheduler

- (id) initWithWorld:(BGWorld *) world
           committer:(BGCommitter *) committer
{
   if( ! (self = [super init]))
      return( nil);
   _world     = [world retain];
   _committer = [committer retain];
   _domains   = [NSMutableArray new];
   return( self);
}


- (void) dealloc
{
   [_world release];
   [_committer release];
   [_domains release];
   [super dealloc];
}


- (void) addDomain:(id <BGDomain>) domain
{
   [_domains addObject:domain];
}


- (void) setInputs:(id <BGInputSource>) inputs
{
   _inputs = inputs;
}


- (void) setActivities:(id <BGActivityClock>) activities
{
   _activities = activities;
}


- (void) setObserver:(id <BGSchedulerObserver>) observer
{
   _observer = observer;
}


- (BGTime) nextBoundaryTime
{
   id <BGDomain>   d;
   BGHorizon       h;
   BGTime          bound;
   BGTime          t;
   NSUInteger      i;

   t     = [_world time];
   bound = BGTimeNever;
   if( _inputs)
      bound = earlier( bound, [_inputs nextInputTime]);
   if( _activities)
      bound = earlier( bound, [_activities nextCompletion]);
   for( i = 0; i < [_domains count]; i++)
   {
      d = [_domains objectAtIndex:i];
      if( ! [d isActive])
         continue;
      h = [d horizonAt:t];
      if( h.safeStep.ms < BGTimeNever.ms - t.ms)
         bound = earlier( bound, BGTimeMake( t.ms + h.safeStep.ms));
      bound = earlier( bound, h.nextEvent);
   }
   /* groups deferred from the last boundary commit at the next one, which comes soon */
   if( [_committer hasPending])
      bound = earlier( bound, BGTimeMake( t.ms + 1));
   /* time moves forward: only the first boundary, or an input, may be at the current time */
   if( bound.ms <= t.ms)
   {
      bound = t;
      if( [_world boundary] > 0 && ! (_inputs && [_inputs nextInputTime].ms <= t.ms))
         bound = BGTimeMake( t.ms + 1);
   }
   return( bound);
}


/* One boundary at `bound`: domains advance to it, then commitment runs there. */
- (void) boundaryAt:(BGTime) bound
{
   id <BGDomain>   d;
   NSArray         *groups;
   BGTime          t;
   NSUInteger      i;

   t = [_world time];

   /* advance every active domain to the bound */
   for( i = 0; i < [_domains count]; i++)
   {
      d = [_domains objectAtIndex:i];
      if( [d isActive])
         [d advanceFrom:t
                     to:bound
                  world:_world
              committer:_committer];
   }

   /* commit at the bound, with the inputs due then */
   [_world setTime:bound];
   [_world setBoundary:[_world boundary] + 1];
   [_activities completeDueAt:bound];
   if( _inputs && [_inputs nextInputTime].ms <= bound.ms)
      [_inputs deliverInputsAt:bound
                         world:_world
                     committer:_committer];
   groups = [_committer commitBoundary];
   [_observer scheduler:self
      didCommitBoundary:[_world boundary]
                 groups:groups];
}


- (BOOL) stepUntil:(BGTime) stop
{
   BGTime   bound;

   bound = [self nextBoundaryTime];
   if( bound.ms > stop.ms || bound.ms == BGTimeNever.ms)
      return( NO);
   [self boundaryAt:bound];
   return( YES);
}


/* A stop is a boundary too (ARCHITECTURE.md): the domains advance to it, so
 * no time passes without them. */
- (NSUInteger) runUntil:(BGTime) stop
{
   NSUInteger   n;

   n = 0;
   while( [self stepUntil:stop])
      n++;
   if( [_world time].ms < stop.ms)
   {
      [self boundaryAt:stop];
      n++;
   }
   return( n);
}

@end

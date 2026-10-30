#import "BGBodies.h"


int64_t   BGSatiety( const BGAgent *agent, int64_t t)
{
   int64_t   fed;

   fed = agent->fed;
   if( t > agent->fedAt)
      fed -= (t - agent->fedAt) / BG_HUNGER_PERIOD;
   return( fed < 0 ? 0 : fed);
}


@implementation BGBodies

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
   return( @"bodies");
}


- (BGStore *) agents
{
   return( [_world storeForKind:[_world kindNamed:"Agent"]]);
}


- (BOOL) isActive
{
   return( [[self agents] count] > 0);
}


/* The next time an agent's stock falls to a multiple of the band, for each
 * agent not yet starved. */
- (BGHorizon) horizonAt:(BGTime) t
{
   const BGAgent   *agent;
   BGStore         *agents;
   BGHorizon       h;
   NSUInteger      i;
   int64_t         now;
   int64_t         band;
   int64_t         when;

   h.safeStep  = BGTimeNever;
   h.nextEvent = BGTimeNever;
   agents      = [self agents];
   for( i = 0; i < [agents count]; i++)
   {
      agent = [agents recordAtIndex:i];
      now   = BGSatiety( agent, t.ms);
      if( now <= 0)
         continue;
      band = ((now - 1) / BG_HUNGER_BAND) * BG_HUNGER_BAND;     /* the next multiple below */
      when = agent->fedAt + (agent->fed - band) * BG_HUNGER_PERIOD;
      if( when > t.ms && when < h.nextEvent.ms)
         h.nextEvent = BGTimeMake( when);
   }
   return( h);
}


/* Nothing to propose: the stock is read, not stepped. */
- (void) advanceFrom:(BGTime) t0
                  to:(BGTime) t1
               world:(BGWorld *) world
           committer:(BGCommitter *) committer
{
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

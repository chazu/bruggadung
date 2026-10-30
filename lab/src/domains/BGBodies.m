#import "BGBodies.h"

#import "BGActions.h"


int64_t   BGSatiety( const BGAgent *agent, int64_t t)
{
   int64_t   fed;

   fed = agent->fed;
   if( t > agent->fedAt)
      fed -= (t - agent->fedAt) / BG_HUNGER_PERIOD;
   return( fed < 0 ? 0 : fed);
}


int64_t   BGColdness( BGWorld *world, BGEntityID agent)
{
   const BGThermalBody   *body;
   int64_t               cold;

   body = [world record:[world kindNamed:"ThermalBody"] for:agent];
   if( ! body || ! body->heatCapacity)
      return( 0);
   cold = (310000 - body->heat * 1000 / body->heatCapacity) / 100;
   return( cold < 0 ? 0 : cold > 100 ? 100 : cold);
}


int64_t   BGBreathlessness( BGWorld *world, BGEntityID agent)
{
   const BGGasStore   *gas;
   int64_t            stuffy;

   if( ! [world record:[world kindNamed:"Respirator"] for:agent] ||
       ! (gas = [world record:[world kindNamed:"GasStore"] for:BGAirOver( world, agent)]) || ! gas->total)
      return( 0);
   stuffy = (gas->dioxide * 1000000 / gas->total - 1000) / 100;
   return( stuffy < 0 ? 0 : stuffy > 100 ? 100 : stuffy);
}


/* Its stocks' periods of harm, if going without: 0 where it isn't. */
static void   deprivation( BGWorld *world, BGEntityID entity, const BGAgent *agent, int64_t t, int64_t periods[ 3])
{
   periods[ 0] = 100 - BGSatiety( agent, t) >= BG_STARVING ? BG_STARVE_PERIOD : 0;
   periods[ 1] = BGColdness( world, entity) >= BG_FREEZING ? BG_FREEZE_PERIOD : 0;
   periods[ 2] = BGBreathlessness( world, entity) >= BG_SMOTHERING ? BG_SMOTHER_PERIOD : 0;
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
   int64_t         periods[ 3];
   int             k;

   h.safeStep  = BGTimeNever;
   h.nextEvent = BGTimeNever;
   agents      = [self agents];
   for( i = 0; i < [agents count]; i++)
   {
      agent = [agents recordAtIndex:i];
      /* the next point of harm, going without */
      deprivation( _world, [agents entityAtIndex:i], agent, t.ms, periods);
      for( k = 0; k < 3; k++)
         if( periods[ k] && (t.ms / periods[ k] + 1) * periods[ k] < h.nextEvent.ms)
            h.nextEvent = BGTimeMake( (t.ms / periods[ k] + 1) * periods[ k]);
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


/* The stock is read, not stepped; but going without, a point of harm for
 * each multiple of its period passed, as the body was at t0: fatigue up to
 * BG_WEARY, then injury. */
- (void) advanceFrom:(BGTime) t0
                  to:(BGTime) t1
               world:(BGWorld *) world
           committer:(BGCommitter *) committer
{
   const BGAgent     *agent;
   BGProposalGroup   *group;
   BGStore           *agents;
   NSUInteger        i;
   int64_t           periods[ 3];
   int64_t           harm;
   int64_t           fatigue;
   int64_t           injury;
   int               k;

   agents = [self agents];
   group  = nil;
   for( i = 0; i < [agents count]; i++)
   {
      agent = [agents recordAtIndex:i];
      deprivation( world, [agents entityAtIndex:i], agent, t0.ms, periods);
      for( harm = 0, k = 0; k < 3; k++)
         if( periods[ k])
            harm += t1.ms / periods[ k] - t0.ms / periods[ k];
      if( ! harm)
         continue;
      fatigue = agent->fatigue;
      injury  = agent->injury;
      for( ; harm > 0; harm--)
         if( fatigue < BG_WEARY)
            fatigue++;
         else if( injury < 100)
            injury++;
      if( ! group)
         group = [BGProposalGroup groupWithPhase:BGPhaseProcess source:@"bodies: going without"];
      if( fatigue != agent->fatigue)
         [group set:"Agent.fatigue" of:BGWhole( [agents entityAtIndex:i]) to:fatigue];
      if( injury != agent->injury)
         [group set:"Agent.injury" of:BGWhole( [agents entityAtIndex:i]) to:injury];
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

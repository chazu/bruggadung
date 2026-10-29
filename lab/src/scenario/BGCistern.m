#import "BGCistern.h"

#import "BGActions.h"
#import "BGWorlds.h"


@implementation BGCistern

+ (NSString *) nameOf:(BGCisternVariant) variant
{
   switch( variant)
   {
   case BGCisternBase:
      return( @"cistern");
   case BGCisternEarlier:
      return( @"cistern-b");
   case BGCisternReversed:
      return( @"cistern-d");
   case BGCisternStopsEarly:
      return( @"cistern-e");
   }
   return( @"?");
}


- (id) initWithWorld:(BGWorld *) world
           committer:(BGCommitter *) committer
             variant:(BGCisternVariant) variant
{
   if( ! (self = [super init]))
      return( nil);
   _variant       = variant;
   _world         = [world retain];
   _committer     = [committer retain];
   _scheduler     = [[BGScheduler alloc] initWithWorld:world
                                             committer:committer];
   _fluid         = [[BGFluidDomain alloc] initWithWorld:world];
   _results       = [NSMutableArray new];
   _groups        = [NSMutableArray new];
   _conserved     = YES;
   _neverNegative = YES;
   [_fluid setReversedOrder:variant == BGCisternReversed];
   _activities = [[BGActivities activitiesWithWorld:world committer:committer] retain];
   [_scheduler addDomain:_fluid];
   [_scheduler setActivities:_activities];
   [_scheduler setInputs:self];
   [_scheduler setObserver:self];
   return( self);
}


- (void) dealloc
{
   [_world release];
   [_committer release];
   [_scheduler release];
   [_fluid release];
   [_activities release];
   [_results release];
   [_groups release];
   [_firstProblem release];
   [_setup release];
   [super dealloc];
}


- (BGWorld *) world
{
   return( _world);
}


- (BGCommitter *) committer
{
   return( _committer);
}


- (BGFluidDomain *) fluid
{
   return( _fluid);
}


- (NSArray *) results
{
   return( _results);
}


- (NSUInteger) failureCount
{
   NSUInteger   i;
   NSUInteger   n;

   n = 0;
   for( i = 0; i < [_results count]; i++)
      if( [[_results objectAtIndex:i] hasPrefix:@"FAIL"])
         n++;
   return( n);
}


- (void) check:(BOOL) ok
          name:(NSString *) name
           why:(NSString *) why
{
   if( ok)
      [_results addObject:[NSString stringWithFormat:@"ok   %@", name]];
   else
      [_results addObject:[NSString stringWithFormat:@"FAIL %@: %@", name, why ? why : @"no"]];
}


/* --- inputs --------------------------------------------------------------------- */

- (int64_t) openTimeB
{
   return( _variant == BGCisternEarlier ? 61000 : 1000);
}


- (BGTime) nextInputTime
{
   switch( _next)
   {
   case 0:
      return( BGTimeMake( 0));
   case 1:
      return( BGTimeMake( 1000));
   case 2:
      return( [self openTimeB] > 1000 ? BGTimeMake( [self openTimeB]) : BGTimeNever);
   default:
      return( BGTimeNever);
   }
}


/* The agent starts filling the bucket under the tap, to `amount` mL. */
- (void) fill:(BGEntityID) bucket
         from:(BGEntityID) tap
           by:(BGEntityID) agent
       amount:(int64_t) amount
{
   NSString          *error;
   BGProposalGroup   *g;

   error = nil;
   g     = BGPerform( _world, _committer, BGActionMake( [_world intern:"fill_bucket"], agent, tap, bucket),
                      amount, &error);
   if( ! g)
      [self check:NO
             name:[NSString stringWithFormat:@"agent %llu can fill from tap %llu",
                                             (unsigned long long) agent, (unsigned long long) tap]
              why:error];
}


- (void) deliverInputsAt:(BGTime) t
                   world:(BGWorld *) world
               committer:(BGCommitter *) committer
{
   BGProposalGroup   *g;
   BGEntityID        h[ 8];

   while( [self nextInputTime].ms <= t.ms)
   {
      switch( _next)
      {
      case 0:
         g = BGCisternSetup( h);
         [committer submit:g];
         _setup   = [g retain];
         _cistern = h[ 0];
         _tapA    = h[ 1];
         _tapB    = h[ 2];
         _crack   = h[ 3];
         _bucketA = h[ 4];
         _bucketB = h[ 5];
         _agentA  = h[ 6];
         _agentB  = h[ 7];
         break;

      case 1:
         [self fill:_bucketA from:_tapA by:_agentA amount:_variant == BGCisternStopsEarly ? 3000 : 10000];
         if( [self openTimeB] == 1000)
            [self fill:_bucketB from:_tapB by:_agentB amount:10000];
         break;

      case 2:
         [self fill:_bucketB from:_tapB by:_agentB amount:10000];
         break;
      }
      _next++;
   }
}


/* --- each boundary --------------------------------------------------------------- */

- (int64_t) totalWater
{
   BGStore      *stores;
   BGEntityID   e;
   NSUInteger   i;
   int64_t      sum;
   int64_t      w;

   stores = [_world storeForKind:[_world kindNamed:"WaterStore"]];
   sum    = [_world totalTileWater] + [_fluid checkedOutWater];
   for( i = 0; i < [stores count]; i++)
   {
      e = [stores entityAtIndex:i];
      if( [_world isCheckedOut:e])
         continue;
      [_world getField:"WaterStore.water" of:e value:&w];
      sum += w;
      if( w < 0)
         _neverNegative = NO;
   }
   return( sum);
}


- (void) scheduler:(BGScheduler *) scheduler
 didCommitBoundary:(uint64_t) boundary
            groups:(NSArray *) groups
{
   int64_t   total;

   if( boundary < 256)
      _times[ boundary] = [_world time].ms;
   if( BGIsHandle( _cistern) && [_setup applied])
   {
      _cistern = [_setup idFor:_cistern];
      _tapA    = [_setup idFor:_tapA];
      _tapB    = [_setup idFor:_tapB];
      _crack   = [_setup idFor:_crack];
      _bucketA = [_setup idFor:_bucketA];
      _bucketB = [_setup idFor:_bucketB];
      _agentA  = [_setup idFor:_agentA];
      _agentB  = [_setup idFor:_agentB];
   }
   total = [self totalWater];
   if( total != 15000 && _conserved)
   {
      _conserved    = NO;
      _firstProblem = [[NSString stringWithFormat:@"boundary %llu: %lld mL", (unsigned long long) boundary,
                                                  (long long) total] retain];
   }
}


/* --- the run --------------------------------------------------------------------- */

- (int64_t) waterOf:(BGEntityID) e
{
   int64_t   w;

   w = 0;
   [_world getField:"WaterStore.water" of:e value:&w];
   return( w);
}


/* The boundary of the "exhausted" event for a tap, or 0. */
- (uint64_t) exhaustedBoundaryOf:(BGEntityID) tap
{
   const BGEvent   *ev;
   NSUInteger      i;

   for( i = 0; i < [_world eventCount]; i++)
   {
      ev = [_world eventAt:i];
      if( ! strcmp( ev->kind, "exhausted") && ev->subject == tap)
         return( ev->boundary);
   }
   return( 0);
}


/* An agent's fill activity: its status, and the boundary its status last changed. */
- (const char *) activityOf:(BGEntityID) agent
                   boundary:(uint64_t *) boundary
{
   const BGActivity   *record;
   const BGEvent      *ev;
   BGStore            *store;
   BGEntityID         a;
   NSUInteger         i;

   store = [_world storeForKind:[_world kindNamed:"Activity"]];
   a     = BGNoEntity;
   for( i = 0; i < [store count]; i++)
      if( ((const BGActivity *) [store recordAtIndex:i])->actorRef == agent)
         a = [store entityAtIndex:i];
   *boundary = 0;
   if( ! a)
      return( "none");
   for( i = 0; i < [_world eventCount]; i++)
   {
      ev = [_world eventAt:i];
      if( ! strcmp( ev->kind, "changed") && ev->subject == a && ev->detail && ! strcmp( ev->detail, "Activity.status"))
         *boundary = ev->boundary;
   }
   record = [_world record:[_world kindNamed:"Activity"] for:a];
   return( tri_type_name( [_world tri], record->status));
}


- (void) runUntil:(BGTime) t
{
   [_scheduler runUntil:t];
}


- (void) resumeWithWorld:(BGWorld *) world
               committer:(BGCommitter *) committer
              fluidState:(NSArray *) state
{
   [_world autorelease];
   _world = [world retain];
   [_committer autorelease];
   _committer = [committer retain];
   [_fluid autorelease];
   _fluid = [[BGFluidDomain alloc] initWithWorld:world];
   [_fluid setReversedOrder:_variant == BGCisternReversed];
   [_fluid restoreSavedState:state];
   [_activities autorelease];
   _activities = [[BGActivities activitiesWithWorld:world committer:committer] retain];
   [_scheduler autorelease];
   _scheduler = [[BGScheduler alloc] initWithWorld:world
                                         committer:committer];
   [_scheduler addDomain:_fluid];
   [_scheduler setActivities:_activities];
   [_scheduler setInputs:self];
   [_scheduler setObserver:self];
}


- (void) run
{
   [self finish];
}


- (void) finish
{
   int64_t    a;
   int64_t    b;
   int64_t    puddle;
   uint64_t   ba;
   uint64_t   bb;
   uint64_t   bc;

   [_scheduler runUntil:BGTimeMake( 300000)];
   [_fluid checkInAll];

   a     = [self waterOf:_bucketA];
   b     = [self waterOf:_bucketB];
   puddle = [_world waterAtX:5 y:5 level:0];
   [self check:_conserved && [self totalWater] == 15000
          name:@"1. exact conservation: buckets + floor + cistern = 15 L at every boundary"
           why:_firstProblem];
   [self check:_neverNegative
          name:@"4. no stock ever goes negative"
           why:nil];
   if( _variant == BGCisternEarlier || _variant == BGCisternStopsEarly)
      [self check:_variant == BGCisternEarlier ? a > b : b > a
             name:_variant == BGCisternEarlier ? @"3b. A, who started a minute earlier, got more"
                                               : @"3e. B, who kept filling, got more"
              why:[NSString stringWithFormat:@"A %lld, B %lld", (long long) a, (long long) b]];
   else
      [self check:llabs( a - b) <= 1
             name:@"3. fairness: equal requests differ by at most one millilitre"
              why:[NSString stringWithFormat:@"A %lld, B %lld", (long long) a, (long long) b]];
   ba = [self exhaustedBoundaryOf:_tapA];
   bb = [self exhaustedBoundaryOf:_tapB];
   bc = [self exhaustedBoundaryOf:_crack];
   /* in 3e both taps close by their watches before the cistern runs dry */
   if( _variant != BGCisternStopsEarly)
   [self check:ba && ba == bb && bb == bc && ba < 256 && _times[ ba] == [_fluid predictedExhaustion].ms &&
               [self waterOf:_cistern] == 0
          name:@"5. every tap hears \"exhausted\" in the same step, at the boundary the horizon predicted"
           why:[NSString stringWithFormat:@"boundaries %llu %llu %llu, at %lldms, predicted %lldms",
                                          (unsigned long long) ba, (unsigned long long) bb, (unsigned long long) bc,
                                          ba < 256 ? (long long) _times[ ba] : -1LL,
                                          (long long) [_fluid predictedExhaustion].ms]];
   {
      const char   *sa;
      const char   *sb;
      uint64_t     ea;
      uint64_t     eb;

      sa = [self activityOf:_agentA boundary:&ea];
      sb = [self activityOf:_agentB boundary:&eb];
      if( _variant == BGCisternStopsEarly)
         [self check:! strcmp( sa, "\"completed\"") && a == 3000 && ! strcmp( sb, "\"completed\"") && b == 10000
                name:@"3e. each watch ended its activity at its amount: A at 3 L, B at 10 L; the crack drained the rest"
                 why:[NSString stringWithFormat:@"A %s with %lld mL, B %s with %lld mL", sa, (long long) a, sb,
                                                (long long) b]];
      else
         [self check:! strcmp( sa, "\"exhausted\"") && ! strcmp( sb, "\"exhausted\"") && ea == eb && ea == ba
                name:@"5. both fill activities end, exhausted, in the step the cistern ran dry"
                 why:[NSString stringWithFormat:@"A %s at %llu, B %s at %llu, dry at %llu", sa,
                                                (unsigned long long) ea, sb, (unsigned long long) eb,
                                                (unsigned long long) ba]];
   }
   [_results addObject:[NSString stringWithFormat:@"     bucket A %lld mL, bucket B %lld mL, floor %lld mL, "
                                                  @"dry at %lldms", (long long) a, (long long) b, (long long) puddle,
                                                  (long long) [_fluid predictedExhaustion].ms]];
}

@end

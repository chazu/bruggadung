#import "BGMarkedNail.h"

#import "BGActions.h"


/* The input log: what happens, and when (simulation milliseconds). */
typedef enum
{
   BGStepSetup,
   BGStepPour,          /* B: the worker's own nails go into the bin */
   BGStepTake,          /* the worker takes 5 */
   BGStepHammer,        /* one nail is hammered into the lock */
   BGStepPullOut,
   BGStepDropBack,      /* all 5 go back into the bin */
   BGStepMergeBent,     /* a merge of the bent nail is proposed outright */
   BGStepEnd
} BGStep;

typedef struct
{
   int64_t   ms;
   BGStep    step;
} BGScriptLine;

static const BGScriptLine   baseScript[] =
{
   {     0, BGStepSetup },
   {  1000, BGStepTake },
   {  5000, BGStepHammer },
   { 60000, BGStepPullOut },
   { 61000, BGStepDropBack },
   { 62000, BGStepMergeBent },
   {    -1, BGStepEnd }
};

static const BGScriptLine   unmarkedScript[] =
{
   {     0, BGStepSetup },
   {  1000, BGStepTake },
   {  5000, BGStepHammer },       /* A: one nail goes into the other hand, unmarked */
   { 61000, BGStepDropBack },
   {    -1, BGStepEnd }
};

static const BGScriptLine   mixedScript[] =
{
   {     0, BGStepSetup },
   {   500, BGStepPour },
   {  1000, BGStepTake },
   {    -1, BGStepEnd }
};


@implementation BGMarkedNail

+ (NSString *) nameOf:(BGMarkedNailVariant) variant
{
   switch( variant)
   {
   case BGMarkedNailBase:
      return( @"marked-nail");
   case BGMarkedNailUnmarked:
      return( @"marked-nail-a");
   case BGMarkedNailMixedGoods:
      return( @"marked-nail-b");
   }
   return( @"?");
}


- (id) initWithWorld:(BGWorld *) world
           committer:(BGCommitter *) committer
             variant:(BGMarkedNailVariant) variant
{
   if( ! (self = [super init]))
      return( nil);
   _variant        = variant;
   _world          = [world retain];
   _committer      = [committer retain];
   _scheduler      = [[BGScheduler alloc] initWithWorld:world
                                              committer:committer];
   _results        = [NSMutableArray new];
   _groups         = [NSMutableArray new];
   _invariantsHeld = YES;
   _activities     = [[BGActivities activitiesWithWorld:world committer:committer] retain];
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
   [_activities release];
   [_results release];
   [_groups release];
   [_explicitMerge release];
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


- (const BGScriptLine *) script
{
   switch( _variant)
   {
   case BGMarkedNailBase:
      return( baseScript);
   case BGMarkedNailUnmarked:
      return( unmarkedScript);
   case BGMarkedNailMixedGoods:
      return( mixedScript);
   }
   return( baseScript);
}


/* --- the input log --------------------------------------------------------- */

- (BGTime) nextInputTime
{
   const BGScriptLine   *line;

   line = &[self script][ _next];
   return( line->step == BGStepEnd ? BGTimeNever : BGTimeMake( line->ms));
}


/* A command: the worker performs an operation from content, through the
 * menu. A command that isn't on the menu is a failed check. */
- (BGProposalGroup *) perform:(const char *) operation
                         item:(BGEntityID) item
                  destination:(BGEntityID) destination
                       amount:(int64_t) amount
{
   BGProposalGroup   *group;
   NSString          *error;

   error = nil;
   group = BGPerform( _world, _committer, BGActionMake( [_world intern:operation], _worker, item, destination),
                      amount, &error);
   if( ! group)
   {
      [self check:NO
             name:[NSString stringWithFormat:@"the worker can %s", operation]
              why:error];
      return( nil);
   }
   [_groups addObject:group];
   return( group);
}


- (void) deliverInputsAt:(BGTime) t
                   world:(BGWorld *) world
               committer:(BGCommitter *) committer
{
   const BGScriptLine   *line;

   for( line = &[self script][ _next]; line->step != BGStepEnd && line->ms <= t.ms; line = &[self script][ ++_next])
      [self perform:line->step];
}


- (void) perform:(BGStep) step
{
   BGProposalGroup   *g;
   BGEntityID        h[ 8];

   switch( step)
   {
   case BGStepSetup:
      g = [BGProposalGroup groupWithPhase:BGPhaseSystem
                                   source:@"setup: the workshop"];
      h[ 0] = [g create:"bin" key:"bin" at:BGOnTile( 3, 4, 0)];
      h[ 1] = [g create:"nails_30" key:"the smith's nails" at:BGIn( h[ 0])];
      h[ 2] = [g create:"lock" key:"lock" at:BGOnTile( 5, 4, 0)];
      h[ 3] = [g create:"worker" key:"worker" at:BGOnTile( 4, 4, 0)];
      h[ 4] = [g create:"smith" key:"smith" at:BGOnTile( 2, 4, 0)];
      h[ 5] = [g create:"ownership" key:"the smith's claim" at:BGLocationMakeNone()];
      [g set:"Claim.quantity" of:BGWhole( h[ 5]) to:30];
      [g relate:BGEdgeClaimant from:BGWhole( h[ 5]) to:BGWhole( h[ 4])];
      [g relate:BGEdgeClaimSubject from:BGWhole( h[ 5]) to:BGWhole( h[ 1])];
      if( _variant == BGMarkedNailMixedGoods)
      {
         h[ 6] = [g create:"nails_10" key:"the worker's nails" at:BGHeldBy( h[ 3], 0)];
         h[ 7] = [g create:"ownership" key:"the worker's claim" at:BGLocationMakeNone()];
         [g set:"Claim.quantity" of:BGWhole( h[ 7]) to:10];
         [g relate:BGEdgeClaimant from:BGWhole( h[ 7]) to:BGWhole( h[ 3])];
         [g relate:BGEdgeClaimSubject from:BGWhole( h[ 7]) to:BGWhole( h[ 6])];
      }
      [_committer submit:g];
      [_groups addObject:g];
      _bin    = h[ 0];
      _stack  = h[ 1];
      _lock   = h[ 2];
      _worker = h[ 3];
      _smith  = h[ 4];
      _claim  = h[ 5];
      [self name:&_bin group:g];
      [self name:&_stack group:g];
      [self name:&_lock group:g];
      [self name:&_worker group:g];
      [self name:&_smith group:g];
      [self name:&_claim group:g];
      if( _variant == BGMarkedNailMixedGoods)
      {
         _workerStack = h[ 6];
         _workerClaim = h[ 7];
         [self name:&_workerStack group:g];
         [self name:&_workerClaim group:g];
      }
      break;

   case BGStepPour:
      [self perform:"put_in" item:_workerStack destination:_bin amount:0];
      break;

   case BGStepTake:
      g = [self perform:"take_some" item:_stack destination:BGNoEntity amount:5];
      if( g)
      {
         _handful = [g proposals][ 0].handle;
         [self name:&_handful group:g];
      }
      break;

   case BGStepHammer:
      /* drive names one nail of the five; commitment splits it off */
      if( _variant == BGMarkedNailBase)
         [self perform:"drive" item:_handful destination:_lock amount:0];
      else
         [self perform:"take_some" item:_handful destination:BGNoEntity amount:1];
      break;

   case BGStepPullOut:
      [self perform:"take" item:_nail destination:BGNoEntity amount:0];
      break;

   case BGStepDropBack:
      [self perform:"put_in" item:_handful destination:_bin amount:0];
      [self perform:"put_in" item:_nail destination:_bin amount:0];
      break;

   case BGStepMergeBent:
      /* not an operation: a merge proposed outright, to see commitment refuse it */
      g = [BGProposalGroup groupWithPhase:BGPhaseSystem
                                   source:@"someone proposes merging the bent nail"];
      [g merge:BGWhole( _nail) into:BGWhole( _stack)];
      [_committer submit:g];
      [_groups addObject:g];
      _explicitMerge = [g retain];
      break;

   case BGStepEnd:
      break;
   }
}


/* --- after each boundary --------------------------------------------------- */

/* A name is a handle until the group that made it applies; then it is the
 * ID that group gave it. Handles are numbered per group. */
- (void) name:(BGEntityID *) name
        group:(BGProposalGroup *) group
{
   _pendingGroups[ _npending] = group;
   _pendingNames[ _npending]  = name;
   _npending++;
}


- (void) learnIDs
{
   BGEntityID   parts[ 4];
   NSUInteger   i;
   NSUInteger   n;

   for( i = 0; i < _npending; i++)
      if( [_pendingGroups[ i] applied])
         *_pendingNames[ i] = [_pendingGroups[ i] idFor:*_pendingNames[ i]];
   _npending = 0;
   /* the hammered nail is whatever is now wedged in the lock; in A, the single nail in the other hand */
   if( ! _nail && _lock && [_world entitiesAt:_lock
                                         form:BGLocationPartOf
                                         into:parts
                                          max:4])
      _nail = parts[ 0];
   if( ! _nail && _variant == BGMarkedNailUnmarked && _worker &&
       (n = [_world entitiesAt:_worker
                          form:BGLocationHeldBy
                          into:parts
                           max:4]))
      for( i = 0; i < n && i < 4; i++)
         if( ! [_world isStack:parts[ i]])
            _nail = parts[ i];
}


/* Totals over every live physical entity: mass, and iron nails. */
- (void) totalsMass:(int64_t *) mass
              nails:(int64_t *) nails
{
   BGStore      *bodies;
   BGEntityID   e;
   NSUInteger   i;
   const char   *unit;

   bodies = [_world storeForKind:[_world kindNamed:"Body"]];
   *mass  = 0;
   *nails = 0;
   for( i = 0; i < [bodies count]; i++)
   {
      e      = [bodies entityAtIndex:i];
      *mass += [_world massOf:e];
      unit   = [_world unitOf:e];
      if( unit && ! strcmp( unit, "iron_nail"))
         *nails += [_world unitsOf:e];
   }
}


/* Every live physical entity has exactly one location, and no two share a
 * hand or an assembly slot. */
- (NSString *) locationProblem
{
   BGStore      *bodies;
   BGStore      *locations;
   BGLocation   *a;
   BGLocation   *b;
   NSUInteger   i;
   NSUInteger   j;

   bodies = [_world storeForKind:[_world kindNamed:"Body"]];
   for( i = 0; i < [bodies count]; i++)
      if( [_world locationOf:[bodies entityAtIndex:i]].form == BGLocationNone)
         return( [NSString stringWithFormat:@"%llu has no location", (unsigned long long) [bodies entityAtIndex:i]]);
   locations = [_world locations];
   for( i = 0; i < [locations count]; i++)
   {
      a = [locations recordAtIndex:i];
      if( a->form != BGLocationHeldBy && a->form != BGLocationPartOf)
         continue;
      for( j = i + 1; j < [locations count]; j++)
      {
         b = [locations recordAtIndex:j];
         if( a->form == b->form && a->place == b->place && a->slot == b->slot && ! strcmp( a->role, b->role))
            return( [NSString stringWithFormat:@"%llu and %llu share a place",
                                               (unsigned long long) [locations entityAtIndex:i],
                                               (unsigned long long) [locations entityAtIndex:j]]);
      }
   }
   return( nil);
}


- (void) scheduler:(BGScheduler *) scheduler
 didCommitBoundary:(uint64_t) boundary
            groups:(NSArray *) groups
{
   NSString   *problem;
   int64_t    mass;
   int64_t    nails;

   [self learnIDs];
   [self totalsMass:&mass
              nails:&nails];
   if( boundary == 1)
   {
      _mass  = mass;
      _nails = nails;
      return;
   }
   problem = [self locationProblem];
   if( mass != _mass || nails != _nails || problem)
   {
      if( _invariantsHeld)
         [_results addObject:[NSString stringWithFormat:@"FAIL invariants at boundary %llu: mass %lld (was %lld), "
                                                        @"nails %lld (was %lld)%@%@",
                                                        (unsigned long long) boundary, (long long) mass,
                                                        (long long) _mass, (long long) nails, (long long) _nails,
                                                        problem ? @", " : @"", problem ? problem : @""]];
      _invariantsHeld = NO;
   }
}


/* --- the run and its checks ------------------------------------------------ */

- (BOOL) traceContains:(NSString *) text
{
   NSArray      *trace;
   NSUInteger   i;

   trace = [_committer trace];
   for( i = 0; i < [trace count]; i++)
      if( [[trace objectAtIndex:i] rangeOfString:text].location != NSNotFound)
         return( YES);
   return( NO);
}


/* From history, which saves keep: the unit was split off in the same group
 * that marked it, though the group proposed no split. */
- (BOOL) splitInGroupThatMarked:(BGEntityID) unit
{
   const BGEvent   *ev;
   const BGEvent   *split;
   NSUInteger      i;

   split = NULL;
   for( i = 0; i < [_world eventCount]; i++)
   {
      ev = [_world eventAt:i];
      if( ! strcmp( ev->kind, "split") && ev->subject == unit && ev->other == _handful && ev->amount == 1)
         split = ev;
      if( split && ! strcmp( ev->kind, "changed") && ev->subject == unit && ev->group == split->group &&
          ev->detail && ! strcmp( ev->detail, "Body.bent"))
         return( YES);
   }
   return( NO);
}


- (void) runUntil:(BGTime) t
{
   [_scheduler runUntil:t];
}


- (void) resumeWithWorld:(BGWorld *) world
               committer:(BGCommitter *) committer
{
   [_world autorelease];
   _world = [world retain];
   [_committer autorelease];
   _committer = [committer retain];
   [_activities autorelease];
   _activities = [[BGActivities activitiesWithWorld:world committer:committer] retain];
   [_scheduler autorelease];
   _scheduler = [[BGScheduler alloc] initWithWorld:world
                                         committer:committer];
   [_scheduler setActivities:_activities];
   [_scheduler setInputs:self];
   [_scheduler setObserver:self];
}


- (void) run
{
   [self runUntil:BGTimeMake( 120000)];
   [self finish];
}


- (void) finish
{
   const BGTombstone   *stone;
   const BGBody        *body;
   NSUInteger          kbody;

   [_scheduler runUntil:BGTimeMake( 120000)];
   kbody = [_world kindNamed:"Body"];

   [self check:_invariantsHeld
          name:@"1. count and mass are conserved exactly"
           why:@"see the invariants failure above"];
   [self check:_invariantsHeld
          name:@"2. location is exclusive at every boundary"
           why:@"see the invariants failure above"];

   switch( _variant)
   {
   case BGMarkedNailBase:
      body = _nail ? [_world record:kbody for:_nail] : NULL;
      [self check:_nail && ! [_world isStack:_nail] && body && body->bent && body->toolMarks == 3 &&
                  [self splitInGroupThatMarked:_nail]
             name:@"3. marking one nail in a stack split it off first, unasked"
              why:[NSString stringWithFormat:@"nail %llu", (unsigned long long) _nail]];
      [self check:[_world isLive:_nail] && [_world locationOf:_nail].form == BGLocationIn &&
                  [_world locationOf:_nail].place == _bin &&
                  [self traceContains:@"units differ physically: one is bent"]
             name:@"4a. the bent nail's merge reaction was rejected, with the reason"
              why:@"no rejection naming the bend"];
      [self check:_explicitMerge && ! [_explicitMerge applied] &&
                  [[_explicitMerge rejection] rangeOfString:@"bent"].location != NSNotFound
             name:@"4b. a merge proposed outright is rejected, with the reason"
              why:[_explicitMerge rejection]];
      stone = [_world tombstone:_handful];
      [self check:stone && stone->successor == _stack && [_world resolve:_handful] == _stack
             name:@"5. the merged handful resolves through its tombstone to the bin stack"
              why:[_world describeEntity:_handful]];
      [self check:[_world unitsOf:_stack] == 29 && [_world massOf:_stack] == 87
             name:@"the bin stack holds 29 nails, 87g"
              why:[_world describeEntity:_stack]];
      [self check:[_world claimedUnitsOf:_stack] == 30 && [_world claimAllocationResolved:_claim]
             name:@"6. the smith's claim covers the bin stack and the bent nail, resolved"
              why:[_world describeEntity:_claim]];
      break;

   case BGMarkedNailUnmarked:
      [self check:_nail && [_world tombstone:_nail] && [_world resolve:_nail] == _stack
             name:@"A. the unmarked nail merged back; a reference to it resolves to the bin stack"
              why:[_world describeEntity:_nail]];
      [self check:[_world unitsOf:_stack] == 30
             name:@"A. the bin stack holds all 30 again"
              why:[_world describeEntity:_stack]];
      [self check:[_world claimAllocationResolved:_claim]
             name:@"A. the smith's claim is resolved"
              why:[_world describeEntity:_claim]];
      break;

   case BGMarkedNailMixedGoods:
      [self check:[_world resolve:_workerStack] == _stack && [_world unitsOf:_stack] == 35
             name:@"B. the worker's nails merged into the bin; 5 were then taken"
              why:[_world describeEntity:_stack]];
      [self check:[_world claimedUnitsOf:_stack] == 40
             name:@"6a. the quantity claims summed on merge (30 + 10)"
              why:[NSString stringWithFormat:@"%lld", (long long) [_world claimedUnitsOf:_stack]]];
      [self check:! [_world claimAllocationResolved:_claim] && ! [_world claimAllocationResolved:_workerClaim] &&
                  [_world claimedUnitsOf:_handful] == 40
             name:@"6b. after the split, whose nails were taken is explicitly unresolved"
              why:[NSString stringWithFormat:@"%@ / %@", [_world describeEntity:_claim], [_world describeEntity:_workerClaim]]];
      break;
   }
}

@end

#import "BGActivities.h"

#import "BGActions.h"
#import "BGProposalGroup.h"
#import "BGView.h"


@implementation BGActivities

+ (instancetype) activitiesWithWorld:(BGWorld *) world
                           committer:(BGCommitter *) committer
{
   BGActivities   *activities;

   activities               = [[self new] autorelease];
   activities->_world       = [world retain];
   activities->_committer   = committer;
   activities->_completions = [NSMutableArray new];
   [committer addListener:activities];
   return( activities);
}


- (void) dealloc
{
   [_world release];
   [_completions release];
   [super dealloc];
}


static BOOL   running( BGWorld *world, BGEntityID a, const BGActivity *record)
{
   return( record && record->status == (uint32_t) tri_type_named( [world tri], "\"running\""));
}


static BGAction   action_of( BGWorld *world, BGEntityID a, const BGActivity *record)
{
   return( BGActionMake( [world textField:"Activity.operation" of:a], (BGEntityID) record->actorRef,
                         (BGEntityID) record->itemRef, (BGEntityID) record->destinationRef));
}


/* --- partial effects ---------------------------------------------------------- */

/* The stage's progress at `t`: kept, plus its running since it started. */
static int64_t   progress_at( const BGActivity *record, int64_t t)
{
   return( record->progress + (record->due ? t - record->started : 0));
}


/* When the stage's next checkpoint falls, after `t`; or BGTimeNever. */
static int64_t   next_checkpoint( BGWorld *world, BGEntityID a, const BGActivity *record, int64_t t)
{
   const char   *operation;
   const char   *field;
   NSString     *effect;
   int64_t      duration;
   int64_t      whole;
   int64_t      n;
   int64_t      k;
   int64_t      at;
   int          role;

   operation = [world textField:"Activity.operation" of:a];
   if( ! record->due || ! BGOperationStage( world, operation, record->stage, &duration, &effect) ||
       ! BGOperationPartial( world, operation, record->stage, &field, &role, &whole, &n))
      return( BGTimeNever.ms);
   for( k = 1; k <= n; k++)
   {
      at = record->started + duration * k / (n + 1) - record->progress;
      if( at > t)
         return( at);
   }
   return( BGTimeNever.ms);
}


/* The stage's partial effect at `progress`, into the group: its field set
 * in proportion. */
- (void) partialOf:(BGEntityID) a
            record:(const BGActivity *) record
          progress:(int64_t) progress
              into:(BGProposalGroup *) group
{
   const char   *operation;
   const char   *field;
   NSString     *effect;
   BGEntityID   target;
   int64_t      duration;
   int64_t      whole;
   int64_t      n;
   int          role;

   operation = [_world textField:"Activity.operation" of:a];
   if( ! BGOperationStage( _world, operation, record->stage, &duration, &effect) ||
       ! BGOperationPartial( _world, operation, record->stage, &field, &role, &whole, &n))
      return;
   target = (BGEntityID) (role == BGRoleItem ? record->itemRef : record->destinationRef);
   if( ! target || ! [_world isLive:target])
      return;
   if( progress > duration)
      progress = duration;
   [group set:field of:BGWhole( target) to:whole * (progress < 0 ? 0 : progress) / duration];
}


/* --- the clock ----------------------------------------------------------------- */

- (BGTime) nextCompletion
{
   const BGActivity   *record;
   BGStore            *store;
   BGTime             next;
   NSUInteger         i;

   store = [_world storeForKind:[_world kindNamed:"Activity"]];
   next  = BGTimeNever;
   for( i = 0; i < [store count]; i++)
   {
      record = [store recordAtIndex:i];
      if( record->due > 0 && running( _world, [store entityAtIndex:i], record) && record->due < next.ms)
         next = BGTimeMake( record->due);
      /* a checkpoint is a step boundary too */
      if( running( _world, [store entityAtIndex:i], record) &&
          next_checkpoint( _world, [store entityAtIndex:i], record, [_world time].ms) < next.ms)
         next = BGTimeMake( next_checkpoint( _world, [store entityAtIndex:i], record, [_world time].ms));
   }
   return( next);
}


- (void) completeDueAt:(BGTime) t
{
   const BGActivity   *record;
   BGProposalGroup    *group;
   BGStore            *store;
   BGEntityID         a;
   NSString           *reason;
   NSString           *effect;
   const char         *operation;
   NSUInteger         i;
   int64_t            duration;
   BOOL               more;

   store = [_world storeForKind:[_world kindNamed:"Activity"]];
   for( i = 0; i < [store count]; i++)
   {
      record = [store recordAtIndex:i];
      a      = [store entityAtIndex:i];
      if( ! record->due || ! running( _world, a, record))
         continue;
      /* a checkpoint: the stage's progress shows */
      if( record->due > t.ms)
      {
         if( next_checkpoint( _world, a, record, t.ms - 1) == t.ms)
         {
            group = [BGProposalGroup groupWithPhase:BGPhaseAction
                                             source:[NSString stringWithFormat:@"activity %llu: checkpoint",
                                                                               (unsigned long long) a]];
            [group setCause:[self startOf:a]];
            [self partialOf:a record:record progress:progress_at( record, t.ms) into:group];
            [_committer submit:group];
         }
         continue;
      }
      operation = [_world textField:"Activity.operation" of:a];
      more      = BGOperationStage( _world, operation, record->stage + 1, &duration, &effect);
      group     = [BGProposalGroup groupWithPhase:BGPhaseAction
                                           source:[NSString stringWithFormat:@"activity %llu: %s %@",
                                                                             (unsigned long long) a, operation,
                                                                             more ? [NSString stringWithFormat:@"stage %lld done",
                                                                                                               (long long) record->stage]
                                                                                  : @"completes"]];
      [group setCause:[self startOf:a]];
      [group setActor:(BGEntityID) record->actorRef];
      if( ! BGOperationStage( _world, operation, record->stage, &duration, &effect))
         effect = nil;
      /* what it needs must still hold when its effect commits: taken from
       * the bench by someone else meanwhile, the seal is not to be taken
       * from their hand */
      reason = [self requirementsOf:a record:record];
      if( ! reason)
         reason = BGApplyNamedEffect( _world, effect, action_of( _world, a, record), record->amount, group);
      /* the effort tells on the actor */
      if( ! reason && BGOperationExertion( _world, operation, record->stage))
      {
         int64_t   fatigue;

         fatigue = 0;
         [_world getField:"Agent.fatigue" of:(BGEntityID) record->actorRef value:&fatigue];
         fatigue += BGOperationExertion( _world, operation, record->stage);
         [group set:"Agent.fatigue" of:BGWhole( (BGEntityID) record->actorRef) to:fatigue > 100 ? 100 : fatigue];
      }
      if( reason)
      {
         [self end:a status:"failed" because:reason cause:[self startOf:a]];
         continue;
      }
      if( BGOperationStage( _world, operation, record->stage + 1, &duration, &effect))
      {
         /* the next stage starts now */
         [group set:"Activity.stage" of:BGWhole( a) to:record->stage + 1];
         [group set:"Activity.progress" of:BGWhole( a) to:0];
         [group set:"Activity.started" of:BGWhole( a) to:t.ms];
         [group set:"Activity.due" of:BGWhole( a) to:t.ms + duration];
      }
      else
      {
         BGLeaveTraces( _world, action_of( _world, a, record), group);
         [group set:"Activity.status" of:BGWhole( a) to:tri_type_named( [_world tri], "\"completed\"")];
         /* ended: its watches with it */
         if( record->watchHolder)
            [group set:"Activity.watchHolder" of:BGWhole( a) to:0];
         if( record->watchFloor)
            [group set:"Activity.watchFloor" of:BGWhole( a) to:0];
      }
      [_committer submit:group];
      [_completions addObject:group];
      [_completions addObject:[NSNumber numberWithUnsignedLongLong:a]];
   }
}


/* The event that created the activity: what its completion follows from. */
- (uint64_t) startOf:(BGEntityID) a
{
   const BGEvent   *ev;
   NSUInteger      i;

   for( i = [_world eventCount]; i-- > 0;)
   {
      ev = [_world eventAt:i];
      if( ev->subject == a && ! strcmp( ev->kind, "created"))
         return( ev->index);
   }
   return( 0);
}


/* --- ending ------------------------------------------------------------------- */

/* Ends an activity: its operation's own clean-up (a fill closes its tap), the
 * status, and the watch removed. */
- (BGProposalGroup *) end:(BGEntityID) a
                  status:(const char *) status
                 because:(NSString *) why
                   cause:(uint64_t) cause
{
   const BGActivity   *record;
   BGProposalGroup    *group;
   char               atom[ 32];

   record = [_world record:[_world kindNamed:"Activity"] for:a];
   if( ! record)
      return( nil);
   group = [BGProposalGroup groupWithPhase:BGPhaseSystem
                                    source:[NSString stringWithFormat:@"activity %llu: %s (%@)",
                                                                      (unsigned long long) a, status, why]];
   [group setCause:cause];
   if( [BGOperationEffect( _world, [_world textField:"Activity.operation" of:a]) isEqualToString:@"fill"])
      [group set:"Tap.open" of:BGWhole( (BGEntityID) record->itemRef) to:0];
   snprintf( atom, sizeof( atom), "\"%s\"", status);
   [group set:"Activity.status" of:BGWhole( a) to:tri_type_named( [_world tri], atom)];
   if( record->watchHolder)
      [group set:"Activity.watchHolder" of:BGWhole( a) to:0];
   if( record->watchFloor)
      [group set:"Activity.watchFloor" of:BGWhole( a) to:0];
   /* stopped short: what its progress shows stays in the world */
   if( strcmp( status, "completed"))
      [self partialOf:a record:record progress:progress_at( record, [_world time].ms) into:group];
   [_committer submit:group];
   return( group);
}


- (BGProposalGroup *) abort:(BGEntityID) a
                    because:(NSString *) why
                      error:(NSString **) error
{
   const BGActivity   *record;

   record = [_world record:[_world kindNamed:"Activity"] for:a];
   if( ! record || ! (running( _world, a, record) ||
                      record->status == (uint32_t) tri_type_named( [_world tri], "\"suspended\"")))
   {
      if( error)
         *error = [NSString stringWithFormat:@"%llu is not under way", (unsigned long long) a];
      return( nil);
   }
   return( [self end:a status:"aborted" because:why cause:[self startOf:a]]);
}


/* --- suspending and resuming ---------------------------------------------------- */

/* Why the activity can't go on: a bound entity gone, or out of the actor's reach. */
- (NSString *) obstacleTo:(BGEntityID) a
                   record:(const BGActivity *) record
{
   BGEntityID   bound[ 3];
   BGView       *view;
   int          i;

   bound[ 0] = (BGEntityID) record->actorRef;
   bound[ 1] = (BGEntityID) record->itemRef;
   bound[ 2] = (BGEntityID) record->destinationRef;
   if( ! [_world isLive:bound[ 0]])
      return( @"its actor is gone");
   view = [BGView viewOf:bound[ 0] inWorld:_world];
   for( i = 1; i < 3; i++)
   {
      if( ! bound[ i])
         continue;
      if( ! [_world isLive:bound[ i]])
         return( [NSString stringWithFormat:@"%llu is gone", (unsigned long long) bound[ i]]);
      if( ! [view canReach:bound[ i]])
         return( [NSString stringWithFormat:@"%llu is out of reach", (unsigned long long) bound[ i]]);
   }
   return( nil);
}


- (BGProposalGroup *) suspend:(BGEntityID) a
                      because:(NSString *) why
                        error:(NSString **) error
{
   const BGActivity   *record;
   BGProposalGroup    *group;
   int64_t            now;

   record = [_world record:[_world kindNamed:"Activity"] for:a];
   if( ! running( _world, a, record) || ! record->due)
   {
      if( error)
         *error = [NSString stringWithFormat:@"%llu is not a timed activity under way", (unsigned long long) a];
      return( nil);
   }
   now   = [_world time].ms;
   group = [BGProposalGroup groupWithPhase:BGPhaseAction
                                    source:[NSString stringWithFormat:@"activity %llu: suspended (%@)",
                                                                      (unsigned long long) a, why]];
   [group set:"Activity.progress" of:BGWhole( a) to:record->progress + (now - record->started)];
   [group set:"Activity.due" of:BGWhole( a) to:0];
   [self partialOf:a record:record progress:record->progress + (now - record->started) into:group];
   [group set:"Activity.status" of:BGWhole( a) to:tri_type_named( [_world tri], "\"suspended\"")];
   [_committer submit:group];
   return( group);
}


/* What the operation needs, rechecked on resume (ACTIONS.md Scenario 3):
 * its pattern against what is so now; the reason if it no longer holds,
 * else nil. Unknown doesn't block. */
- (NSString *) requirementsOf:(BGEntityID) a
                       record:(const BGActivity *) record
{
   TriMatchResult   result;
   NSString         *why;

   why = nil;
   if( BGMatchAction( _world, action_of( _world, a, record), &result, &why) != TRI_INCOMPATIBLE)
      return( nil);
   return( [NSString stringWithFormat:@"what it needs no longer holds, at %s", result.failure.path]);
}


- (BGProposalGroup *) resume:(BGEntityID) a
                       error:(NSString **) error
{
   const BGActivity   *record;
   BGProposalGroup    *group;
   NSString           *reason;
   NSString           *effect;
   int64_t            duration;
   int64_t            remaining;
   int64_t            now;

   record = [_world record:[_world kindNamed:"Activity"] for:a];
   if( ! record || record->status != (uint32_t) tri_type_named( [_world tri], "\"suspended\""))
   {
      if( error)
         *error = [NSString stringWithFormat:@"%llu is not suspended", (unsigned long long) a];
      return( nil);
   }
   if( (reason = [self obstacleTo:a record:record]) ||
       (reason = BGProvidersBusy( _world, record->actorRef, [_world textField:"Activity.operation" of:a], a)) ||
       (reason = [self requirementsOf:a record:record]) ||
       ! BGOperationStage( _world, [_world textField:"Activity.operation" of:a], record->stage, &duration, &effect))
   {
      if( error)
         *error = reason ? reason : @"it has no stage to resume";
      return( nil);
   }
   now   = [_world time].ms;
   group = [BGProposalGroup groupWithPhase:BGPhaseAction
                                    source:[NSString stringWithFormat:@"activity %llu: resumed", (unsigned long long) a]];
   [group set:"Activity.started" of:BGWhole( a) to:now];
   /* what it owes: the stage, and bringing its instruments to bear as
    * they lie now, less what it did before */
   remaining = duration - record->progress;
   if( record->stage == 0)
      remaining += BGAccessDelay( _world, action_of( _world, a, record));
   [group set:"Activity.due" of:BGWhole( a) to:now + (remaining > 0 ? remaining : 0)];
   [group set:"Activity.status" of:BGWhole( a) to:tri_type_named( [_world tri], "\"running\"")];
   [_committer submit:group];
   return( group);
}


/* Resuming with another instrument in the item role (ACTIONS.md Scenario 3:
 * the wrench gone, the player improvises): the operation's pattern is
 * rechecked with it, and the activity binds it from now on. */
- (BGProposalGroup *) improvise:(BGEntityID) a
                           with:(BGEntityID) instrument
                          error:(NSString **) error
{
   const BGActivity   *record;
   BGProposalGroup    *group;
   TriMatchResult     result;
   BGAction           action;
   NSString           *why;

   record = [_world record:[_world kindNamed:"Activity"] for:a];
   if( ! record || record->status != (uint32_t) tri_type_named( [_world tri], "\"suspended\""))
   {
      if( error)
         *error = [NSString stringWithFormat:@"%llu is not suspended", (unsigned long long) a];
      return( nil);
   }
   action                   = action_of( _world, a, record);
   action.roles[ BGRoleItem] = instrument;
   why                      = nil;
   if( BGMatchAction( _world, action, &result, &why) == TRI_INCOMPATIBLE)
   {
      if( error)
         *error = [NSString stringWithFormat:@"%llu won't do for it: %@", (unsigned long long) instrument,
                                            why ? why : [NSString stringWithUTF8String:result.failure.path]];
      return( nil);
   }
   group = [BGProposalGroup groupWithPhase:BGPhaseAction
                                    source:[NSString stringWithFormat:@"activity %llu: improvised with %llu",
                                                                      (unsigned long long) a, (unsigned long long) instrument]];
   [group set:"Activity.itemRef" of:BGWhole( a) to:(int64_t) instrument];
   [_committer submit:group];
   return( group);
}


- (void) committer:(BGCommitter *) committer
    didCommitRound:(uint32_t) round
        eventsFrom:(NSUInteger) first
                to:(NSUInteger) last
{
   const BGActivity   *record;
   const BGEvent      *ev;
   BGProposalGroup    *group;
   BGStore            *store;
   BGEntityID         ended[ 64];
   BGEntityID         a;
   NSString           *effect;
   NSString           *why;
   NSUInteger         nended;
   NSUInteger         i;
   NSUInteger         j;
   NSUInteger         k;
   BOOL               done;

   /* a completion commitment rejected: the activity failed */
   for( i = 0; i + 1 < [_completions count];)
   {
      group = [_completions objectAtIndex:i];
      a     = (BGEntityID) [[_completions objectAtIndex:i + 1] unsignedLongLongValue];
      if( ! [group position])
      {
         i += 2;
         continue;
      }
      if( ! [group applied])
         [self end:a status:"failed" because:[group rejection] cause:[group cause]];
      [_completions removeObjectsInRange:NSMakeRange( i, 2)];
   }

   /* what this round's events mean for the activities bound to their subjects */
   store  = [_world storeForKind:[_world kindNamed:"Activity"]];
   nended = 0;
   for( i = first; i < last; i++)
   {
      ev = [_world eventAt:i];
      for( j = 0; j < [store count]; j++)
      {
         a      = [store entityAtIndex:j];
         record = [store recordAtIndex:j];
         if( ! running( _world, a, record))
            continue;
         for( done = NO, k = 0; k < nended && ! done; k++)
            done = ended[ k] == a;
         if( done)
            continue;
         effect = BGOperationEffect( _world, [_world textField:"Activity.operation" of:a]);
         if( ! strcmp( ev->kind, "watched") && ev->subject == a && record->watchFloor)
         {
            /* water rising at its feet: an interruption, its watch removed */
            group = [self suspend:a because:@"water is rising at its feet" error:NULL];
            [group set:"Activity.watchFloor" of:BGWhole( a) to:0];
            [group setCause:ev->index];
            ended[ nended++ % 64] = a;
         }
         else if( ! strcmp( ev->kind, "watched") && ev->subject == a)
         {
            [self end:a status:"completed" because:@"its watch fired" cause:ev->index];
            ended[ nended++ % 64] = a;
         }
         else if( ! strcmp( ev->kind, "exhausted") && ev->subject == (BGEntityID) record->itemRef &&
                  [effect isEqualToString:@"fill"])
         {
            [self end:a status:"exhausted" because:@"the source ran dry" cause:ev->index];
            ended[ nended++ % 64] = a;
         }
         else if( record->due && (ev->subject == (BGEntityID) record->actorRef || ev->subject == (BGEntityID) record->itemRef ||
                                  ev->subject == (BGEntityID) record->destinationRef) &&
                  ((why = [self obstacleTo:a record:record]) || (why = [self requirementsOf:a record:record])))
         {
            /* a hard interruption: what it binds is gone or out of reach, or
             * what it needs no longer holds (the saw out of its hand): it is
             * suspended, or fails, as its stage declares */
            if( BGOperationFailsHard( _world, [_world textField:"Activity.operation" of:a], record->stage))
               [self end:a status:"failed" because:why cause:ev->index];
            else
            {
               group = [self suspend:a because:why error:NULL];
               [group setCause:ev->index];
            }
            ended[ nended++ % 64] = a;
         }
      }
   }
}

@end

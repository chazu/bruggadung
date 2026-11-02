#import "BGActivities.h"
#import "BGReality.h"

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
   [world setActivityObserver:activities];
   return( activities);
}


- (void) dealloc
{
   if( [_world activityObserver] == self)
      [_world setActivityObserver:nil];
   free( _timers);
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
   BGAction     action;
   const char   *words;

   action = BGActionMake( [world textField:"Activity.operation" of:a], (BGEntityID) record->actorRef,
                          (BGEntityID) record->itemRef, (BGEntityID) record->destinationRef);
   words  = [world textField:"Activity.words" of:a];
   if( words && *words)
      action.content = words;
   return( action);
}


/* --- partial effects ---------------------------------------------------------- */

/* The stage's progress at `t`: kept, plus its running since it started. */
static int64_t   progress_at( const BGActivity *record, int64_t t)
{
   int64_t   rate;

   rate = record->pace > 0 ? record->pace : 100;
   return( record->progress + (record->due ? (t - record->started) * rate / 100 : 0));
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
      at = record->started + BGAtRate( duration * k / (n + 1) - record->progress, record->pace);
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

static BOOL   has_ended( const BGActivity *record)
{
   return( record->status != BG_ACTIVITYSTATUS_RUNNING && record->status != BG_ACTIVITYSTATUS_SUSPENDED);
}


static int   cmp_actor( const void *a, const void *b)
{
   BGEntityID   x;
   BGEntityID   y;

   x = *(const BGEntityID *) a;
   y = *(const BGEntityID *) b;
   return( x < y ? -1 : x > y);
}


/* Whether an ended activity is still asked of: its actor's latest, or, per
 * operation, the completed one that started last (an agent asks whether it
 * did a thing since a time, which only that one can answer). */
- (BOOL) keeps:(BGEntityID) b
     among:(const BGEntityID *) mine
     count:(NSUInteger) n
{
   const BGActivity   *record;
   const BGActivity   *other;
   const char         *op;
   const char         *otherOp;
   NSUInteger         i;

   if( b == mine[ n - 1])
      return( YES);
   record = [_world record:[_world kindNamed:"Activity"] for:b];
   if( record->status != BG_ACTIVITYSTATUS_COMPLETED)
      return( NO);
   op = [_world textField:"Activity.operation" of:b];
   for( i = 0; i < n; i++)
   {
      if( mine[ i] == b || ! (other = [_world record:[_world kindNamed:"Activity"] for:mine[ i]]) ||
          other->status != BG_ACTIVITYSTATUS_COMPLETED)
         continue;
      otherOp = [_world textField:"Activity.operation" of:mine[ i]];
      if( op && otherOp && ! strcmp( op, otherOp) &&
          (other->started > record->started || (other->started == record->started && mine[ i] > b)))
         return( NO);
   }
   return( YES);
}


/* Lets go of an actor's activities that have ended and that nothing asks
 * of any more, in a group of its own: the Activity store holds what is
 * under way, and what is still asked of, not all that ever was. Done in the
 * round its activities ended, read from the world then; the group, if not
 * yet committed, is saved with the deferred, so a game saved and resumed
 * lets go of the same. */
- (void) letGoOf:(BGEntityID) actor
{
   const BGActivity   *record;
   BGProposalGroup    *group;
   BGEntityID         *mine;
   NSUInteger         n;
   NSUInteger         j;

   group = nil;
   mine  = [_world copyActivitiesOf:actor count:&n];
   for( j = 0; j < n; j++)
   {
      record = [_world record:[_world kindNamed:"Activity"] for:mine[ j]];
      if( ! has_ended( record) || [self keeps:mine[ j] among:mine count:n])
         continue;
      if( ! group)
         group = [BGProposalGroup groupWithPhase:BGPhaseSystem
                                          source:[NSString stringWithFormat:@"activities: %llu's ended let go",
                                                                            (unsigned long long) actor]];
      [group destroy:BGWhole( mine[ j]) reason:"ended"];
   }
   free( mine);
   if( group)
      [_committer submit:group];
}


/* The actors whose activities ended in a round's events, each once. */
- (void) letGoAfter:(NSUInteger) first
                 to:(NSUInteger) last
{
   const BGActivity   *record;
   const BGEvent      *ev;
   BGEntityID         *actors;
   NSUInteger         nactors;
   NSUInteger         i;

   actors  = malloc( (last - first + 1) * sizeof( BGEntityID));
   nactors = 0;
   for( i = first; i < last; i++)
   {
      ev = [_world eventAt:i];
      if( strcmp( ev->kind, "changed") || ! ev->detail || strcmp( ev->detail, "Activity.status") ||
          ! (record = [_world record:[_world kindNamed:"Activity"] for:ev->subject]) || ! has_ended( record))
         continue;
      actors[ nactors++] = (BGEntityID) record->actorRef;
   }
   qsort( actors, nactors, sizeof( BGEntityID), cmp_actor);
   for( i = 0; i < nactors; i++)
      if( ! i || actors[ i] != actors[ i - 1])
         [self letGoOf:actors[ i]];
   free( actors);
}


/* --- the timers ------------------------------------------------------------- */

/* When a running activity is next due, as of `t`: its stage's end, or a
 * checkpoint before; never, not running. */
- (int64_t) dueOf:(BGEntityID) a
            after:(int64_t) t
{
   const BGActivity   *record;
   int64_t            at;
   int64_t            check;

   record = [_world record:[_world kindNamed:"Activity"] for:a];
   if( ! running( _world, a, record))
      return( BGTimeNever.ms);
   /* its actor frozen (REALITY.md step 4): it waits, and is told when it rises */
   if( [_world detailOf:(BGEntityID) record->actorRef] == BGDetailFrozen)
      return( BGTimeNever.ms);
   at    = record->due > 0 ? record->due : BGTimeNever.ms;
   check = next_checkpoint( _world, a, record, t);
   return( check < at ? check : at);
}


static BOOL   timer_before( const BGActivityTimer *x, const BGActivityTimer *y)
{
   return( x->at < y->at || (x->at == y->at && x->activity < y->activity));
}


- (void) push:(BGEntityID) a
           at:(int64_t) at
{
   BGActivityTimer   t;
   NSUInteger        i;

   if( at == BGTimeNever.ms)
      return;
   if( _ntimers == _timercap)
   {
      _timercap = _timercap ? _timercap * 2 : 64;
      _timers   = realloc( _timers, _timercap * sizeof( BGActivityTimer));
   }
   _timers[ _ntimers].at       = at;
   _timers[ _ntimers].activity = a;
   for( i = _ntimers++; i && timer_before( &_timers[ i], &_timers[ (i - 1) / 2]); i = (i - 1) / 2)
   {
      t                    = _timers[ i];
      _timers[ i]          = _timers[ (i - 1) / 2];
      _timers[ (i - 1) / 2] = t;
   }
}


- (BGActivityTimer) pop
{
   BGActivityTimer   top;
   BGActivityTimer   t;
   NSUInteger        i;
   NSUInteger        c;

   top         = _timers[ 0];
   _timers[ 0] = _timers[ --_ntimers];
   for( i = 0;; i = c)
   {
      c = 2 * i + 1;
      if( c >= _ntimers)
         break;
      if( c + 1 < _ntimers && timer_before( &_timers[ c + 1], &_timers[ c]))
         c++;
      if( ! timer_before( &_timers[ c], &_timers[ i]))
         break;
      t           = _timers[ i];
      _timers[ i] = _timers[ c];
      _timers[ c] = t;
   }
   return( top);
}


/* The timers, from the store, the first time they are wanted. */
- (void) time
{
   BGStore      *store;
   NSUInteger   i;

   if( _timed)
      return;
   _timed = YES;
   store  = [_world storeForKind:[_world kindNamed:"Activity"]];
   for( i = 0; i < [store count]; i++)
      [self push:[store entityAtIndex:i]
              at:[self dueOf:[store entityAtIndex:i] after:[_world time].ms]];
}


/* The world's word: an activity changed, so when it is due may have. */
- (void) world:(id) world
 changedRecord:(BGEntityID) entity
          kind:(NSUInteger) kind
{
   if( _timed)
      [self push:entity
              at:[self dueOf:entity after:[_world time].ms]];
}


/* The earliest timer that is still so: a stale one (the activity ended, or
 * due another time now) let go, its due time pushed again. */
- (BGTime) nextCompletion
{
   BGActivityTimer   top;
   int64_t           at;

   [self time];
   while( _ntimers)
   {
      top = _timers[ 0];
      at  = [self dueOf:top.activity after:[_world time].ms];
      if( at == top.at)
         return( BGTimeMake( at));
      [self pop];
      [self push:top.activity at:at];      /* again, if it is due at all */
   }
   return( BGTimeNever);
}


- (void) completeDueAt:(BGTime) t
{
   const BGActivity   *record;
   BGProposalGroup    *group;
   BGEntityID         *due;
   BGEntityID         a;
   NSString           *reason;
   NSString           *effect;
   const char         *operation;
   NSUInteger         ndue;
   NSUInteger         i;
   int64_t            duration;
   int64_t            rate;
   BOOL               more;

   /* what is due by now, from the timers, in entity order; each pushed
    * again for its next */
   [self time];
   due  = malloc( (_ntimers + 1) * sizeof( BGEntityID));
   ndue = 0;
   while( _ntimers && _timers[ 0].at <= t.ms)
      due[ ndue++] = [self pop].activity;
   qsort( due, ndue, sizeof( BGEntityID), cmp_actor);
   for( i = 0; i < ndue; i++)
   {
      if( i && due[ i] == due[ i - 1])
         continue;
      a      = due[ i];
      record = [_world record:[_world kindNamed:"Activity"] for:a];
      [self push:a at:[self dueOf:a after:t.ms]];
      if( ! record || ! record->due || ! running( _world, a, record))
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
      [group setWeight:BGContestWeight( _world, (BGEntityID) record->actorRef, operation)];
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
      /* the stage's own traces, with its effect */
      BGLeaveStageTraces( _world, action_of( _world, a, record), record->stage, group);
      if( BGOperationStage( _world, operation, record->stage + 1, &duration, &effect))
      {
         /* the next stage starts now */
         [group set:"Activity.stage" of:BGWhole( a) to:record->stage + 1];
         [group set:"Activity.progress" of:BGWhole( a) to:0];
         [group set:"Activity.started" of:BGWhole( a) to:t.ms];
         rate = BGGradedRate( _world, action_of( _world, a, record),
                              BGWorkRate( _world, (BGEntityID) record->actorRef, operation, record->stage + 1));
         [group set:"Activity.pace" of:BGWhole( a) to:rate];
         [group set:"Activity.due" of:BGWhole( a) to:t.ms + BGAtRate( duration, rate)];
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
   free( due);
}


/* The event that created the activity: what its completion follows from. */
- (uint64_t) startOf:(BGEntityID) a
{
   return( [_world creationOf:a]);
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
   [group set:"Activity.progress" of:BGWhole( a) to:progress_at( record, now)];
   [group set:"Activity.due" of:BGWhole( a) to:0];
   [self partialOf:a record:record progress:progress_at( record, now) into:group];
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
   int64_t            rate;
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
   rate      = BGGradedRate( _world, action_of( _world, a, record),
                             BGWorkRate( _world, (BGEntityID) record->actorRef,
                                         [_world textField:"Activity.operation" of:a], record->stage));
   remaining = BGAtRate( duration - record->progress, rate);
   if( record->stage == 0)
      remaining += BGAccessDelay( _world, action_of( _world, a, record));
   [group set:"Activity.pace" of:BGWhole( a) to:rate];
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


/* A rate input changed (ACTIONS.md §5: "A change to any rate input ...
 * recomputes it"): the stage under way keeps what it has done, and goes on
 * from now at the actor's pace now. */
- (void) repace:(BGEntityID) a
         record:(const BGActivity *) record
          cause:(uint64_t) cause
{
   BGProposalGroup   *group;
   NSString          *effect;
   const char        *operation;
   int64_t           duration;
   int64_t           pace;
   int64_t           done;
   int64_t           now;

   operation = [_world textField:"Activity.operation" of:a];
   if( ! BGOperationStage( _world, operation, record->stage, &duration, &effect))
      return;
   pace = BGGradedRate( _world, action_of( _world, a, record),
                        BGWorkRate( _world, (BGEntityID) record->actorRef, operation, record->stage));
   if( pace == (record->pace > 0 ? record->pace : 100))
      return;
   now   = [_world time].ms;
   done  = progress_at( record, now);
   group = [BGProposalGroup groupWithPhase:BGPhaseAction
                                    source:[NSString stringWithFormat:@"activity %llu: its pace now %lld%%",
                                                                      (unsigned long long) a, (long long) pace]];
   [group setCause:cause];
   [group set:"Activity.progress" of:BGWhole( a) to:done];
   [group set:"Activity.started" of:BGWhole( a) to:now];
   [group set:"Activity.pace" of:BGWhole( a) to:pace];
   [group set:"Activity.due" of:BGWhole( a) to:now + BGAtRate( duration > done ? duration - done : 0, pace)];
   [_committer submit:group];
}


static BOOL   contains_id( const BGEntityID *list, NSUInteger n, BGEntityID e)
{
   NSUInteger   i;

   for( i = 0; i < n; i++)
      if( list[ i] == e)
         return( YES);
   return( NO);
}


/* An activity ended this round, kept to be told of once. */
static BGEntityID   *remember_ended( BGEntityID *ended, NSUInteger *n, NSUInteger *cap, BGEntityID a)
{
   if( *n == *cap)
   {
      *cap  = *cap ? *cap * 2 : 64;
      ended = realloc( ended, *cap * sizeof( BGEntityID));
   }
   ended[ (*n)++] = a;
   return( ended);
}


- (void) committer:(BGCommitter *) committer
    didCommitRound:(uint32_t) round
        eventsFrom:(NSUInteger) first
                to:(NSUInteger) last
{
   const BGActivity   *record;
   const BGEvent      *ev;
   BGProposalGroup    *group;
   BGEntityID         *ended;
   BGEntityID         *touching;
   NSUInteger         ntouching;
   NSUInteger         endedcap;
   BGEntityID         a;
   NSString           *effect;
   NSString           *why;
   NSUInteger         nended;
   NSUInteger         i;
   NSUInteger         j;
   NSUInteger         k;
   BOOL               done;

   ended     = NULL;
   endedcap  = 0;
   touching  = NULL;
   ntouching = 0;

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

   /* what this round's events mean for the activities bound to their
    * subjects: those it takes part in (the world's index), in entity
    * order, then the subject itself, if it is an activity */
   nended = 0;
   for( i = first; i < last; i++)
   {
      ev       = [_world eventAt:i];
      touching = ev->subject ? [_world copyActivitiesTouching:ev->subject count:&ntouching] : NULL;
      for( j = 0; j <= ntouching; j++)
      {
         /* then the subject itself, if it is an activity */
         if( j == ntouching)
            a = [_world record:[_world kindNamed:"Activity"] for:ev->subject] &&
                ! contains_id( touching, ntouching, ev->subject) ? ev->subject : BGNoEntity;
         else
            a = touching[ j];
         if( ! a || ! (record = [_world record:[_world kindNamed:"Activity"] for:a]) || ! running( _world, a, record))
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
            ended = remember_ended( ended, &nended, &endedcap, a);
         }
         else if( ! strcmp( ev->kind, "watched") && ev->subject == a)
         {
            [self end:a status:"completed" because:@"its watch fired" cause:ev->index];
            ended = remember_ended( ended, &nended, &endedcap, a);
         }
         else if( ! strcmp( ev->kind, "exhausted") && ev->subject == (BGEntityID) record->itemRef &&
                  [effect isEqualToString:@"fill"])
         {
            [self end:a status:"exhausted" because:@"the source ran dry" cause:ev->index];
            ended = remember_ended( ended, &nended, &endedcap, a);
         }
         else if( record->due && ev->subject == (BGEntityID) record->actorRef && ! strcmp( ev->kind, "changed") &&
                  ev->detail && (! strcmp( ev->detail, "Agent.fatigue") || ! strcmp( ev->detail, "Agent.injury")))
            [self repace:a record:record cause:ev->index];
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
            ended = remember_ended( ended, &nended, &endedcap, a);
         }
      }
      free( touching);
      touching  = NULL;
      ntouching = 0;
   }
   free( ended);
   /* what ended in the round, let go of */
   [self letGoAfter:first to:last];
}

@end

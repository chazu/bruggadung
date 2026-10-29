#import "BGActivities.h"

#import "BGActions.h"
#import "BGProposalGroup.h"


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
   NSUInteger         i;

   store = [_world storeForKind:[_world kindNamed:"Activity"]];
   for( i = 0; i < [store count]; i++)
   {
      record = [store recordAtIndex:i];
      a      = [store entityAtIndex:i];
      if( ! record->due || record->due > t.ms || ! running( _world, a, record))
         continue;
      group  = [BGProposalGroup groupWithPhase:BGPhaseAction
                                        source:[NSString stringWithFormat:@"activity %llu: %s completes",
                                                                          (unsigned long long) a,
                                                                          [_world textField:"Activity.operation" of:a]]];
      reason = BGApplyEffect( _world, action_of( _world, a, record), record->amount, group);
      if( reason)
      {
         [self end:a status:"failed" because:reason];
         continue;
      }
      [group set:"Activity.status" of:BGWhole( a) to:tri_type_named( [_world tri], "\"completed\"")];
      [_committer submit:group];
      [_completions addObject:group];
      [_completions addObject:[NSNumber numberWithUnsignedLongLong:a]];
   }
}


/* --- ending ------------------------------------------------------------------- */

/* Ends an activity: its operation's own clean-up (a fill closes its tap), the
 * status, and the watch removed. */
- (void) end:(BGEntityID) a
      status:(const char *) status
     because:(NSString *) why
{
   const BGActivity   *record;
   BGProposalGroup    *group;
   char               atom[ 32];

   record = [_world record:[_world kindNamed:"Activity"] for:a];
   if( ! record)
      return;
   group = [BGProposalGroup groupWithPhase:BGPhaseSystem
                                    source:[NSString stringWithFormat:@"activity %llu: %s (%@)",
                                                                      (unsigned long long) a, status, why]];
   if( [BGOperationEffect( _world, [_world textField:"Activity.operation" of:a]) isEqualToString:@"fill"])
      [group set:"Tap.open" of:BGWhole( (BGEntityID) record->itemRef) to:0];
   snprintf( atom, sizeof( atom), "\"%s\"", status);
   [group set:"Activity.status" of:BGWhole( a) to:tri_type_named( [_world tri], atom)];
   if( record->watchHolder)
      [group set:"Activity.watchHolder" of:BGWhole( a) to:0];
   [_committer submit:group];
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
         [self end:a status:"failed" because:[group rejection]];
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
         if( ! strcmp( ev->kind, "watched") && ev->subject == a)
         {
            [self end:a status:"completed" because:@"its watch fired"];
            ended[ nended++ % 64] = a;
         }
         else if( ! strcmp( ev->kind, "exhausted") && ev->subject == (BGEntityID) record->itemRef &&
                  [effect isEqualToString:@"fill"])
         {
            [self end:a status:"exhausted" because:@"the source ran dry"];
            ended[ nended++ % 64] = a;
         }
      }
   }
}

@end

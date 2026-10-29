#import "BGBodyKind.h"


@implementation BGBodyKind

- (void) committer:(BGCommitter *) committer
     reactToEvent:(const BGEvent *) event
            world:(BGWorld *) world
{
   BGProposalGroup   *group;
   BGEntityID        here[ 256];
   const char        *unit;
   NSUInteger        i;
   NSUInteger        n;

   if( strcmp( event->kind, "moved") || event->location.form != BGLocationIn)
      return;
   if( ! [world isLive:event->subject] || ! (unit = [world unitOf:event->subject]))
      return;
   /* the lowest-numbered stack of the same unit already there */
   n = [world entitiesAt:event->location.place
                    form:BGLocationIn
                    into:here
                     max:256];
   for( i = 0; i < n && i < 256; i++)
   {
      if( here[ i] == event->subject || ! [world isStack:here[ i]] || strcmp( [world unitOf:here[ i]], unit))
         continue;
      group = [BGProposalGroup groupWithPhase:BGPhaseSystem
                                       source:[NSString stringWithFormat:@"Body reaction: merge %llu into %llu",
                                                                         (unsigned long long) event->subject,
                                                                         (unsigned long long) here[ i]]];
      [group setCause:event->index];
      [group merge:BGWhole( event->subject)
              into:BGWhole( here[ i])];
      [committer submit:group];
      return;
   }
}

@end

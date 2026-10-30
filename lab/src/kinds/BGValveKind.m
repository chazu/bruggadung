#import "BGValveKind.h"

#import "BGProposalGroup.h"
#import "BGActions.h"


@implementation BGValveKind

- (void) committer:(BGCommitter *) committer
     reactToEvent:(const BGEvent *) event
            world:(BGWorld *) world
{
   const BGValve     *valve;
   BGProposalGroup   *g;
   int64_t           loosened;

   valve = [world record:[world kindNamed:"Valve"] for:event->subject];
   if( ! valve)
      return;
   if( ! strcmp( event->kind, "torqued"))
   {
      g = [BGProposalGroup groupWithPhase:BGPhaseSystem
                                   source:[NSString stringWithFormat:@"valve %llu: %lld Nm against %lld Nm: %s (%s)",
                                                                     (unsigned long long) event->subject,
                                                                     (long long) event->amount / 1000,
                                                                     (long long) valve->breakaway / 1000,
                                                                     event->amount >= valve->breakaway ? "turns" : "holds",
                                                                     event->detail ? event->detail : "no expectation"]];
      [g setCause:event->index];
      if( event->amount >= valve->breakaway && ! valve->turned)
      {
         /* it breaks free, with a creak */
         [g set:"Valve.turned" of:BGWhole( event->subject) to:1];
         BGMakeTrace( world, g, "creak", event->subject, BGLocationMakeNone(), 60, "a valve breaking free");
      }
      else
         [g emit:"held" subject:BGWhole( event->subject) other:BGWhole( event->other)];
      [committer submit:g];
      return;
   }
   if( ! strcmp( event->kind, "struck") && ! valve->turned)
   {
      loosened = valve->breakaway - event->amount;
      if( loosened < valve->rating)
         loosened = valve->rating;
      g = [BGProposalGroup groupWithPhase:BGPhaseSystem
                                   source:[NSString stringWithFormat:@"valve %llu: struck, breaks free at %lld Nm now",
                                                                     (unsigned long long) event->subject,
                                                                     (long long) loosened / 1000]];
      [g setCause:event->index];
      [g set:"Valve.breakaway" of:BGWhole( event->subject) to:loosened];
      [committer submit:g];
   }
}

@end

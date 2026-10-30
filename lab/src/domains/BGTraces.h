/*
 * BGTraces — the trace system (KNOWLEDGE.md §3). Traces are component state
 * on informational entities (content/traces.tri), made and removed only by
 * the operations that declare them, in their effects' groups. Aging is
 * analytic: a trace's strength is computed from its age when it is read,
 * fading evenly from its magnitude to nothing at its `expires`. This domain
 * costs nothing between: its horizon's next event is the earliest moment a
 * trace is gone (below its kind's floor, or expired), and at that boundary
 * it removes what is gone.
 */
#import "BGScheduler.h"


/* How strong the trace is at `t`: its magnitude, faded evenly to 0 at its
 * expiry. */
int64_t   BGTraceStrength( const BGTrace *trace, int64_t t);
/* When it is gone (KNOWLEDGE.md §3): the first moment its strength is below
 * its kind's floor (traces.tri), or its expiry. */
int64_t   BGTraceGone( BGWorld *world, const BGTrace *trace);


@interface BGTraces : NSObject <BGDomain>
{
   BGWorld   *_world;
}

- (id) initWithWorld:(BGWorld *) world;

@end

/*
 * BGScheduler — the boundary loop of ARCHITECTURE.md ("The life of one
 * boundary") and DOMAIN_SIMULATION.md §9. Each step is bounded by the run
 * policy's stop time, the next input, and every active domain's horizon;
 * domains advance to the bound; inputs due then are delivered; change
 * commitment runs; the clock moves to the bound. A quiet world jumps.
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGCommitter.h"


/* How far a domain may advance: a safe step (a duration) and the time of its
 * next possible discrete event. */
typedef struct
{
   BGTime   safeStep;
   BGTime   nextEvent;
} BGHorizon;

/* A domain, at the scheduler's boundary (DOMAIN_SIMULATION.md §13). Inner
 * loops are its own C; the protocol is only the boundary. */
@protocol BGDomain

- (NSString *) name;
- (BOOL) isActive;
- (BGHorizon) horizonAt:(BGTime) t;
/* Advances from t0 to t1 and submits its discrete proposals for t1. */
- (void) advanceFrom:(BGTime) t0
                  to:(BGTime) t1
               world:(BGWorld *) world
           committer:(BGCommitter *) committer;

@end

/* Where inputs come from: scripted scenarios now, the player later. The
 * input log is the replay log. */
@protocol BGInputSource

- (BGTime) nextInputTime;            /* BGTimeNever when there are none */
- (void) deliverInputsAt:(BGTime) t
                   world:(BGWorld *) world
               committer:(BGCommitter *) committer;

@end

@class BGScheduler;

@protocol BGSchedulerObserver

- (void) scheduler:(BGScheduler *) scheduler
 didCommitBoundary:(uint64_t) boundary
            groups:(NSArray *) groups;

@end


@interface BGScheduler : NSObject
{
   BGWorld                      *_world;
   BGCommitter                  *_committer;
   NSMutableArray               *_domains;
   id <BGInputSource>           _inputs;
   id <BGSchedulerObserver>     _observer;
}

- (id) initWithWorld:(BGWorld *) world
           committer:(BGCommitter *) committer;

- (void) addDomain:(id <BGDomain>) domain;
- (void) setInputs:(id <BGInputSource>) inputs;          /* not retained */
- (void) setObserver:(id <BGSchedulerObserver>) observer; /* not retained */

/* The time the next boundary would be at, if nothing stops it first. */
- (BGTime) nextBoundaryTime;
/* Runs one boundary, at most at `stop`. NO when there is nothing to do
 * before `stop`. */
- (BOOL) stepUntil:(BGTime) stop;
/* The run policy for now: run boundaries until `stop`, then set the clock
 * to `stop`. Returns the number of boundaries run. */
- (NSUInteger) runUntil:(BGTime) stop;

@end

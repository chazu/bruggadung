/*
 * BGCistern — DOMAIN_SIMULATION.md Scenario 3, "Two draws on a dwindling
 * stock": a cistern with 15 L, two taps at 5 L/min with a bucket under each,
 * and a crack leaking 0.5 L/min onto the floor. Agents A and B open their
 * taps; the cistern runs dry; the water ends up in the buckets and on the
 * floor, exactly.
 *
 *   base: A and B open their taps at the same time
 *   3b:   A opens a minute earlier, and gets more
 *   3d:   the domain holds its participants in the reverse order inside;
 *         the run must be bit-identical to the base
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGCommitter.h"
#import "BGScheduler.h"
#import "BGFluidDomain.h"


typedef enum
{
   BGCisternBase,
   BGCisternEarlier,         /* 3b */
   BGCisternReversed         /* 3d */
} BGCisternVariant;


@interface BGCistern : NSObject <BGInputSource, BGSchedulerObserver>
{
   BGCisternVariant   _variant;
   BGWorld            *_world;
   BGCommitter        *_committer;
   BGScheduler        *_scheduler;
   BGFluidDomain      *_fluid;
   NSMutableArray     *_results;
   NSMutableArray     *_groups;
   int64_t            _times[ 256];      /* boundary → time */
   NSUInteger         _next;
   BOOL               _conserved;
   BOOL               _neverNegative;
   NSString           *_firstProblem;

   BGEntityID         _cistern;
   BGEntityID         _tapA;
   BGEntityID         _tapB;
   BGEntityID         _crack;
   BGEntityID         _bucketA;
   BGEntityID         _bucketB;
   BGEntityID         _agentA;
   BGEntityID         _agentB;
   BGProposalGroup    *_setup;
}

+ (NSString *) nameOf:(BGCisternVariant) variant;

- (id) initWithWorld:(BGWorld *) world
           committer:(BGCommitter *) committer
             variant:(BGCisternVariant) variant;

- (void) run;
/* only the boundaries up to a time, without the final checks */
- (void) runUntil:(BGTime) t;
/* carry on in a world restored from a save of this one, with a fresh fluid
 * domain given the save's domain state; then finish and check */
- (void) resumeWithWorld:(BGWorld *) world
               committer:(BGCommitter *) committer
              fluidState:(NSArray *) state;
- (void) finish;

- (BGWorld *) world;
- (BGCommitter *) committer;
- (BGFluidDomain *) fluid;
- (NSArray *) results;
- (NSUInteger) failureCount;
/* the total water: at rest in stores and tiles, plus what the domain has out */
- (int64_t) totalWater;

@end

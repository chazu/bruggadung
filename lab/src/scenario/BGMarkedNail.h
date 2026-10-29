/*
 * BGMarkedNail — COMPONENTS.md Scenario 1, "The marked nail", run headless
 * from a scripted input log, with its acceptance checks.
 *
 *   base: the worker takes 5 nails, hammers one into a lock (marking it),
 *         pulls it out, and drops all 5 back: 4 merge, the bent one can't
 *   A:    the same with an unmarked nail, which merges back too
 *   B:    mixed goods: the worker pours their own 10 nails into the smith's
 *         bin, then takes 5; the two quantity claims sum, then can't be
 *         allocated
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGCommitter.h"
#import "BGScheduler.h"
#import "BGActivities.h"


typedef enum
{
   BGMarkedNailBase,
   BGMarkedNailUnmarked,        /* variant A */
   BGMarkedNailMixedGoods       /* variant B */
} BGMarkedNailVariant;


@interface BGMarkedNail : NSObject <BGInputSource, BGSchedulerObserver>
{
   BGMarkedNailVariant   _variant;
   BGWorld               *_world;
   BGCommitter           *_committer;
   BGScheduler           *_scheduler;
   BGActivities          *_activities;
   NSUInteger            _next;
   NSMutableArray        *_results;
   NSMutableArray        *_groups;        /* every group processed, in order */
   int64_t               _mass;           /* totals after setup */
   int64_t               _nails;
   BOOL                  _invariantsHeld;

   BGEntityID            _bin;
   BGEntityID            _stack;
   BGEntityID            _lock;
   BGEntityID            _worker;
   BGEntityID            _smith;
   BGEntityID            _claim;
   BGEntityID            _workerStack;
   BGEntityID            _workerClaim;
   BGEntityID            _handful;
   BGEntityID            _nail;
   BGProposalGroup       *_explicitMerge;

   /* names waiting for their group to apply: the group, and the name's ivar */
   BGProposalGroup       *_pendingGroups[ 16];
   BGEntityID            *_pendingNames[ 16];
   NSUInteger            _npending;
}

+ (NSString *) nameOf:(BGMarkedNailVariant) variant;

- (id) initWithWorld:(BGWorld *) world
           committer:(BGCommitter *) committer
             variant:(BGMarkedNailVariant) variant;

/* Runs the input log to its end, then the final checks. */
- (void) run;
/* The same in parts: run boundaries up to a time; carry on in another world
 * (restored from a save of this one); finish and check. */
- (void) runUntil:(BGTime) t;
- (void) resumeWithWorld:(BGWorld *) world
               committer:(BGCommitter *) committer;
- (void) finish;

- (BGWorld *) world;
- (BGCommitter *) committer;
/* "ok <check>" or "FAIL <check>: <why>", in the order they were made */
- (NSArray *) results;
- (NSUInteger) failureCount;

@end

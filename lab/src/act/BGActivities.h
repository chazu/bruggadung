/*
 * BGActivities — activities under way (ACTIONS.md §5). An activity is an
 * entity with an Activity component, started by BGPerform. This is the
 * engine machinery that ends them:
 *
 *   - a timed activity completes a stage at its due time: the stage's effect
 *     commits then, and the next stage starts; if commitment rejects it, the
 *     activity fails
 *   - a running timed activity whose bound entities are gone or out of the
 *     actor's reach, or whose operation's pattern no longer holds, is
 *     suspended, or fails, as its stage declares (a hard interruption,
 *     ACTIONS.md §5)
 *   - an activity with a watch completes when its domain reports the watch
 *     ("watched", from the fluid domain)
 *   - a fill ends, "exhausted", when its tap reports its source ran dry
 *   - a stage whose progress shows in the world (ACTIONS.md §5's partial
 *     effects) commits it in proportion at its checkpoints, which bound
 *     steps, and when it is suspended, aborted, or fails
 *
 * It follows each commit round (a round listener) and bounds the
 * scheduler's steps by the next completion (an activity clock).
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGCommitter.h"
#import "BGScheduler.h"


/* An activity's next time due: a stage ending, or a checkpoint. */
typedef struct
{
   int64_t      at;
   BGEntityID   activity;
} BGActivityTimer;


@interface BGActivities : NSObject <BGActivityClock, BGRoundListener, BGRecordObserver>
{
   BGWorld           *_world;
   BGCommitter       *_committer;       /* not retained: the committer retains us */
   NSMutableArray    *_completions;     /* pairs: the group, the activity */
   /* when each running activity is next due, a heap, earliest first; an
    * entry may be stale, and is checked against the record when it comes
    * up. Built from the store when first wanted, kept by the world's word
    * of every change: not saved */
   BGActivityTimer   *_timers;
   NSUInteger        _ntimers;
   NSUInteger        _timercap;
   BOOL              _timed;
}

/* Creates the activity system and registers it with the committer. */
+ (instancetype) activitiesWithWorld:(BGWorld *) world
                           committer:(BGCommitter *) committer;

/* The actor's choice, through commitment: suspending keeps the stage's
 * progress; resuming rechecks that everything bound is still there and in
 * reach, and runs what is left of the stage. nil, with the reason, if it
 * can't. */
- (BGProposalGroup *) suspend:(BGEntityID) activity
                      because:(NSString *) why
                        error:(NSString **) error;
- (BGProposalGroup *) resume:(BGEntityID) activity
                       error:(NSString **) error;
/* Another instrument for its item role, when what it had is gone: the
 * operation rechecked with it, and bound from now on; resume after. */
- (BGProposalGroup *) improvise:(BGEntityID) activity
                           with:(BGEntityID) instrument
                          error:(NSString **) error;
/* The actor's choice to give it up: its progress is discarded, what it
 * showed of it stays. */
- (BGProposalGroup *) abort:(BGEntityID) activity
                    because:(NSString *) why
                      error:(NSString **) error;

@end

/*
 * BGActivities — activities under way (ACTIONS.md §5). An activity is an
 * entity with an Activity component, started by BGPerform. This is the
 * engine machinery that ends them:
 *
 *   - a timed activity completes a stage at its due time: the stage's effect
 *     commits then, and the next stage starts; if commitment rejects it, the
 *     activity fails
 *   - a running timed activity whose bound entities are gone or out of the
 *     actor's reach is suspended (a hard interruption, ACTIONS.md §5)
 *   - an activity with a watch completes when its domain reports the watch
 *     ("watched", from the fluid domain)
 *   - a fill ends, "exhausted", when its tap reports its source ran dry
 *
 * It follows each commit round (a round listener) and bounds the
 * scheduler's steps by the next completion (an activity clock).
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGCommitter.h"
#import "BGScheduler.h"


@interface BGActivities : NSObject <BGActivityClock, BGRoundListener>
{
   BGWorld          *_world;
   BGCommitter      *_committer;       /* not retained: the committer retains us */
   NSMutableArray   *_completions;     /* pairs: the group, the activity */
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

@end

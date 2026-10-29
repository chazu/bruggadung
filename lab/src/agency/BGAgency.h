/*
 * BGAgency — agents that choose for themselves (AGENCY.md), first slice. In
 * the decision phase after perception, each agent agency controls, and that
 * has no activity under way, decides one step from its intention, reading
 * only its own knowledge store (the knowledge view). Everything it does is an
 * action, through the menu's machinery.
 *
 * The slice has one commitment and one instrumental goal, written in code
 * against the knowledge view (AGENCY.md wants methods in content; that is the
 * next step):
 *
 *   wedge the lock: nails in hand, then drive one into the lock; to get
 *     nails, go to where they are believed to be and take one
 *   seek nails: when no nails are believed anywhere reachable, look into the
 *     containers the agent knows of, in the order of its belief (where it
 *     last saw nails first, then by recency, then by distance); when nowhere
 *     is left, the commitment is believed impossible for now and dropped,
 *     with the reason
 *
 * Each agent's motivation store (its intentions, the places searched, the
 * decision count) is private and saved, and every decision is logged for the
 * developer.
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGCommitter.h"
#import "BGScheduler.h"
#import "BGKnowledge.h"


typedef enum
{
   BGGoalWedgeLock = 1,
   BGGoalSeekNails
} BGGoal;

#define BG_MAX_GOALS     4
#define BG_MAX_SEARCHED  32


@interface BGMotivation : NSObject
{
@public
   BGEntityID       agent;
   BGGoal           goals[ BG_MAX_GOALS];     /* the intention on top, the commitment below */
   int              ngoals;
   uint32_t         searched[ BG_MAX_SEARCHED];
   int              nsearched;
   uint64_t         decisions;
   BOOL             waiting;
   NSMutableArray   *log;
}
@end


@interface BGAgency : NSObject <BGDecisionPhase, BGSavedSystem>
{
   BGWorld          *_world;
   BGCommitter      *_committer;       /* not retained */
   BGKnowledge      *_knowledge;
   NSMutableArray   *_minds;           /* sorted by agent */
}

- (id) initWithWorld:(BGWorld *) world
           committer:(BGCommitter *) committer
           knowledge:(BGKnowledge *) knowledge;

/* Agency takes the agent over, committed to wedging the lock. */
- (void) commitToWedging:(BGEntityID) agent;

- (BGMotivation *) mindOf:(BGEntityID) agent;
/* the agent's decision log, for the developer */
- (NSArray *) logOf:(BGEntityID) agent;

@end

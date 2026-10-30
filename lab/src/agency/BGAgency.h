/*
 * BGAgency — agents that choose for themselves (AGENCY.md). In the decision
 * phase after perception, each agent agency controls, and that has no
 * activity under way, decides one step from its intention, reading only its
 * own knowledge store (the knowledge view). Everything it does is an action,
 * through the menu's machinery.
 *
 * Goals and methods are content (content/agency.tri, AGENCY.md §5). A goal
 * is done when its `done` condition holds; a condition binds slots to
 * referents the agent believes present and matches the frame they describe,
 * so nothing reads world state or truth. A method is followed when its `pre`
 * holds, its steps re-read at each decision: a subgoal not yet done is
 * adopted above the goal, which stays the intention beneath it; an operation
 * is performed once the agent has walked within reach of what it names. A
 * goal no method can serve is impossible for now: it is dropped, with the
 * reason, and the method that needed it has failed, so the goal beneath
 * tries its next.
 *
 * Each agent's motivation store (its intentions, with their bindings and
 * failed methods, and the decision count) is private and saved, and every
 * decision is logged for the developer.
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGCommitter.h"
#import "BGScheduler.h"
#import "BGKnowledge.h"


#define BG_MAX_INTENTIONS  8
#define BG_MAX_SLOTS       8


typedef struct
{
   const char   *slot;           /* interned */
   uint32_t     referent;
} BGSlotBinding;


/* A goal adopted: the commitment at the bottom of the stack, a subgoal above
 * the goal whose method needed it. */
typedef struct
{
   const char      *goal;        /* interned: the goal's instance name */
   int64_t         adopted;      /* ms */
   uint32_t        failed;       /* the goal's methods that failed since, by rank order */
   int             pending;      /* the method whose subgoal is above, or -1 */
   int             following;    /* the method last followed, or -1 */
   BGSlotBinding   params[ BG_MAX_SLOTS];
   int             nparams;
} BGIntention;


@interface BGMotivation : NSObject
{
@public
   BGEntityID       agent;
   BGIntention      intentions[ BG_MAX_INTENTIONS];     /* the commitment first, the current intention last */
   int              nintentions;
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

/* Agency takes the agent over, committed to the goal (a #Goal instance).
 * NO if content has no such goal. */
- (BOOL) commit:(BGEntityID) agent
         toGoal:(const char *) goal;

- (BGMotivation *) mindOf:(BGEntityID) agent;
/* the agent's decision log, for the developer */
- (NSArray *) logOf:(BGEntityID) agent;

@end

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
 * A step can say something (talk.tri): after a question, the agent waits
 * for the one it asked to answer, a while at most, and a search slot passes
 * over whoever it has asked since adopting the goal.
 *
 * Being asked is a candidate goal (AGENCY.md §4's social generator, §11),
 * considered at every decision point: answering is worth the agent's trust
 * in the asker, plus its `helpful` disposition, less BG_BUSY_COST for each
 * point of attention its running activity demands, less BG_COMMITTED if it
 * holds a goal of its own. Worth more than nothing, it answers, from what it
 * knows: where it believes something like it is, and how it knows, or that
 * it doesn't know; asked who told it, the claim again, with its source.
 * Worth nothing only because it is busy, it answers once it isn't, if the
 * asker can still be waiting. Otherwise it says it won't.
 *
 * Goals have worth (AGENCY.md §3): their considerations, added in dB, among
 * them the credence that something is so. A goal that `arises` from a kind
 * of finding (§4's reactive generator) is a candidate for each such finding
 * the agent holds, and is weighed against what the agent is doing at every
 * decision point, mid-activity too: it wins only if it is worth more than
 * the current intention plus BG_MARGIN plus, while an activity runs,
 * BG_INTERRUPT, so the agent doesn't dither. Winning, it suspends what the
 * agent was doing and goes on top; done, the agent goes back to it, and
 * resumes the activity it suspended. A goal that arose about something is
 * settled with it, and doesn't arise about it again.
 *
 * Commitments (AGENCY.md §7, §8): an agent undertakes a goal for a window,
 * from a source (employment, a promise). While the window is open, the
 * goal is a candidate (the routine generator), worth BG_DUTY plus an
 * urgency that rises to BG_URGENCY by the deadline, weighed like any other;
 * done, or impossible, it is settled for the window; when the window closes
 * it is dropped. The scheduler wakes the agent when a window opens or
 * closes.
 *
 * Autopilot (AGENCY.md §14): the player hands their character to agency
 * with a goal and an interruption threshold. Agency decides for it from its
 * knowledge view, as for anyone, but takes up no goal of its own: when one
 * arises worth more than the threshold, or the goal is done or can't be,
 * control returns to the player, with a notice saying why.
 *
 * Each agent's motivation store (its intentions, with their bindings and
 * failed methods, what it waits for, and the decision count) is private and
 * saved, and every decision is logged for the developer.
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGCommitter.h"
#import "BGScheduler.h"
#import "BGKnowledge.h"
#import "BGActivities.h"


#define BG_MAX_INTENTIONS  8
#define BG_MAX_SLOTS       8
#define BG_MAX_QUESTIONS   8

#define BG_BUSY_COST       3      /* per point of attention the running activity demands */
#define BG_COMMITTED       5      /* for holding a goal of its own */
#define BG_MARGIN          5      /* what another goal must beat the current one by */
#define BG_INTERRUPT       5      /* and more, to interrupt an activity under way */
#define BG_MAX_SETTLED     16
#define BG_MAX_COMMITMENTS 8
#define BG_DUTY            20     /* what a commitment is worth */
#define BG_URGENCY         20     /* and more, rising toward its deadline */


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
   uint32_t        arose;        /* the referent it arose about, or 0 */
   int             commitment;   /* the commitment it keeps, + 1, or 0 */
} BGIntention;


/* A goal undertaken for a window (AGENCY.md §7). */
typedef struct
{
   const char      *goal;        /* interned */
   int64_t         from;         /* ms */
   int64_t         until;        /* ms: its deadline */
   const char      *source;      /* interned: "employment", "promise", "self" */
   BOOL            settled;      /* done, or given up, for this window */
} BGCommitment;


/* A goal that arose about something: settled, or last weighed. */
typedef struct
{
   const char      *goal;        /* interned */
   uint32_t        about;        /* referent */
   int             verdict;      /* weighed: 1 switch, 0 stay */
} BGArisen;


/* A question put to the agent, not yet answered. */
typedef struct
{
   uint32_t         asker;         /* referent */
   const char       *content;      /* interned */
   int64_t          heard;         /* ms */
   BOOL             deferred;      /* "not now" is logged */
} BGQuestion;


@interface BGMotivation : NSObject
{
@public
   BGEntityID       agent;
   BGIntention      intentions[ BG_MAX_INTENTIONS];     /* the commitment first, the current intention last */
   int              nintentions;
   uint64_t         decisions;
   BOOL             waiting;
   uint32_t         awaiting;          /* the referent a question was put to, while it waits for the answer */
   int64_t          awaitSince;        /* ms */
   int64_t          awaitUntil;        /* ms: then it stops waiting */
   uint64_t         heard;             /* the serial of the first observation it has not yet considered for questions */
   BGQuestion       questions[ BG_MAX_QUESTIONS];
   int              nquestions;
   BGArisen         settled[ BG_MAX_SETTLED];
   int              nsettled;
   BGArisen         weighed[ BG_MAX_SETTLED];  /* the last verdict, so it is logged when it changes */
   int              nweighed;
   BGCommitment     commitments[ BG_MAX_COMMITMENTS];
   int              ncommitments;
   BOOL             autopilot;         /* the player's character, handed over */
   int32_t          threshold;         /* worth above which control returns */
   BOOL             handedBack;
   NSMutableArray   *log;
}
@end


@interface BGAgency : NSObject <BGDecisionPhase, BGSavedSystem, BGConcerns>
{
   BGWorld          *_world;
   BGCommitter      *_committer;       /* not retained */
   BGKnowledge      *_knowledge;
   BGActivities     *_activities;      /* not retained: to suspend and resume the agents' own */
   NSMutableArray   *_minds;           /* sorted by agent */
   NSMutableArray   *_notices;         /* control returned, for the player */
   NSMutableArray   *_former;          /* pairs: an agent let go, its log */
}

- (id) initWithWorld:(BGWorld *) world
           committer:(BGCommitter *) committer
           knowledge:(BGKnowledge *) knowledge;

/* Agency takes the agent over, with nothing to do but answer when it is
 * asked something. */
- (void) control:(BGEntityID) agent;

/* Agency takes the agent over, committed to the goal (a #Goal instance).
 * NO if content has no such goal. */
- (BOOL) commit:(BGEntityID) agent
         toGoal:(const char *) goal;

/* Agency takes the agent over, if it hasn't, and the agent undertakes the
 * goal for the window [from, until), from the source. NO if content has no
 * such goal. */
- (BOOL) undertake:(BGEntityID) agent
              goal:(const char *) goal
              from:(int64_t) from
             until:(int64_t) until
            source:(const char *) source;

/* Agency lets the agent go, its mind with it: someone else controls it. */
- (void) relinquish:(BGEntityID) agent;
- (BOOL) controls:(BGEntityID) agent;

/* Autopilot: agency takes the player's character, committed to the goal,
 * until something arises worth more than `threshold`, or the goal is done
 * or impossible. NO if content has no such goal. */
- (BOOL) autopilot:(BGEntityID) agent
            toGoal:(const char *) goal
         threshold:(int32_t) threshold;
/* why control returned since last asked, one line each */
- (NSArray *) takeNotices;

/* Lets agency suspend and resume its agents' activities. */
- (void) setActivities:(BGActivities *) activities;

- (BGMotivation *) mindOf:(BGEntityID) agent;
/* the agent's decision log, for the developer; kept when agency lets it go */
- (NSArray *) logOf:(BGEntityID) agent;

@end

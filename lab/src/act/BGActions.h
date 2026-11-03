/*
 * The action menu and performing actions (ACTIONS.md §1–4). Operations are
 * content: instances of #Operation in the "operations" family. An actor's
 * menu lists each operation and binding of its roles to entities in reach
 * whose match against their descriptions is not incompatible; unknown never
 * excludes. Performing an action checks it is on the menu, then runs the
 * operation's effect, which builds the proposal group commitment applies.
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGCommitter.h"


typedef enum
{
   BGRoleActor = 0,
   BGRoleItem,
   BGRoleDestination,
   BGRoleCount
} BGRole;

extern const char   *BGRoleNames[ BGRoleCount];

typedef struct
{
   const char   *operation;              /* interned */
   BGEntityID   roles[ BGRoleCount];     /* BGNoEntity for a role the operation doesn't have */
   const char   *content;                /* interned: what is said, for say; or NULL */
} BGAction;

static inline BGAction   BGActionMake( const char *operation, BGEntityID actor, BGEntityID item, BGEntityID destination)
{
   BGAction   a;

   a.operation                   = operation;
   a.roles[ BGRoleActor]         = actor;
   a.roles[ BGRoleItem]          = item;
   a.roles[ BGRoleDestination]   = destination;
   a.content                     = NULL;
   return( a);
}


@class BGKnowledgeStore;

@interface BGMenu : NSObject
{
   BGAction         *_items;
   TriMatch         *_matches;
   int32_t          *_masses;       /* the credence mass that entails, in thousandths */
   NSMutableArray   *_residuals;
   BOOL             _believed;
   NSUInteger       _count;
   NSUInteger       _capacity;
}

/* sorted by operation name, then by the bound entities */
+ (instancetype) menuFor:(BGEntityID) actor
                   world:(BGWorld *) world;
/* The knowledge view's menu (KNOWLEDGE.md §13): built from the actor's
 * store, its roles bound to referents (R1, R2, ...) believed present and in
 * reach, described as the actor last perceived them. It can offer what is
 * no longer so. */
+ (instancetype) menuFor:(BGKnowledgeStore *) store
                   world:(BGWorld *) world
                 believed:(BOOL) believed;

- (NSUInteger) count;
/* YES for a knowledge view's menu: its roles are referents */
- (BOOL) believed;
- (const BGAction *) actionAt:(NSUInteger) i;
- (TriMatch) matchAt:(NSUInteger) i;
/* what the actor would have to find out, for an unknown match */
- (NSArray *) residualsAt:(NSUInteger) i;
/* "take item 2: entailed" */
- (NSString *) describeAt:(NSUInteger) i;

@end


/* The match of one action from its actor's view. Incompatible, with the
 * reason, when the operation is unknown, a role is missing or out of reach,
 * or the descriptions rule it out. */
TriMatch           BGMatchAction( BGWorld *world, BGAction action, TriMatchResult *result, NSString **reason);

/* Performs an action: if it is on the actor's menu, submits a group (phase
 * action) for the next boundary. An instant operation's group carries its
 * effect. One with a duration starts a timed activity, whose effect commits
 * when it is due; fill starts an activity that ends by a watch or an event
 * (BGActivities). `amount` is the command's parameter: how many, for
 * take_some; how many millilitres, for fill. nil, with the reason, if it
 * can't be attempted. */
BGProposalGroup    *BGPerform( BGWorld *world, BGCommitter *committer, BGAction action, int64_t amount,
                               NSString **error);

/* The match of an action whose roles are the actor's referents, from what
 * its store says; incompatible when a referent is not believed present and
 * in reach. */
TriMatch           BGMatchBelieved( BGWorld *world, BGKnowledgeStore *store, BGAction action,
                                    TriMatchResult *result, NSString **reason);

/* Performs an action chosen from the knowledge view: it must be on the
 * actor's believed menu. The world's side then resolves the referents to the
 * entities they track; if the world rules the action out (the thing isn't
 * there any more), what commits is the attempt (an "attempted" event, the
 * actor reaching where it believed the thing was), and perception corrects
 * the belief. */
BGProposalGroup    *BGPerformBelieved( BGWorld *world, BGCommitter *committer, BGKnowledgeStore *store,
                                       BGAction action, int64_t amount, NSString **error);

/* An operation's effect, as proposals added to `group`: what an instant
 * action commits, and what a timed activity commits when it is due. The
 * reason if it can't be built. */
NSString           *BGApplyEffect( BGWorld *world, BGAction action, int64_t amount, BGProposalGroup *group);

/* The operation's effect name, and its duration in ms (0 if it has none). */
NSString           *BGOperationEffect( BGWorld *world, const char *operation);
int64_t            BGOperationDuration( BGWorld *world, const char *operation);

/* How fast the actor works now at stage `index` of the operation, in
 * percent of its declared pace (ACTIONS.md §5's rate = f(capabilities,
 * shortfall, actor modifiers)). Provisional, until the document's open
 * question 4 settles f: modifiers only, and only for a stage that takes
 * effort (its `exertion`); fatigue and injury slow it, 200 / (200 +
 * fatigue + injury): half again as long at 100 of them together. Resting,
 * waiting, talking go at their pace. */
int64_t            BGWorkRate( BGWorld *world, BGEntityID actor, const char *operation, int64_t index);
/* A stage's effort in ms of the declared pace, at `rate`: as long, in ms. */
static inline int64_t   BGAtRate( int64_t effort, int64_t rate)
{
   return( rate > 0 && rate < 100 ? (effort * 100 + rate - 1) / rate : effort);
}

/* What it costs in time to bring the instruments the action will use to
 * bear (ACTIONS.md §2's access cost): take_up's duration for each one
 * on a tile in reach, twice that from a container; added to the first
 * stage. 0 for an action that searches for none. Saying an account takes
 * its duration again for each claim after the first (ACTIONS.md decision
 * 14), added the same way. */
int64_t            BGAccessDelay( BGWorld *world, BGAction action);

/* A curve's value at x (AGENCY.md §3's lookup tables, ACTIONS.md decision
 * 11): its points' `output` at their `input`, straight between them and
 * level beyond the ends. NO if it has no points. */
BOOL               BGCurveAt( TriContent *tri, const TriNode *curve, int64_t x, int32_t *out);

/* A graded requirement (ACTIONS.md decision 11): what the operation's
 * offering role brings, as a percent of what its demanding role demands;
 * -1 if it has none, or either can't be read. */
int64_t            BGCapacity( BGWorld *world, BGAction action);
/* The work rate, slowed by the graded requirement's `slowing` curve. */
int64_t            BGGradedRate( BGWorld *world, BGAction action, int64_t rate);

/* What weights the actor's groups for the operation when they conflict
 * (ACTIONS.md decision 13): its value of the field the operation declares
 * (`contest`, an Agent field: "quickness"); 0 if it declares none. */
uint64_t           BGContestWeight( BGWorld *world, BGEntityID actor, const char *operation);

/* Stage `index` of an operation: its duration and effect. An operation with
 * a duration and no stages has one stage. NO past the last stage. */
BOOL               BGOperationStage( BGWorld *world, const char *operation, int64_t index,
                                     int64_t *duration, NSString **effect);
/* Stage `index`'s partial effect (ACTIONS.md §5): the field, the role it
 * shows on (BGRoleItem or BGRoleDestination), the whole it reaches, and its
 * checkpoints. NO if it declares none. */
BOOL               BGOperationPartial( BGWorld *world, const char *operation, int64_t index,
                                       const char **field, int *role, int64_t *whole, int64_t *checkpoints);
/* Whether stage `index` fails on a hard interruption, rather than being
 * suspended. */
BOOL               BGOperationFailsHard( BGWorld *world, const char *operation, int64_t index);
/* The fatigue stage `index` adds to its actor when it completes. */
int64_t            BGOperationExertion( BGWorld *world, const char *operation, int64_t index);

/* Why the actor can't start (or resume) an activity of `operation` now: a
 * running activity of its, other than `except`, uses a provider this one
 * needs (ACTIONS.md §5: an actor runs two activities at once only if they
 * use different providers). nil when it can. */
NSString           *BGProvidersBusy( BGWorld *world, BGEntityID actor, const char *operation, BGEntityID except);

/* The traces the operation declares (KNOWLEDGE.md §3,
 * content/traces/traces.tri), as proposals added to `group`: those it removes
 * destroyed, those it leaves created, made now and running out after their
 * kind's `lasts`. Called with its effect, when an instant action is performed
 * or an activity completes. */
void               BGLeaveTraces( BGWorld *world, BGAction action, BGProposalGroup *group);
/* The traces stage `index` of a staged operation declares, in its group. */
void               BGLeaveStageTraces( BGWorld *world, BGAction action, int64_t index, BGProposalGroup *group);

/* The region of air (a GasStore) over the entity's tile, or 0. */
BGEntityID         BGAirOver( BGWorld *world, BGEntityID e);
/* Authority (COMPONENTS.md Scenario 2): the authorizations over an entity, as
 * entity IDs in NSNumbers; and whether any authorization links to content. */
NSArray            *BGAuthorizationsOver( BGWorld *world, BGEntityID entity);
/* Claims (COMPONENTS.md Scenario 3): those covering an entity, as entity IDs
 * in NSNumbers; and whether its ownership is an open question. */
NSArray            *BGClaimsCovering( BGWorld *world, BGEntityID entity);
BOOL               BGOwnershipOpen( BGWorld *world, BGEntityID entity);
BOOL               BGContentAuthorizes( BGWorld *world, BGEntityID content);
/* ACTIONS.md §3's authorize(action): the authorizations granting the actor
 * something over what the action binds. Never blocks an attempt. */
NSArray            *BGAuthorize( BGWorld *world, BGAction action);
/* The laws the action breaks (INSTITUTIONS.md decision 2), as entity IDs in
 * NSNumbers: true, for the inspector and for those who act on it; nothing
 * blocks it. A law forbids its effect when the act is its kind of wrong:
 * "anothers", the item claimed (owned or held in custody) by someone else
 * and no authorization of the actor over it; "unauthorized", no
 * authorization over what it binds. */
NSArray            *BGLawsBroken( BGWorld *world, BGAction action);
/* Whether someone other than `who` claims it (ownership or custody). */
BOOL               BGClaimedByAnother( BGWorld *world, BGEntityID entity, BGEntityID who);
/* A trace of `kind` (content/traces/traces.tri) on the bearer, or on the
 * tile if none, at `strength`, made in the group; `by` says what left it. */
void               BGMakeTrace( BGWorld *world, BGProposalGroup *group, const char *kind, BGEntityID bearer,
                                BGLocation tile, int64_t strength, const char *by);

/* A named effect, as proposals added to `group`. */
NSString           *BGApplyNamedEffect( BGWorld *world, NSString *effect, BGAction action, int64_t amount,
                                        BGProposalGroup *group);

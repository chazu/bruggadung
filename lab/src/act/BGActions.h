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
} BGAction;

static inline BGAction   BGActionMake( const char *operation, BGEntityID actor, BGEntityID item, BGEntityID destination)
{
   BGAction   a;

   a.operation                   = operation;
   a.roles[ BGRoleActor]         = actor;
   a.roles[ BGRoleItem]          = item;
   a.roles[ BGRoleDestination]   = destination;
   return( a);
}


@class BGKnowledgeStore;

@interface BGMenu : NSObject
{
   BGAction         *_items;
   TriMatch         *_matches;
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

/* Stage `index` of an operation: its duration and effect. An operation with
 * a duration and no stages has one stage. NO past the last stage. */
BOOL               BGOperationStage( BGWorld *world, const char *operation, int64_t index,
                                     int64_t *duration, NSString **effect);

/* A named effect, as proposals added to `group`. */
NSString           *BGApplyNamedEffect( BGWorld *world, NSString *effect, BGAction action, int64_t amount,
                                        BGProposalGroup *group);

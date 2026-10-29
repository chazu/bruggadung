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


@interface BGMenu : NSObject
{
   BGAction         *_items;
   TriMatch         *_matches;
   NSMutableArray   *_residuals;
   NSUInteger       _count;
   NSUInteger       _capacity;
}

/* sorted by operation name, then by the bound entities */
+ (instancetype) menuFor:(BGEntityID) actor
                   world:(BGWorld *) world;

- (NSUInteger) count;
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

/* Performs an action: if it is on the actor's menu, builds its effect's
 * group (phase action) and submits it for the next boundary. `amount` is the
 * command's parameter (how many, for take_some). nil, with the reason, if it
 * can't be attempted. */
BGProposalGroup    *BGPerform( BGWorld *world, BGCommitter *committer, BGAction action, int64_t amount,
                               NSString **error);

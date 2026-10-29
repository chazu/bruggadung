/*
 * BGPlay — an interactive session on one of the laboratory's worlds: the
 * command interface, the text map, and the developer inspector of DESIGN.md's
 * laboratory. A person (or a script) controls one agent:
 *
 *   look                  the map around the actor, and what it can see
 *   menu                  the actor's menu, numbered
 *   do <n> [amount]       perform menu entry n, now
 *   walk n|s|e|w          walk one tile
 *   wait <ms>             let time pass
 *   step                  run to the next boundary
 *   idle                  run until the actor has no activity under way
 *   as <id>               control another agent
 *   activities            the actor's activities, with their stages
 *   suspend <id>, resume <id>
 *                         the actor's choice: suspend keeps the progress
 *   inspect <id>          the developer's view of an entity: truth,
 *                         relations, activities, history
 *   why <id>              what last changed it, and the chain of causes
 *   trace [n]             the last n lines of the commit trace
 *   save <file>, load <file>
 *   time, hash, help, quit
 *
 * Every command is deterministic given the world, so the commands typed are
 * the session's replay log: feeding them back reproduces it exactly.
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGCommitter.h"
#import "BGScheduler.h"
#import "BGFluidDomain.h"
#import "BGActivities.h"
#import "BGActions.h"


@interface BGPlay : NSObject <BGInputSource>
{
   NSString         *_name;
   BGWorld          *_world;
   BGCommitter      *_committer;
   BGScheduler      *_scheduler;
   BGFluidDomain    *_fluid;
   BGActivities     *_activities;
   BGMenu           *_menu;
   BGEntityID       _actor;
   NSMutableString  *_out;
   BOOL             _inputDue;
   NSUInteger       _traceShown;
}

/* "workshop" or "cistern"; nil, with the reason, for another name */
+ (instancetype) playWorld:(NSString *) name
                      seed:(uint64_t) seed
                     error:(NSString **) error;

- (BGWorld *) world;
- (BGEntityID) actor;

/* Runs one command line. NO when it was quit. */
- (BOOL) command:(NSString *) line;
/* What the commands printed since the last call. */
- (NSString *) takeOutput;

@end

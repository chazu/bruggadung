/*
 * BGPlay — an interactive session on one of the laboratory's worlds: the
 * command interface, the text map, and the developer inspector of DESIGN.md's
 * laboratory. A person (or a script) controls one agent:
 *
 *   look                  the map as the actor knows it: what it sees now,
 *                         and what it remembers, with the memory's age
 *   menu                  the actor's menu, from what it knows, numbered
 *   do <n> [amount]       perform menu entry n, now
 *   walk n|s|e|w          walk one tile
 *   wait <ms>             let time pass
 *   step                  run to the next boundary
 *   idle                  run until the actor has no activity under way
 *   ask <R> where <R>     ask someone in reach where something like it is
 *   ask <R> who <R>       ask someone who told them where it is
 *   tell <R> <R> [in <R>] tell someone where something is, as you believe;
 *                         in a container you don't believe it is in: a lie
 *   notebook              what the actor knows, as it knows it: what it
 *                         remembers where, what it was told and how much
 *                         it believes it, open questions, findings, traces
 *   write <R>             write where something is into a notebook held
 *   read <R>              read a record in reach
 *   note <text>, notes    the player's own notes, out of character: they
 *                         never reach the actor's knowledge
 *   as <id>               control another agent; agency answers for the
 *                         others when they are asked
 *   activities            the actor's activities, with their stages
 *   suspend <id>, resume <id>
 *                         the actor's choice: suspend keeps the progress
 *   knows [id]            the developer's view of an agent's knowledge store
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
#import "BGTraces.h"
#import "BGActivities.h"
#import "BGActions.h"
#import "BGKnowledge.h"
#import "BGAgency.h"


@interface BGPlay : NSObject <BGInputSource>
{
   NSString         *_name;
   BGWorld          *_world;
   BGCommitter      *_committer;
   BGScheduler      *_scheduler;
   BGFluidDomain    *_fluid;
   BGTraces         *_traces;
   BGActivities     *_activities;
   BGKnowledge      *_knowledge;
   BGAgency         *_agency;
   BGMenu           *_menu;
   BGEntityID       _actor;
   NSMutableString  *_out;
   NSMutableArray   *_notes;            /* the player's, out of character */
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

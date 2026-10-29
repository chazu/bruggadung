/*
 * BGCommitter — change commitment (ACTIONS.md §8–11), the only writer of
 * world state. At each boundary it orders the submitted groups by phase and
 * a seeded permutation, rewrites each for automatic individuation, applies it
 * against the state the earlier groups left, validates the result, and keeps
 * it or rolls it back with a reason. Applied groups allocate IDs in order and
 * emit committed events; components react to those, and their groups form
 * the next round, up to a bound. What is left is deferred to the next
 * boundary.
 */
#import "BGTypes.h"

#import "BGWorld.h"
#import "BGProposalGroup.h"


@class BGCommitter;

/* A component kind's behaviour on the reactions channel: it is told of each
 * committed event whose subject has its component, and may submit groups. */
@protocol BGReactor

- (void) committer:(BGCommitter *) committer
     reactToEvent:(const BGEvent *) event
            world:(BGWorld *) world;

@end


/* Engine machinery told after each round, before the reactions run: the
 * activity system rechecks the activities bound to what changed (ACTIONS.md
 * §5). It may submit groups, which join the next round. */
@protocol BGRoundListener

- (void) committer:(BGCommitter *) committer
    didCommitRound:(uint32_t) round
        eventsFrom:(NSUInteger) first
                to:(NSUInteger) last;

@end


@interface BGCommitter : NSObject
{
   BGWorld          *_world;
   NSMutableArray   *_submitted;
   NSMutableArray   *_deferred;
   NSMutableArray   *_reactors;        /* pairs: kind index, reactor */
   NSMutableArray   *_listeners;
   NSMutableDictionary   *_sources;     /* commit position → the group's source */
   NSMutableArray   *_trace;
   NSUInteger       _rounds;
   uint64_t         _position;
   uint32_t         _round;
}

- (id) initWithWorld:(BGWorld *) world;

- (BGWorld *) world;
- (void) setRounds:(NSUInteger) rounds;        /* R; 4 by default */
- (void) addReactor:(id <BGReactor>) reactor
            forKind:(const char *) kind;

/* retained: a listener must not retain the committer */
- (void) addListener:(id <BGRoundListener>) listener;
- (void) submit:(BGProposalGroup *) group;
- (BOOL) hasPending;

/* Commits everything submitted for the world's current boundary. Returns the
 * groups processed, in order, each marked applied or rejected. */
- (NSArray *) commitBoundary;

/* Saved state: the last commit position, and the groups deferred to the
 * next boundary. */
- (uint64_t) position;
/* the source of the group committed at a position, if this committer did it */
- (NSString *) sourceOfPosition:(uint64_t) position;
- (void) setPosition:(uint64_t) position;
- (NSArray *) deferredGroups;
- (void) restoreDeferred:(NSArray *) groups;

/* One line per group, rejection, event, and deferral, for the developer. */
- (NSArray *) trace;
- (void) note:(NSString *) line;

@end

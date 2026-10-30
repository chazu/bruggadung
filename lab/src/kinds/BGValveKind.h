/*
 * BGValveKind — how a valve answers (ACTIONS.md Scenario 1): an effect
 * commits the torque applied to it, with no success flag, and the valve, by
 * its hidden breakaway, turns or holds. A blow loosens what has seized.
 * Every attempt is recorded for the developer: the torque, the breakaway,
 * what the turner expected, and what happened.
 */
#import "BGCommitter.h"


@interface BGValveKind : NSObject <BGReactor>
@end

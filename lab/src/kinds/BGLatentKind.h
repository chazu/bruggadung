/*
 * BGLatentKind — what extracting a part does to its assembly
 * (DOMAIN_SIMULATION.md Scenario 2, provisional with content/latent.tri):
 * when the part whose role the descriptor names (`pathWhenOut`) is out of
 * the assembly, a path opens from the store the assembly holds back (its
 * `riser`) to its floor, through the part `pathThrough` names; it passes in
 * proportion to that part's wear past half. A leak, a tap installed in the
 * store, is the path: the fluid domain drains it, a topology change.
 */
#import "BGCommitter.h"


@interface BGLatentKind : NSObject <BGReactor>
@end

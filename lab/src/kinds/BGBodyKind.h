/*
 * BGBodyKind — behaviour of the Body component. On the reactions channel:
 * a unit put into a container that holds a stack of the same unit proposes
 * to merge into it. Whether the units are indistinguishable is commitment's
 * to decide; a refusal is traced with its reason.
 */
#import "BGCommitter.h"


@interface BGBodyKind : NSObject <BGReactor>
@end

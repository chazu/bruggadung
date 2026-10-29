/*
 * BGView — what an actor can bind and what it can tell about each entity:
 * the stub of the knowledge view (ACTIONS.md §3, KNOWLEDGE.md §13) until
 * perception exists. It is the truth projection, limited the way the menu
 * contract requires:
 *
 *   - formulate: only entities in reach can be bound (the actor's tile and
 *     the eight around it, and anything inside, held, or installed there)
 *   - appearsBeginnable: a description carries only fields whose @field
 *     flags say they can be perceived; hidden fields stay open, so they make
 *     a match unknown, and unknown never excludes
 */
#import "BGTypes.h"

#import "BGWorld.h"


@interface BGView : NSObject
{
   BGWorld      *_world;
   BGEntityID   _actor;
}

+ (instancetype) viewOf:(BGEntityID) actor
                inWorld:(BGWorld *) world;

- (BGEntityID) actor;
- (BOOL) canReach:(BGEntityID) entity;
/* entities in reach, the actor included, in ID order */
- (NSUInteger) reachable:(BGEntityID *) out
                     max:(NSUInteger) max;
/* the entity's description, as a Triangle expression */
- (NSString *) describeEntity:(BGEntityID) entity;
/* its parts: the kind (a type expression), and the perceivable fields
 * ("mass: 90g, material: \"iron\", ..."), without id or place */
- (NSString *) kindOf:(BGEntityID) entity;
- (NSString *) featuresOf:(BGEntityID) entity;

@end

/* The first free hand of an agent, or -1. */
int32_t   BGFreeHand( BGWorld *world, BGEntityID agent);
/* How many of an agent's hands are free. */
int32_t   BGFreeHands( BGWorld *world, BGEntityID agent);

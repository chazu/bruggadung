/*
 * BGCoupling — what passes between domains (DOMAIN_SIMULATION.md §7–8). A
 * domain reads the others' values from a snapshot taken at step start, so it
 * never sees another's mid-step state, and the order domains run in can't
 * change the result. What it gives another is a contribution: a typed,
 * additive amount, tagged with its source, which the scheduler holds in
 * transit and hands to the domain that takes it, to apply over its next step.
 */
#import "BGTypes.h"


typedef enum
{
   BGQuantityTemperature = 1,      /* mK, a value */
   BGQuantityHeat        = 2       /* J, an amount */
} BGQuantity;


typedef struct
{
   BGEntityID   target;
   BGEntityID   source;
   BGQuantity   quantity;
   int64_t      amount;
} BGContribution;


/* Values of the domains' participants, as of step start. */
@interface BGSnapshot : NSObject
{
   BGEntityID   *_entities;
   BGQuantity   *_quantities;
   int64_t      *_values;
   NSUInteger   _count;
   NSUInteger   _size;
}

- (void) setQuantity:(BGQuantity) quantity
                  of:(BGEntityID) entity
                  to:(int64_t) value;
/* NO when no domain published it */
- (BOOL) quantity:(BGQuantity) quantity
               of:(BGEntityID) entity
            value:(int64_t *) value;

@end


/* A step's contributions, in the order they were made. */
@interface BGContributions : NSObject
{
   BGContribution   *_items;
   NSUInteger       _count;
   NSUInteger       _size;
}

- (void) addContribution:(BGContribution) contribution;
- (NSUInteger) count;
- (BGContribution) contributionAtIndex:(NSUInteger) i;

@end

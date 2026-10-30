/*
 * BGBodies — body stocks (AGENCY.md §6): how fed an agent is. The stock is
 * component state, `Agent.fed` as of `Agent.fedAt`, and falls a point every
 * three minutes, computed when read; eating sets it again. Nothing is computed
 * between: the domain's horizon is the next time anyone's hunger crosses
 * into another band of ten, so the agent's interoception, and the needs it
 * feels, are refreshed there.
 */
#import "BGScheduler.h"


#define BG_HUNGER_PERIOD   180000     /* ms a point of `fed` lasts: empty in five hours */
#define BG_HUNGER_BAND     10         /* the precision hunger is felt with */


/* How fed the agent is at t, 0 to 100. */
int64_t   BGSatiety( const BGAgent *agent, int64_t t);


@interface BGBodies : NSObject <BGDomain>
{
   BGWorld   *_world;
}

- (id) initWithWorld:(BGWorld *) world;

@end

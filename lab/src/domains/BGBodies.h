/*
 * BGBodies — body stocks (AGENCY.md §6): how fed an agent is. The stock is
 * component state, `Agent.fed` as of `Agent.fedAt`, and falls a point every
 * three minutes, computed when read; eating sets it again. Nothing is computed
 * between: the domain's horizon is the next time anyone's hunger crosses
 * into another band of ten, so the agent's interoception, and the needs it
 * feels, are refreshed there.
 *
 * Going without harms the body (AGENCY.md decision 17): an agent starving
 * (hunger BG_STARVING or more), freezing (cold BG_FREEZING), or smothering
 * (short of breath BG_SMOTHERING) takes a point of harm every period of the
 * stock's (hunger slowly, cold faster, air fastest), at each multiple of it:
 * fatigue up to BG_WEARY, then injury. World state, as the body is, not as
 * it is felt; the domain's horizon is the next such point.
 */
#import "BGScheduler.h"


#define BG_HUNGER_PERIOD   180000     /* ms a point of `fed` lasts: empty in five hours */
#define BG_HUNGER_BAND     10         /* the precision hunger is felt with */


#define BG_STARVING        90         /* hunger that harms: fed 10 or less */
#define BG_FREEZING        50         /* cold that harms: 5 K below 310 K */
#define BG_SMOTHERING      50         /* shortness of breath that harms: 0.6% carbon dioxide */
#define BG_STARVE_PERIOD   600000     /* ms a point of harm from starving */
#define BG_FREEZE_PERIOD   60000      /* ... from freezing */
#define BG_SMOTHER_PERIOD  10000      /* ... from smothering */
#define BG_WEARY           50         /* the fatigue going without adds, before it injures */


/* How fed the agent is at t, 0 to 100. */
int64_t   BGSatiety( const BGAgent *agent, int64_t t);
/* How cold its body is, 0 to 100: ten points a kelvin below 310 K. */
int64_t   BGColdness( BGWorld *world, BGEntityID agent);
/* How short of breath the air over it makes something that breathes, 0 to
 * 100: ten points for every 0.1% of carbon dioxide above 0.1%. */
int64_t   BGBreathlessness( BGWorld *world, BGEntityID agent);


@interface BGBodies : NSObject <BGDomain>
{
   BGWorld   *_world;
}

- (id) initWithWorld:(BGWorld *) world;

@end

/*
 * BGLight — light as a domain (KNOWLEDGE.md decision 14), giving perception
 * its conditions (§5). Daylight follows the clock: day from `dawn` to
 * `nightfall` (content/light/light.tri's `daylight`), twilight `twilight`
 * either side, night between. Indoors, in a room with air (content/air/air.tri)
 * none of whose doorways stands open, it is a step darker.
 * A lamp shining lights its `reach`, burning its oil down as it does (as
 * of `oilAt`, computed when read); spent, it goes out. A lit fire glows a
 * tile round. Nothing is stepped between: the horizon is the next change
 * of the daylight, or the next lamp to burn out.
 */
#import "BGScheduler.h"


/* The light at a tile at t: 2 day, 1 dusk, 0 night. */
int   BGLightAt( BGWorld *world, BGLocation tile, int64_t t);
/* Daylight outdoors at t: 2 day, 1 twilight, 0 night. */
int   BGDaylight( BGWorld *world, int64_t t);
/* What oil a lamp has left to burn at t (ms). */
int64_t   BGLampOil( const BGLamp *lamp, int64_t t);


@interface BGLight : NSObject <BGDomain>
{
   BGWorld   *_world;
}

- (id) initWithWorld:(BGWorld *) world;

@end

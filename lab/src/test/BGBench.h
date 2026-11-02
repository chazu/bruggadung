/*
 * BGBench — measuring the simulation at scale (REALITY.md, step 1): a crowd
 * on a yard, run for a while, and where the time went.
 */
#import "BGTypes.h"


/* `agents` on yard_map (96 x 64), every other one exploring, the rest idle
 * with minds of their own; run for `seconds` of the world's time. Prints
 * boundaries, perceptions and decisions, and the wall time of each phase.
 * Returns 0. */
int   BGBenchCrowd( int agents, int64_t seconds);
/* The same, spread: on plain_map (1024 x 1024), ten tiles apart, so each
 * has as many near it however many there are. */
int   BGBenchCrowdSpread( int agents, int64_t seconds, BOOL spread, BOOL anchored);

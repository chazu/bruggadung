/*
 * BGPath — finding a way over tiles (TERRAIN.md, pathfinding): a search
 * from a tile, by steps north, south, east and west, over the tiles a
 * caller lets through, for a tile it is looking for. Bounded: it expands at
 * most a budget of tiles, so its cost is the same in any size of world.
 * With a target, it is A*, the steps still to go reckoned to the target's
 * reach (a tile beside it, corners too); without, it is breadth-first,
 * nearest first. Plain C; its buffers are kept between searches, so it is
 * not for more than one thread.
 */
#import "BGTypes.h"


#define BG_PATH_BUDGET   4096        /* tiles a search expands, at most */

typedef enum
{
   BGStepNone  = -1,
   BGStepNorth = 0,
   BGStepSouth,
   BGStepEast,
   BGStepWest
} BGStep;

typedef struct
{
   int32_t   x;                      /* where it starts */
   int32_t   y;
   BOOL      targeted;               /* toward (tx, ty): done within a step of it */
   int32_t   tx;
   int32_t   ty;
   NSUInteger budget;                /* 0: BG_PATH_BUDGET */
   void      *context;
   BOOL      (*passable)( void *context, int32_t x, int32_t y);
   BOOL      (*goal)( void *context, int32_t x, int32_t y);    /* untargeted: what it looks for */
} BGPathQuery;

typedef struct
{
   BGStep    step;                   /* the first step; none if it is there, or nothing was found */
   BOOL      found;                  /* a way all the way */
   int32_t   x;                      /* where the way it took ends */
   int32_t   y;
   int64_t   steps;                  /* how many to there */
   NSUInteger expanded;
} BGPathResult;

/* Searches. Targeted and not found within the budget, the first step is
 * toward the tile it reached nearest the target; untargeted, none. The
 * start need not be passable. Ties go to the order north, south, east,
 * west, after the steps nearer the target. */
BGPathResult   BGPathFind( const BGPathQuery *q);

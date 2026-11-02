/*
 * BGTerrain — what each tile at each level is (TERRAIN.md): a terrain kind
 * per cell, from a source (an authored map, or a plain fill), with only the
 * chunks that have changed stored. Plain C, for the loops that ask it of
 * many cells (walking, and later sight, rooms and fluids).
 */
#import "BGTypes.h"

#include "triangle.h"

#define BG_CHUNK         32               /* a chunk is BG_CHUNK x BG_CHUNK tiles of one level */
#define BG_MAX_TERRAIN   1024             /* kinds in content, at most */

typedef uint16_t   BGTerrainKind;           /* a kind's index in the world's table; 0: no tile */

typedef struct
{
   const char   *name;                       /* its content instance: "stone_wall" */
   const char   *look;                       /* its appearance key */
   BOOL         solid;                       /* nothing walks into it */
   BOOL         opaque;                      /* sight stops at it */
   BOOL         floored;                     /* something to stand on */
   BOOL         divides;                     /* a room ends here without a wall: a doorway */
} BGTerrainInfo;

typedef struct BGTerrain   BGTerrain;

/* Terrain from content's kinds (the `terrain` family) over an extent, every
 * cell the fill kind (by name; NULL: "open_floor", or else the first kind).
 * NULL, with the reason, if content has no kinds or the fill names none. */
BGTerrain       *BGTerrainNew( TriContent *tri, int32_t wide, int32_t high, int32_t levels, const char *fill,
                               char *error, size_t errlen);
/* Terrain drawn by a map in content (a #Map instance): its extent is the
 * drawing's. NULL, with the reason, if the map is malformed. */
BGTerrain       *BGTerrainFromMap( TriContent *tri, const char *map, char *error, size_t errlen);
void             BGTerrainFree( BGTerrain *t);

/* The map it came from, or NULL; its extent. */
const char      *BGTerrainMap( const BGTerrain *t);
int32_t          BGTerrainWide( const BGTerrain *t);
int32_t          BGTerrainHigh( const BGTerrain *t);
int32_t          BGTerrainLevels( const BGTerrain *t);

NSUInteger            BGTerrainKindCount( const BGTerrain *t);          /* kinds are 1 .. count */
const BGTerrainInfo  *BGTerrainKindInfo( const BGTerrain *t, BGTerrainKind k);   /* NULL for 0 or none */
BGTerrainKind         BGTerrainKindNamed( const BGTerrain *t, const char *name); /* 0 if none */

/* The kind of a cell: 0 outside the extent. */
BGTerrainKind    BGTerrainAt( const BGTerrain *t, int32_t x, int32_t y, int32_t z);
/* A kind's properties at a cell: outside the extent, solid and opaque, and
 * no floor. */
BOOL             BGTerrainSolid( const BGTerrain *t, int32_t x, int32_t y, int32_t z);
BOOL             BGTerrainOpaque( const BGTerrain *t, int32_t x, int32_t y, int32_t z);
BOOL             BGTerrainFloored( const BGTerrain *t, int32_t x, int32_t y, int32_t z);

/* Sets a cell, storing its chunk if it wasn't; the kind it was, or 0 if the
 * cell is outside the extent or the kind is none. */
BGTerrainKind    BGTerrainSet( BGTerrain *t, int32_t x, int32_t y, int32_t z, BGTerrainKind k);

/* The chunks that differ from the source, for saving: each one's corner,
 * and its cells (BG_CHUNK * BG_CHUNK, row by row; cells past the extent 0).
 * Returns how many; fills up to max. */
NSUInteger       BGTerrainChanged( const BGTerrain *t, int32_t (*corners)[ 3], NSUInteger max);
void             BGTerrainChunkCells( const BGTerrain *t, int32_t x0, int32_t y0, int32_t z, BGTerrainKind *cells);
/* What the source gives a cell, whatever has changed. */
BGTerrainKind    BGTerrainSource( const BGTerrain *t, int32_t x, int32_t y, int32_t z);
/* A hash of the terrain: its source and what has changed. */
uint64_t         BGTerrainHash( const BGTerrain *t);

/* Rooms (TERRAIN.md step 3): a cell's room, the cells of its level joined
 * side by side that are neither solid nor dividing; 0 for a cell in none (a
 * wall, a doorway, outside the extent). Numbered when first asked, and again
 * after terrain changes; a number means nothing across a change. */
uint32_t         BGTerrainRoomAt( BGTerrain *t, int32_t x, int32_t y, int32_t z);
